import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../external/copy_match.dart';
import '../theme/picker_tokens.dart';
import '../widgets/card_picker.dart';
import '../widgets/checklist_scaffold.dart';

/// *N cards need a specific printing* (decided 2026-10-17) — generic cards
/// copied or cut into an **app list**, which holds printings only.
///
/// One row per generic card: **Select printing for …** opens Change Version
/// on its printings; **Skip** leaves it where it was. Every other card goes as
/// it is, and is not listed. The primary action stays disabled until nothing
/// waits — the count in the band says how many are left.
///
/// Pops with each generic line's printing by line index — null for a skipped
/// one — or null on *Back*.
class PrintingChecklistScreen extends StatefulWidget {
  const PrintingChecklistScreen({
    super.key,
    required this.lines,
    required this.generic,
    required this.targetName,
    required this.sourceName,
    required this.cut,
  });

  final List<CardLine> lines;

  /// Indexes into [lines] of the generic ones.
  final List<int> generic;
  final String targetName;
  final String sourceName;
  final bool cut;

  @override
  State<PrintingChecklistScreen> createState() => _PrintingChecklistScreenState();
}

class _PrintingChecklistScreenState extends State<PrintingChecklistScreen> {
  final _chosen = <int, Card>{};
  final _skipped = <int>{};

  Future<void> _select(int i) async {
    final cards = CardsDatabase.instance;
    final printings = await cards.printingsOf(widget.lines[i].name);
    if (!mounted) return;
    final picked = await CardPicker.showSheet(
      context,
      scope: PickerScope.changeVersion,
      db: cards,
      initial: printings,
    );
    if (picked != null && mounted) setState(() => _chosen[i] = picked.card);
  }

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final waiting = widget.generic.where((i) => !_chosen.containsKey(i) && !_skipped.contains(i)).length;
    final going = widget.lines.length - _skipped.length;
    final n = widget.generic.length;

    return ChecklistScaffold(
      title: '$n ${n == 1 ? 'card needs' : 'cards need'} a specific printing',
      subtitle: '${widget.cut ? 'Moving' : 'Copying'} to ${widget.targetName} · '
          '${widget.lines.length - n} others go as they are',
      bandLabel: 'Select a printing',
      waiting: waiting,
      rows: [
        for (final i in widget.generic)
          if (_skipped.contains(i))
            ChecklistRow(
              cardRef: widget.lines[i].cardRef,
              any: true,
              title: widget.lines[i].name,
              dimmed: true,
              sub: Text('Skipped · stays in ${widget.sourceName}', style: TextStyle(fontSize: 12, color: t.textDim)),
              trailing: TextButton(onPressed: () => setState(() => _skipped.remove(i)), child: const Text('Undo')),
            )
          else if (_chosen[i] case final card?)
            ChecklistRow(
              cardRef: card.id,
              any: false,
              title: widget.lines[i].name,
              sub: Text('${card.setCode.toUpperCase()} · ${card.collectorNumber}',
                  style: PickerTokens.mono(context, size: 10.5)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: () => _select(i), child: const Text('Change')),
                ChecklistRow.done(context),
              ]),
            )
          else
            ChecklistRow(
              cardRef: widget.lines[i].cardRef,
              any: true,
              title: 'Select printing for ${widget.lines[i].name}',
              sub: Text('Any printing', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: t.syncInk)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: () => setState(() => _skipped.add(i)), child: const Text('Skip')),
                OutlinedButton(onPressed: () => _select(i), child: const Text('Select')),
              ]),
            ),
      ],
      primaryLabel: '${widget.cut ? 'Move' : 'Copy'} $going ${going == 1 ? 'card' : 'cards'}',
      onPrimary: waiting > 0 || going == 0
          ? null
          : () => Navigator.of(context).pop({
                for (final i in widget.generic) i: _skipped.contains(i) ? null : _chosen[i],
              }),
    );
  }
}
