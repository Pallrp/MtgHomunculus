import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../models/scryfall_card.dart';
import '../widgets/card_picker.dart';
import '../widgets/variant_controls.dart';
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

  /// Which face the art is showing. Always starts on the front: a remembered
  /// face would mean reopening a card to a side you did not ask for.
  bool _showBack = false;
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
      // Opened on the card's NAME, not this printing: a copy that differs only
      // by edition is still a variant of the same card.
      name: entry.snapName,
      base: (
        cardId: entry.cardId,
        name: entry.snapName,
        setCode: entry.snapSetCode,
        setName: entry.snapSetName,
        collectorNumber: entry.snapCollector,
      ),
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
    // Double-faced cards have a back worth reading, and `has_back` is the only
    // thing that decides whether the control exists at all.
    final hasBack = _printing?.hasBack ?? false;
    final url = ScryfallCard.imageUrlFor(
      entry.cardId,
      _printing?.imageUpdatedAt,
      face: _showBack && hasBack ? 'back' : 'front',
    );

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
                child: Column(
                  children: [
                    AspectRatio(
                      aspectRatio: 0.716,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: url == null
                            ? const ColoredBox(color: Colors.black12)
                            : Image.network(
                                // Not disk-cached, deliberately: detail art is
                                // fetched singly, for a screen already online
                                // when it opens.
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (c, _, _) => ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.wifi_off_rounded,
                                      color: theme.disabledColor),
                                ),
                              ),
                      ),
                    ),
                    // A button rather than tapping the art: tapping is the
                    // gesture a future zoom will want, and spending it here
                    // would mean taking it back later. It also advertises that
                    // a back face exists, which a bare tap target cannot.
                    if (hasBack)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => _showBack = !_showBack),
                          icon: const Icon(Icons.flip_camera_android_outlined,
                              size: 16),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          label: Text(_showBack ? 'Front' : 'Back'),
                        ),
                      ),
                  ],
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
                    QuantityRow(
                      quantity: entry.quantity,
                      onChanged: _setQuantity,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          FinishControl(
            value: entry.finish,
            available: _printing?.finishes,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, finish: v!)),
          ),
          LanguageControl(
            value: entry.language,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, language: v!)),
          ),
          ConditionControl(
            value: entry.condition,
            onChanged: (v) =>
                _apply(() => widget.collection.updateEntry(_id, condition: v!)),
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
