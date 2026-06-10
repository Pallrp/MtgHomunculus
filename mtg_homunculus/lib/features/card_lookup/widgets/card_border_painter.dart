import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Paints card-border rectangles over a [CameraPreview] or edge-map widget.
///
/// [rects] are in **sensor/image coordinates**.  The painter applies the
/// same rotation transform that [CameraPreview] uses internally so the
/// overlaid rectangles align with the displayed image.
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
/// computed display coordinate so the drawn rect lands in viewport space.
/// Defaults to [Offset.zero] (correct for the frozen-frame painter where the
/// image is already scaled to fit the viewport via [BoxFit.contain]).
class CardBorderPainter extends CustomPainter {
  final List<ui.Rect> rects;
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

    for (final r in rects) {
      // Transform sensor-coordinate rect → display-coordinate rect.
      final ui.Rect display;
      switch (sensorOrientation) {
        case 90:
          final sx = previewSize.width  / sH;
          final sy = previewSize.height / sW;
          display  = ui.Rect.fromLTWH(
            (sH - r.top - r.height) * sx,
            r.left                  * sy,
            r.height                * sx,
            r.width                 * sy,
          );
        case 270:
          final sx = previewSize.width  / sH;
          final sy = previewSize.height / sW;
          display  = ui.Rect.fromLTWH(
            r.top                   * sx,
            (sW - r.left - r.width) * sy,
            r.height                * sx,
            r.width                 * sy,
          );
        case 180:
          final sx = previewSize.width  / sW;
          final sy = previewSize.height / sH;
          display  = ui.Rect.fromLTWH(
            (sW - r.left - r.width)  * sx,
            (sH - r.top  - r.height) * sy,
            r.width  * sx,
            r.height * sy,
          );
        default: // 0° — no rotation
          final sx = previewSize.width  / sW;
          final sy = previewSize.height / sH;
          display  = ui.Rect.fromLTWH(
            r.left * sx, r.top * sy, r.width * sx, r.height * sy,
          );
      }

      // Translate from display-space to viewport-space by subtracting the
      // crop offset (the amount of the rendered image that lies outside the
      // visible viewport on each side due to the cover-crop).
      final vp = display.translate(-cropOffset.dx, -cropOffset.dy);

      canvas.drawRect(vp, borderPaint);

      // Name-strip highlight band — top [nameStripFraction] of the card rect.
      if (nameStripFraction > 0) {
        canvas.drawRect(
          ui.Rect.fromLTWH(
            vp.left,
            vp.top,
            vp.width,
            vp.height * nameStripFraction,
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
}
