import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../external/deckbox/deckbox_mapping.dart';
import '../external/deckbox/deckbox_row_edit.dart';
import '../external/deckbox/deckbox_row_panel.dart';
import '../external/deckbox_sheet_model.dart';
import '../external/deckbox_sync.dart';
import '../external/external_dao.dart';
import '../models/scryfall_card.dart';
import '../widgets/card_picker.dart';
import '../widgets/variant_controls.dart';

/// One mirrored (*On Deckbox*) row — what tapping it opens (mirror_editing.md).
///
/// Two halves, kept apart on screen because they behave differently:
///
/// - **Staged** — the row's − / +, moved here from the expanded row: they
///   stage, and wait for a push like everything in the sheet.
/// - **Edit on Deckbox** — finish, language, condition, printing. **Saved at
///   once** with Deckbox's own row edit when *Save to Deckbox* is tapped;
///   nothing is staged, and leaving the screen sends nothing.
///
/// On a Tradelist the row is its Inventory's, and edited there (E1). On a
/// Wishlist, condition, language and printing may be *Any*.
class DeckboxMirrorScreen extends StatefulWidget {
  const DeckboxMirrorScreen({super.key, required this.list, required this.entry});

  /// The list the row was opened from.
  final ExternalList list;
  final ExternalEntry entry;

  static Future<void> open(BuildContext context, {required ExternalList list, required ExternalEntry entry}) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => DeckboxMirrorScreen(list: list, entry: entry),
      ));

  @override
  State<DeckboxMirrorScreen> createState() => _DeckboxMirrorScreenState();
}

class _DeckboxMirrorScreenState extends State<DeckboxMirrorScreen> {
  ExternalDao get _dao => CollectionDatabase.instance.externalDao;
  CardsDatabase get _cards => CardsDatabase.instance;
  ExternalList get _list => widget.list;
  bool get _wishlist => _list.kind == 'wishlist';
  bool get _tradelist => _list.kind == 'tradelist';

  /// Followed by id — kept by an edit — and, when a pull replaces the mirror,
  /// by identity.
  late ExternalEntry _row = widget.entry;
  bool _gone = false;
  Card? _printing;
  List<StagedChange> _staged = const [];
  StreamSubscription<List<ExternalEntry>>? _mirrorSub;
  StreamSubscription<List<StagedChange>>? _stagedSub;
  List<ExternalEntry> _mirror = const [];

  // The edit not yet saved — null fields are unchanged.
  bool? _foil;
  ({String? code})? _language;
  ({int? code})? _condition;
  DeckboxEdition? _edition;
  Card? _editionCard;

  /// Deckbox's printings of the card, read once when Change Version is first
  /// opened, and forgotten after a save.
  List<DeckboxEdition>? _editions;
  bool _busy = false;
  String? _error;

