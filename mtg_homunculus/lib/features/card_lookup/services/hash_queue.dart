import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../core/logging/app_logger.dart';
import 'hash_queue_task.dart';
import 'hash_worker.dart';

/// What the UI binds to: starts and stops the hash queue, and mirrors whatever
/// the foreground service reports.
///
/// **It does not do the work.** [HashWorker] does, inside the service's own
/// isolate — see [HashQueueTaskHandler] for why. This side only knows the
/// numbers, so the screen keeps reporting correctly whether the user is looking
/// at it, scanning, or in another app entirely.
class HashQueue extends ChangeNotifier {
  HashQueue._();

  /// Never disposed — the service outlives every screen.
  static final HashQueue instance = HashQueue._();

  /// Per-card download size, for the information line. See
  /// [HashWorker.bytesPerCard].
  static const bytesPerCard = HashWorker.bytesPerCard;

  static const _channelId = 'mtg_hash_queue';

  bool _wired = false;
  bool _running = false;
  bool get running => _running;

  int _hashed = 0;
  int get hashed => _hashed;

  int _done = 0;
  int get done => _done;

  int? _remaining;

  /// Printings still needing a hash, or null before the first count or when
  /// there is no index to compare against.
  ///
  /// This is the *Not yet hashed* figure on the card data screen.
  int? get remaining => _remaining;

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  /// Call once from `main`, before `runApp`.
  ///
  /// [FlutterForegroundTask.initCommunicationPort] registers the port the
  /// service isolate sends progress down, and it has to exist before the
  /// service could possibly start — including when Android restarts the app
  /// into an already-running service.
  static void initMessaging() => FlutterForegroundTask.initCommunicationPort();

  void _wire() {
    if (_wired) return;
    _wired = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Card matching',
        channelDescription:
            'Shown while card images are being fetched and matched.',
        // Silent and low: this is a chore the user started and can ignore. A
        // notification that buzzes for a background download is a nuisance.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The pass is one long run, not a tick: the handler drives its own loop
        // in onStart, so there is no repeat event to schedule.
        eventAction: ForegroundTaskEventAction.nothing(),
        // A wake lock so the CPU keeps decoding with the screen off. No wifi
        // lock — that is for multicast discovery, not ordinary HTTP.
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
  }

  void _onServiceData(Object data) {
    final p = HashProgress.fromMap(data);
    if (p == null) return;

    _hashed = p.hashed;
    _done = p.done;
    _remaining = p.remaining;
    _running = !p.finished;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Counting
  // ---------------------------------------------------------------------------

  /// Count the backlog without starting anything.
  ///
  /// Runs in this isolate, because the card data screen wants the number
  /// whether or not a service is running. It needs every id in the index plus
  /// every hashable id in the table, so it is not a cheap `COUNT(*)`.
  Future<void> count() async {
    if (_running) return;
    try {
      _remaining = await HashWorker().count();
      notifyListeners();
    } catch (e, st) {
      AppLogger.w('HashQueue: count failed', error: e, stackTrace: st);
    }
  }

  // ---------------------------------------------------------------------------
  // Start / stop
  // ---------------------------------------------------------------------------

  /// Start the service, asking for notification permission first if needed.
  ///
  /// Returns false when it could not start — most often because notifications
  /// are denied, which Android requires for a foreground service.
  Future<bool> start() async {
    _wire();
    AppLogger.i('HashQueue: start requested');

    if (await FlutterForegroundTask.isRunningService) {
      // Not an error, but it did happen once and looked like a hang: the
      // service was alive and the UI had no idea.
      AppLogger.w('HashQueue: already running, not starting a second pass');
      _running = true;
      notifyListeners();
      return true;
    }

    // Android 13+ gates the notification, and without a notification there is
    // no foreground service. Asked here rather than at launch, because this is
    // the moment it means something.
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final granted =
          await FlutterForegroundTask.requestNotificationPermission();
      if (granted != NotificationPermission.granted) {
        AppLogger.w('HashQueue: notification permission denied');
        return false;
      }
    }

    _hashed = 0;
    _done = 0;
    _running = true;
    notifyListeners();

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Matching cards',
      notificationText: 'Starting…',
      notificationButtons: [
        const NotificationButton(id: HashQueueButtons.stop, text: 'Stop'),
      ],
      callback: hashQueueCallback,
    );

    if (result is ServiceRequestFailure) {
      AppLogger.w('HashQueue: service failed to start: ${result.error}');
      _running = false;
      notifyListeners();
      await count();
      return false;
    }

    // If the next line is the last one in the log, the native service came up
    // and its Dart isolate did not — the notification would sit on "Starting"
    // forever. That is the failure this line exists to pin down.
    AppLogger.i('HashQueue: service started, waiting for the task isolate');
    return true;
  }

  /// Stop the pass. The backlog is left intact, so starting again resumes it.
  ///
  /// **Asks the handler rather than killing the service.** A hard
  /// `stopService()` tears the task isolate down with eight fetches and their
  /// decode isolates in flight, and after one of those the plugin would not
  /// spawn a replacement isolate on the next start. The handler winds its own
  /// pass down and retires the service; this only falls back to force if it
  /// does not.
  Future<void> stop() async {
    AppLogger.i('HashQueue: stop requested');
    FlutterForegroundTask.sendDataToTask(HashQueueCommands.stop);

    // The UI says stopped straight away; the drain happens behind it.
    _running = false;
    notifyListeners();
    unawaited(_ensureStopped());
  }

  Future<void> _ensureStopped() async {
    // Long enough for the in-flight fetches to hit their 10s timeout.
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!await FlutterForegroundTask.isRunningService) {
        AppLogger.i('HashQueue: service retired itself');
        await count();
        return;
      }
    }
    AppLogger.w('HashQueue: handler did not retire, forcing the service down');
    await FlutterForegroundTask.stopService();
    await count();
  }

  // ---------------------------------------------------------------------------
  // Battery optimisation
  // ---------------------------------------------------------------------------

  /// Whether Android will let this app work with the screen off.
  ///
  /// A foreground service holds a `PARTIAL_WAKE_LOCK`, so the CPU keeps
  /// running — but Doze still **withholds network** from an app that is not
  /// exempt, and the fetches simply stop. Samsung is especially aggressive
  /// about this.
  Future<bool> get ignoringBatteryOptimizations =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;

  /// Ask for the exemption. User-facing and user-initiated by design: this is a
  /// permission Android expects to be requested for a reason the user
  /// recognises, not quietly at launch.
  Future<bool> requestBatteryExemption() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();

  /// Re-read the state after a run ends, including one that finished while the
  /// app was in the background and reported to a port nobody was listening on.
  Future<void> reconcile() async {
    _wire();
    _running = await FlutterForegroundTask.isRunningService;
    if (!_running) await count();
    notifyListeners();
  }
}
