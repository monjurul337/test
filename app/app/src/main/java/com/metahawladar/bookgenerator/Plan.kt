package com.metahawladar.bookgenerator

import org.json.JSONArray
import org.json.JSONObject

data class ChapterPlan(
    val title: String,
    val brief: String,
    /** One sentence tying this chapter back to the book's theme statement. */
    val themeLink: String = "",
)

data class WrittenChapter(val title: String, val body: String) {
    val words: Int get() = body.split(Regex("\\s+")).count { it.isNotBlank() }
}

data class BookPlan(
    val title: String,
    val subtitle: String,
    val series: String,
    val tagline: String,
    val theme: String,
    val description: String,
    val shortDescription: String,
    val bisac: List<String>,
    val keywords: List<String>,
    val targetReader: String,
    val compTitles: List<String>,
    val minAge: Int,
    val mature: Boolean,
    val priceUsd: Double,
    val authorBio: String,
    /** The governing idea every chapter, the tone and the cover must serve. */
    val themeStatement: String,
    val styleGuide: String,
    val bible: String,
    val chapters: List<ChapterPlan>,
    val author: String,
    val fiction: Boolean,
) {
    val chapterTitles: List<String> get() = chapters.map { it.title }

    val slug: String
        get() = title.lowercase()
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .ifEmpty { "book" }

    val fileStem: String
        get() = title.replace(Regex("[^A-Za-z0-9]+"), "-")
            .trim('-')
            .ifEmpty { "Book" }

    /** Round-trips the plan back to the JSON stored as plan.json. */
    fun toJson(): JSONObject = JSONObject()
        .put("title", title)
        .put("subtitle", subtitle)
        .put("series", series)
        .put("tagline", tagline)
        .put("theme", theme)
        .put("description", description)
        .put("shortDescription", shortDescription)
        .put("bisac", JSONArray(bisac))
        .put("keywords", JSONArray(keywords))
        .put("targetReader", targetReader)
        .put("compTitles", JSONArray(compTitles))
        .put("minAge", minAge)
        .put("mature", mature)
        .put("priceUsd", priceUsd)
        .put("authorBio", authorBio)
        .put("themeStatement", themeStatement)
        .put("styleGuide", styleGuide)
        .put("bible", bible)
        .put("author", author)
        .put("fiction", fiction)
        .put(
            "chapters",
            JSONArray().apply {
                chapters.forEach {
                    put(
                        JSONObject()
                            .put("title", it.title)
                            .put("brief", it.brief)
                            .put("themeLink", it.themeLink),
                    )
                }
            },
        )

    companion object {
        fun fromJson(j: JSONObject, author: String, fiction: Boolean): BookPlan {
            fun strings(key: String): List<String> {
                val a: JSONArray = j.optJSONArray(key) ?: return emptyList()
                return (0 until a.length())
                    .map { a.optString(it, "").trim() }
                    .filter { it.isNotEmpty() }
            }

            val rawChapters = j.optJSONArray("chapters")
            val chapters = buildList {
                if (rawChapters != null) {
                    for (i in 0 until rawChapters.length()) {
                        val c = rawChapters.optJSONObject(i) ?: continue
                        add(
                            ChapterPlan(
                                c.optString("title", "Untitled").trim(),
                                c.optString("brief", "").trim(),
                                c.optString("themeLink", "").trim(),
                            )
                        )
                    }
                }
            }

            return BookPlan(
                title = j.optString("title", "Untitled Book").trim(),
                subtitle = j.optString("subtitle", "").trim(),
                series = j.optString("series", "").trim(),
                tagline = j.optString("tagline", "").trim(),
                theme = j.optString("theme", if (fiction) "ember" else "slate").trim(),
                description = j.optString("description", "").trim(),
                shortDescription = j.optString("shortDescription", "").trim(),
                bisac = strings("bisac"),
                keywords = strings("keywords"),
                targetReader = j.optString("targetReader", "").trim(),
                compTitles = strings("compTitles"),
                minAge = j.optInt("minAge", 14),
                mature = j.optBoolean("mature", false),
                priceUsd = j.optDouble("priceUsd", if (fiction) 2.99 else 4.99),
                authorBio = j.optString("authorBio", "").trim(),
                themeStatement = j.optString("themeStatement", "").trim(),
                styleGuide = j.optString("styleGuide", "").trim(),
                bible = j.optString("bible", "").trim(),
                chapters = chapters,
                author = author,
                fiction = fiction,
            )
        }
    }
}
