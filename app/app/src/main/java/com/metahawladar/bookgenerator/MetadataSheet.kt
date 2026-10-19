package com.metahawladar.bookgenerator

import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

/** One row of the upload form. */
data class PublishField(
    val group: String,
    val label: String,
    val value: String,
    val hint: String = "",
)

/**
 * Single source of truth for everything a storefront asks for. The on-screen
 * checklist and metadata.txt are both generated from this list, so they can
 * never drift apart.
 */
object PublishFields {

    val GROUPS = listOf(
        "Files",
        "Store listing",
        "Pricing and rights",
        "Audience",
        "Dates",
        "Content protection",
        "Book details",
    )

    /** The ordered things a first-time publisher still has to do by hand. */
    val STEPS = listOf(
        "Sign in to Google Play Books Partner Center and open Book catalog.",
        "Add a new book, upload the EPUB, then upload cover.png separately.",
        "Paste the store listing fields below, in order.",
        "Set the price, age range, DRM and preview limits exactly as listed.",
        "Set the publication and release dates, leave pre-orders off.",
        "Accept the distribution terms yourself - no tool can do that for you.",
        "Submit, then check back in 3-7 days; \"Needs action\" means a required field is still empty.",
    )

    fun pages(words: Int): Int = (words / 250.0).roundToInt()

    private fun date(daysFromNow: Int): String {
        val c = Calendar.getInstance()
        c.add(Calendar.DAY_OF_YEAR, daysFromNow)
        return String.format(
            Locale.US, "%04d-%02d-%02d",
            c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
        )
    }

