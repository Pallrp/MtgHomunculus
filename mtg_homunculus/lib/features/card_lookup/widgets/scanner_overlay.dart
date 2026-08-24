import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../models/detector_params.dart';
import '../models/rotated_card_rect.dart';
import '../models/scan_result.dart';
import '../models/scryfall_card.dart';
import '../services/card_detector.dart';
import '../services/card_warp.dart';
import '../services/scan_pipeline.dart';
import 'card_border_painter.dart';
import 'manual_entry_dialog.dart';
import 'printing_browser_sheet.dart';
import 'ocr_debug_panel.dart';
import 'tuning_panel.dart';

// ---------------------------------------------------------------------------
// State enum
// ---------------------------------------------------------------------------

enum _Phase { live, frozen }

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Camera overlay widget used on [ListingDetailScreen] and [QuickScanScreen].
///
/// **Responsibilities**
/// - Initialises and owns the [CameraController] (one init, never recreated).
/// - Starts / stops the image stream based on [isActive] (the parent ties this
///   to whether the bottom sheet handle is fully down).
/// - **Live mode**: streams frames → [CardDetector] at ~2 fps → [CardBorderPainter].
/// - **Capture**: stops stream, takes a display photo, re-runs border detection
///   on the last raw sensor frame (same coordinate space as live mode).
/// - **Frozen mode**: shows the captured photo with border rectangles,
///   spinners while the pipeline is running, and result chips once each card
///   is identified.
///
/// **Pipeline wiring (Slice 7)**
/// The `// TODO(slice-7)` block in [_capture] is replaced with a call to
/// `ScanPipeline.run(...)` which drives the per-card OCR + Scryfall flow and
/// calls back with [ScanResult] objects that fill each spinner slot.
class ScannerOverlay extends StatefulWidget {
  /// Whether the camera stream should be running.
  /// Set to `true` when the bottom sheet handle is fully collapsed.
  final bool isActive;

  /// Called when a matched card should be added to the listing.
  /// Returns the listingCardId of the new or quantity-incremented [ListingCard].
  final Future<String> Function(ScryfallCard card)? onCardAdded;

  /// Called when the user picks a different printing or foil status for an
  /// already-matched result (triggered from the printing browser sheet).
  final void Function(
    String listingCardId,
    ScryfallCard newPrinting,
    bool isFoil,
  )? onCardUpdated;

  /// Whether the overlay should render its own capture button.
  ///
  /// Set to `false` when the parent places the button itself (e.g.
  /// [ListingDetailScreen] renders it above the draggable sheet so it is
  /// not obscured).  The parent then calls [ScannerOverlayState.capture]
  /// via a [GlobalKey].
  final bool showCaptureButton;

  /// Called whenever the live border-detection result changes between
  /// "at least one card found" and "no cards found".  Lets the parent
  /// tint the externally-rendered capture button green when cards are
  /// detected.
  final void Function(bool detecting)? onDetectionChanged;

  /// Called when the overlay switches between live and frozen phase.
  ///
  /// `isFrozen = true`  → capture in progress / results visible.
  /// `isFrozen = false` → back to live scanning.
  /// The parent uses this to hide the externally-rendered capture button
  /// while the frozen result view is shown.
  final void Function(bool isFrozen)? onPhaseChanged;

  /// When true, a tuning-panel toggle button is rendered inside the overlay
  /// and the full [TuningPanel] is accessible.  Intended for [QuickScanScreen]
  /// only; leave false (the default) for [ListingDetailScreen].
  final bool showTuningButton;

  const ScannerOverlay({
    super.key,
    required this.isActive,
    this.onCardAdded,
    this.onCardUpdated,
    this.showCaptureButton   = true,
    this.showTuningButton    = false,
    this.onDetectionChanged,
    this.onPhaseChanged,
  });

  @override
  State<ScannerOverlay> createState() => ScannerOverlayState();
}

class ScannerOverlayState extends State<ScannerOverlay> {
  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController?  _controller;
  CameraDescription? _camera;
  bool               _cameraReady  = false;
  PermissionStatus   _cameraStatus = PermissionStatus.denied;

