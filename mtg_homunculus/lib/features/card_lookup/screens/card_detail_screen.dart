import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../models/scryfall_card.dart';
import '../widgets/card_picker.dart';
import '../widgets/variant_editor.dart';

/// One entry, editable.
///
/// The only place a scan is corrected after the fact, and the only place
/// quantity on an older row can be changed.
///
/// **Everything edits in place — there is no save button.** The card is already
/// in the list; every control here is direct manipulation of something that
/// exists, so a save step would be asking the user to confirm a change they can
/// already see.
class CardDetailScreen extends StatefulWidget {
  final int entryId;
  final CollectionDatabase collection;
  final CardsDatabase cards;

  const CardDetailScreen({
    super.key,
    required this.entryId,
    required this.collection,
    required this.cards,
  });

  static Future<void> open(
    BuildContext context, {
    required int entryId,
    required CollectionDatabase collection,
    required CardsDatabase cards,
  }) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => CardDetailScreen(
          entryId: entryId,
          collection: collection,
          cards: cards,
        ),
      ));

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  Entry? _entry;
  Card? _printing;
  bool _loading = true;

  /// The entry id moves when an edit merges this row into an existing variant,
  /// so it is state rather than the widget's parameter.
  late int _id = widget.entryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entry = await widget.collection.entryById(_id);
    // Null when the card cache has been cleared. The entry still renders from
    // its own snapshot — that is what the snapshot is for — it just loses the
    // finish control, which needs to know what the printing came in.
    final printing =
        entry == null ? null : await widget.cards.cardById(entry.cardId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _printing = printing;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------

  Future<void> _apply(Future<int> Function() edit) async {
    _id = await edit();
    await _load();
  }

  Future<void> _setQuantity(int q) async {
    final entry = _entry;
    if (entry == null) return;
    await widget.collection.setQuantity(_id, q);
    if (q <= 0 && mounted) {
      Navigator.of(context).pop();
      return;
    }
    await _load();
  }

  Future<void> _changeVersion() async {
    final entry = _entry;
    if (entry == null) return;
    final printings = await widget.cards.printingsOf(entry.snapName);
    if (!mounted) return;
    final picked = await CardPicker.showSheet(
      context,
      scope: PickerScope.changeVersion,
      db: widget.cards,
      initial: printings,
    );
    if (picked == null || !mounted) return;

    final set = await (widget.cards.select(widget.cards.sets)
          ..where((s) => s.code.equals(picked.card.setCode)))
        .getSingleOrNull();

    await _apply(() => widget.collection.updateEntry(
          _id,
          cardId: picked.card.id,
          name: picked.card.name,
          setCode: picked.card.setCode,
          setName: set?.name ?? picked.card.setCode.toUpperCase(),
          collectorNumber: picked.card.collectorNumber,
        ));
  }

  Future<void> _openVariants() async {
    final entry = _entry;
    if (entry == null) return;
    await VariantEditor.show(
      context,
      listId: entry.listId,
      cardId: entry.cardId,
      db: widget.collection,
      cards: widget.cards,
      imageUpdatedAt: _printing?.imageUpdatedAt,
    );
    if (mounted) await _load();
  }

  Future<void> _delete() async {
    await widget.collection.removeEntry(_id);
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entry = _entry;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This card is no longer in the list.')),
      );
    }

    final theme = Theme.of(context);
    final url = ScryfallCard.imageUrlFor(entry.cardId, _printing?.imageUpdatedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.snapName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove from list',
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: AspectRatio(
                  aspectRatio: 0.716,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: url == null
                        ? const ColoredBox(color: Colors.black12)
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (c, _, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(Icons.wifi_off_rounded,
                                  color: theme.disabledColor),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.snapName, style: theme.textTheme.titleMedium),
                    Text(
                      '${entry.snapSetCode.toUpperCase()} · ${entry.snapCollector}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (entry.snapSetName.isNotEmpty)
                      Text(
                        entry.snapSetName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 16),
                    _QuantityRow(
                      quantity: entry.quantity,
                      onChanged: _setQuantity,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _FinishControl(
            value: entry.finish,
            available: _printing?.finishes,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, finish: v)),
          ),
          _LanguageControl(
            value: entry.language,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, language: v)),
          ),
          _ConditionControl(
            value: entry.condition,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, condition: v)),
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.layers_outlined, size: 18),
                  label: const Text('Open Variants'),
                  // Never gated on quantity. A control that appears and
                  // disappears leaves people hunting for where it went.
                  onPressed: _openVariants,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Change Version'),
                  onPressed: _changeVersion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuantityRow extends StatelessWidget {
  final int quantity;
  final void Function(int) onChanged;

  const _QuantityRow({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text('Qty', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          IconButton(
            icon: Icon(quantity <= 1
                ? Icons.delete_outline_rounded
                : Icons.remove_rounded),
            onPressed: () => onChanged(quantity - 1),
            tooltip: quantity <= 1 ? 'Remove from list' : 'One fewer',
          ),
          Text('$quantity', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => onChanged(quantity + 1),
            tooltip: 'One more',
          ),
        ],
      );
}

class _Labelled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labelled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
            Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
          ],
        ),
      );
}

/// Finish is not a boolean.
///
/// Scryfall documents `finishes` as an array of **foil**, **nonfoil** and
/// **etched** — three values, not two. The control is built from what the
/// printing actually reports, and **a printing with one finish shows no control
/// at all**: offering a choice that does not exist invites an entry describing a
/// card nobody ever made.
///
/// (`glossy` is a promo *type*, not a finish; those cards report `[foil]`.)
class _FinishControl extends StatelessWidget {
  final int value;
  final int? available;
  final void Function(int) onChanged;

  const _FinishControl({
    required this.value,
    required this.available,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Unknown means the card cache is gone; fall back to the three so the entry
    // stays editable rather than freezing on whatever it holds.
    final mask = available ?? (Finish.nonfoil | Finish.foil | Finish.etched);
    final options = [
      for (final f in Finish.all)
        if (mask & f != 0) f,
    ];
    if (options.length < 2) return const SizedBox.shrink();

    return _Labelled(
      label: 'Finish',
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final f in options)
            ButtonSegment(value: f, label: Text(Finish.label(f))),
        ],
        selected: {options.contains(value) ? value : options.first},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _LanguageControl extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _LanguageControl({required this.value, required this.onChanged});

  /// The languages Scryfall prints cards in.
  static const languages = [
    'en', 'es', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'ru', 'zhs', 'zht',
    'he', 'la', 'grc', 'ar', 'sa', 'ph',
  ];

  @override
  Widget build(BuildContext context) => _Labelled(
        label: 'Language',
        child: DropdownButton<String>(
          value: languages.contains(value) ? value : 'en',
          underline: const SizedBox.shrink(),
          items: [
            for (final l in languages)
              DropdownMenuItem(value: l, child: Text(l.toUpperCase())),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}

class _ConditionControl extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;

  const _ConditionControl({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => _Labelled(
        label: 'Condition',
        child: DropdownButton<int>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final c in Condition.all)
              DropdownMenuItem(value: c, child: Text(Condition.label(c))),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      );
}
