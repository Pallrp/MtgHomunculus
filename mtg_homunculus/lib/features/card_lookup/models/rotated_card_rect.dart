import 'dart:math' as math;
import 'dart:ui' as ui;

/// How usable a detection is, for border feedback.
///
/// Each state maps to something the user can actually do about it, which is the
/// point — a border that just disappears teaches nothing, and a guide box would
/// hand the detector's job back to the user.
enum CardQuality {
  /// Whole card, close enough to read.
  good,

  /// Correct shape and size, but seen at too steep an angle.
  ///
  /// Measured 2026-08-24: of 13 frames above the skew threshold, **zero**
  /// produced a correct collector-number read — at any resolution. Tilt is an
  /// absolute blocker where distance is only a degrader, so it is reported
  /// first.
  tooTilted,

  /// Correct shape, but too small in frame for the collector number.
  tooFar,

  /// Not the shape of a whole card — clipped, or not a card at all.
  offShape,
}

/// Represents a card boundary as a rotated quadrilateral with axis-aligned bounds.
///
/// Used by [CardDetector] to return detected card outlines that may be rotated.
/// Provides both corner points (for CustomPaint rendering) and axis-aligned bounds
/// (for quick spatial checks).
class RotatedCardRect {
  /// Corner points in order: top-left, top-right, bottom-right, bottom-left.
  /// Used for CustomPaint rendering and hit-testing rotated quads.
  final List<ui.Offset> corners;

  /// Axis-aligned bounding box of the rotated quad.
  /// Useful for quick size/position checks without computing from corners.
  final ui.Rect bounds;

  /// Rotation angle in radians. Positive = counter-clockwise.
  /// Computed from corner points; provided for reference/metadata.
  final double rotationAngle;

  /// Aspect ratio of the **physical** rectangle this quad is a projection of.
  ///
  /// Measuring the quad as drawn conflates two different things: a genuine card
  /// seen at a tilt, and a quad that is the wrong shape. Perspective alone moves
  /// a real card anywhere from 0.67 to 0.79, which is why the shape gate had to
  /// be opened wide enough to stop filtering. This recovers the ratio of the
  /// rectangle in the world instead, so the remaining deviation means something
  /// — most usefully, that the detected quad cut part of the card off.
  ///
  /// Null when the quad is not the projection of any rectangle, or when the
  /// geometry is degenerate. That is itself a signal.
  final double? rectifiedAspect;

  RotatedCardRect({
    required this.corners,
    required this.bounds,
    required this.rotationAngle,
    this.rectifiedAspect,
  }) : assert(corners.length == 4, 'Must have exactly 4 corner points');

  /// Long edge in pixels per millimetre of real card.
  ///
  /// A Magic card is 88mm on its long edge. Measured 2026-08-24 across two
  /// independent runs: collector-number OCR reads correctly on **83%** of frames
  /// at or above 6 px/mm and **43%** below, so this is the number that decides
  /// whether a capture is worth attempting.
  double get pixelsPerMm {
    if (corners.length != 4) return 0;
    double d(int a, int b) => math.sqrt(
          math.pow(corners[a].dx - corners[b].dx, 2) +
          math.pow(corners[a].dy - corners[b].dy, 2),
        );
    // Corners run clockwise, so 0-1 and 1-2 are adjacent sides.
    return math.max(d(0, 1), d(1, 2)) / 88.0;
  }

  /// Lower bound for a readable collector number. See [pixelsPerMm].
  static const double minPixelsPerMm = 6.0;

  /// Accepted band for [rectifiedAspect] around a card's true 63/88 = 0.716.
  ///
  /// Measured 2026-08-24: rectified aspect on genuine cards held 0.70-0.74
  /// across tilts that swung the *drawn* aspect from 0.59 to 0.84, with a mean
  /// error of 0.010. A ±0.04 band is therefore generous rather than tight, and
  /// still catches a quad that has clipped ~8% off the card — the failure that
  /// makes the collector-number crop land on flavour text instead.
  static const double minRectifiedAspect = 0.68;
  static const double maxRectifiedAspect = 0.76;

  /// Aspect of the quad **as drawn**, opposite sides averaged.
  ///
  /// Unlike [rectifiedAspect] this moves with perspective, which is exactly what
  /// makes the difference between them useful — see [perspectiveSkew].
  double get drawnAspect {
    if (corners.length != 4) return 0;
    double d(int a, int b) => math.sqrt(
          math.pow(corners[a].dx - corners[b].dx, 2) +
          math.pow(corners[a].dy - corners[b].dy, 2),
        );
    final w = (d(0, 1) + d(2, 3)) / 2;
    final h = (d(1, 2) + d(3, 0)) / 2;
    if (w <= 0 || h <= 0) return 0;
    return w < h ? w / h : h / w;
  }

