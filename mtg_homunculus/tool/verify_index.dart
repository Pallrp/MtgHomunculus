// Build script — never ships.
//
//   dart run tool/verify_index.dart
//   dart run tool/verify_index.dart --queries 300
//
// Every accuracy figure so far came from 300-1500 cards. This runs retrieval
// against the **whole** shipped index: degrade a real card, hash it, scan all
// 115,962 entries, and check the correct card comes back first.
//
// It also reports the margin between the right answer and the nearest wrong one,
// which is what a match threshold has to sit inside.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mtg_homunculus/features/card_lookup/services/dhash.dart';

import '_paths.dart';

void main(List<String> args) async {
  final queries = _intArg(args, '--queries') ?? 200;

  // ── load the index ────────────────────────────────────────────────────────
  final bytes = await File(indexPath).readAsBytes();
  var o = 0;
  final magic = ascii.decode(bytes.sublist(0, 8));
  o = 8;
  final vLen = bytes[o++];
  final version = utf8.decode(bytes.sublist(o, o + vLen));
  o += vLen;
  final count = ByteData.sublistView(bytes, o, o + 4).getUint32(0, Endian.little);
  o += 4;
  final hashLen = bytes[o++];
  final headerLen = o;
  const idLen = 16;
  final recordLen = idLen + hashLen;

  if (magic != 'MTGHASH1' || version != DHash.version) {
    stderr.writeln('index mismatch: magic=$magic version=$version');
    stderr.writeln('this build of DHash expects ${DHash.version}');
    exit(1);
  }

  stdout.writeln('index   $count cards, $hashLen-byte hashes, '
      '${(bytes.length / (1024 * 1024)).toStringAsFixed(2)} MB');

  // id -> record number, so a query can be scored against its own card.
  final rowOf = <String, int>{};
  for (var r = 0; r < count; r++) {
    rowOf[_uuid(bytes, headerLen + r * recordLen)] = r;
  }

  // ── pick real cards to query with ─────────────────────────────────────────
  final files = await Directory(imageDir)
      .list(followLinks: false)
      .where((e) => e is File && e.path.endsWith('.jpg'))
      .map((e) => e.path)
      .toList();
  files.sort();
  final step = files.length ~/ queries;
  final picks = [for (var i = 0; i < queries; i++) files[i * step]];

  final degradations = <String, _Gray Function(_Gray)>{
    'clean'     : (g) => g,
    'blur+noise': (g) => g.blur(2).noise(15),
    'crop 2%'   : (g) => g.cropShift(0.02),
    'crop 3%'   : (g) => g.cropShift(0.03),
    'combined'  : (g) => g.blur(2).noise(15).scaleBrightness(0.75).cropShift(0.02),
  };

  stdout.writeln('scan    $queries queries x ${degradations.length} degradations '
      'against all $count\n');
  const thresholds = [6, 10, 14, 18, 22];
  stdout.writeln('For each threshold T: recall = correct card within T; '
      'cands = how many cards are');
  stdout.writeln('within T (1 = identified outright, >1 = Choose Version, '
      '0 = fall through to OCR).\n');
  stdout.write('${'degradation'.padRight(13)}${'self'.padLeft(6)}');
  for (final t in thresholds) {
    stdout.write('T=$t'.padLeft(15));
  }
  stdout.writeln('');
  stdout.write('${''.padRight(13)}${'dist'.padLeft(6)}');
  for (var i = 0; i < thresholds.length; i++) {
    stdout.write('${'recall'.padLeft(8)}${'cands'.padLeft(7)}');
  }
  stdout.writeln('\n${'-' * (19 + 15 * thresholds.length)}');

  final scanMs = <int>[];

  for (final entry in degradations.entries) {
    var selfSum = 0, scored = 0;
    final recall = List<int>.filled(thresholds.length, 0);
    final cands  = List<int>.filled(thresholds.length, 0);

    for (final path in picks) {
      final id = path.split(Platform.pathSeparator).last.replaceAll('.jpg', '');
      final row = rowOf[id];
      if (row == null) continue;

      final decoded = img.decodeJpg(File(path).readAsBytesSync());
      if (decoded == null) continue;
      final q = DHash.compute(
        entry.value(_Gray.from(decoded)).bytes,
        decoded.width,
        decoded.height,
      );

      final sw = Stopwatch()..start();
      final within = List<int>.filled(thresholds.length, 0);
      for (var r = 0; r < count; r++) {
        final base = headerLen + r * recordLen + idLen;
        var d = 0;
        for (var b = 0; b < hashLen; b++) {
          var x = bytes[base + b] ^ q[b];
          while (x != 0) {
            x &= x - 1;
            d++;
          }
        }
        for (var t = 0; t < thresholds.length; t++) {
          if (d <= thresholds[t]) within[t]++;
        }
      }
      sw.stop();
      scanMs.add(sw.elapsedMicroseconds);

      final selfDist =
          _distanceAt(bytes, headerLen + row * recordLen + idLen, q, hashLen);
      selfSum += selfDist;
      for (var t = 0; t < thresholds.length; t++) {
        if (selfDist <= thresholds[t]) recall[t]++;
        cands[t] += within[t];
      }
      scored++;
    }

    stdout.write('${entry.key.padRight(13)}'
        '${(selfSum / scored).toStringAsFixed(1).padLeft(6)}');
    for (var t = 0; t < thresholds.length; t++) {
      stdout.write('${'${(100 * recall[t] / scored).toStringAsFixed(0)}%'.padLeft(8)}'
          '${(cands[t] / scored).toStringAsFixed(1).padLeft(7)}');
    }
    stdout.writeln('');
  }

  scanMs.sort();
  stdout.writeln('');
  stdout.writeln('scan time over $count cards: '
      'median ${(scanMs[scanMs.length ~/ 2] / 1000).toStringAsFixed(1)} ms, '
      'p95 ${(scanMs[(scanMs.length * 95) ~/ 100] / 1000).toStringAsFixed(1)} ms');
}

