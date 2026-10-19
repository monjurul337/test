import 'dart:io';

import 'package:flutter/material.dart';

import 'plan.dart';
import 'writer.dart';

/// A "how will this look in the store" preview of the finished book: the
/// real cover, the chapters typeset like an ebook (serif, justified, page
/// numbers), paged like Google Play Books.
class _PreviewPage {
  const _PreviewPage.text(this.heading, this.paragraphs) : isCover = false;

  const _PreviewPage.cover()
      : heading = null,
        paragraphs = const <String>[],
        isCover = true;

  final String? heading;
  final List<String> paragraphs;
  final bool isCover;
}

/// Strips light Markdown so prose reads cleanly (bold/italics markers,
/// stray heading marks, horizontal rules).
List<String> _paragraphs(String body) {
  final String cleaned = body
      .replaceAllMapped(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll('---', '');
  return cleaned
      .split('\n')
      .map((String l) => l.trim().replaceAll('**', '').replaceAll('~~', ''))
      .where((String l) => l.isNotEmpty)
      .toList();
}

/// Pages: cover first, then the chapters filled with paragraphs - the same
/// chapter flow an ereader paginates.
List<_PreviewPage> paginatePreview(
  List<WrittenChapter> chapters, {
  int wordsPerPage = 300,
}) {
  final List<_PreviewPage> pages = <_PreviewPage>[_PreviewPage.cover()];
  for (int i = 0; i < chapters.length; i++) {
    final List<String> paras = _paragraphs(chapters[i].body);
    List<String> current = <String>[];
    int words = 0;
    bool firstPage = true;
    void flush() {
      if (current.isEmpty) return;
      pages.add(_PreviewPage.text(
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
  return pages;
}

/// The paged reader - close enough to the Play Books paper style.
class BookPreviewDialog extends StatefulWidget {
  const BookPreviewDialog(this.result, {super.key, required this.onOpenFolder});

  final BookResult result;
  final void Function(String path) onOpenFolder;

  @override
  State<BookPreviewDialog> createState() => _BookPreviewDialogState();
}

class _BookPreviewDialogState extends State<BookPreviewDialog> {
  late final List<_PreviewPage> _pages;
  final PageController _controller = PageController();
  int _index = 0;

  static const int wordsPerPage = 300;

  @override
  void initState() {
    super.initState();
    _pages = paginatePreview(widget.result.chapters, wordsPerPage: wordsPerPage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 780),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
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
                    onPressed: () =>
                        widget.onOpenFolder(widget.result.epubPath),
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
            ),
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
                        ? _coverPage()
                        : _textPage(context, _pages[i], i),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Rough Google Play Books look - final spacing is set '
                      'by the reader.',
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
            ),
          ],
        ),
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
  Widget _coverPage() {
    final File f = File(widget.result.coverPath);
    if (!f.existsSync()) {
      return const SizedBox(
        width: 240,
        child: Card(child: SizedBox(height: 360)),
      );
    }
    return Image.file(f, fit: BoxFit.contain);
  }

  Widget _textPage(BuildContext context, _PreviewPage page, int no) {
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
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
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
