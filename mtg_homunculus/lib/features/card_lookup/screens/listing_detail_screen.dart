import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../widgets/listing_sheet.dart';
import '../services/csv_exporter.dart';
import 'card_detail_screen.dart';
import '../widgets/scanner_overlay.dart' show ScannerOverlay, ScannerOverlayState;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Shows the camera scanner overlay and the listing's card collection in a
/// draggable bottom sheet.
///
/// The camera stream is active only while the sheet handle is fully collapsed
/// ([_minSheetSize]).  Dragging the sheet upward pauses the camera.
class ListingDetailScreen extends StatefulWidget {
  final int listId;

  const ListingDetailScreen({super.key, required this.listId});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  // Sheet constants.
  // _minSheetSize must fit: button-half (34 px) + title row + divider + a
  // small peek of the card list below.
  static const double _minSheetSize    = 0.14;
  static const double _maxSheetSize    = 0.88;
  // Camera is active only when the sheet is at or near its minimum size.
  static const double _activeThreshold = _minSheetSize + 0.03;

  final _sheetController = DraggableScrollableController();
  final _scannerKey      = GlobalKey<ScannerOverlayState>();

  CardList?    _list;
  List<Entry>  _entries       = const [];
  StreamSubscription<List<Entry>>? _entriesSub;
  bool         _loading       = true;
  bool         _cameraActive  = true;
  bool         _detecting     = false;   // drives capture-button green tint

  EntrySort    _sort          = EntrySort.scanned;
  Set<int>     _selected      = const {};

  /// The row to pulse: a frame was discarded because this card is already the
  /// last one added. Cleared on a timer so a later discard re-triggers it.
  int?         _pulseEntryId;

