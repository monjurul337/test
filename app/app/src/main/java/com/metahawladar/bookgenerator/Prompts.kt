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
        revisionNote: String = "",
        previousDraft: String = "",
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
        val revision = if (revisionNote.isBlank()) "" else """

THIS IS A REWRITE. The previous draft of this chapter was rejected for the
following reason - fix it completely while keeping everything the bible and the
story so far require:
$revisionNote"""
        val draft = if (previousDraft.isBlank()) "" else """

PREVIOUS DRAFT (rewrite it, do not simply copy it):
${previousDraft.take(9000)}"""
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
- No author notes, no commentary, no word count.$revision$draft"""
    }

    const val EDITOR_SYSTEM = """
You are a ruthless but fair line-and-continuity editor at a commercial
publisher. You read for the paying reader. You flag only real problems a
reviewer would notice, never style preferences. You answer only with the JSON
object requested - no markdown fences, no commentary."""

    /** Asks for a structured quality report over the finished manuscript. */
    fun quality(
        title: String,
        bible: String,
        fiction: Boolean,
        chapterTitles: List<String>,
        manuscript: String,
    ): String {
        val list = chapterTitles.mapIndexed { i, t -> "${i + 1}. $t" }.joinToString("\n")
        val kind = if (fiction) "fiction" else "non-fiction"
        val extra = if (fiction) {
            "character: a voice that slips, an unmotivated action"
        } else {
            "accuracy: a claim that is vague, unsupported or wrong"
        }
        return """BOOK: $title
TYPE: $kind

BOOK BIBLE (the author's intent - judge the manuscript against it):
$bible

CHAPTERS:
$list

MANUSCRIPT:
$manuscript

Edit this manuscript. Find the problems that would cost the book a star in a
review:
- continuity: contradictions in names, ages, dates, places, objects, injuries,
  timeline, who knows what, clues planted or resolved wrongly
- repetition: the same image, phrase, beat or explanation reused
- filler: padding, throat-clearing, a chapter that does not move anything
- $extra
- pacing: a chapter that drags or resolves too fast

Return JSON exactly like this:
{
  "score": 0-100,
  "verdict": "one honest sentence about whether this is ready to sell",
  "strengths": ["..."],
  "issues": [
    {"chapter": 3, "type": "continuity|repetition|filler|character|accuracy|pacing",
     "severity": "high|medium|low",
     "detail": "what is wrong, quoting the text briefly",
     "fix": "a specific instruction a writer could follow"}
  ]
}
Rules: chapter is the 1-based number, or 0 for a whole-book issue. At most 20
issues, highest severity first. If the book is clean, return an empty issues
list and say so in the verdict. Never invent a problem to look useful."""
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

    private val COVER_MOODS = mapOf(
        "ember" to "warm night palette of deep violet, ember orange and gold; " +
            "firelight, drifting sparks, dramatic mystery mood",
        "frost" to "cold blue and steel palette; winter haze, frost, long " +
            "shadows, quiet noir mood",
        "forest" to "green and gold woodland palette; soft canopy light, moss, " +
            "warm rural calm",
        "rose" to "pink, rose and violet palette; dusk glow, petals, tender " +
            "romantic mood",
        "slate" to "dark navy and cyan tech palette; clean geometry, screen " +
            "glow, modern business focus",
        "sand" to "warm sand, ochre and cream palette; soft desert light, " +
            "calm reflective memoir mood",
    )

    private val COVER_SCENES = listOf(
        "a lone silhouette walking toward a distant light",
        "a single meaningful object from the story on a table, close up",
        "a dramatic skyline or landscape at the turning point of the day",
        "an open road or path vanishing into weather",
        "a window with light spilling out into the dark",
        "layers of mist over water or hills at dawn",
        "a still life of two or three symbolic objects",
        "an abstract atmospheric field of light, texture and colour",
    )

    /**
     * Art-direction prompt for the cover image model. The image must come
     * back with no text on it - the title and author are typeset locally on
     * top, so the words stay spelled correctly and crisp at print size.
     */
    fun coverArt(
        title: String,
        tagline: String,
        themeName: String,
        fiction: Boolean,
        seed: Int = 0,
    ): String {
        val mood = COVER_MOODS[themeName] ?: COVER_MOODS.getValue("ember")
        val scene = COVER_SCENES[kotlin.math.abs(seed) % COVER_SCENES.size]
        val kind = if (fiction) "novel" else "non-fiction book"
        val through = if (tagline.isBlank()) {
            "the title \"$title\""
        } else {
            "the title \"$title\" and the line \"$tagline\""
        }
        return """Create the background artwork for the cover of a $kind.

Art direction: $mood.

Picture this: $scene, interpreted through $through.

Rules:
- Vertical 2:3 composition, cinematic lighting, rich painterly detail, the quality of a top-selling trade cover.
- Absolutely no text, no letters, no numbers, no words, no logos, no watermarks, no borders, no frames.
- Keep the upper third and the bottom edge calm and uncluttered - the title and author name will be typeset over them later.
- One clear focal point; no collage of many small scenes."""
    }
}
