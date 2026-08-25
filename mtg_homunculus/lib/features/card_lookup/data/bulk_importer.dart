import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/logging/app_logger.dart';
import 'cards_database.dart';

/// Which stage of the setup the user is looking at.
enum ImportStep { checking, downloading, inserting, indexing, done }

/// Progress for the setup screen.
///
/// [count] is a real tally to show as a number — bytes downloaded, cards
/// inserted. [fraction] drives the bar, and is null when a step genuinely has no
/// denominator, in which case that step alone shows indeterminate.
///
/// These are deliberately separate. The bulk file's card count is not published,
/// and counting the lines first is not available to us: the parse is streamed
/// straight off the network, so a counting pass would mean downloading 74 MB
/// twice or writing 595 MB to disk. Both numbers here are therefore *measured*
/// rather than one being an estimate dressed up as a total.
class ImportProgress {
  final ImportStep step;
  final int count;
  final double? fraction;
  const ImportProgress(this.step, {this.count = 0, this.fraction});

  @override
  String toString() =>
      '$step $count${fraction == null ? '' : ' ${(fraction! * 100).round()}%'}';
}

/// Imports Scryfall's `default_cards` bulk file into [CardsDatabase].
///
/// Parsing 595 MB of JSONL is far too slow to do on the UI isolate, so the
/// download, decompress, parse and field extraction all happen in a spawned
/// isolate which streams **batches** of extracted rows back. Sending one message
/// per card would cost more than the parsing; batching makes it negligible.
///
/// The SQL side is already off the UI isolate — [CardsDatabase] opens with
/// `NativeDatabase.createInBackground`.
class BulkImporter {
  BulkImporter._();

  /// Cards per message from the parse isolate, and per insert transaction.
  static const _batchSize = 2000;

  /// Field extraction, exposed for testing.
  ///
  /// This is where a bulk import goes silently wrong: a mis-mapped rarity enum or
  /// finishes bitmask corrupts 116k rows without erroring, and nothing downstream
  /// would notice.
  @visibleForTesting
  static CardsCompanion? extractForTest(String line, Map<String, CardSet> sets) =>
      _extract(line, sets);

  /// Run a full import, emitting progress as it goes.
  ///
  /// Does **not** decide whether an import is needed — see [remoteEtag].
  static Stream<ImportProgress> run(CardsDatabase db) async* {
    final controller = StreamController<ImportProgress>();
    final receive = ReceivePort();
    Isolate? isolate;

    // Bridge the isolate's messages onto the progress stream, doing the inserts
    // as batches arrive.
    var inserted = 0;
    final seenSets = <String>{};

    unawaited(() async {
      try {
        isolate = await Isolate.spawn(_parseEntry, receive.sendPort);

        await for (final msg in receive) {
          if (msg is _Failed) {
            controller.addError(msg.error);
            break;
          }
          if (msg is _Downloading) {
            controller.add(ImportProgress(
              ImportStep.downloading,
              count: msg.bytes,
              fraction: msg.total > 0 ? msg.bytes / msg.total : null,
            ));
            continue;
          }
          if (msg is _Batch) {
            // Sets first: cards.set_code is a foreign key, and the stream can
            // reach a card before anything else has mentioned its set.
            final newSets =
                msg.sets.where((s) => seenSets.add(s.code)).toList();
            if (newSets.isNotEmpty) {
              await db.batch((b) => b.insertAll(db.sets, newSets,
                  mode: InsertMode.insertOrIgnore));
            }

            await db.batch((b) => b.insertAll(db.cards, msg.cards,
                mode: InsertMode.insertOrReplace));

            inserted += msg.cards.length;
            controller.add(ImportProgress(
              ImportStep.inserting,
              count: inserted,
              fraction: msg.totalBytes > 0
                  ? (msg.bytes / msg.totalBytes).clamp(0.0, 1.0)
                  : null,
            ));
            continue;
          }
          if (msg is _Done) {
            controller.add(const ImportProgress(ImportStep.indexing));
            await db.rebuildNameIndex();

            await db.setMeta(MetaKeys.bulkCardCount, '$inserted');
            await db.setMeta(MetaKeys.bulkEtag, msg.etag ?? '');
            await db.setMeta(MetaKeys.bulkUpdatedAt, msg.updatedAt ?? '');
            await db.setMeta(MetaKeys.bulkImportedAt,
                DateTime.now().toIso8601String().substring(0, 10));

            controller.add(const ImportProgress(ImportStep.done));
            break;
          }
        }
      } catch (e, st) {
        AppLogger.w('BulkImporter failed', error: e, stackTrace: st);
        controller.addError(e);
      } finally {
        receive.close();
        isolate?.kill(priority: Isolate.immediate);
        await controller.close();
      }
    }());

    yield* controller.stream;
  }

