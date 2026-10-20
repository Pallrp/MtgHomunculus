import 'package:flutter/material.dart';

import '../theme/picker_tokens.dart';

/// *Any printing* — a Deckbox Wishlist's one setting, in two places: Manual
/// Add and the scan peek. **On** adds the card, not a printing; **off** adds
/// the exact printing. Kept per Wishlist; flipping either place flips both.
class AnyPrintingChip extends StatelessWidget {
  const AnyPrintingChip({
    super.key,
    required this.on,
    required this.onChanged,
    this.enabled = true,
    this.height = 40,
  });

  final bool on;
  final void Function(bool) onChanged;

  /// Greyed while a set code is in the search — a set code picks a printing.
  final bool enabled;

  /// 44 in the scan peek, for a one-handed scan.
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final lit = on && enabled;
    return Semantics(
      button: true,
      toggled: lit,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? () => onChanged(!on) : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: lit ? t.sync : t.surface,
              border: Border.all(color: lit ? t.sync : t.line, width: 1.5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                lit ? Icons.check_rounded : Icons.layers_outlined,
                size: 16,
                color: lit ? Colors.white : t.textDim,
              ),
              const SizedBox(width: 7),
              Text(
                'Any printing',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: lit ? Colors.white : t.textDim,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