  // ── Live mode ─────────────────────────────────────────────────────────────
  CameraImage?           _lastFrame;   // most recent raw YUV frame from stream
  List<RotatedCardRect>  _liveRects  = [];
  Size?                  _frameSize;   // sensor frame dimensions (width × height)
  bool                   _canProcess = true;

  // ── Frozen mode ───────────────────────────────────────────────────────────
  _Phase                _phase           = _Phase.live;
  bool                  _capturing       = false;  // true while stopping stream + taking picture
  XFile?                _capturedPhoto;
  List<RotatedCardRect> _frozenRects     = [];
  List<ScanResult?>     _scanResults     = [];     // null slot = spinner
  bool                  _pipelineRunning = false;

  // ── Tuning / debug ────────────────────────────────────────────────────────
  bool           _tuningOpen  = false;
  bool           _showEdgeMap = false;

  // ── [dev-tool] live OCR readout ────────────────────────────────────────────
  bool           _showOcrDebug   = false;
  Uint8List?     _ocrCardPng;
  Uint8List?     _ocrBandPng;
  String         _ocrText        = '';
  double         _ocrPxPerMm     = 0;
  bool           _ocrBusy        = false;
  DateTime       _ocrLastRun     = DateTime.fromMillisecondsSinceEpoch(0);
  int            _ocrDumpIx      = 0;
  TextRecognizer? _recognizer;
  DetectorParams _params      = const DetectorParams.defaults();
  Uint8List?     _liveEdgeMap;
  Uint8List?     _frozenEdgeMap;

