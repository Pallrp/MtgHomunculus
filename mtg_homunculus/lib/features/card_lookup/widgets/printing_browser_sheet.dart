import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../models/scryfall_card.dart';
import '../services/scryfall_client.dart';

/// Modal bottom sheet for browsing all English printings of a card and
/// toggling foil status.
///
/// Open via [PrintingBrowserSheet.show].  On **Apply**, [onUpdated] is called
/// with the (possibly changed) printing and foil flag, then the sheet is
/// dismissed.  Tapping × or dragging down dismisses without a callback.
class PrintingBrowserSheet extends StatefulWidget {
  /// The printing returned by the scan pipeline (becomes the initial selection).
  final ScryfallCard initialCard;

  /// The [ListingCard.id] to update — forwarded unchanged to [onUpdated].
  final String listingCardId;

  /// Whether this entry is currently marked foil.
  /// Defaults to false for auto-scanned cards.
  final bool initialIsFoil;

  /// Called when the user taps **Apply**.
  ///
  /// Receives the (possibly unchanged) [listingCardId], the selected printing,
  /// and the foil flag.  Null is valid for Quick Scan (no listing) — the sheet
  /// still dismisses without calling back.
  final void Function(
    String listingCardId,
    ScryfallCard newPrinting,
    bool isFoil,
  )? onUpdated;

  const PrintingBrowserSheet({
    super.key,
    required this.initialCard,
    required this.listingCardId,
    this.initialIsFoil = false,
    this.onUpdated,
  });

  // ---------------------------------------------------------------------------
  // Show helper
  // ---------------------------------------------------------------------------

  /// Shows [PrintingBrowserSheet] as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required ScryfallCard card,
    required String listingCardId,
    bool isFoil = false,
    void Function(String, ScryfallCard, bool)? onUpdated,
  }) =>
      showModalBottomSheet<void>(
        context:            context,
        isScrollControlled: true,
        useSafeArea:        true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => PrintingBrowserSheet(
          initialCard:   card,
          listingCardId: listingCardId,
          initialIsFoil: isFoil,
          onUpdated:     onUpdated,
        ),
      );

  @override
  State<PrintingBrowserSheet> createState() => _PrintingBrowserSheetState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _PrintingBrowserSheetState extends State<PrintingBrowserSheet> {
  late ScryfallCard _selected;
  late bool         _isFoil;

  List<ScryfallCard>? _printings;  // null → loading
  String?             _errorMsg;   // non-null → fetch failed

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCard;
    _isFoil   = widget.initialIsFoil;
    _fetchPrintings();
  }

  Future<void> _fetchPrintings() async {
    try {
      final printings = await ScryfallClient.allPrintings(widget.initialCard.name);
      if (!mounted) return;
      setState(() {
        _printings = printings;
        // Keep initial selection when it is in the list; fall back to first.
        if (printings.isNotEmpty &&
            !printings.any((p) => p.scryfallId == _selected.scryfallId)) {
          _selected = printings.first;
        }
      });
    } catch (e, st) {
      AppLogger.w('PrintingBrowserSheet: fetch failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() => _errorMsg = 'Could not load printings.\nCheck your connection.');
    }
  }

  void _confirm() {
    widget.onUpdated?.call(widget.listingCardId, _selected, _isFoil);
    Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand:           false,
      initialChildSize: 0.72,
      minChildSize:     0.45,
      maxChildSize:     0.92,
      builder: (_, scrollController) => Column(
        children: [
          const _DragHandle(),
          _SheetHeader(
            cardName: widget.initialCard.name,
            onClose:  () => Navigator.pop(context),
          ),
          const Divider(height: 1),
          _FoilToggle(
            // Guard: only show isFoil=true when the selected printing supports it.
            isFoil:    _isFoil && _selected.foilAvailable,
            available: _selected.foilAvailable,
            onChanged: (v) => setState(() => _isFoil = v),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'All printings',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: _buildList(scrollController)),
          // Apply button — pinned at bottom, above system nav bar.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirm,
                  child:     const Text('Apply'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ScrollController controller) {
    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:   Text(_errorMsg!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_printings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_printings!.isEmpty) {
      return const Center(child: Text('No printings found.'));
    }

    return ListView.separated(
      controller:       controller,
      itemCount:        _printings!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final p          = _printings![index];
        final isSelected = p.scryfallId == _selected.scryfallId;
        return _PrintingRow(
          printing:   p,
          isSelected: isSelected,
          onTap:      () => setState(() {
            _selected = p;
            // Clear foil if the new printing doesn't support it.
            if (_isFoil && !p.foilAvailable) _isFoil = false;
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width:  40,
          height: 4,
          decoration: BoxDecoration(
            color:        Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _SheetHeader extends StatelessWidget {
  final String      cardName;
  final VoidCallback onClose;

  const _SheetHeader({required this.cardName, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Text(
                  'Change printing',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cardName,
                  style:    Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon:      const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _FoilToggle extends StatelessWidget {
  final bool               isFoil;
  final bool               available;
  final ValueChanged<bool>  onChanged;

  const _FoilToggle({
    required this.isFoil,
    required this.available,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title:    const Text('Foil'),
      subtitle: available
          ? null
          : Text(
              'Not available for this printing',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
      value:     isFoil,
      onChanged: available ? onChanged : null,
    );
  }
}

class _PrintingRow extends StatelessWidget {
  final ScryfallCard printing;
  final bool         isSelected;
  final VoidCallback onTap;

  const _PrintingRow({
    required this.printing,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Thumbnail.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: printing.imageUri != null
                  ? Image.network(
                      printing.imageUri!,
                      width: 36, height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _PlaceholderThumb(),
                    )
                  : const _PlaceholderThumb(),
            ),
            const SizedBox(width: 12),

            // Set name + collector number + price.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    printing.setName,
                    overflow: TextOverflow.ellipsis,
                    style:    Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${printing.setCode.toUpperCase()} · #${printing.collectorNumber}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (printing.priceUsd != null || printing.priceEur != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (printing.priceUsd != null)
                          '\$${printing.priceUsd!.toStringAsFixed(2)}',
                        if (printing.priceEur != null)
                          '€${printing.priceEur!.toStringAsFixed(2)}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.primary),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Checkmark — always rendered; transparent when not selected so
            // row width stays constant.
            Icon(
              Icons.check_rounded,
              color: isSelected ? cs.primary : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

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
          size:  18,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
}
