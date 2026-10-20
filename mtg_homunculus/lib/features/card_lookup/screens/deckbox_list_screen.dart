import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart' show Card, CardsDatabase;
import '../data/collection_database.dart';
import '../external/deckbox_sync.dart';
import '../external/external_dao.dart';
import '../external/removal_match.dart';
import '../models/dev_flags.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../services/card_identifier.dart' show Identification;
import '../widgets/card_picker.dart';
import '../widgets/deckbox_sheet.dart';
import '../widgets/scanner_overlay.dart' show ScannerOverlay;
import '../widgets/which_copy_sheet.dart';
import 'deckbox_push_screen.dart';
import 'deckbox_mirror_screen.dart';
import 'deckbox_staged_screen.dart';

/// One Deckbox list (M3): the camera, and over it the [DeckboxSheet] — the
/// list's staged changes and its mirror.
///
/// Built like [ListingDetailScreen] — the same camera, the same peek and full
/// sheet, the camera running only at peek — but **every change is staged**,
/// never written: a scan or Manual Add stages into the target section, and
/// only *Push* sends anything to Deckbox.
///
/// Opening it pulls, unless it was pulled within the cooldown and is not stale.
class DeckboxListScreen extends StatefulWidget {
  const DeckboxListScreen({super.key, required this.listId});

  final int listId;

  @override
  State<DeckboxListScreen> createState() => _DeckboxListScreenState();
}

class _DeckboxListScreenState extends State<DeckboxListScreen> {
  // Sheet geometry — as ListingDetailScreen, with the peek's target line.
  static const double _maxSheetSize = 0.88;

  double _minSheetSize(BuildContext context) {
    final media = MediaQuery.of(context);
    final peek = DeckboxSheet.peekContentFor(wishlist: _list?.kind == 'wishlist');
    final size = (peek + media.viewPadding.bottom) / media.size.height;
    return size.clamp(0.08, _maxSheetSize - 0.05);
  }

  double _activeThreshold(BuildContext context) => _minSheetSize(context) + 0.03;

  double? _snapFor;
  List<double>? _snapSizes;

  /// One list instance across rebuilds — see ListingDetailScreen._snaps: a new
  /// list reads as changed and snaps every drag back to peek.
  List<double> _snaps(double minSheet) {
    if (_snapSizes == null || _snapFor != minSheet) {
      _snapFor = minSheet;
      _snapSizes = [minSheet, _maxSheetSize];
    }
    return _snapSizes!;
  }

  final _sheetController = DraggableScrollableController();

  ExternalDao get _dao => CollectionDatabase.instance.externalDao;
  CardsDatabase get _cards => CardsDatabase.instance;

  final _subs = <StreamSubscription<Object?>>[];
  ExternalList? _list;
  List<ExternalAccount> _accounts = const [];
  List<ExternalEntry> _mirror = const [];
  List<StagedChange> _staged = const [];
  bool _loaded = false;
  bool _openPullDone = false;
  /// Off at first: a list opens on its cards, as an app list does.
  bool _cameraActive = false;

  ScanTarget _target = ScanTarget.add;
  int? _lastStagedId;
  int? _pulseStagedId;

