import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../models/scan_result.dart';
import '../models/scryfall_card.dart';
import 'scryfall_client.dart';
import 'yuv_converter.dart';

/// Orchestrates the post-capture identification pipeline for each detected
/// card border.
///
/// For each border rect (sequentially, to respect Scryfall's rate limit):
///   1. Crop the bounding box from the raw sensor frame.
///   2. Orient the crop to display orientation and extract the name strip
///      (top ~12% of the card face).
///   3. Encode to JPEG and run ML Kit text recognition (OCR).
///   4. Call [ScryfallClient.namedFuzzy] with the OCR result.
///   5. On a match: call [onCardAdded] to persist the card, return
///      [MatchedResult].  On 404 or empty OCR: return [FailedResult].
///
/// All methods are static — no instance needed.
class ScanPipeline {
  ScanPipeline._();

  /// Default name-strip fraction used when callers do not supply one.
  static const double _defaultNameStripFraction = 0.15;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Run the pipeline over [borders] (sensor-coordinate rects from the last
  /// captured frame), calling [onResult] after each card resolves.
  ///
  /// [sensorOrientation] is taken from [CameraDescription.sensorOrientation]
  /// and drives the name-strip crop direction.
  ///
  /// [onCardAdded] may be null (e.g. Quick Scan without a listing).  In that
  /// case matched cards still produce a [MatchedResult] but are not persisted;
  /// [MatchedResult.listingCardId] will be an empty string.
  static Future<void> run({
    required CameraImage frame,
    required List<ui.Rect> borders,
    required int sensorOrientation,
    required void Function(int index, ScanResult result) onResult,
    Future<String> Function(ScryfallCard card)? onCardAdded,
    double nameStripFraction = _defaultNameStripFraction,
  }) async {
    // Reuse a single recogniser across all borders in the scan to avoid
    // re-initialising the ML Kit model for each card.
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      for (int i = 0; i < borders.length; i++) {
        final result = await _processOne(
          recognizer:        recognizer,
          frame:             frame,
          border:            borders[i],
          sensorOrientation: sensorOrientation,
          onCardAdded:       onCardAdded,
          nameStripFraction: nameStripFraction,
        );
        onResult(i, result);
      }
    } finally {
      await recognizer.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Per-card processing
  // ---------------------------------------------------------------------------

  static Future<ScanResult> _processOne({
    required TextRecognizer recognizer,
    required CameraImage frame,
    required ui.Rect border,
    required int sensorOrientation,
    required Future<String> Function(ScryfallCard)? onCardAdded,
    double nameStripFraction = _defaultNameStripFraction,
  }) async {
    // ── Step 1: OCR the name strip ───────────────────────────────────────────
    final ocrText = await _ocrNameStrip(
      recognizer:        recognizer,
      frame:             frame,
      sensorBorder:      border,
      sensorOrientation: sensorOrientation,
      nameStripFraction: nameStripFraction,
    );
    AppLogger.d('ScanPipeline: OCR → "$ocrText"');

    if (ocrText.isEmpty) return FailedResult(border, '');

    // ── Step 2: Scryfall fuzzy name lookup ───────────────────────────────────
    ScryfallCard? card;
    try {
      card = await ScryfallClient.namedFuzzy(ocrText);
    } catch (e, st) {
      AppLogger.w(
        'ScanPipeline: Scryfall error for "$ocrText"',
        error: e, stackTrace: st,
      );
      return FailedResult(border, ocrText);
    }

    if (card == null) {
      AppLogger.d('ScanPipeline: no Scryfall match for "$ocrText"');
      return FailedResult(border, ocrText);
    }

    // ── Step 3: Persist to listing (if callback provided) ────────────────────
    String listingCardId = '';
    if (onCardAdded != null) {
      try {
        listingCardId = await onCardAdded(card);
      } catch (e, st) {
        AppLogger.w(
          'ScanPipeline: onCardAdded failed for "${card.name}"',
          error: e, stackTrace: st,
        );
        // Still return a MatchedResult; the caller can retry adding manually.
        return MatchedResult(border, card, '');
      }
    }

    AppLogger.i('ScanPipeline: matched "${card.name}" → listingCardId: '
        '"${listingCardId.isEmpty ? "not persisted" : listingCardId}"');
    return MatchedResult(border, card, listingCardId);
  }

  // ---------------------------------------------------------------------------
  // OCR helpers
  // ---------------------------------------------------------------------------

  /// Crop the name strip from [frame], orient it for legibility, encode to
  /// JPEG, and run ML Kit text recognition.
  ///
  /// Returns the trimmed OCR text, or an empty string on any error.
  static Future<String> _ocrNameStrip({
    required TextRecognizer recognizer,
    required CameraImage frame,
    required ui.Rect sensorBorder,
    required int sensorOrientation,
    double nameStripFraction = _defaultNameStripFraction,
  }) async {
    cv.Mat? nv21Mat, bgrMat, displayCropMat;
    File?   tempFile;
    try {
      // 1 — Decode the YUV frame into a BGR Mat.
      final nv21 = YuvConverter.yuv420ToNv21(frame);
      nv21Mat = cv.Mat.fromList(
        frame.height + frame.height ~/ 2,
        frame.width,
        cv.MatType.CV_8UC1,
        nv21.toList(),
      );
      bgrMat = cv.cvtColor(nv21Mat, cv.COLOR_YUV2BGR_NV21);

      // 2 — Crop the card bounding box (clamped to frame bounds).
      final left   = sensorBorder.left.toInt().clamp(0, frame.width  - 1);
      final top    = sensorBorder.top.toInt().clamp(0, frame.height - 1);
      final width  = sensorBorder.width.toInt().clamp(1, frame.width  - left);
      final height = sensorBorder.height.toInt().clamp(1, frame.height - top);
      // cardCropMat is a region view of bgrMat — same lifetime, no separate dispose.
      final cardCropMat = bgrMat.region(cv.Rect(left, top, width, height));

      // 3 — Rotate crop to display orientation so the name is always at the top.
      //     For sensorOrientation=0 no rotation is needed; work directly on the view.
      final cv.Mat workMat;
      if (sensorOrientation != 0) {
        displayCropMat = _rotateToDisplay(cardCropMat, sensorOrientation);
        workMat        = displayCropMat;
      } else {
        workMat = cardCropMat;
      }

      // 4 — Extract the name strip: top [nameStripFraction] rows of the
      //     display-oriented crop.
      //     nameStripView is a region view of workMat — same lifetime.
      final stripH       = (workMat.rows * nameStripFraction).toInt().clamp(1, workMat.rows);
      final nameStripView = workMat.region(cv.Rect(0, 0, workMat.cols, stripH));

      // 5 — Encode to JPEG and write to a temp file for ML Kit.
      final (success, encoded) = cv.imencode('.jpg', nameStripView);
      if (!success) return '';

      final dir  = await getTemporaryDirectory();
      tempFile   = File('${dir.path}/ns_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(encoded.toList());

      // 6 — OCR.
      final result = await recognizer.processImage(
        InputImage.fromFilePath(tempFile.path),
      );
      return result.text.trim();
    } catch (e, st) {
      AppLogger.w(
        'ScanPipeline: OCR error for border $sensorBorder',
        error: e, stackTrace: st,
      );
      return '';
    } finally {
      nv21Mat?.dispose();
      bgrMat?.dispose();
      displayCropMat?.dispose();
      try { await tempFile?.delete(); } catch (_) {}
    }
  }

  /// Rotate [crop] so that the card face is in display orientation
  /// (name strip at the top, reading left-to-right).
  ///
  /// The returned Mat is a new allocation — the caller must dispose it.
  static cv.Mat _rotateToDisplay(cv.Mat crop, int sensorOrientation) {
    // Sensor orientation tells us the angle the sensor delivers frames at,
    // relative to the natural device orientation.
    //
    //  sensorOrientation=90  → sensor is 90° CW vs display
    //    → rotate crop 90° CW to correct (left columns become top rows)
    //  sensorOrientation=270 → sensor is 90° CCW vs display
    //    → rotate crop 90° CCW
    //  sensorOrientation=180 → sensor is upside-down
    //    → rotate crop 180°
    switch (sensorOrientation) {
      case 90:  return cv.rotate(crop, cv.ROTATE_90_CLOCKWISE);
      case 270: return cv.rotate(crop, cv.ROTATE_90_COUNTERCLOCKWISE);
      case 180: return cv.rotate(crop, cv.ROTATE_180);
      default:  // 0° — caller guarantees this branch is not reached
        return crop;
    }
  }
}
