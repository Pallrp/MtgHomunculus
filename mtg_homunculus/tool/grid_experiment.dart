// Build script — never ships. Grid calibration for DHash.
//
//   dart run tool/grid_experiment.dart
//   dart run tool/grid_experiment.dart --cards 600
//
// The grid in `dhash.dart` was chosen from ONE card and one synthetic
// degradation. This measures the candidates against real Scryfall art and
// degradations that resemble what the scanner actually produces.
//
// What matters is not the average distance but the **gap**: the worst
// same-card distance has to stay below the best different-card distance, or no
// threshold exists that separates them.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mtg_homunculus/features/card_lookup/services/dhash.dart';

import '_paths.dart';

class Grid {
  final int w, h;
  final bool horizontal, vertical;
  const Grid(this.w, this.h, {this.horizontal = true, this.vertical = true});

  int get bits =>
      (horizontal ? (w - 1) * h : 0) + (vertical ? w * (h - 1) : 0);

  String get label =>
      '${w}x$h ${horizontal && vertical ? "H+V" : horizontal ? "H" : "V"}';
}

const _grids = [
  Grid(8, 11),                        // current
  Grid(8, 11, vertical: false),       // same grid, horizontal only
  Grid(6, 8),
  Grid(10, 14),
  Grid(12, 16),
  Grid(16, 22),
  Grid(8, 8),                         // square grid on a non-square card
  Grid(16, 8),                        // the shape the docs say scored worst
];

void main(List<String> args) async {
  final n = _intArg(args, '--cards') ?? 400;

  final files = await Directory(imageDir)
      .list(followLinks: false)
      .where((e) => e is File && e.path.endsWith('.jpg'))
      .map((e) => e.path)
      .take(n * 3)
      .toList();
  files.sort();
  if (files.length < n) {
    stderr.writeln('Only ${files.length} images cached; run the fetcher first.');
    exit(1);
  }
  final picks = [for (var i = 0; i < n; i++) files[i * (files.length ~/ n)]];

  stdout.writeln('loading $n cards...');
  final cards = <_Gray>[];
  for (final p in picks) {
    final d = img.decodeJpg(File(p).readAsBytesSync());
    if (d == null) continue;
    cards.add(_Gray.from(d));
  }
  stdout.writeln('loaded ${cards.length}\n');

  // Degradations, roughly in the order the scanner inflicts them.
  final degradations = <String, _Gray Function(_Gray)>{
    'blur'          : (g) => g.blur(2),
    'noise +-20'    : (g) => g.noise(20),
    'dim x0.65'     : (g) => g.scaleBrightness(0.65),
    'crop 3%'       : (g) => g.cropShift(0.03),
    'combined'      : (g) => g.blur(2).noise(15).scaleBrightness(0.75).cropShift(0.02),
  };

  stdout.writeln('${'grid'.padRight(12)}${'bits'.padLeft(5)}   '
      '${'degradation'.padRight(13)}${'rank-1'.padLeft(8)}'
      '${'margin'.padLeft(9)}${'mean self'.padLeft(11)}${'mean other'.padLeft(11)}');
  stdout.writeln('-' * 79);

  for (final grid in _grids) {
    final originals = [for (final c in cards) _hash(c, grid)];
    var first = true;

    for (final entry in degradations.entries) {
      var hits = 0, selfSum = 0, otherSum = 0, otherN = 0;
      var worstMargin = grid.bits;

      for (var i = 0; i < cards.length; i++) {
        final q = _hash(entry.value(cards[i]), grid);
        final self = _distance(originals[i], q, grid.bits);
        selfSum += self;

        // Nearest wrong answer — the only competitor that matters.
        var nearestOther = grid.bits;
        for (var j = 0; j < originals.length; j++) {
          if (j == i) continue;
          final d = _distance(originals[j], q, grid.bits);
          if (d < nearestOther) nearestOther = d;
          otherSum += d;
          otherN++;
        }
        if (self < nearestOther) hits++;
        final margin = nearestOther - self;
        if (margin < worstMargin) worstMargin = margin;
      }

      stdout.writeln(
        '${(first ? grid.label : '').padRight(12)}'
        '${(first ? '${grid.bits}' : '').padLeft(5)}   '
        '${entry.key.padRight(13)}'
        '${'${(100 * hits / cards.length).toStringAsFixed(1)}%'.padLeft(8)}'
        '${worstMargin.toString().padLeft(9)}'
        '${(selfSum / cards.length).toStringAsFixed(1).padLeft(11)}'
        '${(otherSum / otherN).toStringAsFixed(1).padLeft(11)}',
      );
      first = false;
    }
    stdout.writeln('');
  }

  // The production implementation must agree with the experiment for 8x11 H+V,
  // or none of the above transfers.
  final probe = cards.first;
  final mine  = _hash(probe, const Grid(8, 11));
  final prod  = DHash.compute(probe.bytes, probe.w, probe.h);
  final agree = mine.length == prod.length &&
      List.generate(mine.length, (i) => mine[i] == prod[i]).every((x) => x);
  stdout.writeln('cross-check vs DHash (8x11 H+V): '
      '${agree ? "IDENTICAL" : "DIFFERENT — results do not transfer"}');
}

