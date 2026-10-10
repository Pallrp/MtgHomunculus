import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../data/bulk_importer.dart';
import '../data/cards_database.dart';
import 'hash_queue.dart';

/// Which of the update control's states is showing.
enum UpdatePhase {
  /// Nothing has been asked. The control offers *Check for updates*.
  idle,

  /// A `HEAD` is in flight.
  checking,

  /// The ETag matched. Includes the case where the user pressed *Update* on a
  /// stale badge and the remote file had settled since — "already up to date"
  /// is a state, not a failure.
  upToDate,

  /// The ETag differs. The control offers *Update*.
  available,

  /// An import is running. [CardDataUpdater.progress] carries the step.
  running,

  /// The check or the import failed. [CardDataUpdater.error] carries why.
  failed,
}

/// One-shot news for the shell to surface wherever the user happens to be.
enum CardDataOutcome { updated, failed }

/// Owns checking for and applying card-data updates.
///
/// **A singleton, deliberately not a screen's state.** An Update does not
/// block, so the user can leave the card data screen mid-download — and if the
/// screen owned the import, leaving would kill it. Living here, the transfer
/// continues and the screen re-attaches by listening on its way back in.
///
/// It does **not** touch the hash index. Per `local_data_store.md`, Update
/// enqueues what the import touched and leaves the index alone; re-fetching it
/// is Re-download's job, which runs through the setup screen instead.
class CardDataUpdater extends ChangeNotifier {
  CardDataUpdater._();

  /// Never disposed — it outlives every screen by design.
  static final CardDataUpdater instance = CardDataUpdater._();

  /// What the bulk file costs, for the one sentence that decides whether now is
  /// the moment. Approximate and deliberately rounded.
  static const downloadSize = '78 MB';

  static const _weekly = Duration(days: 7);

  CardsDatabase get _db => CardsDatabase.instance;

  UpdatePhase _phase = UpdatePhase.idle;
  UpdatePhase get phase => _phase;

  ImportProgress? _progress;
  ImportProgress? get progress => _progress;

  Object? _error;
  Object? get error => _error;

  DateTime? _checkedAt;
  DateTime? get checkedAt => _checkedAt;

  /// True once a check has found a difference, until an import clears it.
  ///
  /// Backed by `meta.pending_etag`, so it survives a restart.
  bool _updateAvailable = false;
  bool get updateAvailable => _updateAvailable;

  bool get busy =>
      _phase == UpdatePhase.checking || _phase == UpdatePhase.running;

  final _outcomes = StreamController<CardDataOutcome>.broadcast();

  /// Completion news. The shell listens and shows it over whatever is on
  /// screen, because an Update the user started may well finish while they are
  /// scanning.
  Stream<CardDataOutcome> get outcomes => _outcomes.stream;

  // ---------------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------------

  /// Restore the badge from `meta`, then run the weekly check if it is due.
  ///
  /// Safe to call on every entry into the sub-app.
  Future<void> refresh() async {
    await _restorePending();
    await _weeklyCheck();
  }

  Future<void> _restorePending() async {
    try {
      final pending = await _db.metaValue(MetaKeys.pendingEtag) ?? '';
      final current = await _db.metaValue(MetaKeys.bulkEtag) ?? '';
      final available = pending.isNotEmpty && pending != current;
      if (available != _updateAvailable) {
        _updateAvailable = available;
        if (available && _phase == UpdatePhase.idle) {
          _phase = UpdatePhase.available;
        }
        notifyListeners();
      }
    } catch (e) {
      AppLogger.w('CardDataUpdater: could not read pending etag', error: e);
    }
  }

  Future<void> _weeklyCheck() async {
    if (busy) return;
    try {
      final last = await _db.metaValue(MetaKeys.lastUpdatePrompted) ?? '';
      final when = DateTime.tryParse(last);
      if (when != null && DateTime.now().difference(when) < _weekly) return;
    } catch (_) {
      return;
    }
    await check(manual: false);
  }

  // ---------------------------------------------------------------------------
  // Check
  // ---------------------------------------------------------------------------

