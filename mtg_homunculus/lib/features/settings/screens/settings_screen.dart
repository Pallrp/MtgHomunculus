import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_settings.dart';
import '../models/game_tracker_settings.dart';
import '../models/setting_enums.dart';
import '../services/settings_service.dart';
import '../widgets/log_test_dialog.dart';
import '../widgets/setting_nav_tile.dart';
import '../widgets/setting_segment.dart';
import '../widgets/setting_toggle.dart';
import '../widgets/preset_tracker_list.dart';
import '../widgets/format_preset_list.dart';
import '../widgets/player_color_picker.dart';
import '../../../../core/logging/app_logger.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings app;
  final GtSettings  gt;
  final SettingsService service;
  final ValueChanged<AppSettings> onAppChanged;
  final ValueChanged<GtSettings>  onGtChanged;

  const SettingsScreen({
    super.key,
    required this.app,
    required this.gt,
    required this.service,
    required this.onAppChanged,
    required this.onGtChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _app;
  late GtSettings  _gt;

  @override
  void initState() {
    super.initState();
    _app = widget.app;
    _gt  = widget.gt;
  }

  void _updateApp(AppSettings newApp) {
    setState(() => _app = newApp);
    widget.onAppChanged(newApp);
  }

  void _updateGt(GtSettings newGt) {
    setState(() => _gt = newGt);
    widget.onGtChanged(newGt);
  }

  // Reverse-maps holdDurationMs back to the HoldSensitivity enum for the segment.
  HoldSensitivity get _holdSensitivity => switch (_gt.holdDurationMs) {
        250 => HoldSensitivity.short,
        600 => HoldSensitivity.long,
        _   => HoldSensitivity.medium,
      };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: TabBar(
            tabs: const [Tab(text: 'App'), Tab(text: 'Game Tracker')],
            labelColor: Theme.of(context).colorScheme.onSurface,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            indicatorColor: Theme.of(context).colorScheme.primary,
          ),
        ),
        body: TabBarView(
          children: [_buildAppTab(), _buildGameTrackerTab()],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // App tab (steps 12 + 13)
  // ---------------------------------------------------------------------------

  Widget _buildAppTab() {
    return ListView(
      children: [
        _sectionHeader('Visual'),
        SettingSegment<AppThemeMode>(
          label: 'Theme',
          options: AppThemeMode.values,
          labelOf: (v) => switch (v) {
            AppThemeMode.system => 'System',
            AppThemeMode.light  => 'Light',
            AppThemeMode.dark   => 'Dark',
            AppThemeMode.custom => 'Custom',
          },
          enabledWhen: (v) => v != AppThemeMode.custom,
          value: _app.themeMode,
          onChanged: (v) {
            widget.service.setThemeMode(v);
            _updateApp(_app.copyWith(themeMode: v));
          },
        ),
        // TODO(settings): text scale slider — iceboxed
        // SettingSlider(label: 'Text Scale', value: _app.textScale, min: 0.8, max: 1.4, ...)
        _sectionHeader('Device'),
        SettingToggle(
          label: 'Keep screen awake',
          subtitle: 'Prevents the screen from turning off during a game',
          value: _app.keepAwake,
          onChanged: (v) {
            widget.service.setKeepAwake(v);
            _updateApp(_app.copyWith(keepAwake: v));
          },
        ),
        SettingToggle(
          label: 'Haptic feedback',
          subtitle: 'Vibrate on life total and tracker changes',
          value: _app.hapticLevel == HapticLevel.on,
          onChanged: (v) {
            final level = v ? HapticLevel.on : HapticLevel.off;
            widget.service.setHapticLevel(level);
            _updateApp(_app.copyWith(hapticLevel: level));
          },
        ),
        // TODO(settings): device permissions overview (iceboxed — permission_handler)
        _sectionHeader('Diagnostics'),
        SettingSegment<LogLevel>(
          label: 'Diagnostic logging',
          options: LogLevel.values,
          labelOf: (v) => switch (v) {
            LogLevel.off     => 'Off',
            LogLevel.errors  => 'Errors',
            LogLevel.verbose => 'Verbose',
          },
          value: _app.logLevel,
          onChanged: (v) {
            widget.service.setLogLevel(v);
            _updateApp(_app.copyWith(logLevel: v));
          },
        ),
        SettingNavTile(
          label: 'Share log file',
          subtitle: 'Send app.log via email or cloud storage',
          enabled: _app.logLevel != LogLevel.off,
          onTap: () async {
            final file = XFile(AppLogger.logFilePath);
            await Share.shareXFiles([file], subject: 'MtgHomunculus log');
          },
        ),
        if (kDebugMode)
          SettingNavTile(
            label: 'Test log output', // [dev-tool]
            subtitle: 'Fire a test entry at each log level',
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => LogTestDialog(currentLevel: _app.logLevel),
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Game Tracker tab (steps 14, 15, 16)
  // ---------------------------------------------------------------------------

  Widget _buildGameTrackerTab() {
    return ListView(
      children: [
        _sectionHeader('Presets'),
        ListenableBuilder(
          listenable: widget.service.trackerLibraryNotifier,
          builder: (_, _) => SettingNavTile(
            label: 'Tracker Library',
            subtitle: '${widget.service.trackerLibrary.length} trackers',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => PresetTrackerList(service: widget.service),
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: widget.service.formatPresetsNotifier,
          builder: (_, _) => SettingNavTile(
            label: 'Format Presets',
            subtitle: '${widget.service.formatPresets.length} presets',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => FormatPresetList(service: widget.service),
              ),
            ),
          ),
        ),
        _sectionHeader('Players'),
        SettingNavTile(
          label: 'Player Colors',
          subtitle: 'Default color per player slot',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerColorPicker(
                colors: _gt.playerColors,
                service: widget.service,
                onColorsChanged: (colors) {
                  _updateGt(_gt.copyWith(playerColors: colors));
                },
              ),
            ),
          ),
        ),
        _sectionHeader('Gameplay'),
        SettingToggle(
          label: 'Show zero-value trackers',
          subtitle: 'Keep tracker pills visible when their value is 0',
          value: _gt.showZeroTrackers,
          onChanged: (v) {
            widget.service.setShowZeroTrackers(v);
            _updateGt(_gt.copyWith(showZeroTrackers: v));
          },
        ),
        SettingToggle(
          label: 'Confirm before New Game',
          subtitle: 'Ask before wiping the current game',
          value: _gt.confirmNewGame,
          onChanged: (v) {
            widget.service.setConfirmNewGame(v);
            _updateGt(_gt.copyWith(confirmNewGame: v));
          },
        ),
        SettingSegment<HoldSensitivity>(
          label: 'Hold sensitivity',
          options: HoldSensitivity.values,
          labelOf: (v) => switch (v) {
            HoldSensitivity.short  => 'Short',
            HoldSensitivity.medium => 'Medium',
            HoldSensitivity.long   => 'Long',
          },
          value: _holdSensitivity,
          onChanged: (v) {
            widget.service.setHoldSensitivity(v);
            _updateGt(_gt.copyWith(holdDurationMs: v.durationMs));
          },
        ),
        // TODO(settings): life history (iceboxed — see player_card.dart)
        // TODO(settings): audio profiles (iceboxed — triggers: life change, KO, game start)
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
            fontSize: 11,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
