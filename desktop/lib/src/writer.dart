import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'cover.dart';
import 'epub.dart';
import 'gemini.dart';
import 'imagegen.dart';
import 'llm.dart';
import 'metadata.dart';
import 'plan.dart';
import 'prompts.dart';
import 'zipwriter.dart';

/// Progress callback: ([fraction 0..1], message).
typedef ProgressFn = void Function(double, String);

class BookRequest {
  BookRequest({
    required this.topic,
    required this.author,
    required this.fiction,
    required this.chapters,
    required this.totalWords,
    required this.model,
    this.provider = Providers.gemini,
    this.coverArtModel = ImageGen.off,
    this.themeOverride,
    this.note = '',
    this.extras = const BookExtras(),
  });

  final String topic;
  final String author;
  final bool fiction;
  final int chapters;
  final int totalWords;
  final String model;

  /// gemini | nvidia - see [Providers].
  final String provider;

  /// Image model for the cover artwork, or [ImageGen.off] for the built-in
  /// geometric cover.
  final String coverArtModel;
  final String? themeOverride;
  final String note;

  /// Copyright page, bio, also-by and the review request.
  final BookExtras extras;
}

/// One problem the editor pass found.
class QualityIssue {
  QualityIssue(this.chapter, this.type, this.severity, this.detail, this.fix);

  factory QualityIssue.fromJson(Map<String, dynamic> j) => QualityIssue(
        (j['chapter'] as num?)?.toInt() ?? 0,
        (j['type'] ?? 'other').toString(),
        (j['severity'] ?? 'low').toString(),
        (j['detail'] ?? '').toString(),
        (j['fix'] ?? '').toString(),
      );

  /// 1-based chapter number, or 0 for a whole-book note.
  final int chapter;
  final String type;
  final String severity;
  final String detail;
  final String fix;

  int get rank => severity == 'high' ? 0 : (severity == 'medium' ? 1 : 2);
}

/// The result of the editor pass.
class QualityReport {
  QualityReport(this.score, this.verdict, this.strengths, this.issues);

  factory QualityReport.fromJson(Map<String, dynamic> j) {
    final List<QualityIssue> issues = <QualityIssue>[
      for (final dynamic i in (j['issues'] as List<dynamic>?) ?? <dynamic>[])
        QualityIssue.fromJson(i as Map<String, dynamic>)
    ]..sort((QualityIssue a, QualityIssue b) => a.rank.compareTo(b.rank));
    return QualityReport(
      (j['score'] as num?)?.toInt() ?? 0,
      (j['verdict'] ?? '').toString(),
      <String>[
        for (final dynamic s in (j['strengths'] as List<dynamic>?) ?? <dynamic>[])
          s.toString()
      ],
      issues,
    );
  }

  final int score;
  final String verdict;
  final List<String> strengths;
  final List<QualityIssue> issues;

  int get high => issues.where((QualityIssue i) => i.severity == 'high').length;

  String toMarkdown(String title) {
    final StringBuffer b = StringBuffer()
      ..writeln('# Editor report - $title')
      ..writeln()
      ..writeln('**Score:** $score/100')
      ..writeln()
      ..writeln(verdict)
      ..writeln();
    if (strengths.isNotEmpty) {
      b.writeln('## What works');
      for (final String s in strengths) {
        b.writeln('- $s');
      }
      b.writeln();
    }
    b.writeln('## Issues (${issues.length})');
    if (issues.isEmpty) {
      b.writeln();
      b.writeln('None found.');
    }
    for (final QualityIssue i in issues) {
      b
        ..writeln()
        ..writeln('### ${i.severity.toUpperCase()} - ${i.type} - '
            '${i.chapter == 0 ? 'whole book' : 'chapter ${i.chapter}'}')
        ..writeln(i.detail)
        ..writeln()
        ..writeln('**Fix:** ${i.fix}');
    }
    return b.toString();
  }
}

