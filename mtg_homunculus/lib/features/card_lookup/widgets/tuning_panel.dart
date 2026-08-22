import 'package:flutter/material.dart';

import '../models/detector_params.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Semi-transparent parameter-tuning panel rendered over the scanner.
///
/// Shows all [DetectorParams] fields as interactive controls (sliders and
/// segmented buttons) grouped into high-impact and lower-impact sections.  Changes are reported immediately via [onParamsChanged] so the
/// caller can hot-reload detection without any explicit "Apply" step.
///
/// The panel does not persist values itself — the caller is responsible for
/// calling [DetectorParams.setCurrent] from [onParamsChanged].
class TuningPanel extends StatefulWidget {
  final DetectorParams params;
  final bool           showEdgeMap;

  final void Function(DetectorParams) onParamsChanged;
  final void Function(bool)           onEdgeMapToggled;
  final VoidCallback                  onClose;

  const TuningPanel({
    super.key,
    required this.params,
    required this.showEdgeMap,
    required this.onParamsChanged,
    required this.onEdgeMapToggled,
    required this.onClose,
  });

  @override
  State<TuningPanel> createState() => _TuningPanelState();
}

class _TuningPanelState extends State<TuningPanel> {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DetectorParams get _p => widget.params;

  void _update(DetectorParams next) => widget.onParamsChanged(next);

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.65;

