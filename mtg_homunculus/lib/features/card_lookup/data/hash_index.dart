import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../services/dhash.dart';

/// One candidate from an index scan.
class HashMatch {
  /// Scryfall card id.
  final String id;

  /// Differing bits, 0..[DHash.bitCount]. **A distance, not a probability** —
  /// there is no "87% sure"; there is "12 of 157 bits differ".
  final int distance;

  const HashMatch(this.id, this.distance);

  @override
  String toString() => '$id@$distance';
}

/// The perceptual-hash index: every scannable printing as (card id, dHash).
///
/// Built on a desktop from ~11.5 GB of card images, published as a GitHub release
/// asset, and downloaded once on first run. See `local_data_store.md`.
///
/// Held as **one flat buffer**, not a table. Hamming distance has no index
/// structure a database could exploit — two hashes one bit apart sort at opposite
/// ends — so every match is a full scan either way, and scanning a contiguous
/// 2 MB buffer beats a query that allocates a BLOB per row. Measured 25 ms across
/// 116k records.
class HashIndex {
  HashIndex._(this._bytes, this._count, this._headerLen, this._hashLen);

  /// Always the newest release's asset of that name. Publishing a new release
  /// changes what this serves with no code change — but **every release must
  /// carry the file**, since this does not fall back to an older one.
  static const downloadUrl =
      'https://github.com/Pallrp/MtgHomunculus/releases/latest/download/hash_index.bin';

  static const _magic = 'MTGHASH1';
  static const _idBytes = 16;

  /// Match threshold, **calibrated against 44 real captures on 2026-08-25**.
  ///
  /// ```
  /// best distance   min 10 · median 16 · max 20      44 passes, 26 matched
  /// candidates      min  1 · median  2 · max  7
  /// ```
  ///
  /// Two things that measurement settled, both contrary to what synthetic
  /// degradation of reference art predicted (0-1.4 for a clean capture):
  ///
  /// **There is a floor of ~10 that every capture pays.** Not one landed below
  /// it. Intermittent framing error cannot produce a floor — it would give a
  /// bimodal spread with clean captures near zero. Something systematic costs
  /// ~10 bits on every frame; an illumination gradient across the card is the
  /// leading hypothesis and is untested. Note `dhash_test` proves invariance to
  /// **uniform** brightness scaling only, which says nothing about a ramp.
  ///
  /// **Raising this is the wrong lever.** At 20 the median is already 2
  /// candidates and the max is 7; loosening trades missed matches for constant
  /// Choose Version prompts. Five of the 26 hits sat exactly at 20, so the
  /// distribution is censored here — some misses are matches just outside.
  ///
  /// Left as-is deliberately. Recall is ~59% but **precision was 100%** across
  /// the sample, and combined with the OCR path that identifies a card inside
  /// two frames. A scanner that occasionally waits half a second is fine; one
  /// that confidently adds the wrong card is not.
  static const matchThreshold = 20;

  final Uint8List _bytes;
  final int _count;
  final int _headerLen;
  final int _hashLen;

