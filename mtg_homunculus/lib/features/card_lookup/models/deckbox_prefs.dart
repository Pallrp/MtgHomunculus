import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Deckbox integration's own settings — choices about what the app sends,
/// kept apart from [ScanDefaults] (about cards) and [DevFlags] (about tools).
class DeckboxPrefs {
  DeckboxPrefs._();

  static const _kAlsoForTrade = 'deckbox.also_for_trade';

  /// **Also put additions up for trade** (tradelist.md, decision 3): an
  /// Inventory addition staged while this is on carries the flag, and its
  /// push puts the copies on the Tradelist in the same import. **On by
  /// default**; **app-wide** — every Deckbox list reads it — and kept across
  /// restarts. Each staged addition keeps its own flag from then on.
  static final alsoForTrade = ValueNotifier<bool>(true);

  /// Call once alongside [DevFlags.load].
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    alsoForTrade.value = p.getBool(_kAlsoForTrade) ?? true;
  }

  static Future<void> setAlsoForTrade(bool value) async {
    alsoForTrade.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAlsoForTrade, value);
  }
}
