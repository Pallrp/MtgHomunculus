import 'package:shared_preferences/shared_preferences.dart';

import '../data/collection_database.dart';

/// What finish, language and condition a scanned card lands on.
///
/// **A scan can never determine any of them.** The camera sees art and text; it
/// cannot see that a card is foil, Japanese, or moderately played. So every
/// scanned entry takes these, and the cheapest fix for the common case is making
/// them settable — someone grading a box of played cards sets the condition once
/// instead of correcting every row afterwards.
///
/// **App-wide, never per-list.** A per-list copy would render the same chip
/// differently depending on which list you opened it from.
///
/// [VariantDefaults] in the database layer stays as the compile-time fallback:
/// it is what `addCard` uses when a caller supplies nothing, and it cannot read
/// preferences because default parameter values must be constant. These are what
/// the app passes in.
class ScanDefaults {
  /// Only [Finish.nonfoil] and [Finish.foil] are offered. Etched is real but far
  /// too rare to default a whole collection to.
  final int finish;

  final String language;
  final int condition;

  const ScanDefaults({
    this.finish = VariantDefaults.finish,
    this.language = VariantDefaults.language,
    this.condition = VariantDefaults.condition,
  });

  /// The finishes a user may pick as their default.
  static const offeredFinishes = [Finish.nonfoil, Finish.foil];

  ScanDefaults copyWith({int? finish, String? language, int? condition}) =>
      ScanDefaults(
        finish: finish ?? this.finish,
        language: language ?? this.language,
        condition: condition ?? this.condition,
      );

  /// The finish to record for a printing that does not come in [finish].
  ///
  /// Storing a finish the card was never printed in produces an entry that
  /// cannot be matched against anything real — so a nonfoil default lands on the
  /// first finish the printing actually has.
  int finishFor(int availableFinishes) {
    if (availableFinishes == 0) return finish;
    if (availableFinishes & finish != 0) return finish;
    for (final f in Finish.all) {
      if (availableFinishes & f != 0) return f;
    }
    return finish;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  static const _kFinish = 'scan_defaults.finish';
  static const _kLanguage = 'scan_defaults.language';
  static const _kCondition = 'scan_defaults.condition';

  static ScanDefaults _current = const ScanDefaults();
  static bool _loaded = false;

  /// The current defaults. Always valid — at worst the built-in ones.
  static ScanDefaults get current => _current;

  static Future<ScanDefaults> loadCurrent() async {
    if (_loaded) return _current;
    final p = await SharedPreferences.getInstance();
    _current = ScanDefaults(
      finish: p.getInt(_kFinish) ?? VariantDefaults.finish,
      language: p.getString(_kLanguage) ?? VariantDefaults.language,
      condition: p.getInt(_kCondition) ?? VariantDefaults.condition,
    );
    _loaded = true;
    return _current;
  }

  static Future<void> setCurrent(ScanDefaults next) async {
    _current = next;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kFinish, next.finish);
    await p.setString(_kLanguage, next.language);
    await p.setInt(_kCondition, next.condition);
  }

  /// Test seam — set without touching preferences.
  static void setForTesting(ScanDefaults next) {
    _current = next;
    _loaded = true;
  }
}
