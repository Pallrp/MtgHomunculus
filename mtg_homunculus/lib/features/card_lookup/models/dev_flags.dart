import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Developer switches for the scanner surface.
///
/// Kept apart from [ScanDefaults] on purpose: those are choices a *user* makes
/// about their cards, these are tools for whoever is measuring the detector.
/// Neither belongs in the other's menu.
///
/// **A setting, not a `kDebugMode` gate.** The tuning panel's whole value is
/// being reachable on a real device, in the field, in the lighting that caused
/// the problem — which is exactly where a debug-build gate would put it out of
/// reach. It defaults off and persists, so it is toggled once rather than once
/// per session.
class DevFlags {
  DevFlags._();

  static const _kTuningTools = 'dev_flags.tuning_tools';

  /// Whether the scanner renders its tuning / OCR-debug button cluster.
  ///
  /// A [ValueNotifier] rather than a plain static, because the switch lives in
  /// the listing sheet's gear menu while the button it controls is painted by
  /// the overlay behind that sheet — something has to tell the screen between
  /// them to rebuild.
  static final tuningTools = ValueNotifier<bool>(false);

  /// Call once alongside [ScanDefaults.loadCurrent].
  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    tuningTools.value = p.getBool(_kTuningTools) ?? false;
  }

  static Future<void> setTuningTools(bool value) async {
    tuningTools.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTuningTools, value);
  }

  /// Test seam — set without touching preferences.
  static void setForTesting({bool tuningTools = false}) {
    DevFlags.tuningTools.value = tuningTools;
  }
}
