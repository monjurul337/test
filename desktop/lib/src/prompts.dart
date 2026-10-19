/// All model-facing text lives here so prose quality can be tuned in one place.
class Prompts {
  static const String planSystem = '''
You are a commercial book development editor who has shipped hundreds of
profitable self-published titles. You think about what readers actually buy and
finish. You answer only with the JSON object requested - no markdown fences,
no commentary.''';

  static const String fictionSystem = '''
You are a professional novelist writing commercial fiction for a paying readership.
Write clean, confident prose. Concrete sensory detail over abstraction. Characters
reveal themselves through action and speech, not through the narrator explaining
them. Vary sentence length. Never summarise a scene you could dramatise. No purple
prose, no cliche. Pick British or American spelling and keep it.''';

  static const String nonfictionSystem = '''
You are a professional non-fiction author writing a practical guide for working
adults. Be specific and useful. Every claim gets a concrete example, number,
script, or step. Short paragraphs. Direct address to the reader. No filler, no
motivational padding, no restating the chapter title back to the reader. Never
promise something the chapter does not deliver.''';

  static const String themeHint =
      'ember = warm night, mystery/thriller/drama; frost = cold blue, noir/winter/literary; '
      'forest = green-gold, cozy/rural/historical; rose = pink-violet, romance/women\'s fiction; '
      'slate = dark tech, business/nonfiction/self-help; sand = warm neutral, memoir/essays/guides';

  static const String planSchema = '''{
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
}''';

  static String plan({
    required String topic,
    required bool fiction,
    required int chapters,
    required int totalWords,
    required String author,
    String note = '',
  }) {
    final String kind = fiction ? 'novel/novella' : 'non-fiction book';
    final int per = totalWords ~/ (chapters == 0 ? 1 : chapters);
    return '''Develop a complete, commercially viable $kind from this topic:

TOPIC: $topic

Constraints:
- Exactly $chapters chapters. Target total length about $totalWords words
  (~$per words per chapter), so scope the story/argument to fit. Do not plan an
  epic that cannot land in $totalWords words.
- Author name is "$author". Do not invent awards, degrees, or client numbers.
- Cover theme must be one of: $themeHint
- Pick a genre niche that actually sells, and commit to its conventions.
${note.isEmpty ? '' : '- Extra instructions: $note'}

Return JSON exactly in this shape:
$planSchema''';
  }

  static String chapter({
    required String title,
    required String subtitle,
    required String styleGuide,
    required String bible,
    required List<String> chapterTitles,
    required String storySoFar,
    required int index,
    required String chapterTitle,
    required String brief,
    required int wordsTarget,
    required bool fiction,
    String revisionNote = '',
    String previousDraft = '',
  }) {
    final int n = index + 1;
    final int total = chapterTitles.length;
    final String? next = n < total ? chapterTitles[n] : null;
    final StringBuffer list = StringBuffer();
    for (int i = 0; i < chapterTitles.length; i++) {
      list.writeln('${i + 1}. ${chapterTitles[i]}');
    }
    return '''BOOK: $title${subtitle.isEmpty ? '' : ' - $subtitle'}
STYLE: $styleGuide

BOOK BIBLE (authoritative - never contradict it):
$bible

FULL CHAPTER LIST:
$list
STORY SO FAR (what the reader already knows):
${storySoFar.isEmpty ? 'Nothing yet - this is the opening chapter.' : storySoFar}

NOW WRITE CHAPTER $n OF $total: "$chapterTitle"
What this chapter must do: $brief
${next != null ? 'The next chapter is "$next", so end in a way that leads there.' : 'This is the final chapter. Land the ending fully; resolve the central question.'}

Rules:
- About $wordsTarget words. This is a real target, not a suggestion.
- Start with the first line of the chapter body. Do NOT output the chapter title or any heading for it.
- Output Markdown. ${fiction ? 'Use a line containing only  * * *  for scene breaks.' : 'Use ## subheads to structure it, and lists or tables where they genuinely help.'}
- ${fiction ? 'Dramatise. No summarising narration, no recapping earlier chapters.' : 'No recapping earlier chapters, no "in this chapter we will".'}
- Plant exactly what the bible says is planted here. Reveal nothing the bible withholds.
- No author notes, no commentary, no word count.${revisionNote.isEmpty ? '' : '''

THIS IS A REWRITE. The previous draft of this chapter was rejected for the
following reason - fix it completely while keeping everything the bible and the
story so far require:
$revisionNote'''}${previousDraft.isEmpty ? '' : '''

PREVIOUS DRAFT (rewrite it, do not simply copy it):
${previousDraft.length > 9000 ? previousDraft.substring(0, 9000) : previousDraft}'''}''';
  }