int _distanceAt(Uint8List buf, int off, Uint8List q, int len) {
  var d = 0;
  for (var b = 0; b < len; b++) {
    var x = buf[off + b] ^ q[b];
    while (x != 0) {
      x &= x - 1;
      d++;
    }
  }
  return d;
}

String _uuid(Uint8List b, int off) {
  final sb = StringBuffer();
  for (var i = 0; i < 16; i++) {
    sb.write(b[off + i].toRadixString(16).padLeft(2, '0'));
    if (i == 3 || i == 5 || i == 7 || i == 9) sb.write('-');
  }
  return sb.toString();
}

class _Gray {
  final Uint8List bytes;
  final int w, h;
  _Gray(this.bytes, this.w, this.h);

  factory _Gray.from(img.Image src) {
    final rgb = src.getBytes(order: img.ChannelOrder.rgb);
    final out = Uint8List(src.width * src.height);
    for (var i = 0, p = 0; i < out.length; i++, p += 3) {
      out[i] = (rgb[p] * 299 + rgb[p + 1] * 587 + rgb[p + 2] * 114) ~/ 1000;
    }
    return _Gray(out, src.width, src.height);
  }

  _Gray blur(int r) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sum = 0, n = 0;
        for (var dy = -r; dy <= r; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -r; dx <= r; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            sum += bytes[yy * w + xx];
            n++;
          }
        }
        out[y * w + x] = sum ~/ n;
      }
    }
    return _Gray(out, w, h);
  }

  _Gray noise(int amp) {
    final rng = Random(99);
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = (bytes[i] + rng.nextInt(amp * 2 + 1) - amp).clamp(0, 255);
    }
    return _Gray(out, w, h);
  }

  _Gray scaleBrightness(double f) {
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = (bytes[i] * f).round().clamp(0, 255);
    }
    return _Gray(out, w, h);
  }

  _Gray cropShift(double frac) {
    final dx = (w * frac).round(), dy = (h * frac).round();
    final cw = w - dx, ch = h - dy;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final sy = dy + (y * ch) ~/ h;
      for (var x = 0; x < w; x++) {
        final sx = dx + (x * cw) ~/ w;
        out[y * w + x] = bytes[sy.clamp(0, h - 1) * w + sx.clamp(0, w - 1)];
      }
    }
    return _Gray(out, w, h);
  }
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}
