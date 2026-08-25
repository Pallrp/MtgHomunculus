// Build script — never ships. Part 2 of 2.
//
// Turns the image cache from `fetch_card_images.dart` into the hash index that
// *does* ship, bundled as an asset.
//
//   dart run tool/build_hash_index.dart
//   dart run tool/build_hash_index.dart --limit 500     # smoke test
//
// Decoding ~116k JPEGs in pure Dart is the slow part, so it runs across
// isolates. Everything else is arithmetic.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mtg_homunculus/features/card_lookup/services/dhash.dart';

import '_paths.dart';

/// Files handed to one isolate at a time.
///
/// Big enough that spawn overhead disappears against the decodes, small enough
/// that progress still moves and a crash loses little.
const _chunkSize = 500;

/// 16 raw UUID bytes rather than the 36-character string: 20 bytes saved per
/// card, ~2.3 MB across the index.
const _idBytes = 16;

const _magic = 'MTGHASH1';

void main(List<String> args) async {
  final limit = _intArg(args, '--limit');

  final dir = Directory(imageDir);
  if (!await dir.exists()) {
    stderr.writeln('No image cache at $imageDir');
    stderr.writeln('Run: dart run tool/fetch_card_images.dart');
    exit(1);
  }

  stdout.writeln('index   grid ${DHash.gridWidth}x${DHash.gridHeight} H+V  '
      '${DHash.bitCount} bits  ${DHash.byteLength} bytes  '
      'version ${DHash.version}');

  // ── collect ───────────────────────────────────────────────────────────────
  stdout.write('scan    listing images...');
  var files = await dir
      .list(followLinks: false)
      .where((e) => e is File && e.path.endsWith('.jpg'))
      .map((e) => e.path)
      .toList();
  files.sort();
  if (limit != null && files.length > limit) files = files.sublist(0, limit);
  stdout.writeln('\rscan    ${files.length} images'
      '${limit != null ? '  (--limit $limit)' : ''}          ');

  if (files.isEmpty) {
    stderr.writeln('Nothing to hash.');
    exit(1);
  }

  // ── hash ──────────────────────────────────────────────────────────────────
  final chunks = <List<String>>[];
  for (var i = 0; i < files.length; i += _chunkSize) {
    chunks.add(files.sublist(i, (i + _chunkSize).clamp(0, files.length)));
  }

  final workers = Platform.numberOfProcessors.clamp(2, 16);
  stdout.writeln('hash    ${chunks.length} chunks of $_chunkSize '
      'across $workers isolates');

  final entries = <_Entry>[];
  final failures = <String>[];
  var done = 0, failed = 0;
  final started = DateTime.now();
  var lastTick = DateTime.now();

  void tick({bool force = false}) {
    if (!force && DateTime.now().difference(lastTick).inMilliseconds < 250) {
      return;
    }
    lastTick = DateTime.now();
    final secs = DateTime.now().difference(started).inMilliseconds / 1000;
    final rate = secs > 0 ? done / secs : 0;
    final left = files.length - done;
    stdout.write('\r        hashed ${done.toString().padLeft(6)}  '
        'failed ${failed.toString().padLeft(4)}  '
        'left ${left.toString().padLeft(6)}  '
        '${rate.toStringAsFixed(0).padLeft(4)}/s  '
        'eta ${_dur(rate > 0 ? (left / rate).round() : 0)}   ');
  }

  var nextChunk = 0;
  Future<void> worker() async {
    while (true) {
      final i = nextChunk++;
      if (i >= chunks.length) return;
      final result = await Isolate.run(() => _hashChunk(chunks[i]));
      entries.addAll(result.entries);
      failures.addAll(result.failures.take(20 - failures.length.clamp(0, 20)));
      failed += result.failures.length;
      done += chunks[i].length;
      tick();
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  tick(force: true);
  stdout.writeln();

  // ── write ─────────────────────────────────────────────────────────────────
  entries.sort((a, b) => a.id.compareTo(b.id));
  final bytes = _encode(entries);

  final out = File(indexPath);
  await out.parent.create(recursive: true);
  await out.writeAsBytes(bytes);

  final kb = bytes.length / 1024;
  stdout.writeln('');
  stdout.writeln('done    ${entries.length} hashed, $failed failed');
  stdout.writeln('        ${kb < 1024 ? '${kb.toStringAsFixed(0)} KB'
      : '${(kb / 1024).toStringAsFixed(2)} MB'}  ->  $indexPath');
  stdout.writeln('        ${_dur(DateTime.now().difference(started).inSeconds)} total');

  if (failures.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('first ${failures.length} failure(s):');
    for (final f in failures) {
      stdout.writeln('  $f');
    }
  }

  _sanityCheck(bytes, entries);
}

// ---------------------------------------------------------------------------
// Hashing — runs inside an isolate
// ---------------------------------------------------------------------------

class _Entry {
  final String id;
  final Uint8List hash;
  const _Entry(this.id, this.hash);
}

class _ChunkResult {
  final List<_Entry> entries;
  final List<String> failures;
  const _ChunkResult(this.entries, this.failures);
}

_ChunkResult _hashChunk(List<String> paths) {
  final entries = <_Entry>[];
  final failures = <String>[];

  for (final path in paths) {
    final id = path
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'\.jpg$'), '');
    try {
      final decoded = img.decodeJpg(File(path).readAsBytesSync());
      if (decoded == null) {
        failures.add('$id: decode returned null');
        continue;
      }
      final gray = _luma(decoded);
      entries.add(_Entry(
        id,
        DHash.compute(gray, decoded.width, decoded.height),
      ));
    } catch (e) {
      failures.add('$id: $e');
    }
  }
  return _ChunkResult(entries, failures);
}