// ---------------------------------------------------------------------------
// Parameterised hash — mirrors DHash exactly, but with the grid as an argument
// ---------------------------------------------------------------------------

Uint8List _hash(_Gray g, Grid grid) {
  final cells = Float64List(grid.w * grid.h);
  for (var gy = 0; gy < grid.h; gy++) {
    final y0 = (gy * g.h) ~/ grid.h;
    final y1 = (((gy + 1) * g.h) ~/ grid.h).clamp(y0 + 1, g.h);
    for (var gx = 0; gx < grid.w; gx++) {
      final x0 = (gx * g.w) ~/ grid.w;
      final x1 = (((gx + 1) * g.w) ~/ grid.w).clamp(x0 + 1, g.w);
      var sum = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          sum += g.bytes[y * g.w + x];
        }
      }
      cells[gy * grid.w + gx] = sum / ((y1 - y0) * (x1 - x0));
    }
  }

  final out = Uint8List((grid.bits + 7) ~/ 8);
  var bit = 0;
  void push(bool set) {
    if (set) out[bit >> 3] |= 0x80 >> (bit & 7);
    bit++;
  }
  if (grid.horizontal) {
    for (var y = 0; y < grid.h; y++) {
      for (var x = 0; x < grid.w - 1; x++) {
        push(cells[y * grid.w + x] < cells[y * grid.w + x + 1]);
      }
    }
  }
  if (grid.vertical) {
    for (var x = 0; x < grid.w; x++) {
      for (var y = 0; y < grid.h - 1; y++) {
        push(cells[y * grid.w + x] < cells[(y + 1) * grid.w + x]);
      }
    }
  }
  return out;
}

int _distance(Uint8List a, Uint8List b, int bits) {
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    var x = a[i] ^ b[i];
    while (x != 0) {
      x &= x - 1;
      d++;
    }
  }
  return d;
}

// ---------------------------------------------------------------------------
// Grayscale image + degradations
// ---------------------------------------------------------------------------

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

  /// Focus loss.
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

  /// Sensor noise.
  _Gray noise(int amp) {
    final rng = Random(1234);
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = (bytes[i] + rng.nextInt(amp * 2 + 1) - amp).clamp(0, 255);
    }
    return _Gray(out, w, h);
  }

  /// Lighting. dHash should be immune — this is the control.
  _Gray scaleBrightness(double f) {
    final out = Uint8List(w * h);
    for (var i = 0; i < out.length; i++) {
      out[i] = (bytes[i] * f).round().clamp(0, 255);
    }
    return _Gray(out, w, h);
  }

  /// Corner error: the warp includes slightly less than the whole card and is
  /// stretched back to full size. Measured corner error on device ran ~4%, so
  /// this is the degradation that most resembles a real miss.
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
