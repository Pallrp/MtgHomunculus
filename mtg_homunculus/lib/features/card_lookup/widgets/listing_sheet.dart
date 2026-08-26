import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import 'attribute_chips.dart';
import 'scanner_overlay.dart' show CaptureButton;

/// The listing sheet — one component at two heights.
///
/// ```
/// Peek   one row: the card just scanned          camera running
/// Full   management bar + every row              camera stopped
/// ```
///
/// **No mid-height state.** Two is enough, and a third would need its own answer
/// to "is the camera on?" that nobody could predict.
///
/// There is no separate toast and no closed state: before the first scan the
/// sheet is the chevron and an empty line.
class ListingSheet extends StatelessWidget {
  final String listName;
  final List<Entry> entries;

  final ScrollController scrollController;
  final DraggableScrollableController sheetController;
  final double minSheetSize;

  /// Whether the camera is running — which is the same thing as the sheet being
  /// collapsed, so it also decides peek versus full.
  final bool cameraActive;
  final bool detecting;

  /// The entry the peek row pulses for: a frame was discarded because this card
  /// is the one already in the last-added slot.
  final int? pulseEntryId;

  final Future<void> Function(int entryId) onDeleteCard;
  final Future<void> Function(int entryId, int quantity) onSetQuantity;
  final void Function(Entry entry) onCardTap;
  final VoidCallback onCapture;
  final VoidCallback onExportCsv;

  final EntrySort sort;
  final void Function(EntrySort) onSortChanged;

  final Set<int> selected;
  final void Function(Set<int>) onSelectionChanged;
  final Future<void> Function(Set<int> ids, bool move) onMoveTo;
  final Future<void> Function(Set<int> ids) onDeleteSelected;

  const ListingSheet({
    super.key,
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
    required this.sort,
    required this.onSortChanged,
    required this.selected,
    required this.onSelectionChanged,
    required this.onMoveTo,
    required this.onDeleteSelected,
    this.pulseEntryId,
  });

  /// Half the [CaptureButton] height. The button straddles this offset so its
  /// top half floats in the camera feed and its bottom half rests on the sheet.
  static const double _buttonHalf = 34.0;

  bool get _full => !cameraActive;
  bool get _selecting => selected.isNotEmpty;

  int get _copies => entries.fold(0, (n, e) => n + e.quantity);

  List<Entry> get _sorted => sort.apply(entries);

  // ---------------------------------------------------------------------------

  /// The camera button never changes meaning.
  ///
  /// Collapsed it captures; expanded it collapses back to the camera. It is the
  /// same idea both ways — *get me to the camera* — which is why multi-select
  /// adds a second row rather than transforming this one.
  IconData get _cameraIcon =>
      cameraActive ? Icons.camera_alt_rounded : Icons.keyboard_arrow_down_rounded;