  /// Compare the remote ETag against the stored one.
  ///
  /// [manual] separates the two callers, because a failure means different
  /// things to each. An automatic check that fails says **nothing** — a flake is
  /// not news. A manual one has a button press behind it, so it reports, or the
  /// control looks broken.
  ///
  /// Either way a failed check does **not** advance `last_update_prompted`: it
  /// retries on the next launch rather than waiting out a week on a flake.
  Future<void> check({bool manual = true}) async {
    if (busy) return;
    _phase = UpdatePhase.checking;
    _error = null;
    notifyListeners();

    final remote = await BulkImporter.remoteEtag();
    if (remote == null || remote.isEmpty) {
      AppLogger.w('CardDataUpdater: ETag check failed');
      if (manual) {
        _phase = UpdatePhase.failed;
        _error = 'Could not reach Scryfall.';
      } else {
        _phase = _updateAvailable ? UpdatePhase.available : UpdatePhase.idle;
      }
      notifyListeners();
      return;
    }

    final current = await _db.metaValue(MetaKeys.bulkEtag) ?? '';
    final differs = remote != current;

    await _db.setMeta(MetaKeys.pendingEtag, differs ? remote : '');
    await _stampChecked();

    _updateAvailable = differs;
    _phase = differs ? UpdatePhase.available : UpdatePhase.upToDate;
    notifyListeners();
  }

  Future<void> _stampChecked() async {
    _checkedAt = DateTime.now();
    await _db.setMeta(
      MetaKeys.lastUpdatePrompted,
      _checkedAt!.toIso8601String().substring(0, 10),
    );
  }

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------

  /// Fetch and apply the bulk file.
  ///
  /// Re-compares the ETag first: the badge may be days old and the remote file
  /// may have settled since, and 78 MB is not worth spending on a stale signal.
  Future<void> start() async {
    if (busy) return;
    _phase = UpdatePhase.checking;
    _error = null;
    notifyListeners();

    final remote = await BulkImporter.remoteEtag();
    final current = await _db.metaValue(MetaKeys.bulkEtag) ?? '';

    // A check that cannot reach Scryfall does not stop the import — the import
    // does its own download and will fail on its own terms if the network is
    // genuinely gone. Only a *definite* match stops it.
    if (remote != null && remote.isNotEmpty && remote == current) {
      await _db.setMeta(MetaKeys.pendingEtag, '');
      await _stampChecked();
      _updateAvailable = false;
      _phase = UpdatePhase.upToDate;
      notifyListeners();
      return;
    }

    _phase = UpdatePhase.running;
    _progress = const ImportProgress(ImportStep.checking);
    notifyListeners();

    try {
      // incremental: additive name indexing, so search keeps working while this
      // runs. That is what makes not blocking safe.
      await for (final p in BulkImporter.run(_db, incremental: true)) {
        _progress = p;
        notifyListeners();
        if (p.step == ImportStep.done) break;
      }

      await _db.setMeta(MetaKeys.pendingEtag, '');
      await _stampChecked();
      _updateAvailable = false;
      _phase = UpdatePhase.upToDate;
      _progress = null;
      notifyListeners();
      _outcomes.add(CardDataOutcome.updated);

      // The import is what creates a backlog: whatever printings it just added
      // have no hash. Starting straight away is the point — the user has
      // already opted into fetching card data, and leaving the queue for them
      // to find later would mean a week of scans silently falling back to OCR.
      unawaited(HashQueue.instance.start());
    } catch (e, st) {
      AppLogger.w('CardDataUpdater: update failed', error: e, stackTrace: st);
      // The database is still entirely valid — the import writes by primary key
      // and deletes nothing, so a half-applied update is merely partly newer.
      // Nothing was lost, which is why this reports rather than alarms.
      _error = e;
      _phase = UpdatePhase.failed;
      _progress = null;
      notifyListeners();
      _outcomes.add(CardDataOutcome.failed);
    }
  }

  /// Return to the resting state after the user has read a result.
  void acknowledge() {
    if (busy) return;
    _phase = _updateAvailable ? UpdatePhase.available : UpdatePhase.idle;
    _error = null;
    notifyListeners();
  }
}