  /// Current ETag for the bulk file, or null if it cannot be read.
  ///
  /// This — not a date — decides whether to re-download. Compare against
  /// [MetaKeys.bulkEtag].
  ///
  /// The ETag lives on the **download response header**, not in the `/bulk-data`
  /// metadata: that JSON carries `updated_at` and `compressed_size` and no hash
  /// at all. A HEAD against the file gets it without transferring 74 MB.
  static Future<String?> remoteEtag() async {
    final client = HttpClient();
    try {
      final meta = await _bulkMeta(client);
      if (meta == null) return null;
      final req = await client.headUrl(meta.uri);
      _headers(req);
      final res = await req.close();
      await res.drain<void>();
      return res.headers.value(HttpHeaders.etagHeader);
    } catch (e) {
      AppLogger.w('BulkImporter: etag check failed: $e');
      return null;
    } finally {
      client.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate side
// ---------------------------------------------------------------------------

class _Downloading {
  final int bytes, total;
  const _Downloading(this.bytes, this.total);
}

class _Batch {
  final List<CardsCompanion> cards;
  final List<CardSet> sets;

  /// Compressed bytes consumed so far, against the published total. Exact, and
  /// a faithful proxy for parse progress: the stream applies backpressure, so
  /// bytes only arrive as fast as the parser eats them.
  final int bytes, totalBytes;
  const _Batch(this.cards, this.sets, this.bytes, this.totalBytes);
}

class _Done {
  final String? etag, updatedAt;
  const _Done(this.etag, this.updatedAt);
}

class _Failed {
  final Object error;
  const _Failed(this.error);
}

class _BulkMeta {
  final Uri uri;
  final String? updatedAt;
  final int compressedSize;
  const _BulkMeta(this.uri, this.updatedAt, this.compressedSize);
}

const _userAgent = 'MtgHomunculus/1.0';

/// Scryfall answers a request without an explicit `Accept` header with HTTP 400
/// rather than a default representation.
void _headers(HttpClientRequest req) {
  req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
  req.headers.set(HttpHeaders.acceptHeader, 'application/json');
}

Future<_BulkMeta?> _bulkMeta(HttpClient client) async {
  final req = await client.getUrl(Uri.https('api.scryfall.com', '/bulk-data'));
  _headers(req);
  final res = await req.close();
  if (res.statusCode != 200) return null;

  final json =
      jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  final entry = (json['data'] as List?)
      ?.cast<Map<String, dynamic>>()
      .where((e) => e['type'] == 'default_cards')
      .firstOrNull;
  if (entry == null) return null;

  // Scryfall serves JSONL now; `download_uri` is the older wrapped-array field.
  final uri = (entry['jsonl_download_uri'] ?? entry['download_uri']) as String?;
  if (uri == null) return null;

  return _BulkMeta(
    Uri.parse(uri),
    entry['updated_at'] as String?,
    ((entry['compressed_size'] ?? entry['size']) as num?)?.toInt() ?? 0,
  );
}

Future<void> _parseEntry(SendPort send) async {
  final client = HttpClient();
  try {
    final meta = await _bulkMeta(client);
    if (meta == null) {
      send.send(const _Failed('could not read Scryfall bulk-data metadata'));
      return;
    }

    final req = await client.getUrl(meta.uri);
    _headers(req);
    final res = await req.close();
    if (res.statusCode != 200) {
      send.send(_Failed('bulk download failed: HTTP ${res.statusCode}'));
      return;
    }

    // The file arrives as a gzip *file*, not with `Content-Encoding: gzip`, so
    // HttpClient.autoUncompress never fires. Decompress explicitly, streaming --
    // 595 MB must never be held in memory or written to disk on a phone.
    var downloaded = 0;
    final counted = res.map((chunk) {
      downloaded += chunk.length;
      send.send(_Downloading(downloaded, meta.compressedSize));
      return chunk;
    });

    final cards = <CardsCompanion>[];
    final sets = <String, CardSet>{};

    await for (final line in counted
        .transform(gzip.decoder)
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final row = _extract(line, sets);
      if (row == null) continue;
      cards.add(row);

      if (cards.length >= BulkImporter._batchSize) {
        send.send(_Batch(List.of(cards), List.of(sets.values), downloaded,
            meta.compressedSize));
        cards.clear();
        sets.clear();
      }
    }
    if (cards.isNotEmpty) {
      send.send(_Batch(
          List.of(cards), List.of(sets.values), downloaded, meta.compressedSize));
    }

    send.send(_Done(
      res.headers.value(HttpHeaders.etagHeader),
      meta.updatedAt,
    ));
  } catch (e) {
    send.send(_Failed(e));
  } finally {
    client.close();
  }
}

/// Pull the ~20 fields worth keeping out of one JSONL line.
///
/// Returns null for lines that are not a card worth storing. Sets encountered
/// are accumulated into [sets] — they are derived from the card stream rather
/// than fetched separately, since every card carries its set's code, name and
/// type.
CardsCompanion? _extract(String line, Map<String, CardSet> sets) {
  if (line.length < 2 || line.codeUnitAt(0) != 0x7B) return null;

  Map<String, dynamic> c;
  try {
    c = jsonDecode(line) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }

  // Digital-only printings have no physical card to scan.
  if (c['digital'] == true) return null;

  final id = c['id'] as String?;
  final name = c['name'] as String?;
  final setCode = c['set'] as String?;
  final oracleId = c['oracle_id'] as String?;
  final collector = c['collector_number'] as String?;
  if (id == null ||
      name == null ||
      setCode == null ||
      oracleId == null ||
      collector == null) {
    return null;
  }

  sets.putIfAbsent(
    setCode,
    () => CardSet(
      code: setCode,
      name: c['set_name'] as String? ?? setCode,
      releasedAt: _unixDate(c['released_at']),
      setType: c['set_type'] as String?,
    ),
  );

  final faces = c['card_faces'] as List?;

  return CardsCompanion.insert(
    id: id,
    oracleId: oracleId,
    illustrationId: Value(c['illustration_id'] as String?),
    name: name,
    setCode: setCode,
    collectorNumber: collector,
    lang: Value(c['lang'] as String? ?? 'en'),
    rarity: Value(_rarity(c['rarity'] as String?)),
    releasedAt: Value(_unixDate(c['released_at'])),
    cmc: Value((c['cmc'] as num?)?.toDouble()),
    colors: Value(_colors(c['colors'])),
    colorIdentity: Value(_colors(c['color_identity'])),
    watermark: Value(c['watermark'] as String?),
    layout: Value(c['layout'] as String?),
    fullArt: Value(c['full_art'] == true),
    hasBack: Value(faces != null && faces.length > 1),
    imageUpdatedAt: Value(_unixDate(c['image_updated_at'])),
    imageStatus: Value(_imageStatus(c['image_status'] as String?)),
    finishes: Value(_finishes(c['finishes'])),
  );
}

/// `['B','R']` → `'BR'`. Empty string for colourless, which is meaningfully
/// different from null (unknown).
String? _colors(Object? v) =>
    v is List ? v.cast<String>().join() : null;

int? _rarity(String? r) => switch (r) {
      'common' => 0,
      'uncommon' => 1,
      'rare' => 2,
      'mythic' => 3,
      'special' => 4,
      'bonus' => 5,
      _ => null,
    };

int _imageStatus(String? s) => switch (s) {
      'placeholder' => 1,
      'lowres' => 2,
      'highres_scan' => 3,
      _ => 0, // missing
    };

/// `['nonfoil','foil']` → `3`. One integer instead of ~25 bytes of JSON, and it
/// makes "does this come in foil?" a single bitwise AND.
int _finishes(Object? v) {
  if (v is! List) return 0;
  var mask = 0;
  for (final f in v) {
    mask |= switch (f) {
      'nonfoil' => 1,
      'foil' => 2,
      'etched' => 4,
      _ => 0,
    };
  }
  return mask;
}

/// `'2017-09-29'` or a full timestamp → unix seconds.
int? _unixDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : d.millisecondsSinceEpoch ~/ 1000;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
