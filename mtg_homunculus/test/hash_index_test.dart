import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/data/hash_index.dart';
import 'package:mtg_homunculus/features/card_lookup/services/dhash.dart';

/// Build an index exactly as `tool/build_hash_index.dart` writes one.
Uint8List buildIndex(
  List<(String id, Uint8List hash)> records, {
  String magic = 'MTGHASH1',
  String? version,
  int? headerCount,
  int hashLen = 20,
}) {
  final v = utf8.encode(version ?? DHash.version);
  final b = BytesBuilder(copy: false)
    ..add(ascii.encode(magic))
    ..addByte(v.length)
    ..add(v)
    ..add(Uint8List(4)
      ..buffer
          .asByteData()
          .setUint32(0, headerCount ?? records.length, Endian.little))
    ..addByte(hashLen);
  for (final (id, hash) in records) {
    final hex = id.replaceAll('-', '');
    for (var i = 0; i < 16; i++) {
      b.addByte(int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
    }
    b.add(hash);
  }
  return b.takeBytes();
}

String uuid(int n) {
  final h = n.toRadixString(16).padLeft(32, '0');
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

/// A hash that differs from all-zeros in exactly [bits] positions.
Uint8List hashWithBits(int bits) {
  final h = Uint8List(DHash.byteLength);
  for (var i = 0; i < bits; i++) {
    h[i >> 3] |= 0x80 >> (i & 7);
  }
  return h;
}

void main() {
  final zero = Uint8List(DHash.byteLength);

  group('parse', () {
    test('reads a well-formed index', () {
      final idx = HashIndex.parse(buildIndex([
        (uuid(1), zero),
        (uuid(2), hashWithBits(4)),
      ]))!;
      expect(idx.count, 2);
      expect(idx.recordLength, 16 + DHash.byteLength);
    });

    test('rejects a wrong magic', () {
      expect(HashIndex.parse(buildIndex([(uuid(1), zero)], magic: 'NOTINDEX')),
          isNull);
    });

    test('refuses a version mismatch rather than matching nothing silently', () {
      // A different grid produces different hashes with NO error — only matches
      // that never happen. Loading it would look like the scanner is broken.
      expect(
        HashIndex.parse(buildIndex([(uuid(1), zero)], version: 'dhash-16x8-h-v9')),
        isNull,
      );
    });

    test('rejects a hash length this build cannot read', () {
      expect(HashIndex.parse(buildIndex([], hashLen: 8)), isNull);
    });

    test('too short to hold a header is null, not a crash', () {
      expect(HashIndex.parse(Uint8List(4)), isNull);
      expect(HashIndex.parse(Uint8List(0)), isNull);
    });

    test('an index with no records parses as empty', () {
      final idx = HashIndex.parse(buildIndex([]))!;
      expect(idx.count, 0);
      expect(idx.nearest(zero), isEmpty);
    });
  });

  group('count comes from length, not the header', () {
    test('a stale header count is ignored', () {
      // Appending leaves the header's count behind on purpose.
      final idx = HashIndex.parse(buildIndex(
        [(uuid(1), zero), (uuid(2), zero), (uuid(3), zero)],
        headerCount: 1, // as if written before two appends
      ))!;
      expect(idx.count, 3, reason: 'length is the truth, the header is stale');
    });

    test('a truncated append is floored, not overrun', () {
      final full = buildIndex([(uuid(1), zero), (uuid(2), zero)]);
      // Kill the write halfway through the second record.
      final cut = Uint8List.sublistView(full, 0, full.length - 10);
      final idx = HashIndex.parse(cut)!;
      expect(idx.count, 1, reason: 'the half-written record must be dropped');
      expect(idx.nearest(zero).single.id, uuid(1));
    });
  });

  group('nearest', () {
    late HashIndex idx;
    setUp(() {
      idx = HashIndex.parse(buildIndex([
        (uuid(1), zero), // distance 0
        (uuid(2), hashWithBits(3)), // 3
        (uuid(3), hashWithBits(18)), // 18
        (uuid(4), hashWithBits(60)), // 60
      ]))!;
    });

    test('an exact hash matches at distance 0', () {
      final hits = idx.nearest(zero, threshold: 0);
      expect(hits.single.id, uuid(1));
      expect(hits.single.distance, 0);
    });

    test('results are ordered nearest first', () {
      final hits = idx.nearest(zero, threshold: 20);
      expect(hits.map((h) => h.id), [uuid(1), uuid(2), uuid(3)]);
      expect(hits.map((h) => h.distance), [0, 3, 18]);
    });

    test('the threshold excludes, it does not merely rank', () {
      expect(idx.nearest(zero, threshold: 5).map((h) => h.id),
          [uuid(1), uuid(2)]);
      expect(idx.nearest(zero, threshold: 2).single.id, uuid(1));
    });

    test('several results is normal, not a failure', () {
      // Reprints with identical art hash identically — ~9% of the real index.
      final dupes = HashIndex.parse(buildIndex([
        (uuid(10), zero),
        (uuid(11), zero),
        (uuid(12), zero),
      ]))!;
      expect(dupes.nearest(zero, threshold: 0), hasLength(3));
    });

    test('limit truncates after ordering, keeping the nearest', () {
      final hits = idx.nearest(zero, threshold: 60, limit: 2);
      expect(hits.map((h) => h.distance), [0, 3]);
    });

    test('a wrong-sized hash returns nothing rather than garbage', () {
      expect(idx.nearest(Uint8List(4)), isEmpty);
    });
  });

  group('the real index', () {
    // assets/hash_index.bin is a build artifact and gitignored, so this skips on
    // a fresh clone rather than failing. When present it is the only test that
    // exercises the loader against what actually ships.
    final f = File('assets/hash_index.bin');
    test('parses, and a stored hash finds itself at distance 0', () {
      final bytes = f.readAsBytesSync();
      final idx = HashIndex.parse(bytes)!;
      expect(idx.count, greaterThan(100000));

      // Lift a hash straight out of the file and look it up.
      final headerLen = bytes.length - idx.count * idx.recordLength;
      final at = headerLen + 5000 * idx.recordLength;
      final hash = Uint8List.sublistView(
          bytes, at + 16, at + 16 + DHash.byteLength);

      final exact = idx.nearest(hash, threshold: 0);
      expect(exact, isNotEmpty);
      expect(exact.first.distance, 0);
    });

    test('survives nine flipped bits and still ranks the same card first', () {
      final bytes = f.readAsBytesSync();
      final idx = HashIndex.parse(bytes)!;
      final headerLen = bytes.length - idx.count * idx.recordLength;
      final at = headerLen + 5000 * idx.recordLength;
      final hash = Uint8List.sublistView(
          bytes, at + 16, at + 16 + DHash.byteLength);

      final truth = idx.nearest(hash, threshold: 0).first.id;
      final noisy = Uint8List.fromList(hash);
      for (var i = 0; i < 9; i++) {
        noisy[i] ^= 1 << (i % 8);
      }

      final near = idx.nearest(noisy, threshold: 20);
      expect(near, isNotEmpty);
      expect(near.first.id, truth);
    });
  }, skip: File('assets/hash_index.bin').existsSync()
      ? false
      : 'assets/hash_index.bin not built');

  group('ids', () {
    test('round-trip the uuid encoding', () {
      final idx = HashIndex.parse(buildIndex([
        (uuid(1), zero),
        ('76ac5b70-47db-4cdb-91e7-e5c18c42e516', zero),
      ]))!;
      expect(idx.ids(), {uuid(1), '76ac5b70-47db-4cdb-91e7-e5c18c42e516'});
    });
  });
}
