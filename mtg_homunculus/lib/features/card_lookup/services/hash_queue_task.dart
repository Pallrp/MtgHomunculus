import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../settings/services/settings_service.dart';
import 'hash_worker.dart';

/// The foreground service's entry point. Top level and annotated: the plugin
/// looks it up by handle, and release builds would tree-shake it otherwise.
@pragma('vm:entry-point')
void hashQueueCallback() {
  FlutterForegroundTask.setTaskHandler(HashQueueTaskHandler());
}

/// Runs [HashWorker] inside the foreground service, in its own isolate.
///
/// Nothing from the UI isolate is reachable here; `CardsDatabase.instance`
/// resolves to a second connection, which the job only reads, once. See
/// `.claude/background_processing.md`.
class HashQueueTaskHandler extends TaskHandler {
  HashWorker? _worker;

  /// Android drops notification updates that come faster than it draws them.
  static const _notifyEvery = Duration(seconds: 1);
  DateTime _lastNotified = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long teardown waits for the job to unwind.
  static const _unwindGrace = Duration(seconds: 5);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // No plugin has a channel in this isolate until this runs.
    DartPluginRegistrant.ensureInitialized();
    await _attachLogger();
    AppLogger.i('HashQueueTask: started by ${starter.name}');

    // Jobs start only from the app. A system restart is one nobody asked for.
    if (starter == TaskStarter.system) {
      AppLogger.i('HashQueueTask: system restart refused, stopping');
      await FlutterForegroundTask.stopService();
      return;
    }

    final worker = _worker = HashWorker();
    await worker.run(onProgress: _report);

    // Retiring from inside is the orderly path; see HashQueue.stop.
    AppLogger.i('HashQueueTask: finished, stopping service');
    await FlutterForegroundTask.stopService();
  }

  /// `AppLogger` is static, and statics are per isolate: without this every
  /// log call here is a silent no-op.
  Future<void> _attachLogger() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final loaded = await SettingsService.load();
      AppLogger.attachSecondary(level: loaded.app.logLevel, logDir: dir.path);
    } catch (_) {
      // Logging is diagnostics; failing to start it must not stop the work.
    }
  }

  void _report(HashProgress p) {
    FlutterForegroundTask.sendDataToMain(p.toMap());

    final now = DateTime.now();
    if (!p.finished && now.difference(_lastNotified) < _notifyEvery) return;
    _lastNotified = now;

    unawaited(FlutterForegroundTask.updateService(
      notificationTitle: 'Matching cards',
      notificationText: p.total == 0
          ? 'Checking…'
          : '${p.hashed} matched · ${p.remaining} left',
    ));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  /// Stop the job and wait for it before the engine goes.
  ///
  /// The plugin destroys the engine only once this returns, so however the
  /// service is stopped, nothing is left in flight when it does. On the normal
  /// path the job has already finished and this returns at once.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    AppLogger.i('HashQueueTask: destroyed${isTimeout ? ' (timeout)' : ''}');
    final worker = _worker;
    if (worker == null) return;

    worker.stop();
    try {
      await worker.finished.timeout(_unwindGrace);
    } on TimeoutException {
      AppLogger.w('HashQueueTask: job did not unwind within '
          '${_unwindGrace.inSeconds}s; tearing down anyway');
    }
  }

  /// The notification's Stop button.
  @override
  void onNotificationButtonPressed(String id) {
    if (id != HashQueueButtons.stop) return;
    AppLogger.i('HashQueueTask: stop pressed');
    _worker?.stop();
  }

  /// In-app stop, relayed from the UI isolate — asked, not killed.
  @override
  void onReceiveData(Object data) {
    if (data != HashQueueCommands.stop) return;
    AppLogger.i('HashQueueTask: stop requested by the app');
    _worker?.stop();
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

abstract final class HashQueueButtons {
  static const stop = 'hash_stop';
}

abstract final class HashQueueCommands {
  static const stop = 'stop';
}