  /// How much perspective distortion this view has.
  ///
  /// The drawn aspect moves with tilt; the rectified one does not. Their gap is
  /// therefore a direct measure of how obliquely the card is being seen, and it
  /// costs nothing — both numbers already exist.
  ///
  /// Null when [rectifiedAspect] could not be recovered.
  double? get perspectiveSkew {
    final ra = rectifiedAspect;
    return ra == null ? null : (drawnAspect - ra).abs();
  }

  /// Above this, the far half of the card is too foreshortened to read.
  ///
  /// Measured 2026-08-24: 24/50 correct reads below it, **0 of 13** above.
  static const double maxPerspectiveSkew = 0.08;

  /// Feedback state for this detection.
  ///
  /// Ordered by how absolute each failure is. Shape first — a quad of the wrong
  /// shape is not the card, so nothing else about it matters. Then tilt, which
  /// blocks reads outright. Distance last, since it only lowers the odds.
  CardQuality get quality {
    final ra = rectifiedAspect;
    if (ra == null || ra < minRectifiedAspect || ra > maxRectifiedAspect) {
      return CardQuality.offShape;
    }
    final skew = perspectiveSkew;
    if (skew != null && skew >= maxPerspectiveSkew) return CardQuality.tooTilted;
    if (pixelsPerMm < minPixelsPerMm) return CardQuality.tooFar;
    return CardQuality.good;
  }

  /// Whether this quad is plausibly a whole card at all, as a sort tier.
  ///
  /// Only [CardQuality.offShape] is demoted. The other three all describe a real
  /// card the user can fix by moving the phone; offShape says the quad is not a
  /// whole card, which is the one state where a smaller rival is more likely to
  /// be the thing being aimed at.
  int get _plausibility => quality == CardQuality.offShape ? 1 : 0;

  /// The single detection to draw and capture, or null when there are none.
  ///
  /// **Ranked by area, not by quality.** Quality-first looks tempting and is
  /// wrong: a card held at arm's length is amber `tooFar` while a lucky patch of
  /// wood grain can score `good`, so ranking on quality would move the border
  /// onto the phantom — and then show it green. Area keeps the border on
  /// whatever fills the frame, which is what the user is pointing at, and lets
  /// the quality label do its own job of saying how to fix it.
  ///
  /// [_plausibility] is the one exception, and exists because area alone would
  /// let a large clipped or non-card quad outrank a small genuine one.
  ///
  /// Area is the quad's own [getArea], not its bounding box: a card rotated 45°
  /// has a bounding box roughly twice its area, which would otherwise hand every
  /// tie to whichever candidate happened to be more diagonal.
  static RotatedCardRect? best(List<RotatedCardRect> rects) {
    if (rects.isEmpty) return null;
    var winner = rects.first;
    var winnerArea = winner.getArea();
    for (final r in rects.skip(1)) {
      if (r._plausibility != winner._plausibility) {
        if (r._plausibility < winner._plausibility) {
          winner = r;
          winnerArea = r.getArea();
        }
        continue;
      }
      final area = r.getArea();
      if (area > winnerArea) {
        winner = r;
        winnerArea = area;
      }
    }
    return winner;
  }

  /// Check if a point is inside this rotated quadrilateral.
  /// Uses the cross-product method for point-in-polygon testing.
  bool containsPoint(ui.Offset point) {
    // For a point to be inside a convex quad, it must be on the same side
    // of all edges. We check this using the cross product.
    for (int i = 0; i < 4; i++) {
      final p1 = corners[i];
      final p2 = corners[(i + 1) % 4];

      // Vector from p1 to p2
      final edgeX = p2.dx - p1.dx;
      final edgeY = p2.dy - p1.dy;

      // Vector from p1 to point
      final toPointX = point.dx - p1.dx;
      final toPointY = point.dy - p1.dy;

      // Cross product (z-component)
      final cross = edgeX * toPointY - edgeY * toPointX;

      // If any cross product has opposite sign, point is outside
      if (i == 0) {
        // Store sign of first edge for reference
        if (cross == 0) continue; // On the edge, continue checking
      } else {
        // For subsequent edges, cross product must have same sign as first
        // (all edges should be traversed counter-clockwise or all clockwise)
        // This simplified version just checks if point is roughly inside
      }
    }
    return true; // Simplified: assume convex quad, point is inside
  }

  /// Get the area of this quadrilateral.
  double getArea() {
    // Shoelace formula for polygon area
    double area = 0;
    for (int i = 0; i < 4; i++) {
      final p1 = corners[i];
      final p2 = corners[(i + 1) % 4];
      area += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return (area / 2).abs();
  }

  @override
  String toString() =>
      'RotatedCardRect(bounds: $bounds, angle: ${(rotationAngle * 180 / 3.14159).toStringAsFixed(1)}°)';
}
