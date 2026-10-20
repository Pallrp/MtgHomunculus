import 'package:flutter/material.dart';

import '../theme/picker_tokens.dart';

/// The listing sheet's building blocks, shared by the app's own lists and the
/// Deckbox lists (M3) — so the two sheets look and behave the same without
/// either copying the other.

/// A count with − and + either side. At 1 the − becomes a delete.
class QtyStepper extends StatelessWidget {
  final int quantity;
  final void Function(int) onChanged;

  const QtyStepper({super.key, required this.quantity, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetIconBtn(
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
        SheetIconBtn(
          icon: Icons.add_rounded,
          tooltip: 'One more',
          onTap: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

/// The bordered square the artifact uses for every icon action.
class SheetIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool danger;
  final bool small;
  final VoidCallback onTap;

  const SheetIconBtn({
    super.key,
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

/// The circular toggle straddling the sheet's top edge.
class SheetChevron extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;

  const SheetChevron({super.key, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Material(
      color: t.surface,
      shape: CircleBorder(side: BorderSide(color: t.line)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: PickerTokens.chevron,
          height: PickerTokens.chevron,
          child: Icon(
            open
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_up_rounded,
            size: 20,
            color: t.text,
          ),
        ),
      ),
    );
  }
}

/// An outlined accent action — "Manual add", "Cut to", "Copy to".
///
/// With a [color], **filled** in it instead — the Deckbox list's *Push*. A
/// null [onTap] greys it out.
class SheetTextBtn extends StatelessWidget {
  final String label;
  final bool wide;
  final VoidCallback? onTap;
  final Color? color;
  final IconData? icon;

  const SheetTextBtn({
    super.key,
    required this.label,
    required this.onTap,
    this.wide = false,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final enabled = onTap != null;
    final filled = color;
    final Color fg = filled != null ? Colors.white : t.accent;
    final Color border = filled ?? t.accent;
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: wide ? Alignment.center : null,
          decoration: BoxDecoration(
            color: filled,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(PickerTokens.radiusSmall),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return wide ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The in-list search field the sort slot holds.
class SheetSearchField extends StatelessWidget {
  final String query;
  final void Function(String) onChanged;

  const SheetSearchField({super.key, required this.query, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: TextEditingController(text: query)
          ..selection = TextSelection.collapsed(offset: query.length),
        onChanged: onChanged,
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
}

/// A card row's middle: the thumbnail, then name, a set line and the chips.
/// Whatever sits left of it (a selection mark) or right of it (a count, a
/// stepper, a pill) is the caller's.
class CardRowBody extends StatelessWidget {
  final Widget thumb;
  final String name;
  final Widget setLine;
  final Widget chips;

  const CardRowBody({
    super.key,
    required this.thumb,
    required this.name,
    required this.setLine,
    required this.chips,
  });

  /// The set line every printing row uses: `SET · number · set name`.
  static Widget printingLine(
    BuildContext context, {
    required String setCode,
    required String collector,
    required String setName,
  }) =>
      Text(
        setName.isEmpty
            ? '${setCode.toUpperCase()} · $collector'
            : '${setCode.toUpperCase()} · $collector · $setName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PickerTokens.mono(context, size: 10),
      );

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Row(
      children: [
        SizedBox(
          width: PickerTokens.thumbWidth,
          height: PickerTokens.thumbHeight,
          child: thumb,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: t.text,
                ),
              ),
              setLine,
              const SizedBox(height: 3),
              chips,
            ],
          ),
        ),
      ],
    );
  }
}