    fun build(
        plan: BookPlan,
        words: Int,
        chapterCount: Int,
        epubName: String,
        publisher: String = "",
    ): List<PublishField> {
        val out = ArrayList<PublishField>()
        fun add(group: String, label: String, value: String, hint: String = "") {
            if (value.isBlank()) return
            out.add(PublishField(group, label, value, hint))
        }

        add(
            "Files", "Book file", epubName,
            "EPUB 3, complete book, front cover embedded, validated by EpubCheck. " +
                "Google accepts only .epub or .pdf, never .doc or .html.",
        )
        add(
            "Files", "Cover image", "cover.png",
            "1600 x 2560 PNG. Google needs this separately for the store thumbnail. " +
                "Minimum 640 px, maximum 7200 px on either side.",
        )

        add(
            "Store listing", "Format", "ebook",
            "Partner Center prefills this. Leave it as ebook.",
        )
        add("Store listing", "Title", plan.title)
        add("Store listing", "Subtitle", plan.subtitle)
        add(
            "Store listing", "Series", plan.series,
            "Series name and number. Leave blank if the book is standalone.",
        )
        add("Store listing", "Contributor", plan.author, "Role: Author")
        add("Store listing", "Contributor biography", plan.authorBio)
        add(
            "Store listing", "Short description", plan.shortDescription,
            "Under 400 characters, for stores with a short field.",
        )
        add("Store listing", "Description", plan.description, "The main store blurb.")
        add(
            "Store listing", "Subject standard", "BISAC",
            "Play Store genres are built on BISAC. All genres must come from this one standard.",
        )
        plan.bisac.take(3).forEachIndexed { i, code ->
            add(
                "Store listing", "Genre ${i + 1} (BISAC)", code,
                if (i == 0) {
                    "Google recommends at most 3 genres. The first must be the most relevant."
                } else {
                    ""
                },
            )
        }
        if (plan.keywords.isNotEmpty()) {
            add(
                "Store listing", "Keywords", plan.keywords.joinToString(", "),
                "Use every slot the form gives you.",
            )
        }
        add(
            "Store listing", "Language", "English (en)",
            "The primary language of the book, as set in Book info.",
        )
        if (publisher.isNotBlank()) {
            add(
                "Store listing", "Publisher", publisher,
                "Shown publicly on Google Books preview pages as " +
                    "\"Pages displayed by permission of...\".",
            )
        }
        if (plan.series.isNotBlank()) {
            add(
                "Store listing", "Volume in series", "1",
                "Number every volume with no gaps, or Play will not build a series page.",
            )
        }
        add(
            "Store listing", "Related books", "Leave blank",
            "Only for other editions of the same book, e.g. a paperback ISBN.",
        )

        add(
            "Pricing and rights", "List price", "USD %.2f".format(Locale.US, plan.priceUsd),
            "Google Play pays 70% of list price in most countries, at any price point.",
        )
        add(
            "Pricing and rights", "ISBN", "Leave blank",
            "Google Play assigns a free identifier at upload, so you do not need one.",
        )
        add("Pricing and rights", "Territories", "Worldwide")

        add(
            "Audience", "Age group - minimum age", plan.minAge.toString(),
            "Partner Center calls this Age group: the intended audience for the book.",
        )
        add(
            "Audience", "Age group - maximum age", "Leave blank",
            "Setting a maximum caps your audience for no benefit.",
        )
        add(
            "Audience", "For mature audiences?", if (plan.mature) "Yes" else "No",
            if (plan.mature) {
                "This book contains adult content, so the flag is required."
            } else {
                "Saying Yes without cause removes the book from recommendations in many countries."
            },
        )

        add("Dates", "Publication date", date(0), "The day the book is first published - today.")
        add(
            "Dates", "Release date", date(10),
            "About 10 days out, so every store goes live together. Distribution takes 3-7 days.",
        )
        add(
            "Dates", "Allow pre-orders?", "No",
            "Yes only for book 2 or later in a series, once you already have readers.",
        )

        add(
            "Content protection", "Apply DRM encryption?", "No",
            "DRM does not stop piracy and annoys real buyers. DRM-free is the indie standard.",
        )
        add(
            "Content protection", "Preview limit", "20%",
            "In fiction the preview is the sales pitch. Do not lower it.",
        )
        add(
            "Content protection", "Copy / paste limit", "0%",
            "A small allowance lets reviewers quote you, but 0% is fine.",
        )

        add(
            "Book details", "Page count", pages(words).toString(),
            "EPUB has no fixed pages; stores use this only as a hint.",
        )
        add("Book details", "Word count", words.toString())
        add("Book details", "Chapters", chapterCount.toString())
        add("Book details", "Target reader", plan.targetReader)
        if (plan.compTitles.isNotEmpty()) {
            add(
                "Book details", "Comparable titles", plan.compTitles.joinToString("; "),
                "Useful for ads and for picking categories.",
            )
        }
        return out
    }
}

/** The plain-text upload sheet that ships next to the EPUB. */
object MetadataSheet {

    fun build(
        plan: BookPlan,
        words: Int,
        chapterCount: Int,
        epubName: String,
        publisher: String = "",
    ): String {
        val fields = PublishFields.build(plan, words, chapterCount, epubName, publisher)
        val b = StringBuilder()
        b.appendLine("=".repeat(70))
            .appendLine("BOOK METADATA - ${plan.title}")
            .appendLine("Generated by Book Generator - Meta Hawladar Team")
            .appendLine("=".repeat(70))
            .appendLine()
            .appendLine("WHAT YOU STILL HAVE TO DO")
            .appendLine("-".repeat(70))
        PublishFields.STEPS.forEachIndexed { i, step ->
            b.appendLine("${i + 1}. ${wrap(step, 66, "   ")}")
        }
        b.appendLine()
            .appendLine("GOOGLE PLAY BOOKS RULES THIS FILE ALREADY MEETS")
            .appendLine("-".repeat(70))
        PlayRules.SATISFIED.forEach { b.appendLine("- ${wrap(it, 66, "  ")}") }
        b.appendLine()

        for (group in PublishFields.GROUPS) {
            val rows = fields.filter { it.group == group }
            if (rows.isEmpty()) continue
            b.appendLine("=".repeat(70))
                .appendLine(group.uppercase())
                .appendLine("=".repeat(70))
                .appendLine()
            for (r in rows) {
                b.appendLine("-".repeat(70))
                    .appendLine(r.label.uppercase())
                    .appendLine(wrap(r.value, 70))
                if (r.hint.isNotEmpty()) {
                    b.appendLine(wrap("  why: ${r.hint}", 70, "       "))
                }
                b.appendLine()
            }
        }
        b.appendLine("=".repeat(70))
        return b.toString()
    }

