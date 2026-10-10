import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

// ignore: unnecessary_import — explicit for debugPaintSizeEnabled (wireframe mode)
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'app_shell.dart';
import 'features/card_lookup/theme/picker_tokens.dart';
import 'core/logging/app_logger.dart';
import 'features/settings/models/app_settings.dart';
import 'features/settings/models/game_tracker_settings.dart';
import 'features/settings/models/setting_enums.dart';
import 'features/settings/services/settings_service.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Global error hooks — analogous to server-side exception middleware.
  //
  // FlutterError.onError   : widget build/layout/painting errors.
  // PlatformDispatcher     : all other uncaught Dart errors (incl. async).
  //
  // Both log via AppLogger then delegate to the default Flutter handler so the
  // red error screen still appears in debug mode.
  // ---------------------------------------------------------------------------
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.e(
      'Flutter error [${details.library ?? "unknown"}]',
      error:      details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details); // preserves red screen in debug
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.e('Uncaught error', error: error, stackTrace: stack);
    return true; // handled — suppresses the default crash
  };

  // debugPaintSizeEnabled = false; // set true to overlay widget bounds (wireframe mode)
  // Load settings here — platform channel is guaranteed ready after
  // ensureInitialized(), eliminating any cold-start stall risk.
  final loaded  = await SettingsService.load();
  final docsDir = await getApplicationDocumentsDirectory();
  AppLogger.configure(level: loaded.app.logLevel, logDir: docsDir.path);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(MtgHomunculusApp(
    service: loaded.service,
    app:     loaded.app,
    gt:      loaded.gt,
  ));
}

class MtgHomunculusApp extends StatefulWidget {
  final SettingsService service;
  final AppSettings     app;
  final GtSettings      gt;

  const MtgHomunculusApp({
    super.key,
    required this.service,
    required this.app,
    required this.gt,
  });

  @override
  State<MtgHomunculusApp> createState() => _MtgHomunculusAppState();
}

class _MtgHomunculusAppState extends State<MtgHomunculusApp> {
  late AppThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.app.themeMode;
  }

  void _onThemeChange(AppThemeMode mode, String colorProfileId) {
    setState(() => _themeMode = mode);
    // TODO(settings): apply colorProfileId to theme once color profiles land
  }

  ThemeMode get _materialThemeMode => switch (_themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light  => ThemeMode.light,
        AppThemeMode.dark   => ThemeMode.dark,
        AppThemeMode.custom => ThemeMode.light, // placeholder until color picking lands
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MtgHomunculus',
      debugShowCheckedModeBanner: false,
      themeMode: _materialThemeMode,
      theme: ThemeData(
        // The card-lookup palette rides alongside the app's own colours rather
        // than replacing them — see PickerTokens.
        extensions: const [PickerTokens.light],
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F4F5),
        colorScheme: ColorScheme.light(
          primary: Colors.blueGrey.shade700,
          surface: const Color(0xFFF2F4F5),
          surfaceContainer: const Color(0xFFE6E9EA),
          surfaceContainerHigh: const Color(0xFFDCE0E2),
          surfaceContainerHighest: const Color(0xFFD0D5D8),
          onSurface: const Color(0xFF1A1A1A),
          onSurfaceVariant: const Color(0xFF555555),
          outline: const Color(0xFF888888),
          outlineVariant: const Color(0xFFBBBBBB),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFE6E9EA),
          foregroundColor: const Color(0xFF1A1A1A),
          titleTextStyle: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 18,
          ),
          iconTheme: const IconThemeData(color: Color(0xFF444444)),
          actionsIconTheme: const IconThemeData(color: Color(0xFF555555)),
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        extensions: const [PickerTokens.dark],
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        colorScheme: ColorScheme.dark(
          primary: Colors.blueGrey.shade700,
          surface: const Color(0xFF1A1A1A),
          surfaceContainer: const Color(0xFF2A2A2A),
          surfaceContainerHigh: const Color(0xFF303030),
          surfaceContainerHighest: const Color(0xFF3A3A3A),
          onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFBBBBBB),
          outline: const Color(0xFF555555),
          outlineVariant: const Color(0xFF383838),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF242424),
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
          iconTheme: IconThemeData(color: Colors.white70),
          actionsIconTheme: IconThemeData(color: Colors.white70),
          elevation: 0,
        ),
      ),
      home: AppShell(
        service:      widget.service,
        app:          widget.app,
        gt:           widget.gt,
        onThemeChange: _onThemeChange,
      ),
    );
  }
}
