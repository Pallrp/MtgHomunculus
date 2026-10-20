import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/copy_match.dart';
import '../external/external_dao.dart';
import '../models/scan_defaults.dart';
import '../theme/picker_tokens.dart';
import '../widgets/attribute_chips.dart';
import '../widgets/checklist_scaffold.dart';
import '../widgets/which_copy_sheet.dart';

/// *Remove from Inventory* (M3 step 4, the canvas's *Remove: match and skip*)
/// — cards copied or cut into a Deckbox list's **To remove**, matched to its
/// rows by [CopyMatcher], when not every card matched on its own.
///
/// Each card that could be several rows waits for **Choose** (the which-copy
/// sheet) or **Skip**; a choice or skip can be undone. What Deckbox does not
/// have is counted in a banner that opens to say which. **Stage N cards**
/// stays disabled until nothing waits — and while nothing would be staged.
///
/// Pops with the final matches, or null on *Back*.
class RemoveMatchScreen extends StatefulWidget {
  const RemoveMatchScreen({
    super.key,
    required this.lines,
    required this.rows,
    required this.list,
    required this.left,
    required this.accountName,
    required this.sourceName,
    this.title,
    this.words = CopyMatcher.removeWords,
    this.excess = _moreThanDeckbox,
  });

  /// *Mark for trade on Tradelist* in place of *Remove from Inventory*.
  final String? title;
  final ({String missing, String spent}) words;

  /// The skipped part of a card placed only partly — *2 more than Deckbox has*.
  final String Function(int n) excess;

  static String _moreThanDeckbox(int n) => '$n more than Deckbox has';

  final List<CardLine> lines;
  final List<ExternalEntry> rows;
  final ExternalList list;
  final int Function(ExternalEntry) left;
  final String accountName;

  /// Where skipped cards stay — *Trade binder*.
  final String sourceName;

  @override
  State<RemoveMatchScreen> createState() => _RemoveMatchScreenState();
}

class _RemoveMatchScreenState extends State<RemoveMatchScreen> {
  final _chosen = <int, ExternalEntry>{};
  final _skipped = <int>{};

  List<LineMatch> get _matches => CopyMatcher.matchAll(
        lines: widget.lines,
        rows: widget.rows,
        left: widget.left,
        chosen: _chosen,
        skipped: _skipped,
        words: widget.words,
      );

  Future<void> _choose(int i, Choose c) async {
    final row = await WhichCopySheet.show(
      context,
      name: c.line.name,
      subtitle: '${c.line.setCode.toUpperCase()} · ${c.line.collectorNumber} · '
          '${c.rows.length} rows on Deckbox',
      rows: c.rows,
      countOf: (e) => ExternalDao.countOn(widget.list, e),
      stagedOf: (e) => ExternalDao.countOn(widget.list, e) - widget.left(e),
    );
    if (row != null && mounted) setState(() => _chosen[i] = row);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final waiting = CopyMatcher.open(matches);
    final staging = CopyMatcher.staged(matches);

    // Ambiguous ones first — they are the work — then the rest as they came.
    final shown = <int>[
      for (var i = 0; i < matches.length; i++) if (matches[i] is Choose) i,
      for (var i = 0; i < matches.length; i++)
        if (matches[i] is Placed || (matches[i] is Unplaced && (matches[i] as Unplaced).skippedByUser)) i,
    ];
    final notThere = <String>[
      for (final m in matches)
        if (m case Unplaced(:final line, :final reason, skippedByUser: false))
          '${line.name} · ${line.setCode.toUpperCase()} · ${line.quantity} — $reason'
        else if (m case Placed(:final line) when m.excess > 0)
          '${line.name} · ${line.setCode.toUpperCase()} · ${widget.excess(m.excess)}',
    ];

    return ChecklistScaffold(
      title: widget.title ?? 'Remove from ${widget.list.name}',
      subtitle: '${widget.accountName} · ${matches.whereType<Placed>().length} of ${widget.lines.length} found',
      bandLabel: 'Choose a copy',
      waiting: waiting,
      rows: [for (final i in shown) _row(context, i, matches[i])],
      below: [if (notThere.isNotEmpty) SkippedBanner(lines: notThere, sourceName: widget.sourceName)],
      primaryLabel: 'Stage $staging ${staging == 1 ? 'card' : 'cards'}',
      onPrimary: waiting > 0 || staging == 0 ? null : () => Navigator.of(context).pop(matches),
    );
  }

  Widget _row(BuildContext context, int i, LineMatch m) {
    final t = PickerTokens.of(context);
    final line = m.line;
    final title = line.quantity > 1 ? '${line.name} ×${line.quantity}' : line.name;
    return switch (m) {
      Choose(:final rows) => ChecklistRow(
          cardRef: line.cardRef,
          any: line.anyPrinting,
          title: title,
          sub: Text('${line.setCode.toUpperCase()} ${line.collectorNumber} · ${rows.length} rows on Deckbox',
              style: PickerTokens.mono(context, size: 10.5)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => setState(() => _skipped.add(i)), child: const Text('Skip')),
            OutlinedButton(onPressed: () => _choose(i, m), child: const Text('Choose')),
          ]),
        ),
      Placed(:final row) => ChecklistRow(
          cardRef: line.cardRef,
          any: line.anyPrinting,
          title: title,
          sub: AttributeChips(
            finish: row.finish,
            language: row.languageCode,
            condition: row.conditionCode,
            defaults: ScanDefaults.current,
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (m.chosen) TextButton(onPressed: () => setState(() => _chosen.remove(i)), child: const Text('Undo')),
            ChecklistRow.done(context),
          ]),
        ),
      Unplaced() => ChecklistRow(
          cardRef: line.cardRef,
          any: line.anyPrinting,
          title: title,
          dimmed: true,
          sub: Text('Skipped · stays in ${widget.sourceName}', style: TextStyle(fontSize: 12, color: t.textDim)),
          trailing: TextButton(onPressed: () => setState(() => _skipped.remove(i)), child: const Text('Undo')),
        ),
    };
  }
}
