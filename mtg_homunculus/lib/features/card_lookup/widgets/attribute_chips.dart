import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';
import '../theme/picker_tokens.dart';

/// How a chip earns colour.
enum ChipEmphasis {
  /// This is what you always hold. Recede.
  muted,

  /// Not your default. Worth a glance, not an alarm.
  notable,

  /// Foil, and only foil — the one gradient in the list.
  iridescent,

  /// Condition, coloured by how bad it is.
  warm,
}

/// Finish, language and condition for one entry.
///
/// Row height is driven by the thumbnail, so these cost no extra height.
///
/// **Two colouring rules, because only one of the three attributes has a
/// direction.** Finish and language have no "worse" — Japanese is not worse than
/// English, just not what you usually hold — so what is worth showing is
/// *deviation from your norm*. Condition does have a direction, and it is about
/// value rather than habit: deviation-coding it would mean a user whose default
/// is LP sees NM painted as the notable chip, which is backwards.
///
/// The split also keeps the logic honest — two attributes consult the defaults,
/// the third is a fixed table.
class AttributeChips extends StatelessWidget {
  final int finish;
  final String language;
  final int condition;

  /// Defaults to compare against. Injected rather than read statically so a test
  /// can state the norm it is testing.
  final ScanDefaults defaults;

  /// Hides chips that match the default entirely.
  ///
  /// For dense surfaces where only deviations are worth the pixels. Condition is
  /// never hidden — it is severity-coded, so `NM` is information rather than
  /// an absence of it.
  final bool deviationsOnly;

  const AttributeChips({
    super.key,
    required this.finish,
    required this.language,
    required this.condition,
    required this.defaults,
    this.deviationsOnly = false,
  });

  AttributeChips.of(Entry entry, {super.key, ScanDefaults? defaults, this.deviationsOnly = false})
      : finish = entry.finish,
        language = entry.language,
        condition = entry.condition,
        defaults = defaults ?? ScanDefaults.current;

  @override
  Widget build(BuildContext context) {
    final finishDeviates = finish != defaults.finish;
    final langDeviates = language != defaults.language;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (finishDeviates || !deviationsOnly)
          _Chip(
            label: Finish.label(finish).toUpperCase(),
            emphasis: !finishDeviates
                ? ChipEmphasis.muted
                : finish == Finish.foil
                    ? ChipEmphasis.iridescent
                    : ChipEmphasis.notable,
          ),
        if (langDeviates || !deviationsOnly)
          _Chip(
            label: language.toUpperCase(),
            emphasis: langDeviates ? ChipEmphasis.notable : ChipEmphasis.muted,
          ),
        _Chip(
          label: Condition.label(condition),
          emphasis: condition == Condition.nearMint
              ? ChipEmphasis.muted
              : ChipEmphasis.warm,
          // Severity drives the shade within `warm`, on a fixed ramp — never on
          // the user's default. See the class doc.
          severity: condition,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String label;
  final ChipEmphasis emphasis;
  final int severity;

  const _Chip({
    required this.label,
    required this.emphasis,
    this.severity = Condition.nearMint,
  });

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);

    // The condition ramp, warming with damage.
    //
    // The artifact names one warn colour, for MP. The other three steps are
    // interpolated from it rather than invented, so the ramp stays inside the
    // palette while still giving four distinguishable states — a ramp whose
    // middle steps look identical is not a ramp.
    //
    // Only DMG reaches vermilion, and only in the text. Vermilion is
    // destructive-only in this design, and a played card is not an error.
    final ramp = <int, (Color fg, Color bg)>{
      Condition.lightlyPlayed: (
        t.textDim,
        Color.lerp(t.surface2, t.warnBg, 0.45)!,
      ),
      Condition.moderatelyPlayed: (t.warn, t.warnBg),
      Condition.heavilyPlayed: (
        t.warn,
        Color.lerp(t.warnBg, t.vermilion, 0.18)!,
      ),
      Condition.damaged: (
        t.vermilion,
        Color.lerp(t.warnBg, t.vermilion, 0.36)!,
      ),
    };

    final (Color fg, Color bg, Color border, Gradient? gradient) =
        switch (emphasis) {
      ChipEmphasis.muted => (t.textFaint, t.surface2, t.line, null),
      ChipEmphasis.notable => (t.accent, t.accentSoft, t.accent, null),
      ChipEmphasis.iridescent => (
          PickerTokens.onFoil,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.2),
          PickerTokens.foil,
        ),
      ChipEmphasis.warm => (
          ramp[severity]?.$1 ?? t.textFaint,
          ramp[severity]?.$2 ?? t.surface2,
          ramp[severity]?.$1 ?? t.line,
          null,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(PickerTokens.radiusChip),
      ),
      child: Text(
        label,
        style: PickerTokens.mono(context, size: 10, color: fg),
      ),
    );
  }
}
