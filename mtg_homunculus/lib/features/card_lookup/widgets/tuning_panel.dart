import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/detector_params.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Semi-transparent parameter-tuning panel rendered over the scanner.
///
/// Shows all [DetectorParams] fields as interactive controls (sliders,
/// segmented buttons, text field) grouped into high-impact and lower-impact
/// sections.  Changes are reported immediately via [onParamsChanged] so the
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
  late final TextEditingController _minAreaCtrl;

  @override
  void initState() {
    super.initState();
    _minAreaCtrl = TextEditingController(
      text: widget.params.minArea.toInt().toString(),
    );
  }

  @override
  void didUpdateWidget(TuningPanel old) {
    super.didUpdateWidget(old);
    // Sync text field if params were reset from outside (e.g. "Reset defaults").
    if (old.params.minArea != widget.params.minArea) {
      _minAreaCtrl.text = widget.params.minArea.toInt().toString();
    }
  }

  @override
  void dispose() {
    _minAreaCtrl.dispose();
    super.dispose();
  }

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

                  _buildMinAreaField(context),
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
                  _buildRangeSlider(
                    context,
                    label:    'Portrait Aspect Ratio',
                    hint:     'Range: 0.1–1.5 · MTG portrait ≈ 0.72 · Default: 0.32 / 0.80',
                    low:      _p.minRatioPort,
                    high:     _p.maxRatioPort,
                    min:      0.1,
                    max:      1.5,
                    decimals: 2,
                    onChanged: (low, high) => _update(
                      _p.copyWith(minRatioPort: low, maxRatioPort: high),
                    ),
                  ),
                  _buildRangeSlider(
                    context,
                    label:    'Landscape Aspect Ratio',
                    hint:     'Range: 0.5–3.0 · Default: 0.80 / 1.60',
                    low:      _p.minRatioLand,
                    high:     _p.maxRatioLand,
                    min:      0.5,
                    max:      3.0,
                    decimals: 2,
                    onChanged: (low, high) => _update(
                      _p.copyWith(minRatioLand: low, maxRatioLand: high),
                    ),
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

  /// RangeSlider for paired min/max values — enforces low < high.
  Widget _buildRangeSlider(
    BuildContext context, {
    required String label,
    required String hint,
    required double low,
    required double high,
    required double min,
    required double max,
    required int    decimals,
    required void Function(double low, double high) onChanged,
  }) => _ControlRow(
    label: label,
    value: '${low.toStringAsFixed(decimals)} / ${high.toStringAsFixed(decimals)}',
    hint:  hint,
    child: RangeSlider(
      values:    RangeValues(low, high),
      min:       min,
      max:       max,
      onChanged: (v) => onChanged(v.start, v.end),
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

  /// Min area — plain text field (no meaningful upper bound).
  Widget _buildMinAreaField(BuildContext context) => _ControlRow(
    label: 'Min Area (px²)',
    value: '',           // value shown inside the text field itself
    hint:  'Positive integer · Default: 2000',
    child: TextField(
      controller:   _minAreaCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense:       true,
        border:        const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffixText:    'px²',
        suffixStyle:   Theme.of(context).textTheme.bodySmall,
      ),
      onChanged: (s) {
        final v = double.tryParse(s);
        if (v != null && v > 0) _update(_p.copyWith(minArea: v));
      },
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