  // ---------------------------------------------------------------------------
  // Init / dispose
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Load persisted tuning params (fast — returns cached value after first load).
    DetectorParams.loadCurrent().then((p) {
      if (mounted) setState(() => _params = p);
    });
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Permission was already requested by ListingHomeScreen (sub-app entry).
    _cameraStatus = await Permission.camera.status;
    if (!_cameraStatus.isGranted) {
      if (mounted) setState(() {});
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      AppLogger.w('ScannerOverlay: no cameras found');
      if (mounted) setState(() {});
      return;
    }

    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      _camera!,
      // Measured in spike S1/S3 (2026-08-21): `medium` misreads the set code
      // (KLN for XLN), and everything above `high` costs framerate for no gain
      // — `max` actively regressed. `high` also happens to match
      // [CardDetector.detectShortSide], so detection runs at native resolution
      // with no downscale and no corner-error amplification.
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
    } catch (e, st) {
      AppLogger.e(
        'ScannerOverlay: camera init failed',
        error: e, stackTrace: st,
      );
      if (mounted) setState(() {});
      return;
    }

    if (!mounted) return;
    setState(() => _cameraReady = true);
    if (widget.isActive && _phase == _Phase.live) _startStream();
  }

  @override
  void didUpdateWidget(ScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_cameraReady || oldWidget.isActive == widget.isActive) return;

    if (widget.isActive && _phase == _Phase.live) {
      _startStream();
    } else if (!widget.isActive) {
      _stopStream();
    }
  }

  @override
  void dispose() {
    _recognizer?.close();
    _stopStream();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Public API (used by parent via GlobalKey when showCaptureButton = false)
  // ---------------------------------------------------------------------------

  /// Triggers the capture sequence programmatically.
  ///
  /// No-op if the camera is not ready, already capturing, no frame has
  /// been received yet, or the overlay is already in frozen mode.
  void capture() => _capture();

  /// Returns to live scanning, discarding the current frozen result.
  ///
  /// No-op if already in live mode.
  void reset() => _reset();

  // ---------------------------------------------------------------------------
  // Stream management
  // ---------------------------------------------------------------------------

  void _startStream() {
    if (_controller == null || !_cameraReady) return;
    if (_controller!.value.isStreamingImages) return; // guard: already streaming
    _canProcess = true;
    _controller!.startImageStream((CameraImage frame) async {
      if (!_canProcess || !mounted) return;
      _canProcess = false;
      _lastFrame  = frame;

      List<RotatedCardRect> rects;
      Uint8List?            edgeMap;
      if (_showEdgeMap) {
        (rects, edgeMap) = await CardDetector.detectBordersDebug(
          frame,
          params:            _params,
          sensorOrientation: _camera!.sensorOrientation,
        );
      } else {
        rects = await CardDetector.detectBorders(frame, params: _params);
      }
      if (mounted) {
        final wasDetecting = _liveRects.isNotEmpty;
        setState(() {
          _liveRects   = rects;
          _liveEdgeMap = edgeMap;
          _frameSize   = Size(frame.width.toDouble(), frame.height.toDouble());
        });
        if (rects.isNotEmpty != wasDetecting) {
          widget.onDetectionChanged?.call(rects.isNotEmpty);
        }
      }

      if (_showOcrDebug) {
        // Deliberately not awaited — the readout must never slow detection.
        unawaited(_runOcrDebug(frame, rects));
      }

      // Throttle to ~2 fps.
      await Future.delayed(const Duration(milliseconds: 300));
      _canProcess = true;
    });
  }

  /// [dev-tool] Warp the best detection, crop the collector band, OCR it.
  ///
  /// Throttled hard — one pass per second at most, and never overlapping —
  /// because it converts the whole frame and round-trips through ML Kit.
  Future<void> _runOcrDebug(CameraImage frame, List<RotatedCardRect> rects) async {
    if (_ocrBusy) return;
    if (DateTime.now().difference(_ocrLastRun) < const Duration(seconds: 1)) return;
    _ocrLastRun = DateTime.now();

    if (rects.isEmpty) {
      if (mounted) {
        setState(() {
          _ocrCardPng = null;
          _ocrBandPng = null;
          _ocrText    = '';
          _ocrPxPerMm = 0;
        });
      }
      return;
    }

    _ocrBusy = true;
    if (mounted) setState(() {});

    cv.Mat? card;
    File? tmp;
    try {
      final corners = rects.first.corners;
      final pxPerMm = CardWarp.pixelsPerMm(corners);

      card = CardWarp.fromCameraImage(frame, corners);
      if (card == null) return;

      final band     = CardWarp.collectorBand(card);
      final cardPng  = CardWarp.encodePng(card);
      final bandPng  = CardWarp.encodePng(band);

      var text = '';
      final (ok, jpg) = cv.imencode('.jpg', band);
      if (ok) {
        final dir = await getTemporaryDirectory();
        tmp = File('${dir.path}/ocrdbg_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tmp.writeAsBytes(jpg.toList());
        _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
        final res = await _recognizer!.processImage(InputImage.fromFilePath(tmp.path));
        text = res.text.trim();
      }

      // [dev-tool] Keep the last 8 warps on disk, in the documents dir so
      // `adb run-as` can pull them. Lets the warp be inspected directly rather
      // than inferred from the OCR text.
      final ix = _ocrDumpIx++ % 8;
      try {
        final docs = await getApplicationDocumentsDirectory();
        final d = Directory('${docs.path}/ocrdump');
        if (!await d.exists()) await d.create(recursive: true);
        if (cardPng != null) {
          await File('${d.path}/${ix}_card.png').writeAsBytes(cardPng);
        }
        if (bandPng != null) {
          await File('${d.path}/${ix}_band.png').writeAsBytes(bandPng);
        }
      } catch (e) {
        AppLogger.w('OCR-DBG dump failed: $e');
      }

      AppLogger.d(
        'OCR-DBG #$ix ${frame.width}x${frame.height} '
        '${pxPerMm.toStringAsFixed(2)} px/mm  '
        '${text.isEmpty ? "EMPTY" : '"${text.replaceAll('\n', ' / ')}"'}',
      );

      if (mounted) {
        setState(() {
          _ocrCardPng = cardPng;
          _ocrBandPng = bandPng;
          _ocrText    = text;
          _ocrPxPerMm = pxPerMm;
        });
      }
    } catch (e, st) {
      AppLogger.w('OCR-DBG failed', error: e, stackTrace: st);
    } finally {
      card?.dispose();
      if (tmp != null) { try { await tmp.delete(); } catch (_) {} }
      _ocrBusy = false;
      if (mounted) setState(() {});
    }
  }

  void _stopStream() {
    if (_controller?.value.isStreamingImages != true) return;
    try { _controller!.stopImageStream(); } catch (_) {}
  }

  /// Calculate the crop offset for the camera preview based on aspect ratios.
  ///
  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  Future<void> _capture() async {
    if (!_cameraReady || _capturing || _lastFrame == null ||
        _phase == _Phase.frozen) { return; }
    final lastFrame = _lastFrame!;

    // 1 — Show loading overlay over the live preview while we work.
    setState(() {
      _capturing = true;
      _liveRects = []; // clear live borders immediately
    });
    widget.onDetectionChanged?.call(false);

    // 2 — Stop stream and take a JPEG for display.
    _stopStream();
    XFile? photo;
    try {
      photo = await _controller!.takePicture();
    } catch (e, st) {
      AppLogger.w('ScannerOverlay: takePicture failed', error: e, stackTrace: st);
    }

    // 3 — Detect borders on the stored raw sensor frame.
    List<RotatedCardRect> rects;
    Uint8List?            frozenEdgeMap;
    if (_showEdgeMap) {
      (rects, frozenEdgeMap) = await CardDetector.detectBordersDebug(
        lastFrame,
        params:            _params,
        sensorOrientation: _camera!.sensorOrientation,
      );
    } else {
      rects = await CardDetector.detectBorders(lastFrame, params: _params);
    }
    AppLogger.d('ScannerOverlay: capture detected ${rects.length} border(s)');

    if (!mounted) return;

    // 4 — Switch to frozen mode; all detected border slots start as spinners.
    setState(() {
      _phase           = _Phase.frozen;
      _capturing       = false;
      _capturedPhoto   = photo;
      _frozenRects     = rects;
      _frozenEdgeMap   = frozenEdgeMap;
      _scanResults     = List.filled(rects.length, null);
      _pipelineRunning = rects.isNotEmpty;
    });
    widget.onPhaseChanged?.call(true);

    if (rects.isNotEmpty) {
      await ScanPipeline.run(
        frame:             lastFrame,
        borders:           rects,
        sensorOrientation: _camera!.sensorOrientation,
        onCardAdded:       widget.onCardAdded,
        nameStripFraction: _params.nameStripFraction,
        onResult: (i, result) {
          if (mounted) {
            setState(() {
              _scanResults[i]  = result;
              _pipelineRunning = _scanResults.any((r) => r == null);
            });
          }
        },
      );
    }
    if (mounted) { setState(() => _pipelineRunning = false); }
  }

  void _reset() {
    setState(() {
      _phase           = _Phase.live;
      _capturing       = false;
      _capturedPhoto   = null;
      _frozenRects     = [];
      _frozenEdgeMap   = null;
      _scanResults     = [];
      _pipelineRunning = false;
      _liveRects       = [];
      _liveEdgeMap     = null;
    });
    widget.onDetectionChanged?.call(false);
    widget.onPhaseChanged?.call(false);
    if (widget.isActive) _startStream();
  }

  // ---------------------------------------------------------------------------
  // Coordinate transform — sensor rect → display rect
  // (mirrors the logic in CardBorderPainter so spinners/chips align with borders)
  // ---------------------------------------------------------------------------

  ui.Rect _toDisplayRect(RotatedCardRect rotated, double displayW, double displayH) {
    final r = rotated.bounds;  // Use axis-aligned bounds
    final sW = _frameSize!.width;
    final sH = _frameSize!.height;
    switch (_camera!.sensorOrientation) {
      case 90:
        final sx = displayW / sH;
        final sy = displayH / sW;
        return ui.Rect.fromLTWH(
          (sH - r.top - r.height) * sx,
          r.left                  * sy,
          r.height * sx,
          r.width  * sy,
        );
      case 270:
        final sx = displayW / sH;
        final sy = displayH / sW;
        return ui.Rect.fromLTWH(
          r.top                   * sx,
          (sW - r.left - r.width) * sy,
          r.height * sx,
          r.width  * sy,
        );
      case 180:
        final sx = displayW / sW;
        final sy = displayH / sH;
        return ui.Rect.fromLTWH(
          (sW - r.left - r.width)  * sx,
          (sH - r.top  - r.height) * sy,
          r.width  * sx,
          r.height * sy,
        );
      default: // 0°
        final sx = displayW / sW;
        final sy = displayH / sH;
        return ui.Rect.fromLTWH(
          r.left * sx, r.top * sy, r.width * sx, r.height * sy,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_cameraStatus.isGranted) return _buildPermissionDenied(context);
    if (!_cameraReady)            return _buildLoading();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Main scanner content (live or frozen).
        _phase == _Phase.live ? _buildLive(context) : _buildFrozen(context),

        // Top-right button cluster: Re-scan (frozen only) + tuning toggle.
        if (_phase == _Phase.frozen || widget.showTuningButton)
          Positioned(
            top: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_phase == _Phase.frozen) ...[
                      _buildRescanButton(),
                      if (widget.showTuningButton) const SizedBox(height: 6),
                    ],
                    if (widget.showTuningButton)
                      _buildTuningToggleButton(),
                  ],
                ),
              ),
            ),
          ),

        // [dev-tool] OCR readout — sits above the tuning sheet so both are usable.
        if (_showOcrDebug)
          Positioned(
            left: 8, right: 8,
            bottom: _tuningOpen
                ? MediaQuery.of(context).size.height * 0.65 + 8
                : 16,
            child: SafeArea(
              top: false,
              child: OcrDebugPanel(
                card:    _ocrCardPng,
                band:    _ocrBandPng,
                text:    _ocrText,
                pxPerMm: _ocrPxPerMm,
                busy:    _ocrBusy,
              ),
            ),
          ),

        // Tuning panel — slides up from the bottom when open.
        if (widget.showTuningButton && _tuningOpen)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: TuningPanel(
              params:       _params,
              showEdgeMap:  _showEdgeMap,
              showOcrDebug: _showOcrDebug,
              onParamsChanged: (p) async {
                setState(() => _params = p);
                await DetectorParams.setCurrent(p);
              },
              onEdgeMapToggled: (v) => setState(() => _showEdgeMap = v),
              onOcrDebugToggled: (v) => setState(() {
                _showOcrDebug = v;
                if (!v) {
                  _ocrCardPng = null;
                  _ocrBandPng = null;
                  _ocrText    = '';
                  _ocrPxPerMm = 0;
                }
              }),
              onClose: () => setState(() => _tuningOpen = false),
            ),
          ),
      ],
    );
  }

  Widget _buildRescanButton() => FilledButton.icon(
    icon:      const Icon(Icons.refresh_rounded, size: 18),
    label:     const Text('Re-scan'),
    onPressed: _pipelineRunning ? null : _reset,
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xAA000000),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
  );

  Widget _buildTuningToggleButton() => IconButton(
    icon:  Icon(_tuningOpen ? Icons.tune : Icons.tune_rounded),
    color: _showEdgeMap ? Colors.greenAccent : Colors.white,
    style: IconButton.styleFrom(
      backgroundColor: _tuningOpen
          ? Colors.white.withValues(alpha: 0.2)
          : const Color(0xAA000000),
    ),
    tooltip:   _tuningOpen ? 'Close tuning' : 'Open tuning',
    onPressed: () => setState(() => _tuningOpen = !_tuningOpen),
  );

  Widget _buildLoading() => const Center(child: CircularProgressIndicator());

  Widget _buildPermissionDenied(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera permission required for scanning.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  // ── Live ──────────────────────────────────────────────────────────────────

  Widget _buildLive(BuildContext context) {
    if (_frameSize == null || _camera == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final so = _camera!.sensorOrientation;
    // Use actual frame dimensions (not camera plugin's preview size) for consistency with frozen mode.
    final displayImageSize = (so == 90 || so == 270)
        ? Size(_frameSize!.height, _frameSize!.width)
        : _frameSize!;
    final displayW = displayImageSize.width;
    final displayH = displayImageSize.height;

    final Widget mediaContent;
    if (_showEdgeMap && _liveEdgeMap != null) {
      mediaContent = Image.memory(_liveEdgeMap!, fit: BoxFit.fill);
    } else {
      mediaContent = CameraPreview(_controller!);
    }

    // Use LayoutBuilder to fill the viewport and apply the crop offset explicitly.
    // This ensures live preview matches snapshot cropping.
    return LayoutBuilder(
      builder: (_, constraints) {
        final viewportW = constraints.maxWidth;
        final viewportH = constraints.maxHeight;

        // Scale factor: how much to scale the camera frame to fill the viewport.
        final scaleX = viewportW / displayW;
        final scaleY = viewportH / displayH;
        final scale = max(scaleX, scaleY); // Cover mode: fill viewport, crop edges

        // Scaled dimensions of the camera frame.
        final scaledW = displayW * scale;
        final scaledH = displayH * scale;

        // Center the scaled image within the viewport.
        final offsetX = (viewportW - scaledW) / 2;
        final offsetY = (viewportH - scaledH) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Media — scaled and clipped to fill viewport (matching snapshot crop).
            Positioned(
              left:   offsetX,
              top:    offsetY,
              width:  scaledW,
              height: scaledH,
              child: ClipRect(
                child: mediaContent,
              ),
            ),

            // Border overlay — same scaling and positioning as media layer.
            if (_frameSize != null && !_capturing)
              Positioned(
                left:   offsetX,
                top:    offsetY,
                width:  scaledW,
                height: scaledH,
                child: CustomPaint(
                  painter: CardBorderPainter(
                    rects:             _liveRects,
                    imageSize:         _frameSize!,
                    previewSize:       Size(scaledW, scaledH),
                    sensorOrientation: so,
                    cropOffset:        ui.Offset.zero,  // ← Positioned layout handles all positioning
                  ),
                ),
              ),

            // Loading overlay while stopping stream / taking picture.
            if (_capturing)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),

            // Capture button — only when the parent has not taken ownership.
            if (!_capturing && widget.showCaptureButton)
              Positioned(
                left: 0, right: 0, bottom: 24,
                child: Center(
                  child: CaptureButton(
                    detecting: _liveRects.isNotEmpty,
                    onTap:     capture,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Frozen ────────────────────────────────────────────────────────────────

  Widget _buildFrozen(BuildContext context) {
    if (_capturedPhoto == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Capture failed.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            TextButton(onPressed: _reset, child: const Text('Re-scan')),
          ],
        ),
      );
    }

    // In edge-map mode show the processed Canny output instead of the JPEG.
    // Both images share the same natural display dimensions (JPEG has EXIF
    // rotation applied; edge map is pre-rotated by CardDetector).
    // Use BoxFit.cover (crop) to match the live preview—no letterboxing.
    final frozenDisplay = (_showEdgeMap && _frozenEdgeMap != null)
        ? Image.memory(_frozenEdgeMap!, fit: BoxFit.cover)
        : Image.file(File(_capturedPhoto!.path), fit: BoxFit.cover);

    return Stack(
      fit: StackFit.expand,
      children: [
        frozenDisplay,

        // Border rectangles + spinners / result chips.
        // BoxFit.cover crops the image to fill the widget, matching the live preview.
        if (_frameSize != null)
          LayoutBuilder(
            builder: (_, constraints) {
              final widgetW = constraints.maxWidth;
              final widgetH = constraints.maxHeight;

                    // Both the JPEG (EXIF-rotated) and the edge map (pre-rotated by
              // CardDetector) display in portrait when sensorOrientation is
              // 90 or 270 — swap w/h accordingly.
              final so = _camera!.sensorOrientation;
              final displayImageSize = (so == 90 || so == 270)
                  ? Size(_frameSize!.height, _frameSize!.width)
                  : _frameSize!;

              final displayW = displayImageSize.width;
              final displayH = displayImageSize.height;

              // Calculate how to scale image with BoxFit.cover (same as live preview).
              final scaleX = widgetW / displayW;
              final scaleY = widgetH / displayH;
              final scale = max(scaleX, scaleY); // Cover: fill viewport, crop edges

              final scaledW = displayW * scale;
              final scaledH = displayH * scale;

              // Center the scaled image in viewport.
              final offsetX = (widgetW - scaledW) / 2;
              final offsetY = (widgetH - scaledH) / 2;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Border lines + optional name-strip highlight band.
                  // Position with same logic as live preview for consistent corner placement.
                  Positioned(
                    left:   offsetX,
                    top:    offsetY,
                    width:  scaledW,
                    height: scaledH,
                    child: CustomPaint(
                      painter: CardBorderPainter(
                        rects:             _frozenRects,
                        imageSize:         _frameSize!,
                        previewSize:       Size(scaledW, scaledH),  // ← Use actual display size
                        sensorOrientation: so,
                        cropOffset:        ui.Offset.zero,
                        nameStripFraction: _showEdgeMap
                            ? _params.nameStripFraction
                            : 0,
                      ),
                    ),
                  ),

                  // Spinner or result chip centred on each border.
                  ..._frozenRects.asMap().entries.map((entry) {
                    final i      = entry.key;
                    final dRect  = _toDisplayRect(
                      entry.value, widgetW, widgetH,
                    );
                    final result =
                        i < _scanResults.length ? _scanResults[i] : null;
                    return Positioned(
                      left: dRect.center.dx - 20,
                      top:  dRect.center.dy - 20,
                      child: result == null
                          ? const SizedBox(
                              width: 40, height: 40,
                              child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3,
                              ),
                            )
                          : _buildResultChip(context, result),
                    );
                  }),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildResultChip(BuildContext context, ScanResult result) =>
      switch (result) {
        MatchedResult(:final card, :final listingCardId) => _MatchedChip(
            card:  card,
            onTap: () => PrintingBrowserSheet.show(
              context,
              card:          card,
              listingCardId: listingCardId,
              onUpdated:     widget.onCardUpdated,
            ),
          ),
        FailedResult(:final ocrText) => _FailedChip(
            ocrText: ocrText,
            onTap:   () => ManualEntryDialog.show(
              context,
              ocrText:     ocrText,
              onCardAdded: widget.onCardAdded,
            ),
          ),
      };
}

// ---------------------------------------------------------------------------
// Capture button
// ---------------------------------------------------------------------------

class CaptureButton extends StatelessWidget {
  final VoidCallback? onTap;

  /// True when the live preview has at least one detected border.
  /// Tints the button green to signal the camera has found cards.
  /// Ignored when [backgroundColor] is provided.
  final bool detecting;

  /// Override the icon. Defaults to [Icons.camera_alt_rounded].
  final IconData? icon;

  /// Override the circle fill colour.  When null the detecting-based
  /// green/white logic applies.
  final Color? backgroundColor;

  /// Override the icon colour. Defaults to [Colors.black87].
  final Color? iconColor;

  const CaptureButton({
    super.key,
    this.onTap,
    this.detecting       = false,
    this.icon,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ??
        (detecting
            ? Colors.greenAccent.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 68, height: 68,
        decoration: BoxDecoration(
          shape:  BoxShape.circle,
          color:  bgColor,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Icon(
          icon ?? Icons.camera_alt_rounded,
          size:  30,
          color: iconColor ?? Colors.black87,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result chips
// ---------------------------------------------------------------------------

class _MatchedChip extends StatelessWidget {
  final ScryfallCard card;
  final VoidCallback onTap;

  const _MatchedChip({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  card.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _FailedChip extends StatelessWidget {
  final String ocrText;
  final VoidCallback onTap;

  const _FailedChip({required this.ocrText, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.close_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  ocrText.isEmpty ? 'Not found' : ocrText,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
}
