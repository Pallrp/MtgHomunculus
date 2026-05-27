import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/toolbelt_tool.dart';
import '../widgets/gt_game_scope.dart';

class InitiativeTool extends EffectTool<InitiativeEffect> {
  const InitiativeTool()
      : super(icon: Icons.flag_outlined, label: 'Initiative');

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  static const _activeColor = Color(0xFF9B59B6);

  @override
  Widget buildIcon(GameState game) {
    final isActive = game.effects.any((e) => e is InitiativeEffect);
    if (isActive) return const Icon(Symbols.gate, size: 28, color: _activeColor);
    return ColorFiltered(
      colorFilter: _grayscale,
      child: const Opacity(opacity: 0.45, child: Icon(Symbols.gate, size: 28)),
    );
  }

  @override
  Color? activeBorderColor(GameState game) {
    return game.effects.any((e) => e is InitiativeEffect) ? _activeColor : null;
  }

  @override
  void onTap(BuildContext context) {
    final scope = GtGameScope.of(context);
    final onPickReq = scope.onPickRequestChanged;
    final onGameChanged = scope.onGameChanged;
    final game = scope.game;

    onPickReq(PlayerPickRequest(
      title: 'Who has the Initiative?',
      onPick: (playerId) {
        onPickReq(null);
        onGameChanged(game.setEffect(InitiativeEffect(playerId)));
      },
      onCancel: () {},
    ));
  }
}
