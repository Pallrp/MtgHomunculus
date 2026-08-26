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
import '../data/cards_database.dart';
import '../data/hash_index.dart';
import '../models/detector_params.dart';
import '../models/rotated_card_rect.dart';
import '../models/scan_result.dart';
import '../models/scryfall_card.dart';
import '../services/card_detector.dart';
import '../services/card_identifier.dart';
import '../services/card_warp.dart';
import '../services/dhash.dart';
import '../services/duplicate_guard.dart';
import '../services/scan_pipeline.dart';
import 'card_border_painter.dart';
import 'card_picker.dart';
import 'ocr_debug_panel.dart';
import 'tuning_panel.dart';

// ---------------------------------------------------------------------------
// State enum
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// Camera overlay widget used on [ListingDetailScreen] and [QuickScanScreen].
///
/// **Responsibilities**
/// - Initialises and owns the [CameraController] (one init, never recreated).
/// - Starts / stops the image stream based on [isActive] (the parent ties this
///   to whether the bottom sheet handle is fully down).
/// - Streams frames → [CardDetector] at ~2 fps → [CardBorderPainter].
/// - **Capture identifies the live frame in place.** The preview never freezes:
///   spike S3 established that a stream frame carries the resolution the
///   pipeline needs, so there is nothing a still would add and no inspection
///   step to hold the image for.
/// - The most recent outcome shows briefly as a chip. The last-scan bar and
///   sheet in `single_card_capture_flow.md` replace it.
class ScannerOverlay extends StatefulWidget {
  /// Whether the camera stream should be running.
  /// Set to `true` when the bottom sheet handle is fully collapsed.
  final bool isActive;

  /// Called when a matched card should be added to the listing.
  /// Returns the entry id of the new or quantity-incremented row.
  final Future<int> Function(ScryfallCard card)? onCardAdded;

  /// Called when the user taps the chip for a card that was just added, to open
  /// it for correction. The overlay does not own Card Detail — it is a screen,
  /// and pushing one from inside the camera surface would leave the scanner
  /// running underneath it.
  final void Function(int entryId)? onEntryTapped;

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

  /// Called once when nothing has been detected for 30 seconds.
  ///
  /// The overlay reports the condition and does nothing about it: the designed
  /// response is to expand the listing sheet, which the parent owns and which
  /// stops the camera as a side effect — one gesture, one state, and reviewing
  /// what you collected is the likely next thing anyway.
  final VoidCallback? onIdle;

  /// When true, a tuning-panel toggle button is rendered inside the overlay
  /// and the full [TuningPanel] is accessible.  Intended for [QuickScanScreen]
  /// only; leave false (the default) for [ListingDetailScreen].
  final bool showTuningButton;

