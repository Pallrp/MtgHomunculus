import 'dart:math' show atan2, cos, max, min, sin, sqrt;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/logging/app_logger.dart';
import '../models/detector_params.dart';
import '../models/rotated_card_rect.dart';
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

  /// Detection never needs more than this on the frame's short side.
  ///
  /// Hough finds card borders perfectly well at 720, and capping it is what
  /// keeps a high capture resolution affordable — the per-frame cost stops
  /// scaling once the stream goes past this.
  ///
  /// Measured 2026-08-21: at `ResolutionPreset.high` the stream is already
  /// 1280×720, so no downscale happens at all and corners are found at native
  /// resolution. Above that, corners are found on a downscaled copy and scaled
  /// back up — which multiplies corner error with them.
  static const int detectShortSide = 720;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Detect card borders in [frame].
  ///
  /// [params] defaults to [DetectorParams.current] when omitted.
  ///
  /// Returns rotated card rectangles in **sensor/image coordinates**.
  /// Returns an empty list on any OpenCV error (logged at warning level).
  static Future<List<RotatedCardRect>> detectBorders(
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
  static Future<(List<RotatedCardRect>, Uint8List)> detectBordersDebug(
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

  /// Detect card borders in [frame] after cropping to match screen aspect ratio.
  /// Used for snapshot detection to ensure corners are in displayable coordinates.
  ///
  /// [screenWidth] and [screenHeight] are used to calculate the crop rectangle.
  /// Returns corners in cropped-frame coordinates (no transformation needed for display).
  /// Also returns the crop rectangle for cropping the JPEG display.
  static Future<(List<RotatedCardRect>, ui.Rect)> detectBordersForSnapshot(
    CameraImage frame, {
    required double screenWidth,
    required double screenHeight,
    DetectorParams? params,
  }) async {
    // Calculate how to crop the frame to match screen aspect ratio
    final cropRect = _calculateCropRect(
      frameWidth: frame.width,
      frameHeight: frame.height,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
    );

    // Detect on full frame (faster than pixel-level cropping)
    final (rects, _) = await _run(
      frame,
      params ?? DetectorParams.current,
    );

    // Adjust corner coordinates to be relative to the crop rectangle
    // (convert from full-frame coords to cropped-frame coords)
    final adjustedRects = rects.map((rect) {
      final adjustedCorners = rect.corners
          .map((corner) => ui.Offset(
                corner.dx - cropRect.left,
                corner.dy - cropRect.top,
              ))
          .toList();
      final adjustedBounds = ui.Rect.fromLTWH(
        rect.bounds.left - cropRect.left,
        rect.bounds.top - cropRect.top,
        rect.bounds.width,
        rect.bounds.height,
      );
      return RotatedCardRect(
        corners: adjustedCorners,
        bounds: adjustedBounds,
        rotationAngle: rect.rotationAngle,
      );
    }).toList();

    return (adjustedRects, cropRect);
  }

  // ---------------------------------------------------------------------------
  // Core detection
  // ---------------------------------------------------------------------------

  /// Runs the full detection pipeline.
  ///
  /// When [returnEdgeMap] is true, the dilated edge map is rotated to display
  /// orientation and encoded as PNG bytes; the second tuple element is null
  /// otherwise (no encoding overhead on the normal code path).
  static Future<(List<RotatedCardRect>, Uint8List?)> _run(
    CameraImage frame,
    DetectorParams p, {
    bool returnEdgeMap     = false,
    int  sensorOrientation = 0,
  }) async {
    cv.Mat? nv21Mat, bgrMat;
    try {
      // Convert YUV_420_888 → NV21 → BGR, then hand off to the Mat pipeline.
      final nv21 = YuvConverter.yuv420ToNv21(frame);
      nv21Mat = cv.Mat.fromList(
        frame.height + frame.height ~/ 2,
        frame.width,
        cv.MatType.CV_8UC1,
        nv21.toList(),
      );
      bgrMat = cv.cvtColor(nv21Mat, cv.COLOR_YUV2BGR_NV21);

      // Detect on a downscaled copy when the frame is larger than needed, then
      // lift the corners back into full-frame coordinates. Transparent to
      // callers: rects always come back in [frame] pixel space.
      final short = min(bgrMat.rows, bgrMat.cols);
      if (short > detectShortSide) {
        final scale = detectShortSide / short;
        cv.Mat? smallMat;
        try {
          smallMat = cv.resize(bgrMat, (
            (bgrMat.cols * scale).round(),
            (bgrMat.rows * scale).round(),
          ));
          final (rects, edgeMap) = await detectFromBgr(
            smallMat,
            p,
            returnEdgeMap:     returnEdgeMap,
            sensorOrientation: sensorOrientation,
          );
          return (_scaleRects(rects, 1 / scale), edgeMap);
        } finally {
          smallMat?.dispose();
        }
      }

      return await detectFromBgr(
        bgrMat,
        p,
        returnEdgeMap:     returnEdgeMap,
        sensorOrientation: sensorOrientation,
      );
    } catch (e, st) {
      AppLogger.w('CardDetector: YUV conversion failed', error: e, stackTrace: st);
      return (const <RotatedCardRect>[], null);
    } finally {
      nv21Mat?.dispose();
      bgrMat?.dispose();
    }
  }

  /// Multiply every corner and bound by [factor].
  ///
  /// Used to lift rects found on a downscaled copy back into full-frame
  /// coordinates.
  static List<RotatedCardRect> _scaleRects(
    List<RotatedCardRect> rects,
    double factor,
  ) {
    if (factor == 1.0) return rects;
    return rects
        .map((r) => RotatedCardRect(
              corners: r.corners
                  .map((c) => ui.Offset(c.dx * factor, c.dy * factor))
                  .toList(),
              bounds: ui.Rect.fromLTWH(
                r.bounds.left * factor,
                r.bounds.top * factor,
                r.bounds.width * factor,
                r.bounds.height * factor,
              ),
              rotationAngle: r.rotationAngle,
            ))
        .toList();
  }

  /// Detection pipeline on an already-decoded **BGR** [bgr] Mat.
  ///
  /// Split out from [_run] so detection can run on any source — a camera stream
  /// frame, a still captured with `takePicture()`, or a downscaled copy — rather
  /// than only on a [CameraImage].  Caller owns [bgr] and disposes it.
  ///
  /// Returns rects in **[bgr] pixel coordinates**.
  static Future<(List<RotatedCardRect>, Uint8List?)> detectFromBgr(
    cv.Mat bgr,
    DetectorParams p, {
    bool returnEdgeMap     = false,
    int  sensorOrientation = 0,
  }) async {
    cv.Mat? grayMat, blurMat, edgeMat, dilatedMat, kernel, rotatedEdge;
    try {
      // 1 — Resolve fractional params against this frame.
      //
      // The SHORT side is the orientation-independent measure: a portrait card
      // is bounded by frame height in a landscape stream frame and by frame
      // width in a portrait still. Resolving here means one set of tuning
      // values holds across every resolution and orientation.
      final b = _Bounds.resolve(bgr, p);

      // 2 — Grayscale + Gaussian blur to suppress texture noise.
      grayMat = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
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

      final funnel = _Funnel.maybeStart(bgr.cols, bgr.rows, p);

      // 5 — Contours propose.
      //
      // A contour is a *connected* boundary, so one contour is one candidate.
      // There is no combination step, and therefore no way to assemble a
      // rectangle out of lines belonging to different objects -- which is the
      // mechanism that produces phantoms in the Hough path.
      //
      // This ran second until 2026-08-24, reached only when Hough returned zero
      // lines. That ordering is why houghMinLineLength=247 "worked": it starved
      // HoughLinesP into silence so control fell through to here.
      final contourRects = _detectFromContours(
        dilatedMat, bgr.cols, bgr.rows, p, b, funnel,
      );
      if (contourRects.isNotEmpty) {
        funnel?.recordPath('contour');
        funnel?.emit();
        return (contourRects, edgeMapPng);
      }

      // 6 — Hough rescues.
      //
      // Only reached when contours proposed nothing -- a broken border, too
      // little contrast, a boundary that never closed. Gaps are what Hough
      // tolerates and contours cannot, so this is the job it is actually
      // suited to.
      final houghRects = _detectFromHough(
        dilatedMat, bgr.cols, bgr.rows, p, b, funnel,
      );
      funnel?.recordPath(houghRects.isEmpty ? 'none' : 'hough');
      funnel?.emit();
      return (houghRects, edgeMapPng);
    } catch (e, st) {
      AppLogger.w('CardDetector: OpenCV error', error: e, stackTrace: st);
      return (const <RotatedCardRect>[], null);
    } finally {
      grayMat?.dispose();
      blurMat?.dispose();
      edgeMat?.dispose();
      dilatedMat?.dispose();
      kernel?.dispose();
      rotatedEdge?.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Hough line detection helper
  // ---------------------------------------------------------------------------

  /// Angle tolerance (degrees) for treating two lines as the same direction.
  static const double _angleTolDeg = 8;

  /// Perpendicular-offset tolerance (px) for treating two same-direction lines
  /// as duplicate detections of a single physical edge.
  static const double _offsetTolPx = 12;

  /// Minimum angular separation (degrees) between the two line families.
  /// Below this the resulting "quad" degenerates into a sliver.
  static const double _minFamilySepDeg = 30;

  /// Max lines kept per family — caps combinations at C(6,2)^2 = 225.
  ///
  /// Must be generous enough that a card sharing the frame with a larger object
  /// still gets its (shorter) edges into the candidate set; the aspect filter
  /// discards the resulting bad combinations cheaply.
  static const int _maxPerFamily = 8;

  /// Fraction of the frame size an intersection may fall outside before it is
  /// treated as spurious.  Non-zero so cards running past the frame edge still
  /// resolve their off-screen corners.
  static const double _cornerMarginFraction = 0.25;

  /// Short/long side ratio of a real Magic card: 63mm x 88mm.
  static const double _kCardAspect = 63 / 88;

  /// Card-likeness scores closer together than this are treated as tied, and
  /// broken by size instead.  Sized to exceed the gap between a card and its
  /// own inner features (~0.02) while staying well under the gap to a
  /// non-card shape such as a binder page (~0.17).
  static const double _likenessTieBand = 0.06;

  /// Fraction of the smaller quad that must be shared before overlap
  /// suppression discards it.  Measured against the *smaller* area rather than
  /// the union so a small quad fully inside a large one is also suppressed,
  /// while two adjacent cards — which barely overlap — both survive.
  static const double _nmsOverlapFraction = 0.6;

  /// Minimum quad-area / bounding-box-area ratio.  A true rectangle scores 1.0
  /// axis-aligned and ~0.5 at 45 degrees; slivers score near zero.
  static const double _minFillRatio = 0.25;

  static const double _degToRad = 3.141592653589793 / 180;

  static List<RotatedCardRect> _detectCardsFromHoughLines(
    cv.Mat lines,
    int frameWidth,
    int frameHeight,
    DetectorParams p,
    _Bounds b,
    _Funnel? funnel,
  ) {
    // 1 — Extract raw segments, longest first.
    final raw = <_Seg>[];
    for (int i = 0; i < lines.rows; i++) {
      raw.add(_Seg.fromPoints(
        lines.at<int>(i, 0).toDouble(),
        lines.at<int>(i, 1).toDouble(),
        lines.at<int>(i, 2).toDouble(),
        lines.at<int>(i, 3).toDouble(),
      ));
    }
    raw.sort((a, b) => b.length.compareTo(a.length));

    funnel?.recordLines(lines.rows, raw.take(8).toList());

    // 2 — Merge collinear duplicates.  Dilation plus the physical thickness of
    // a card border make HoughLinesP emit several near-identical segments per
    // edge; without this the candidate set is many copies of the same line.
    final merged = _mergeCollinearLines(raw);

    // 3 — Split into two direction families.  A quadrilateral needs two
    // distinct directions, and ranking purely by length collapses onto one.
    final families = _splitAngleFamilies(merged);
    funnel?.recordFamilies(merged.length, families);
    if (families == null) return const [];

    final famA = families.$1;
    final famB = families.$2;

    // 4 — Two lines from each family bound a quadrilateral.  Intersections use
    // the *infinite* lines: Hough segments end where edge pixels run out —
    // typically short of the corner — so requiring segment overlap would
    // discard exactly the gap tolerance Hough was chosen for.
    final results = <RotatedCardRect>[];
    for (int i = 0; i < famA.length - 1; i++) {
      for (int j = i + 1; j < famA.length; j++) {
        for (int k = 0; k < famB.length - 1; k++) {
          for (int l = k + 1; l < famB.length; l++) {
            final quad = _quadFromLinePairs(
              famA[i], famA[j], famB[k], famB[l],
              frameWidth, frameHeight, p, b, funnel,
            );
            if (quad != null) results.add(quad);
          }
        }
      }
    }

    return results;
  }

  /// Collapse segments lying on the same infinite line into one.
  ///
  /// Two segments merge when their directions agree within [_angleTolDeg] and
  /// their perpendicular offsets within [_offsetTolPx].  The representative
  /// spans the full extent of the group along the shared direction, which also
  /// bridges gaps that [cv.HoughLinesP] left as separate segments.
  static List<_Seg> _mergeCollinearLines(List<_Seg> segs) {
    final merged = <_Seg>[];
    final used = List<bool>.filled(segs.length, false);

    for (int i = 0; i < segs.length; i++) {
      if (used[i]) continue;
      used[i] = true;

      // segs is length-sorted, so segs[i] is the strongest of its group and
      // anchors the match.
      final group = <_Seg>[segs[i]];
      for (int j = i + 1; j < segs.length; j++) {
        if (used[j]) continue;
        if (_angleDiffDeg(segs[i].angleDeg, segs[j].angleDeg) > _angleTolDeg) continue;
        if ((segs[i].rho - _offsetAlong(segs[i], segs[j])).abs() > _offsetTolPx) continue;
        group.add(segs[j]);
        used[j] = true;
      }

      merged.add(group.length == 1 ? segs[i] : _spanOf(group, segs[i]));
    }

    return merged;
  }

  /// Perpendicular offset of [other] measured against the normal of [anchor].
  ///
  /// Each segment stores its own [_Seg.rho] against its own normal, and that
  /// normal flips sign across the 0/180 degree wrap — so two nearly-horizontal
  /// segments on the same edge can land at +rho and -rho and fail to merge.
  /// Measuring both against a single normal removes the discontinuity.
  static double _offsetAlong(_Seg anchor, _Seg other) {
    final th = anchor.angleDeg * _degToRad;
    final mx = (other.x1 + other.x2) / 2;
    final my = (other.y1 + other.y2) / 2;
    return -mx * sin(th) + my * cos(th);
  }

  /// Build the segment spanning [group] along the direction of [anchor].
  static _Seg _spanOf(List<_Seg> group, _Seg anchor) {
    final th = anchor.angleDeg * _degToRad;
    final dx = cos(th);
    final dy = sin(th);

    // Length-weighted mean offset, so the strongest segments dominate where
    // the merged line sits.
    double rhoSum = 0, wSum = 0;
    for (final s in group) {
      rhoSum += _offsetAlong(anchor, s) * s.length;
      wSum   += s.length;
    }
    final rho = wSum > 0 ? rhoSum / wSum : anchor.rho;

    double tMin = double.infinity, tMax = double.negativeInfinity;
    for (final s in group) {
      final ta = s.x1 * dx + s.y1 * dy;
      final tb = s.x2 * dx + s.y2 * dy;
      tMin = min(tMin, min(ta, tb));
      tMax = max(tMax, max(ta, tb));
    }

    // P(t) = t * direction + rho * normal, with normal = (-sin, cos).
    return _Seg.fromPoints(
      tMin * dx - rho * dy, tMin * dy + rho * dx,
      tMax * dx - rho * dy, tMax * dy + rho * dx,
    );
  }

  /// Partition [segs] into two direction families at least [_minFamilySepDeg]
  /// apart, each holding at least 2 lines.  Returns null when no such split
  /// exists — that frame cannot yield a quadrilateral at all.
  static (List<_Seg>, List<_Seg>)? _splitAngleFamilies(List<_Seg> segs) {
    if (segs.length < 4) return null;

    // segs arrives length-sorted; the longest line anchors the first family.
    final anchorA = segs.first;
    final famA = <_Seg>[];
    final rest = <_Seg>[];
    for (final s in segs) {
      if (_angleDiffDeg(s.angleDeg, anchorA.angleDeg) <= _angleTolDeg) {
        famA.add(s);
      } else {
        rest.add(s);
      }
    }
    if (famA.length < 2 || rest.length < 2) return null;

    // Anchor the second family on the longest remaining line far enough off
    // the direction of A to bound a non-degenerate quad.
    _Seg? anchorB;
    for (final s in rest) {
      if (_angleDiffDeg(s.angleDeg, anchorA.angleDeg) >= _minFamilySepDeg) {
        anchorB = s;
        break;
      }
    }
    if (anchorB == null) return null;

    final bAngle = anchorB.angleDeg;
    final famB = rest
        .where((s) => _angleDiffDeg(s.angleDeg, bAngle) <= _angleTolDeg)
        .toList();
    if (famB.length < 2) return null;

    return (
      famA.take(_maxPerFamily).toList(),
      famB.take(_maxPerFamily).toList(),
    );
  }

  /// Build a quadrilateral bounded by two lines from each family.
  static RotatedCardRect? _quadFromLinePairs(
    _Seg a1, _Seg a2, _Seg b1, _Seg b2,
    int frameWidth,
    int frameHeight,
    DetectorParams p,
    _Bounds b,
    _Funnel? funnel,
  ) {
    funnel?.recordCombo();

    final marginX = frameWidth * _cornerMarginFraction;
    final marginY = frameHeight * _cornerMarginFraction;

    // Walking a1 -> b1 -> a2 -> b2 visits the corners in cyclic order.
    final corners = <ui.Offset>[];
    for (final pair in [(a1, b1), (a1, b2), (a2, b2), (a2, b1)]) {
      final pt = _intersectInfinite(pair.$1, pair.$2);
      if (pt == null) return null;
      if (pt.dx < -marginX || pt.dx > frameWidth + marginX ||
          pt.dy < -marginY || pt.dy > frameHeight + marginY) {
        funnel?.recordOutOfBounds();
        return null;
      }
      corners.add(pt);
    }

    final ordered = _orderCornersClockwise(corners);
    final rect = _boundsFromCorners(ordered);

    // Reject slivers: two families can clear the separation gate and still
    // bound a quad with almost no interior.
    final boundsArea = rect.width * rect.height;
    if (boundsArea <= 0) return null;
    if (_computeQuadrilateralArea(ordered) / boundsArea < _minFillRatio) {
      funnel?.recordSliver();
      return null;
    }

    // Shape gate.  Measured on the quad's own edges, so unlike the axis-aligned
    // ratio this survives in-plane rotation; averaging opposite sides absorbs
    // most of the trapezoid distortion from a tilted phone.
    final aspect = _quadAspect(ordered);
    if (aspect < p.minCardAspect || aspect > p.maxCardAspect) {
      funnel?.recordAspectReject(aspect);
      return null;
    }

    if (!_validateCardRect(rect, frameWidth, frameHeight, p, b)) {
      funnel?.recordValidateReject(rect);
      return null;
    }

    funnel?.recordQuadFormed(aspect);
    return RotatedCardRect(
      corners: ordered,
      bounds: rect,
      rotationAngle: _calculateRotationAngle(ordered),
    );
  }

  // ---------------------------------------------------------------------------
  // Detection paths
  // ---------------------------------------------------------------------------

  /// Propose candidates from connected contours.
  ///
  /// Each surviving contour yields exactly one rect, so the candidate count is
  /// bounded by the number of distinct objects in the frame rather than by the
  /// combinatorics of line pairing.
  static List<RotatedCardRect> _detectFromContours(
    cv.Mat dilated,
    int frameWidth,
    int frameHeight,
    DetectorParams p,
    _Bounds b,
    _Funnel? funnel,
  ) {
    final (contours, _) = cv.findContours(
      dilated,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    final frameArea = frameWidth * frameHeight;
    final results   = <RotatedCardRect>[];
    var quads = 0, areaRej = 0, notQuad = 0, notConvex = 0;

    // Every contour's area, kept so the funnel can report the largest against
    // b.minArea. That ratio distinguishes the two readings of an areaRej-heavy
    // frame: a boundary that fragmented into sub-threshold pieces (largest
    // lands near the gate) from one that never formed at all (largest is
    // noise-sized). They need opposite fixes.
    final areas = <double>[];

    // Vertex count of every contour that clears the area gate. `notQuad`
    // alone cannot say which way approxPolyDP missed: too fine an epsilon
    // keeps every lump as a vertex (6, 7, 8...), too coarse collapses a corner
    // and lands below 4. The two want opposite moves on the slider.
    final verts = <int>[];

    for (int i = 0; i < contours.length; i++) {
      final area = cv.contourArea(contours[i]);
      areas.add(area);
      if (area < b.minArea) { areaRej++; continue; }
      if (area > frameArea * p.maxAreaFraction) { areaRej++; continue; }

      final perimeter = cv.arcLength(contours[i], true);
      final approx    = cv.approxPolyDP(
        contours[i],
        p.polyEpsilonFraction * perimeter,
        true,
      );
      // NOTE: this exact-four-corners test discards a card whose outline has one
      // nicked corner or a slight bend. Step C replaces it with a rectangularity
      // score; until then it is a competing explanation for any contour miss.
      verts.add(approx.length);
      if (approx.length != 4) { notQuad++; continue; }
      if (!cv.isContourConvex(approx)) { notConvex++; continue; }
      quads++;

      // Use the polygon's own vertices, NOT minAreaRect/boxPoints.
      //
      // A tilted card projects to a trapezoid — near edge longer than far edge
      // — and no rectangle can fit a trapezoid, so a bounding rect puts the
      // corners visibly off the card and the error grows with tilt. `approx`
      // already holds the real corners; CardWarp needs them to build a correct
      // perspective transform.
      final corners = <ui.Offset>[
        for (int k = 0; k < 4; k++)
          ui.Offset(approx[k].x.toDouble(), approx[k].y.toDouble()),
      ];
      final ordered = _orderCornersClockwise(corners);

      results.add(RotatedCardRect(
        corners: ordered,
        bounds: _boundsFromCorners(ordered),
        rotationAngle: _calculateRotationAngle(ordered),
      ));
    }

    final kept = _filterDetections(results, b, funnel);
    areas.sort((x, y) => y.compareTo(x));
    funnel?.recordContours(
      contours.length, areaRej, notQuad, notConvex, quads, kept.length,
      areas.take(3).toList(), b.minArea, verts,
    );
    return kept;
  }

  /// Propose candidates by pairing Hough lines.
  ///
  /// Returns an empty list rather than throwing, so a failure here falls
  /// through to "no detection" instead of taking the frame down.
  static List<RotatedCardRect> _detectFromHough(
    cv.Mat dilated,
    int frameWidth,
    int frameHeight,
    DetectorParams p,
    _Bounds b,
    _Funnel? funnel,
  ) {
    cv.Mat? linesMat;
    try {
      linesMat = cv.HoughLinesP(
        dilated,
        p.houghRho,
        p.houghTheta,
        p.houghThreshold,
        minLineLength: b.minLineLength,
        maxLineGap: p.houghMaxLineGap.toDouble(),
      );

      if (linesMat.rows == 0) {
        // Record explicitly: otherwise this failure mode is invisible.
        funnel?.recordLines(0, const []);
        return const [];
      }

      final results = _detectCardsFromHoughLines(
        linesMat, frameWidth, frameHeight, p, b, funnel,
      );
      return _filterDetections(results, b, funnel);
    } catch (e, st) {
      AppLogger.w('CardDetector: Hough path failed', error: e, stackTrace: st);
      return const [];
    } finally {
      linesMat?.dispose();
    }
  }

  /// Intersection of the two *infinite* lines through the given segments.
  /// Returns null when they are parallel.
  static ui.Offset? _intersectInfinite(_Seg a, _Seg b) {
    final dx1 = a.x2 - a.x1;
    final dy1 = a.y2 - a.y1;
    final dx2 = b.x2 - b.x1;
    final dy2 = b.y2 - b.y1;

    final cross = dx1 * dy2 - dy1 * dx2;
    if (cross.abs() < 1e-9) return null;

    final t = ((b.x1 - a.x1) * dy2 - (b.y1 - a.y1) * dx2) / cross;
    return ui.Offset(a.x1 + t * dx1, a.y1 + t * dy1);
  }

  /// Short/long side ratio of a quadrilateral, measured on its own edges.
  ///
  /// Opposite sides are averaged before the ratio is taken: perspective turns a
  /// tilted rectangle into a trapezoid where the near edge grows as much as the
  /// far edge shrinks, so the mean of the pair stays close to the true side.
  static double _quadAspect(List<ui.Offset> c) {
    if (c.length != 4) return 0;
    final sideA = ((c[0] - c[1]).distance + (c[2] - c[3]).distance) / 2;
    final sideB = ((c[1] - c[2]).distance + (c[3] - c[0]).distance) / 2;
    if (sideA <= 0 || sideB <= 0) return 0;
    return min(sideA, sideB) / max(sideA, sideB);
  }

  /// How far a detection departs from card proportions.  Lower is better.
  static double _cardLikeness(RotatedCardRect r) =>
      (_quadAspect(r.corners) - _kCardAspect).abs();

  /// Smallest angle between two undirected directions, in degrees (0–90).
  static double _angleDiffDeg(double a, double b) {
    final d = (a - b).abs() % 180;
    return d > 90 ? 180 - d : d;
  }

  /// Compute the area of a quadrilateral using the shoelace formula.
  static double _computeQuadrilateralArea(List<ui.Offset> corners) {
    if (corners.length != 4) return 0;

    double area = 0;
    for (int i = 0; i < 4; i++) {
      final p1 = corners[i];
      final p2 = corners[(i + 1) % 4];
      area += p1.dx * p2.dy - p2.dx * p1.dy;
    }
    return (area / 2).abs();
  }

  /// Compute axis-aligned bounds from corner points.
  static ui.Rect _boundsFromCorners(List<ui.Offset> corners) {
    final xs = corners.map((c) => c.dx);
    final ys = corners.map((c) => c.dy);

    final left = xs.reduce((a, b) => a < b ? a : b);
    final top = ys.reduce((a, b) => a < b ? a : b);
    final right = xs.reduce((a, b) => a > b ? a : b);
    final bottom = ys.reduce((a, b) => a > b ? a : b);

    return ui.Rect.fromLTRB(left, top, right, bottom);
  }

  /// Validate detected card rectangle by size and area.
  /// Aspect ratio filtering is deprecated (rotated cards have variable axis-aligned ratios).
  static bool _validateCardRect(
    ui.Rect rect,
    int frameWidth,
    int frameHeight,
    DetectorParams p,
    _Bounds b,
  ) {
    final area = rect.width * rect.height;
    final frameArea = frameWidth * frameHeight;

    // Check area bounds
    if (area < b.minArea) return false;
    if (area > frameArea * p.maxAreaFraction) return false;

    return true;
  }

  /// Reorder 4 corner points into a circular sequence (clockwise from top-left).
  /// This ensures the path drawn by connecting corners[0] → [1] → [2] → [3]
  /// forms a proper quadrilateral instead of a bowtie.
  static List<ui.Offset> _orderCornersClockwise(List<ui.Offset> corners) {
    if (corners.length != 4) return corners;

    // Find centroid
    final centerX = corners.map((p) => p.dx).reduce((a, b) => a + b) / 4;
    final centerY = corners.map((p) => p.dy).reduce((a, b) => a + b) / 4;
    final center = ui.Offset(centerX, centerY);

    // Sort by angle from center (clockwise from top)
    final sorted = [...corners];
    sorted.sort((a, b) {
      final angleA = atan2(a.dy - center.dy, a.dx - center.dx);
      final angleB = atan2(b.dy - center.dy, b.dx - center.dx);
      return angleA.compareTo(angleB);
    });

    return sorted;
  }

  /// Calculate rotation angle from corner points.
  /// Uses the angle of the first edge (corner[0] → corner[1]).
  static double _calculateRotationAngle(List<ui.Offset> corners) {
    if (corners.length < 2) return 0;

    final p1 = corners[0];
    final p2 = corners[1];

    final dy = p2.dy - p1.dy;
    final dx = p2.dx - p1.dx;

    return atan2(dy, dx);
  }

  /// Reduce raw candidates to one detection per physical card.
  ///
  /// Two stages:
  /// 1. **Size gate** — drop quads outside the plausible card-pixel range.
  /// 2. **Overlap suppression** — rank by how card-shaped each quad is, keep
  ///    the best, and discard anything overlapping it heavily.
  ///
  /// Stage 2 replaces the previous "nested / overlap / dedup" trio, which
  /// compared every quad against every other globally and therefore kept
  /// exactly one detection per *frame*.  Suppression is driven by overlap
  /// instead, so duplicate detections of one card collapse together while two
  /// cards sitting side by side — which barely overlap — both survive.
  static List<RotatedCardRect> _filterDetections(
    List<RotatedCardRect> rects,
    _Bounds b,
    _Funnel? funnel,
  ) {
    if (rects.isEmpty) {
      funnel?.recordStages(0, 0);
      return rects;
    }

    // Stage 1 — gross size gate.
    final sized = rects.where((r) {
      final minDim = min(r.bounds.width, r.bounds.height);
      final maxDim = max(r.bounds.width, r.bounds.height);
      return minDim >= b.minCardPx && maxDim <= b.maxCardPx;
    }).toList();

    if (sized.length <= 1) {
      funnel?.recordStages(sized.length, sized.length);
      funnel?.recordKept(sized);
      return sized;
    }

    // Stage 2 — non-maximum suppression, best-scoring candidate first.
    //
    // Scores are bucketed before comparison.  A card's inner features sit within
    // a few hundredths of true card proportions — the black frame lands near
    // 0.70 and the art box near 0.74 against the card's 0.716 — which is inside
    // the corner-estimation noise, so ranking on the raw score is a coin flip
    // between a card and its own interior.  Within a bucket the larger quad
    // wins, and the outer border is always the larger.  Genuinely non-card
    // shapes (a binder page scores ~0.89) fall in a worse bucket and still lose
    // outright, so the size preference never overrides the shape test.
    final ranked = [...sized]..sort((a, b) {
      final bucketA = (_cardLikeness(a) / _likenessTieBand).floor();
      final bucketB = (_cardLikeness(b) / _likenessTieBand).floor();
      if (bucketA != bucketB) return bucketA.compareTo(bucketB);
      final areaA = a.bounds.width * a.bounds.height;
      final areaB = b.bounds.width * b.bounds.height;
      return areaB.compareTo(areaA);
    });

    final kept = <RotatedCardRect>[];
    for (final cand in ranked) {
      var suppressed = false;
      for (final k in kept) {
        if (_overlapFraction(cand.bounds, k.bounds) > _nmsOverlapFraction) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(cand);
    }

    funnel?.recordStages(sized.length, kept.length);
    funnel?.recordKept(kept);
    return kept;
  }

  /// Shared area as a fraction of the *smaller* rectangle.
  ///
  /// Deliberately not intersection-over-union: a small quad sitting entirely
  /// inside a large one (an art box within a card) scores a low IoU and would
  /// survive, but scores 1.0 here and is suppressed.  Two adjacent cards still
  /// score low, so both are kept.
  static double _overlapFraction(ui.Rect a, ui.Rect b) {
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final smaller = min(areaA, areaB);
    if (smaller <= 0) return 0;
    return _computeIntersectionArea(a, b) / smaller;
  }

  /// Compute the area of intersection between two axis-aligned rectangles.
  static double _computeIntersectionArea(ui.Rect r1, ui.Rect r2) {
    final left = max(r1.left, r2.left);
    final right = min(r1.right, r2.right);
    final top = max(r1.top, r2.top);
    final bottom = min(r1.bottom, r2.bottom);

    if (left >= right || top >= bottom) return 0;
    return (right - left) * (bottom - top);
  }

  /// Calculate the crop rectangle to fit frame to screen aspect ratio.
  /// Returns a Rect with the (left, top, width, height) of the crop region.
  static ui.Rect _calculateCropRect({
    required int frameWidth,
    required int frameHeight,
    required double screenWidth,
    required double screenHeight,
  }) {
    final frameAspect = frameWidth / frameHeight;
    final screenAspect = screenWidth / screenHeight;

    int cropLeft = 0, cropTop = 0, cropWidth = frameWidth, cropHeight = frameHeight;

    if (frameAspect > screenAspect) {
      // Frame is wider than screen → crop sides
      cropWidth = (frameHeight * screenAspect).toInt();
      cropLeft = (frameWidth - cropWidth) ~/ 2;
    } else if (frameAspect < screenAspect) {
      // Frame is narrower than screen → crop top/bottom
      cropHeight = (frameWidth / screenAspect).toInt();
      cropTop = (frameHeight - cropHeight) ~/ 2;
    }
    // else: perfect match, no cropping needed

    return ui.Rect.fromLTWH(cropLeft.toDouble(), cropTop.toDouble(), cropWidth.toDouble(), cropHeight.toDouble());
  }

}

// ---------------------------------------------------------------------------
// Frame-resolved bounds
// ---------------------------------------------------------------------------

/// [DetectorParams] fractions resolved against one frame.
///
/// Every size-like parameter is stored as a fraction of the frame's **short
/// side** and turned into pixels here, once per frame. That is what lets one
/// set of tuning values hold at 480×720 and 1920×1080, portrait or landscape.
class _Bounds {
  /// Shorter of the frame's two dimensions.
  final double shortSide;

  final double minCardPx;
  final double maxCardPx;
  final double minLineLength;
  final double minArea;

  const _Bounds._(
    this.shortSide,
    this.minCardPx,
    this.maxCardPx,
    this.minLineLength,
    this.minArea,
  );

  factory _Bounds.resolve(cv.Mat frame, DetectorParams p) {
    final short = min(frame.rows, frame.cols).toDouble();
    return _Bounds._(
      short,
      short * p.minCardFraction,
      short * p.maxCardFraction,
      short * p.houghMinLineFraction,
      short * short * p.minAreaFraction,
    );
  }

  @override
  String toString() =>
      'short=${shortSide.round()} card=${minCardPx.round()}-${maxCardPx.round()} '
      'minLine=${minLineLength.round()} minArea=${minArea.round()}';
}

// ---------------------------------------------------------------------------
// Line segment with cached geometry
// ---------------------------------------------------------------------------

/// A Hough segment plus the two quantities the grouping logic needs:
/// its undirected direction and its perpendicular distance from the origin.
///
/// Together these identify the *infinite line* a segment lies on, which is what
/// makes collinear duplicates detectable and corner intersection possible
/// without the segments having to physically overlap.
class _Seg {
  final double x1, y1, x2, y2;

  /// Direction in degrees, normalised to [0, 180) — lines are undirected.
  final double angleDeg;

  /// Signed perpendicular offset from the origin: -x*sin(t) + y*cos(t).
  /// Two segments on the same infinite line share both [angleDeg] and [rho].
  final double rho;

  final double length;

  const _Seg._(
    this.x1, this.y1, this.x2, this.y2,
    this.angleDeg, this.rho, this.length,
  );

  factory _Seg.fromPoints(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;

    var deg = atan2(dy, dx) * 180 / 3.141592653589793;
    if (deg < 0) deg += 180;
    if (deg >= 180) deg -= 180;

    final th = deg * 3.141592653589793 / 180;
    final rho = -x1 * sin(th) + y1 * cos(th);

    return _Seg._(x1, y1, x2, y2, deg, rho, sqrt(dx * dx + dy * dy));
  }

  /// Axis extent — the quantity OpenCV HoughLinesP thresholds minLineLength
  /// against, as distinct from Euclidean [length].
  double get axisExtent => max((x2 - x1).abs(), (y2 - y1).abs());
}

// ---------------------------------------------------------------------------
// Detection funnel diagnostics
// ---------------------------------------------------------------------------

/// Per-frame counters tracking where candidate quads die in the Hough pipeline.
///
/// Answers "which stage is dropping the card?" without assuming an answer up
/// front.  Throttled to one frame per [_interval] so the live stream stays
/// readable and unslowed; remove this class and its call sites once the
/// pipeline behaviour is settled.
class _Funnel {
  static const Duration _interval = Duration(seconds: 1);
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  final int frameWidth;
  final int frameHeight;
  final DetectorParams p;

  int _totalLines = 0;
  final List<String> _topLines = [];

  int _mergedCount = 0;
  int _famA = 0;
  int _famB = 0;
  double _famSepDeg = 0;
  bool _splitFailed = false;

  int _combosTried     = 0;
  int _outOfBounds     = 0;
  int _slivers         = 0;
  int _aspectRejects   = 0;
  int _validateRejects = 0;
  int _quadsFormed     = 0;

  /// Aspect ratios seen, so the accept band can be set from measurements
  /// rather than guessed.  Rejected ones are tracked separately from formed
  /// ones — a card scored just outside the band looks very different from a
  /// binder page scored well outside it.
  double _aspectRejMin = double.infinity;
  double _aspectRejMax = double.negativeInfinity;
  final List<double> _formedAspects = [];

  int? _sizeOk, _kept;

  // Contour path — the base rate step B exists to measure.
  int? _contoursFound, _contourAreaRej, _contourNotQuad,
       _contourNotConvex, _contourQuads, _contourKept;

  /// Three largest contour areas and the gate they were measured against.
  List<double> _topAreas = const [];
  double _minArea = 0;

  /// Vertex counts from approxPolyDP for contours that cleared the area gate.
  List<int> _verts = const [];

  /// Which path produced the frame's result: contour, hough, or none.
  String _path = 'none';
  final List<String> _keptDesc = [];

  _Funnel._(this.frameWidth, this.frameHeight, this.p);

  /// Returns a funnel if this frame is due for logging, null otherwise.
  static _Funnel? maybeStart(int w, int h, DetectorParams p) {
    final now = DateTime.now();
    if (now.difference(_last) < _interval) return null;
    _last = now;
    return _Funnel._(w, h, p);
  }

  void recordLines(int total, List<_Seg> top) {
    _totalLines = total;
    for (final s in top) {
      _topLines.add(
        'len=${s.length.round()} '
        'ext=${s.axisExtent.round()} '
        'ang=${s.angleDeg.round()} '
        'rho=${s.rho.round()}',
      );
    }
  }

  void recordFamilies(int merged, (List<_Seg>, List<_Seg>)? families) {
    _mergedCount = merged;
    if (families == null) {
      _splitFailed = true;
      return;
    }
    _famA = families.$1.length;
    _famB = families.$2.length;
    final a = families.$1.first.angleDeg;
    final b = families.$2.first.angleDeg;
    final d = (a - b).abs() % 180;
    _famSepDeg = d > 90 ? 180 - d : d;
  }

  void recordContours(
    int found, int areaRej, int notQuad, int notConvex, int quads, int kept,
    List<double> topAreas, double minArea, List<int> verts,
  ) {
    _topAreas = topAreas;
    _minArea  = minArea;
    _verts    = verts;
    _contoursFound    = found;
    _contourAreaRej   = areaRej;
    _contourNotQuad   = notQuad;
    _contourNotConvex = notConvex;
    _contourQuads     = quads;
    _contourKept      = kept;
  }

  void recordPath(String path) => _path = path;

  void recordCombo()                   => _combosTried++;
  void recordOutOfBounds()             => _outOfBounds++;
  void recordSliver()                  => _slivers++;
  void recordValidateReject(ui.Rect r) => _validateRejects++;

  void recordAspectReject(double aspect) {
    _aspectRejects++;
    _aspectRejMin = min(_aspectRejMin, aspect);
    _aspectRejMax = max(_aspectRejMax, aspect);
  }

  void recordQuadFormed(double aspect) {
    _quadsFormed++;
    if (_formedAspects.length < 12) _formedAspects.add(aspect);
  }

  void recordStages(int sizeOk, int kept) {
    _sizeOk = sizeOk;
    _kept   = kept;
  }

  void recordKept(List<RotatedCardRect> kept) {
    for (final r in kept) {
      _keptDesc.add(
        '${r.bounds.width.round()}x${r.bounds.height.round()}'
        '@${(r.rotationAngle * 180 / 3.141592653589793).round()}deg'
        ' ar=${CardDetector._quadAspect(r.corners).toStringAsFixed(2)}',
      );
    }
  }

  /// Largest contours as a percentage of the area gate. Above 100% means the
  /// contour cleared it; well below means the boundary never reached card size.
  String _fmtAreas() => _minArea <= 0
      ? '-'
      : _topAreas.map((a) => '${(100 * a / _minArea).round()}%').join(', ');

  String _fmtAspects(List<double> xs) =>
      xs.map((a) => a.toStringAsFixed(2)).join(',');

  void emit() {
    AppLogger.d(
      'FUNNEL ${frameWidth}x$frameHeight '
      'canny=${p.cannyLow.round()}/${p.cannyHigh.round()} '
      'dil=${p.dilationIterations} blur=${p.blurKernelSize} '
      'maxGap=${p.houghMaxLineGap} '
      'thresh=${p.houghThreshold}\n'
      '  PATH=$_path  contours=$_contoursFound  areaRej=$_contourAreaRej '
      'notQuad=$_contourNotQuad notConvex=$_contourNotConvex '
      'quads=$_contourQuads contourKept=$_contourKept\n'
      '  minArea=${_minArea.round()}  top3=[${_fmtAreas()}]  '
      'eps=${p.polyEpsilonFraction.toStringAsFixed(3)} verts=$_verts\n'
      '  houghLines=$_totalLines  top8=[${_topLines.join(' | ')}]\n'
      '  merged=$_mergedCount  '
      '${_splitFailed ? "SPLIT FAILED (no two families)" : "famA=$_famA famB=$_famB sep=${_famSepDeg.round()}deg"}\n'
      '  combos=$_combosTried  outOfBounds=$_outOfBounds  slivers=$_slivers  '
      'aspectRejects=$_aspectRejects'
      '${_aspectRejects > 0 ? " (${_aspectRejMin.toStringAsFixed(2)}..${_aspectRejMax.toStringAsFixed(2)})" : ""}  '
      'validateRejects=$_validateRejects  quadsFormed=$_quadsFormed\n'
      '  formedAspects=[${_fmtAspects(_formedAspects)}]\n'
      '  sizeOk=$_sizeOk  kept=$_kept  [${_keptDesc.join(' | ')}]',
    );
  }
}
