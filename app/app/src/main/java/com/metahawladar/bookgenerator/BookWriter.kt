package com.metahawladar.bookgenerator

import java.io.File
import org.json.JSONObject
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class BookRequest(
    val topic: String,
    val author: String,
    val fiction: Boolean,
    val chapters: Int,
    val totalWords: Int,
    val model: String,
    /** gemini | nvidia | gemini-web - see [Providers]. */
    val provider: String = Providers.GEMINI,
    val themeOverride: String? = null,
    val note: String = "",
    /** Copyright page, bio, also-by and the review request. */
    val extras: BookExtras = BookExtras(),
)

/** One problem the editor pass found. */
data class QualityIssue(
    /** 1-based chapter number, or 0 for a whole-book note. */
    val chapter: Int,
    val type: String,
    val severity: String,
    val detail: String,
    val fix: String,
) {
    val rank: Int get() = when (severity) {
        "high" -> 0
        "medium" -> 1
        else -> 2
    }
}

/** The result of the editor pass. */
data class QualityReport(
    val score: Int,
    val verdict: String,
    val strengths: List<String>,
    val issues: List<QualityIssue>,
) {
    companion object {
        fun fromJson(j: JSONObject): QualityReport {
            val issues = ArrayList<QualityIssue>()
            j.optJSONArray("issues")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    issues.add(
                        QualityIssue(
                            o.optInt("chapter", 0),
                            o.optString("type", "other"),
                            o.optString("severity", "low"),
                            o.optString("detail", ""),
                            o.optString("fix", ""),
                        )
                    )
                }
            }
            val strengths = ArrayList<String>()
            j.optJSONArray("strengths")?.let { arr ->
                for (i in 0 until arr.length()) strengths.add(arr.optString(i, ""))
            }
            return QualityReport(
                j.optInt("score", 0),
                j.optString("verdict", ""),
                strengths.filter { it.isNotBlank() },
                issues.sortedBy { it.rank },
            )
        }
    }

    fun toMarkdown(title: String): String {
        val b = StringBuilder()
            .appendLine("# Editor report - $title").appendLine()
            .appendLine("**Score:** $score/100").appendLine()
            .appendLine(verdict).appendLine()
        if (strengths.isNotEmpty()) {
            b.appendLine("## What works")
            strengths.forEach { b.appendLine("- $it") }
            b.appendLine()
        }
        b.appendLine("## Issues (${issues.size})")
        if (issues.isEmpty()) b.appendLine().appendLine("None found.")
        issues.forEach { i ->
            val where = if (i.chapter == 0) "whole book" else "chapter ${i.chapter}"
            b.appendLine()
                .appendLine("### ${i.severity.uppercase()} - ${i.type} - $where")
                .appendLine(i.detail).appendLine()
                .appendLine("**Fix:** ${i.fix}")
        }
        return b.toString()
    }
}

data class BookResult(
    /** Kept so a chapter can be rewritten or a cover reskinned later. */
    val request: BookRequest,
    val plan: BookPlan,
    val directory: File,
    val epub: File,
    val cover: File,
    val metadata: File,
    val zip: File,
    val words: Int,
    val chapters: List<WrittenChapter> = emptyList(),
    val summary: String = "",
    val coverStyle: CoverStyle = CoverStyle(),
    val report: QualityReport? = null,
    val reportFile: File? = null,
)

