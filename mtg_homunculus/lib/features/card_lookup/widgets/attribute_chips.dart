import 'package:flutter/material.dart';

import '../data/collection_database.dart';
import '../models/scan_defaults.dart';

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

  /// The condition ramp, warming with damage.
  ///
  /// Fixed values rather than theme colours: these mean the same thing in both
  /// themes, and a scheme colour would make `DMG` read as an error state.
  static const _ramp = {
    Condition.lightlyPlayed: Color(0xFFC8B560),
    Condition.moderatelyPlayed: Color(0xFFC89550),
    Condition.heavilyPlayed: Color(0xFFC06A40),
    Condition.damaged: Color(0xFFB04A40),
  };

  /// Static, deliberately. A shimmer on every row would be unbearable at ten
  /// rows a screen.
  static const _foil = LinearGradient(
    colors: [Color(0xFF8FD6FF), Color(0xFFC9A7FF), Color(0xFFFFC2E2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (Color fg, Color bg, Gradient? gradient) = switch (emphasis) {
      ChipEmphasis.muted => (cs.onSurfaceVariant, cs.surfaceContainerHighest, null),
      ChipEmphasis.notable => (cs.onPrimaryContainer, cs.primaryContainer, null),
      ChipEmphasis.iridescent => (const Color(0xFF221833), Colors.transparent, _foil),
      ChipEmphasis.warm => (
          const Color(0xFF201510),
          _ramp[severity] ?? cs.surfaceContainerHighest,
          null,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              height: 1.1,
            ),
      ),
    );
  }
}
