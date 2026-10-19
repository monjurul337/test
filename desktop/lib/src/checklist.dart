import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'metadata.dart';

/// Everything the storefront asks for, grouped, with a copy button on every
/// field. Generated from the same list that writes metadata.txt.
class PublishChecklist extends StatelessWidget {
  const PublishChecklist({
    super.key,
    required this.fields,
    required this.onCopied,
  });

  final List<PublishField> fields;
  final void Function(String label) onCopied;

  static const Color _gold = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> groups = PublishFields.groups
        .where((String g) => fields.any((PublishField f) => f.group == g))
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.18)),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.checklist, size: 18, color: _gold),
              const SizedBox(width: 8),
              Text(
                'Everything you need to publish',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: _gold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StepList(steps: PublishFields.steps),
          const SizedBox(height: 6),
          for (final String group in groups) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Text(
                group.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.6,
                  color: _gold.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final PublishField f
                in fields.where((PublishField x) => x.group == group))
              _FieldRow(field: f, onCopied: onCopied),
          ],
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: PublishChecklist._gold.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(steps[i], style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.onCopied});

  final PublishField field;
  final void Function(String label) onCopied;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  field.label,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  field.value,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (field.hint.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    field.hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: field.value));
              onCopied(field.label);
            },
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}
