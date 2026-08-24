import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/logging/app_logger.dart';
import 'yuv_converter.dart';

/// Warps a detected card quad to a canonical, front-facing rectangle.
///
/// The output size is **488 × 680** — exactly what Scryfall serves as
/// `image_uris.normal`, for *every* card regardless of layout. Normalising both
/// sides to the same frame means no layout-dependent processing: full-art,
/// Secret Lair, saga and split cards are all handled identically, and a
/// perceptual hash can compare a capture against a reference directly.
class CardWarp {
  CardWarp._();

  /// Canonical card size. Matches Scryfall `image_uris.normal`.
  static const int width  = 488;
  static const int height = 680;

  /// Collector-number region, as fractions of the canonical card.
  ///
  /// Values found empirically in spike S1 (2026-08-21) — the band covering
  /// `180/279 C` and the set/language line beneath it.
  static const double collectorX = 0.03;
  static const double collectorY = 0.895;
  static const double collectorW = 0.44;
  static const double collectorH = 0.09;

  // ---------------------------------------------------------------------------
  // Corner ordering
  // ---------------------------------------------------------------------------

  /// Reorder four corners to **top-left, top-right, bottom-right, bottom-left**
  /// in *image space*.
  ///
  /// Note this says nothing about which end of the *card* is up — a card lying
  /// upside down in frame yields an upside-down warp. Orientation detection is
  /// a separate concern; see `single_card_capture_flow.md`.
  static List<ui.Offset> orderCorners(List<ui.Offset> c) {
    if (c.length != 4) return c;
    var tl = c[0], br = c[0], tr = c[0], bl = c[0];
    for (final p in c) {
      if (p.dx + p.dy < tl.dx + tl.dy) tl = p;
      if (p.dx + p.dy > br.dx + br.dy) br = p;
      if (p.dx - p.dy > tr.dx - tr.dy) tr = p;
      if (p.dx - p.dy < bl.dx - bl.dy) bl = p;
    }
    return [tl, tr, br, bl];
  }

  // ---------------------------------------------------------------------------
  // Warp
  // ---------------------------------------------------------------------------

  /// Warp the quad described by [corners] out of [bgr] into a canonical card.
  ///
  /// [corners] must be in **[bgr] pixel coordinates**. Returns null on failure.
  /// **The caller owns the returned Mat and must dispose it.**
  static cv.Mat? toCanonical(cv.Mat bgr, List<ui.Offset> corners) {
    if (corners.length != 4) return null;
    final o = orderCorners(corners);

    final topLen  = _dist(o[0], o[1]);
    final sideLen = _dist(o[1], o[2]);
    if (topLen <= 0 || sideLen <= 0) return null;

    // A card lying sideways in frame: warp to a landscape canvas, then rotate
    // upright, rather than stretching it into a portrait one.
    final landscape = topLen > sideLen;
    final outW = landscape ? height : width;
    final outH = landscape ? width  : height;

    cv.VecPoint2f? src, dst;
    cv.Mat? m, warped;
    try {
      src = cv.VecPoint2f.fromList([
        cv.Point2f(o[0].dx, o[0].dy),
        cv.Point2f(o[1].dx, o[1].dy),
        cv.Point2f(o[2].dx, o[2].dy),
        cv.Point2f(o[3].dx, o[3].dy),
      ]);
      dst = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(outW - 1, 0),
        cv.Point2f(outW - 1, outH - 1),
        cv.Point2f(0, outH - 1),
      ]);
      m = cv.getPerspectiveTransform2f(src, dst);
      warped = cv.warpPerspective(bgr, m, (outW, outH));

      if (!landscape) {
        final out = warped;
        warped = null; // ownership passes to the caller
        return out;
      }
      final rotated = cv.rotate(warped, cv.ROTATE_90_CLOCKWISE);
      return rotated;
    } catch (e, st) {
      AppLogger.w('CardWarp: perspective transform failed', error: e, stackTrace: st);
      return null;
    } finally {
      src?.dispose();
      dst?.dispose();
      m?.dispose();
      warped?.dispose();
    }
  }

  /// Convenience: convert [frame] to BGR and warp in one step.
  ///
  /// [corners] must be in **sensor/frame coordinates**, which is what
  /// `CardDetector` returns. Caller disposes the result.
  static cv.Mat? fromCameraImage(CameraImage frame, List<ui.Offset> corners) {
    cv.Mat? nv21, bgr;
    try {
      final bytes = YuvConverter.yuv420ToNv21(frame);
      nv21 = cv.Mat.fromList(
        frame.height + frame.height ~/ 2,
        frame.width,
        cv.MatType.CV_8UC1,
        bytes.toList(),
      );
      bgr = cv.cvtColor(nv21, cv.COLOR_YUV2BGR_NV21);
      return toCanonical(bgr, corners);
    } catch (e, st) {
      AppLogger.w('CardWarp: frame conversion failed', error: e, stackTrace: st);
      return null;
    } finally {
      nv21?.dispose();
      bgr?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Regions
  // ---------------------------------------------------------------------------

  /// The collector-number band of a canonical card.
  ///
  /// Returns a **region view** of [card] — same lifetime, do not dispose
  /// separately.
  static cv.Mat collectorBand(cv.Mat card) {
    final x = (card.cols * collectorX).round().clamp(0, card.cols - 1);
    final y = (card.rows * collectorY).round().clamp(0, card.rows - 1);
    final w = (card.cols * collectorW).round().clamp(1, card.cols - x);
    final h = (card.rows * collectorH).round().clamp(1, card.rows - y);
    return card.region(cv.Rect(x, y, w, h));
  }

  /// Encode a Mat to PNG bytes for display, or null on failure.
  static Uint8List? encodePng(cv.Mat m) {
    try {
      final (ok, bytes) = cv.imencode('.png', m);
      return ok ? Uint8List.fromList(bytes.toList()) : null;
    } catch (_) {
      return null;
    }
  }

  /// Pixels per millimetre across the card's long edge, from a detected quad.
  ///
  /// A Magic card is 88mm on its long edge. Useful for judging whether a
  /// capture carries enough resolution for OCR — measured in spike S1, the
  /// collector number needs roughly **6 px/mm**.
  static double pixelsPerMm(List<ui.Offset> corners) {
    if (corners.length != 4) return 0;
    final o = orderCorners(corners);
    final longEdge = math.max(_dist(o[0], o[1]), _dist(o[1], o[2]));
    return longEdge / 88.0;
  }

  static double _dist(ui.Offset a, ui.Offset b) =>
      math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));
}
