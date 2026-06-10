import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/logging/app_logger.dart';
import '../models/detector_params.dart';
import 'yuv_converter.dart';

/// Runs OpenCV contour detection on a raw camera frame and returns
/// axis-aligned bounding boxes for every region whose aspect ratio matches
/// an MTG card.
///
/// All methods are static — no instance needed.
///
/// **Normal use:** [detectBorders] — returns border rects only.
/// **Debug use:**  [detectBordersDebug] — returns border rects AND the
/// dilated Canny edge map encoded as a PNG, pre-rotated to display orientation
/// so it can be shown directly in an [Image.memory] widget.
class CardDetector {
  CardDetector._();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Detect card borders in [frame].
  ///
  /// [params] defaults to [DetectorParams.current] when omitted.
  ///
  /// Returns bounding boxes in **sensor/image coordinates**.
  /// Returns an empty list on any OpenCV error (logged at warning level).
  static Future<List<ui.Rect>> detectBorders(
    CameraImage frame, {
    DetectorParams? params,
  }) async {
    final (rects, _) = await _run(
      frame,
      params ?? DetectorParams.current,
    );
    return rects;
  }

  /// Debug variant: same detection as [detectBorders] but also returns the
  /// dilated Canny edge map as a PNG [Uint8List], pre-rotated to display
  /// orientation for use with [Image.memory].
  ///
  /// The extra rotation + encoding adds a small overhead (~5–15 ms at medium
  /// resolution).  Use only in debug/tuning mode.
  static Future<(List<ui.Rect>, Uint8List)> detectBordersDebug(
    CameraImage frame, {
    DetectorParams? params,
    required int sensorOrientation,
  }) async {
    final (rects, edgeMap) = await _run(
      frame,
      params ?? DetectorParams.current,
      returnEdgeMap:     true,
      sensorOrientation: sensorOrientation,
    );
    // edgeMap is non-null when returnEdgeMap: true.
    return (rects, edgeMap!);
  }

  // ---------------------------------------------------------------------------
  // Core detection
  // ---------------------------------------------------------------------------

  /// Runs the full detection pipeline.
  ///
  /// When [returnEdgeMap] is true, the dilated edge map is rotated to display
  /// orientation and encoded as PNG bytes; the second tuple element is null
  /// otherwise (no encoding overhead on the normal code path).
  static Future<(List<ui.Rect>, Uint8List?)> _run(
    CameraImage frame,
    DetectorParams p, {
    bool returnEdgeMap     = false,
    int  sensorOrientation = 0,
  }) async {
    cv.Mat? nv21Mat, bgrMat, grayMat, blurMat, edgeMat,
            dilatedMat, kernel, rotatedEdge;
    try {
      // 1 — Convert YUV_420_888 → NV21 → BGR Mat.
      final nv21 = YuvConverter.yuv420ToNv21(frame);
      nv21Mat = cv.Mat.fromList(
        frame.height + frame.height ~/ 2,
        frame.width,
        cv.MatType.CV_8UC1,
        nv21.toList(),
      );
      bgrMat = cv.cvtColor(nv21Mat, cv.COLOR_YUV2BGR_NV21);

      // 2 — Grayscale + Gaussian blur to suppress texture noise.
      grayMat = cv.cvtColor(bgrMat, cv.COLOR_BGR2GRAY);
      blurMat = cv.gaussianBlur(
        grayMat,
        (p.blurKernelSize, p.blurKernelSize),
        0,
      );

      // 3 — Canny edge detection.
      edgeMat = cv.canny(blurMat, p.cannyLow, p.cannyHigh);

      // 4 — Dilate edge map to close small gaps in the card border.
      kernel     = cv.Mat.ones(p.dilationKernelSize, p.dilationKernelSize, cv.MatType.CV_8UC1);
      dilatedMat = cv.dilate(edgeMat, kernel, iterations: p.dilationIterations);

      // 4b — Optionally capture the edge map before contour detection consumes it.
      Uint8List? edgeMapPng;
      if (returnEdgeMap) {
        rotatedEdge = switch (sensorOrientation) {
          90  => cv.rotate(dilatedMat, cv.ROTATE_90_CLOCKWISE),
          270 => cv.rotate(dilatedMat, cv.ROTATE_90_COUNTERCLOCKWISE),
          180 => cv.rotate(dilatedMat, cv.ROTATE_180),
          _   => dilatedMat, // 0° — no copy, same mat, don't dispose separately
        };
        final (ok, encoded) = cv.imencode('.png', rotatedEdge);
        if (ok) edgeMapPng = Uint8List.fromList(encoded.toList());
        // If rotation produced a new mat, keep it in rotatedEdge for disposal.
        // If 0°, rotatedEdge == dilatedMat; set to null so we don't double-dispose.
        if (sensorOrientation == 0) rotatedEdge = null;
      }

      // 5 — Find external contours on the dilated edge map.
      final (contours, _) = cv.findContours(
        dilatedMat,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );

      // 6 — Filter by area, 4-corner quadrilateral shape, and aspect ratio.
      final frameArea = frame.width * frame.height;
      final results   = <ui.Rect>[];
      for (int i = 0; i < contours.length; i++) {
        final area = cv.contourArea(contours[i]);
        if (area < p.minArea) continue;
        if (area > frameArea * p.maxAreaFraction) continue;

        final perimeter = cv.arcLength(contours[i], true);
        final approx    = cv.approxPolyDP(
          contours[i],
          p.polyEpsilonFraction * perimeter,
          true,
        );
        if (approx.length != 4) continue;
        if (!cv.isContourConvex(approx)) continue;

        final r     = cv.boundingRect(approx);
        final ratio = r.width / r.height;
        if ((ratio >= p.minRatioPort && ratio <= p.maxRatioPort) ||
            (ratio >= p.minRatioLand && ratio <= p.maxRatioLand)) {
          results.add(ui.Rect.fromLTWH(
            r.x.toDouble(),
            r.y.toDouble(),
            r.width.toDouble(),
            r.height.toDouble(),
          ));
        }
      }
      return (results, edgeMapPng);
    } catch (e, st) {
      AppLogger.w('CardDetector: OpenCV error', error: e, stackTrace: st);
      return (const <ui.Rect>[], null);
    } finally {
      nv21Mat?.dispose();
      bgrMat?.dispose();
      grayMat?.dispose();
      blurMat?.dispose();
      edgeMat?.dispose();
      dilatedMat?.dispose();
      kernel?.dispose();
      rotatedEdge?.dispose(); // null when sensorOrientation==0 or returnEdgeMap==false
    }
  }
}
