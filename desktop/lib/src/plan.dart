/// Parsed output of the planning call.
class ChapterPlan {
  ChapterPlan(this.title, this.brief, [this.themeLink = '']);

  factory ChapterPlan.fromJson(Map<String, dynamic> j) => ChapterPlan(
    (j['title'] ?? 'Untitled').toString().trim(),
    (j['brief'] ?? '').toString().trim(),
    (j['themeLink'] ?? '').toString().trim(),
  );

  final String title;
  final String brief;

  /// One sentence tying this chapter back to the book's theme statement.
  final String themeLink;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'brief': brief,
    'themeLink': themeLink,
  };
}

class BookPlan {
  BookPlan({
    required this.title,
    required this.subtitle,
    required this.series,
    required this.tagline,
    required this.theme,
    required this.description,
    required this.shortDescription,
    required this.bisac,
    required this.keywords,
    required this.targetReader,
    required this.compTitles,
    required this.minAge,
    required this.mature,
    required this.priceUsd,
    required this.authorBio,
    required this.themeStatement,
    required this.styleGuide,
    required this.bible,
    required this.chapters,
    required this.author,
    required this.fiction,
  });

  factory BookPlan.fromJson(
    Map<String, dynamic> j, {
    required String author,
    required bool fiction,
  }) {
    List<String> strs(String key) => ((j[key] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    final List<dynamic> raw = (j['chapters'] as List<dynamic>?) ?? <dynamic>[];
    return BookPlan(
      title: (j['title'] ?? 'Untitled Book').toString().trim(),
      subtitle: (j['subtitle'] ?? '').toString().trim(),
      series: (j['series'] ?? '').toString().trim(),
      tagline: (j['tagline'] ?? '').toString().trim(),
      theme: (j['theme'] ?? (fiction ? 'ember' : 'slate')).toString().trim(),
      description: (j['description'] ?? '').toString().trim(),
      shortDescription: (j['shortDescription'] ?? '').toString().trim(),
      bisac: strs('bisac'),
      keywords: strs('keywords'),
      targetReader: (j['targetReader'] ?? '').toString().trim(),
      compTitles: strs('compTitles'),
      minAge: int.tryParse('${j['minAge']}') ?? 14,
      mature: j['mature'] == true,
      priceUsd: double.tryParse('${j['priceUsd']}') ?? (fiction ? 2.99 : 4.99),
      authorBio: (j['authorBio'] ?? '').toString().trim(),
      themeStatement: (j['themeStatement'] ?? '').toString().trim(),
      styleGuide: (j['styleGuide'] ?? '').toString().trim(),
      bible: (j['bible'] ?? '').toString().trim(),
      chapters: raw
          .map((dynamic e) => ChapterPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
      author: author,
      fiction: fiction,
    );
  }

  final String title;
  final String subtitle;
  final String series;
  final String tagline;
  final String theme;
  final String description;
  final String shortDescription;
  final List<String> bisac;
  final List<String> keywords;
  final String targetReader;
  final List<String> compTitles;
  final int minAge;
  final bool mature;
  final double priceUsd;
  final String authorBio;

  /// The governing idea every chapter, the tone and the cover must serve.
  final String themeStatement;
  final String styleGuide;
  final String bible;
  final List<ChapterPlan> chapters;
  final String author;
  final bool fiction;

  List<String> get chapterTitles =>
      chapters.map((ChapterPlan c) => c.title).toList();

  /// Returns a copy with the theme fields replaced. Used by the Theme panel so
  /// a later cover regeneration, chapter rewrite or editor pass sees the edits.
  BookPlan copyWith({String? themeStatement, List<ChapterPlan>? chapters}) =>
      BookPlan(
        title: title,
        subtitle: subtitle,
        series: series,
        tagline: tagline,
        theme: theme,
        description: description,
        shortDescription: shortDescription,
        bisac: bisac,
        keywords: keywords,
        targetReader: targetReader,
        compTitles: compTitles,
        minAge: minAge,
        mature: mature,
        priceUsd: priceUsd,
        authorBio: authorBio,
        themeStatement: themeStatement ?? this.themeStatement,
        styleGuide: styleGuide,
        bible: bible,
        chapters: chapters ?? this.chapters,
        author: author,
        fiction: fiction,
      );

  String get slug {
    final String s = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    final String t = s.replaceAll(RegExp(r'^-|-$'), '');
    return t.isEmpty ? 'book' : t;
  }

  String get fileStem {
    final String s = title
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return s.isEmpty ? 'Book' : s;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'subtitle': subtitle,
    'series': series,
    'tagline': tagline,
    'theme': theme,
    'description': description,
    'shortDescription': shortDescription,
    'bisac': bisac,
    'keywords': keywords,
    'targetReader': targetReader,
    'compTitles': compTitles,
    'minAge': minAge,
    'mature': mature,
    'priceUsd': priceUsd,
    'authorBio': authorBio,
    'themeStatement': themeStatement,
    'styleGuide': styleGuide,
    'bible': bible,
    'author': author,
    'fiction': fiction,
    'chapters': chapters.map((ChapterPlan c) => c.toJson()).toList(),
  };
}

/// A finished chapter: plan + prose.
class WrittenChapter {
  WrittenChapter(this.title, this.body);
  final String title;
  final String body;
  int get words =>
      body.split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).length;
}
