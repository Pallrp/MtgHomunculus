import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sheet_model.dart';
import '../models/scan_defaults.dart';
import '../models/scryfall_card.dart';
import '../theme/picker_tokens.dart';
import 'attribute_chips.dart';
import 'card_thumb.dart';
import 'sheet_parts.dart';

/// The rows and headers of a Deckbox list's sheet (M3), on the listing sheet's
/// own parts.

// ---------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------

/// The canvas's tints: the **scan target** is blue, header and rows; a staged
/// section's header is a shade darker than the page; *On Deckbox* is plain.
extension DeckboxTints on PickerTokens {
  Color get targetHeader => Color.lerp(syncSoft, sync, 0.12)!;
  Color get targetRow => syncSoft;
  Color get stagedHeader => surface2;

  /// **The list hues** (tradelist.md): each Deckbox list's colour, behind
  /// the halves of an `X/Y` pill and — later — on the lists where one is
  /// chosen. Low, so they tint rather than shout. The Inventory's sits
  /// between the folder's Deckbox tint and the Push button's blue.
  Color get inventoryHue => Color.lerp(syncSoft, sync, 0.15)!;
  Color get inventoryInk => syncInk;
  Color get tradelistHue => Color.lerp(accentSoft, accent, 0.15)!;
  Color get tradelistInk => Color.lerp(accent, text, 0.15)!;
  Color get wishlistHue => Color.lerp(warningBg, warning, 0.15)!;
  Color get wishlistInk => Color.lerp(warning, text, 0.15)!;

  /// A list row's background where a Deckbox list is chosen — the lists
  /// folder, the destination picker: its hue, laid softly over the surface,
  /// so the three lists read apart at a glance (tradelist.md, step 6).
  Color listTint(String? kind) {
    final hue = hueOf(kind);
    if (hue == null) return surface;
    // Blue and green a good deal stronger — at 45 % they read washed out in
    // the folder (2026-10-20); yellow is already loud.
    final strength = kind == 'wishlist' ? 0.45 : 0.85;
    return Color.alphaBlend(hue.bg.withValues(alpha: strength), surface);
  }

  /// A Deckbox list's hue and the ink that reads on it; null for any other.
  ({Color bg, Color ink})? hueOf(String? kind) => switch (kind) {
        'inventory' => (bg: inventoryHue, ink: inventoryInk),
        'tradelist' => (bg: tradelistHue, ink: tradelistInk),
        'wishlist' => (bg: wishlistHue, ink: wishlistInk),
        _ => null,
      };
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

/// A foldable section header. [onTarget] non-null gives it the scan-target
/// radio; null leaves the radio's space empty, so the three labels line up.
class DeckboxSectionHeader extends StatelessWidget {
  const DeckboxSectionHeader({
    super.key,
    required this.label,
    required this.count,
    required this.folded,
    required this.onFold,
    this.isTarget = false,
    this.staged = false,
    this.onTarget,
    this.tag,
    this.check,
  });

  final String label;
  final int count;
  final bool folded;
  final VoidCallback onFold;
  final bool isTarget;
  final bool staged;
  final VoidCallback? onTarget;

  /// A warning beside the count — *1 flagged*.
  final String? tag;

  /// Selecting: the radio's place becomes **select all in this section** —
  /// `state` true, false, or null for some.
  final ({bool? state, VoidCallback onTap})? check;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final (Color bg, Color fg) = isTarget
        ? (t.targetHeader, t.syncInk)
        : staged
            ? (t.stagedHeader, t.text)
            : (t.surface, t.textDim);

    return InkWell(
      onTap: onFold,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.only(left: 6, right: 4),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(children: [
          if (check case final c?)
            SelectBox(state: c.state, label: 'Select all in $label', onTap: c.onTap)
          else if (onTarget != null)
            _Radio(on: isTarget, label: 'Scan into $label', onTap: onTarget!)
          else
            const SizedBox(width: 44, height: 44),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: PickerTokens.mono(context, size: 11.5, weight: FontWeight.w500, color: fg)
                  .copyWith(letterSpacing: 1.1),
            ),
          ),
          if (tag != null)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.warningBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tag!, style: PickerTokens.mono(context, size: 10.5, color: t.warning)),
            ),
          Text('$count', style: PickerTokens.mono(context, size: 12.5, color: fg)),
          SizedBox(
            width: 40,
            height: 44,
            child: Icon(
              folded ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
              size: 20,
              color: fg,
            ),
          ),
        ]),
      ),
    );
  }
}