  const ScannerOverlay({
    super.key,
    required this.isActive,
    this.onCardAdded,
    this.onEntryTapped,
    this.showCaptureButton   = true,
    this.showTuningButton    = false,
    this.onDetectionChanged,
    this.onIdle,
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

  /// Act on one card per capture — see [_shownRects].
  ///
  /// [dev-tool] toggle only, so the two behaviours can be compared on device.
  /// The flow this belongs to is single-card by design
  /// (`single_card_capture_flow.md`).
  bool                   _singleRect = true;

  /// The detections the user is shown, and the ones capture will act on.
  ///
  /// **These must be the same list.** Drawing one border while identifying every
  /// detection would make the overlay lie about what the button does — the user
  /// would see one card outlined and get a Choose Version sheet for a patch of
  /// wood grain they were never told about.
  List<RotatedCardRect> get _shownRects {
    if (!_singleRect) return _liveRects;
    final best = RotatedCardRect.best(_liveRects);
    return best == null ? const [] : [best];
  }

  // ── Identification ────────────────────────────────────────────────────────
  bool       _capturing   = false;  // pipeline in flight
  ScanResult? _lastResult;          // most recent outcome, shown briefly
  DateTime?   _lastResultAt;

  /// Identify without waiting for a button press.
  ///
  /// The designed behaviour (`single_card_capture_flow.md`): point, and cards
  /// appear. The button stays as an override for a border the gate refuses.
  bool _loopEnabled = true;

  /// Stops one card being added on every frame it stays in view.
  final _guard = DuplicateGuard();

  /// Choose Version is on screen, and detection is suspended.
  ///
  /// Identification is already blocked while the picker awaits — the capture
  /// that opened it has not returned — but detection is not, and it would keep
  /// running at 2fps behind a sheet covering the screen.
  ///
  /// The point is not the saved work. It is that **nothing computed before the
  /// user answered survives the answer**: the card gets reangled while the
  /// picker is up, so on close the next frame is a genuinely new view rather
  /// than a queued verdict on the old one. The ~700ms of detect-then-identify
  /// that follows is the breathing room, and needs no artificial delay.
  bool _promptOpen = false;

  /// Outcome colour for the border, and when it expires.
  ///
  /// Separate from [_lastResult], which drives the result chip and lives for
  /// seconds. This is a flash measured in hundreds of milliseconds, because at
  /// two scans a second a four-second border colour would still be showing the
  /// previous card's outcome when the next one resolves.
  Color?    _flashColour;
  DateTime? _flashUntil;

  /// When a card was last on screen, for the idle timeout.
  DateTime _lastDetectionAt = DateTime.now();
  bool     _idleFired       = false;

  /// After this long with nothing detected, the user has stopped scanning.
  static const _idleAfter = Duration(seconds: 30);

  /// How long an outcome colours the border.
  static const _flashFor = Duration(milliseconds: 600);

  /// What the border should say about the scan loop, or null to leave it to
  /// [CardQuality].
  ///
  /// The outcome flash outranks "identifying": a scan that has just finished has
  /// something to report, and the next one starting must not overwrite it before
  /// the user sees it.
  Color? get _borderState =>
      _flashColour ?? (_capturing ? Colors.yellowAccent : null);

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

  /// Loaded once, lazily. Null means matching is unavailable — the index has not
  /// been downloaded yet — rather than failing.
  HashIndex?      _index;
  bool            _indexTried = false;
  CardsDatabase?  _cardsDb;
  CardIdentifier? _identifier;
  List<HashCandidate> _hashHits = const [];
  String              _dataStatus = '';
  DetectorParams _params      = const DetectorParams.defaults();
  Uint8List?     _liveEdgeMap;

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
    if (widget.isActive) _startStream();
  }

  @override
  void didUpdateWidget(ScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_cameraReady || oldWidget.isActive == widget.isActive) return;

    if (widget.isActive) {
      _startStream();
    } else if (!widget.isActive) {
      _stopStream();
    }
  }

  @override
  void dispose() {
    // Leaving the scanner is what ends a scanning session, so this is where the
    // card last added stops being suppressed.
    _guard.reset();
    _recognizer?.close();
    _identifier?.dispose();
    _cardsDb?.close();
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
  /// been received yet, or a previous identification is still running.
  /// Force a capture, ignoring the quality gate the loop applies.
  ///
  /// The user pressing the button is them overruling the gate — an amber border
  /// still reads correctly 43% of the time, and refusing to try would make the
  /// button feel broken on exactly the frames someone reaches for it.
  void capture() => _capture(manual: true);

  // ---------------------------------------------------------------------------
  // Stream management
  // ---------------------------------------------------------------------------

  void _startStream() {
    if (_controller == null || !_cameraReady) return;
    if (_controller!.value.isStreamingImages) return; // guard: already streaming
    _canProcess = true;
    _controller!.startImageStream((CameraImage frame) async {
      if (!_canProcess || !mounted) return;
      // The user is answering a question. Detecting behind the sheet would queue
      // up a verdict on a view they are in the middle of changing.
      if (_promptOpen) return;
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
        if (rects.isNotEmpty) {
          _lastDetectionAt = DateTime.now();
          _idleFired = false;
        }
        _maybeAutoCapture();
        _checkIdle();
      }

      if (_showOcrDebug && mounted) {
        // The readout must show the card the border is drawn on, or it reports
        // on a quad the user was never shown.
        // Deliberately not awaited — the readout must never slow detection.
        unawaited(_runOcrDebug(frame, _shownRects));
      }

      // Throttle to ~2 fps.
      await Future.delayed(const Duration(milliseconds: 300));
      _canProcess = true;
    });
  }

