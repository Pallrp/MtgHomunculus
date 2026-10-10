import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../../features/settings/models/setting_enums.dart';

const _kLogFile   = 'app_log.txt';
const _kLogBackup = 'app_log.1.txt';

class AppLogger {
  static Logger? _logger;
  static String  _logFilePath = '';
  static bool    _initialized = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static String get logFilePath => _logFilePath;

  /// Full setup — resolve path and rotation. Call once in main() before runApp().
  static void configure({required LogLevel level, required String logDir}) {
    _logFilePath = '$logDir/$_kLogFile';

    if (!_initialized) {
      _initialized = true;
      _clearLogFile(); // Fresh log on each app startup
      _rotateIfNeeded();
    }

    _logger = _buildLogger(level);

    if (level != LogLevel.off) {
      _logger!.i(
        'Logger configured — level: ${level.name}, '
        'logFile: $_logFilePath, '
        'fileSize: ${_currentFileSizeKb().toStringAsFixed(1)} KB',
      );
    }
  }

  /// Attach the logger in a **secondary isolate**, appending to the existing
  /// file.
  ///
  /// `_logger` is a `static`, and in Dart statics live per isolate — so the
  /// foreground service's isolate starts with a null one and every log call
  /// there is a silent no-op until this runs. It cannot use [configure],
  /// because `_initialized` is per isolate too: that path would read as a
  /// fresh start and **clear the log the UI isolate is writing**.
  ///
  /// Both isolates then append to one file. Lines may interleave, which is
  /// preferable to hunting through two files, and each write is a single
  /// open-append-close so a line is never torn in half.
  static void attachSecondary({
    required LogLevel level,
    required String logDir,
  }) {
    _logFilePath = '$logDir/$_kLogFile';
    _initialized = true; // never clear, never rotate from here
    _logger = _buildLogger(level);
  }

  /// Lightweight level change — call from AppShell when the setting changes.
  static void setLevel(LogLevel level) {
    _logger = _buildLogger(level);
  }

  static void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger?.e(message, error: error, stackTrace: stackTrace);

  static void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger?.w(message, error: error, stackTrace: stackTrace);

  static void i(String message) => _logger?.i(message);

  static void d(String message) => _logger?.d(message);

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Logger _buildLogger(LogLevel level) {
    final loggerLevel = switch (level) {
      LogLevel.off     => Level.off,
      LogLevel.errors  => Level.error,
      LogLevel.verbose => Level.trace,
    };

    // SimplePrinter produces clean timestamped plain text — readable in both
    // the log file and the debug console without ANSI escape codes in the file.
    final outputs = <LogOutput>[
      _FileOutput(_logFilePath),
      if (kDebugMode) ConsoleOutput(),
    ];

    return Logger(
      level:   loggerLevel,
      output:  outputs.length == 1 ? outputs.first : MultiOutput(outputs),
      printer: SimplePrinter(colors: false, printTime: true),
    );
  }

  static void _clearLogFile() {
    try {
      final file = File(_logFilePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Clear failure is non-fatal — continue with existing file.
    }
  }

  static void _rotateIfNeeded() {
    try {
      final file = File(_logFilePath);
      if (file.existsSync() && file.lengthSync() > 512 * 1024) {
        final dir = _logFilePath.substring(0, _logFilePath.lastIndexOf('/'));
        file.renameSync('$dir/$_kLogBackup');
      }
    } catch (_) {
      // Rotation failure is non-fatal — continue with existing file.
    }
  }

  static double _currentFileSizeKb() {
    try {
      final file = File(_logFilePath);
      return file.existsSync() ? file.lengthSync() / 1024 : 0;
    } catch (_) {
      return 0;
    }
  }
}

// ---------------------------------------------------------------------------
// Custom file output — dart:io File append, silently swallows all errors.
// ---------------------------------------------------------------------------

class _FileOutput extends LogOutput {
  final String path;
  _FileOutput(this.path);

  @override
  void output(OutputEvent event) {
    if (path.isEmpty) return;
    try {
      File(path).writeAsStringSync(
        '${event.lines.join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Silently swallow — log writes must never crash the app.
    }
  }
}
