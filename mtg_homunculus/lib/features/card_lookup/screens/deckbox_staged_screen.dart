import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../external/deckbox/deckbox_mapping.dart';
import '../external/external_dao.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../widgets/card_picker.dart';
import '../widgets/variant_controls.dart';

/// One staged addition, editable (M3) — Card Detail for a Deckbox list.
///
/// **Chip edits are allowed here**, unlike on a mirrored row: nothing has been
/// sent, so changing the condition is just changing what will be. An edit may
/// flip the row between `x1` and `+1`, which is correct. **Change Version**
/// moves it between printings — and, on a Wishlist, to and from *Any
/// printing*, the first tile.
///
/// Edits in place, as Card Detail does: no save button.
class DeckboxStagedScreen extends StatefulWidget {
  const DeckboxStagedScreen({super.key, required this.stagedId, required this.list});

  final int stagedId;
  final ExternalList list;

  static Future<void> open(BuildContext context, {required int stagedId, required ExternalList list}) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DeckboxStagedScreen(stagedId: stagedId, list: list),
      ));

  @override
  State<DeckboxStagedScreen> createState() => _DeckboxStagedScreenState();
}

class _DeckboxStagedScreenState extends State<DeckboxStagedScreen> {
  ExternalDao get _dao => CollectionDatabase.instance.externalDao;
  CardsDatabase get _cards => CardsDatabase.instance;

  /// Moves when an edit merges this row into another staged one.
  late int _id = widget.stagedId;
  StreamSubscription<List<StagedChange>>? _sub;
  StagedChange? _staged;
  Card? _printing;
  bool _loaded = false;

  /// Deckbox's eleven languages, in the app's usual order.
  static final _languages = [
    for (final l in LanguageControl.languages)
      if (DeckboxMapping.languages.containsValue(l)) l,
  ];

  @override
  void initState() {
    super.initState();
    _sub = _dao.watchStaged(widget.list.id).listen((all) async {
      final s = all.where((x) => x.id == _id).firstOrNull;
      final ref = s?.cardRef ?? s?.cardId;
      final printing = ref == null ? null : await _cards.cardById(ref);
      if (!mounted) return;
      setState(() {
        _staged = s;
        _printing = printing;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _edit({
    Value<int?> finish = const Value.absent(),
    Value<String?> languageCode = const Value.absent(),
    Value<int?> conditionCode = const Value.absent(),
    StagedVersion? version,
  }) async {
    _id = await _dao.updateStagedAddition(
      _id,
      finish: finish,
      languageCode: languageCode,
      conditionCode: conditionCode,
      version: version,
    );
  }

  Future<void> _setQuantity(int q) async {
    await _dao.setStagedQuantity(_id, q);
    if (q <= 0 && mounted) Navigator.of(context).pop();
  }

  Future<void> _unstage() async {
    await _dao.unstage([_id]);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _changeVersion() async {
    final s = _staged;
    if (s == null) return;
    final printings = await _cards.printingsOf(s.name);
    if (!mounted) return;
    final picked = await CardPicker.showSheet(
      context,
      scope: PickerScope.changeVersion,
      db: _cards,
      initial: printings,
      offerAny: widget.list.kind == 'wishlist',
      currentAny: s.anyPrinting,
    );
    if (picked == null || !mounted) return;

    if (picked.anyPrinting) {
      await _edit(version: (
        name: picked.card.name,
        cardId: null,
        cardRef: picked.card.id,
        anyPrinting: true,
        setCode: '',
        setName: '',
        collectorNumber: '',
      ));
      return;
    }
    final set = await (_cards.select(_cards.sets)..where((x) => x.code.equals(picked.card.setCode)))
        .getSingleOrNull();
    // A printing has every attribute: what a generic row left as *any* takes
    // the scan defaults, as a scan would have.
    final d = ScanDefaults.current;
    await _edit(
      version: (
        name: picked.card.name,
        cardId: picked.card.id,
        cardRef: picked.card.id,
        anyPrinting: false,
        setCode: picked.card.setCode,
        setName: set?.name ?? picked.card.setCode.toUpperCase(),
        collectorNumber: picked.card.collectorNumber,
      ),
      finish: s.finish == null ? Value(d.finishFor(picked.card.finishes)) : const Value.absent(),
      languageCode: s.languageCode == null ? Value(d.language) : const Value.absent(),
      conditionCode: s.conditionCode == null ? Value(d.condition) : const Value.absent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = _staged;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This card is no longer staged.')),
      );
    }

    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final ref = s.cardRef ?? s.cardId;
    final url = ref == null ? null : ScryfallCard.imageUrlFor(ref, _printing?.imageUpdatedAt);
    final generic = s.anyPrinting;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Unstage',
            onPressed: _unstage,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            child: Icon(Icons.wifi_off_rounded, color: theme.disabledColor),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: theme.textTheme.titleMedium),
                if (generic)
                  Text('Any printing', style: dim?.copyWith(fontStyle: FontStyle.italic))
                else ...[
                  Text('${s.setCode.toUpperCase()} · ${s.collectorNumber}', style: dim),
                  if (s.setName.isNotEmpty) Text(s.setName, style: dim),
                ],
                const SizedBox(height: 4),
                Text('Staged to add to ${widget.list.name}', style: dim),
                if (s.lastError case final error?) ...[
                  const SizedBox(height: 6),
                  Text(error, style: dim?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 12),
                QuantityRow(quantity: s.quantity, onChanged: _setQuantity, removeLabel: 'Unstage'),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          FinishControl(
            value: s.finish,
            available: generic ? Finish.nonfoil | Finish.foil : _printing?.finishes,
            allowAny: generic,
            onChanged: (v) => _edit(finish: Value(v)),
          ),
          LanguageControl(
            value: s.languageCode,
            options: _languages,
            allowAny: generic,
            onChanged: (v) => _edit(languageCode: Value(v)),
          ),
          ConditionControl(
            value: s.conditionCode,
            allowAny: generic,
            onChanged: (v) => _edit(conditionCode: Value(v)),
          ),
          // An Inventory addition can also go up for trade, in the same push
          // (tradelist.md, decision 3) — set from the list's switch when
          // staged, changeable here for this card alone.
          if (widget.list.kind == 'inventory')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also up for trade'),
              subtitle: const Text('Goes on the Tradelist too when pushed'),
              value: s.forTrade,
              onChanged: (v) => _dao.setForTrade(_id, v),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Change Version'),
            onPressed: _changeVersion,
          ),
        ],
      ),
    );
  }
}
