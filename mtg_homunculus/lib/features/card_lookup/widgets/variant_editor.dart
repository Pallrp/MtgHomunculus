import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import 'attribute_chips.dart';

/// Every copy of one printing, in one place.
///
/// Two copies of a card, one Japanese and one English, cannot be a single row
/// with a quantity — and splitting them by subtracting from the original is
/// exactly the awkward step this exists to avoid.
///
/// **Nothing is subtracted.** The editor holds the whole card: adding a variant
/// never takes a copy from anywhere, and totals resolve on Save.
///
/// **Change Version is not here.** It lives one level up in Card Detail, so that
/// Save and Cancel commit or discard variant edits only, and never a printing
/// change made in the same breath.
class VariantEditor extends StatefulWidget {
  final int listId;
  final String cardId;
  final CollectionDatabase db;
  final int? imageUpdatedAt;

  const VariantEditor({
    super.key,
    required this.listId,
    required this.cardId,
    required this.db,
    this.imageUpdatedAt,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int listId,
    required String cardId,
    required CollectionDatabase db,
    int? imageUpdatedAt,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => VariantEditor(
          listId: listId,
          cardId: cardId,
          db: db,
          imageUpdatedAt: imageUpdatedAt,
        ),
      );

  @override
  State<VariantEditor> createState() => _VariantEditorState();
}

class _VariantEditorState extends State<VariantEditor> {
  List<VariantEdit> _rows = [];
  Entry? _sample;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Opens prepopulated with what the list already holds.
  ///
  /// That is what makes Save a *rewrite* rather than a diff the caller has to
  /// compute — see [CollectionDatabase.setVariantsFor].
  Future<void> _load() async {
    final existing = await widget.db.entriesForCard(widget.listId, widget.cardId);
    if (!mounted) return;
    setState(() {
      _sample = existing.isEmpty ? null : existing.first;
      _rows = existing.map(VariantEdit.of).toList();
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------

  int get _totalCopies => _rows.fold(0, (n, r) => n + (r.quantity ?? 1));

  /// A new variant starts as a duplicate of the one above.
  ///
  /// Usually exactly one attribute differs from a copy the user already owns, so
  /// copying lands closer to the answer than a blank row would, and the next tap
  /// changes the one chip that is wrong.
  void _addVariant() {
    setState(() {
      final last = _rows.isEmpty ? null : _rows.last;
      _rows = [
        ..._rows,
        VariantEdit(
          finish: last?.finish ?? ScanDefaults.current.finish,
          language: last?.language ?? ScanDefaults.current.language,
          condition: last?.condition ?? ScanDefaults.current.condition,
          quantity: 1,
        ),
      ];
    });
  }

  void _replace(int i, VariantEdit next) =>
      setState(() => _rows = [..._rows]..[i] = next);

  void _remove(int i) => setState(() => _rows = [..._rows]..removeAt(i));

  void _bump(int i, int delta) {
    final row = _rows[i];
    final next = (row.quantity ?? 1) + delta;
    if (next <= 0) {
      _remove(i);
      return;
    }
    _replace(
      i,
      VariantEdit(
        finish: row.finish,
        language: row.language,
        condition: row.condition,
        quantity: next,
      ),
    );
  }

  Future<void> _editRow(int i) async {
    final edited = await _VariantChipDialog.show(context, _rows[i]);
    if (edited == null) return;
    _replace(i, edited);
  }

  Future<void> _save() async {
    final sample = _sample;
    if (sample == null) {
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    await widget.db.setVariantsFor(
      listId: widget.listId,
      cardId: widget.cardId,
      wanted: _rows,
      name: sample.snapName,
      setCode: sample.snapSetCode,
      setName: sample.snapSetName,
      collectorNumber: sample.snapCollector,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final sample = _sample;

        return Column(
          children: [
            _header(theme, sample),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: _rows.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == _rows.length) {
                    return ListTile(
                      leading: const Icon(Icons.add_rounded),
                      title: const Text('Add variant'),
                      onTap: _addVariant,
                    );
                  }
                  return _VariantRow(
                    edit: _rows[i],
                    onTap: () => _editRow(i),
                    onBump: (d) => _bump(i, d),
                    onRemove: () => _remove(i),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            _actions(context),
          ],
        );
      },
    );
  }

  Widget _header(ThemeData theme, Entry? sample) {
    final url = sample == null
        ? null
        : ScryfallCard.imageUrlFor(sample.cardId, widget.imageUpdatedAt,
            size: 'small');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: AspectRatio(
              aspectRatio: 0.716,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: url == null
                    ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                    : Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (c, _, _) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                        )),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sample?.snapName ?? 'Variants',
                    style: theme.textTheme.titleSmall),
                if (sample != null)
                  Text(
                    '${sample.snapSetCode.toUpperCase()} · ${sample.snapCollector}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                Text(
                  '$_totalCopies ${_totalCopies == 1 ? "copy" : "copies"} '
                  'across ${_rows.length} '
                  '${_rows.length == 1 ? "variant" : "variants"}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

class _VariantRow extends StatelessWidget {
  final VariantEdit edit;
  final VoidCallback onTap;
  final void Function(int delta) onBump;
  final VoidCallback onRemove;

  const _VariantRow({
    required this.edit,
    required this.onTap,
    required this.onBump,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final qty = edit.quantity ?? 1;
    return Dismissible(
      key: ObjectKey(edit),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: AttributeChips(
                  finish: edit.finish,
                  language: edit.language,
                  condition: edit.condition,
                  defaults: ScanDefaults.current,
                ),
              ),
              // Trash at 1 rather than a disabled minus: reaching zero is how a
              // variant is removed, so the control says so.
              IconButton(
                icon: Icon(qty <= 1
                    ? Icons.delete_outline_rounded
                    : Icons.remove_rounded),
                onPressed: () => onBump(-1),
                tooltip: qty <= 1 ? 'Remove variant' : 'One fewer',
              ),
              Text('$qty', style: Theme.of(context).textTheme.titleSmall),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => onBump(1),
                tooltip: 'One more',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap a row to change its chips.
class _VariantChipDialog extends StatefulWidget {
  final VariantEdit initial;
  const _VariantChipDialog({required this.initial});

  static Future<VariantEdit?> show(BuildContext context, VariantEdit initial) =>
      showDialog<VariantEdit>(
        context: context,
        builder: (_) => _VariantChipDialog(initial: initial),
      );

  @override
  State<_VariantChipDialog> createState() => _VariantChipDialogState();
}

class _VariantChipDialogState extends State<_VariantChipDialog> {
  late int _finish = widget.initial.finish;
  late String _language = widget.initial.language;
  late int _condition = widget.initial.condition;

  static const _languages = ['en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko',
      'ru', 'zhs', 'zht'];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (final f in Finish.all)
                  ButtonSegment(value: f, label: Text(Finish.label(f))),
              ],
              selected: {_finish},
              onSelectionChanged: (s) => setState(() => _finish = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Language'),
                const Spacer(),
                DropdownButton<String>(
                  value: _languages.contains(_language) ? _language : 'en',
                  items: [
                    for (final l in _languages)
                      DropdownMenuItem(value: l, child: Text(l.toUpperCase())),
                  ],
                  onChanged: (v) => setState(() => _language = v ?? 'en'),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Condition'),
                const Spacer(),
                DropdownButton<int>(
                  value: _condition,
                  items: [
                    for (final c in Condition.all)
                      DropdownMenuItem(value: c, child: Text(Condition.label(c))),
                  ],
                  onChanged: (v) =>
                      setState(() => _condition = v ?? Condition.nearMint),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(VariantEdit(
              finish: _finish,
              language: _language,
              condition: _condition,
              quantity: widget.initial.quantity,
            )),
            child: const Text('Done'),
          ),
        ],
      );
}
