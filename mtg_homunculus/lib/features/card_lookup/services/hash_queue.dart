import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Ids that failed this session, skipped until the next launch.
  ///
  /// Retrying inside one session would spin forever on a permanently
  /// unobtainable image. A non-zero *Not yet hashed* is honest about those:
  /// they genuinely are not hashed.
  final _failed = <String>{};

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
    notifyListeners();

    final client = http.Client();
    try {
      var index = await HashIndex.load();
      if (index == null) {
        AppLogger.i('HashQueue: no index to append to, nothing to do');
        return;
      }

      final pending = await _db.unhashed(index.ids());
      pending.removeWhere((c) => _failed.contains(c.id));
      _remaining = pending.length;
      _counted = true;
      notifyListeners();

      if (pending.isEmpty) {
        AppLogger.i('HashQueue: nothing to hash');
        return;
      }
      AppLogger.i('HashQueue: ${pending.length} to hash');

      final batch = <String, Uint8List>{};

      for (final card in pending) {
        if (!_running) break; // stopped

        final hash = await _hashOne(client, card);
        if (hash == null) {
          _failed.add(card.id);
        } else {
          batch[card.id] = hash;
        }

        _done++;
        _remaining = pending.length - _done;
        notifyListeners();

        if (batch.length >= _appendEvery) {
          index = await HashIndex.append(batch) ?? index;
          batch.clear();
        }
      }

      if (batch.isNotEmpty) await HashIndex.append(batch);

      AppLogger.i('HashQueue: hashed $_done, '
          '${_failed.length} could not be fetched');
    } catch (e, st) {
      AppLogger.w('HashQueue: run failed', error: e, stackTrace: st);
    } finally {
      client.close();
      _running = false;
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

  Future<Uint8List?> _hashOne(http.Client client, Card card) async {
    final url =
        ScryfallCard.imageUrlFor(card.id, card.imageUpdatedAt, size: 'small');
    if (url == null) return null;

    try {
      final res = await client.get(
        Uri.parse(url),
        // Scryfall asks for a naming User-Agent on every request, and the docs
        // warn that ignoring it can get an app banned.
        headers: const {'User-Agent': 'MtgHomunculus/1.0'},
      );
      if (res.statusCode != 200) return null;

      // Off the UI isolate: a decode plus a box average per card, thousands of
      // times over, would otherwise be felt as jank while the user scans.
      return await compute(_decodeAndHash, res.bodyBytes);
    } catch (e) {
      AppLogger.w('HashQueue: ${card.id} failed: $e');
      return null;
    }
  }
}

/// Top-level for [compute]: JPEG bytes → dHash.
Uint8List? _decodeAndHash(Uint8List bytes) {
  final decoded = img.decodeJpg(bytes);
  if (decoded == null) return null;
  final gray = DHash.lumaFromRgb(decoded.getBytes(order: img.ChannelOrder.rgb));
  return DHash.compute(gray, decoded.width, decoded.height);
}
