// `Card` here is a printing from the local database, not Material's widget —
// which is not used on this screen.
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart' hide Card;

import '../data/cards_database.dart';
import '../models/scryfall_card.dart';

/// The one interruption the scanner is allowed.
///
/// Fires when identification returns more than one candidate, which is not a
/// failure but a structural outcome: reprints with identical art hash
/// identically, and a card name alone cannot determine a printing — "Forest"
/// matches hundreds. Whenever the collector number cannot be read, ambiguity is
/// guaranteed, and this is the designed answer to it.
///
/// **The card is not added until the user picks.** No ambiguous row state, no
/// cleanup later. A silently wrong printing is hard to notice and the correction
/// cost grows the longer a session runs, which is what justifies breaking the
/// no-interruption rule here and nowhere else.
class ChooseVersionSheet extends StatefulWidget {
  /// Candidates from the scan, best first.
  final List<Card> candidates;

  final CardsDatabase db;

  const ChooseVersionSheet({
    super.key,
    required this.candidates,
    required this.db,
  });

  /// Returns the chosen printing, or null if the user skipped.
  static Future<Card?> show(
    BuildContext context, {
    required List<Card> candidates,
    required CardsDatabase db,
  }) =>
      showModalBottomSheet<Card>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ChooseVersionSheet(candidates: candidates, db: db),
      );

  @override
  State<ChooseVersionSheet> createState() => _ChooseVersionSheetState();
}

class _ChooseVersionSheetState extends State<ChooseVersionSheet> {
  late List<Card> _shown = widget.candidates;
  bool _widened = false;
  bool _loading = false;

  /// Widen to every printing of the same name.
  ///
  /// The scan narrowed to a few; this is the escape when the right one is not
  /// among them — usually because the collector number was misread rather than
  /// unread, so the wrong printings scored highest.
  Future<void> _moreVersions() async {
    if (_widened || _shown.isEmpty) return;
    setState(() => _loading = true);
    final names = {for (final c in widget.candidates) c.name};
    final all = <Card>[];
    for (final n in names) {
      all.addAll(await (widget.db.select(widget.db.cards)
            ..where((c) => c.name.equals(n))
            ..orderBy([(c) => OrderingTerm.desc(c.releasedAt)]))
          .get());
    }
    if (!mounted) return;
    setState(() {
      _shown = all;
      _widened = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      minChildSize: 0.4,
      builder: (context, scrollController) => Column(
        children: [
          // ── header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose version',
                          style: theme.textTheme.titleMedium),
                      Text(
                        _widened
                            ? '${_shown.length} printings'
                            : '${_shown.length} possible matches',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  // Skip: resume scanning, nothing added.
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Skip this card',
                ),
              ],
            ),
          ),

          // ── grid ────────────────────────────────────────────────────────
          Expanded(
            child: GridView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                // Card art is 0.716; the rest is the two text lines.
                childAspectRatio: 0.56,
              ),
              itemCount: _shown.length,
              itemBuilder: (context, i) => _VersionTile(
                card: _shown[i],
                onTap: () => Navigator.of(context).pop(_shown[i]),
              ),
            ),
          ),

          // ── escapes ─────────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: _loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.grid_view_rounded, size: 18),
                      label: Text(_widened ? 'All printings' : 'More versions'),
                      onPressed: _widened || _loading ? null : _moreVersions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Art for the gross match, text for the precise one.
///
/// A thumbnail cannot do this job: the user is holding a physical card and
/// checking whether the thing on screen is the same one, which needs the whole
/// card at a size where frame, art and border read clearly.
///
/// The `SET · COLLECTOR` line is not decoration. The hardest case is two
/// printings with identical art separated only by a set symbol a few pixels
/// across — nobody can verify that visually — but the collector number is printed
/// on the card in the user's hand.
class _VersionTile extends StatelessWidget {
  final Card card;
  final VoidCallback onTap;

  const _VersionTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.716,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: url == null
                  ? _placeholder(theme, Icons.image_not_supported_outlined)
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, progress) => progress == null
                          ? child
                          : _placeholder(theme, null, progress: progress),
                      errorBuilder: (c, _, _) =>
                          _placeholder(theme, Icons.wifi_off_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${card.setCode.toUpperCase()} · ${card.collectorNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(ThemeData theme, IconData? icon,
          {ImageChunkEvent? progress}) =>
      ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: icon != null
              ? Icon(icon, size: 22, color: theme.disabledColor)
              : SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress?.expectedTotalBytes == null
                        ? null
                        : progress!.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
        ),
      );
}
