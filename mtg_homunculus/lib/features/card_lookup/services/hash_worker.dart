import 'dart:async';
import 'dart:io' show File, HttpClient;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:image/image.dart' as img;

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../models/scryfall_card.dart';
import 'dhash.dart';

/// Where the job has got to.
class HashProgress {
  /// Cards that actually gained a fingerprint.
  final int hashed;

  /// Cards the job has been through, hashed or skipped.
  final int done;

  /// How many were in the backlog when the job began.
  final int total;

  /// True once the job has ended, for whatever reason.
  final bool finished;

  const HashProgress({
    required this.hashed,
    required this.done,
    required this.total,
    this.finished = false,
  });

  int get remaining => total - done;

  Map<String, dynamic> toMap() => {
        'hashed': hashed,
        'done': done,
        'total': total,
        'finished': finished,
      };

  static HashProgress? fromMap(Object? data) {
    if (data is! Map) return null;
    final hashed = data['hashed'], done = data['done'], total = data['total'];
    if (hashed is! int || done is! int || total is! int) return null;
    return HashProgress(
      hashed: hashed,
      done: done,
      total: total,
      finished: data['finished'] == true,
    );
  }
}

/// The hash job: fetch, hash and append every printing the index lacks.
///
/// Runs entirely on the foreground service's isolate; progress leaves through
/// a callback. A card that fails is skipped and stays in the backlog, which the
/// next job derives fresh — nothing is tracked. See
/// `.claude/background_processing.md`.
class HashWorker {
  /// Roughly what one `small` JPEG costs, for the information line.
  static const bytesPerCard = 15 * 1024;

  /// `small` (146 × 204): the same 88 cells as `normal` at a seventh the size.
  static const _size = 'small';

  /// Fetches in flight at once. Measured: the job is almost all round trips,
  /// and `*.scryfall.io` has no rate limit.
  static const _concurrency = 8;

  /// One request's budget, connect included.
  static const _deadline = Duration(seconds: 10);

  /// Tries per card before skipping it.
  static const _attempts = 2;

  /// How long a stopped job waits for cards in flight before abandoning them.
  static const _unwindGrace = Duration(seconds: 2);

  final CardsDatabase _db;
  HashWorker({CardsDatabase? db}) : _db = db ?? CardsDatabase.instance;

  bool _stop = false;
  final _stopped = Completer<void>();
  http.Client? _client;

  final _finished = Completer<void>();

  /// Completes when [run] has fully unwound.
  Future<void> get finished => _finished.future;

  /// Take no more cards, and drop every request in flight.
  ///
  /// Closing the client (`force: true`) reaches requests still connecting,
  /// which the abort trigger cannot. Cards already downloaded still append.
  void stop() {
    _stop = true;
    if (!_stopped.isCompleted) _stopped.complete();
    _client?.close();
  }

  /// Appends one at a time: two overlapping open-append-closes could
  /// interleave within a record, which [HashIndex.parse] cannot detect.
  Future<bool> _appendQueue = Future.value(true);

  Future<bool> _append(File at, String id, Uint8List hash) {
    final done =
        _appendQueue.then((_) => HashIndex.appendOnly({id: hash}, at: at));
    _appendQueue = done.catchError((Object _) => false);
    return done;
  }

  /// How many printings still need a hash. Null when there is no index.
  Future<int?> count() async {
    final index = await HashIndex.load();
    if (index == null) return null;
    final indexed = index.ids();
    final hashable = await _db.hashableIds();
    return hashable.where((id) => !indexed.contains(id)).length;
  }

