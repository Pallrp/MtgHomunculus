import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../../core/logging/app_logger.dart';
import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../models/scryfall_card.dart';
import 'dhash.dart';

/// Hashes the printings the shipped index does not cover.
///
/// **One trigger: a missing hash.** Not a changed `image_updated_at` and not an
/// improved `image_status` — replacing a card's art does not change the
/// physical card the hash is compared against, and `DHash` box-averages into 88
/// cells, so source resolution is averaged away by construction. The one
/// genuinely dangerous case, hashing a placeholder, cannot happen:
/// [CardsDatabase.unhashed] filters `image_status >= 2`, and a placeholder that
/// *becomes* real art crosses that filter with no hash at all — which is the
/// missing-hash trigger again. See `local_data_store.md`.
///
/// **`small`, not `normal`.** The desktop build fetches 488 × 680 at ~100 KB a
/// card; the device gets the same 88 cells out of 146 × 204 at ~15 KB. For a
/// 2,000-card backlog that is ~30 MB of someone's data plan instead of ~200.
class HashQueue extends ChangeNotifier {
  HashQueue._();

  /// Never disposed — it outlives every screen, and may keep working while the
  /// user scans. There is no read/write collision to avoid:
  /// [HashIndex.append] returns a *new* index rather than mutating the one the
  /// scanner holds, so a stale in-memory copy costs exactly one frame.
  static final HashQueue instance = HashQueue._();

  /// Roughly what one `small` JPEG costs, for the information line. Measured
  /// loosely and deliberately rounded — the point is the order of magnitude.
  static const bytesPerCard = 15 * 1024;

  /// Appended in batches rather than per card: each [HashIndex.append] rewrites
  /// and reloads the index, so this turns N reloads into N/250.
  static const _appendEvery = 250;

  /// Consecutive transient failures before the queue stops on its own.
  ///
  /// Lifecycle pausing covers the backgrounding case, but not every way the
  /// network can vanish — flight mode, a dead hotspot, Scryfall down. This is
  /// the backstop that does not need to know which.
  static const _giveUpAfter = 10;

  CardsDatabase get _db => CardsDatabase.instance;

  bool _running = false;
  bool get running => _running;

  int _remaining = 0;

  /// How many printings still need a hash, or null before the first count.
  ///
  /// This is the *Not yet hashed* figure on the card data screen.
  int? get remaining => _counted ? _remaining : null;
  bool _counted = false;

  int _done = 0;
  int get done => _done;

  int _hashed = 0;

  /// How many actually got a hash, as opposed to merely being *processed*.
  int get hashed => _hashed;

  /// Ids whose image will never arrive — a 4xx on a printing the table thinks
  /// is hashable. Skipped until the next launch, because retrying a 404 inside
  /// one session spins forever.
  ///
  /// **Only permanent failures go in here.** A dropped connection is not one,
  /// and treating it as one was a real bug: backgrounding the app failed every
  /// request instantly, and because a *failure is fast* where a success takes
  /// half a second, the loop tore through a thousand cards in ten seconds and
  /// marked them all unobtainable.
  final _unobtainable = <String>{};

  /// Paused because the app is not in the foreground.
  ///
  /// Android gives a backgrounded app no usable network, so continuing would
  /// burn the backlog on failures. Nothing is lost by waiting.
  bool _paused = false;
  bool get paused => _paused;

  Completer<void>? _resumeGate;
  AppLifecycleListener? _lifecycle;

