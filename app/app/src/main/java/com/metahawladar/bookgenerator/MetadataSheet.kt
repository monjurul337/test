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

    fun build(plan: BookPlan, words: Int, chapterCount: Int, epubName: String): List<PublishField> {
        val out = ArrayList<PublishField>()
        fun add(group: String, label: String, value: String, hint: String = "") {
            if (value.isBlank()) return
            out.add(PublishField(group, label, value, hint))
        }

        add("Files", "Book file", epubName, "Validated EPUB 3. Upload this as the book content.")
        add(
            "Files", "Cover image", "cover.png",
            "1600 x 2560. Upload separately - the cover embedded in the EPUB is not enough for Google Play.",
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
        plan.bisac.forEachIndexed { i, code ->
            add(
                "Store listing", "Genre / BISAC ${i + 1}", code,
                if (i == 0) "The first one is treated as the primary category." else "",
            )
        }
        if (plan.keywords.isNotEmpty()) {
            add(
                "Store listing", "Keywords", plan.keywords.joinToString(", "),
                "Use every slot the form gives you.",
            )
        }
        add("Store listing", "Language", "English (en)")

        add(
            "Pricing and rights", "List price", "USD %.2f".format(Locale.US, plan.priceUsd),
            "Below USD 2.99 Amazon pays 35% instead of 70%.",
        )
        add(
            "Pricing and rights", "ISBN", "Leave blank",
            "Google Play assigns a free identifier at upload, so you do not need one.",
        )
        add("Pricing and rights", "Territories", "Worldwide")

        add("Audience", "Minimum age", plan.minAge.toString())
        add(
            "Audience", "Maximum age", "Leave blank",
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

    fun build(plan: BookPlan, words: Int, chapterCount: Int, epubName: String): String {
        val fields = PublishFields.build(plan, words, chapterCount, epubName)
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
