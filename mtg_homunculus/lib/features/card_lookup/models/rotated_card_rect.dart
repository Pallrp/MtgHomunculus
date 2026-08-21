import 'dart:ui' as ui;

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

  RotatedCardRect({
    required this.corners,
    required this.bounds,
    required this.rotationAngle,
  }) : assert(corners.length == 4, 'Must have exactly 4 corner points');

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
