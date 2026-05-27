import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../game_tracker/models/game_state.dart';  // kPlayerColors
import '../../../features/settings/models/format_preset.dart';

// GtSettingsScope re-exports this class — existing importers of gt_settings_scope.dart
// continue to resolve GtSettings without changes.
class GtSettings {
  final bool confirmNewGame;
  final int holdDurationMs;
  final List<Color> playerColors;
  // Snapshots from SettingsService, kept in sync via AppShell listeners on
  // formatPresetsNotifier.
  final List<FormatPreset> formatPresets;

  const GtSettings({
    this.confirmNewGame   = false,
    this.holdDurationMs   = 400,
    this.playerColors     = kPlayerColors,
    this.formatPresets    = const [],
  });

  GtSettings copyWith({
    bool?               confirmNewGame,
    int?                holdDurationMs,
    List<Color>?        playerColors,
    List<FormatPreset>? formatPresets,
  }) =>
      GtSettings(
        confirmNewGame:   confirmNewGame   ?? this.confirmNewGame,
        holdDurationMs:   holdDurationMs   ?? this.holdDurationMs,
        playerColors:     playerColors     ?? this.playerColors,
        formatPresets:    formatPresets    ?? this.formatPresets,
      );

  @override
  bool operator ==(Object other) =>
      other is GtSettings &&
      other.confirmNewGame   == confirmNewGame &&
      other.holdDurationMs   == holdDurationMs &&
      listEquals(other.playerColors,  playerColors) &&
      listEquals(other.formatPresets, formatPresets);

  @override
  int get hashCode => Object.hash(
        confirmNewGame,
        holdDurationMs,
        Object.hashAll(playerColors),
        Object.hashAll(formatPresets),
      );
}