    return Material(
      elevation:   16,
      color:       cs.surface.withValues(alpha: 0.96),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(context),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _buildEdgeToggle(context),
                  const SizedBox(height: 8),
                  _buildResetRow(context),
                  const SizedBox(height: 12),

                  // ── HIGH IMPACT ──────────────────────────────────────────
                  _sectionLabel(context, 'HIGH IMPACT'),
                  const Divider(height: 8),
                  const SizedBox(height: 4),

                  _buildCannySlider(context),
                  _buildSegmented(
                    context,
                    label:   'Blur Kernel Size',
                    hint:    'Odd values only · Default: 5',
                    value:   _p.blurKernelSize,
                    options: const [3, 5, 7, 9],
                    onChanged: (v) => _update(_p.copyWith(blurKernelSize: v)),
                  ),
                  _buildIntSlider(
                    context,
                    label:    'Dilation Iterations',
                    hint:     'Range: 0–10 · Default: 2',
                    value:    _p.dilationIterations,
                    min:      0,
                    max:      10,
                    onChanged: (v) => _update(_p.copyWith(dilationIterations: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Poly Epsilon Fraction',
                    hint:     'Range: 0.005–0.15 · Default: 0.03',
                    value:    _p.polyEpsilonFraction,
                    min:      0.005,
                    max:      0.15,
                    decimals: 3,
                    onChanged: (v) => _update(_p.copyWith(polyEpsilonFraction: v)),
                  ),

                  const SizedBox(height: 12),

                  // ── LOWER IMPACT ─────────────────────────────────────────
                  _sectionLabel(context, 'LOWER IMPACT'),
                  const Divider(height: 8),
                  const SizedBox(height: 4),

                  _buildFloatSlider(
                    context,
                    label:    'Min Area Fraction',
                    hint:     'Of shortSide² · Range: 0.002–0.10 · Default: 0.02',
                    value:    _p.minAreaFraction,
                    min:      0.002,
                    max:      0.10,
                    decimals: 3,
                    onChanged: (v) => _update(_p.copyWith(minAreaFraction: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Max Area Fraction',
                    hint:     'Range: 0.01–1.0 · Default: 0.70',
                    value:    _p.maxAreaFraction,
                    min:      0.01,
                    max:      1.0,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(maxAreaFraction: v)),
                  ),
                  _buildSegmented(
                    context,
                    label:   'Dilation Kernel Size',
                    hint:    'Odd values only · Default: 3',
                    value:   _p.dilationKernelSize,
                    options: const [3, 5, 7],
                    onChanged: (v) => _update(_p.copyWith(dilationKernelSize: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Min Card Fraction',
                    hint:     'Of the frame\'s short side · Range: 0.05–0.50 · Default: 0.15',
                    value:    _p.minCardFraction,
                    min:      0.05,
                    max:      0.50,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(minCardFraction: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Max Card Fraction',
                    hint:     'Of the frame\'s short side · Range: 0.30–1.20 · Default: 0.95',
                    value:    _p.maxCardFraction,
                    min:      0.30,
                    max:      1.20,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(maxCardFraction: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Min Card Aspect',
                    hint:     'Short/long side ratio · A card is 0.72 · Range: 0.30–0.72 · Default: 0.55',
                    value:    _p.minCardAspect,
                    min:      0.30,
                    max:      0.72,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(minCardAspect: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Max Card Aspect',
                    hint:     'Rejects squarer shapes (binder pages) · Range: 0.72–1.00 · Default: 0.85',
                    value:    _p.maxCardAspect,
                    min:      0.72,
                    max:      1.00,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(maxCardAspect: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Name Strip Fraction',
                    hint:     'Range: 0.05–0.40 · Default: 0.15',
                    value:    _p.nameStripFraction,
                    min:      0.05,
                    max:      0.40,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(nameStripFraction: v)),
                  ),

                  const SizedBox(height: 12),

                  // ── HOUGH LINE DETECTION ────────────────────────────────────
                  _sectionLabel(context, 'HOUGH LINE DETECTION'),
                  const Divider(height: 8),
                  const SizedBox(height: 4),

                  _buildFloatSlider(
                    context,
                    label:    'Hough Rho',
                    hint:     'Distance resolution (px) · Range: 0.5–2.0 · Default: 1.0',
                    value:    _p.houghRho,
                    min:      0.5,
                    max:      2.0,
                    decimals: 1,
                    onChanged: (v) => _update(_p.copyWith(houghRho: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Hough Theta',
                    hint:     'Angle resolution (rad) · Range: 0.005–0.05 · Default: 0.0175 (~1°)',
                    value:    _p.houghTheta,
                    min:      0.005,
                    max:      0.05,
                    decimals: 4,
                    onChanged: (v) => _update(_p.copyWith(houghTheta: v)),
                  ),
                  _buildIntSlider(
                    context,
                    label:    'Hough Threshold',
                    hint:     'Min votes for line detection · Range: 10–200 · Default: 50',
                    value:    _p.houghThreshold,
                    min:      10,
                    max:      200,
                    onChanged: (v) => _update(_p.copyWith(houghThreshold: v)),
                  ),
                  _buildFloatSlider(
                    context,
                    label:    'Hough Min Line Fraction',
                    hint:     'Of the frame\'s short side · Range: 0.03–0.40 · Default: 0.10',
                    value:    _p.houghMinLineFraction,
                    min:      0.03,
                    max:      0.40,
                    decimals: 2,
                    onChanged: (v) => _update(_p.copyWith(houghMinLineFraction: v)),
                  ),
                  _buildIntSlider(
                    context,
                    label:    'Hough Max Line Gap',
                    hint:     'Max gap between segments (px) · Range: 5–50 · Default: 20',
                    value:    _p.houghMaxLineGap,
                    min:      5,
                    max:      50,
                    onChanged: (v) => _update(_p.copyWith(houghMaxLineGap: v)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header widgets
  // ---------------------------------------------------------------------------

  Widget _buildHandle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Text(
            'Scanner Tuning',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon:      const Icon(Icons.close_rounded),
            onPressed: widget.onClose,
            tooltip:   'Close tuning panel',
            color:     cs.onSurface,
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeToggle(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Show edge overlay'),
    subtitle: const Text(
      'Replaces the camera feed with the Canny + dilation output',
    ),
    value:    widget.showEdgeMap,
    onChanged: widget.onEdgeMapToggled,
  );

  Widget _buildResetRow(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      icon:      const Icon(Icons.restart_alt_rounded, size: 16),
      label:     const Text('Reset to defaults'),
      onPressed: () {
        _update(const DetectorParams.defaults());
        // Text field syncs via didUpdateWidget.
      },
    ),
  );

  // ---------------------------------------------------------------------------
  // Section label
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color:          Theme.of(context).colorScheme.primary,
        fontWeight:     FontWeight.w700,
        letterSpacing:  1.2,
      ),
    ),
  );

  // ---------------------------------------------------------------------------
  // Control builders
  // ---------------------------------------------------------------------------

  /// Canny thresholds — RangeSlider so low < high is always enforced.
  Widget _buildCannySlider(BuildContext context) {
    return _ControlRow(
      label:   'Canny Thresholds',
      value:   '${_p.cannyLow.toInt()} / ${_p.cannyHigh.toInt()}',
      hint:    'Range: 0–255 · Low must be < High · Default: 20 / 60',
      child: RangeSlider(
        values: RangeValues(_p.cannyLow, _p.cannyHigh),
        min:    0,
        max:    255,
        onChanged: (v) => _update(
          _p.copyWith(cannyLow: v.start, cannyHigh: v.end),
        ),
      ),
    );
  }

  /// Integer-valued slider.
  Widget _buildIntSlider(
    BuildContext context, {
    required String label,
    required String hint,
    required int value,
    required int min,
    required int max,
    required void Function(int) onChanged,
  }) => _ControlRow(
    label: label,
    value: '$value',
    hint:  hint,
    child: Slider(
      value:      value.toDouble(),
      min:        min.toDouble(),
      max:        max.toDouble(),
      divisions:  max - min,
      onChanged:  (v) => onChanged(v.round()),
    ),
  );

  /// Continuous float slider.
  Widget _buildFloatSlider(
    BuildContext context, {
    required String label,
    required String hint,
    required double value,
    required double min,
    required double max,
    required int    decimals,
    required void Function(double) onChanged,
  }) => _ControlRow(
    label: label,
    value: value.toStringAsFixed(decimals),
    hint:  hint,
    child: Slider(
      value:     value,
      min:       min,
      max:       max,
      onChanged: onChanged,
    ),
  );

  /// Segmented button for discrete odd-integer choices.
  Widget _buildSegmented(
    BuildContext context, {
    required String    label,
    required String    hint,
    required int       value,
    required List<int> options,
    required void Function(int) onChanged,
  }) => _ControlRow(
    label: label,
    value: '$value',
    hint:  hint,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SegmentedButton<int>(
        segments: [
          for (final o in options)
            ButtonSegment(value: o, label: Text('$o')),
        ],
        selected:          {value},
        onSelectionChanged: (s) => onChanged(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ),
  );

}

// ---------------------------------------------------------------------------
// Shared layout row
// ---------------------------------------------------------------------------

class _ControlRow extends StatelessWidget {
  final String label;
  final String value; // current value shown next to label; pass '' for text fields
  final String hint;  // limit / default reminder shown below the control
  final Widget child;

  const _ControlRow({
    required this.label,
    required this.value,
    required this.hint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.bodyMedium;
    final hintStyle  = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row with current value on the right.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: labelStyle),
              if (value.isNotEmpty)
                Text(
                  value,
                  style: labelStyle?.copyWith(
                    color:      cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          // The control (slider, segmented button, text field, etc.).
          child,
          // Hint text — limit info and default value.
          Text(hint, style: hintStyle),
        ],
      ),
    );
  }
}
