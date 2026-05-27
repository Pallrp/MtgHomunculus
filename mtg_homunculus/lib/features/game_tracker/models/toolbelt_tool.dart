import 'package:flutter/material.dart';
import 'game_effect.dart';
import 'game_state.dart';

abstract class ToolbeltTool {
  final IconData icon;
  final String label;
  const ToolbeltTool({required this.icon, required this.label});

  // Primary gesture.
  void onTap(BuildContext context);

  // Secondary gesture — default no-op. Override for increment/decrement etc.
  void onLongPress(BuildContext context) {}

  // Icon widget shown in the strip. Override to display runtime state
  // (storm count, day/night symbol, active indicator, etc.).
  Widget buildIcon(GameState game) => Icon(icon, size: 28);

  // When non-null, ToolbeltToolItem draws a subtle border of this color around
  // the icon to indicate the tool is active. Return null when inactive.
  // May return different colors for different states (e.g. Day vs Night).
  Color? activeBorderColor(GameState game) => null;
}

// Associates a tool with its GameEffect type for type-safe clearEffect<T> calls.
abstract class EffectTool<T extends GameEffect> extends ToolbeltTool {
  const EffectTool({required super.icon, required super.label});

  // Returns true when this tool manages the given effect instance.
  // Used by GameGrid to dispatch badge taps without naming specific tools.
  bool handlesEffect(GameEffect effect) => effect is T;
}

// Tools that never write to GameState.
class UtilityTool extends ToolbeltTool {
  final void Function(BuildContext) _action;
  const UtilityTool({
    required super.icon,
    required super.label,
    required void Function(BuildContext) action,
  }) : _action = action;

  @override
  void onTap(BuildContext context) => _action(context);
}
