import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/app_logger.dart';

import '../../game_tracker/models/game_state.dart'; // kPlayerColors
import '../models/app_settings.dart';
import '../models/format_preset.dart';
import '../models/game_tracker_settings.dart';
import '../models/setting_enums.dart';

class SettingsService {
  final SharedPreferences _prefs;
  final ValueNotifier<List<FormatPreset>> _formatLibrary;

  SettingsService._(
    this._prefs,
    List<FormatPreset> formats,
  ) : _formatLibrary = ValueNotifier(formats);

  // ---------------------------------------------------------------------------
  // Load — one async call at app start
  // ---------------------------------------------------------------------------

  static Future<({SettingsService service, AppSettings app, GtSettings gt})>
      load() async {
    final prefs   = await SharedPreferences.getInstance();
    final service = SettingsService._(
      prefs,
      _readFormatPresets(prefs),
    );
    return (
      service: service,
      app:     service._buildAppSettings(),
      gt:      service._buildGtSettings(),
    );
  }

  // ---------------------------------------------------------------------------
  // AppSettings saves
  // ---------------------------------------------------------------------------

  void setThemeMode(AppThemeMode v)   => _prefs.setString('app.themeMode', v.name);
  void setColorProfileId(String v)    => _prefs.setString('app.colorProfileId', v);
  void setTextScale(double v)         => _prefs.setDouble('app.textScale', v);
  void setKeepAwake(bool v)           => _prefs.setBool('app.keepAwake', v);
  void setHapticLevel(HapticLevel v)  => _prefs.setString('app.hapticLevel', v.name);
  void setLogLevel(LogLevel v)        => _prefs.setString('app.logLevel', v.name);

  // ---------------------------------------------------------------------------
  // GtSettings saves
  // ---------------------------------------------------------------------------

  void setConfirmNewGame(bool v)           => _prefs.setBool('gt.confirmNewGame', v);
  void setHoldSensitivity(HoldSensitivity v) =>
      _prefs.setString('gt.holdSensitivity', v.name);
  void setPlayerColors(List<Color> colors) =>
      _prefs.setString('gt.playerColors', _encodeColors(colors));

  // ---------------------------------------------------------------------------
  // Format presets
  // ---------------------------------------------------------------------------

  ValueNotifier<List<FormatPreset>> get formatPresetsNotifier => _formatLibrary;
  List<FormatPreset> get formatPresets => _formatLibrary.value;

  void addFormatPreset(FormatPreset p) {
    _mutateFormats((l) => l..add(p));
  }

  void updateFormatPreset(FormatPreset p) {
    _mutateFormats((l) {
      final i = l.indexWhere((x) => x.id == p.id);
      if (i != -1) l[i] = p;
    });
  }

  void removeFormatPreset(String id) {
    _mutateFormats((l) => l..removeWhere((p) => p.id == id));
  }

  void reorderFormatPresets(int from, int to) {
    _mutateFormats((l) {
      final p = l.removeAt(from);
      l.insert(to, p);
    });
  }

  void seedDefaultFormats(List<FormatPreset> defaults) {
    final seeded = _prefs.getStringList('gt.seededFormatIds') ?? [];
    final toSeed = defaults.where((p) => !seeded.contains(p.id)).toList();
    if (toSeed.isEmpty) return;
    _mutateFormats((l) => l..addAll(toSeed));
    _prefs.setStringList(
      'gt.seededFormatIds',
      [...seeded, ...toSeed.map((p) => p.id)],
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _mutateFormats(void Function(List<FormatPreset>) fn) {
    final updated = [..._formatLibrary.value];
    fn(updated);
    _formatLibrary.value = updated;
    try {
      _prefs.setString(
        'gt.formatPresets',
        jsonEncode(updated.map((p) => p.toJson()).toList()),
      );
    } catch (e, s) {
      AppLogger.e('Failed to persist format presets', error: e, stackTrace: s);
    }
  }

  AppSettings _buildAppSettings() {
    final themeMode = AppThemeMode.values.firstWhere(
      (e) => e.name == (_prefs.getString('app.themeMode') ?? 'system'),
      orElse: () => AppThemeMode.system,
    );
    final hapticLevel = HapticLevel.values.firstWhere(
      (e) => e.name == (_prefs.getString('app.hapticLevel') ?? 'off'),
      orElse: () => HapticLevel.off,
    );
    final logLevel = LogLevel.values.firstWhere(
      (e) => e.name == (_prefs.getString('app.logLevel') ?? 'errors'),
      orElse: () => LogLevel.errors,
    );
    return AppSettings(
      themeMode:      themeMode,
      colorProfileId: _prefs.getString('app.colorProfileId') ?? 'default',
      textScale:      _prefs.getDouble('app.textScale') ?? 1.0,
      keepAwake:      _prefs.getBool('app.keepAwake') ?? false,
      hapticLevel:    hapticLevel,
      logLevel:       logLevel,
    );
  }

  GtSettings _buildGtSettings() {
    final sensitivity = HoldSensitivity.values.firstWhere(
      (e) => e.name == (_prefs.getString('gt.holdSensitivity') ?? 'medium'),
      orElse: () => HoldSensitivity.medium,
    );
    final colorsRaw = _prefs.getString('gt.playerColors');
    final colors = colorsRaw != null ? _decodeColors(colorsRaw) : kPlayerColors;
    return GtSettings(
      confirmNewGame:   _prefs.getBool('gt.confirmNewGame') ?? false,
      holdDurationMs:   sensitivity.durationMs,
      playerColors:     colors,
    );
  }

  static List<FormatPreset> _readFormatPresets(SharedPreferences prefs) {
    final raw = prefs.getString('gt.formatPresets');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => FormatPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _encodeColors(List<Color> colors) =>
      jsonEncode(colors.map((c) => c.toARGB32()).toList());

  static List<Color> _decodeColors(String raw) =>
      (jsonDecode(raw) as List<dynamic>)
          .map((v) => Color(v as int))
          .toList();
}
