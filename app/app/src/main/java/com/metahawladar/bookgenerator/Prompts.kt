package com.metahawladar.bookgenerator

/** All model-facing text lives here so prose quality can be tuned in one place. */
object Prompts {

    const val PLAN_SYSTEM = """
You are a commercial book development editor who has shipped hundreds of
profitable self-published titles. You think about what readers actually buy and
finish. You answer only with the JSON object requested - no markdown fences,
no commentary."""

    const val FICTION_SYSTEM = """
You are a professional novelist writing commercial fiction for a paying readership.
Write clean, confident prose. Concrete sensory detail over abstraction. Characters
reveal themselves through action and speech, not through the narrator explaining
them. Vary sentence length. Never summarise a scene you could dramatise. No purple
prose, no cliche. Pick British or American spelling and keep it."""

    const val NONFICTION_SYSTEM = """
You are a professional non-fiction author writing a practical guide for working
adults. Be specific and useful. Every claim gets a concrete example, number,
script, or step. Short paragraphs. Direct address to the reader. No filler, no
motivational padding, no restating the chapter title back to the reader. Never
promise something the chapter does not deliver."""

    const val THEME_HINT =
        "ember = warm night, mystery/thriller/drama; frost = cold blue, noir/winter/literary; " +
            "forest = green-gold, cozy/rural/historical; rose = pink-violet, romance/women's fiction; " +
            "slate = dark tech, business/nonfiction/self-help; sand = warm neutral, memoir/essays/guides"

    const val PLAN_SCHEMA = """{
  "title": "short, memorable, searchable",
  "subtitle": "only if it genuinely helps - else empty string",
  "series": "e.g. 'A Wrenhaven Mystery - Book One' - empty string if standalone",
  "tagline": "one or two short lines for the cover, empty string if none fits",
  "theme": "one of: ember, frost, forest, rose, slate, sand",
  "description": "180-260 word store blurb, written to sell",
  "shortDescription": "under 400 characters",
  "bisac": ["3 BISAC codes with names, e.g. 'FIC022070 - Fiction / Mystery & Detective / Cozy'"],
  "keywords": ["7 store keywords, lowercase, buyer search phrases not themes"],
  "targetReader": "one or two sentences naming who buys this",
  "compTitles": ["3 real comparable published books"],
  "minAge": 14,
  "mature": false,
  "priceUsd": 2.99,
  "authorBio": "2-3 sentences, third person, no invented credentials",
  "styleGuide": "3-5 sentences fixing voice, tense, POV, spelling convention, and what to avoid",
  "bible": "THE MOST IMPORTANT FIELD. 350-600 words. For fiction: setting, full cast with ages and motives, the central question, the real answer/culprit, every clue and where it is planted, and the ending. For non-fiction: the core framework, its named parts, the through-line argument, and the promise the book must keep. Every chapter is written against this text alone, so it must be complete and internally consistent.",
  "chapters": [
    {"title": "chapter title, no 'Chapter N' prefix", "brief": "60-110 words: exactly what happens or is taught here, what changes by the end, and what must be set up for later chapters"}
  ]
}"""

    fun plan(
        topic: String,
        fiction: Boolean,
        chapters: Int,
        totalWords: Int,
        author: String,
        note: String = "",
    ): String {
        val kind = if (fiction) "novel/novella" else "non-fiction book"
        val per = totalWords / if (chapters == 0) 1 else chapters
        val extra = if (note.isBlank()) "" else "- Extra instructions: $note"
        return """Develop a complete, commercially viable $kind from this topic:

TOPIC: $topic

Constraints:
- Exactly $chapters chapters. Target total length about $totalWords words
  (~$per words per chapter), so scope the story/argument to fit. Do not plan an
  epic that cannot land in $totalWords words.
- Author name is "$author". Do not invent awards, degrees, or client numbers.
- Cover theme must be one of: $THEME_HINT
- Pick a genre niche that actually sells, and commit to its conventions.
$extra

Return JSON exactly in this shape:
$PLAN_SCHEMA"""
    }

    fun chapter(
        title: String,
        subtitle: String,
        styleGuide: String,
        bible: String,
        chapterTitles: List<String>,
        storySoFar: String,
        index: Int,
        chapterTitle: String,
        brief: String,
        wordsTarget: Int,
        fiction: Boolean,
    ): String {
        val n = index + 1
        val total = chapterTitles.size
        val next = if (n < total) chapterTitles[n] else null
        val list = chapterTitles.mapIndexed { i, t -> "${i + 1}. $t" }.joinToString("\n")
        val head = if (subtitle.isBlank()) title else "$title - $subtitle"
        val soFar = storySoFar.ifBlank { "Nothing yet - this is the opening chapter." }
        val lead = if (next != null) {
            "The next chapter is \"$next\", so end in a way that leads there."
        } else {
            "This is the final chapter. Land the ending fully; resolve the central question."
        }
        val fmt = if (fiction) {
            "Use a line containing only  * * *  for scene breaks."
        } else {
            "Use ## subheads to structure it, and lists or tables where they genuinely help."
        }
        val mode = if (fiction) {
            "Dramatise. No summarising narration, no recapping earlier chapters."
        } else {
            "No recapping earlier chapters, no \"in this chapter we will\"."
        }
        return """BOOK: $head
STYLE: $styleGuide

BOOK BIBLE (authoritative - never contradict it):
$bible

FULL CHAPTER LIST:
$list

STORY SO FAR (what the reader already knows):
$soFar

NOW WRITE CHAPTER $n OF $total: "$chapterTitle"
What this chapter must do: $brief
$lead

Rules:
- About $wordsTarget words. This is a real target, not a suggestion.
- Start with the first line of the chapter body. Do NOT output the chapter title or any heading for it.
- Output Markdown. $fmt
- $mode
- Plant exactly what the bible says is planted here. Reveal nothing the bible withholds.
- No author notes, no commentary, no word count."""
    }

    fun summary(previous: String, chapterText: String): String {
        val prev = previous.ifBlank { "(none)" }
        val body = if (chapterText.length > 14000) chapterText.take(14000) else chapterText
        return """Previous running summary:
$prev

New chapter text:
$body

Rewrite the running summary so it covers everything through this chapter. Under
220 words. Plain prose, no headings. Track: what happened, what the reader now
knows, every open question, and any detail a later chapter must stay consistent
with (names, dates, objects, injuries, lies)."""
    }
}