  /// A Wishlist's *Any printing*, from its list row, written back when
  /// flipped — in Manual Add or in the peek, which share it.
  final _anyPrinting = ValueNotifier<bool>(true);
  bool _anyLoaded = false;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetChange);
    _subs.addAll([
      _dao.watchList(widget.listId).listen((l) {
        setState(() {
          _list = l;
          _loaded = true;
        });
        if (l != null && !_anyLoaded) {
          _anyLoaded = true;
          _anyPrinting.value = l.anyPrinting;
          _anyPrinting.addListener(_saveAnyPrinting);
        }
        if (l != null && !_openPullDone) {
          _openPullDone = true;
          DeckboxSync.instance.pullIfDue(l);
          _watchMirror(l);
        }
      }),
      _dao.watchStaged(widget.listId).listen((s) => setState(() => _staged = s)),
      _dao.watchAccounts().listen((a) => setState(() => _accounts = a)),
    ]);
  }

  StreamSubscription<List<ExternalEntry>>? _mirrorSub;

  /// The rows this list shows — its own, or for a Tradelist its Inventory's
  /// (tradelist.md: one mirror for both).
  Future<void> _watchMirror(ExternalList l) async {
    final id = await _dao.mirrorIdOf(l);
    if (!mounted) return;
    _mirrorSub = _dao.watchEntries(id).listen((e) => setState(() => _mirror = e));
  }

  @override
  void dispose() {
    _mirrorSub?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _sheetController.removeListener(_onSheetChange);
    _sheetController.dispose();
    _anyPrinting.dispose();
    super.dispose();
  }

  bool get _wishlist => _list?.kind == 'wishlist';

  /// A Tradelist's **To add** marks owned copies for trade (tradelist.md,
  /// step 4): its scans and Manual Add resolve against the Inventory's free
  /// copies, as a removal resolves against a list's rows.
  bool get _marking => _list?.kind == 'tradelist' && _target == ScanTarget.add;

  /// Generic additions: a Wishlist with *Any printing* on.
  bool get _addGeneric => _wishlist && _anyPrinting.value;

  void _saveAnyPrinting() {
    final l = _list;
    if (l != null && l.anyPrinting != _anyPrinting.value) _dao.setAnyPrinting(l.id, _anyPrinting.value);
  }

  ExternalAccount? get _account => _accounts.where((a) => a.id == _list?.accountId).firstOrNull;

  // ---------------------------------------------------------------------------
  // Sheet
  // ---------------------------------------------------------------------------

  void _onSheetChange() {
    if (!_sheetController.isAttached || !mounted) return;
    final active = _sheetController.size <= _activeThreshold(context);
    if (active != _cameraActive) setState(() => _cameraActive = active);
  }

  void _collapseToCamera() {
    if (!_sheetController.isAttached || !mounted) return;
    _sheetController.animateTo(
      _minSheetSize(context),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _onScannerIdle() {
    if (!_sheetController.isAttached || !mounted) return;
    if (_sheetController.size > _activeThreshold(context)) return;
    _sheetController.animateTo(
      _maxSheetSize,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  // ---------------------------------------------------------------------------
  // Staging a scan
  // ---------------------------------------------------------------------------

  /// A card scanned into **To add**. Returns the staged row's id.
  Future<int> _onCardScanned(ScryfallCard card) async {
    final list = _list;
    if (list == null) return -1;
    final id = await _stageScannedAddition(list, card);
    if (mounted) setState(() => _lastStagedId = id);
    return id;
  }

  /// A card scanned into **To remove** — or into a Tradelist's **To add**,
  /// to mark — handed over whole by the scanner, so [RemovalMatcher] can weigh
  /// what the scan was sure of against the rows it could be. Returns the
  /// staged row's id, or -1 when nothing was staged.
  Future<int> _onScannedResolve(Identification scan) async {
    final list = _list;
    if (list == null || scan.candidates.isEmpty) return -1;
    final mark = _marking;
    final known = RemovalMatcher.printingRead(scan);
    final match = RemovalMatcher.resolve(
      rows: mark ? _markable(list) : _holding(list),
      left: (e) => mark ? _free(e) : _left(list, e),
      candidates: scan.candidates,
      printingKnown: known,
    );
    final c = scan.candidates.first;
    final oneCard = scan.candidates.map((x) => x.name).toSet().length == 1;
    return _stageMatch(
      list,
      match,
      mark: mark,
      subtitle: (n) => known
          ? '${c.setCode.toUpperCase()} · ${c.collectorNumber} · $n rows on Deckbox match'
          : oneCard
              ? 'Printing not read · $n rows of it on Deckbox'
              : 'Not sure which card · $n rows on Deckbox could be it',
    );
  }

  /// The exact printing, on the scan defaults — as an app list's scan lands.
  /// On a Wishlist with *Any printing* on, the **card**: identified, its
  /// printing dropped — kept only as the reference behind the row.
  Future<int> _stageScannedAddition(ExternalList list, ScryfallCard card) {
    if (_addGeneric) return _stageGeneric(list, card.name, card.scryfallId);
    final d = ScanDefaults.current;
    return _dao.stageAddition(
      listId: list.id,
      name: card.name,
      cardId: card.scryfallId,
      cardRef: card.scryfallId,
      anyPrinting: false,
      finish: d.finishFor(
        (card.nonFoilAvailable ? Finish.nonfoil : 0) | (card.foilAvailable ? Finish.foil : 0),
      ),
      languageCode: d.language,
      conditionCode: d.condition,
      setCode: card.setCode,
      setName: card.setName,
      collectorNumber: card.collectorNumber,
    );
  }

  /// A card in any printing — name only, no attributes: *any* until the user
  /// sets one in its detail.
  Future<int> _stageGeneric(ExternalList list, String name, String cardRef, {int quantity = 1}) =>
      _dao.stageAddition(
        listId: list.id,
        name: name,
        cardId: null,
        cardRef: cardRef,
        anyPrinting: true,
        finish: null,
        languageCode: null,
        conditionCode: null,
        quantity: quantity,
      );

  /// The list's rows holding copies — what a removal can come from.
  List<ExternalEntry> _holding(ExternalList list) =>
      [for (final e in _mirror) if (ExternalDao.countOn(list, e) > 0) e];

  /// A Tradelist's Inventory rows with **free** copies — owned, not yet for
  /// trade — what a mark can come from.
  List<ExternalEntry> _markable(ExternalList list) =>
      [for (final e in _mirror) if (ExternalDao.freeOf(e) > 0) e];

  /// Acts on a [RemovalMatch]: stages its one row — a removal, or with [mark]
  /// a mark for trade — asks between its rows, or says why nothing was
  /// staged. Returns the staged row's id, or -1.
  Future<int> _stageMatch(
    ExternalList list,
    RemovalMatch match, {
    required String Function(int rows) subtitle,
    int quantity = 1,
    bool mark = false,
  }) async {
    final ExternalEntry? row;
    switch (match) {
      case NotOnList(:final name):
        _toast(mark ? "$name isn't in your Inventory. Not staged." : "$name isn't in ${list.name}. Not staged.");
        return -1;
      case AllStaged(:final name):
        _toast(mark ? 'Every copy of $name is already for trade, or staged to be.' : 'All of $name is already staged to remove.');
        return -1;
      case StageRow(row: final only):
        row = only;
      case AskRows(:final rows):
        if (!mounted) return -1;
        final names = rows.map((e) => e.name).toSet();
        row = await WhichCopySheet.show(
          context,
          name: names.length == 1 ? names.single : 'card',
          subtitle: subtitle(rows.length),
          rows: rows,
          countOf: (e) => mark ? ExternalDao.freeOf(e) : ExternalDao.countOn(list, e),
          stagedOf: (e) => mark ? ExternalDao.freeOf(e) - _free(e) : ExternalDao.countOn(list, e) - _left(list, e),
        );
    }
    if (row == null) return -1;

    final took = mark
        ? await _dao.stageMark(list: list, row: row, quantity: quantity)
        : await _dao.stageRemoval(list: list, row: row, quantity: quantity);
    if (took == 0) {
      _toast(mark ? 'Every copy of ${row.name} is already for trade, or staged to be.' : 'All of ${row.name} is already staged to remove.');
      return -1;
    }
    if (took < quantity) {
      _toast(mark ? 'Only $took more of ${row.name} to mark — staged $took.' : 'Only $took more of ${row.name} to remove — staged $took.');
    }
    final key = row.identityKey;
    final direction = mark ? 'add' : 'remove';
    final id = (await _dao.stagedFor(list.id))
            .where((s) => s.direction == direction && s.identityKey == key)
            .firstOrNull
            ?.id ??
        -1;
    if (id >= 0 && mounted) setState(() => _lastStagedId = id);
    return id;
  }

  /// Copies of a mirrored row not yet staged to remove.
  int _left(ExternalList list, ExternalEntry e) =>
      ExternalDao.countOn(list, e) -
      _staged
          .where((s) => s.direction == 'remove' && s.identityKey == e.identityKey)
          .fold(0, (n, s) => n + s.quantity);

  /// Free copies of an Inventory row not yet staged to mark for trade.
  int _free(ExternalEntry e) =>
      ExternalDao.freeOf(e) -
      _staged
          .where((s) => s.direction == 'add' && s.identityKey == e.identityKey)
          .fold(0, (n, s) => n + s.quantity);

  /// An ambiguous scan into **To add**: with *Any printing* on, the printing
  /// is dropped anyway — so printings of one card are no question at all.
  List<Card> _narrow(List<Card> candidates) {
    final oneCard = candidates.map((c) => c.name).toSet().length == 1;
    return _addGeneric && oneCard ? [candidates.first] : candidates;
  }

  /// A discarded frame pulses the staged row it concerns.
  void _onDuplicate(ScryfallCard card) {
    final wanted = _target == ScanTarget.add ? 'add' : 'remove';
    final s = _staged
        .where((s) => s.direction == wanted && (s.cardId == card.scryfallId || (s.anyPrinting && s.name == card.name)))
        .firstOrNull;
    if (s == null) return;
    setState(() => _pulseStagedId = s.id);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _pulseStagedId == s.id) setState(() => _pulseStagedId = null);
    });
  }

  // ---------------------------------------------------------------------------
  // Manual add, pull, push
  // ---------------------------------------------------------------------------

  /// Manual Add, into **the target** — as a scan would be. Its tile steppers
  /// stage straight into it; the picker stays open for the next card.
  Future<void> _manualAdd() async {
    final list = _list;
    if (list == null) return;
    final subtitle = [?_account?.username, list.name].join(' · ');
    if (_target == ScanTarget.remove || _marking) {
      // A text filter over the rows it can come from: only printings on
      // Deckbox — to mark, only those with free copies — and an *Any
      // printing* tile per card with a generic row.
      final mark = _marking;
      final pool = mark ? _markable(list) : _holding(list);
      await CardPicker.showScreen(
        context,
        db: _cards,
        title: mark ? 'Mark for trade' : 'Remove a card',
        subtitle: subtitle,
        onlyOn: (
          printings: {for (final e in pool) if (!e.anyPrinting && e.cardId != null) e.cardId!},
          anyNames: {for (final e in pool) if (e.anyPrinting) e.name},
        ),
        sink: PickerSink(
          count: (card, any) => _stagedOn(list, card, any, _staged, mark: mark),
          bump: (card, any, delta) => _bumpStaged(list, card, any, delta, mark: mark),
        ),
      );
      return;
    }
    await CardPicker.showScreen(
      context,
      db: _cards,
      subtitle: subtitle,
      // Adding, on a Wishlist, it carries the *Any printing* chip.
      anyPrinting: _wishlist ? _anyPrinting : null,
      sink: PickerSink(
        count: (card, any) => _stagedAddition(list, card, any, _staged)?.quantity ?? 0,
        bump: (card, any, delta) => _bumpAddition(list, card, any, delta),
      ),
    );
  }

  /// The staged addition a + from the picker lands on: the printing on the
  /// scan defaults, or the card in any printing with nothing set.
  StagedChange? _stagedAddition(ExternalList list, Card card, bool any, List<StagedChange> staged) {
    final d = ScanDefaults.current;
    final key = ExternalDao.additionKey(
      name: card.name,
      cardId: any ? null : card.id,
      anyPrinting: any,
      finish: any ? null : d.finishFor(card.finishes),
      languageCode: any ? null : d.language,
      conditionCode: any ? null : d.condition,
    );
    return staged.where((s) => s.direction == 'add' && s.stageKey == key).firstOrNull;
  }

  Future<int> _bumpAddition(ExternalList list, Card card, bool any, int delta) async {
    if (delta > 0) {
      final id = any ? await _stageGeneric(list, card.name, card.id) : await _stagePrinting(list, card);
      if (mounted) setState(() => _lastStagedId = id);
    } else {
      final s = _stagedAddition(list, card, any, await _dao.stagedFor(list.id));
      if (s != null) await _dao.setStagedQuantity(s.id, s.quantity - 1);
    }
    return _stagedAddition(list, card, any, await _dao.stagedFor(list.id))?.quantity ?? 0;
  }

  /// [card] picked by hand: the exact printing, on the scan defaults.
  Future<int> _stagePrinting(ExternalList list, Card card) async {
    final set = await (_cards.select(_cards.sets)..where((x) => x.code.equals(card.setCode))).getSingleOrNull();
    final d = ScanDefaults.current;
    return _dao.stageAddition(
      listId: list.id,
      name: card.name,
      cardId: card.id,
      cardRef: card.id,
      anyPrinting: false,
      finish: d.finishFor(card.finishes),
      languageCode: d.language,
      conditionCode: d.condition,
      setCode: card.setCode,
      setName: set?.name ?? card.setCode.toUpperCase(),
      collectorNumber: card.collectorNumber,
    );
  }

  /// The rows a picker tile stands for in **To remove** — or, to [mark], in a
  /// Tradelist's To add: a printing's own rows, or — the *Any* tile — the
  /// card's generic rows.
  List<ExternalEntry> _tileRows(ExternalList list, Card card, bool any, {required bool mark}) => [
        for (final e in mark ? _markable(list) : _holding(list))
          if (any ? e.anyPrinting && e.name == card.name : !e.anyPrinting && e.cardId == card.id) e,
      ];

  /// Copies of a tile's rows staged — to remove, or to [mark].
  int _stagedOn(ExternalList list, Card card, bool any, List<StagedChange> staged, {required bool mark}) {
    final keys = {for (final e in _tileRows(list, card, any, mark: mark)) e.identityKey};
    final direction = mark ? 'add' : 'remove';
    return staged
        .where((s) => s.direction == direction && keys.contains(s.identityKey))
        .fold(0, (n, s) => n + s.quantity);
  }

  /// **+** stages one more from the tile's rows — several ask which; **−**
  /// takes back the one staged last.
  Future<int> _bumpStaged(ExternalList list, Card card, bool any, int delta, {required bool mark}) async {
    final rows = _tileRows(list, card, any, mark: mark);
    if (delta > 0) {
      await _stageMatch(
        list,
        RemovalMatcher.resolve(
          rows: rows,
          left: (e) => mark ? _free(e) : _left(list, e),
          candidates: [card],
          printingKnown: false,
        ),
        mark: mark,
        subtitle: (n) => any
            ? 'Any printing · $n rows on Deckbox'
            : '${card.setCode.toUpperCase()} · ${card.collectorNumber} · $n rows on Deckbox',
      );
    } else {
      final keys = {for (final e in rows) e.identityKey};
      final direction = mark ? 'add' : 'remove';
      final last = (await _dao.stagedFor(list.id))
          .where((s) => s.direction == direction && keys.contains(s.identityKey))
          .fold<StagedChange?>(null, (a, s) => a == null || s.stagedAt >= a.stagedAt ? s : a);
      if (last != null) await _dao.setStagedQuantity(last.id, last.quantity - 1);
    }
    return _stagedOn(list, card, any, await _dao.stagedFor(list.id), mark: mark);
  }

  Future<void> _pull() async {
    final list = _list;
    if (list == null) return;
    final outcome = await DeckboxSync.instance.pull(list);
    if (outcome case PullFailed(:final message)) AppLogger.w('Deckbox pull ${list.name}: $message');
  }

  /// No confirmation — decided in design: the staged sections *are* the
  /// review. A push already running is reopened, not started again.
  void _push() {
    final list = _list;
    if (list == null) return;
    final run = DeckboxSync.instance.startPush(list);
    DeckboxPushScreen.open(context, run, accountName: _account?.username);
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (list == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deckbox list')),
        body: const Center(child: Text('This list is no longer on this phone.')),
      );
    }

    final minSheet = _minSheetSize(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(
          child: ValueListenableBuilder<bool>(
            valueListenable: DevFlags.tuningTools,
            builder: (context, showTools, _) => ScannerOverlay(
              isActive: _cameraActive,
              showCaptureButton: false,
              showTuningButton: showTools,
              onCardAdded: _onCardScanned,
              onIdle: _onScannerIdle,
              onDuplicate: _onDuplicate,
              narrowCandidates: _target == ScanTarget.add && !_marking ? _narrow : null,
              // Into To remove the list resolves scans itself, between its
              // own rows — Choose Version never opens for a removal.
              onIdentified: _target == ScanTarget.remove || _marking ? _onScannedResolve : null,
            ),
          ),
        ),
        DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _maxSheetSize,
          minChildSize: minSheet,
          maxChildSize: _maxSheetSize,
          snap: true,
          snapSizes: _snaps(minSheet),
          builder: (context, scrollController) => DeckboxSheet(
            list: list,
            account: _account,
            mirror: _mirror,
            staged: _staged,
            scrollController: scrollController,
            sheetController: _sheetController,
            minSheetSize: minSheet,
            maxSheetSize: _maxSheetSize,
            cameraActive: _cameraActive,
            target: _target,
            onTargetChanged: (t) => setState(() {
              _target = t;
              _lastStagedId = null;
            }),
            onCollapse: _collapseToCamera,
            onManualAdd: _manualAdd,
            onPush: _push,
            onPull: _pull,
            onOpenStaged: (s) => DeckboxStagedScreen.open(context, stagedId: s.id, list: list),
            onOpenMirror: (e) => DeckboxMirrorScreen.open(context, list: list, entry: e),
            anyPrinting: list.kind == 'wishlist' ? _anyPrinting : null,
            lastStagedId: _lastStagedId,
            pulseStagedId: _pulseStagedId,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
