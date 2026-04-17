import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/game_state.dart'; // for kPlayerColors

/// Game-tracker settings passed down from AppShell via GameTrackerScreen.
///
/// hapticFeedback lives in AppSettings (app-wide) — not here.
class GtSettings {
  final int holdDurationMs;
  final bool showZeroTrackers;
  final bool confirmNewGame;
  final List<Color> playerColors;

  const GtSettings({
    this.holdDurationMs   = 400,
    this.showZeroTrackers = true,
    this.confirmNewGame   = false,
    this.playerColors     = kPlayerColors,
  });

  @override
  bool operator ==(Object other) =>
      other is GtSettings &&
      other.holdDurationMs   == holdDurationMs &&
      other.showZeroTrackers == showZeroTrackers &&
      other.confirmNewGame   == confirmNewGame &&
      listEquals(other.playerColors, playerColors);

  @override
  int get hashCode => Object.hash(
        holdDurationMs,
        showZeroTrackers,
        confirmNewGame,
        Object.hashAll(playerColors),
      );
}

/// Injects [GtSettings] into the game tracker widget tree.
///
/// Wrap [GameTrackerScreen]'s body with this so any descendant can read
/// settings via [GtSettingsScope.of(context)] without prop drilling.
class GtSettingsScope extends InheritedWidget {
  final GtSettings settings;

  const GtSettingsScope({
    super.key,
    required this.settings,
    required super.child,
  });

  static GtSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GtSettingsScope>();
    assert(scope != null, 'No GtSettingsScope found in context');
    return scope!.settings;
  }

  @override
  bool updateShouldNotify(GtSettingsScope old) => settings != old.settings;
}
