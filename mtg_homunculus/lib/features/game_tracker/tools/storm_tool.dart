import 'package:flutter/material.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/toolbelt_tool.dart';
import '../widgets/gt_game_scope.dart';

class StormTool extends EffectTool<StormEffect> {
  const StormTool()
      : super(icon: Icons.thunderstorm_outlined, label: 'Storm');

  static const _activeColor = Color(0xFFB0D8FF);

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget buildIcon(GameState game) {
    final storm = game.storm;
    if (storm == null) {
      return ColorFiltered(
        colorFilter: _grayscale,
        child: const Opacity(
          opacity: 0.45,
          child: Icon(Icons.thunderstorm_outlined, size: 28),
        ),
      );
    }
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 0.2,
            child: Icon(Icons.thunderstorm_outlined, size: 28, color: _activeColor),
          ),
          Text(
            '${storm.count}',
            style: const TextStyle(
              color: _activeColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Color? activeBorderColor(GameState game) =>
      game.storm != null ? _activeColor : null;

  @override
  void onTap(BuildContext context) {
    final scope = GtGameScope.of(context);
    final game = scope.game;
    final storm = game.storm;
    scope.onGameChanged(game.setEffect(
      StormEffect(count: storm == null ? 1 : storm.count + 1),
    ));
  }

  // Called repeatedly by ToolbeltToolItem while the user holds the tool.
  @override
  void onLongPress(BuildContext context) {
    final scope = GtGameScope.of(context);
    final game = scope.game;
    final storm = game.storm;
    if (storm == null || storm.count <= 0) return;
    scope.onGameChanged(game.setEffect(StormEffect(count: storm.count - 1)));
  }
}
