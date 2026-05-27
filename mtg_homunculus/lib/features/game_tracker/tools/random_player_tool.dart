import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/toolbelt_tool.dart';
import '../widgets/gt_game_scope.dart';

class RandomPlayerTool extends ToolbeltTool {
  const RandomPlayerTool()
      : super(icon: Icons.shuffle_rounded, label: 'Random');

  @override
  Widget buildIcon(GameState game) =>
      const Icon(Icons.shuffle_rounded, size: 28);

  @override
  void onTap(BuildContext context) {
    final scope = GtGameScope.of(context);
    final onPickReq = scope.onPickRequestChanged;
    final onStartRoulette = scope.onStartRandomRoulette;
    final players = scope.game.players;

    onPickReq(PlayerPickRequest(
      title: 'Tap a player to exclude them — or tap the diamond to include all',
      // Diamond label overrides "Cancel" for this pick phase.
      diamondLabel: 'All',
      // Diamond tap → include all players in the pool.
      onDiamondActivate: () {
        onPickReq(null);
        onStartRoulette?.call(players.map((p) => p.id).toList());
      },
      // Card tap → exclude that player; their opponents form the pool.
      onPick: (playerId) {
        onPickReq(null);
        final pool = players
            .where((p) => p.id != playerId)
            .map((p) => p.id)
            .toList();
        if (pool.isEmpty) return; // guard: can't randomise with no candidates
        onStartRoulette?.call(pool);
      },
      onCancel: () {},
    ));
  }
}
