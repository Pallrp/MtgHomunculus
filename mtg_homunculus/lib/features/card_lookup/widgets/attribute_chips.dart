import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../theme/picker_tokens.dart';

/// Finish, language and condition for one entry.
///
/// **All three, always.** Row height is thumbnail-driven, so the chips ride
/// along free — hiding the ones matching your defaults would save nothing and
/// cost the ability to read a row at a glance. What changes is not *whether* a
/// chip is there but how loudly it speaks.
///
/// **Two colouring rules, because only one of the three has a natural
/// ordering.**
///
/// Finish and language are deviation-coded: neither has a "worse" direction —
/// Japanese is not worse than English, it is just not what you usually hold — so
/// matches recede and differences take the accent.
///
/// Condition is severity-coded on a fixed ramp: it *does* have a direction, and
/// it is about value rather than habit. If a user set their default to LP,
/// deviation-coding would paint NM as the notable one, which is backwards.
///
/// The split also keeps the logic honest: two attributes consult the defaults,
/// the third is a fixed table. One lookup, no per-list state.
class AttributeChips extends StatelessWidget {
  final int finish;
  final String language;
  final int condition;

  /// Defaults to compare against. Injected rather than read statically so a test
  /// can state the norm it is testing.
  final ScanDefaults defaults;

  const AttributeChips({
    super.key,
    required this.finish,
    required this.language,
    required this.condition,
    required this.defaults,
  });

  AttributeChips.of(Entry entry, {super.key, ScanDefaults? defaults})
      : finish = entry.finish,
        language = entry.language,
        condition = entry.condition,
        defaults = defaults ?? ScanDefaults.current;

  /// The artifact labels nonfoil `NORMAL`, which is also what a shop would.
  static String finishLabel(int f) => switch (f) {
        Finish.foil => 'FOIL',
        Finish.etched => 'ETCHED',
        _ => 'NORMAL',
      };

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final cond = t.condition(condition);

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        _Chip(
          label: finishLabel(finish),
          // Foil is the one gradient in the list, and it is shown whether or not
          // it is your default: a foil is a foil.
          gradient: finish == Finish.foil ? PickerTokens.foil : null,
          fg: finish == Finish.foil
              ? PickerTokens.onFoil
              : finish == defaults.finish
                  ? t.textFaint
                  : t.accent,
          bg: finish == Finish.foil
              ? null
              : finish == defaults.finish
                  ? t.surface2
                  : t.accentSoft,
          border: finish == Finish.foil
              ? Colors.black.withValues(alpha: 0.2)
              : finish == defaults.finish
                  ? t.line
                  : t.accent,
        ),
        _Chip(
          label: language.toUpperCase(),
          fg: language == defaults.language ? t.textFaint : t.accent,
          bg: language == defaults.language ? t.surface2 : t.accentSoft,
          border: language == defaults.language ? t.line : t.accent,
        ),
        _Chip(
          label: Condition.label(condition),
          // Near Mint is passive and takes the ordinary muted chip. Note this
          // never consults the defaults — see the class doc.
          fg: cond?.$1 ?? t.textFaint,
          bg: cond?.$2 ?? t.surface2,
          border: cond?.$1 ?? t.line,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color? bg;
  final Color border;
  final Gradient? gradient;

  const _Chip({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: PickerTokens.mono(context, size: 8.5, color: fg),
        ),
      );
}