    private fun wrap(text: String, width: Int = 78, indent: String = ""): String {
        val out = ArrayList<String>()
        for (para in text.split("\n")) {
            if (para.isBlank()) { out.add(""); continue }
            val line = StringBuilder()
            for (word in para.trim().split(Regex("\\s+"))) {
                when {
                    line.isEmpty() -> line.append(word)
                    line.length + 1 + word.length <= width -> line.append(' ').append(word)
                    else -> { out.add(line.toString()); line.clear(); line.append(word) }
                }
            }
            if (line.isNotEmpty()) out.add(line.toString())
        }
        if (out.size <= 1) return out.joinToString("")
        return out.first() + "\n" + out.drop(1).joinToString("\n") { "$indent$it" }
    }
}

/**
 * Checks the finished book against the published Google Play Books rules.
 *
 * Sources: "Book file guidelines" and "EPUB files" in the Partner Center help
 * centre, plus the Publisher Content Policies.
 */
object PlayRules {

    /** Returns one line per problem. An empty list means nothing is blocking. */
    fun check(
        plan: BookPlan,
        words: Int,
        coverWidth: Int,
        coverHeight: Int,
        epubBytes: Long,
    ): List<String> {
        val bad = ArrayList<String>()

        if (words < 1000) {
            bad.add(
                "The book is only $words words. Google requires at least 4 pages, " +
                    "and short filler is rejected as low-quality content."
            )
        }
        if (plan.title.isBlank()) {
            bad.add("Title is empty. Title and genre are required fields.")
        }
        if (plan.description.isBlank()) {
            bad.add(
                "Description is empty. Without it the book will not be discoverable " +
                    "and may be flagged as low quality."
            )
        }
        if (plan.bisac.isEmpty()) {
            bad.add("No BISAC genre. A subject code is a required field.")
        }
        if (plan.bisac.size > 3) {
            bad.add(
                "${plan.bisac.size} genres planned. Google recommends at most 3, " +
                    "and only the first 3 are written to the sheet."
            )
        }
        val small = minOf(coverWidth, coverHeight)
        val big = maxOf(coverWidth, coverHeight)
        if (small < 640) {
            bad.add("Cover is ${coverWidth}x$coverHeight. The minimum is 640 px.")
        }
        if (big > 7200) {
            bad.add("Cover is ${coverWidth}x$coverHeight. The maximum is 7200 px.")
        }
        if (epubBytes > 2_000_000_000L) {
            bad.add("The EPUB is over 2 GB, which Google will not accept.")
        }
        return bad
    }

    /** The rules this build already satisfies, for the sheet. */
    val SATISFIED = listOf(
        "EPUB 3 with the front cover embedded, and the complete book - not a sample.",
        "Only .epub is produced; Google rejects .doc and .html.",
        "Cover also saved as a separate PNG for the store thumbnail.",
        "Images are PNG only - inside the supported GIF/JPEG/PNG/SVG set.",
        "No JavaScript, no MathML and no multi-column CSS, none of which Play Books renders.",
        "A \"bodymatter\" landmark so the free sample opens on chapter 1, not the copyright page.",
        "Reflowable text, so the book works on every screen size Play Books supports.",
        "BISAC subject codes, which is the standard the Play Store genres are built on.",
    )
}