/** Orchestrates plan -> chapters -> cover -> EPUB -> metadata. */
class BookWriter(
    private val apiKey: String,
    private val outputRoot: File,
    /** Gemini keys used for cover artwork, even when the text provider is
     * NVIDIA. Falls back to [apiKey] when not given. */
    private val geminiKeys: String = apiKey,
) {

    companion object {
        /** Zips several finished books into one archive, for batch runs. */
        fun packBatch(results: List<BookResult>, outputRoot: File): File {
            val stamp = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
                .format(java.util.Date())
            val out = File(outputRoot, "batch-$stamp-${results.size}-books.zip")
            ZipOutputStream(out.outputStream().buffered()).use { zos ->
                for (r in results) {
                    val dir = r.directory
                    if (!dir.isDirectory) continue
                    dir.walkTopDown()
                        .filter { it.isFile && !it.name.endsWith(".zip", true) }
                        .sortedBy { it.path }
                        .forEach { f ->
                            val rel = f.relativeTo(dir).path.replace('\\', '/')
                            zos.putNextEntry(ZipEntry("${dir.name}/$rel"))
                            f.inputStream().use { it.copyTo(zos) }
                            zos.closeEntry()
                        }
                }
            }
            return out
        }
    }

    @Volatile
    private var cancelled = false

    fun cancel() { cancelled = true }

    private fun checkCancelled() {
        if (cancelled) throw CancellationRequested()
    }

    class CancellationRequested : RuntimeException("Cancelled")

    suspend fun run(req: BookRequest, progress: (Float, String) -> Unit): BookResult {
        val gemini = Providers.client(req.provider, apiKey, req.model)

        progress(0.02f, "Planning the book...")
        val planJson = gemini.generateJson(
            Prompts.plan(req.topic, req.fiction, req.chapters, req.totalWords, req.author, req.note),
            system = Prompts.PLAN_SYSTEM,
            temperature = 0.95,
            thinking = 4096,
            log = { progress(0.02f, it) },
        )
        checkCancelled()

        val plan = BookPlan.fromJson(planJson, req.author, req.fiction)
        if (plan.chapters.isEmpty()) {
            throw GeminiException("The planner returned no chapters. Try again.")
        }

        val dir = File(outputRoot, plan.slug).apply { mkdirs() }
        File(dir, "plan.json").writeText(planJson.toString(2))
        progress(0.08f, "Title: ${plan.title}  (${plan.chapters.size} chapters)")

        val per = max(400, req.totalWords / plan.chapters.size)
        val written = ArrayList<WrittenChapter>()
        var soFar = ""
        val system = if (req.fiction) Prompts.FICTION_SYSTEM else Prompts.NONFICTION_SYSTEM

        plan.chapters.forEachIndexed { i, ch ->
            checkCancelled()
            val frac = 0.10f + 0.78f * (i.toFloat() / plan.chapters.size)
            progress(frac, "Chapter ${i + 1}/${plan.chapters.size}: ${ch.title}")

            var body = gemini.generate(
                Prompts.chapter(
                    title = plan.title,
                    subtitle = plan.subtitle,
                    styleGuide = plan.styleGuide,
                    bible = plan.bible,
                    chapterTitles = plan.chapterTitles,
                    storySoFar = soFar,
                    index = i,
                    chapterTitle = ch.title,
                    brief = ch.brief,
                    wordsTarget = per,
                    fiction = req.fiction,
                ),
                system = system,
                temperature = 0.92,
                maxTokens = 16384,
                log = { progress(frac, it) },
            )
            body = stripHeading(body, ch.title)
            written.add(WrittenChapter(ch.title, body))

            if (i + 1 < plan.chapters.size) {
                checkCancelled()
                soFar = gemini.generate(
                    Prompts.summary(soFar, body),
                    temperature = 0.3,
                    maxTokens = 2048,
                )
                File(dir, "summary.txt").writeText(soFar)
            }
        }

        checkCancelled()
        return finish(
            req = req,
            plan = plan,
            written = written,
            soFar = soFar,
            dir = dir,
            style = CoverStyle(theme = req.themeOverride ?: plan.theme),
            progress = progress,
        )
    }

    /**
     * Cover -> EPUB -> metadata -> ZIP. Shared by the first run, a chapter
     * rewrite and the cover studio, so every artefact always matches.
     */
    private suspend fun finish(
        req: BookRequest,
        plan: BookPlan,
        written: List<WrittenChapter>,
        soFar: String,
        dir: File,
        style: CoverStyle,
        progress: (Float, String) -> Unit,
        coverPng: ByteArray? = null,
        report: QualityReport? = null,
        reportFile: File? = null,
    ): BookResult {
        val png = coverPng ?: renderCover(req, plan, style, progress)
        val coverFile = File(dir, "cover.png").apply { writeBytes(png) }

        progress(0.95f, "Building the EPUB...")
        val epubName = "${plan.fileStem}.epub"
        val epubFile = File(dir, epubName)
        EpubBuilder.build(plan, written, png, epubFile, req.extras)

        progress(0.98f, "Writing the metadata sheet...")
        val words = written.sumOf { it.words }
        val metaFile = File(dir, "metadata.txt").apply {
            writeText(MetadataSheet.build(plan, words, written.size, epubName))
        }

        progress(0.99f, "Packing the publishing kit...")
        val zipFile = File(dir, "${plan.fileStem}-publishing-kit.zip")
        packKit(dir, zipFile, plan.fileStem)

        progress(1f, "Done: $words words, ${written.size} chapters.")
        return BookResult(
            request = req,
            plan = plan,
            directory = dir,
            epub = epubFile,
            cover = coverFile,
            metadata = metaFile,
            zip = zipFile,
            words = words,
            chapters = written,
            summary = soFar,
            coverStyle = style,
            report = report,
            reportFile = reportFile,
        )
    }

    /**
     * Generates cover artwork with the image model, typesets the title on
     * top, and falls back to the drawn theme scene if no artwork can be
     * produced. Artwork sources, in order: Gemini API keys, then the
     * cookie-session client for web-session runs, then the procedural cover.
     */
    private suspend fun renderCover(
        req: BookRequest,
        plan: BookPlan,
        style: CoverStyle,
        progress: (Float, String) -> Unit,
    ): ByteArray {
        progress(0.90f, "Generating the cover artwork...")
        val theme = if (style.theme == "auto" || style.theme.isBlank()) plan.theme else style.theme
        val artPrompt = Prompts.coverArt(plan.title, plan.tagline, theme, req.fiction, style.seed)
        var art: ByteArray? = null
        if (KeyPool.parse(geminiKeys).any { it.startsWith("AIza") }) {
            try {
                art = Gemini(geminiKeys).generateImage(
                    artPrompt,
                    log = { progress(0.90f, it) },
                )
            } catch (e: Exception) {
                progress(
                    0.90f,
                    if (req.provider == Providers.WEB) {
                        "Cover artwork via API unavailable (${e.message}) - trying the web session."
                    } else {
                        "Cover artwork via API unavailable (${e.message}) - using the drawn cover."
                    },
                )
            }
        }
        if (art == null && req.provider == Providers.WEB) {
            try {
                art = webArt().generateImage(artPrompt, log = { progress(0.90f, it) })
            } catch (e: Exception) {
                progress(0.90f, "Cover artwork via the web session unavailable (${e.message}).")
            }
        }
        if (art == null) {
            progress(
                0.90f,
                "No AI artwork - using the drawn cover. Add a Gemini API key " +
                    "or a working web session for AI artwork.",
            )
        }
        progress(0.92f, "Typesetting the cover...")
        return withContext(Dispatchers.Default) {
            CoverRenderer.render(
                title = plan.title,
                subtitle = plan.subtitle,
                series = plan.series,
                tagline = plan.tagline,
                author = plan.author,
                themeName = theme,
                fiction = req.fiction,
                style = style,
                art = art,
            )
        }
    }

    /** One lazily-built client for artwork through the cookie session. */
    private var webArtClient: GeminiWeb? = null

    private fun webArt(): GeminiWeb = webArtClient ?: GeminiWeb(apiKey).also { webArtClient = it }

    /** Same as [renderCover] but for a finished book, used by the cover studio. */
    suspend fun renderCover(
        r: BookResult,
        style: CoverStyle,
        progress: (Float, String) -> Unit = { _, _ -> },
    ): ByteArray = renderCover(r.request, r.plan, style, progress)

    /** Rewrites a single chapter and rebuilds every artefact around it. */
    suspend fun regenerateChapter(
        r: BookResult,
        index: Int,
        note: String,
        progress: (Float, String) -> Unit,
    ): BookResult {
        cancelled = false
        val plan = r.plan
        val req = r.request
        val gemini = Providers.client(req.provider, apiKey, req.model)
        val ch = plan.chapters[index]
        val per = max(400, req.totalWords / plan.chapters.size)

        progress(0.15f, "Rewriting chapter ${index + 1}: ${ch.title}")
        var body = gemini.generate(
            Prompts.chapter(
                title = plan.title,
                subtitle = plan.subtitle,
                styleGuide = plan.styleGuide,
                bible = plan.bible,
                chapterTitles = plan.chapterTitles,
                storySoFar = summaryBefore(r, index),
                index = index,
                chapterTitle = ch.title,
                brief = ch.brief,
                wordsTarget = per,
                fiction = req.fiction,
                revisionNote = note,
                previousDraft = r.chapters[index].body,
            ),
            system = if (req.fiction) Prompts.FICTION_SYSTEM else Prompts.NONFICTION_SYSTEM,
            temperature = 0.92,
            maxTokens = 16384,
            log = { progress(0.4f, it) },
        )
        body = stripHeading(body, ch.title)
        checkCancelled()

        val written = r.chapters.toMutableList()
        written[index] = WrittenChapter(ch.title, body)

        progress(0.75f, "Rebuilding the book...")
        return finish(
            req = req,
            plan = plan,
            written = written,
            soFar = r.summary,
            dir = r.directory,
            style = r.coverStyle,
            progress = progress,
            coverPng = r.cover.takeIf { it.isFile }?.readBytes(),
            report = r.report,
            reportFile = r.reportFile,
        )
    }

    /** Everything the reader knew before [index]. */
    private fun summaryBefore(r: BookResult, index: Int): String {
        if (index == 0) return ""
        val b = StringBuilder()
        for (i in 0 until index) {
            val body = r.chapters[i].body
            b.appendLine("Chapter ${i + 1} - ${r.chapters[i].title}: ${body.take(700)}")
                .appendLine()
        }
        val out = b.toString()
        return if (out.length > 9000) out.takeLast(9000) else out
    }

    /**
     * Reads the finished manuscript back and reports what a reviewer would
     * complain about.
     */
    suspend fun qualityPass(r: BookResult, progress: (Float, String) -> Unit): BookResult {
        cancelled = false
        val gemini = Providers.client(r.request.provider, apiKey, r.request.model)
        progress(0.1f, "Editor pass: reading the whole manuscript...")

        val ms = StringBuilder()
        r.chapters.forEachIndexed { i, c ->
            ms.appendLine("--- CHAPTER ${i + 1}: ${c.title} ---")
                .appendLine(c.body).appendLine()
        }

        val j = gemini.generateJson(
            Prompts.quality(
                title = r.plan.title,
                bible = r.plan.bible,
                fiction = r.request.fiction,
                chapterTitles = r.plan.chapterTitles,
                manuscript = ms.toString(),
            ),
            system = Prompts.EDITOR_SYSTEM,
            temperature = 0.25,
            maxTokens = 16384,
            thinking = 4096,
            log = { progress(0.5f, it) },
        )
        checkCancelled()

        val report = QualityReport.fromJson(j)
        val out = File(r.directory, "quality-report.md")
            .apply { writeText(report.toMarkdown(r.plan.title)) }
        progress(1f, "Editor pass: ${report.score}/100, ${report.issues.size} issues.")
        return r.copy(report = report, reportFile = out)
    }

    /**
     * Four covers to choose from: the current one plus three honest
     * alternatives. Each option gets its own generated artwork.
     */
    suspend fun coverVariants(
        r: BookResult,
        progress: (Float, String) -> Unit = { _, _ -> },
    ): List<CoverVariant> {
        val themes = CoverTheme.ALL.keys.toList()
        val current = if (r.coverStyle.theme == "auto") r.plan.theme else r.coverStyle.theme
        val at = themes.indexOf(current).coerceAtLeast(0)
        val styles = listOf(
            CoverStyle(current, r.coverStyle.layout, r.coverStyle.font, r.coverStyle.seed),
            CoverStyle(current, "bottom", "sans", 7),
            CoverStyle(themes[(at + 2) % themes.size], "center", "auto", 19),
            CoverStyle(themes[(at + 4) % themes.size], "left", "serif", 73),
        )
        val out = ArrayList<CoverVariant>(styles.size)
        styles.forEachIndexed { i, st ->
            checkCancelled()
            progress(0.1f + 0.8f * (i.toFloat() / styles.size), "Cover ${i + 1}/${styles.size}: ${st.label}")
            out.add(
                CoverVariant(
                    st,
                    renderCover(r, st, progress),
                ),
            )
        }
        progress(1f, "Covers ready.")
        return out
    }

    /** Swaps the cover and rebuilds the EPUB, the metadata sheet and the ZIP. */
    suspend fun applyCoverStyle(
        r: BookResult,
        style: CoverStyle,
        progress: (Float, String) -> Unit,
        png: ByteArray? = null,
    ): BookResult {
        cancelled = false
        progress(0.2f, "Applying the new cover...")
        return finish(
            req = r.request,
            plan = r.plan,
            written = r.chapters,
            soFar = r.summary,
            dir = r.directory,
            style = style,
            progress = progress,
            coverPng = png,
            report = r.report,
            reportFile = r.reportFile,
        )
    }

    /** Zips every generated artefact into one folder inside the archive. */
    private fun packKit(dir: File, zipFile: File, stem: String) {
        ZipOutputStream(zipFile.outputStream().buffered()).use { zos ->
            fun add(file: File, path: String) {
                if (!file.isFile) return
                zos.putNextEntry(ZipEntry(path))
                file.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
            dir.listFiles()
                ?.filter { it.isFile && it.name != zipFile.name }
                ?.sortedBy { it.name }
                ?.forEach { add(it, "$stem/${it.name}") }
        }
    }

    private fun stripHeading(body: String, title: String): String {
        var s = body.trim()
        val pattern = Regex(
            "^\\s*#{1,3}\\s*(chapter\\s*\\d+\\s*[:.\\-]?\\s*)?" + Regex.escape(title) + "\\s*$",
            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE),
        )
        s = pattern.replaceFirst(s, "").trim()
        if (s.startsWith("# ")) {
            val nl = s.indexOf('\n')
            s = if (nl == -1) "" else s.substring(nl + 1).trim()
        }
        return s
    }
}