  int get count => _count;
  int get recordLength => _idBytes + _hashLen;

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'hash_index.bin'));
  }

  /// Read the index from app storage, or null if it is absent or unusable.
  ///
  /// Returning null is not an error state — matching simply falls through to the
  /// OCR path until an index is present.
  static Future<HashIndex?> load() async {
    try {
      final f = await file();
      if (!await f.exists()) return null;
      return parse(await f.readAsBytes());
    } catch (e, st) {
      AppLogger.w('HashIndex: load failed', error: e, stackTrace: st);
      return null;
    }
  }

  /// Parse a raw index. Null when the bytes are not a usable index.
  ///
  /// **The record count comes from the file length, not the header.** A killed
  /// append leaves a length that is not `header + n * recordLength`, which is
  /// detectable; trusting a stale header would silently truncate or overrun.
  static HashIndex? parse(Uint8List bytes) {
    if (bytes.length < _magic.length + 6) return null;

    var o = 0;
    if (ascii.decode(bytes.sublist(0, _magic.length), allowInvalid: true) !=
        _magic) {
      AppLogger.w('HashIndex: bad magic');
      return null;
    }
    o = _magic.length;

    final vLen = bytes[o++];
    if (o + vLen + 5 > bytes.length) return null;
    final version = utf8.decode(bytes.sublist(o, o + vLen), allowMalformed: true);
    o += vLen;

    // Header count is read past but deliberately unused; see above.
    o += 4;
    final hashLen = bytes[o++];

    if (version != DHash.version) {
      // Not an error to recover from: a different grid produces different hashes
      // with no error at all, only matches that never happen. Refuse it loudly.
      AppLogger.w('HashIndex: version mismatch — file is "$version", '
          'this build expects "${DHash.version}". Refusing to load.');
      return null;
    }
    if (hashLen != DHash.byteLength) {
      AppLogger.w('HashIndex: hash length $hashLen, expected ${DHash.byteLength}');
      return null;
    }

    final recordLen = _idBytes + hashLen;
    final body = bytes.length - o;
    final count = body ~/ recordLen;
    if (body % recordLen != 0) {
      AppLogger.w('HashIndex: $body trailing bytes is not a whole number of '
          '$recordLen-byte records — truncated append? Using $count.');
    }
    return HashIndex._(bytes, count, o, hashLen);
  }

  /// Download the index to app storage, replacing any existing copy.
  ///
  /// Writes to a `.part` file first so an interrupted download cannot leave a
  /// truncated index that would then parse as a shorter one.
  static Future<bool> download({void Function(int bytes, int total)? onProgress}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'MtgHomunculus/1.0');
      req.followRedirects = true;
      final res = await req.close();
      if (res.statusCode != 200) {
        AppLogger.w('HashIndex: download failed, HTTP ${res.statusCode}');
        return false;
      }

      final dst = await file();
      final part = File('${dst.path}.part');
      final sink = part.openWrite();
      var got = 0;
      final total = res.contentLength;
      await res.forEach((chunk) {
        sink.add(chunk);
        got += chunk.length;
        onProgress?.call(got, total > 0 ? total : 0);
      });
      await sink.close();

      // Refuse to install something that will not parse.
      if (parse(await part.readAsBytes()) == null) {
        await part.delete();
        AppLogger.w('HashIndex: downloaded file did not parse; discarded');
        return false;
      }
      if (await dst.exists()) await dst.delete();
      await part.rename(dst.path);
      return true;
    } catch (e, st) {
      AppLogger.w('HashIndex: download failed', error: e, stackTrace: st);
      return false;
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  /// Every card within [threshold] bits of [hash], nearest first.
  ///
  /// Several results is the normal, expected case rather than a failure:
  /// reprints with identical art hash identically, so the picker resolves it.
  /// Measured on the full index, ~9% of cards have a hash-identical twin.
  List<HashMatch> nearest(
    Uint8List hash, {
    int threshold = matchThreshold,
    int limit = 12,
  }) {
    if (hash.length != _hashLen) return const [];

    final hits = <HashMatch>[];
    final recordLen = _idBytes + _hashLen;

    for (var r = 0; r < _count; r++) {
      final base = _headerLen + r * recordLen + _idBytes;
      var d = 0;
      for (var b = 0; b < _hashLen; b++) {
        var x = _bytes[base + b] ^ hash[b];
        while (x != 0) {
          x &= x - 1; // clear the lowest set bit
          d++;
        }
        // Bail as soon as this record cannot qualify — most do not.
        if (d > threshold) break;
      }
      if (d <= threshold) {
        hits.add(HashMatch(_uuidAt(_headerLen + r * recordLen), d));
      }
    }

    hits.sort((a, b) => a.distance.compareTo(b.distance));
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// Every card id in the index. Transient by design — used to diff against the
  /// card table, then discarded rather than held resident.
  Set<String> ids() {
    final recordLen = _idBytes + _hashLen;
    return {
      for (var r = 0; r < _count; r++) _uuidAt(_headerLen + r * recordLen),
    };
  }

  String _uuidAt(int off) {
    final b = StringBuffer();
    for (var i = 0; i < _idBytes; i++) {
      b.write(_bytes[off + i].toRadixString(16).padLeft(2, '0'));
      if (i == 3 || i == 5 || i == 7 || i == 9) b.write('-');
    }
    return b.toString();
  }

  // ---------------------------------------------------------------------------
  // Growth
  // ---------------------------------------------------------------------------

  /// Append hashes computed on-device, and return the reloaded index.
  ///
  /// Appends rather than rewrites: the file only ever grows by
  /// `recordLength` bytes per card, and a partial write is detectable from the
  /// length. The header's count is left stale on purpose — nothing reads it.
  static Future<HashIndex?> append(Map<String, Uint8List> entries) async {
    if (entries.isEmpty) return load();
    try {
      final f = await file();
      if (!await f.exists()) return null;

      final buf = BytesBuilder(copy: false);
      for (final e in entries.entries) {
        if (e.value.length != DHash.byteLength) continue;
        buf.add(_uuidBytes(e.key));
        buf.add(e.value);
      }
      await f.writeAsBytes(buf.takeBytes(), mode: FileMode.append, flush: true);
      return load();
    } catch (e, st) {
      AppLogger.w('HashIndex: append failed', error: e, stackTrace: st);
      return null;
    }
  }

  static Uint8List _uuidBytes(String id) {
    final hex = id.replaceAll('-', '');
    final out = Uint8List(_idBytes);
    for (var i = 0; i < _idBytes; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