/// A 44 dp checkbox — a row's, or a section's *select all* (null: some).
class SelectBox extends StatelessWidget {
  const SelectBox({super.key, required this.state, required this.label, required this.onTap});

  final bool? state;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Semantics(
      label: label,
      checked: state ?? false,
      mixed: state == null,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            switch (state) {
              true => Icons.check_box_rounded,
              false => Icons.check_box_outline_blank_rounded,
              null => Icons.indeterminate_check_box_rounded,
            },
            size: 22,
            color: state == false ? t.textDim : t.accent,
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on, required this.label, required this.onTap});

  final bool on;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Semantics(
      label: label,
      checked: on,
      inMutuallyExclusiveGroup: true,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: on ? t.sync : t.textDim, width: 2),
              ),
              alignment: Alignment.center,
              child: on
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: t.sync),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pills
// ---------------------------------------------------------------------------

enum PillKind { newRow, more, remove, flag }

/// `x2`, `+2`, `−2 of 3` — see [DeckboxSheetModel].
class StagePill extends StatelessWidget {
  const StagePill(this.text, {super.key, required this.kind, this.small = false, this.tradeHalf, this.list});

  final String text;
  final PillKind kind;
  final bool small;

  /// The list's kind. An **addition** pill (`xN`, `+N`) sits on its list's
  /// hue — blue, green, yellow — as both halves of an `X/Y` pill do; the text
  /// alone tells a new row from an existing one (2026-10-20). Removals and
  /// flags keep their outlines.
  final String? list;

  /// An Inventory addition also going up for trade: the pill splits — the
  /// Inventory's half (blue) then the Tradelist's (green), `x1/x1`, each on
  /// its list's hue (tradelist.md, decision 4).
  final String? tradeHalf;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final style = PickerTokens.mono(context, size: small ? 11 : 12.5, weight: FontWeight.w600);
    final vertical = small ? 3.5 : 5.5;
    final trade = tradeHalf;
    if (trade != null) {
      // The slash has a cell of its own, split down the middle, so it crosses
      // the seam between the two hues.
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: t.inventoryHue,
            padding: EdgeInsets.fromLTRB(small ? 7 : 9, vertical, 1, vertical),
            child: Text(text, style: style.copyWith(color: t.inventoryInk)),
          ),
          Container(
            padding: EdgeInsets.symmetric(vertical: vertical, horizontal: 1),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.inventoryHue, t.inventoryHue, t.tradelistHue, t.tradelistHue],
                stops: const [0, 0.5, 0.5, 1],
              ),
            ),
            child: Text('/', style: style.copyWith(color: Color.lerp(t.inventoryInk, t.tradelistInk, 0.5))),
          ),
          Container(
            color: t.tradelistHue,
            padding: EdgeInsets.fromLTRB(1, vertical, small ? 7 : 9, vertical),
            child: Text(trade, style: style.copyWith(color: t.tradelistInk)),
          ),
        ]),
      );
    }
    final hue = t.hueOf(list);
    if (hue != null && (kind == PillKind.newRow || kind == PillKind.more)) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: vertical),
        decoration: BoxDecoration(color: hue.bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: style.copyWith(color: hue.ink)),
      );
    }
    final (Color bg, Color border, Color fg) = switch (kind) {
      PillKind.newRow => (t.surface, t.sync, t.syncInk),
      PillKind.more => (t.sync, t.sync, Colors.white),
      PillKind.remove => (t.surface, t.text, t.text),
      PillKind.flag => (t.surface, t.warning, t.warning),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: PickerTokens.mono(context, size: small ? 11 : 12.5, weight: FontWeight.w600, color: fg),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thumbnail and set line
// ---------------------------------------------------------------------------

/// The card's art from its reference printing — for a generic row, the
/// stand-in — with an *ANY* badge on a generic row.
class DeckboxThumb extends StatelessWidget {
  const DeckboxThumb({super.key, required this.cardRef, required this.any});

  final String? cardRef;
  final bool any;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final ref = cardRef;
    return Stack(children: [
      Positioned.fill(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CardThumb(url: ref == null ? null : ScryfallCard.imageUrlFor(ref, null, size: 'small')),
        ),
      ),
      if (any)
        Positioned(
          top: 2,
          left: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(color: t.sync, borderRadius: BorderRadius.circular(6)),
            child: Text(
              'ANY',
              style: PickerTokens.mono(context, size: 7, weight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ),
    ]);
  }
}

Widget _anyPrintingLine(BuildContext context) => Text(
      'Any printing',
      style: TextStyle(
        fontSize: 11.5,
        fontStyle: FontStyle.italic,
        color: PickerTokens.of(context).syncInk,
      ),
    );

Widget _warningLine(BuildContext context, String text) {
  final t = PickerTokens.of(context);
  return Row(children: [
    Icon(Icons.warning_amber_rounded, size: 14, color: t.warning),
    const SizedBox(width: 4),
    Expanded(
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: t.warning),
      ),
    ),
  ]);
}

