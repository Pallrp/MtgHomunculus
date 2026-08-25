import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/services/dhash.dart';

/// Synthetic 488 x 680 grayscale image, the canonical card size.
Uint8List _img(int w, int h, int Function(int x, int y) f) {
  final b = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      b[y * w + x] = f(x, y).clamp(0, 255);
    }
  }
  return b;
}

void main() {
  const w = 488, h = 680;

  group('parameters', () {
    test('157 bits in 20 bytes', () {
      expect(DHash.horizontalBits, 77);
      expect(DHash.verticalBits, 80);
      expect(DHash.bitCount, 157);
      expect(DHash.byteLength, 20);
    });

    test('the 3 pad bits are never set', () {
      final hash = DHash.compute(
        _img(w, h, (x, y) => x + y), w, h,
      );
      // 157 bits used; bits 157..159 are the low 3 of the final byte.
      expect(hash.last & 0x07, 0, reason: 'pad bits must stay zero');
    });
  });

  group('gradients', () {
    test('flat image sets no bits', () {
      final hash = DHash.compute(_img(w, h, (_, _) => 128), w, h);
      expect(hash.every((b) => b == 0), isTrue);
    });

    test('left-to-right ramp sets every horizontal bit, no vertical bit', () {
      final hash = DHash.compute(_img(w, h, (x, _) => x ~/ 2), w, h);
      var set = 0;
      for (var i = 0; i < DHash.bitCount; i++) {
        if ((hash[i >> 3] & (0x80 >> (i & 7))) != 0) set++;
      }
      expect(set, DHash.horizontalBits,
          reason: 'a pure horizontal ramp has no vertical gradient');
    });

    test('top-to-bottom ramp sets every vertical bit, no horizontal bit', () {
      final hash = DHash.compute(_img(w, h, (_, y) => y ~/ 3), w, h);
      var set = 0;
      for (var i = 0; i < DHash.bitCount; i++) {
        if ((hash[i >> 3] & (0x80 >> (i & 7))) != 0) set++;
      }
      expect(set, DHash.verticalBits);
    });
  });

  group('distance', () {
    final card = _img(w, h, (x, y) => (sin(x / 40) * 60 + cos(y / 25) * 60 + 128).toInt());

    test('identical images are distance 0', () {
      expect(DHash.distance(DHash.compute(card, w, h),
                            DHash.compute(card, w, h)), 0);
    });

    test('survives brightness shift — the hash is about gradients', () {
      final darker = Uint8List.fromList(card.map((b) => (b * 0.6).toInt()).toList());
      expect(DHash.distance(DHash.compute(card, w, h),
                            DHash.compute(darker, w, h)), 0);
    });

    test('tolerates noise', () {
      final rng = Random(7);
      final noisy = Uint8List.fromList(
        card.map((b) => (b + rng.nextInt(31) - 15).clamp(0, 255)).toList(),
      );
      final d = DHash.distance(DHash.compute(card, w, h),
                               DHash.compute(noisy, w, h));
      expect(d, lessThan(20), reason: 'noise must not swamp a real match');
    });

    test('unrelated images are far apart', () {
      final other = _img(w, h, (x, y) => ((x ~/ 30) % 2 == (y ~/ 30) % 2) ? 30 : 220);
      final d = DHash.distance(DHash.compute(card, w, h),
                               DHash.compute(other, w, h));
      expect(d, greaterThan(40), reason: 'must separate from a real match');
    });

    test('mismatched lengths return maximum distance, never a false match', () {
      expect(DHash.distance(Uint8List(4), Uint8List(DHash.byteLength)),
             DHash.bitCount);
    });
  });

  group('input handling', () {
    test('honours a padded row stride', () {
      const stride = w + 16;
      final padded = Uint8List(stride * h);
      final tight  = _img(w, h, (x, y) => (x * y) % 251);
      for (var y = 0; y < h; y++) {
        padded.setRange(y * stride, y * stride + w, tight, y * w);
      }
      expect(DHash.compute(padded, w, h, rowStride: stride),
             DHash.compute(tight, w, h));
    });

    test('degenerate input returns zeros rather than throwing', () {
      expect(DHash.compute(Uint8List(0), 0, 0).every((b) => b == 0), isTrue);
      expect(DHash.compute(Uint8List(4), 2, 2).every((b) => b == 0), isTrue);
    });
  });
}
