import 'package:shared_preferences/shared_preferences.dart';

/// All tunable parameters for [CardDetector] and [ScanPipeline].
///
/// A static singleton keeps both [ListingDetailScreen] and [QuickScanScreen]
/// in sync without threading values through the widget tree.  Any change made
/// in the tuning panel is immediately persisted via [setCurrent] so values
/// survive app restarts and version updates.
///
/// Call [loadCurrent] once (e.g. in [ScannerOverlayState.initState]) to
/// populate the singleton from [SharedPreferences]; subsequent calls are
/// instant (cached).
class DetectorParams {
  // ── Detection ──────────────────────────────────────────────────────────────

  /// Canny lower threshold. Lower = more edges detected.
  final double cannyLow;

  /// Canny upper threshold. Typically 2–3× [cannyLow].
  final double cannyHigh;

  /// GaussianBlur kernel size. Must be an odd integer: 3, 5, 7, or 9.
  final int blurKernelSize;

  /// Minimum contour area in pixels. Filters noise and tiny shapes.
  final double minArea;

  /// Maximum contour area as a fraction of the total frame area.
  final double maxAreaFraction;

  /// approxPolyDP epsilon as a fraction of the contour perimeter.
  final double polyEpsilonFraction;

  /// Number of dilation passes applied to the Canny edge map.
  final int dilationIterations;

  /// Dilation structuring element size. Must be an odd integer: 3, 5, or 7.
  final int dilationKernelSize;

  /// Portrait aspect-ratio band — lower bound.
  final double minRatioPort;

  /// Portrait aspect-ratio band — upper bound.
  final double maxRatioPort;

  /// Landscape aspect-ratio band — lower bound.
  final double minRatioLand;

  /// Landscape aspect-ratio band — upper bound.
  final double maxRatioLand;

  // ── Hough line detection ───────────────────────────────────────────────────

  /// Hough line distance resolution in pixels.
  final double houghRho;

  /// Hough line angle resolution in radians (~1 degree = pi/180).
  final double houghTheta;

  /// Minimum number of votes (edge pixels) for a line to be detected.
  final int houghThreshold;

  /// Minimum line length in pixels (cv.HoughLinesP parameter).
  final int houghMinLineLength;

  /// Maximum gap between line segments in pixels (cv.HoughLinesP parameter).
  final int houghMaxLineGap;

  // ── OCR pipeline ───────────────────────────────────────────────────────────

  /// Fraction of the display-oriented card crop used as the name strip.
  final double nameStripFraction;

  // ── Card size filtering ────────────────────────────────────────────────────

  /// Minimum card width/height in pixels. Filters out small noise.
  final int minCardPixels;

  /// Maximum card width/height in pixels. Filters out page borders and large structures.
  final int maxCardPixels;

  /// Lower bound on a detected quad's short/long side ratio.
  ///
  /// Measured on the quad's own edges, so it is invariant to in-plane rotation.
  /// A real card is 63x88mm = 0.716; the band must be wide enough to absorb the
  /// foreshortening a tilted phone introduces (~0.62 at 30 degrees).
  final double minCardAspect;

  /// Upper bound on a detected quad's short/long side ratio. Squarer shapes
  /// (binder pages, table edges) are rejected.
  final double maxCardAspect;

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  const DetectorParams({
    required this.cannyLow,
    required this.cannyHigh,
    required this.blurKernelSize,
    required this.minArea,
    required this.maxAreaFraction,
    required this.polyEpsilonFraction,
    required this.dilationIterations,
    required this.dilationKernelSize,
    required this.minRatioPort,
    required this.maxRatioPort,
    required this.minRatioLand,
    required this.maxRatioLand,
    required this.houghRho,
    required this.houghTheta,
    required this.houghThreshold,
    required this.houghMinLineLength,
    required this.houghMaxLineGap,
    required this.nameStripFraction,
    required this.minCardPixels,
    required this.maxCardPixels,
    required this.minCardAspect,
    required this.maxCardAspect,
  });

