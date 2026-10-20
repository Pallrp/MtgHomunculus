import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../theme/picker_tokens.dart';
import 'attribute_chips.dart';
import 'deckbox_rows.dart';

/// *Which Llanowar Elves?* (M3) — a card scanned into **To remove** matches
/// several rows on Deckbox. The app never picks between them; the user does.
///
/// **One tap**: tapping a row stages from it and closes (decided 2026-10-16 —
/// select-then-confirm was a tap too many). Closing the sheet — down, back,
/// or outside it — skips the card. Closed with the row, or null when skipped.
///
/// A row whose every copy is already staged is shown but cannot be picked.
class WhichCopySheet extends StatelessWidget {
  const WhichCopySheet({
    super.key,
    required this.name,
    required this.subtitle,
    required this.rows,
    required this.countOf,
    required this.stagedOf,
  });

  final String name;
  final String subtitle;
  final List<ExternalEntry> rows;
  final int Function(ExternalEntry) countOf;
  final int Function(ExternalEntry) stagedOf;

  static Future<ExternalEntry?> show(
    BuildContext context, {
    required String name,
    required String subtitle,
    required List<ExternalEntry> rows,
    required int Function(ExternalEntry) countOf,
    required int Function(ExternalEntry) stagedOf,
  }) =>
      showModalBottomSheet<ExternalEntry>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => WhichCopySheet(
          name: name,
          subtitle: subtitle,
          rows: rows,
          countOf: countOf,
          stagedOf: stagedOf,
        ),
      );

  bool _open(ExternalEntry e) => countOf(e) - stagedOf(e) > 0;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Which $name?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(height: 2),
            Text(subtitle, style: PickerTokens.mono(context, size: 11.5)),
          ]),
        ),
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _Option(
              row: e,
              showName: rows.map((r) => r.name).toSet().length > 1,
              enabled: _open(e),
              count: countOf(e),
              staged: stagedOf(e),
              onTap: () => Navigator.of(context).pop(e),
            ),
          ),
        SafeArea(top: false, child: const SizedBox(height: 10)),
      ]),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.row,
    required this.showName,
    required this.enabled,
    required this.count,
    required this.staged,
    required this.onTap,
  });

  final ExternalEntry row;

  /// The options are not all one card — a scan sure only of the image.
  final bool showName;
  final bool enabled;
  final int count;
  final int staged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final e = row;
    final extras = [
      if (e.condition == 'Proxy') 'PROXY',
      for (final f in e.rowFlags.split(',')) if (f.isNotEmpty) f.toUpperCase(),
    ];
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            SizedBox(width: 36, height: 50, child: DeckboxThumb(cardRef: e.cardRef, any: e.anyPrinting)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showName)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text),
                    ),
                  ),
                Wrap(spacing: 3, runSpacing: 3, children: [
                  AttributeChips(
                    finish: e.finish,
                    language: e.languageCode,
                    condition: e.conditionCode,
                    defaults: ScanDefaults.current,
                  ),
                  for (final x in extras)
                    Text(x, style: PickerTokens.mono(context, size: 9, color: t.accent)),
                ]),
                const SizedBox(height: 6),
                Text(
                  [
                    if (e.anyPrinting)
                      'Any printing'
                    else if (e.editionCode.isNotEmpty)
                      '${e.editionCode.toUpperCase()} · ${e.cardNumber}',
                    '$count on Deckbox',
                    if (staged > 0) staged >= count ? 'all already staged' : '$staged already staged',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: t.textDim),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
