import 'setting_enums.dart';

class AppSettings {
  final AppThemeMode themeMode;
  final String colorProfileId;
  final double textScale;
  final bool keepAwake;
  final HapticLevel hapticLevel;
  final LogLevel logLevel;

  const AppSettings({
    this.themeMode      = AppThemeMode.system,
    this.colorProfileId = 'default',
    this.textScale      = 1.0,
    this.keepAwake      = false,
    this.hapticLevel    = HapticLevel.off,
    this.logLevel       = LogLevel.errors,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String?       colorProfileId,
    double?       textScale,
    bool?         keepAwake,
    HapticLevel?  hapticLevel,
    LogLevel?     logLevel,
  }) =>
      AppSettings(
        themeMode:      themeMode      ?? this.themeMode,
        colorProfileId: colorProfileId ?? this.colorProfileId,
        textScale:      textScale      ?? this.textScale,
        keepAwake:      keepAwake      ?? this.keepAwake,
        hapticLevel:    hapticLevel    ?? this.hapticLevel,
        logLevel:       logLevel       ?? this.logLevel,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode      == themeMode &&
      other.colorProfileId == colorProfileId &&
      other.textScale      == textScale &&
      other.keepAwake      == keepAwake &&
      other.hapticLevel    == hapticLevel &&
      other.logLevel       == logLevel;

  @override
  int get hashCode => Object.hash(
        themeMode,
        colorProfileId,
        textScale,
        keepAwake,
        hapticLevel,
        logLevel,
      );
}
