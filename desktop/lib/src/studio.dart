import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'cover.dart';
import 'plan.dart';
import 'writer.dart';

/// What the cover studio hands back when you accept a cover.
class ChosenCover {
  ChosenCover(this.style, this.png);
  final CoverStyle style;
  final Uint8List png;
}

/// Four generated options plus manual theme, layout, font and shuffle
/// controls. Nothing is written to disk until the caller applies the result.
Future<ChosenCover?> showCoverStudio({
  required BuildContext context,
  required BookWriter writer,
  required BookResult result,
}) {
  return showDialog<ChosenCover>(
    context: context,
    builder: (BuildContext ctx) =>
        _CoverStudio(writer: writer, result: result),
  );
}

class _CoverStudio extends StatefulWidget {
  const _CoverStudio({required this.writer, required this.result});
  final BookWriter writer;
  final BookResult result;

  @override
  State<_CoverStudio> createState() => _CoverStudioState();
}

class _CoverStudioState extends State<_CoverStudio> {
  List<CoverVariant> _variants = <CoverVariant>[];
  int _selected = 0;
  bool _loading = true;
  bool _rendering = false;
  late CoverStyle _style;
  Uint8List? _custom;

  @override
  void initState() {
    super.initState();
    _style = widget.result.coverStyle;
    _load();
  }

  Future<void> _load() async {
    final List<CoverVariant> v = await widget.writer.coverVariants(widget.result);
    if (!mounted) return;
    setState(() {
      _variants = v;
      _style = v.first.style;
      _loading = false;
    });
  }

  Future<void> _renderCustom() async {
    setState(() => _rendering = true);
    final BookPlan p = widget.result.plan;
    final Uint8List png = await CoverRenderer.render(
      title: p.title,
      subtitle: p.subtitle,
      series: p.series,
      tagline: p.tagline,
      author: p.author,
      themeName: _style.theme == 'auto' ? p.theme : _style.theme,
      fiction: widget.result.request.fiction,
      style: _style,
    );
    if (!mounted) return;
    setState(() {
      _custom = png;
      _selected = -1;
      _rendering = false;
    });
  }

  Uint8List? get _current =>
      _selected >= 0 && _selected < _variants.length
          ? _variants[_selected].png
          : _custom;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Cover studio'),
      content: SizedBox(
        width: 720,
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Pick one of the four, or build your own below. '
                      'The chosen cover is written into the EPUB and the ZIP.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (int i = 0; i < _variants.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _thumb(
                                theme,
                                _variants[i].png,
                                _variants[i].style.label,
                                _selected == i,
                                () => setState(() {
                                  _selected = i;
                                  _style = _variants[i].style;
                                }),
                              ),
                            ),
                          ),
                        if (_custom != null)
                          Expanded(
                            child: _thumb(theme, _custom!, 'custom',
                                _selected == -1, () => setState(() => _selected = -1)),
                          ),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: CoverTheme.all.containsKey(_style.theme)
                                ? _style.theme
                                : CoverTheme.all.keys.first,
                            decoration: const InputDecoration(labelText: 'Colour'),
                            items: CoverTheme.all.keys
                                .map((String t) => DropdownMenuItem<String>(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: (String? v) =>
                                setState(() => _style = _style.copyWith(theme: v)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _style.layout,
                            decoration: const InputDecoration(labelText: 'Layout'),
                            items: CoverStyle.layouts
                                .map((String t) => DropdownMenuItem<String>(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: (String? v) =>
                                setState(() => _style = _style.copyWith(layout: v)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _style.font,
                            decoration: const InputDecoration(labelText: 'Font'),
                            items: CoverStyle.fonts
                                .map((String t) => DropdownMenuItem<String>(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: (String? v) =>
                                setState(() => _style = _style.copyWith(font: v)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _rendering
                              ? null
                              : () {
                                  _style = _style.copyWith(
                                      seed: DateTime.now().millisecondsSinceEpoch %
                                          100000);
                                  _renderCustom();
                                },
                          icon: const Icon(Icons.casino_outlined),
                          label: const Text('Shuffle art'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: _rendering ? null : _renderCustom,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Preview my settings'),
                        ),
                        if (_rendering) ...<Widget>[
                          const SizedBox(width: 14),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _current == null
              ? null
              : () => Navigator.pop(
                  context, ChosenCover(_style, _current!)),
          child: const Text('Use this cover'),
        ),
      ],
    );
  }

  Widget _thumb(ThemeData theme, Uint8List png, String label, bool on,
      VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: on
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: on ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: 1600 / 2560,
              child: Image.memory(png, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// The editor report, with a one-tap rewrite for every chapter it complains
/// about.
class QualityCard extends StatelessWidget {
  const QualityCard({
    super.key,
    required this.report,
    required this.onFix,
    this.busy = false,
  });

  final QualityReport report;

  /// (chapter index starting at 0, the instruction to the writer)
  final void Function(int, String) onFix;
  final bool busy;

  Color _colour(String severity, ColorScheme c) => switch (severity) {
        'high' => const Color(0xFFFF6B6B),
        'medium' => const Color(0xFFFFC83D),
        _ => c.outline,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.fact_check_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Editor report',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
                const Spacer(),
                Text('${report.score}/100',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(report.verdict, style: theme.textTheme.bodySmall),
            if (report.issues.isEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('No issues found.', style: theme.textTheme.bodySmall),
            ],
            for (final QualityIssue i in report.issues) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 4,
                    height: 38,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    color: _colour(i.severity, theme.colorScheme),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${i.severity.toUpperCase()}  ${i.type}'
                          '${i.chapter == 0 ? '' : '  -  chapter ${i.chapter}'}',
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(i.detail, style: theme.textTheme.bodySmall),
                        if (i.fix.isNotEmpty)
                          Text('Fix: ${i.fix}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  if (i.chapter > 0)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => onFix(
                              i.chapter - 1,
                              '${i.detail}\n\nRequired fix: ${i.fix}'),
                      child: Text('Rewrite ${i.chapter}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
