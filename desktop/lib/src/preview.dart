import 'dart:io';

import 'package:flutter/material.dart';

import 'plan.dart';
import 'writer.dart';

/// Matches the app's signature gold, kept local so [main] can import this
/// file without a cycle.
const Color kGold = Color(0xFFFFC83D);

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

/// The reader - one long sheet of paper you scroll from the cover through
/// every chapter, the way a continuous-scroll ereader behaves. No Next
/// buttons; the footer bar fills as you read.
class BookPreviewDialog extends StatefulWidget {
  const BookPreviewDialog(this.result, {super.key, required this.onOpen});

  final BookResult result;

  /// Opens an artefact (the EPUB file) with the platform handler.
  final void Function(String path) onOpen;

  @override
  BookPreviewDialogState createState() => BookPreviewDialogState();
}

class BookPreviewDialogState extends State<BookPreviewDialog> {
  final ScrollController _scroll = ScrollController();
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final double max = _scroll.position.maxScrollExtent;
    final double p = max <= 0 ? 0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((p - _progress).abs() > 0.005) {
      setState(() => _progress = p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Size screen = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: SizedBox(
        width: 900 < screen.width - 80 ? 900 : screen.width - 80,
        height: 780 < screen.height - 64 ? 780 : screen.height - 64,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(theme),
            if (widget.result.chapters.isNotEmpty) const Divider(height: 1),
            Expanded(
              child: Container(
                color: const Color(0xFF2A2531),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 780),
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
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(56, 44, 56, 44),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _coverBlock(),
                          for (final WrittenChapter ch
                              in widget.result.chapters) ...<Widget>[
                            Text(
                              ch.title,
                              textAlign: TextAlign.left,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: 'Georgia',
                                fontFamilyFallback: const <String>[
                                  'Times New Roman',
                                  'Serif'
                                ],
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 18),
                            for (final String p in previewParagraphs(ch.body))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Text(
                                  p,
                                  style: _bodyStyle(theme),
                                  textAlign: TextAlign.justify,
                                ),
                              ),
                            const SizedBox(height: 30),
                          ],
                        ],
                      ),
                    ),
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

  TextStyle _bodyStyle(ThemeData theme) =>
      theme.textTheme.bodyMedium!.copyWith(
        fontFamily: 'Georgia',
        fontFamilyFallback: const <String>['Times New Roman', 'Serif'],
        height: 1.62,
        fontSize: 16,
      );

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
            onPressed: () => widget.onOpen(widget.result.epubPath),
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
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Row(
        children: <Widget>[
          Icon(Icons.swipe_up, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scroll to read - scroll straight from the cover to the last '
              'chapter.',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  /// The top of the sheet: the actual generated cover, full width.
  Widget _coverBlock() {
    final File f = File(widget.result.coverPath);
    Widget inner;
    if (f.existsSync()) {
      inner = Image.file(
        f,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      inner = const SizedBox(
        height: 480,
        child: Center(child: FlutterLogo()),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 34),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: AspectRatio(
          aspectRatio: 1600 / 2560,
          child: inner,
        ),
      ),
    );
  }
}

/// Entry point for the "Preview book" button.
void showBookPreview(
  BuildContext context,
  BookResult result, {
  required void Function(String path) onOpen,
}) {
  showDialog<void>(
    context: context,
    builder: (BuildContext ctx) =>
        BookPreviewDialog(result, onOpen: onOpen),
  );
}
