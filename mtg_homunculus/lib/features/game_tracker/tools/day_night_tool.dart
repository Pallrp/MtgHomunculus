import 'package:flutter/material.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/toolbelt_tool.dart';
import '../widgets/gt_game_scope.dart';

class DayNightTool extends EffectTool<DayNightEffect> {
  const DayNightTool()
      : super(icon: Icons.wb_twilight_rounded, label: 'Day/Night');

  static const _dayColor   = Color(0xFFFFA000); // amber
  static const _nightColor = Color(0xFF283593); // dark indigo

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget buildIcon(GameState game) {
    final dn = game.dayNight;
    if (dn == null) {
      return ColorFiltered(
        colorFilter: _grayscale,
        child: const Opacity(
          opacity: 0.45,
          child: Icon(Icons.wb_twilight_rounded, size: 28),
        ),
      );
    }
    if (dn.isDay) return const Icon(Icons.wb_sunny_outlined, size: 28, color: _dayColor);
    return const Icon(Icons.nightlight_round, size: 28, color: _nightColor);
  }

  @override
  Color? activeBorderColor(GameState game) {
    final dn = game.dayNight;
    if (dn == null) return null;
    return dn.isDay ? _dayColor : _nightColor;
  }

  @override
  void onTap(BuildContext context) {
    final scope = GtGameScope.of(context);
    final game = scope.game;
    final dn = game.dayNight;
    scope.onGameChanged(game.setEffect(
      dn == null ? const DayNightEffect(isDay: true) : DayNightEffect(isDay: !dn.isDay),
    ));
  }
}