  void _watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onPause: () {
        if (!_running || _paused) return;
        _paused = true;
        _resumeGate = Completer<void>();
        AppLogger.i('HashQueue: paused, app backgrounded');
        notifyListeners();
      },
      onResume: () {
        if (!_paused) return;
        _paused = false;
        _resumeGate?.complete();
        _resumeGate = null;
        AppLogger.i('HashQueue: resumed');
        notifyListeners();
      },
    );
  }

  /// Count the backlog without processing it.
  Future<void> count() async {
    try {
      final index = await HashIndex.load();
      if (index == null) {
        _counted = false;
        notifyListeners();
        return;
      }
      final indexed = index.ids();
      final hashable = await _db.hashableIds();
      _remaining = hashable.where((id) => !indexed.contains(id)).length;
      _counted = true;
      notifyListeners();
    } catch (e, st) {
      AppLogger.w('HashQueue: count failed', error: e, stackTrace: st);
    }
  }

  /// Work the backlog to exhaustion.
  ///
  /// Safe to call repeatedly; a second call while running is a no-op.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    _done = 0;
    _hashed = 0;
    _watchLifecycle();
    notifyListeners();

    final client = http.Client();
    try {
      var index = await HashIndex.load();
      if (index == null) {
        AppLogger.i('HashQueue: no index to append to, nothing to do');
        return;
      }

      final pending = await _db.unhashed(index.ids());
      pending.removeWhere((c) => _unobtainable.contains(c.id));
      _remaining = pending.length;
      _counted = true;
      notifyListeners();

      if (pending.isEmpty) {
        AppLogger.i('HashQueue: nothing to hash');
        return;
      }
      AppLogger.i('HashQueue: ${pending.length} to hash');

      final batch = <String, Uint8List>{};
      var consecutiveTransient = 0;

      for (final card in pending) {
        if (!_running) break; // stopped

        // Hold here rather than failing every request while backgrounded.
        if (_resumeGate case final gate?) await gate.future;
        if (!_running) break;

        final outcome = await _hashOne(client, card);

        switch (outcome.kind) {
          case _FetchKind.ok:
            batch[card.id] = outcome.hash!;
            _hashed++;
            consecutiveTransient = 0;
          case _FetchKind.permanent:
            _unobtainable.add(card.id);
            consecutiveTransient = 0;
          case _FetchKind.transient:
            // Left out of `_unobtainable` on purpose: it gets another go on the
            // next run, within this session.
            consecutiveTransient++;
        }

        _done++;
        _remaining = pending.length - _done;
        notifyListeners();

        if (batch.length >= _appendEvery) {
          index = await HashIndex.append(batch) ?? index;
          batch.clear();
        }

        // The backstop, independent of knowing *why* the network went away:
        // if nothing is getting through, stop rather than spending the backlog
        // on failures at memory speed.
        if (consecutiveTransient >= _giveUpAfter) {
          AppLogger.w('HashQueue: $_giveUpAfter failures in a row, stopping');
          _running = false;
          break;
        }
      }

      if (batch.isNotEmpty) await HashIndex.append(batch);

      AppLogger.i('HashQueue: hashed $_hashed of $_done processed, '
          '${_unobtainable.length} unobtainable');
    } catch (e, st) {
      AppLogger.w('HashQueue: run failed', error: e, stackTrace: st);
    } finally {
      client.close();
      _running = false;
      _paused = false;
      _resumeGate?.complete();
      _resumeGate = null;
      notifyListeners();
      // Re-count against the index as it now stands rather than trusting the
      // running tally, which does not know what an append actually wrote.
      await count();
    }
  }

  /// Ask the queue to stop at the next card. It leaves the backlog intact.
  void stop() {
    if (!_running) return;
    _running = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // One card
  // ---------------------------------------------------------------------------

  Future<_Fetch> _hashOne(http.Client client, Card card) async {
    final url =
        ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt, size: 'small');
    if (url == null) return const _Fetch.permanent();

    try {
      final res = await client
          .get(
            Uri.parse(url),
            // Scryfall asks for a naming User-Agent on every request, and the
            // docs warn that ignoring it can get an app banned.
            headers: const {'User-Agent': 'MtgHomunculus/1.0'},
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        // 4xx is about this URL and will not improve; 5xx and the rest are
        // about the server or the connection, and may.
        final permanent = res.statusCode >= 400 && res.statusCode < 500;
        AppLogger.w('HashQueue: ${card.id} HTTP ${res.statusCode}'
            '${permanent ? ' (giving up on it)' : ''}');
        return permanent ? const _Fetch.permanent() : const _Fetch.transient();
      }

      // Off the UI isolate: a decode plus a box average per card, thousands of
      // times over, would otherwise be felt as jank while the user scans.
      final hash = await compute(_decodeAndHash, res.bodyBytes);
      // Bytes arrived and would not decode — that is the image, not the link.
      return hash == null ? const _Fetch.permanent() : _Fetch.ok(hash);
    } catch (e) {
      // Socket errors, DNS failures, timeouts: the connection, not the card.
      AppLogger.w('HashQueue: ${card.id} fetch failed: $e');
      return const _Fetch.transient();
    }
  }
}

enum _FetchKind { ok, permanent, transient }

/// Why a card did or did not get a hash.
///
/// The distinction is the whole fix: a permanent failure may be remembered and
/// skipped, a transient one must not be, or a ten-second network blip burns
/// through the entire backlog.
class _Fetch {
  final _FetchKind kind;
  final Uint8List? hash;

  const _Fetch.ok(this.hash) : kind = _FetchKind.ok;
  const _Fetch.permanent() : kind = _FetchKind.permanent, hash = null;
  const _Fetch.transient() : kind = _FetchKind.transient, hash = null;
}

/// Top-level for [compute]: JPEG bytes → dHash.
Uint8List? _decodeAndHash(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return null;
  final gray = DHash.lumaFromRgb(decoded.getBytes(order: img.ChannelOrder.rgb));
  return DHash.compute(gray, decoded.width, decoded.height);
}