// ---------------------------------------------------------------------------
// On Deckbox: a mirrored row
// ---------------------------------------------------------------------------

/// One mirrored row: the card, what Deckbox says about it, its real count, and
/// beside it whatever is staged against it.
///
/// Three kinds, told apart on sight: a **mapped** row reads like an app entry;
/// an **any printing** row says so and carries an *ANY* badge; an **unmapped**
/// row says it could not be matched, and shows Deckbox's own edition.
///
/// **Tap** opens the row's detail — its − / + and its edit on Deckbox
/// (mirror_editing.md). **Swipe** stages removal of the whole row. The row
/// itself never changes here: Deckbox's count stays until a push.
class MirrorRow extends StatelessWidget {
  const MirrorRow({
    super.key,
    required this.entry,
    required this.count,
    required this.tradelist,
    required this.added,
    required this.removed,
    required this.onTap,
    required this.onSwipe,
    this.selecting = false,
    this.selected = false,
    this.listKind,
  });

  final ExternalEntry entry;

  /// Selecting: a checkbox leads, tap toggles it, no − / + and no swipe.
  final bool selecting;
  final bool selected;

  /// Deckbox's count — on a Tradelist, the count for trade.
  final int count;
  final bool tradelist;

  /// The list's kind — the hue of the small `+N` beside the count.
  final String? listKind;
  final int added;
  final int removed;
  final VoidCallback onTap;
  final VoidCallback? onSwipe;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final e = entry;
    final unmapped = !e.anyPrinting && e.cardId == null;

    final Widget setLine;
    if (e.anyPrinting) {
      setLine = _anyPrintingLine(context);
    } else if (unmapped) {
      setLine = _warningLine(context, 'Not matched · ${e.edition} #${e.cardNumber}');
    } else {
      setLine = CardRowBody.printingLine(
        context,
        setCode: e.editionCode,
        collector: e.cardNumber,
        setName: e.edition,
      );
    }

    final extras = [
      if (e.condition == 'Proxy') 'PROXY',
      for (final f in e.rowFlags.split(',')) if (f.isNotEmpty) f.toUpperCase(),
    ];

    final row = InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: PickerTokens.rowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(children: [
          if (selecting)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: selected ? t.accent : t.textFaint,
              ),
            ),
          Expanded(
            child: CardRowBody(
              thumb: DeckboxThumb(cardRef: e.cardRef, any: e.anyPrinting),
              name: e.name,
              setLine: setLine,
              chips: Wrap(spacing: 3, runSpacing: 3, children: [
                AttributeChips(
                  finish: e.finish,
                  language: e.languageCode,
                  condition: e.conditionCode,
                  defaults: ScanDefaults.current,
                ),
                for (final x in extras)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: t.accentSoft,
                      border: Border.all(color: t.accent),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(x, style: PickerTokens.mono(context, size: 8.5, color: t.accent)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          if (removed > 0) ...[
            StagePill('−$removed', kind: PillKind.remove, small: true),
            const SizedBox(width: 4),
          ],
          if (added > 0) ...[
            StagePill('+$added', kind: PillKind.newRow, small: true, list: listKind),
            const SizedBox(width: 4),
          ],
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '$count×',
              style: PickerTokens.mono(context, size: 12.5, weight: FontWeight.w500, color: t.textDim),
            ),
            // The other list's count, small and grey under this one's — the
            // row is shared (tradelist.md). On a Tradelist the count is the one
            // for trade, and what is owned sits under it; on the Inventory the
            // reverse, when any copy is for trade.
            if (tradelist)
              Text(
                '${e.count} owned',
                style: PickerTokens.mono(context, size: 9.5, color: t.textFaint),
              )
            else if (e.tradeCount > 0)
              Text(
                '${e.tradeCount} for trade',
                style: PickerTokens.mono(context, size: 9.5, color: t.textFaint),
              ),
          ]),
        ]),
      ),
    );

    if (onSwipe == null || selecting) return row;
    return Dismissible(
      key: ValueKey('mirror-${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: t.text,
        child: const Text('Stage removal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      // The row stays — it is Deckbox's. Swiping only stages its removal.
      confirmDismiss: (_) async {
        onSwipe!();
        return false;
      },
      child: row,
    );
  }
}