class BookResult {
  BookResult({
    required this.request,
    required this.plan,
    required this.directory,
    required this.epubPath,
    required this.coverPath,
    required this.metadataPath,
    required this.zipPath,
    required this.words,
    required this.chapters,
    required this.summary,
    required this.coverStyle,
    this.artwork,
    this.artPrompt = '',
    this.report,
    this.reportPath,
  });

  /// Kept so a chapter can be rewritten or a cover reskinned later.
  final BookRequest request;
  final BookPlan plan;
  final String directory;
  final String epubPath;
  final String coverPath;
  final String metadataPath;

  /// One zip with the EPUB, the cover, the metadata sheet and the sources.
  final String zipPath;
  final int words;
  final List<WrittenChapter> chapters;
  final String summary;
  final CoverStyle coverStyle;

  /// The generated cover painting, if any, kept so the cover studio can
  /// restyle the type without paying for a new picture.
  final Uint8List? artwork;
  final String artPrompt;
  final QualityReport? report;
  final String? reportPath;

  BookResult copyWith({
    QualityReport? report,
    String? reportPath,
  }) =>
      BookResult(
        request: request,
        plan: plan,
        directory: directory,
        epubPath: epubPath,
        coverPath: coverPath,
        metadataPath: metadataPath,
        zipPath: zipPath,
        words: words,
        chapters: chapters,
        summary: summary,
        coverStyle: coverStyle,
        artwork: artwork,
        artPrompt: artPrompt,
        report: report ?? this.report,
        reportPath: reportPath ?? this.reportPath,
      );
}

/// Zips several finished books into one archive, for batch runs.
Future<String> packBatch(List<BookResult> results, String outputRoot) async {
  final ZipWriter kit = ZipWriter();
  for (final BookResult r in results) {
    final Directory d = Directory(r.directory);
    if (!d.existsSync()) continue;
    final String stem =
        d.path.split(Platform.pathSeparator).where((String s) => s.isNotEmpty).last;
    for (final FileSystemEntity e in d.listSync(recursive: true)) {
      if (e is! File) continue;
      if (e.path.toLowerCase().endsWith('.zip')) continue;
      final String rel = e.path
          .substring(d.path.length + 1)
          .replaceAll('\\', '/');
      kit.addBytes('$stem/$rel', await e.readAsBytes());
    }
  }
  final DateTime now = DateTime.now();
  final String stamp = '${now.year}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final File out = File('$outputRoot${Platform.pathSeparator}'
      'batch-$stamp-${results.length}-books.zip');
  await out.writeAsBytes(kit.finish());
  return out.path;
}

class BookWriter {
  BookWriter({required this.apiKey, required this.outputRoot});

  final String apiKey;
  final String outputRoot;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  void _check() {
    if (_cancelled) throw const BookCancelled();
  }

