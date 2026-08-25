import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../data/collection_database.dart';
import '../models/scryfall_card.dart';
import '../services/csv_exporter.dart';
import '../widgets/printing_browser_sheet.dart';
import '../widgets/scanner_overlay.dart' show ScannerOverlay, ScannerOverlayState, CaptureButton;

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
  static const double _midSheetSize    = 0.50;
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
    final id = await _db.addCard(
      listId:          widget.listId,
      cardId:          card.scryfallId,
      name:            card.name,
      setCode:         card.setCode,
      collectorNumber: card.collectorNumber,
    );
    AppLogger.d('ListingDetailScreen: added "${card.name}" -> $id');
    return id;
  }

  /// Called when the user picks a different printing or foil status from the
  /// printing browser sheet.  Fire-and-forget; errors are logged.
  void _onCardUpdated(int entryId, ScryfallCard newPrinting, bool isFoil) {
    _doCardUpdate(entryId, newPrinting, isFoil).catchError((Object e, StackTrace st) {
      AppLogger.e('ListingDetailScreen: update failed', error: e, stackTrace: st);
    });
  }

  Future<void> _doCardUpdate(
    int entryId, ScryfallCard newPrinting, bool isFoil,
  ) async {
    await _db.updateEntry(
      entryId,
      cardId:          newPrinting.scryfallId,
      name:            newPrinting.name,
      setCode:         newPrinting.setCode,
      collectorNumber: newPrinting.collectorNumber,
      finish:          isFoil ? Finish.foil : Finish.nonfoil,
    );
  }

  // ---------------------------------------------------------------------------
  // Listing mutations (called from sheet rows)
  // ---------------------------------------------------------------------------

  /// Adapt an entry to the model the printing browser speaks.
  ///
  /// Built from the snapshot rather than a `cards.db` lookup, so it holds only
  /// what the row itself knows — enough to open the browser, which then fetches
  /// the printings it lists.
  ScryfallCard _asScryfallCard(Entry e) => ScryfallCard.fromLocal(
        id:              e.cardId,
        name:            e.snapName,
        setCode:         e.snapSetCode,
        setName:         e.snapSetCode.toUpperCase(),
        collectorNumber: e.snapCollector,
        finishes:        e.finish,
      );

  Future<void> _deleteCard(int entryId) => _db.removeEntry(entryId);

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
              onCardUpdated:      _onCardUpdated,
              onDetectionChanged: (d) => setState(() => _detecting     = d),
              onIdle:             _onScannerIdle,
            ),
          ),

          // Draggable listing sheet.
          DraggableScrollableSheet(
            controller:       _sheetController,
            initialChildSize: _minSheetSize,
            minChildSize:     _minSheetSize,
            maxChildSize:     _maxSheetSize,
            snap:             true,
            snapSizes:        const [_minSheetSize, _midSheetSize, _maxSheetSize],
            builder: (context, scrollController) => _ListingPanel(
              listName:         _list!.name,
              entries:          _entries,
              scrollController: scrollController,
              sheetController:  _sheetController,
              minSheetSize:     _minSheetSize,
              cameraActive:     _cameraActive,
              detecting:        _detecting,
              onDeleteCard:     _deleteCard,
              onSetQuantity:    _setQuantity,
              onCardTap: (entry) => PrintingBrowserSheet.show(
                context,
                card:      _asScryfallCard(entry),
                entryId:   entry.id,
                isFoil:    entry.finish == Finish.foil,
                onUpdated: _onCardUpdated,
              ),
              onCapture: () => _scannerKey.currentState?.capture(),
              onExportCsv: _exportCsv,
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

// ---------------------------------------------------------------------------
// Listing panel (bottom sheet content)
// ---------------------------------------------------------------------------

class _ListingPanel extends StatelessWidget {
  final String                             listName;
  final List<Entry>                        entries;
  final ScrollController                   scrollController;
  final DraggableScrollableController      sheetController;
  final double                             minSheetSize;
  final bool                               cameraActive;
  final bool                               detecting;
  final Future<void> Function(int id)           onDeleteCard;
  final Future<void> Function(int id, int qty)  onSetQuantity;
  final void Function(Entry entry)              onCardTap;
  final VoidCallback                            onCapture;
  final VoidCallback                            onExportCsv;

  /// Total copies, which is not the row count as soon as anything is held in
  /// multiples.
  int get _copies => entries.fold(0, (n, e) => n + e.quantity);

  const _ListingPanel({
    required this.listName,
    required this.entries,
    required this.scrollController,
    required this.sheetController,
    required this.minSheetSize,
    required this.cameraActive,
    required this.detecting,
    required this.onDeleteCard,
    required this.onSetQuantity,
    required this.onCardTap,
    required this.onCapture,
    required this.onExportCsv,
  });

  // Half the CaptureButton height — the button straddles this offset so its
  // top half floats in the camera feed and its bottom half rests on the surface.
  static const double _buttonHalf = 34.0;

  // ── Camera-button helpers ─────────────────────────────────────────────────

  IconData get _cameraIcon {
    if (!cameraActive) return Icons.keyboard_arrow_down_rounded;
    return Icons.camera_alt_rounded;
  }

  VoidCallback _cameraTap(BuildContext context) {
    if (!cameraActive) {
      return () => sheetController.animateTo(
            minSheetSize,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
    }
    return onCapture;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // ── Sheet surface ─────────────────────────────────────────────────
        // Starts at the button's vertical centre so the button straddles the
        // rounded top edge: bottom half on the surface, top half above it
        // (camera feed visible through the transparent Stack area).
        //
        // Dragging works naturally: the entire CustomScrollView is wired to
        // the DraggableScrollableSheet's scrollController, so overscrolling
        // anywhere — header or card list — expands / collapses the sheet.
        Positioned(
          top: _buttonHalf, left: 0, right: 0, bottom: 0,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color:        cs.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow:    const [BoxShadow(color: Colors.black38, blurRadius: 10)],
              ),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                // Header — top padding clears the button's lower half so the
                // title text never hides behind it.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, _buttonHalf, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            listName,
                            style:    Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$_copies copy(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon:      const Icon(Icons.share_rounded),
                          tooltip:   'Export as CSV',
                          onPressed: entries.isNotEmpty ? onExportCsv : null,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          padding:   EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: Divider(height: 1)),

                // Card list or empty-state placeholder.
                if (entries.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No cards yet — scan to add.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, index) {
                        if (index.isOdd) return const Divider(height: 1);
                        final entry = entries[index ~/ 2];
                        return _ListingCardRow(
                          entry:    entry,
                          onTap:    () => onCardTap(entry),
                          onDelete: () => onDeleteCard(entry.id),
                          onSetQty: (qty) => onSetQuantity(entry.id, qty),
                        );
                      },
                      childCount: entries.length * 2 - 1,
                    ),
                  ),
              ],
              ),
            ),
          ),
        ),

        // ── Capture button ────────────────────────────────────────────────
        // Positioned at top: 0 so its centre sits exactly on the container's
        // top edge.  Tap-only — dragging is handled by the CustomScrollView.
        Positioned(
          top: 0, left: 0, right: 0,
          child: Center(
            child: CaptureButton(
              detecting: detecting && cameraActive,
              onTap:     _cameraTap(context),
              icon:      _cameraIcon,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Listing card row
// ---------------------------------------------------------------------------

class _ListingCardRow extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(int qty) onSetQty;

  const _ListingCardRow({
    required this.entry,
    required this.onTap,
    required this.onDelete,
    required this.onSetQty,
  });

  @override
  Widget build(BuildContext context) {
    // Rendered from the entry's own snapshot, not a cards.db lookup: a list has
    // to stay readable with the card cache wiped.
    final imageUri = ScryfallCard.imageUrlFor(entry.cardId, null, size: 'small');
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Qty — tappable to open qty editor.
        SizedBox(
          width: 48,
          child: GestureDetector(
            onTap: () => _showQtyDialog(context),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Text(
                '${entry.quantity}×',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
        ),

        // Thumbnail + name + set info — tappable to open printing browser.
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  // Thumbnail.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: imageUri != null
                        ? Image.network(
                            imageUri,
                            width: 36, height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _PlaceholderThumb(),
                          )
                        : const _PlaceholderThumb(),
                  ),
                  const SizedBox(width: 10),

                  // Name + set line.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.snapName,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${entry.snapSetCode.toUpperCase()} · ${entry.snapCollector}',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            if (entry.finish != Finish.nonfoil) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color:        Colors.amber.shade700,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'foil',
                                  style: TextStyle(
                                    color: Colors.white, fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Delete button.
        IconButton(
          icon:    const Icon(Icons.delete_outline_rounded, size: 20),
          color:   cs.error,
          tooltip: 'Remove',
          onPressed: onDelete,
        ),
      ],
    );
  }

  Future<void> _showQtyDialog(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _QtyDialog(
        initial:  entry.quantity,
        cardName: entry.snapName,
      ),
    );
    if (result != null) onSetQty(result);
  }
}

// ---------------------------------------------------------------------------
// Qty editor dialog
// ---------------------------------------------------------------------------

class _QtyDialog extends StatefulWidget {
  final int    initial;
  final String cardName;

  const _QtyDialog({required this.initial, required this.cardName});

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  late int _qty;

  @override
  void initState() {
    super.initState();
    _qty = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.cardName, overflow: TextOverflow.ellipsis),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon:      const Icon(Icons.remove_rounded),
            onPressed: _qty > 0 ? () => setState(() => _qty--) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '$_qty',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton(
            icon:      const Icon(Icons.add_rounded),
            onPressed: () => setState(() => _qty++),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _qty),
          child: Text(_qty == 0 ? 'Remove' : 'Done'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _PlaceholderThumb extends StatelessWidget {
  const _PlaceholderThumb();

  @override
  Widget build(BuildContext context) => Container(
        width: 36, height: 50,
        decoration: BoxDecoration(
          color:        Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.style_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
}
