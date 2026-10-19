import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'cover.dart';
import 'epub.dart';
import 'gemini.dart';
import 'metadata.dart';
import 'plan.dart';
import 'prompts.dart';

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
    this.themeOverride,
    this.note = '',
  });

  final String topic;
  final String author;
  final bool fiction;
  final int chapters;
  final int totalWords;
  final String model;
  final String? themeOverride;
  final String note;
}

class BookResult {
  BookResult(this.plan, this.directory, this.epubPath, this.coverPath,
      this.metadataPath, this.words);
  final BookPlan plan;
  final String directory;
  final String epubPath;
  final String coverPath;
  final String metadataPath;
  final int words;
}

class BookWriter {
  BookWriter({required this.apiKey, required this.outputRoot});

  final String apiKey;
  final String outputRoot;

  bool _cancelled = false;
  void cancel() => _cancelled = true;

  void _check() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<BookResult> run(BookRequest req, ProgressFn progress) async {
    final Gemini g = Gemini(apiKey, model: req.model);

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
    progress(0.90, 'Rendering the cover...');
    final Uint8List png = await CoverRenderer.render(
      title: plan.title,
      subtitle: plan.subtitle,
      series: plan.series,
      tagline: plan.tagline,
      author: plan.author,
      themeName: req.themeOverride ?? plan.theme,
      fiction: req.fiction,
    );
    final File coverFile = File('${dir.path}/cover.png');
    await coverFile.writeAsBytes(png);

    progress(0.95, 'Building the EPUB...');
    final Uint8List epub = EpubBuilder.build(
      plan: plan,
      chapters: written,
      coverPng: png,
      uuid: _uuid(),
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
    ));

    progress(1.0, 'Done: $words words, ${written.length} chapters.');
    return BookResult(plan, dir.path, epubFile.path, coverFile.path,
        metaFile.path, words);
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

class _Cancelled implements Exception {
  const _Cancelled();
  @override
  String toString() => 'Cancelled';
}
