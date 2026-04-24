import 'package:flutter/material.dart';

/// A labelled group of 2–4 mutually exclusive options backed by [SegmentedButton].
///
/// Use [enabledWhen] to grey out options that are not yet implemented
/// (e.g. AppThemeMode.custom while color picking is iceboxed).
class SettingSegment<T> extends StatelessWidget {
  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T)? enabledWhen;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingSegment({
    super.key,
    required this.label,
    required this.options,
    required this.labelOf,
    this.enabledWhen,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<T>(
            showSelectedIcon: false,
            segments: options
                .map((o) => ButtonSegment<T>(
                      value: o,
                      label: Text(labelOf(o)),
                      enabled: enabledWhen?.call(o) ?? true,
                    ))
                .toList(),
            selected: {value},
            onSelectionChanged: (set) => onChanged(set.first),
          ),
        ],
      ),
    );
  }
}