  static final _languages = [
    for (final l in LanguageControl.languages)
      if (DeckboxMapping.languages.containsValue(l)) l,
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_follow());
    _stagedSub = _dao.watchStaged(_list.id).listen((s) {
      if (mounted) setState(() => _staged = s);
    });
  }

  Future<void> _follow() async {
    final mirrorId = await _dao.mirrorIdOf(_list);
    _mirrorSub = _dao.watchEntries(mirrorId).listen((rows) async {
      final row = rows.where((e) => e.id == _row.id).firstOrNull ??
          rows.where((e) => e.identityKey == _row.identityKey).firstOrNull;
      final ref = row?.cardRef ?? row?.cardId;
      final printing = ref == null ? null : await _cards.cardById(ref);
      if (!mounted) return;
      setState(() {
        _mirror = rows;
        _gone = row == null;
        if (row != null) _row = row;
        _printing = printing;
      });
    });
  }

  @override
  void dispose() {
    _mirrorSub?.cancel();
    _stagedSub?.cancel();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  // ── staged ─────────────────────────────────────────────────────────────────

  // **− and + net** (device test, 2026-10-20): each first takes back one of
  // the other way staged on this row, and only stages anew when there is
  // none. "On this row" is what the sheet's pills count — a removal or mark
  // by the row's identity, an addition by its variant — so a removal staged
  // before an edit still nets (it followed the row), and an addition staged
  // before one no longer does (it kept its old variant).

  /// The newest staged change counted against this row, one way.
  StagedChange? _onRow({required bool adding}) {
    final model = DeckboxSheetModel(list: _list, mirror: _mirror, staged: _staged);
    return adding
        ? model.additions.where((a) => a.existing?.id == _row.id).firstOrNull?.staged
        : model.removals.where((r) => r.row?.id == _row.id).firstOrNull?.staged;
  }

  Future<void> _minus() async {
    if (_onRow(adding: true) case final s?) return _dao.setStagedQuantity(s.id, s.quantity - 1);
    final took = await _dao.stageRemoval(list: _list, row: _row);
    if (took == 0 && mounted) _toast('All of ${_row.name} is already staged to remove');
  }

  /// On a Tradelist, one more copy **marked for trade**; elsewhere one more
  /// copy of the row's variant — the row's + as it was in the sheet.
  Future<void> _plus() async {
    if (_onRow(adding: false) case final s?) return _dao.setStagedQuantity(s.id, s.quantity - 1);
    if (_tradelist) {
      final took = await _dao.stageMark(list: _list, row: _row);
      if (took == 0 && mounted) _toast('Every copy of ${_row.name} is already for trade, or staged to be');
      return;
    }
    await _dao.stageAdditionLike(_row);
  }

  // ── the edit ───────────────────────────────────────────────────────────────

  bool get _dirty => _foil != null || _language != null || _condition != null || _edition != null;

  bool get _anyNow => _edition == null ? _row.anyPrinting : _edition!.id == 0;

  Future<void> _changeVersion() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var editions = _editions;
    if (editions == null) {
      final read = await DeckboxSync.instance.editionsOf(_list, _row);
      if (!mounted) return;
      if (read.error != null) {
        setState(() {
          _busy = false;
          _error = read.error;
        });
        return;
      }
      editions = _editions = read.editions;
    }

    final printings = await _cards.printingsOf(_row.name);
    final codes = {for (final p in printings) p.setCode};
    final sets = await (_cards.select(_cards.sets)..where((s) => s.code.isIn(codes))).get();
    final setName = {for (final s in sets) s.code: s.name};
    final matched = DeckboxRowEdit.matchPrintings(editions, [
      for (final p in printings)
        (id: p.id, setCode: p.setCode, setName: setName[p.setCode] ?? '', number: p.collectorNumber),
    ]);
    if (!mounted) return;
    setState(() => _busy = false);
    final offerAny = _wishlist || _row.anyPrinting;
    if (matched.isEmpty && !offerAny) {
      _toast("None of Deckbox's printings of ${_row.name} match the app's");
      return;
    }

    final picked = await CardPicker.showSheet(
      context,
      scope: PickerScope.changeVersion,
      db: _cards,
      initial: [for (final p in printings) if (matched.containsKey(p.id)) p],
      offerAny: offerAny,
      currentAny: _anyNow,
    );
    if (picked == null || !mounted) return;
    final edition = picked.anyPrinting ? editions.firstWhere((e) => e.id == 0) : matched[picked.card.id];
    if (edition == null) return;
    setState(() {
      final same = '${edition.id}' == _row.printingId || (edition.id == 0 && _row.printingId.isEmpty);
      _edition = same ? null : edition;
      _editionCard = same || picked.anyPrinting ? null : picked.card;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await DeckboxSync.instance.editRow(
      _list,
      _row,
      RowEdit(
        foil: _foil,
        language: _language,
        condition: _condition,
        edition: _edition,
        cardId: _editionCard?.id,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _foil = null;
        _language = null;
        _condition = null;
        _edition = null;
        _editionCard = null;
        _editions = null;
      }
    });
    if (error == null) _toast('Saved on Deckbox');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final e = _row;
    if (_gone) {
      return Scaffold(
        appBar: AppBar(title: Text(e.name, overflow: TextOverflow.ellipsis)),
        body: const Center(child: Text('This row is no longer on Deckbox.')),
      );
    }

    final model = DeckboxSheetModel(list: _list, mirror: _mirror, staged: _staged);
    final removed = model.removed[e.id] ?? 0;
    final added = model.added[e.id] ?? 0;
    final count = ExternalDao.countOn(_list, e);
    final ref = e.cardRef ?? e.cardId;
    final url = ref == null ? null : ScryfallCard.imageUrlFor(ref, _printing?.imageUpdatedAt);
    final unmapped = !e.anyPrinting && e.cardId == null;

    final etched = e.editionCode.endsWith('_e');
    final proxy = e.condition == 'Proxy';
    final allowAny = _wishlist || _anyNow;
    final finishShown = _foil == null ? e.finish : (_foil! ? Finish.foil : (_anyNow ? null : Finish.nonfoil));
    final printingFinishes = (_editionCard ?? _printing)?.finishes;

    return Scaffold(
      appBar: AppBar(title: Text(e.name, overflow: TextOverflow.ellipsis)),
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
                Text(e.name, style: theme.textTheme.titleMedium),
                if (e.anyPrinting)
                  Text('Any printing', style: dim?.copyWith(fontStyle: FontStyle.italic))
                else ...[
                  Text('${e.editionCode.toUpperCase()} · ${e.cardNumber}', style: dim),
                  if (e.edition.isNotEmpty) Text(e.edition, style: dim),
                  if (unmapped) Text('Not matched to a printing in the app', style: dim),
                ],
                const SizedBox(height: 4),
                Text(
                  _tradelist
                      ? 'On Deckbox · $count for trade · ${e.count} owned'
                      : e.tradeCount > 0
                          ? 'On Deckbox · $count owned · ${e.tradeCount} for trade'
                          : 'On Deckbox · $count ${_wishlist ? 'wanted' : 'owned'}',
                  style: dim,
                ),
                const SizedBox(height: 12),
                _StagedRow(
                  removed: removed,
                  added: added,
                  addWord: _tradelist ? 'to mark' : 'to add',
                  onMinus: added > 0 || count - removed > 0 ? _minus : null,
                  // An unmapped row has no printing to add more of.
                  onPlus: removed > 0 || e.anyPrinting || e.cardId != null ? _plus : null,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Edit on Deckbox', style: theme.textTheme.titleSmall),
          Text(
            'Saved to ${_tradelist ? 'the Inventory' : _list.name} on Deckbox straight away — not staged.',
            style: dim,
          ),
          const SizedBox(height: 8),
          AbsorbPointer(
            absorbing: _busy,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Etched is an edition on Deckbox, not a finish to toggle.
              if (!etched)
                FinishControl(
                  value: finishShown,
                  // On a generic row foil is a flag or nothing: Any or Foil.
                  available: _anyNow
                      ? Finish.foil
                      : (printingFinishes ?? Finish.nonfoil | Finish.foil) & (Finish.nonfoil | Finish.foil),
                  allowAny: _anyNow,
                  onChanged: (v) => setState(() {
                    final foil = v == Finish.foil;
                    _foil = foil == (e.foil == 'foil') ? null : foil;
                  }),
                ),
              LanguageControl(
                value: _language == null ? e.languageCode : _language!.code,
                options: _languages,
                allowAny: allowAny,
                onChanged: (v) => setState(() => _language = v == e.languageCode ? null : (code: v)),
              ),
              if (proxy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Condition: Proxy — change it on deckbox.org', style: dim),
                )
              else
                ConditionControl(
                  value: _condition == null ? e.conditionCode : _condition!.code,
                  allowAny: allowAny,
                  onChanged: (v) => setState(() => _condition = v == e.conditionCode ? null : (code: v)),
                ),
              if (_edition case final to?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    to.id == 0 ? 'Changing to: any printing' : 'Changing to: ${to.code} · ${to.number} — ${to.name}',
                    style: dim?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Change Version'),
                onPressed: _busy ? null : _changeVersion,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Save to Deckbox'),
                onPressed: _dirty && !_busy ? _save : null,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: dim?.copyWith(color: theme.colorScheme.error)),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// The row's staged copies, each way, with the − / + that stage more.
class _StagedRow extends StatelessWidget {
  const _StagedRow({
    required this.removed,
    required this.added,
    required this.addWord,
    required this.onMinus,
    required this.onPlus,
  });

  final int removed;
  final int added;
  final String addWord;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [
      if (removed > 0) '−$removed to remove',
      if (added > 0) '+$added $addWord',
    ];
    return Row(children: [
      IconButton.outlined(
        icon: const Icon(Icons.remove_rounded),
        tooltip: 'Stage one to remove',
        onPressed: onMinus,
      ),
      Expanded(
        child: Text(
          parts.isEmpty ? 'Nothing staged' : parts.join(' · '),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ),
      IconButton.outlined(
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Stage one more',
        onPressed: onPlus,
      ),
    ]);
  }
}
