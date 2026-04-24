// Enums used by the settings system.
// Stored as their .name string in shared_preferences; resolved to concrete
// values at build / interaction time.

enum AppThemeMode { system, light, dark, custom }
// Flutter's ThemeMode has no 'custom' variant — we wrap it with our own.
// 'custom' is a disabled segment in the UI until color picking is implemented.
// Resolved to ThemeMode at MaterialApp build time (custom → ThemeMode.light placeholder).

enum HapticLevel { off, on }
// Resolved to HapticFeedback.vibrate() at interaction time.
// 'low'/'high' stored values from older installs fall back to 'off' via orElse.

enum LogLevel { off, errors, verbose }
// off     → nothing written
// errors  → Level.error and above (default)
// verbose → Level.trace and above (for diagnostics)

enum HoldSensitivity { short, medium, long }
// Resolved to holdDurationMs when building GtSettings.

extension HoldSensitivityMs on HoldSensitivity {
  int get durationMs => switch (this) {
        HoldSensitivity.short  => 250,
        HoldSensitivity.medium => 400,
        HoldSensitivity.long   => 600,
      };
}
