import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../theme/picker_tokens.dart';
import 'attribute_chips.dart';
import 'scanner_overlay.dart' show CaptureButton;

/// What the slot under the management bar is currently showing.
///
/// **One slot, three occupants.** Only one is ever relevant, and each expands
/// over the others rather than adding a row of its own — so the bar above never
/// moves and the camera button never changes meaning.
enum SlotMode { manualAdd, sort, select }

/// The listing sheet — one component at two heights.
///
/// ```
/// Peek   the chevron and one row: the card just scanned    camera running
/// Full   management bar, the slot, and every row           camera stopped
/// ```
///
/// **Peek carries no management bar.** It is ~93 dp — the chevron's lower half
/// plus a single row — and the viewfinder keeps the rest. A list name and a
/// count there would cost a third of the peek to say what the user already knows.
///
/// **No mid-height stop and no closed state.** Before the first scan the sheet
/// is the chevron and an empty line.
class ListingSheet extends StatelessWidget {
  final String listName;
  final List<Entry> entries;

  final ScrollController scrollController;
  final DraggableScrollableController sheetController;
  final double minSheetSize;

  /// Whether the camera is running — the same thing as the sheet being
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
  final VoidCallback onManualAdd;

  final EntrySort sort;
  final void Function(EntrySort) onSortChanged;

  /// Searches **this list**, never Scryfall. The one inside Manual Add does
  /// that, and keeping them apart is cleaner than one field guessing.
  final String query;
  final void Function(String) onQueryChanged;

