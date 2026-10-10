import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../../settings/services/settings_service.dart';
import 'hash_worker.dart';

/// The foreground service's entry point.
///
/// **Must be top level and annotated**, because the plugin looks it up by
/// handle to start a *second* Flutter isolate — tree shaking would otherwise
/// remove it from a release build.
@pragma('vm:entry-point')
void hashQueueCallback() {
  FlutterForegroundTask.setTaskHandler(HashQueueTaskHandler());
}

/// Runs [HashWorker] inside the foreground service.
///
/// **Why a service at all.** Android cuts DNS for a backgrounded app — measured
/// on device as `SocketException: Failed host lookup … errno = 7` on 2008 of
/// 2010 consecutive fetches. A foreground service with `dataSync` is the only
/// sanctioned way to keep fetching while the user is in another app, and the
/// notification is a fair trade: it carries live progress and a stop button.
///
/// **This runs in its own isolate.** Nothing from the UI isolate is reachable —
/// not `HashQueue.instance`, not a loaded `HashIndex`, not the open database.
/// `CardsDatabase.instance` resolves here to a second connection to the same
/// file, which is fine because the worker only reads it.
class HashQueueTaskHandler extends TaskHandler {
  HashWorker? _worker;

  /// Notification updates are throttled: the worker reports per card, and at
  /// eight concurrent fetches that is dozens a second. Android coalesces
  /// notification updates anyway, and hammering it wastes battery.
  ///
  /// Kept low because with the screen off the notification is the *only* live
  /// indicator — the UI isolate is suspended and its count goes stale, which
  /// is why the two numbers disagreed.
  static const _notifyEvery = 10;
  int _lastNotified = -1;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // The service isolate starts with no plugins registered, so anything that
    // touches a platform channel — path_provider, which both the database and
    // the index file need — fails until this runs.
    DartPluginRegistrant.ensureInitialized();
    await _attachLogger();

    AppLogger.i('HashQueueTask: started by $starter');

    final worker = _worker = HashWorker();
    await worker.run(onProgress: _report);

    // The work is finite: when the backlog is done the service has no reason to
    // keep a notification alive, so it retires itself.
    AppLogger.i('HashQueueTask: finished, stopping service');
    await FlutterForegroundTask.stopService();
  }

  /// Without this every log call in this isolate is a silent no-op, because
  /// `AppLogger`'s logger is a static and `main()` — which configures it —
  /// never ran here. The level comes from the same setting the UI reads, so
  /// turning on Verbose covers the service too.
  Future<void> _attachLogger() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final loaded = await SettingsService.load();
      AppLogger.attachSecondary(
        level: loaded.app.logLevel,
        logDir: dir.path,
      );
    } catch (_) {
      // Logging is diagnostics; failing to start it must not stop the work.
    }
  }

  void _report(HashProgress p) {
    FlutterForegroundTask.sendDataToMain(p.toMap());

    if (p.finished || p.done - _lastNotified >= _notifyEvery) {
      _lastNotified = p.done;
      FlutterForegroundTask.updateService(
        notificationTitle: 'Matching cards',
        notificationText: p.total == 0
            ? 'Checking…'
            : '${p.hashed} of ${p.total} matched',
      );
    }
  }

  /// Unused: the work is a single long pass, not a repeating tick.
  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    AppLogger.i('HashQueueTask: destroyed');
    _worker?.stop();
  }

  /// The notification's stop button.
  @override
  void onNotificationButtonPressed(String id) {
    if (id != HashQueueButtons.stop) return;
    AppLogger.i('HashQueueTask: stop pressed');
    _worker?.stop();
  }

  /// In-app stop, relayed from the UI isolate.
  ///
  /// **Asked, not killed.** Stopping the service from outside tears this
  /// isolate down mid-flight — eight HTTP gets and their decode isolates — and
  /// after one of those the plugin failed to spawn a replacement isolate on the
  /// next start: the notification appeared and `onStart` never ran. Letting the
  /// handler wind down its own pass and retire the service keeps the teardown
  /// orderly.
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