  // ---------------------------------------------------------------------------
  // Init / dispose
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetChange);
    _loadListing();
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChange);
    _sheetController.dispose();
    _entriesSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sheet listener
  // ---------------------------------------------------------------------------

  void _onSheetChange() {
    if (!_sheetController.isAttached) return;
    final active = _sheetController.size <= _activeThreshold;
    if (active != _cameraActive) setState(() => _cameraActive = active);
  }

  /// Nothing detected for 30 seconds — open the sheet.
  ///
  /// Expanding stops the camera through [_onSheetChange], so this needs no
  /// separate blackout state: one gesture, one state, and reviewing what you
  /// collected is the likely next thing anyway.
  void _onScannerIdle() {
    if (!_sheetController.isAttached) return;
    if (_sheetController.size > _activeThreshold) return; // already open
    _sheetController.animateTo(
      _maxSheetSize,
      duration: const Duration(milliseconds: 280),
      curve:    Curves.easeOut,
    );
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  CollectionDatabase get _db => CollectionDatabase.instance;

  /// Opened lazily and kept: Card Detail needs it for the finish control, which
  /// has to know what the printing actually came in.
  CardsDatabase? _cardsDb;
  CardsDatabase get _cards => _cardsDb ??= CardsDatabase();

  /// Entries arrive as a stream, so a card added by the scan loop shows up
  /// without the screen having to know a scan happened.
  Future<void> _loadListing() async {
    final list = await _db.listById(widget.listId);
    if (!mounted) return;
    setState(() { _list = list; _loading = false; });
    _entriesSub = _db.watchEntries(widget.listId).listen((rows) {
      if (mounted) setState(() => _entries = rows);
    });
  }

  // ---------------------------------------------------------------------------
  // ScannerOverlay callbacks
  // ---------------------------------------------------------------------------

  /// Called by [ScanPipeline] when a card is matched.
  ///
  /// The variant key does the deduplicating: a scan supplies no finish,
  /// language or condition, so it lands on the app-wide defaults and any
  /// further copy of that same variant increments rather than adding a row.
  /// Returns the entry id of the created or incremented row.
  Future<int> _onCardAdded(ScryfallCard card) async {
    // A scan cannot see finish, language or condition, so the user's defaults
    // are what it lands on — `finishFor` keeps a nonfoil default off a printing
    // that was never made nonfoil.
    final d = ScanDefaults.current;
    final id = await _db.addCard(
      listId:          widget.listId,
      cardId:          card.scryfallId,
      name:            card.name,
      setCode:         card.setCode,
      setName:         card.setName,
      collectorNumber: card.collectorNumber,
      finish:          d.finishFor(
        (card.nonFoilAvailable ? Finish.nonfoil : 0) |
            (card.foilAvailable ? Finish.foil : 0),
      ),
      language:        d.language,
      condition:       d.condition,
    );
    AppLogger.d('ListingDetailScreen: added "${card.name}" '
        '[${card.setCode.toUpperCase()} ${card.collectorNumber}] -> entry $id');
    return id;
  }

  /// Card Detail is the one place a scan is corrected after the fact.
  ///
  /// Pushed from here rather than from inside the overlay: it is a screen, and
  /// the camera should not keep running underneath one. Entries arrive by
  /// stream, so whatever it changes shows up without being reported back.
  Future<void> _openDetail(int entryId) => CardDetailScreen.open(
        context,
        entryId: entryId,
        collection: _db,
        cards: _cards,
      );

  // ---------------------------------------------------------------------------
  // Listing mutations (called from sheet rows)
  // ---------------------------------------------------------------------------

  Future<void> _deleteCard(int entryId) => _db.removeEntry(entryId);

  /// Cut or copy the selection into another list.
  Future<void> _moveTo(Set<int> ids, bool move) async {
    final target = await _pickList(exclude: widget.listId);
    if (target == null) return;
    await (move ? _db.cutTo(ids, target) : _db.copyTo(ids, target));
    if (mounted) setState(() => _selected = const {});
  }

  Future<void> _deleteSelected(Set<int> ids) async {
    for (final id in ids) {
      await _db.removeEntry(id);
    }
    if (mounted) setState(() => _selected = const {});
  }

  /// Destination picker — what the trailing preposition in "Cut to" promises.
  Future<int?> _pickList({required int exclude}) async {
    final lists = (await _db.allLists()).where((l) => l.id != exclude).toList();
    if (!mounted || lists.isEmpty) return null;
    return showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in lists)
              ListTile(
                title: Text(l.name),
                onTap: () => Navigator.of(sheetContext).pop(l.id),
              ),
          ],
        ),
      ),
    );
  }

  /// A discarded frame reaches the sheet as a pulse on the row it concerns.
  ///
  /// Matched by printing rather than entry id, because a discarded frame was
  /// never added and so has no entry of its own — the row it belongs to is
  /// whichever one already holds that card.
  void _onDuplicate(ScryfallCard card) {
    for (final e in _entries) {
      if (e.cardId == card.scryfallId) {
        _pulse(e.id);
        return;
      }
    }
  }

  void _pulse(int entryId) {
    setState(() => _pulseEntryId = entryId);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && _pulseEntryId == entryId) {
        setState(() => _pulseEntryId = null);
      }
    });
  }

  /// Zero deletes — see [CollectionDatabase.setQuantity].
  Future<void> _setQuantity(int entryId, int qty) =>
      _db.setQuantity(entryId, qty);

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportCsv() async {
    final list = _list;
    if (list == null) return;
    try {
      await CsvExporter.share(name: list.name, entries: _entries);
    } catch (e, st) {
      AppLogger.e('CSV export failed', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_list == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Listing')),
        body: const Center(child: Text('Listing not found.')),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen camera overlay.
          Positioned.fill(
            child: ScannerOverlay(
              key:                _scannerKey,
              isActive:           _cameraActive,
              showCaptureButton:  false,
              onCardAdded:        _onCardAdded,
              onEntryTapped:      _openDetail,
              onDetectionChanged: (d) => setState(() => _detecting     = d),
              onIdle:             _onScannerIdle,
              onDuplicate:        _onDuplicate,
            ),
          ),

          // Draggable listing sheet.
          DraggableScrollableSheet(
            controller:       _sheetController,
            initialChildSize: _minSheetSize,
            minChildSize:     _minSheetSize,
            maxChildSize:     _maxSheetSize,
            snap:             true,
            // Peek and full only. A third stop would need its own answer to
            // "is the camera on?", which nobody could predict.
            snapSizes:        const [_minSheetSize, _maxSheetSize],
            builder: (context, scrollController) => ListingSheet(
              listName:         _list!.name,
              entries:          _entries,
              scrollController: scrollController,
              sheetController:  _sheetController,
              minSheetSize:     _minSheetSize,
              cameraActive:     _cameraActive,
              detecting:        _detecting,
              pulseEntryId:     _pulseEntryId,
              onDeleteCard:     _deleteCard,
              onSetQuantity:    _setQuantity,
              onCardTap:        (entry) => _openDetail(entry.id),
              onCapture:        () => _scannerKey.currentState?.capture(),
              onExportCsv:      _exportCsv,
              sort:             _sort,
              onSortChanged:    (s) => setState(() => _sort = s),
              selected:         _selected,
              onSelectionChanged: (s) => setState(() => _selected = s),
              onMoveTo:         _moveTo,
              onDeleteSelected: _deleteSelected,
            ),
          ),

          // Back button overlaid top-left (no AppBar in full-screen layout).
          Positioned(
            top: 0, left: 0,
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

        ],
      ),
    );
  }
}
