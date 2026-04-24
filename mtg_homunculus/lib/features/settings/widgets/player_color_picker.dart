import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../app_theme.dart';
import '../../game_tracker/models/game_state.dart'; // kPlayerColors
import '../services/settings_service.dart';

class PlayerColorPicker extends StatefulWidget {
  final List<Color> colors;
  final SettingsService service;
  final void Function(List<Color>) onColorsChanged;

  const PlayerColorPicker({
    super.key,
    required this.colors,
    required this.service,
    required this.onColorsChanged,
  });

  @override
  State<PlayerColorPicker> createState() => _PlayerColorPickerState();
}

class _PlayerColorPickerState extends State<PlayerColorPicker> {
  late List<Color> _colors;

  static const List<String> _labels = ['P1', 'P2', 'P3', 'P4', 'P5', 'P6'];

  @override
  void initState() {
    super.initState();
    _colors = List.from(widget.colors);
  }

  void _updateColor(int index, Color color) {
    setState(() => _colors[index] = color);
    widget.service.setPlayerColors(_colors);
    widget.onColorsChanged(List.from(_colors));
  }

  void _resetToDefaults() {
    setState(() => _colors = List.from(kPlayerColors));
    widget.service.setPlayerColors(_colors);
    widget.onColorsChanged(List.from(_colors));
  }

  Future<void> _openPicker(int index) async {
    Color draft = _colors[index];

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.dialogBg,
        shape: AppTheme.dialogShape,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Player ${index + 1} Color',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ColorPicker(
                pickerColor: draft,
                onColorChanged: (c) => draft = c,
                enableAlpha: false,
                labelTypes: const [],
                pickerAreaHeightPercent: 0.5,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _updateColor(index, draft);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Colors'),
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tap a swatch to change the default color for that player slot.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: List.generate(
                _colors.length,
                (i) => GestureDetector(
                  onTap: () => _openPicker(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _colors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _colors[i].withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _labels[i],
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
