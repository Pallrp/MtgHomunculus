import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../game_tracker/models/game_state.dart';  // kPlayerColors
import '../../game_tracker/models/tracker.dart';
import '../../../features/settings/models/format_preset.dart';

// Moved from gt_settings_scope.dart and extended with trackerLibrary + copyWith.
// GtSettingsScope re-exports this class — existing importers of gt_settings_scope.dart
// continue to resolve GtSettings without changes.
class GtSettings {
  final bool showZeroTrackers;
  final bool confirmNewGame;
  final int holdDurationMs;
  final List<Color> playerColors;
  // When true, active GameEffects that affect screen colors (e.g. DayNightEffect)
  // are allowed to override the game tracker's Theme. Structural additions such
  // as card borders and effect icons are never affected by this setting.
  final bool adaptiveTheme;
  // Snapshots from SettingsService, kept in sync via AppShell listeners on
  // trackerLibraryNotifier and formatPresetsNotifier.
  final List<Tracker>       trackerLibrary;
  final List<FormatPreset>  formatPresets;

  const GtSettings({
    this.showZeroTrackers = true,
    this.confirmNewGame   = false,
    this.holdDurationMs   = 400,
    this.playerColors     = kPlayerColors,
    this.adaptiveTheme    = true,
    this.trackerLibrary   = const [],
    this.formatPresets    = const [],
  });

  GtSettings copyWith({
    bool?               showZeroTrackers,
    bool?               confirmNewGame,
    int?                holdDurationMs,
    List<Color>?        playerColors,
    bool?               adaptiveTheme,
    List<Tracker>?      trackerLibrary,
    List<FormatPreset>? formatPresets,
  }) =>
      GtSettings(
        showZeroTrackers: showZeroTrackers ?? this.showZeroTrackers,
        confirmNewGame:   confirmNewGame   ?? this.confirmNewGame,
        holdDurationMs:   holdDurationMs   ?? this.holdDurationMs,
        playerColors:     playerColors     ?? this.playerColors,
        adaptiveTheme:    adaptiveTheme    ?? this.adaptiveTheme,
        trackerLibrary:   trackerLibrary   ?? this.trackerLibrary,
        formatPresets:    formatPresets    ?? this.formatPresets,
      );

  @override
  bool operator ==(Object other) =>
      other is GtSettings &&
      other.showZeroTrackers == showZeroTrackers &&
      other.confirmNewGame   == confirmNewGame &&
      other.holdDurationMs   == holdDurationMs &&
      other.adaptiveTheme    == adaptiveTheme &&
      listEquals(other.playerColors,   playerColors) &&
      listEquals(other.trackerLibrary, trackerLibrary) &&
      listEquals(other.formatPresets,  formatPresets);
  // Note: listEquals on trackerLibrary uses Tracker's == (identity by default).
  // Implement Tracker.== if spurious GtSettingsScope rebuilds become a concern.

  @override
  int get hashCode => Object.hash(
        showZeroTrackers,
        confirmNewGame,
        holdDurationMs,
        adaptiveTheme,
        Object.hashAll(playerColors),
        Object.hashAll(trackerLibrary),
        Object.hashAll(formatPresets),
      );
}