  /// Factory-style const constructor with the tuned baseline values.
  const DetectorParams.defaults()
      : cannyLow            = 20,
        cannyHigh           = 60,
        blurKernelSize      = 5,
        minArea             = 2000,
        maxAreaFraction     = 0.70,
        polyEpsilonFraction = 0.03,
        dilationIterations  = 2,
        dilationKernelSize  = 3,
        minRatioPort        = 0.32,
        maxRatioPort        = 0.80,
        minRatioLand        = 0.80,
        maxRatioLand        = 1.60,
        houghRho            = 1.0,
        houghTheta          = 0.01745, // ~1 degree in radians (pi/180)
        houghThreshold      = 50,
        houghMinLineLength  = 100,
        houghMaxLineGap     = 20,
        nameStripFraction   = 0.15,
        minCardPixels       = 100,     // Minimum card dimension in pixels
        maxCardPixels       = 400,     // Maximum card dimension in pixels
        minCardAspect       = 0.55,    // ~30 degrees of tilt below 0.716
        maxCardAspect       = 0.85;    // above this it is a squarer object

  DetectorParams copyWith({
    double? cannyLow,
    double? cannyHigh,
    int?    blurKernelSize,
    double? minArea,
    double? maxAreaFraction,
    double? polyEpsilonFraction,
    int?    dilationIterations,
    int?    dilationKernelSize,
    double? minRatioPort,
    double? maxRatioPort,
    double? minRatioLand,
    double? maxRatioLand,
    double? houghRho,
    double? houghTheta,
    int?    houghThreshold,
    int?    houghMinLineLength,
    int?    houghMaxLineGap,
    double? nameStripFraction,
    int?    minCardPixels,
    int?    maxCardPixels,
    double? minCardAspect,
    double? maxCardAspect,
  }) => DetectorParams(
    cannyLow:            cannyLow            ?? this.cannyLow,
    cannyHigh:           cannyHigh           ?? this.cannyHigh,
    blurKernelSize:      blurKernelSize      ?? this.blurKernelSize,
    minArea:             minArea             ?? this.minArea,
    maxAreaFraction:     maxAreaFraction     ?? this.maxAreaFraction,
    polyEpsilonFraction: polyEpsilonFraction ?? this.polyEpsilonFraction,
    dilationIterations:  dilationIterations  ?? this.dilationIterations,
    dilationKernelSize:  dilationKernelSize  ?? this.dilationKernelSize,
    minRatioPort:        minRatioPort        ?? this.minRatioPort,
    maxRatioPort:        maxRatioPort        ?? this.maxRatioPort,
    minRatioLand:        minRatioLand        ?? this.minRatioLand,
    maxRatioLand:        maxRatioLand        ?? this.maxRatioLand,
    houghRho:            houghRho            ?? this.houghRho,
    houghTheta:          houghTheta          ?? this.houghTheta,
    houghThreshold:      houghThreshold      ?? this.houghThreshold,
    houghMinLineLength:  houghMinLineLength  ?? this.houghMinLineLength,
    houghMaxLineGap:     houghMaxLineGap     ?? this.houghMaxLineGap,
    nameStripFraction:   nameStripFraction   ?? this.nameStripFraction,
    minCardPixels:       minCardPixels       ?? this.minCardPixels,
    maxCardPixels:       maxCardPixels       ?? this.maxCardPixels,
    minCardAspect:       minCardAspect       ?? this.minCardAspect,
    maxCardAspect:       maxCardAspect       ?? this.maxCardAspect,
  );

  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static DetectorParams _current = const DetectorParams.defaults();
  static bool           _loaded  = false;

  /// The current in-memory params.  Always valid (at worst returns defaults).
  static DetectorParams get current => _current;

  /// Loads persisted params from [SharedPreferences].
  /// Subsequent calls return immediately from cache.
  static Future<DetectorParams> loadCurrent() async {
    if (_loaded) return _current;
    _current = await _fromPrefs();
    _loaded  = true;
    return _current;
  }

  /// Replaces the singleton and persists to [SharedPreferences].
  static Future<void> setCurrent(DetectorParams p) async {
    _current = p;
    await _save(p);
  }

  // ---------------------------------------------------------------------------
  // SharedPreferences persistence
  // ---------------------------------------------------------------------------

  static const String _pfx = 'detector_params.';

