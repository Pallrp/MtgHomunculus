import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_settings_scope.dart';
import 'sub_app.dart';
import 'features/game_tracker/models/default_formats.dart';
import 'features/game_tracker/screens/game_tracker_screen.dart';
import 'core/logging/app_logger.dart';
import 'features/card_lookup/data/cards_database.dart';
import 'features/card_lookup/screens/card_data_setup_screen.dart';
import 'features/card_lookup/screens/listing_home_screen.dart';
import 'features/settings/models/game_tracker_settings.dart';
import 'features/settings/models/setting_enums.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/settings/services/settings_service.dart';

class AppShell extends StatefulWidget {
  final SettingsService service;
  final AppSettings     app;
  final GtSettings      gt;
  // Called when themeMode or colorProfileId changes so MtgHomunculusApp
  // can rebuild MaterialApp with the new theme.
  final void Function(AppThemeMode themeMode, String colorProfileId) onThemeChange;

  const AppShell({
    super.key,
    required this.service,
    required this.app,
    required this.gt,
    required this.onThemeChange,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late SettingsService _service;
  late AppSettings     _app;
  late GtSettings      _gt;
  // ignore: prefer_final_fields — will be reassigned when sub-app switching lands
  SubApp _activeSubApp = SubApp.gameTracker;

  late AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _app     = widget.app;

    _service.seedDefaultFormats(kDefaultFormats);

    _gt = widget.gt.copyWith(
      formatPresets: _service.formatPresets,
    );

    _service.formatPresetsNotifier.addListener(_onFormatPresetsChanged);

    _lifecycleListener = AppLifecycleListener(
      onResume: _applyWakelock,
      onPause:  () => WakelockPlus.disable(),
    );

    // Schedule wakelock post-frame — platform channel call, not safe mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyWakelock());
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _service.formatPresetsNotifier.removeListener(_onFormatPresetsChanged);
    _cardsDb?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Library listeners
  // ---------------------------------------------------------------------------

  void _onFormatPresetsChanged() {
    if (!mounted) return;
    setState(() => _gt = _gt.copyWith(formatPresets: _service.formatPresets));
  }

  // ---------------------------------------------------------------------------
  // Settings callbacks (passed to SettingsScreen)
  // ---------------------------------------------------------------------------

  void _onAppChanged(AppSettings newApp) {
    final themeChanged = newApp.themeMode     != _app.themeMode ||
                         newApp.colorProfileId != _app.colorProfileId;
    final wakeChanged  = newApp.keepAwake      != _app.keepAwake;
    final levelChanged = newApp.logLevel       != _app.logLevel;
    setState(() => _app = newApp);
    if (themeChanged) widget.onThemeChange(newApp.themeMode, newApp.colorProfileId);
    if (wakeChanged)  _applyWakelock();
    if (levelChanged) AppLogger.setLevel(newApp.logLevel);
  }

  void _onGtChanged(GtSettings newGt) {
    setState(() => _gt = newGt);
  }

  // ---------------------------------------------------------------------------
  // Wakelock
  // ---------------------------------------------------------------------------

  void _applyWakelock() {
    if (_app.keepAwake) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _openSettings() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          app:          _app,
          gt:           _gt,
          service:      _service,
          onAppChanged: _onAppChanged,
          onGtChanged:  _onGtChanged,
        ),
      ),
    );
  }

  /// Card database, opened lazily and kept for the process lifetime.
  ///
  /// Opening is cheap — drift connects on first use — so this costs nothing until
  /// the card lookup is actually entered.
  CardsDatabase? _cardsDb;
  CardsDatabase get _cards => _cardsDb ??= CardsDatabase();

  Future<void> _openCardLookup() async {
    // First run has no card data, and the sub-app cannot do anything useful
    // without it: search returns nothing and identification has nothing to match
    // against. Setup blocks; updates never do.
    final imported = await _cards.metaValue(MetaKeys.bulkImportedAt);
    if (!mounted) return;

    if (imported == null || imported.isEmpty) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (ctx) => CardDataSetupScreen(
            db: _cards,
            // Replace the setup screen rather than stacking on it — there is
            // nothing to go back to.
            onReady: () => Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => const ListingHomeScreen()),
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const ListingHomeScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: _app,
      child: Stack(
        children: [
          // Persistent sub-apps — always mounted, toggled visible/hidden.
          Offstage(
            offstage: _activeSubApp != SubApp.gameTracker,
            child: GameTrackerScreen(
              settings:         _gt,
              onSettingsTap:    _openSettings,
              onCardLookupTap:  _openCardLookup,
            ),
          ),

          // On-demand sub-apps (iceboxed — add as sub-apps are built):
          // if (_activeSubApp == SubApp.deckBuilder) DeckBuilderScreen(),
          // if (_activeSubApp == SubApp.cardLookup)  CardLookupScreen(),
        ],
      ),
    );
  }
}
