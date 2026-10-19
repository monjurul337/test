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
- No author notes, no commentary, no word count.''';
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
}
