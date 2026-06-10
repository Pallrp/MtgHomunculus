import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../models/card_listing.dart';
import '../models/listing_card.dart';
import '../models/scryfall_card.dart';
import '../services/csv_exporter.dart';
import '../services/listing_storage.dart';
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
  final String listingId;

  const ListingDetailScreen({super.key, required this.listingId});

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

  CardListing? _listing;
  bool         _loading       = true;
  bool         _cameraActive  = true;
  bool         _detecting     = false;   // drives capture-button green tint
  bool         _scannerFrozen = false;   // hides button while result view is shown

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

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  Future<void> _loadListing() async {
    final listing = await ListingStorage.loadListing(widget.listingId);
    if (mounted) setState(() { _listing = listing; _loading = false; });
  }

  // ---------------------------------------------------------------------------
  // ScannerOverlay callbacks
  // ---------------------------------------------------------------------------

  /// Called by [ScanPipeline] when a card is matched.
  ///
  /// Deduplicates by (scryfallId, isFoil=false): increments qty if already
  /// present, creates a new [ListingCard] otherwise.
  /// Returns the [ListingCard.id] of the created or incremented entry.
  Future<String> _onCardAdded(ScryfallCard card) async {
    final listing = _listing;
    if (listing == null) return '';

    final existingIdx = listing.cards.indexWhere(
      (c) => c.printing.scryfallId == card.scryfallId && !c.isFoil,
    );

    final CardListing updated;
    final String listingCardId;

    if (existingIdx != -1) {
      // Duplicate — increment quantity.
      final existing = listing.cards[existingIdx];
      listingCardId  = existing.id;
      final cards    = [...listing.cards];
      cards[existingIdx] = existing.copyWith(quantity: existing.quantity + 1);
      updated = listing.copyWith(cards: cards);
    } else {
      // New entry.
      final newCard  = ListingCard.create(printing: card);
      listingCardId  = newCard.id;
      updated = listing.copyWith(cards: [...listing.cards, newCard]);
    }

    await ListingStorage.saveListing(updated);
    if (mounted) setState(() => _listing = updated);
    AppLogger.d('ListingDetailScreen: added "${card.name}" → $listingCardId');
    return listingCardId;
  }

  /// Called when the user picks a different printing or foil status from the
  /// printing browser sheet.  Fire-and-forget; errors are logged.
  void _onCardUpdated(String listingCardId, ScryfallCard newPrinting, bool isFoil) {
    _doCardUpdate(listingCardId, newPrinting, isFoil).catchError((Object e, StackTrace st) {
      AppLogger.e('ListingDetailScreen: update failed', error: e, stackTrace: st);
    });
  }

  Future<void> _doCardUpdate(
    String listingCardId, ScryfallCard newPrinting, bool isFoil,
  ) async {
    final listing = _listing;
    if (listing == null) return;
    final idx = listing.cards.indexWhere((c) => c.id == listingCardId);
    if (idx == -1) return;
    final cards = [...listing.cards];
    cards[idx] = listing.cards[idx].copyWith(printing: newPrinting, isFoil: isFoil);
    final updated = listing.copyWith(cards: cards);
    await ListingStorage.saveListing(updated);
    if (mounted) setState(() => _listing = updated);
  }

  // ---------------------------------------------------------------------------
  // Listing mutations (called from sheet rows)
  // ---------------------------------------------------------------------------

  Future<void> _deleteCard(String listingCardId) async {
    final listing = _listing;
    if (listing == null) return;
    final updated = listing.copyWith(
      cards: listing.cards.where((c) => c.id != listingCardId).toList(),
    );
    await ListingStorage.saveListing(updated);
    if (mounted) setState(() => _listing = updated);
  }

  Future<void> _setQuantity(String listingCardId, int qty) async {
    if (qty < 1) { await _deleteCard(listingCardId); return; }
    final listing = _listing;
    if (listing == null) return;
    final idx = listing.cards.indexWhere((c) => c.id == listingCardId);
    if (idx == -1) return;
    final cards = [...listing.cards];
    cards[idx] = listing.cards[idx].copyWith(quantity: qty);
    final updated = listing.copyWith(cards: cards);
    await ListingStorage.saveListing(updated);
    if (mounted) setState(() => _listing = updated);
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportCsv() async {
    final listing = _listing;
    if (listing == null) return;
    try {
      await CsvExporter.share(listing);
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
    if (_listing == null) {
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
              onPhaseChanged:     (f) => setState(() => _scannerFrozen = f),
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
              listing:          _listing!,
              scrollController: scrollController,
              sheetController:  _sheetController,
              minSheetSize:     _minSheetSize,
              cameraActive:     _cameraActive,
              detecting:        _detecting,
              scannerFrozen:    _scannerFrozen,
              onDeleteCard:     _deleteCard,
              onSetQuantity:    _setQuantity,
              onCardTap: (id) {
                final card = _listing!.cards.firstWhere((c) => c.id == id);
                PrintingBrowserSheet.show(
                  context,
                  card:          card.printing,
                  listingCardId: id,
                  isFoil:        card.isFoil,
                  onUpdated:     _onCardUpdated,
                );
              },
              onCapture: () => _scannerKey.currentState?.capture(),
              onReset:   () => _scannerKey.currentState?.reset(),
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

          // Export button overlaid top-right — disabled when listing is empty.
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  icon:      const Icon(Icons.share_rounded),
                  color:     Colors.white,
                  style:     IconButton.styleFrom(backgroundColor: Colors.black45),
                  tooltip:   'Export as CSV',
                  onPressed: _listing!.cards.isNotEmpty ? _exportCsv : null,
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
  final CardListing                        listing;
  final ScrollController                   scrollController;
  final DraggableScrollableController      sheetController;
  final double                             minSheetSize;
  final bool                               cameraActive;
  final bool                               detecting;
  final bool                               scannerFrozen;
  final Future<void> Function(String id)           onDeleteCard;
  final Future<void> Function(String id, int qty)  onSetQuantity;
  final void Function(String id)                   onCardTap;
  final VoidCallback                               onCapture;
  final VoidCallback                               onReset;

  const _ListingPanel({
    required this.listing,
    required this.scrollController,
    required this.sheetController,
    required this.minSheetSize,
    required this.cameraActive,
    required this.detecting,
    required this.scannerFrozen,
    required this.onDeleteCard,
    required this.onSetQuantity,
    required this.onCardTap,
    required this.onCapture,
    required this.onReset,
  });

  // Half the CaptureButton height — the button straddles this offset so its
  // top half floats in the camera feed and its bottom half rests on the surface.
  static const double _buttonHalf = 34.0;

  // ── Camera-button helpers ─────────────────────────────────────────────────

  IconData get _cameraIcon {
    if (scannerFrozen) return Icons.replay_rounded;
    if (!cameraActive) return Icons.keyboard_arrow_down_rounded;
    return Icons.camera_alt_rounded;
  }

  VoidCallback _cameraTap(BuildContext context) {
    if (scannerFrozen) return onReset;
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
                            listing.name,
                            style:    Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${listing.cardCount} copy(s)',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: Divider(height: 1)),

                // Card list or empty-state placeholder.
                if (listing.cards.isEmpty)
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
                        final card = listing.cards[index ~/ 2];
                        return _ListingCardRow(
                          card:     card,
                          onTap:    () => onCardTap(card.id),
                          onDelete: () => onDeleteCard(card.id),
                          onSetQty: (qty) => onSetQuantity(card.id, qty),
                        );
                      },
                      childCount: listing.cards.length * 2 - 1,
                    ),
                  ),
              ],
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
              detecting:       detecting && cameraActive && !scannerFrozen,
              onTap:           _cameraTap(context),
              icon:            _cameraIcon,
              backgroundColor: scannerFrozen
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)
                  : null,
              iconColor: scannerFrozen ? Colors.white : null,
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
  final ListingCard card;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(int qty) onSetQty;

  const _ListingCardRow({
    required this.card,
    required this.onTap,
    required this.onDelete,
    required this.onSetQty,
  });

  @override
  Widget build(BuildContext context) {
    final p  = card.printing;
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
                '${card.quantity}×',
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
                    child: p.imageUri != null
                        ? Image.network(
                            p.imageUri!,
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
                          p.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${p.setCode.toUpperCase()} · ${p.collectorNumber}',
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ),
                            if (card.isFoil) ...[
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
        initial:  card.quantity,
        cardName: card.printing.name,
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
