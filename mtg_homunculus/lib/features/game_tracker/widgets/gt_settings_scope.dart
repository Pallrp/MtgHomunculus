import 'package:flutter/material.dart';
import '../../settings/models/game_tracker_settings.dart';

// Re-export so existing importers of this file still resolve GtSettings.
export '../../settings/models/game_tracker_settings.dart' show GtSettings;

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