  /// [dev-tool] Fetch the match index so a real capture can be measured against
  /// it. Belongs on the card data screen; this is the stopgap.
  Future<void> _downloadIndex() async {
    setState(() => _dataStatus = 'Downloading match index…');
    final ok = await HashIndex.download(onProgress: (got, total) {
      if (!mounted) return;
      final mb = (got / (1024 * 1024)).toStringAsFixed(1);
      setState(() => _dataStatus = total > 0
          ? 'Downloading… $mb MB  ${(100 * got / total).round()}%'
          : 'Downloading… $mb MB');
    });
    if (!mounted) return;

    // Force the next debug pass to pick it up.
    _indexTried = false;
    _index = null;
    _hashHits = const [];

    if (!ok) {
      setState(() => _dataStatus = 'Match index download FAILED — see log');
      return;
    }
    final idx = await HashIndex.load();
    if (!mounted) return;
    setState(() {
      _index = idx;
      _indexTried = true;
      _dataStatus = idx == null
          ? 'Downloaded but did not parse — version mismatch?'
          : 'Match index ready — ${idx.count} cards';
    });
  }

  /// [dev-tool] Clear the first-run gate so setup runs again on next entry.
  ///
  /// Clears `bulk_imported_at` rather than deleting `cards.db`, which drift has
  /// open. The import replaces rows by primary key, so re-running it is safe.
  Future<void> _resetCardData() async {
    final db = _cardsDb ??= CardsDatabase();
    await db.setMeta(MetaKeys.bulkImportedAt, '');
    try {
      final f = await HashIndex.file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (!mounted) return;
    _index = null;
    _indexTried = true;
    _hashHits = const [];
    setState(() => _dataStatus =
        'Card data cleared — leave and re-enter Card Lookup to re-run setup');
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

      // ── dHash against the shipped index ──────────────────────────────────
      // Calibration: the match threshold is a guess until a real capture has
      // been measured against the real index. Everything supporting it so far
      // degraded reference art synthetically.
      if (!_indexTried) {
        _indexTried = true;
        _index = await HashIndex.load();
        AppLogger.d('HASH-DBG index ${_index == null ? "absent" : "${_index!.count} cards"}');
      }
      if (_index != null) {
        cv.Mat? gray;
        try {
          gray = cv.cvtColor(card, cv.COLOR_BGR2GRAY);
          final hash = DHash.compute(gray.data, gray.cols, gray.rows);
          final hits = _index!.nearest(hash);

          _cardsDb ??= CardsDatabase();
          final labelled = <HashCandidate>[];
          for (final h in hits.take(3)) {
            final c = await _cardsDb!.cardById(h.id);
            labelled.add(HashCandidate(
              c == null
                  ? h.id
                  : '${c.name} · ${c.setCode.toUpperCase()} ${c.collectorNumber}',
              h.distance,
            ));
          }
          _hashHits = labelled;
          AppLogger.d('HASH-DBG ${hits.length} within ${HashIndex.matchThreshold}'
              '${hits.isEmpty ? "" : "  best=${hits.first.distance}"}'
              '${labelled.isEmpty ? "" : "  ${labelled.first.label}"}');
        } catch (e, st) {
          AppLogger.w('HASH-DBG failed', error: e, stackTrace: st);
          _hashHits = const [];
        } finally {
          gray?.dispose();
        }
      }

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
    // The duplicate slot is deliberately NOT cleared here. Expanding the list
    // sheet stops the stream, and someone checking what they have collected has
    // not told the scanner that the card in their hand is a different one —
    // clearing here re-arms the card still in view and re-adds it on the next
    // frame. The slot clears on dispose, i.e. on leaving the scanner.
    _idleFired = false;
    _lastDetectionAt = DateTime.now();
    if (_controller?.value.isStreamingImages != true) return;
    try { _controller!.stopImageStream(); } catch (_) {}
  }

  /// Calculate the crop offset for the camera preview based on aspect ratios.
  ///
  // ---------------------------------------------------------------------------
  // Capture
  // ---------------------------------------------------------------------------

  /// Identify automatically when a usable border is on screen.
  ///
  /// **Gated on [CardQuality.good], which the manual button deliberately is
  /// not.** The gate would be wrong for a button — the user pressed it, so
  /// attempt something — but it is right for a loop, where skipping a frame
  /// costs 300ms and the next one is already coming. The measurements say the
  /// same: 0 of 13 frames above the skew threshold ever produced a correct
  /// collector read, and below 6 px/mm the rate falls from 83% to 43%. Burning
  /// a full identify on those blocks the frame that would have worked.
  ///
  /// No stability gate — see "Rate Limiting Falls Out For Free" in
  /// `single_card_capture_flow.md`. Requiring N consecutive matching detections
  /// adds latency to every scan to solve what pipeline latency already solves.
  void _maybeAutoCapture() {
    if (!_loopEnabled || _capturing || !widget.isActive) return;
    final rects = _shownRects;
    if (rects.isEmpty || rects.first.quality != CardQuality.good) return;
    unawaited(_capture());
  }

  /// The scanner never saw it — open the picker's full-screen scope.
  Future<void> _manualAdd() async {
    final db = _cardsDb ??= CardsDatabase();
    if (!mounted) return;
    final picked = await CardPicker.showScreen(context, db: db);
    if (picked == null) return;
    final card = await ScanPipeline.toScryfallCard(db, picked.card);
    await widget.onCardAdded?.call(card);
  }

  /// Tell the parent the user has stopped scanning.
  ///
  /// Fires once per idle stretch, and rearms only when a card is seen again —
  /// otherwise a phone face-down on the table would fire this twice a second.
  /// What to *do* about it belongs to the parent: the overlay does not own the
  /// sheet, and expanding it is what stops the camera.
  void _checkIdle() {
    if (_idleFired || _capturing || !widget.isActive) return;
    if (DateTime.now().difference(_lastDetectionAt) < _idleAfter) return;
    _idleFired = true;
    AppLogger.d('Scanner: idle for ${_idleAfter.inSeconds}s');
    widget.onIdle?.call();
  }

  /// Colour the border for [_flashFor], then let it return to quality colours.
  void _flash(Color colour) {
    final until = DateTime.now().add(_flashFor);
    setState(() {
      _flashColour = colour;
      _flashUntil  = until;
    });
    Future.delayed(_flashFor, () {
      // Another scan may have flashed in the meantime; only clear our own.
      if (!mounted || _flashUntil != until) return;
      setState(() {
        _flashColour = null;
        _flashUntil  = null;
      });
    });
  }

  Future<void> _capture({bool manual = false}) async {
    if (!_cameraReady || _capturing || _lastFrame == null) return;
    final frame = _lastFrame!;
    final rects = _shownRects;

    if (rects.isEmpty) return;

    // The number that decides whether single-rect earns its place: how many
    // detections it discarded, and whether the kept one was the card.
    AppLogger.d('Capture: ${_liveRects.length} detected, '
        'identifying ${rects.length}'
        '${_singleRect ? " (single)" : " (all)"}'
        '${manual ? " [button]" : " [auto]"}'
        '  quality=${rects.map((r) => r.quality.name).join(",")}');

    // The preview keeps running and the border stays drawn — it turns yellow
    // instead. There is no inspection step to freeze for: the stream frame is
    // the capture (spike S3), so stopping it would only cost the next detection
    // and buy nothing.
    setState(() => _capturing = true);

    try {
      // Identification runs entirely against local data — the card database and
      // the hash index — so a scan makes no network request at all.
      final db = _cardsDb ??= CardsDatabase();
      if (!_indexTried) {
        _indexTried = true;
        _index = await HashIndex.load();
      }
      _identifier ??= CardIdentifier(db, _index);

      await ScanPipeline.run(
        frame:       frame,
        borders:     rects,
        identifier:  _identifier!,
        db:          db,
        onCardAdded: widget.onCardAdded,
        onAmbiguous: (candidates) async {
          if (!mounted) return null;
          setState(() {
            _promptOpen = true;
            // Drop the geometry the question was asked about. It stops a stale
            // border painting when the sheet closes, and makes the manual
            // capture button a no-op until a real frame arrives rather than
            // firing on a quad from before the answer.
            _liveRects = const [];
          });
          try {
            final picked = await CardPicker.showSheet(
              context,
              scope: PickerScope.chooseVersion,
              db: db,
              initial: candidates,
            );
            return picked?.card;
          } finally {
            // A `finally`, so this lifts on a pick, a skip, and a back-gesture
            // dismissal alike.
            if (mounted) setState(() => _promptOpen = false);
          }
        },
        guard: _guard,
        onResult: (i, result) {
          if (!mounted) return;
          // A duplicate is the loop working, not an outcome: it must not flash,
          // and it must not replace the chip for the card actually added.
          if (result is DuplicateResult) {
            AppLogger.d('Capture: duplicate — ${result.card.name} '
                '[${result.card.setCode.toUpperCase()} '
                '${result.card.collectorNumber}]');
            return;
          }
          _flash(result is MatchedResult ? Colors.greenAccent : Colors.redAccent);
          setState(() {
            _lastResult   = result;
            _lastResultAt = DateTime.now();
          });
        },
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Transient banner for the most recent scan.
  ///
  /// Placeholder for the last-scan bar in `single_card_capture_flow.md`, which
  /// belongs to the sheet work. Enough to confirm a card was added without
  /// interrupting the scanning rhythm.
  Widget? _buildLastResult(BuildContext context) {
    final result = _lastResult;
    final at     = _lastResultAt;
    if (result == null || at == null) return null;
    if (DateTime.now().difference(at) > const Duration(seconds: 4)) return null;

    return switch (result) {
      MatchedResult(:final card, :final entryId) => _MatchedChip(
          card:  card,
          onTap: () => widget.onEntryTapped?.call(entryId),
        ),
      FailedResult() => _FailedChip(
          ocrText: '',
          onTap:   _manualAdd,
        ),
      // Never reaches here — filtered in onResult, since a duplicate is the
      // loop working rather than an outcome to report.
      DuplicateResult() => null,
    };
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
        // Live preview — there is no other mode.
        _buildLive(context),

        // Top-right button cluster: tuning toggle.
        if (widget.showTuningButton)
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
                    _buildTuningToggleButton(),
                  ],
                ),
              ),
            ),
          ),