  VoidCallback _cameraTap() => cameraActive
      ? onCapture
      : () => sheetController.animateTo(
            minSheetSize,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned(
          top: _buttonHalf,
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(child: _bar(context)),
                if (_full && _selecting)
                  SliverToBoxAdapter(child: _selectionBar(context)),
                if (entries.isEmpty)
                  SliverToBoxAdapter(child: _empty(context))
                else
                  _rows(context),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Center(
            child: CaptureButton(
              detecting: detecting && cameraActive,
              onTap: _cameraTap(),
              icon: _cameraIcon,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------

  /// Peek shows the list's identity; full adds the management controls.
  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final unique = entries.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, _buttonHalf + 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(listName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                Text(
                  '$_copies ${_copies == 1 ? "card" : "cards"}'
                  '${unique == _copies ? "" : " · $unique unique"}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_full) ...[
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort',
              onPressed: () => _pickSort(context),
            ),
            IconButton(
              icon: Icon(_selecting
                  ? Icons.checklist_rtl_rounded
                  : Icons.checklist_rounded),
              tooltip: 'Select',
              // Opens with everything preselected — the common case is "all of
              // these go somewhere", and deselecting a few is less work than
              // ticking eighteen.
              onPressed: () => onSelectionChanged(
                _selecting ? {} : {for (final e in entries) e.id},
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'List settings',
              onPressed: () => _listSettings(context),
            ),
          ],
        ],
      ),
    );
  }

  /// A **second** row, never a transformation of the first.
  ///
  /// The camera button and the list identity keep meaning what they meant, so
  /// nothing the user learned a moment ago stops being true while selecting.
  Widget _selectionBar(BuildContext context) {
    final theme = Theme.of(context);
    final all = selected.length == entries.length;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(all
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded),
            tooltip: all ? 'Deselect all' : 'Select all',
            onPressed: () => onSelectionChanged(
              all ? {} : {for (final e in entries) e.id},
            ),
          ),
          Text('${selected.length} selected',
              style: theme.textTheme.labelLarge),
          const Spacer(),
          // The trailing preposition is deliberate: both open a destination
          // picker rather than acting immediately.
          TextButton(
            onPressed: () => onMoveTo(selected, true),
            child: const Text('Cut to'),
          ),
          TextButton(
            onPressed: () => onMoveTo(selected, false),
            child: const Text('Copy to'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Remove from list',
            onPressed: () => onDeleteSelected(selected),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Text(
          'No cards yet — scan to add.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _rows(BuildContext context) {
    final rows = _sorted;
    // Peek shows one row: the card just scanned. Newest first, always.
    final visible = _full ? rows : rows.take(1).toList();

    return SliverList.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final entry = visible[i];
        return _EntryRow(
          entry: entry,
          // The stepper is the peek row's control only. In the list the count is
          // static text, because the list can be re-sorted — at which point
          // "the newest one" stops meaning anything and an inconsistency
          // between the top row and the rest would have no justification.
          showStepper: !_full,
          pulsing: !_full && entry.id == pulseEntryId,
          selected: selected.contains(entry.id),
          selecting: _full && _selecting,
          onTap: () {
            if (_full && _selecting) {
              final next = {...selected};
              next.contains(entry.id)
                  ? next.remove(entry.id)
                  : next.add(entry.id);
              onSelectionChanged(next);
            } else {
              onCardTap(entry);
            }
          },
          onDelete: () => onDeleteCard(entry.id),
          onSetQty: (q) => onSetQuantity(entry.id, q),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _pickSort(BuildContext context) async {
    final picked = await showModalBottomSheet<EntrySort>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in EntrySort.values)
              ListTile(
                title: Text(s.label),
                trailing: s == sort
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onSortChanged(picked);
  }

  Future<void> _listSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('Export as CSV'),
              enabled: entries.isNotEmpty,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onExportCsv();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Sort orders for a list.
///
/// Deliberately no *filter*: search already covers what filtering would have
/// done, and a filter UI is a lot of surface for a list you just built.
enum EntrySort {
  scanned('Scanned'),
  name('Name (A–Z)'),
  released('Release date'),
  set('Set');

  const EntrySort(this.label);
  final String label;

  List<Entry> apply(List<Entry> entries) {
    final out = [...entries];
    switch (this) {
      // `added_at` descending is the scan order the list arrives in.
      case EntrySort.scanned:
        out.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case EntrySort.name:
        out.sort((a, b) => a.snapName.toLowerCase().compareTo(
              b.snapName.toLowerCase(),
            ));
      // No release date on the snapshot, so the set code stands in — it groups
      // printings the same way without needing the card cache present.
      case EntrySort.released:
      case EntrySort.set:
        out.sort((a, b) {
          final s = a.snapSetCode.compareTo(b.snapSetCode);
          return s != 0 ? s : a.snapCollector.compareTo(b.snapCollector);
        });
    }
    return out;
  }
}

// ---------------------------------------------------------------------------

/// Peek and list rows are identical except on the right.
class _EntryRow extends StatefulWidget {
  final Entry entry;
  final bool showStepper;
  final bool pulsing;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(int quantity) onSetQty;

  const _EntryRow({
    required this.entry,
    required this.showStepper,
    required this.pulsing,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onDelete,
    required this.onSetQty,
  });

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(_EntryRow old) {
    super.didUpdateWidget(old);
    // A discarded frame is otherwise completely silent, which reads the same as
    // the scanner having stopped working. The row already showing that card is
    // the right thing to point at, so it says "yes, still that one" rather than
    // "something went wrong".
    if (widget.pulsing && !old.pulsing) {
      _pulse.forward(from: 0).then((_) => _pulse.reverse());
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.entry;
    final url = ScryfallCard.imageUrlFor(e.cardId, null, size: 'small');

    final row = InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (widget.selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  widget.selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 20,
                  color: widget.selected
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 36,
                height: 50,
                child: url == null
                    ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (c, _, _) => ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.image_not_supported_outlined,
                              size: 14, color: theme.disabledColor),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.snapName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                  Text(
                    '${e.snapSetCode.toUpperCase()} · ${e.snapCollector}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 3),
                  AttributeChips(
                    finish: e.finish,
                    language: e.language,
                    condition: e.condition,
                    defaults: ScanDefaults.current,
                    deviationsOnly: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.showStepper)
              _Stepper(
                quantity: e.quantity,
                onChanged: widget.onSetQty,
              )
            else
              Text('${e.quantity}×',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey(e.id),
      direction: widget.selecting
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.error,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => ColoredBox(
          color: theme.colorScheme.primary.withValues(alpha: 0.18 * _pulse.value),
          child: child,
        ),
        child: row,
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int quantity;
  final void Function(int) onChanged;

  const _Stepper({required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(quantity <= 1
                ? Icons.delete_outline_rounded
                : Icons.remove_rounded),
            onPressed: () => onChanged(quantity - 1),
            tooltip: quantity <= 1 ? 'Remove' : 'One fewer',
          ),
          Text('$quantity', style: Theme.of(context).textTheme.titleSmall),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => onChanged(quantity + 1),
            tooltip: 'One more',
          ),
        ],
      );
}