  Future<BookResult> run(BookRequest req, ProgressFn progress) async {
    final LlmClient g =
        createClient(provider: req.provider, keys: apiKey, model: req.model);

    progress(0.02, 'Planning the book...');
    final Map<String, dynamic> planJson = await g.generateJson(
      Prompts.plan(
        topic: req.topic,
        fiction: req.fiction,
        chapters: req.chapters,
        totalWords: req.totalWords,
        author: req.author,
        note: req.note,
      ),
      system: Prompts.planSystem,
      temperature: 0.95,
      thinking: 4096,
      log: (String m) => progress(0.02, m),
    );
    _check();

    BookPlan plan =
        BookPlan.fromJson(planJson, author: req.author, fiction: req.fiction);
    if (plan.chapters.isEmpty) {
      throw GeminiException('The planner returned no chapters. Try again.');
    }

    final Directory dir = Directory('$outputRoot/${plan.slug}');
    await dir.create(recursive: true);
    await File('${dir.path}/plan.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(plan.toJson()));

    progress(0.08, 'Title: ${plan.title}  (${plan.chapters.length} chapters)');

    final int per = max(400, req.totalWords ~/ plan.chapters.length);
    final List<WrittenChapter> written = <WrittenChapter>[];
    String soFar = '';
    final String system =
        req.fiction ? Prompts.fictionSystem : Prompts.nonfictionSystem;

    for (int i = 0; i < plan.chapters.length; i++) {
      _check();
      final ChapterPlan ch = plan.chapters[i];
      final double frac = 0.10 + 0.78 * (i / plan.chapters.length);
      progress(frac, 'Chapter ${i + 1}/${plan.chapters.length}: ${ch.title}');

      String body = await g.generate(
        Prompts.chapter(
          title: plan.title,
          subtitle: plan.subtitle,
          styleGuide: plan.styleGuide,
          bible: plan.bible,
          chapterTitles: plan.chapterTitles,
          storySoFar: soFar,
          index: i,
          chapterTitle: ch.title,
          brief: ch.brief,
          wordsTarget: per,
          fiction: req.fiction,
        ),
        system: system,
        temperature: 0.92,
        maxTokens: 16384,
        log: (String m) => progress(frac, m),
      );
      body = _stripHeading(body, ch.title);
      written.add(WrittenChapter(ch.title, body));

      final File md = File(
          '${dir.path}/chapters/${(i + 1).toString().padLeft(2, '0')}-${_slug(ch.title)}.md');
      await md.create(recursive: true);
      await md.writeAsString('# ${ch.title}\n\n$body\n');

      if (i + 1 < plan.chapters.length) {
        _check();
        soFar = await g.generate(
          Prompts.summary(soFar, body),
          temperature: 0.3,
          maxTokens: 2048,
        );
        await File('${dir.path}/summary.txt').writeAsString(soFar);
      }
    }

    _check();
    Uint8List? artwork;
    String artPrompt = '';
    if (req.coverArtModel != ImageGen.off) {
      progress(0.88, 'Painting the cover artwork...');
      try {
        artPrompt = (await g.generate(
          Prompts.coverArt(
            title: plan.title,
            subtitle: plan.subtitle,
            genre: plan.bisac.isEmpty ? '' : plan.bisac.first,
            bible: plan.bible,
            fiction: req.fiction,
          ),
          temperature: 0.9,
          maxTokens: 512,
        ))
            .trim();
        artwork = await ImageGen(
          provider: req.provider,
          keys: apiKey,
          model: req.coverArtModel,
        ).render(artPrompt, log: (String m) => progress(0.88, m));
        await File('${dir.path}/cover-art.png').writeAsBytes(artwork);
        progress(0.89, 'Artwork ready.');
      } catch (e) {
        progress(0.89, 'Cover art failed ($e) - using the built-in cover.');
        artwork = null;
      }
    }

    return _finish(
      req: req,
      plan: plan,
      written: written,
      soFar: soFar,
      dir: dir,
      style: CoverStyle(theme: req.themeOverride ?? plan.theme),
      progress: progress,
      artwork: artwork,
      artPrompt: artPrompt,
    );
  }

  /// Paints a fresh cover picture for a finished book and rebuilds it.
  Future<BookResult> regenerateArtwork(
    BookResult r,
    ProgressFn progress, {
    String? promptOverride,
  }) async {
    _cancelled = false;
    final BookRequest req = r.request;
    if (req.coverArtModel == ImageGen.off) {
      throw LlmException(
          'Cover art is switched off. Pick an image model before generating.');
    }
    final LlmClient g =
        createClient(provider: req.provider, keys: apiKey, model: req.model);

    progress(0.15, 'Painting new cover artwork...');
    final String prompt = (promptOverride != null && promptOverride.isNotEmpty)
        ? promptOverride
        : (await g.generate(
            Prompts.coverArt(
              title: r.plan.title,
              subtitle: r.plan.subtitle,
              genre: r.plan.bisac.isEmpty ? '' : r.plan.bisac.first,
              bible: r.plan.bible,
              fiction: req.fiction,
            ),
            temperature: 1.0,
            maxTokens: 512,
          ))
            .trim();

    final Uint8List art = await ImageGen(
      provider: req.provider,
      keys: apiKey,
      model: req.coverArtModel,
    ).render(prompt, log: (String m) => progress(0.4, m));
    await File('${r.directory}/cover-art.png').writeAsBytes(art);

    return _finish(
      req: req,
      plan: r.plan,
      written: r.chapters,
      soFar: r.summary,
      dir: Directory(r.directory),
      style: r.coverStyle,
      progress: progress,
      artwork: art,
      artPrompt: prompt,
      report: r.report,
      reportPath: r.reportPath,
    );
  }

  /// Cover -> EPUB -> metadata -> ZIP. Shared by the first run, a chapter
  /// rewrite and the cover studio, so every artefact always matches.
  Future<BookResult> _finish({
    required BookRequest req,
    required BookPlan plan,
    required List<WrittenChapter> written,
    required String soFar,
    required Directory dir,
    required CoverStyle style,
    required ProgressFn progress,
    Uint8List? coverPng,
    Uint8List? artwork,
    String artPrompt = '',
    QualityReport? report,
    String? reportPath,
  }) async {
    progress(0.90, 'Rendering the cover...');
    final Uint8List png = coverPng ??
        await CoverRenderer.render(
          title: plan.title,
          subtitle: plan.subtitle,
          series: plan.series,
          tagline: plan.tagline,
          author: plan.author,
          themeName: style.theme == 'auto' ? plan.theme : style.theme,
          fiction: req.fiction,
          style: style,
          artwork: artwork,
        );
    final File coverFile = File('${dir.path}/cover.png');
    await coverFile.writeAsBytes(png);

    progress(0.95, 'Building the EPUB...');
    final Uint8List epub = EpubBuilder.build(
      plan: plan,
      chapters: written,
      coverPng: png,
      uuid: _uuid(),
      extras: req.extras,
    );
    final String epubName = '${plan.fileStem}.epub';
    final File epubFile = File('${dir.path}/$epubName');
    await epubFile.writeAsBytes(epub);

    progress(0.98, 'Writing the metadata sheet...');
    final int words =
        written.fold<int>(0, (int a, WrittenChapter c) => a + c.words);
    final File metaFile = File('${dir.path}/metadata.txt');
    await metaFile.writeAsString(MetadataSheet.build(
      plan: plan,
      words: words,
      chapterCount: written.length,
      epubName: epubName,
      publisher: req.extras.publisher,
    ));

    // Google Play Books rejects files that break its documented limits, so
    // say so here rather than after a failed upload.
    final List<String> problems = PlayRules.check(
      plan: plan,
      words: words,
      coverWidth: CoverRenderer.width,
      coverHeight: CoverRenderer.height,
      epubBytes: epub.length,
    );
    if (problems.isEmpty) {
      progress(0.985, 'Google Play Books checks passed.');
    } else {
      for (final String msg in problems) {
        progress(0.985, 'PLAY BOOKS WARNING: $msg');
      }
    }

    progress(0.99, 'Packing the publishing kit...');
    final ZipWriter kit = ZipWriter();
    final String stem = plan.fileStem;
    kit.addBytes('$stem/$epubName', epub);
    kit.addBytes('$stem/cover.png', png);
    kit.addString('$stem/metadata.txt', await metaFile.readAsString());
    kit.addString('$stem/plan.json',
        const JsonEncoder.withIndent('  ').convert(plan.toJson()));
    for (int i = 0; i < written.length; i++) {
      kit.addString(
        '$stem/chapters/${(i + 1).toString().padLeft(2, '0')}-'
        '${_slug(written[i].title)}.md',
        '# ${written[i].title}\n\n${written[i].body}\n',
      );
    }
    if (soFar.isNotEmpty) kit.addString('$stem/summary.txt', soFar);
    if (artwork != null) kit.addBytes('$stem/cover-art.png', artwork);
    if (report != null) {
      kit.addString('$stem/quality-report.md', report.toMarkdown(plan.title));
    }
    final File zipFile = File('${dir.path}/$stem-publishing-kit.zip');
    await zipFile.writeAsBytes(kit.finish());

    progress(1.0, 'Done: $words words, ${written.length} chapters.');
    return BookResult(
      request: req,
      plan: plan,
      directory: dir.path,
      epubPath: epubFile.path,
      coverPath: coverFile.path,
      metadataPath: metaFile.path,
      zipPath: zipFile.path,
      words: words,
      chapters: written,
      summary: soFar,
      coverStyle: style,
      artwork: artwork,
      artPrompt: artPrompt,
      report: report,
      reportPath: reportPath,
    );
  }

  /// Rewrites a single chapter and rebuilds every artefact around it.
  Future<BookResult> regenerateChapter(
    BookResult r,
    int index,
    String note,
    ProgressFn progress,
  ) async {
    _cancelled = false;
    final BookPlan plan = r.plan;
    final BookRequest req = r.request;
    final LlmClient g =
        createClient(provider: req.provider, keys: apiKey, model: req.model);
    final ChapterPlan ch = plan.chapters[index];
    final int per = max(400, req.totalWords ~/ plan.chapters.length);

    progress(0.15, 'Rewriting chapter ${index + 1}: ${ch.title}');
    String body = await g.generate(
      Prompts.chapter(
        title: plan.title,
        subtitle: plan.subtitle,
        styleGuide: plan.styleGuide,
        bible: plan.bible,
        chapterTitles: plan.chapterTitles,
        storySoFar: _summaryBefore(r, index),
        index: index,
        chapterTitle: ch.title,
        brief: ch.brief,
        wordsTarget: per,
        fiction: req.fiction,
        revisionNote: note,
        previousDraft: r.chapters[index].body,
      ),
      system: req.fiction ? Prompts.fictionSystem : Prompts.nonfictionSystem,
      temperature: 0.92,
      maxTokens: 16384,
      log: (String m) => progress(0.4, m),
    );
    body = _stripHeading(body, ch.title);
    _check();

    final List<WrittenChapter> written = List<WrittenChapter>.from(r.chapters);
    written[index] = WrittenChapter(ch.title, body);

    final Directory dir = Directory(r.directory);
    final File md = File('${dir.path}/chapters/'
        '${(index + 1).toString().padLeft(2, '0')}-${_slug(ch.title)}.md');
    await md.create(recursive: true);
    await md.writeAsString('# ${ch.title}\n\n$body\n');

    progress(0.75, 'Rebuilding the book...');
    return _finish(
      req: req,
      plan: plan,
      written: written,
      soFar: r.summary,
      dir: dir,
      style: r.coverStyle,
      progress: progress,
      artwork: r.artwork,
      artPrompt: r.artPrompt,
      report: r.report,
      reportPath: r.reportPath,
    );
  }

  /// Everything the reader knew before [index]. Cheap stand-in for the running
  /// summary, which only exists for the full run.
  String _summaryBefore(BookResult r, int index) {
    if (index == 0) return '';
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < index; i++) {
      final String body = r.chapters[i].body;
      b.writeln('Chapter ${i + 1} - ${r.chapters[i].title}: '
          '${body.length > 700 ? '${body.substring(0, 700)}...' : body}');
      b.writeln();
    }
    final String out = b.toString();
    return out.length > 9000 ? out.substring(out.length - 9000) : out;
  }