// ---------------------------------------------------------------------------
// To add / To remove: a staged row
// ---------------------------------------------------------------------------

/// One staged change. **Tap** opens its stepper; at 1 the − unstages it.
/// **Swipe** unstages it. A flagged removal or a refused addition says why.
class StagedRow extends StatefulWidget {
  const StagedRow({
    super.key,
    required this.staged,
    required this.pill,
    required this.pillKind,
    required this.inTarget,
    required this.expanded,
    required this.pulsing,
    required this.onTap,
    required this.onSetQuantity,
    required this.onUnstage,
    this.maxQuantity,
    this.peek = false,
    this.selecting = false,
    this.selected = false,
    this.tradeHalf,
    this.listKind,
  });

  final StagedChange staged;

  /// See [StagePill.tradeHalf].
  final String? tradeHalf;

  /// See [StagePill.list].
  final String? listKind;

  /// Selecting: a checkbox leads, tap toggles it, no stepper and no swipe.
  final bool selecting;
  final bool selected;
  final String pill;
  final PillKind pillKind;
  final bool inTarget;
  final bool expanded;
  final bool pulsing;
  final VoidCallback onTap;
  final void Function(int quantity) onSetQuantity;
  final VoidCallback onUnstage;

  /// A removal's cap: the mirrored row's count.
  final int? maxQuantity;

  /// The scan peek's row: the stepper always shown, no swipe.
  final bool peek;

  @override
  State<StagedRow> createState() => _StagedRowState();
}

class _StagedRowState extends State<StagedRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(StagedRow old) {
    super.didUpdateWidget(old);
    // As in the app's own sheet: a frame discarded as the card just staged
    // pulses its row, so the scanner does not look stopped.
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
    final s = widget.staged;
    final note = DeckboxSheetModel.flagText(s) ?? s.lastError;
    final bg = widget.inTarget ? t.targetRow : t.surface;
    final showStepper = !widget.selecting && (widget.peek || widget.expanded);

    final Widget setLine = s.anyPrinting
        ? _anyPrintingLine(context)
        : CardRowBody.printingLine(
            context,
            setCode: s.setCode,
            collector: s.collectorNumber,
            setName: s.setName,
          );

    final row = InkWell(
      onTap: widget.onTap,
      child: Container(
        constraints: BoxConstraints(
          minHeight: widget.peek ? PickerTokens.thumbHeight : PickerTokens.rowHeight,
        ),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: widget.peek ? 0 : 8),
        decoration: BoxDecoration(
          border: widget.peek ? null : Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(children: [
          if (widget.selecting)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                widget.selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 22,
                color: widget.selected ? t.accent : t.textFaint,
              ),
            ),
          Expanded(
            child: CardRowBody(
              thumb: DeckboxThumb(cardRef: s.cardRef ?? s.cardId, any: s.anyPrinting),
              name: s.name,
              setLine: setLine,
              chips: note == null || widget.peek
                  ? AttributeChips(
                      finish: s.finish,
                      language: s.languageCode,
                      condition: s.conditionCode,
                      defaults: ScanDefaults.current,
                    )
                  : _warningLine(context, note),
            ),
          ),
          const SizedBox(width: 6),
          if (showStepper) ...[
            SheetIconBtn(
              icon: s.quantity <= 1 ? Icons.close_rounded : Icons.remove_rounded,
              tooltip: s.quantity <= 1 ? 'Unstage' : 'One fewer',
              danger: s.quantity <= 1,
              small: true,
              onTap: () => widget.onSetQuantity(s.quantity - 1),
            ),
            const SizedBox(width: 4),
          ],
          StagePill(widget.pill, kind: widget.pillKind, tradeHalf: widget.tradeHalf, list: widget.listKind),
          if (showStepper) ...[
            const SizedBox(width: 4),
            SheetIconBtn(
              icon: Icons.add_rounded,
              tooltip: 'One more',
              small: true,
              onTap: widget.maxQuantity != null && s.quantity >= widget.maxQuantity!
                  ? () {}
                  : () => widget.onSetQuantity(s.quantity + 1),
            ),
          ],
        ]),
      ),
    );

    final tinted = AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => ColoredBox(
        color: Color.alphaBlend(t.sync.withValues(alpha: 0.22 * _pulse.value), bg),
        child: child,
      ),
      child: row,
    );

    if (widget.peek || widget.selecting) return tinted;
    return Dismissible(
      key: ValueKey('staged-${s.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: t.vermilion,
        child: const Text('Unstage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      onDismissed: (_) => widget.onUnstage(),
      child: tinted,
    );
  }
}
