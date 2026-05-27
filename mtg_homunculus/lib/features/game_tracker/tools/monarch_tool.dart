import 'package:flutter/material.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/toolbelt_tool.dart';
import '../widgets/gt_game_scope.dart';

class MonarchTool extends EffectTool<MonarchEffect> {
  const MonarchTool()
      : super(icon: Icons.emoji_events_outlined, label: 'Monarch');

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget buildIcon(GameState game) {
    const crown = Text('👑', style: TextStyle(fontSize: 22));
    if (game.effects.any((e) => e is MonarchEffect)) return crown;
    return ColorFiltered(
      colorFilter: _grayscale,
      child: Opacity(opacity: 0.45, child: crown),
    );
  }

  @override
  Color? activeBorderColor(GameState game) {
    return game.effects.any((e) => e is MonarchEffect)
        ? const Color(0xFFFFD700)
        : null;
  }

  @override
  void onTap(BuildContext context) {
    final scope = GtGameScope.of(context);
    final onPickReq = scope.onPickRequestChanged;
    final onGameChanged = scope.onGameChanged;
    final game = scope.game;

    onPickReq(PlayerPickRequest(
      title: 'Who is the Monarch?',
      onPick: (playerId) {
        onPickReq(null);
        onGameChanged(game.setEffect(MonarchEffect(playerId)));
      },
      onCancel: () {},
    ));
  }
}