  static const String editorSystem = '''
You are a ruthless but fair line-and-continuity editor at a commercial
publisher. You read for the paying reader. You flag only real problems a
reviewer would notice, never style preferences. You answer only with the JSON
object requested - no markdown fences, no commentary.''';

  /// Asks for a structured quality report over the finished manuscript.
  static String quality({
    required String title,
    required String bible,
    required bool fiction,
    required List<String> chapterTitles,
    required String manuscript,
  }) {
    final StringBuffer list = StringBuffer();
    for (int i = 0; i < chapterTitles.length; i++) {
      list.writeln('${i + 1}. ${chapterTitles[i]}');
    }
    return '''BOOK: $title
TYPE: ${fiction ? 'fiction' : 'non-fiction'}

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
- ${fiction ? 'character: a voice that slips, an unmotivated action' : 'accuracy: a claim that is vague, unsupported or wrong'}
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
list and say so in the verdict. Never invent a problem to look useful.''';
  }

  static String summary(String previous, String chapterText) => '''
Previous running summary:
${previous.isEmpty ? '(none)' : previous}

New chapter text:
${chapterText.length > 14000 ? chapterText.substring(0, 14000) : chapterText}

Rewrite the running summary so it covers everything through this chapter. Under
220 words. Plain prose, no headings. Track: what happened, what the reader now
knows, every open question, and any detail a later chapter must stay consistent
with (names, dates, objects, injuries, lies).''';

  /// Art-direction prompt for the cover image model. The image must come back
  /// with no text on it - the title and author are typeset locally on top, so
  /// the words are always spelled correctly and stay crisp at print size.
  static String coverArt({
    required String title,
    required String tagline,
    required String themeName,
    required bool fiction,
    int seed = 0,
  }) {
    const Map<String, String> moods = <String, String>{
      'ember':
          'warm night palette of deep violet, ember orange and gold; firelight, '
              'drifting sparks, dramatic mystery mood',
      'frost':
          'cold blue and steel palette; winter haze, frost, long shadows, '
              'quiet noir mood',
      'forest':
          'green and gold woodland palette; soft canopy light, moss, '
              'warm rural calm',
      'rose':
          'pink, rose and violet palette; dusk glow, petals, '
              'tender romantic mood',
      'slate':
          'dark navy and cyan tech palette; clean geometry, screen glow, '
              'modern business focus',
      'sand':
          'warm sand, ochre and cream palette; soft desert light, '
              'calm reflective memoir mood',
    };
    const List<String> scenes = <String>[
      'a lone silhouette walking toward a distant light',
      'a single meaningful object from the story on a table, close up',
      'a dramatic skyline or landscape at the turning point of the day',
      'an open road or path vanishing into weather',
      'a window with light spilling out into the dark',
      'layers of mist over water or hills at dawn',
      'a still life of two or three symbolic objects',
      'an abstract atmospheric field of light, texture and colour',
    ];
    final String mood = moods[themeName] ?? moods['ember']!;
    final String scene = scenes[seed.abs() % scenes.length];
    final String kind = fiction ? 'novel' : 'non-fiction book';
    return '''Create the background artwork for the cover of a $kind.

Art direction: $mood.

Picture this: $scene, interpreted through the title "$title"${tagline.isEmpty ? '' : ' and the line "$tagline"'}.

Rules:
- Vertical 2:3 composition, cinematic lighting, rich painterly detail, the quality of a top-selling trade cover.
- Absolutely no text, no letters, no numbers, no words, no logos, no watermarks, no borders, no frames.
- Keep the upper third and the bottom edge calm and uncluttered - the title and author name will be typeset over them later.
- One clear focal point; no collage of many small scenes.''';
  }
}