/// BT.601 luma — the same weighting OpenCV's `COLOR_BGR2GRAY` uses.
///
/// This has to match what the app feeds [DHash] at runtime. A different
/// weighting shifts cell means, flips borderline gradient bits, and quietly
/// widens every Hamming distance against the shipped index.
Uint8List _luma(img.Image src) {
  final w = src.width, h = src.height;
  final out = Uint8List(w * h);
  final rgb = src.getBytes(order: img.ChannelOrder.rgb);
  for (var i = 0, p = 0; i < out.length; i++, p += 3) {
    out[i] = (rgb[p] * 299 + rgb[p + 1] * 587 + rgb[p + 2] * 114) ~/ 1000;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Index format
// ---------------------------------------------------------------------------

/// ```
/// "MTGHASH1"          8 bytes
/// versionLen          1 byte
/// version             versionLen bytes, UTF-8
/// count               uint32 little-endian
/// hashLen             1 byte
/// records             count x (16-byte uuid + hashLen bytes), sorted by uuid
/// ```
///
/// The version string is what stops a rebuilt app silently mismatching a stale
/// index: a grid change produces hashes that are simply *different*, with no
/// error to notice — only matches that never happen.
Uint8List _encode(List<_Entry> entries) {
  final version = utf8.encode(DHash.version);
  final recordLen = _idBytes + DHash.byteLength;
  final size = _magic.length + 1 + version.length + 4 + 1
      + entries.length * recordLen;

  final out = BytesBuilder(copy: false);
  out.add(ascii.encode(_magic));
  out.addByte(version.length);
  out.add(version);
  out.add(Uint8List(4)..buffer.asByteData().setUint32(0, entries.length, Endian.little));
  out.addByte(DHash.byteLength);
  for (final e in entries) {
    out.add(_uuidBytes(e.id));
    out.add(e.hash);
  }

  final bytes = out.takeBytes();
  assert(bytes.length == size, 'index size mismatch');
  return bytes;
}

/// `8-4-4-4-12` hex to 16 raw bytes.
Uint8List _uuidBytes(String id) {
  final hex = id.replaceAll('-', '');
  final out = Uint8List(_idBytes);
  for (var i = 0; i < _idBytes; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Read the index back and check it against what we just hashed.
///
/// A build script that writes a subtly wrong file is worse than one that
/// crashes, because nothing downstream will complain — the app will just never
/// match anything.
void _sanityCheck(Uint8List bytes, List<_Entry> entries) {
  var o = 0;
  final magic = ascii.decode(bytes.sublist(0, _magic.length));
  o += _magic.length;
  final vLen = bytes[o++];
  final version = utf8.decode(bytes.sublist(o, o + vLen));
  o += vLen;
  final count = ByteData.sublistView(bytes, o, o + 4).getUint32(0, Endian.little);
  o += 4;
  final hashLen = bytes[o++];

  final ok = magic == _magic &&
      version == DHash.version &&
      count == entries.length &&
      hashLen == DHash.byteLength &&
      bytes.length == o + count * (_idBytes + hashLen);

  stdout.writeln('');
  stdout.writeln('verify  magic=$magic version=$version count=$count '
      'hashLen=$hashLen  ${ok ? 'OK' : 'FAILED'}');
  if (!ok) exit(1);

  if (entries.isEmpty) return;

  // Round-trip one record.
  final first = entries.first;
  final rec = o;
  final id = _formatUuid(bytes.sublist(rec, rec + _idBytes));
  final hash = bytes.sublist(rec + _idBytes, rec + _idBytes + hashLen);
  final match = id == first.id && DHash.distance(Uint8List.fromList(hash), first.hash) == 0;
  stdout.writeln('        first record $id  ${match ? 'OK' : 'MISMATCH'}');
  if (!match) exit(1);

  // A quick look at how far apart unrelated cards land — if this is small, the
  // hash is not discriminating and the grid needs revisiting.
  if (entries.length > 1000) {
    var sum = 0, n = 0;
    for (var i = 0; i + 500 < entries.length && n < 500; i += 97, n++) {
      sum += DHash.distance(entries[i].hash, entries[i + 500].hash);
    }
    stdout.writeln('        mean distance between unrelated cards: '
        '${(sum / n).toStringAsFixed(1)} / ${DHash.bitCount} bits');
  }
}

String _formatUuid(List<int> b) {
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

String _dur(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m${(seconds % 60).toString().padLeft(2, '0')}s';
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}m';
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}