        // Most recent scan outcome — brief, non-blocking.
        if (_buildLastResult(context) case final banner?)
          Positioned(
            left: 12, right: 12,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: banner,
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
                card:       _ocrCardPng,
                band:       _ocrBandPng,
                text:       _ocrText,
                pxPerMm:    _ocrPxPerMm,
                busy:       _ocrBusy,
                hashes:     _hashHits,
                indexCount: _index?.count,
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
              singleRect:   _singleRect,
              loopEnabled:  _loopEnabled,
              onParamsChanged: (p) async {
                setState(() => _params = p);
                await DetectorParams.setCurrent(p);
              },
              onEdgeMapToggled: (v) => setState(() => _showEdgeMap = v),
              onSingleRectToggled: (v) => setState(() => _singleRect = v),
              onLoopToggled: (v) => setState(() {
                _loopEnabled = v;
                // Turning the loop off mid-session must not leave the last card
                // remembered — the button is then the only way to scan, and it
                // would refuse the card still in frame.
                if (!v) _guard.reset();
              }),
              onDownloadIndex:   _downloadIndex,
              onResetCardData:   _resetCardData,
              dataStatus:        _dataStatus,
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
    // Use actual frame dimensions, not the plugin's preview size.
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
            //
            // Drawn *through* identification, not hidden by it. The loop fires
            // two to three times a second, so anything that disappears while a
            // scan is in flight spends most of its life invisible.
            if (_frameSize != null)
              Positioned(
                left:   offsetX,
                top:    offsetY,
                width:  scaledW,
                height: scaledH,
                child: CustomPaint(
                  painter: CardBorderPainter(
                    rects:             _shownRects,
                    imageSize:         _frameSize!,
                    previewSize:       Size(scaledW, scaledH),
                    sensorOrientation: so,
                    cropOffset:        ui.Offset.zero,  // ← Positioned layout handles all positioning
                    // [dev-tool] Append the measured value while calibrating.
                    showQualityDetail: _tuningOpen || _showOcrDebug,
                    stateColour:       _borderState,
                  ),
                ),
              ),

            // No blocking overlay. The scan loop runs continuously, so a
            // full-screen spinner would strobe; the border colour carries the
            // same information without covering the thing being scanned.

            // Capture button — only when the parent has not taken ownership.
            if (widget.showCaptureButton)
              Positioned(
                left: 0, right: 0, bottom: 24,
                child: Center(
                  child: CaptureButton(
                    detecting: _shownRects.isNotEmpty,
                    onTap:     capture,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

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