  /// Reads the finished manuscript back and reports what a reviewer would
  /// complain about.
  Future<BookResult> qualityPass(BookResult r, ProgressFn progress) async {
    _cancelled = false;
    final LlmClient g = createClient(
        provider: r.request.provider, keys: apiKey, model: r.request.model);
    progress(0.1, 'Editor pass: reading the whole manuscript...');

    final StringBuffer ms = StringBuffer();
    for (int i = 0; i < r.chapters.length; i++) {
      ms
        ..writeln('--- CHAPTER ${i + 1}: ${r.chapters[i].title} ---')
        ..writeln(r.chapters[i].body)
        ..writeln();
    }

    final Map<String, dynamic> j = await g.generateJson(
      Prompts.quality(
        title: r.plan.title,
        bible: r.plan.bible,
        fiction: r.request.fiction,
        chapterTitles: r.plan.chapterTitles,
        manuscript: ms.toString(),
      ),
      system: Prompts.editorSystem,
      temperature: 0.25,
      maxTokens: 16384,
      thinking: 4096,
      log: (String m) => progress(0.5, m),
    );
    _check();

    final QualityReport report = QualityReport.fromJson(j);
    final File out = File('${r.directory}/quality-report.md');
    await out.writeAsString(report.toMarkdown(r.plan.title));
    progress(1.0,
        'Editor pass: ${report.score}/100, ${report.issues.length} issues.');
    return r.copyWith(report: report, reportPath: out.path);
  }

