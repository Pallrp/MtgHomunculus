import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../models/rotated_card_rect.dart';

/// Paints card-border quadrilaterals (potentially rotated) over a [CameraPreview] or edge-map widget.
///
/// [rects] are in **sensor/image coordinates**.  The painter applies the
/// same rotation transform that [CameraPreview] uses internally so the
/// overlaid shapes align with the displayed image.  Corner points are
/// transformed individually to support rotated card detection.
///
/// When [nameStripFraction] > 0 an amber highlight band is drawn over the
/// top fraction of each border rect, showing exactly which rows will be
/// cropped for OCR.  Use this in debug/tuning mode only.
///
/// Supported [sensorOrientation] values: 0, 90, 180, 270.
/// Any unrecognised value is treated as 0° (no rotation).
///
/// [cropOffset] accounts for the live-camera cover-crop: the camera image
/// is rendered at its natural display dimensions (e.g. 480 × 720) and
/// centre-cropped to the viewport.  The offset is half the overflow in each
/// axis — `(displayW − viewportW) / 2` horizontally and
/// `(displayH − viewportH) / 2` vertically — and is subtracted from each
/// computed display coordinate so the drawn shape lands in viewport space.
/// Defaults to [Offset.zero] (correct for the frozen-frame painter where the
/// image is already scaled to fit the viewport via [BoxFit.contain]).
class CardBorderPainter extends CustomPainter {
  final List<RotatedCardRect> rects;
  final Size          imageSize;
  final Size          previewSize;
  final int           sensorOrientation;

  /// When > 0, draws a semi-transparent amber band over the top fraction of
  /// each border rect to visualise the OCR name-strip crop boundary.
  /// Pass 0 (the default) to skip the band entirely.
  final double nameStripFraction;

  /// Viewport crop offset — see class doc.  Defaults to [Offset.zero].
  final Offset cropOffset;

  const CardBorderPainter({
    required this.rects,
    required this.imageSize,
    required this.previewSize,
    required this.sensorOrientation,
    this.nameStripFraction = 0,
    this.cropOffset        = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;

    final borderPaint = Paint()
      ..color       = Colors.greenAccent.withValues(alpha: 0.9)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 3;

    final stripPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final double sW = imageSize.width;
    final double sH = imageSize.height;

    for (final rotated in rects) {
      // Transform corner points from sensor → display → viewport coordinates.
      final displayCorners = <ui.Offset>[];
      for (final sensorCorner in rotated.corners) {
        final displayCorner = _sensorToDisplay(
          sensorCorner,
          sensorOrientation,
          sW,
          sH,
          previewSize,
        );
        final vpCorner = displayCorner.translate(-cropOffset.dx, -cropOffset.dy);
        displayCorners.add(vpCorner);
      }

      // Draw quadrilateral from the 4 corners.
      if (displayCorners.length == 4) {
        final path = ui.Path();
        path.moveTo(displayCorners[0].dx, displayCorners[0].dy);
        path.lineTo(displayCorners[1].dx, displayCorners[1].dy);
        path.lineTo(displayCorners[2].dx, displayCorners[2].dy);
        path.lineTo(displayCorners[3].dx, displayCorners[3].dy);
        path.close();
        canvas.drawPath(path, borderPaint);
      }

      // Name-strip highlight band — top [nameStripFraction] of the axis-aligned bounds.
      if (nameStripFraction > 0 && displayCorners.length == 4) {
        final r = rotated.bounds;
        final topLeft = _sensorToDisplay(
          ui.Offset(r.left, r.top),
          sensorOrientation,
          sW,
          sH,
          previewSize,
        ).translate(-cropOffset.dx, -cropOffset.dy);
        final bottomRight = _sensorToDisplay(
          ui.Offset(r.right, r.bottom),
          sensorOrientation,
          sW,
          sH,
          previewSize,
        ).translate(-cropOffset.dx, -cropOffset.dy);

        // Draw a rectangle from topLeft to the bottom of the name strip.
        final stripHeight = (bottomRight.dy - topLeft.dy) * nameStripFraction;
        canvas.drawRect(
          ui.Rect.fromLTWH(
            topLeft.dx,
            topLeft.dy,
            bottomRight.dx - topLeft.dx,
            stripHeight,
          ),
          stripPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(CardBorderPainter old) =>
      !listEquals(old.rects, rects)             ||
      old.imageSize          != imageSize        ||
      old.previewSize        != previewSize      ||
      old.sensorOrientation  != sensorOrientation ||
      old.nameStripFraction  != nameStripFraction ||
      old.cropOffset         != cropOffset;

  /// Transform a single point from sensor coordinates to display coordinates.
  /// Applies the same rotation transformation that [CameraPreview] uses.
  static ui.Offset _sensorToDisplay(
    ui.Offset sensorPt,
    int sensorOrientation,
    double sW,
    double sH,
    Size previewSize,
  ) {
    switch (sensorOrientation) {
      case 90:
        final sx = previewSize.width / sH;
        final sy = previewSize.height / sW;
        return ui.Offset(
          (sH - sensorPt.dy - 1) * sx,
          sensorPt.dx * sy,
        );
      case 270:
        final sx = previewSize.width / sH;
        final sy = previewSize.height / sW;
        return ui.Offset(
          sensorPt.dy * sx,
          (sW - sensorPt.dx - 1) * sy,
        );
      case 180:
        final sx = previewSize.width / sW;
        final sy = previewSize.height / sH;
        return ui.Offset(
          (sW - sensorPt.dx - 1) * sx,
          (sH - sensorPt.dy - 1) * sy,
        );
      default: // 0° — no rotation
        final sx = previewSize.width / sW;
        final sy = previewSize.height / sH;
        return ui.Offset(sensorPt.dx * sx, sensorPt.dy * sy);
    }
  }
}