  static Future<DetectorParams> _fromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const d = DetectorParams.defaults();
    return DetectorParams(
      cannyLow:            prefs.getDouble('${_pfx}canny_low')             ?? d.cannyLow,
      cannyHigh:           prefs.getDouble('${_pfx}canny_high')            ?? d.cannyHigh,
      blurKernelSize:      prefs.getInt   ('${_pfx}blur_kernel_size')      ?? d.blurKernelSize,
      minArea:             prefs.getDouble('${_pfx}min_area')              ?? d.minArea,
      maxAreaFraction:     prefs.getDouble('${_pfx}max_area_fraction')     ?? d.maxAreaFraction,
      polyEpsilonFraction: prefs.getDouble('${_pfx}poly_epsilon_fraction') ?? d.polyEpsilonFraction,
      dilationIterations:  prefs.getInt   ('${_pfx}dilation_iterations')   ?? d.dilationIterations,
      dilationKernelSize:  prefs.getInt   ('${_pfx}dilation_kernel_size')  ?? d.dilationKernelSize,
      minRatioPort:        prefs.getDouble('${_pfx}min_ratio_port')        ?? d.minRatioPort,
      maxRatioPort:        prefs.getDouble('${_pfx}max_ratio_port')        ?? d.maxRatioPort,
      minRatioLand:        prefs.getDouble('${_pfx}min_ratio_land')        ?? d.minRatioLand,
      maxRatioLand:        prefs.getDouble('${_pfx}max_ratio_land')        ?? d.maxRatioLand,
      houghRho:            prefs.getDouble('${_pfx}hough_rho')             ?? d.houghRho,
      houghTheta:          prefs.getDouble('${_pfx}hough_theta')           ?? d.houghTheta,
      houghThreshold:      prefs.getInt   ('${_pfx}hough_threshold')       ?? d.houghThreshold,
      houghMinLineLength:  prefs.getInt   ('${_pfx}hough_min_line_length') ?? d.houghMinLineLength,
      houghMaxLineGap:     prefs.getInt   ('${_pfx}hough_max_line_gap')    ?? d.houghMaxLineGap,
      nameStripFraction:   prefs.getDouble('${_pfx}name_strip_fraction')   ?? d.nameStripFraction,
      minCardPixels:       prefs.getInt   ('${_pfx}min_card_pixels')       ?? d.minCardPixels,
      maxCardPixels:       prefs.getInt   ('${_pfx}max_card_pixels')       ?? d.maxCardPixels,
      minCardAspect:       prefs.getDouble('${_pfx}min_card_aspect')       ?? d.minCardAspect,
      maxCardAspect:       prefs.getDouble('${_pfx}max_card_aspect')       ?? d.maxCardAspect,
    );
  }

  static Future<void> _save(DetectorParams p) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setDouble('${_pfx}canny_low',             p.cannyLow),
      prefs.setDouble('${_pfx}canny_high',            p.cannyHigh),
      prefs.setInt   ('${_pfx}blur_kernel_size',      p.blurKernelSize),
      prefs.setDouble('${_pfx}min_area',              p.minArea),
      prefs.setDouble('${_pfx}max_area_fraction',     p.maxAreaFraction),
      prefs.setDouble('${_pfx}poly_epsilon_fraction', p.polyEpsilonFraction),
      prefs.setInt   ('${_pfx}dilation_iterations',   p.dilationIterations),
      prefs.setInt   ('${_pfx}dilation_kernel_size',  p.dilationKernelSize),
      prefs.setDouble('${_pfx}min_ratio_port',        p.minRatioPort),
      prefs.setDouble('${_pfx}max_ratio_port',        p.maxRatioPort),
      prefs.setDouble('${_pfx}min_ratio_land',        p.minRatioLand),
      prefs.setDouble('${_pfx}max_ratio_land',        p.maxRatioLand),
      prefs.setDouble('${_pfx}hough_rho',             p.houghRho),
      prefs.setDouble('${_pfx}hough_theta',           p.houghTheta),
      prefs.setInt   ('${_pfx}hough_threshold',       p.houghThreshold),
      prefs.setInt   ('${_pfx}hough_min_line_length', p.houghMinLineLength),
      prefs.setInt   ('${_pfx}hough_max_line_gap',    p.houghMaxLineGap),
      prefs.setDouble('${_pfx}name_strip_fraction',   p.nameStripFraction),
      prefs.setInt   ('${_pfx}min_card_pixels',       p.minCardPixels),
      prefs.setInt   ('${_pfx}max_card_pixels',       p.maxCardPixels),
      prefs.setDouble('${_pfx}min_card_aspect',       p.minCardAspect),
      prefs.setDouble('${_pfx}max_card_aspect',       p.maxCardAspect),
    ]);
  }
}
