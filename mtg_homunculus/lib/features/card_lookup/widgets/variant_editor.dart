import 'package:flutter/material.dart';

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../theme/picker_tokens.dart';
import 'attribute_chips.dart';
import 'card_picker.dart';

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

  /// The card's name. The editor spans every printing of it — a copy differing
  /// only by edition is still a variant of the same card.
  final String name;

  /// The printing a newly added variant starts on.
  final VariantPrinting base;

  final CollectionDatabase db;

  /// Needed for Change Edition, which lists and searches printings.
  final CardsDatabase cards;
  final int? imageUpdatedAt;

  const VariantEditor({
    super.key,
    required this.listId,
    required this.name,
    required this.base,
    required this.db,
    required this.cards,
    this.imageUpdatedAt,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int listId,
    required String name,
    required VariantPrinting base,
    required CollectionDatabase db,
    required CardsDatabase cards,
    int? imageUpdatedAt,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => VariantEditor(
          listId: listId,
          name: name,
          base: base,
          db: db,
          cards: cards,
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
    final existing =
        await widget.db.entriesForCardName(widget.listId, widget.name);
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
          // A new variant starts on whatever printing the row above names, so
          // adding one to a card whose rows have all moved edition does not
          // silently drop back to the original.
          printing: last?.printing ?? widget.base,
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
    _replace(i, row.copyWith(quantity: next));
  }

  /// Tapping a row opens it as its own detail sheet.
  ///
  /// Save there commits into this editor's list, not to the database — so
  /// cancelling out of the editor afterwards still discards everything, which is
  /// what Cancel has always promised.
  Future<void> _editRow(int i) async {
    final sample = _sample;
    if (sample == null) return;
    final edited = await VariantDetailSheet.show(
      context,
      initial: _rows[i],
      basePrinting: widget.base,
      cards: widget.cards,
      imageUpdatedAt: widget.imageUpdatedAt,
    );
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
      name: widget.name,
      wanted: _rows,
      base: widget.base,
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

/// One variant, opened from the editor's list.
///
/// **The same shape as Card Detail, minus what does not apply.** There is no
/// Open Variants button — you are already inside it — and Save/Cancel commit to
/// the editor rather than to the database, so a cancelled edit here leaves the
/// list untouched exactly like a cancelled edit there.
///
/// Change Edition is present, because a copy differing only by printing is the
/// same kind of "these are not one row" problem that variants exist for.
class VariantDetailSheet extends StatefulWidget {
  final VariantEdit initial;

  /// The card the editor was opened on, used when this row has not been moved.
  final VariantPrinting basePrinting;
  final CardsDatabase cards;
  final int? imageUpdatedAt;

  const VariantDetailSheet({
    super.key,
    required this.initial,
    required this.basePrinting,
    required this.cards,
    this.imageUpdatedAt,
  });

  static Future<VariantEdit?> show(
    BuildContext context, {
    required VariantEdit initial,
    required VariantPrinting basePrinting,
    required CardsDatabase cards,
    int? imageUpdatedAt,
  }) =>
      showModalBottomSheet<VariantEdit>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => VariantDetailSheet(
          initial: initial,
          basePrinting: basePrinting,
          cards: cards,
          imageUpdatedAt: imageUpdatedAt,
        ),
      );

  @override
  State<VariantDetailSheet> createState() => _VariantDetailSheetState();
}

class _VariantDetailSheetState extends State<VariantDetailSheet> {
  late VariantEdit _edit = widget.initial;

  /// Available finishes for whichever printing this row currently names. Null
  /// until looked up, and stays null when the card cache is gone.
  int? _finishes;

  VariantPrinting get _printing => _edit.printing ?? widget.basePrinting;

  @override
  void initState() {
    super.initState();
    _loadFinishes();
  }

  Future<void> _loadFinishes() async {
    final card = await widget.cards.cardById(_printing.cardId);
    if (mounted) setState(() => _finishes = card?.finishes);
  }

  Future<void> _changeEdition() async {
    // Opens on every printing of this card, with the search field live so a set
    // code narrows it — the list is hundreds long for a reprinted card.
    final printings = await widget.cards.printingsOf(_printing.name);
    if (!mounted) return;
    final picked = await CardPicker.showSheet(
      context,
      scope: PickerScope.changeVersion,
      db: widget.cards,
      initial: printings,
    );
    if (picked == null || !mounted) return;

    final set = await (widget.cards.select(widget.cards.sets)
          ..where((x) => x.code.equals(picked.card.setCode)))
        .getSingleOrNull();
    if (!mounted) return;

    setState(() {
      _edit = _edit.copyWith(printing: (
        cardId: picked.card.id,
        name: picked.card.name,
        setCode: picked.card.setCode,
        setName: set?.name ?? picked.card.setCode.toUpperCase(),
        collectorNumber: picked.card.collectorNumber,
      ));
      _finishes = null;
    });
    _loadFinishes();
  }

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final printing = _printing;
    final url = ScryfallCard.imageUrlFor(
      printing.cardId,
      _edit.printing == null ? widget.imageUpdatedAt : null,
    );
    final qty = _edit.quantity ?? 1;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (context, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: AspectRatio(
                        aspectRatio: 0.716,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: url == null
                              ? ColoredBox(color: t.surface2)
                              : Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, _, _) =>
                                      ColoredBox(color: t.surface2),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            printing.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          Text(
                            '${printing.setCode.toUpperCase()} · '
                            '${printing.collectorNumber}',
                            style: PickerTokens.mono(context, size: 11),
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            label: 'Qty',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _Tap(
                                  icon: Icons.remove_rounded,
                                  onTap: qty <= 1
                                      ? null
                                      : () => setState(() =>
                                          _edit = _edit.copyWith(
                                              quantity: qty - 1)),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Center(
                                    child: Text(
                                      '$qty',
                                      style: PickerTokens.mono(
                                        context,
                                        size: 13,
                                        weight: FontWeight.w600,
                                        color: t.text,
                                      ),
                                    ),
                                  ),
                                ),
                                _Tap(
                                  icon: Icons.add_rounded,
                                  onTap: () => setState(() =>
                                      _edit =
                                          _edit.copyWith(quantity: qty + 1)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FinishField(
                  value: _edit.finish,
                  available: _finishes,
                  onChanged: (v) =>
                      setState(() => _edit = _edit.copyWith(finish: v)),
                ),
                _LanguageField(
                  value: _edit.language,
                  onChanged: (v) =>
                      setState(() => _edit = _edit.copyWith(language: v)),
                ),
                _ConditionField(
                  value: _edit.condition,
                  onChanged: (v) =>
                      setState(() => _edit = _edit.copyWith(condition: v)),
                ),
                const SizedBox(height: 16),
                _OutlineButton(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Change Edition',
                  onTap: _changeEdition,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _OutlineButton(
                      label: 'Cancel',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _OutlineButton(
                      label: 'Save',
                      primary: true,
                      onTap: () => Navigator.of(context).pop(_edit),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(label.toUpperCase(),
                  style: PickerTokens.fieldLabel(context)),
            ),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ],
        ),
      );
}

/// Finish is not a boolean — see `card_management_ui.md`. Built from what the
/// printing reports, and absent entirely when there is only one.
class _FinishField extends StatelessWidget {
  final int value;
  final int? available;
  final void Function(int) onChanged;

  const _FinishField({
    required this.value,
    required this.available,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final mask = available ?? (Finish.nonfoil | Finish.foil | Finish.etched);
    final options = [
      for (final f in Finish.all)
        if (mask & f != 0) f,
    ];
    if (options.length < 2) return const SizedBox.shrink();

    return _Field(
      label: 'Finish',
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in options)
              InkWell(
                onTap: () => onChanged(f),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: f != value
                        ? null
                        : f == Finish.foil
                            ? null
                            : t.accentSoft,
                    gradient: f == value && f == Finish.foil
                        ? PickerTokens.foil
                        : null,
                    border: Border(right: BorderSide(color: t.line)),
                  ),
                  child: Text(
                    Finish.label(f),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          f == value ? FontWeight.w600 : FontWeight.w400,
                      color: f != value
                          ? t.textDim
                          : f == Finish.foil
                              ? PickerTokens.onFoil
                              : t.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageField extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _LanguageField({required this.value, required this.onChanged});

  static const languages = [
    'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'ru', 'zhs', 'zht',
  ];

  @override
  Widget build(BuildContext context) => _Field(
        label: 'Language',
        child: _Dropdown<String>(
          value: languages.contains(value) ? value : 'en',
          items: languages,
          labelOf: (v) => v.toUpperCase(),
          onChanged: onChanged,
        ),
      );
}

class _ConditionField extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;

  const _ConditionField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => _Field(
        label: 'Condition',
        child: _Dropdown<int>(
          value: value,
          items: Condition.all,
          labelOf: Condition.label,
          severity: value,
          onChanged: onChanged,
        ),
      );
}

class _Dropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final void Function(T) onChanged;

  /// The condition this dropdown holds, when it holds one.
  final int? severity;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.severity,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    // Carries the condition ramp's own colour, so a played card reads as played
    // before the dropdown is opened.
    final ramp = severity == null ? null : t.condition(severity!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: ramp?.$2,
        border: Border.all(color: ramp?.$1 ?? t.line),
        borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: PickerTokens.mono(
            context,
            size: 12,
            color: ramp?.$1 ?? t.textDim,
          ),
          items: [
            for (final i in items)
              DropdownMenuItem(value: i, child: Text(labelOf(i))),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _Tap({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
        ),
        child: Icon(icon, size: 15, color: onTap == null ? t.textFaint : t.text),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: primary ? t.accent : null,
          border: Border.all(color: primary ? t.accent : t.line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: primary ? t.ground : t.textDim),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: primary ? t.ground : t.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
