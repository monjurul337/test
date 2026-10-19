import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'plan.dart';
import 'writer.dart';

/// Matches the app's signature gold, kept local so [main] can import this
/// file without a cycle.
const Color kGold = Color(0xFFFFC83D);

/// A "how will this look in the store" preview of the finished book: the
/// real cover, the chapters typeset like an ebook (serif, justified, page
/// numbers), paged like Google Play Books.
class PreviewPage {
  const PreviewPage.text(this.heading, this.paragraphs) : isCover = false;

  const PreviewPage.cover()
      : heading = null,
        paragraphs = const <String>[],
        isCover = true;

  final String? heading;
  final List<String> paragraphs;
  final bool isCover;
}

/// Strips light Markdown so prose reads cleanly (bold/italics markers,
/// stray heading marks, horizontal rules).
List<String> previewParagraphs(String body) {
  final String cleaned = body
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll('---', '');
  return cleaned
      .split('\n')
      .map((String l) => l.trim().replaceAll('**', '').replaceAll('~~', ''))
      .where((String l) => l.isNotEmpty)
      .toList();
}

/// Pages: cover first, then the chapters filled with paragraphs - the same
/// chapter flow an ereader paginates.
List<PreviewPage> paginatePreview(
  List<WrittenChapter> chapters, {
  int wordsPerPage = 300,
}) {
  final List<PreviewPage> pages = <PreviewPage>[const PreviewPage.cover()];
  for (int i = 0; i < chapters.length; i++) {
    final List<String> paras = previewParagraphs(chapters[i].body);
    List<String> current = <String>[];
    int words = 0;
    bool firstPage = true;
    void flush() {
      if (current.isEmpty) return;
      pages.add(PreviewPage.text(
          firstPage ? '${i + 1}. ${chapters[i].title}' : null, current));
      firstPage = false;
      current = <String>[];
      words = 0;
    }

    for (final String p in paras) {
      final int w =
          p.split(RegExp(r'\s+')).where((String s) => s.isNotEmpty).length;
      if (words + w > wordsPerPage && current.isNotEmpty) flush();
      current.add(p);
      words += w;
    }
    flush();
  }
  if (pages.length == 1) {
    // Never hand the pager an empty book.
    pages.add(const PreviewPage.text(
        'No chapters yet', <String>['This book has no written chapters.']));
  }
  return pages;
}

/// The paged reader - close enough to the Play Books paper style.
class BookPreviewDialog extends StatefulWidget {
  const BookPreviewDialog(this.result, {super.key, required this.onOpenFolder});

  final BookResult result;
  final void Function(String path) onOpenFolder;

  @override
  BookPreviewDialogState createState() => BookPreviewDialogState();
}

class BookPreviewDialogState extends State<BookPreviewDialog> {
  static const int wordsPerPage = 300;
  static const double maxWidth = 900;
  static const double maxHeight = 780;

  final PageController _controller = PageController();
  int _index = 0;
  List<PreviewPage> _pages = const <PreviewPage>[];

  @override
  void initState() {
    super.initState();
    // Never let one bad chapter blank the whole reader.
    try {
      _pages = paginatePreview(widget.result.chapters,
          wordsPerPage: wordsPerPage);
    } catch (_) {
      _pages = <PreviewPage>[
        const PreviewPage.cover(),
        const PreviewPage.text(
            'Preview unavailable', <String>['The chapters could not be read.']),
      ];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Size screen = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: SizedBox(
        width: math.min(maxWidth, screen.width - 80),
        height: math.min(maxHeight, screen.height - 64),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(theme),
            const Divider(height: 1),
            Expanded(
              child: Container(
                color: const Color(0xFF2A2531),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (int i) => setState(() => _index = i),
                  itemBuilder: (BuildContext context, int i) => Center(
                    child: _pages[i].isCover
                        ? _coverPage(theme)
                        : _textPage(context, _pages[i], i),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
      child: Row(
        children: <Widget>[
          Icon(Icons.menu_book_outlined,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Preview - ${widget.result.plan.title}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: () => widget.onOpenFolder(widget.result.epubPath),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const Text('Open EPUB'),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _footer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'Rough Google Play Books look - final spacing is set by the '
              'reader.',
              style: theme.textTheme.labelSmall,
            ),
          ),
          TextButton(
            onPressed: () => _flip(-1),
            child: const Text('Prev'),
          ),
          Text('${_index + 1} / ${_pages.length}',
              style: theme.textTheme.labelSmall),
          TextButton(
            onPressed: () => _flip(1),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  void _flip(int dir) {
    final int target = (_index + dir).clamp(0, _pages.length - 1);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// Page 1 - the actual generated cover art straight from disk.
  Widget _coverPage(ThemeData theme) {
    final File f = File(widget.result.coverPath);
    if (!f.existsSync()) {
      return _coverPlaceholder(theme);
    }
    return Image.file(
      f,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _coverPlaceholder(theme),
    );
  }

  Widget _coverPlaceholder(ThemeData theme) => Container(
        width: 260,
        height: 400,
        decoration: BoxDecoration(
          color: const Color(0xFF1D1826),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: kGold.withValues(alpha: 0.3)),
        ),
        alignment: Alignment.center,
        child: Text('No cover yet',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.primary)),
      );

  Widget _textPage(BuildContext context, PreviewPage page, int no) {
    final ThemeData theme = Theme.of(context);
    final TextStyle body = theme.textTheme.bodyMedium!.copyWith(
      fontFamily: 'Georgia',
      fontFamilyFallback: const <String>['Times New Roman', 'Serif'],
      height: 1.62,
      fontSize: page.paragraphs.length > 6 ? 14 : 16,
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
      constraints: const BoxConstraints(maxWidth: 720),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x59000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (page.heading != null) ...<Widget>[
            Text(
              page.heading!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Georgia',
                fontFamilyFallback: const <String>['Times New Roman', 'Serif'],
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final String p in page.paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(p, style: body, textAlign: TextAlign.justify),
                    ),
                ],
              ),
            ),
          ),
          Text(
            '${no + 1}',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry point for the "Preview book" button.
void showBookPreview(
  BuildContext context,
  BookResult result, {
  required void Function(String path) onOpenFolder,
}) {
  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) =>
        BookPreviewDialog(result, onOpenFolder: onOpenFolder),
  );
}
