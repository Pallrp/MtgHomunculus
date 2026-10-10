import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../models/scryfall_card.dart';
import 'dhash.dart';

/// Where the queue has got to.
class HashProgress {
  /// Cards that actually gained a fingerprint.
  final int hashed;

  /// Cards the loop has been through, hashed or not. A failed fetch moves this
  /// without moving [hashed], which is why both exist.
  final int done;

  /// How many were pending when the run began.
  final int total;

  /// True once the loop has stopped, for whatever reason.
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

/// Fetches and hashes the printings the shipped index does not cover.
///
/// **Isolate-agnostic on purpose.** This is the body of the work, with no
/// `ChangeNotifier`, no lifecycle hooks and no notification: it runs inside the
/// foreground service's isolate, which has no widget tree to talk to. Progress
/// leaves through a callback and the caller decides what to do with it.
///
/// **One trigger: a missing hash.** Not a changed `image_updated_at` and not an
/// improved `image_status` — replacing a card's art does not change the
/// physical card the hash is compared against, and [DHash] box-averages into 88
/// cells, so source resolution is averaged away by construction. Hashing a
/// placeholder, the one genuinely dangerous case, cannot happen:
/// [CardsDatabase.unhashed] filters `image_status >= 2`, and a placeholder that
/// *becomes* real art crosses that filter with no hash — the missing-hash
/// trigger again.
class HashWorker {
  /// Roughly what one `small` JPEG costs. Loose and deliberately rounded; the
  /// point is the order of magnitude for the information line.
  static const bytesPerCard = 15 * 1024;

  /// `small` (146 × 204), not the `normal` the desktop build uses: the same 88
  /// cells out of ~15 KB instead of ~100 KB. For a 2,000-card backlog that is
  /// ~30 MB of someone's data plan rather than ~200.
  static const _size = 'small';

  /// Fetches in flight at once.
  ///
  /// `*.scryfall.io` has **no rate limit**, and sequential fetching measured
  /// 2 cards/second on device — almost all of it waiting on round trips. Eight
  /// is enough to hide that latency without becoming a thundering herd.
  static const _concurrency = 8;

  /// Hashes written to the index per append.
  ///
  /// **Small on purpose.** Interruption is the normal case here — the user
  /// presses Stop, Android dozes, the screen goes off — and anything still
  /// sitting in the batch when that happens is thrown away. It was 250, and an
  /// interrupted pass duly discarded 124 cards of finished network and CPU
  /// work. Ten bounds the loss to something not worth noticing, and
  /// [HashIndex.appendOnly] makes the write cheap enough to do that often.
  static const _appendEvery = 10;

  /// Consecutive transient failures before giving up.
  ///
  /// The network can vanish in ways no lifecycle hook reports — flight mode, a
  /// dead hotspot, Scryfall down. This is the backstop that does not need to
  /// know which.
  static const _giveUpAfter = 24;

  final CardsDatabase _db;
  HashWorker({CardsDatabase? db}) : _db = db ?? CardsDatabase.instance;

  bool _stop = false;
  void stop() => _stop = true;

  /// Serialises appends.
  ///
  /// Eight workers share the batch, so two of them can be awaiting a write at
  /// once. Each append is a separate open-append-close, and two overlapping
  /// ones could interleave *within* a record — which `HashIndex.parse` cannot
  /// detect, because the file length would still be a whole number of records.
  /// It would simply hold a garbage hash. A chained future is enough: writes
  /// are rare and tiny next to the fetches.
  Future<void> _appendQueue = Future<void>.value();