  /// Four covers to choose from: the current one plus three honest alternatives.
  Future<List<CoverVariant>> coverVariants(BookResult r) async {
    final List<String> themes = CoverTheme.all.keys.toList();
    final String current =
        r.coverStyle.theme == 'auto' ? r.plan.theme : r.coverStyle.theme;
    final int at = themes.indexOf(current) < 0 ? 0 : themes.indexOf(current);
    final List<CoverStyle> styles = <CoverStyle>[
      CoverStyle(theme: current, layout: r.coverStyle.layout, seed: r.coverStyle.seed),
      CoverStyle(theme: current, layout: 'bottom', font: 'sans', seed: 7),
      CoverStyle(theme: themes[(at + 2) % themes.length], layout: 'center', seed: 19),
      CoverStyle(theme: themes[(at + 4) % themes.length], layout: 'left', font: 'serif', seed: 73),
    ];
    final List<CoverVariant> out = <CoverVariant>[];
    for (final CoverStyle st in styles) {
      out.add(CoverVariant(
        st,
        await CoverRenderer.render(
          title: r.plan.title,
          subtitle: r.plan.subtitle,
          series: r.plan.series,
          tagline: r.plan.tagline,
          author: r.plan.author,
          themeName: st.theme,
          fiction: r.request.fiction,
          style: st,
          artwork: r.artwork,
        ),
      ));
    }
    return out;
  }

