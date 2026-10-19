package com.metahawladar.bookgenerator

import java.io.File
import kotlin.math.max

data class BookRequest(
    val topic: String,
    val author: String,
    val fiction: Boolean,
    val chapters: Int,
    val totalWords: Int,
    val model: String,
    val themeOverride: String? = null,
    val note: String = "",
)

data class BookResult(
    val plan: BookPlan,
    val directory: File,
    val epub: File,
    val cover: File,
    val metadata: File,
    val words: Int,
)

/** Orchestrates plan -> chapters -> cover -> EPUB -> metadata. */
class BookWriter(private val apiKey: String, private val outputRoot: File) {

    @Volatile
    private var cancelled = false

    fun cancel() { cancelled = true }

    private fun checkCancelled() {
        if (cancelled) throw CancellationRequested()
    }

    class CancellationRequested : RuntimeException("Cancelled")

    suspend fun run(req: BookRequest, progress: (Float, String) -> Unit): BookResult {
        val gemini = Gemini(apiKey, req.model)

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
        val chaptersDir = File(dir, "chapters").apply { mkdirs() }

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
            File(chaptersDir, "%02d-%s.md".format(i + 1, slug(ch.title)))
                .writeText("# ${ch.title}\n\n$body\n")

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
        progress(0.90f, "Rendering the cover...")
        val png = CoverRenderer.render(
            title = plan.title,
            subtitle = plan.subtitle,
            series = plan.series,
            tagline = plan.tagline,
            author = plan.author,
            themeName = req.themeOverride ?: plan.theme,
            fiction = req.fiction,
        )
        val coverFile = File(dir, "cover.png").apply { writeBytes(png) }

        progress(0.95f, "Building the EPUB...")
        val epubName = "${plan.fileStem}.epub"
        val epubFile = File(dir, epubName)
        EpubBuilder.build(plan, written, png, epubFile)

        progress(0.98f, "Writing the metadata sheet...")
        val words = written.sumOf { it.words }
        val metaFile = File(dir, "metadata.txt").apply {
            writeText(MetadataSheet.build(plan, words, written.size, epubName))
        }

        progress(1f, "Done: $words words, ${written.size} chapters.")
        return BookResult(plan, dir, epubFile, coverFile, metaFile, words)
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

    private fun slug(s: String): String {
        val t = s.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
        return (if (t.length > 40) t.take(40) else t).ifEmpty { "chapter" }
    }
}
