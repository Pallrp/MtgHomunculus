import 'package:flutter/material.dart';

/// A labelled continuous slider with a live value readout.
///
/// [formatValue] controls the display string for the current value.
/// Defaults to one decimal place if omitted.
class SettingSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? formatValue;
  final ValueChanged<double> onChanged;

  const SettingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.formatValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = formatValue?.call(value) ?? value.toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              Text(displayValue, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
