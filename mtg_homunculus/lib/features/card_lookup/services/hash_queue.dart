import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../core/logging/app_logger.dart';
import 'hash_queue_task.dart';
import 'hash_worker.dart';

/// What the UI binds to: starts and stops the hash job, and mirrors what the
/// foreground service reports. The work itself runs in the service — see
/// [HashQueueTaskHandler] and `.claude/background_processing.md`.
class HashQueue extends ChangeNotifier {
  HashQueue._();

  /// Never disposed — the service outlives every screen.
  static final HashQueue instance = HashQueue._();

  /// Per-card download size, for the information line.
  static const bytesPerCard = HashWorker.bytesPerCard;

  static const _channelId = 'mtg_hash_queue';

  /// How long a stop may take before the service is forced down. A last
  /// resort: a healthy job retires itself within about a second, and a forced
  /// stop can leave the next start stalled.
  static const _stopGrace = Duration(seconds: 30);

  bool _wired = false;
  AppLifecycleListener? _lifecycle;

  bool _running = false;
  bool get running => _running;

  int _hashed = 0;

  /// Cards that gained a fingerprint this job — not merely processed.
  int get hashed => _hashed;

  int _done = 0;
  int get done => _done;

  int _total = 0;
  int get total => _total;

  int? _remaining;

  /// The *Not yet hashed* figure: null before the first count, or with no index.
  int? get remaining => _remaining;

  /// Completes when the running job ends. Null while idle.
  Completer<void>? _ended;

  /// A start asked for in the background, waiting for the next resume.
  Completer<bool>? _deferred;

  /// From a start request until the service is up — when "no service" means
  /// "not yet", not "ended".
  bool _starting = false;

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  /// Call once from `main`, before `runApp`: the port progress arrives on.
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
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        showWhen: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        // The service keeps the process alive; these keep the CPU and the
        // Wi-Fi radio awake with the screen off.
        allowWakeLock: true,
        allowWifiLock: true,
        // Jobs start only from the app — never on boot, update or restart.
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: false,
        // Swiping the app away does not stop the job. Matches the manifest.
        stopWithTask: false,
      ),
    );

    FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onServiceData(Object data) {
    final p = HashProgress.fromMap(data);
    if (p == null) return;

    _hashed = p.hashed;
    _done = p.done;
    _total = p.total;
    _remaining = p.remaining;
    _running = !p.finished;
    notifyListeners();

    if (p.finished) unawaited(_finish());
  }

  /// Release anyone waiting on the job, and re-count against the index.
  Future<void> _finish() async {
    final ended = _ended;
    _ended = null;
    _running = false;
    notifyListeners();
    await count();
    if (ended != null && !ended.isCompleted) ended.complete();
  }

  void _onResume() {
    final deferred = _deferred;
    if (deferred != null) {
      _deferred = null;
      AppLogger.i('HashQueue: app resumed, starting the deferred job');
      unawaited(_startNow().then(deferred.complete));
    }
    unawaited(reconcile());
  }

  // ---------------------------------------------------------------------------
  // Counting
  // ---------------------------------------------------------------------------

  /// Count the backlog without starting anything. Reads the whole index, so
  /// only the card data screen and a job's end call it.
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

  /// Start a job, or attach to the one already running.
  ///
  /// Android 12+ refuses to start a foreground service from the background, so
  /// a start asked for there waits for the next resume. Returns false when it
  /// could not start — most often because notifications are denied.
  Future<bool> start() async {
    _wire();
    AppLogger.i('HashQueue: start requested');

    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      AppLogger.i('HashQueue: app in the background, deferring to resume');
      return (_deferred ??= Completer<bool>()).future;
    }
    return _startNow();
  }

  /// [start], then wait for the job to end — what an Update awaits.
  Future<void> runToEnd() async {
    if (!await start()) return;
    await _ended?.future;
  }

  Future<bool> _startNow() async {
    _starting = true;
    try {
      return await _startService();
    } finally {
      _starting = false;
    }
  }

  Future<bool> _startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      AppLogger.i('HashQueue: already running, attaching');
      _markRunning();
      return true;
    }

    // The notification carries the Stop button; asked for when it matters.
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
    _total = 0;
    _markRunning();

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Matching cards',
      notificationText: 'Starting…',
      notificationButtons: [
        const NotificationButton(id: HashQueueButtons.stop, text: 'Stop'),
      ],
      callback: hashQueueCallback,
    );

    if (result is ServiceRequestFailure) {
      AppLogger.w('HashQueue: service failed to start: ${result.error}');
      await _finish();
      return false;
    }

    AppLogger.i('HashQueue: service started, waiting for the task isolate');
    return true;
  }

  void _markRunning() {
    _running = true;
    _ended ??= Completer<void>();
    notifyListeners();
  }

  /// Stop the job. Asks the handler, which winds down and retires the service
  /// itself; the service is forced down only after [_stopGrace].
  Future<void> stop() async {
    AppLogger.i('HashQueue: stop requested');
    FlutterForegroundTask.sendDataToTask(HashQueueCommands.stop);
    unawaited(_ensureStopped());
  }

  Future<void> _ensureStopped() async {
    final deadline = DateTime.now().add(_stopGrace);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!await FlutterForegroundTask.isRunningService) {
        AppLogger.i('HashQueue: service retired itself');
        if (_running) await _finish();
        return;
      }
    }
    AppLogger.w('HashQueue: handler did not retire within '
        '${_stopGrace.inSeconds}s, forcing the service down');
    await FlutterForegroundTask.stopService();
    await _finish();
  }

  /// Re-read the service's state on launch and resume: catch a job that ended
  /// unheard, and re-bind to one still running.
  Future<void> reconcile() async {
    _wire();
    if (_starting) return;
    final alive = await FlutterForegroundTask.isRunningService;
    if (alive && !_running) {
      AppLogger.i('HashQueue: found a running job, re-binding');
      _markRunning();
    } else if (!alive && _running) {
      AppLogger.i('HashQueue: job ended while nobody was listening');
      await _finish();
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }
}