  /// Work the backlog to exhaustion, or until stopped.
  Future<void> run({required void Function(HashProgress) onProgress}) async {
    // Dart's default connect timeout is none at all.
    final client = _client =
        IOClient(HttpClient()..connectionTimeout = _deadline);
    var hashed = 0, done = 0, total = 0;

    void report({bool finished = false}) => onProgress(HashProgress(
          hashed: hashed,
          done: done,
          total: total,
          finished: finished,
        ));

    try {
      // Resolved once: nothing in the per-card loop may wait on a plugin.
      final indexFile = await HashIndex.file();

      if (!await HashIndex.repairTail(at: indexFile)) {
        AppLogger.i('HashWorker: no index to append to');
        return;
      }

      final index = await HashIndex.load();
      if (index == null) {
        AppLogger.i('HashWorker: index did not load');
        return;
      }

      final pending = await _db.unhashed(index.ids());
      total = pending.length;
      report();
      if (pending.isEmpty) {
        AppLogger.i('HashWorker: nothing to hash');
        return;
      }
      AppLogger.i('HashWorker: ${pending.length} to hash');

      var next = 0;

      Future<void> fetcher() async {
        // No lock on `next`: Dart never interrupts code between awaits.
        while (!_stop && next < pending.length) {
          final card = pending[next++];

          final hash = await _hashOne(client, card);
          if (hash != null) {
            if (!await _append(indexFile, card.id, hash)) {
              AppLogger.w('HashWorker: append failed, stopping the job');
              stop();
              return;
            }
            hashed++;
          }

          done++;
          report();
        }
      }

      // After a stop, cards still in flight get [_unwindGrace] and are then
      // abandoned, so a stuck await can never keep the job from finishing.
      final pool =
          Future.wait([for (var i = 0; i < _concurrency; i++) fetcher()]);
      await Future.any([
        pool,
        _stopped.future.then((_) => Future<void>.delayed(_unwindGrace)),
      ]);

      if (_stop) {
        await _appendQueue.timeout(_unwindGrace, onTimeout: () => false);
      } else {
        await _appendQueue;
      }

      final abandoned = next - done;
      if (abandoned > 0) {
        AppLogger.w('HashWorker: abandoned $abandoned card(s) still in flight');
      }
      AppLogger.i('HashWorker: hashed $hashed of $done processed, '
          '$total in the backlog${_stop ? ', stopped' : ''}');
    } catch (e, st) {
      AppLogger.w('HashWorker: run failed', error: e, stackTrace: st);
    } finally {
      client.close();
      _client = null;
      report(finished: true);
      if (!_finished.isCompleted) _finished.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // One card
  // ---------------------------------------------------------------------------

  /// Fetch and hash one card, or null to skip it.
  Future<Uint8List?> _hashOne(http.Client client, Card card) async {
    final url =
        ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt, size: _size);
    if (url == null) return null;

    for (var attempt = 1; attempt <= _attempts; attempt++) {
      if (_stop) return null;

      final bytes = await _fetch(client, Uri.parse(url), card.id, attempt);
      if (bytes == null) continue;

      // Inline, not `compute`: a `small` image decodes in milliseconds, and a
      // spawned isolate per card wedged the job with the screen off.
      try {
        final hash = decodeAndHash(bytes);
        if (hash == null) AppLogger.w('HashWorker: ${card.id} did not decode');
        return hash;
      } catch (e) {
        AppLogger.w('HashWorker: ${card.id} decode threw: $e');
        return null;
      }
    }
    return null;
  }

  /// One request under one deadline, or null on any failure.
  ///
  /// `http` aborts a request only through `send` with an [http.AbortableRequest];
  /// the trigger fires at the deadline or on a stop, and covers the body.
  Future<Uint8List?> _fetch(
    http.Client client,
    Uri uri,
    String id,
    int attempt,
  ) async {
    final trigger = Completer<void>();
    void fire() {
      if (!trigger.isCompleted) trigger.complete();
    }

    final timer = Timer(_deadline, fire);
    unawaited(_stopped.future.then((_) => fire()));

    try {
      final request = http.AbortableRequest('GET', uri,
          abortTrigger: trigger.future)
        // Scryfall asks for a naming User-Agent on every request.
        ..headers['User-Agent'] = 'MtgHomunculus/1.0';

      final res = await http.Response.fromStream(await client.send(request));
      if (res.statusCode != 200) {
        AppLogger.w('HashWorker: $id HTTP ${res.statusCode} (try $attempt)');
        return null;
      }
      return res.bodyBytes;
    } catch (e) {
      if (_stop) return null; // the stop closing the client, not news
      AppLogger.w('HashWorker: $id fetch failed (try $attempt): $e');
      return null;
    } finally {
      timer.cancel();
    }
  }
}

/// JPEG bytes → dHash.
Uint8List? decodeAndHash(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return null;
  final gray = DHash.lumaFromRgb(decoded.getBytes(order: img.ChannelOrder.rgb));
  return DHash.compute(gray, decoded.width, decoded.height);
}