  Future<void> _appendSerialised(Map<String, Uint8List> entries) {
    final done = _appendQueue.then((_) => HashIndex.appendOnly(entries));
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

  /// Work the backlog to exhaustion, reporting as it goes.
  Future<void> run({required void Function(HashProgress) onProgress}) async {
    final client = http.Client();
    var hashed = 0, done = 0, total = 0;

    void report({bool finished = false}) => onProgress(HashProgress(
          hashed: hashed,
          done: done,
          total: total,
          finished: finished,
        ));

    try {
      // Read once, for the backlog. Nothing after this needs the index in
      // memory, which is why appending never reloads it.
      final index = await HashIndex.load();
      if (index == null) {
        AppLogger.i('HashWorker: no index to append to');
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

      final batch = <String, Uint8List>{};
      var consecutiveTransient = 0;
      var next = 0;

      // A fixed pool rather than one future per card: 2,000 simultaneous
      // requests would be a thundering herd, and the sockets would fail in
      // ways indistinguishable from the network being gone.
      Future<void> worker() async {
        while (true) {
          if (_stop || consecutiveTransient >= _giveUpAfter) return;
          if (next >= pending.length) return;
          final card = pending[next++];

          final outcome = await _fetchOne(client, card);
          switch (outcome.kind) {
            case _FetchKind.ok:
              batch[card.id] = outcome.hash!;
              hashed++;
              consecutiveTransient = 0;
            case _FetchKind.permanent:
              consecutiveTransient = 0;
            case _FetchKind.transient:
              consecutiveTransient++;
          }

          done++;
          report();

          if (batch.length >= _appendEvery) {
            final snapshot = Map<String, Uint8List>.from(batch);
            batch.clear();
            await _appendSerialised(snapshot);
          }
        }
      }

      await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);

      if (batch.isNotEmpty) await _appendSerialised(batch);
      // And let any still-chained write land before reporting finished.
      await _appendQueue;

      if (consecutiveTransient >= _giveUpAfter) {
        AppLogger.w('HashWorker: $_giveUpAfter failures in a row, stopped');
      }
      AppLogger.i('HashWorker: hashed $hashed of $done processed');
    } catch (e, st) {
      AppLogger.w('HashWorker: run failed', error: e, stackTrace: st);
    } finally {
      client.close();
      report(finished: true);
    }
  }

  // ---------------------------------------------------------------------------
  // One card
  // ---------------------------------------------------------------------------

  Future<_Fetch> _fetchOne(http.Client client, Card card) async {
    final url =
        ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt, size: _size);
    if (url == null) return const _Fetch.permanent();

    try {
      final res = await client
          .get(
            Uri.parse(url),
            // Scryfall asks for a naming User-Agent on every request, and the
            // docs warn that ignoring it can get an app banned.
            headers: const {'User-Agent': 'MtgHomunculus/1.0'},
          )
          // Short, because a stop can only take effect once the in-flight
          // fetches drain, and 15 KB has no business taking longer.
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        // 4xx is about this URL and will not improve; 5xx and the rest are
        // about the server or the connection, and may.
        final permanent = res.statusCode >= 400 && res.statusCode < 500;
        AppLogger.w('HashWorker: ${card.id} HTTP ${res.statusCode}');
        return permanent ? const _Fetch.permanent() : const _Fetch.transient();
      }

      // Off this isolate as well: a decode plus a box average, thousands of
      // times over, would otherwise block the loop that is driving the fetches.
      final hash = await compute(decodeAndHash, res.bodyBytes);
      // Bytes arrived and would not decode — that is the image, not the link.
      return hash == null ? const _Fetch.permanent() : _Fetch.ok(hash);
    } catch (e) {
      // Socket errors, DNS failures, timeouts: the connection, not the card.
      AppLogger.w('HashWorker: ${card.id} fetch failed: $e');
      return const _Fetch.transient();
    }
  }
}

enum _FetchKind { ok, permanent, transient }

/// Why a card did or did not get a hash.
///
/// The distinction matters: a dropped connection must not be recorded the way a
/// 404 is, or a ten-second network blip writes off the whole backlog — which is
/// exactly what happened before this split existed.
class _Fetch {
  final _FetchKind kind;
  final Uint8List? hash;

  const _Fetch.ok(this.hash) : kind = _FetchKind.ok;
  const _Fetch.permanent()
      : kind = _FetchKind.permanent,
        hash = null;
  const _Fetch.transient()
      : kind = _FetchKind.transient,
        hash = null;
}

/// Top-level for [compute]: JPEG bytes → dHash.
@pragma('vm:entry-point')
Uint8List? decodeAndHash(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return null;
  final gray = DHash.lumaFromRgb(decoded.getBytes(order: img.ChannelOrder.rgb));
  return DHash.compute(gray, decoded.width, decoded.height);
}
