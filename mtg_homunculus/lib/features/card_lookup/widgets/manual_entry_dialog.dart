import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../models/scryfall_card.dart';
import '../services/scryfall_client.dart';

/// Dialog for manually entering (or correcting) a card name when automatic
/// OCR recognition has failed.
///
/// Pre-filled with [ocrText] (the raw OCR output, possibly empty).  If
/// [ocrText] is non-empty the dialog auto-searches on open so the user
/// immediately sees whether the garbled text happened to match.
///
/// Flow:
///   1. User reads / edits the text field.
///   2. Taps **Search** (or presses Enter) → Scryfall fuzzy lookup.
///   3. If matched → card preview appears; **Add** persists it and closes.
///   4. If not found → error hint; user edits and retries.
///
/// Open via [ManualEntryDialog.show].
class ManualEntryDialog extends StatefulWidget {
  /// Raw OCR text to pre-fill (may be empty string).
  final String ocrText;

  /// Called with the matched card when the user taps **Add**.
  /// Null is valid for Quick Scan (no listing) — the dialog still closes.
  final Future<String> Function(ScryfallCard)? onCardAdded;

  const ManualEntryDialog({
    super.key,
    required this.ocrText,
    this.onCardAdded,
  });

  /// Shows [ManualEntryDialog] as a modal dialog.
  static Future<void> show(
    BuildContext context, {
    required String ocrText,
    Future<String> Function(ScryfallCard)? onCardAdded,
  }) =>
      showDialog<void>(
        context: context,
        builder: (_) => ManualEntryDialog(
          ocrText:     ocrText,
          onCardAdded: onCardAdded,
        ),
      );

  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  late final TextEditingController _controller;

  bool          _searching = false;
  bool          _adding    = false;
  ScryfallCard? _found;
  bool          _notFound  = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.ocrText);
    // Auto-search on open when OCR text is non-empty.
    if (widget.ocrText.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;

    setState(() {
      _searching = true;
      _found     = null;
      _notFound  = false;
    });

    try {
      final card = await ScryfallClient.namedFuzzy(query);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found     = card;
        _notFound  = card == null;
      });
    } catch (e, st) {
      AppLogger.w('ManualEntryDialog: search error', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _notFound  = true;
      });
    }
  }

  Future<void> _add() async {
    final card = _found;
    if (card == null || _adding) return;

    setState(() => _adding = true);
    try {
      await widget.onCardAdded?.call(card);
    } catch (e, st) {
      AppLogger.w('ManualEntryDialog: onCardAdded error', error: e, stackTrace: st);
    }
    if (mounted) Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manual entry'),
      // SizedBox(width: double.maxFinite) lets the dialog be as wide as the
      // theme allows rather than shrinking to the content's intrinsic width.
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search row ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:      _controller,
                    autofocus:       true,
                    textInputAction: TextInputAction.search,
                    onSubmitted:     (_) => _search(),
                    decoration: const InputDecoration(
                      hintText:       'Card name',
                      border:         OutlineInputBorder(),
                      isDense:        true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon:      const Icon(Icons.search_rounded),
                  onPressed: _searching ? null : _search,
                  tooltip:   'Search Scryfall',
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Result area ─────────────────────────────────────────────────
            if (_searching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child:   CircularProgressIndicator(),
                ),
              )
            else if (_found != null)
              _CardPreview(card: _found!)
            else if (_notFound)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size:  18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'No card found. Try a different spelling.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:     const Text('Cancel'),
        ),
        if (_found != null)
          FilledButton(
            onPressed: _adding ? null : _add,
            child: _adding
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Add'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Card preview
// ---------------------------------------------------------------------------

class _CardPreview extends StatelessWidget {
  final ScryfallCard card;

  const _CardPreview({required this.card});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Thumbnail.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: card.imageUri != null
                ? Image.network(
                    card.imageUri!,
                    width: 36, height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _PlaceholderThumb(),
                  )
                : const _PlaceholderThumb(),
          ),
          const SizedBox(width: 10),

          // Card details.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  card.setName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '${card.setCode.toUpperCase()} · #${card.collectorNumber}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (card.priceUsd != null || card.priceEur != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (card.priceUsd != null)
                        '\$${card.priceUsd!.toStringAsFixed(2)}',
                      if (card.priceEur != null)
                        '€${card.priceEur!.toStringAsFixed(2)}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: cs.primary),
                  ),
                ],
              ],
            ),
          ),
        ],
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
