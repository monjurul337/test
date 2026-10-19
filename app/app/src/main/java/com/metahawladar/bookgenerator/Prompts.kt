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
  "themeStatement": "THE GOVERNING SENTENCE. 1-2 sentences naming (a) exactly who the reader is, (b) the single transformation or central question the book delivers, and (c) the one controlling image or metaphor that runs through it. Every chapter, the tone, and the cover are judged against this sentence alone.",
  "styleGuide": "3-5 sentences fixing voice, tense, POV, spelling convention, sentence rhythm, and what to avoid. This tone is fixed for the whole book - it must suit the themeStatement and must not shift between chapters.",
  "bible": "THE MOST IMPORTANT FIELD. 350-600 words. For fiction: setting, full cast with ages and motives, the central question, the real answer/culprit, every clue and where it is planted, and the ending. For non-fiction: the core framework, its named parts, the through-line argument, and the promise the book must keep. Every chapter is written against this text alone, so it must be complete and internally consistent.",
  "chapters": [
    {"title": "chapter title, no 'Chapter N' prefix", "brief": "60-110 words: exactly what happens or is taught here, what changes by the end, and what must be set up for later chapters", "themeLink": "one sentence naming which clause of the themeStatement this chapter advances. If you cannot write it without repeating another chapter or going vague, the chapter does not belong - merge or replace it."}
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

THEME CONSISTENCY (non-negotiable):
- Write "themeStatement" first and derive everything else from it.
- Every chapter must carry a "themeLink" tracing it back to the themeStatement.
  No chapter may introduce a subject the themeStatement does not cover, and no
  two chapters may advance the same clause in the same way.
- "styleGuide" fixes one tone for the whole book and that tone must match the
  themeStatement's mood.
- The "theme" colourway must be the closest fit from the list above for the
  themeStatement's mood. The cover picture itself is painted from the title
  alone, so the title must carry the book's central image.
- Title, subtitle and tagline must promise exactly what the chapters deliver -
  nothing broader, nothing extra.

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
        themeStatement: String = "",
        themeLink: String = "",
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
        val theme = if (themeStatement.isBlank()) "" else """THEME STATEMENT (the book's governing idea - every paragraph must serve it):
$themeStatement

"""
        val link = if (themeLink.isBlank()) "" else "How it serves the theme: $themeLink\n"
        return """BOOK: $head
${theme}STYLE (fixed for the whole book - do not drift from it): $styleGuide

BOOK BIBLE (authoritative - never contradict it):
$bible

FULL CHAPTER LIST:
$list

STORY SO FAR (what the reader already knows):
$soFar

NOW WRITE CHAPTER $n OF $total: "$chapterTitle"
What this chapter must do: $brief
$link$lead

Rules:
- About $wordsTarget words. This is a real target, not a suggestion.
- Start with the first line of the chapter body. Do NOT output the chapter title or any heading for it.
- Output Markdown. $fmt
- $mode
- Plant exactly what the bible says is planted here. Reveal nothing the bible withholds.
- Stay inside the theme statement. Do not introduce a subject, lesson or subplot
  it does not cover, however interesting it is.
- Hold the STYLE exactly: same person, tense, rhythm and level of formality as
  every other chapter. A reader must not be able to tell the chapters apart by voice.
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
        themeStatement: String = "",
    ): String {
        val list = chapterTitles.mapIndexed { i, t -> "${i + 1}. $t" }.joinToString("\n")
        val kind = if (fiction) "fiction" else "non-fiction"
        val theme = if (themeStatement.isBlank()) "" else """
THEME STATEMENT (the governing idea - the whole book is judged against it):
$themeStatement
"""
        val extra = if (fiction) {
            "character: a voice that slips, an unmotivated action"
        } else {
            "accuracy: a claim that is vague, unsupported or wrong"
        }
        return """BOOK: $title
TYPE: $kind
$theme
BOOK BIBLE (the author's intent - judge the manuscript against it):
$bible

CHAPTERS:
$list

MANUSCRIPT:
$manuscript

Edit this manuscript. Find the problems that would cost the book a star in a
review:
- theme: a chapter that drifts off the theme statement, repeats another
  chapter's role in it, or a title/subtitle that promises more than the
  chapters deliver
- tone: a chapter whose voice, person, tense or formality differs from the rest
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
    {"chapter": 3, "type": "theme|tone|continuity|repetition|filler|character|accuracy|pacing",
     "severity": "high|medium|low",
     "detail": "what is wrong, quoting the text briefly",
     "fix": "a specific instruction a writer could follow"}
  ]
}
Rules: chapter is the 1-based number, or 0 for a whole-book issue. At most 20
issues, highest severity first. If the book is clean, return an empty issues
list and say so in the verdict. Never invent a problem to look useful."""
    }

    /**
     * Turns the title alone into one art-director prompt for the image model.
     *
     * The cover is deliberately built from the title and nothing else: a
     * short, concrete prompt is what FLUX.1-schnell renders best, and it keeps
     * the picture to one clear idea instead of a crowded summary of the book.
     */
    fun coverArt(title: String): String =
        """You are the art director for a commercial book cover.

BOOK TITLE: $title

Working from the title alone, write ONE image-generation prompt for the cover
artwork. Rules:
- Read the title literally and choose the single strongest object or scene it
  suggests. One subject, no collage, no second idea.
- Vertical composition. Keep the upper third and the lower fifth visually calm
  and uncluttered, because the title and the author name are typeset there
  afterwards and must stay legible at thumbnail size.
- Name the medium, the lighting and the mood (for example: moody oil painting,
  low winter light, lantern glow, heavy shadow).
- No text, no letters, no numbers, no logos, no watermark, no close-up faces,
  no book or cover mockup.
- 40 words maximum, one paragraph, no preamble and no quotes."""

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
