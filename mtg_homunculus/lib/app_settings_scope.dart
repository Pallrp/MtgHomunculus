import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/settings/models/app_settings.dart';
import 'features/settings/models/setting_enums.dart';

// Re-export so callers only need one import for both the scope and the model.
export 'features/settings/models/app_settings.dart' show AppSettings;

/// Fires the appropriate haptic feedback for the current app settings.
/// Call at every interaction point that changes a game value.
void triggerHaptic(BuildContext context) {
  switch (AppSettingsScope.of(context).hapticLevel) {
    case HapticLevel.off:
      return;
    case HapticLevel.on:
      HapticFeedback.vibrate();
  }
}

/// Injects [AppSettings] into the entire sub-app stack.
///
/// Mirrors [GtSettingsScope] but at the app-shell level, making app-wide
/// values (haptic level, text scale, etc.) accessible in any sub-app without
/// prop drilling or touching [GtSettings].
class AppSettingsScope extends InheritedWidget {
  final AppSettings settings;

  const AppSettingsScope({
    super.key,
    required this.settings,
    required super.child,
  });

  static AppSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found in context');
    return scope!.settings;
  }

  @override
  bool updateShouldNotify(AppSettingsScope old) => settings != old.settings;
}