  final SlotMode slotMode;
  final void Function(SlotMode) onSlotModeChanged;

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
    required this.onManualAdd,
    required this.sort,
    required this.onSortChanged,
    required this.query,
    required this.onQueryChanged,
    required this.slotMode,
    required this.onSlotModeChanged,
    required this.selected,
    required this.onSelectionChanged,
    required this.onMoveTo,
    required this.onDeleteSelected,
    this.pulseEntryId,
  });

  /// The chevron straddles the sheet edge, so half of it sits on the surface.
  static const double _chevHalf = PickerTokens.chevron / 2;

  /// Chevron half plus one row. The artifact's measured peek total.
  static const double peekContent = _chevHalf + PickerTokens.rowHeight;

  bool get _full => !cameraActive;

  int get _copies => entries.fold(0, (n, e) => n + e.quantity);

  /// Sorted, then filtered by the in-list search.
  List<Entry> get _visible {
    final q = query.trim().toLowerCase();
    final rows = sort.apply(entries);
    if (q.isEmpty) return rows;
    return [
      for (final e in rows)
        if (e.snapName.toLowerCase().contains(q) ||
            e.snapSetCode.toLowerCase().contains(q))
          e,
    ];
  }

  // ---------------------------------------------------------------------------

  /// The camera button never changes meaning.
  ///
  /// Collapsed it captures; expanded it collapses back to the camera. Same idea
  /// either way — *get me to the camera* — which is why the slot below carries
  /// the modes instead of this.
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
    final t = PickerTokens.of(context);
    // The system navigation bar sits under the sheet's bottom edge, so without
    // this the peek row is drawn behind it. Taken from the device: gesture
    // navigation and a three-button bar are different heights.
    final navBar = MediaQuery.viewPaddingOf(context).bottom;
    final rows = _visible;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: _chevHalf,
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: t.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(
              controller: scrollController,
              // Without this the sheet cannot be dragged open when its content
              // is shorter than the viewport: a scrollable with no extent
              // reports no drag, and DraggableScrollableSheet has nothing to
              // follow. That is the peek state, i.e. always.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (_full) ...[
                  SliverToBoxAdapter(child: _mgmtBar(context)),
                  SliverToBoxAdapter(child: _slot(context)),
                ],
                if (rows.isEmpty)
                  SliverToBoxAdapter(child: _empty(context))
                else
                  _rows(context, rows),
                SliverToBoxAdapter(child: SizedBox(height: navBar + 8)),
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

  /// Full height only. 54 dp, per the artifact.
  Widget _mgmtBar(BuildContext context) {
    final t = PickerTokens.of(context);
    final unique = entries.length;

    return Container(
      padding: EdgeInsets.fromLTRB(10, _chevHalf + 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                Text(
                  '$_copies ${_copies == 1 ? "copy" : "copies"} · '
                  '$unique unique',
                  style: PickerTokens.mono(context, size: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.swap_vert_rounded,
            tooltip: 'Sort and search this list',
            active: slotMode == SlotMode.sort,
            onTap: () => onSlotModeChanged(
              slotMode == SlotMode.sort ? SlotMode.manualAdd : SlotMode.sort,
            ),
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.checklist_rounded,
            tooltip: 'Select',
            active: slotMode == SlotMode.select,
            onTap: () {
              if (slotMode == SlotMode.select) {
                onSelectionChanged(const {});
                onSlotModeChanged(SlotMode.manualAdd);
              } else {
                // Opens with everything selected — the common case is "all of
                // these go somewhere", and deselecting a few is less work than
                // ticking eighteen.
                onSelectionChanged({for (final e in entries) e.id});
                onSlotModeChanged(SlotMode.select);
              }
            },
          ),
          const SizedBox(width: 6),
          _IconBtn(
            icon: Icons.settings_outlined,
            tooltip: 'List settings',
            onTap: () => _listSettings(context),
          ),
        ],
      ),
    );
  }

  /// The single row under the management bar.
  Widget _slot(BuildContext context) {
    final t = PickerTokens.of(context);
    final selecting = slotMode == SlotMode.select;

    return Container(
      decoration: BoxDecoration(
        color: selecting ? t.accentSoft : null,
        border: Border(
          bottom: BorderSide(color: selecting ? t.accent : t.line),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: switch (slotMode) {
        SlotMode.manualAdd => _TextBtn(
            label: '+  Manual add',
            wide: true,
            onTap: onManualAdd,
          ),
        SlotMode.sort => Row(
            children: [
              Expanded(child: _listSearchField(context)),
              const SizedBox(width: 8),
              _IconBtn(
                icon: Icons.swap_vert_rounded,
                tooltip: sort.label,
                onTap: () => _pickSort(context),
              ),
            ],
          ),
        SlotMode.select => Row(
            children: [
              _IconBtn(
                icon: selected.length == entries.length
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                tooltip: selected.length == entries.length
                    ? 'Deselect all'
                    : 'Select all',
                active: selected.length == entries.length,
                small: true,
                onTap: () => onSelectionChanged(
                  selected.length == entries.length
                      ? const {}
                      : {for (final e in entries) e.id},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${selected.length} selected',
                  style: PickerTokens.mono(
                    context,
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: t.accent,
                  ),
                ),
              ),
              // The trailing preposition is deliberate: both open a destination
              // picker rather than acting immediately.
              _TextBtn(label: 'Cut to', onTap: () => onMoveTo(selected, true)),
              const SizedBox(width: 5),
              _TextBtn(
                  label: 'Copy to', onTap: () => onMoveTo(selected, false)),
              const SizedBox(width: 5),
              _IconBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Remove from list',
                danger: true,
                small: true,
                onTap: () => onDeleteSelected(selected),
              ),
            ],
          ),
      },
    );
  }

  Widget _listSearchField(BuildContext context) {
    final t = PickerTokens.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: TextEditingController(text: query)
          ..selection = TextSelection.collapsed(offset: query.length),
        onChanged: onQueryChanged,
        style: PickerTokens.mono(context, size: 12, color: t.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.surface2,
          hintText: 'Find in this list…',
          hintStyle: PickerTokens.mono(context, size: 12, color: t.textFaint),
          prefixIcon: Icon(Icons.search_rounded, size: 16, color: t.textFaint),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: t.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(7),
            borderSide: BorderSide(color: t.accent),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(14, _full ? 16 : _chevHalf + 16, 14, 20),
        child: Center(
          child: Text(
            query.trim().isEmpty
                ? 'No cards yet — scan to add.'
                : 'Nothing here matches.',
            style: PickerTokens.mono(context, size: 11, color: PickerTokens.of(context).textFaint),
          ),
        ),
      );

  Widget _rows(BuildContext context, List<Entry> rows) {
    // Peek shows one row: the card just scanned.
    final visible = _full ? rows : rows.take(1).toList();

    return SliverList.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: PickerTokens.of(context).line),
      itemBuilder: (context, i) {
        final entry = visible[i];
        return _EntryRow(
          entry: entry,
          // The stepper is the peek row's control only. In the list every row
          // shows a count — including the topmost, since the list can be
          // re-sorted and "newest" stops meaning anything.
          peek: !_full,
          pulsing: !_full && entry.id == pulseEntryId,
          selected: selected.contains(entry.id),
          selecting: _full && slotMode == SlotMode.select,
          onTap: () {
            if (_full && slotMode == SlotMode.select) {
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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in EntrySort.values)
              ListTile(
                title: Text(s.label),
                trailing: s == sort
                    ? Icon(Icons.check_rounded,
                        color: PickerTokens.of(context).accent)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(s),
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
/// Deliberately no *filter*: the slot's search covers what filtering would have
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
      // `added_at` descending restores scan order, newest first.
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
  final bool peek;
  final bool pulsing;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(int quantity) onSetQty;

  const _EntryRow({
    required this.entry,
    required this.peek,
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
    final t = PickerTokens.of(context);
    final e = widget.entry;
    final url = ScryfallCard.imageUrlFor(e.cardId, null, size: 'small');

    final meta = e.snapSetName.isEmpty
        ? '${e.snapSetCode.toUpperCase()} · ${e.snapCollector}'
        : '${e.snapSetCode.toUpperCase()} · ${e.snapCollector} · '
            '${e.snapSetName}';

    final row = InkWell(
      onTap: widget.onTap,
      child: Container(
        // Thumbnail-driven, so the chips ride along free.
        constraints: BoxConstraints(
          minHeight: widget.peek
              ? PickerTokens.rowHeight + ListingSheet._chevHalf
              : PickerTokens.rowHeight,
        ),
        padding: EdgeInsets.fromLTRB(
          10,
          widget.peek ? ListingSheet._chevHalf + 8 : 8,
          10,
          8,
        ),
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
                  color: widget.selected ? t.accent : t.textFaint,
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: PickerTokens.thumbWidth,
                height: PickerTokens.thumbHeight,
                child: url == null
                    ? ColoredBox(color: t.surface2)
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (c, _, _) => ColoredBox(
                          color: t.surface2,
                          child: Icon(Icons.image_not_supported_outlined,
                              size: 14, color: t.textFaint),
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
                  Text(
                    e.snapName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: t.text,
                    ),
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PickerTokens.mono(context, size: 10),
                  ),
                  const SizedBox(height: 3),
                  AttributeChips(
                    finish: e.finish,
                    language: e.language,
                    condition: e.condition,
                    defaults: ScanDefaults.current,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (widget.peek)
              _Stepper(quantity: e.quantity, onChanged: widget.onSetQty)
            else
              Text(
                '${e.quantity}×',
                style: PickerTokens.mono(
                  context,
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: t.textDim,
                ),
              ),
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
        color: t.vermilion,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => ColoredBox(
          color: t.accent.withValues(alpha: 0.22 * _pulse.value),
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
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon:
              quantity <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
          tooltip: quantity <= 1 ? 'Remove' : 'One fewer',
          danger: quantity <= 1,
          onTap: () => onChanged(quantity - 1),
        ),
        SizedBox(
          width: 26,
          child: Center(
            child: Text(
              '$quantity',
              style: PickerTokens.mono(
                context,
                size: 13,
                weight: FontWeight.w500,
                color: t.text,
              ),
            ),
          ),
        ),
        _IconBtn(
          icon: Icons.add_rounded,
          tooltip: 'One more',
          onTap: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

/// The bordered square the artifact uses for every icon action.
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool danger;
  final bool small;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final (Color fg, Color bg, Color border) = danger
        ? (t.vermilion, Colors.transparent, t.vermilion)
        : active
            ? (t.ground, t.accent, t.accent)
            : (t.text, t.surface2, t.line);
    final size = small ? 32.0 : 38.0;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: small ? 15 : 18, color: fg),
        ),
      ),
    );
  }
}

/// An outlined accent action — "Manual add", "Cut to", "Copy to".
class _TextBtn extends StatelessWidget {
  final String label;
  final bool wide;
  final VoidCallback onTap;

  const _TextBtn({required this.label, required this.onTap, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        alignment: wide ? Alignment.center : null,
        decoration: BoxDecoration(
          border: Border.all(color: t.accent),
          borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.accent,
          ),
        ),
      ),
    );
    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }
}
