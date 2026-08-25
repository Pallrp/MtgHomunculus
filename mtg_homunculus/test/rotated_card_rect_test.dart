import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtg_homunculus/features/card_lookup/models/rotated_card_rect.dart';

/// An axis-aligned card of [longSide] pixels, at the true card aspect unless
/// [aspect] says otherwise.
///
/// [rectifiedAspect] is supplied rather than derived: recovering it needs the
/// focal length and belongs to the detector, and passing it in is what lets a
/// test state "this quad is off-shape" directly.
RotatedCardRect rect({
  required double longSide,
  double aspect = 0.716,
  double? rectifiedAspect = 0.716,
  Offset origin = Offset.zero,
}) {
  final w = longSide * aspect;
  final h = longSide;
  return RotatedCardRect(
    corners: [
      origin,
      origin.translate(w, 0),
      origin.translate(w, h),
      origin.translate(0, h),
    ],
    bounds: Rect.fromLTWH(origin.dx, origin.dy, w, h),
    rotationAngle: 0,
    rectifiedAspect: rectifiedAspect,
  );
}

/// The same card turned 45°, which roughly doubles its bounding box while
/// leaving its actual area unchanged.
RotatedCardRect rotated45({required double longSide}) {
  final w = longSide * 0.716;
  final h = longSide;
  const a = math.pi / 4;
  final cx = w / 2, cy = h / 2;
  Offset turn(double x, double y) {
    final dx = x - cx, dy = y - cy;
    return Offset(
      cx + dx * math.cos(a) - dy * math.sin(a),
      cy + dx * math.sin(a) + dy * math.cos(a),
    );
  }

  final corners = [turn(0, 0), turn(w, 0), turn(w, h), turn(0, h)];
  final xs = corners.map((c) => c.dx);
  final ys = corners.map((c) => c.dy);
  return RotatedCardRect(
    corners: corners,
    bounds: Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    ),
    rotationAngle: a,
    rectifiedAspect: 0.716,
  );
}

void main() {
  group('best', () {
    test('nothing detected yields nothing', () {
      expect(RotatedCardRect.best(const []), isNull);
    });

    test('a single detection is returned whatever its quality', () {
      // A clipped card is still the only thing on screen, and must keep its
      // border so the "Whole card not in view" label can appear.
      final only = rect(longSide: 300, rectifiedAspect: 0.50);
      expect(only.quality, CardQuality.offShape);
      expect(RotatedCardRect.best([only]), same(only));
    });

    test('the larger of two plausible cards wins', () {
      final small = rect(longSide: 300);
      final big = rect(longSide: 700);
      expect(RotatedCardRect.best([small, big]), same(big));
      expect(RotatedCardRect.best([big, small]), same(big));
    });

    test('a distant real card beats a closer phantom that scores good', () {
      // The case that rules out ranking on quality. A card at arm's length is
      // amber `tooFar`; a patch of wood grain can land inside every band and
      // score `good`. Quality-first would move the border onto the phantom and
      // then colour it green.
      final card = rect(longSide: 400);
      final phantom = rect(longSide: 200);
      expect(card.quality, CardQuality.tooFar); // 400px / 88mm = 4.5 px/mm
      expect(phantom.quality, CardQuality.tooFar);

      final closeCard = rect(longSide: 700);
      expect(closeCard.quality, CardQuality.good);

      expect(RotatedCardRect.best([phantom, card]), same(card));
      expect(RotatedCardRect.best([phantom, closeCard]), same(closeCard));
    });

    test('a large off-shape quad loses to a smaller genuine card', () {
      // Area alone would hand this to the blob — a table edge or binder page
      // that cleared the detector's looser drawn-aspect gate.
      final blob = rect(longSide: 900, aspect: 0.9, rectifiedAspect: 0.95);
      final card = rect(longSide: 400);
      expect(blob.quality, CardQuality.offShape);

      expect(RotatedCardRect.best([blob, card]), same(card));
      expect(RotatedCardRect.best([card, blob]), same(card));
    });

    test('the least bad is chosen when everything is off-shape', () {
      final small = rect(longSide: 200, rectifiedAspect: 0.4);
      final large = rect(longSide: 600, rectifiedAspect: 0.4);
      expect(RotatedCardRect.best([small, large]), same(large));
    });

    test('rotation does not decide the winner', () {
      // A 45° card has ~2x the bounding box of the same card square-on, so
      // ranking on bounds would pick the diagonal one regardless of size.
      final diagonal = rotated45(longSide: 500);
      final upright = rect(longSide: 600);
      expect(diagonal.bounds.width * diagonal.bounds.height,
          greaterThan(upright.bounds.width * upright.bounds.height));
      expect(RotatedCardRect.best([diagonal, upright]), same(upright));
    });
  });
}