  /// Swaps the cover and rebuilds the EPUB, the metadata sheet and the ZIP.
  Future<BookResult> applyCoverStyle(
    BookResult r,
    CoverStyle style,
    ProgressFn progress, {
    Uint8List? png,
  }) async {
    _cancelled = false;
    progress(0.2, 'Applying the new cover...');
    return _finish(
      req: r.request,
      plan: r.plan,
      written: r.chapters,
      soFar: r.summary,
      dir: Directory(r.directory),
      style: style,
      coverPng: png,
      progress: progress,
      artwork: r.artwork,
      artPrompt: r.artPrompt,
      report: r.report,
      reportPath: r.reportPath,
    );
  }

  static String _stripHeading(String body, String title) {
    String s = body.trim();
    final RegExp h = RegExp(
        r'^\s*#{1,3}\s*(chapter\s*\d+\s*[:.\-]?\s*)?' +
            RegExp.escape(title) +
            r'\s*$',
        caseSensitive: false,
        multiLine: true);
    s = s.replaceFirst(h, '').trim();
    if (s.startsWith('# ')) {
      final int nl = s.indexOf('\n');
      s = nl == -1 ? '' : s.substring(nl + 1).trim();
    }
    return s;
  }

  static String _slug(String s) {
    final String t = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final String cut = t.length > 40 ? t.substring(0, 40) : t;
    return cut.isEmpty ? 'chapter' : cut;
  }

  static String _uuid() {
    final Random r = Random.secure();
    String hex(int n) => List<String>.generate(
        n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }
}

/// Thrown when the user cancels a run; a batch treats it as "stop here".
class BookCancelled implements Exception {
  const BookCancelled();
  @override
  String toString() => 'Cancelled';
}
