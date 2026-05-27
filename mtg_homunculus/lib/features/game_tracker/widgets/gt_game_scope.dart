import 'package:flutter/widgets.dart';
import '../models/game_state.dart';

/// A tool calls [GtGameScope.onPickRequestChanged] with a [PlayerPickRequest]
/// to activate the in-game player-pick overlay. The screen and grid react
/// generically — no tool-specific checks needed anywhere in the screen layer.
class PlayerPickRequest {
  final String? title;
  final void Function(String playerId) onPick;
  final VoidCallback onCancel;
  // When set, the diamond shows this label instead of "Cancel".
  final String? diamondLabel;
  // When set, diamond tap calls this instead of onCancel.
  final VoidCallback? onDiamondActivate;

  const PlayerPickRequest({
    this.title,
    required this.onPick,
    required this.onCancel,
    this.diamondLabel,
    this.onDiamondActivate,
  });
}

class GtGameScope extends InheritedWidget {
  final GameState game;
  // Tools call GameState's own mutation methods and pass the result here.
  final void Function(GameState) onGameChanged;
  // Non-null while a player-pick overlay is active.
  final PlayerPickRequest? playerPickRequest;
  final void Function(PlayerPickRequest?) onPickRequestChanged;
  // Called by RandomPlayerTool to hand the roulette pool to the screen.
  // The screen owns the animation state; the tool only knows the pool.
  final void Function(List<String> playerIds)? onStartRandomRoulette;

  const GtGameScope({
    super.key,
    required this.game,
    required this.onGameChanged,
    required this.onPickRequestChanged,
    this.playerPickRequest,
    this.onStartRandomRoulette,
    required super.child,
  });

  static GtGameScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GtGameScope>()!;

  @override
  bool updateShouldNotify(GtGameScope old) =>
      game != old.game ||
      playerPickRequest != old.playerPickRequest ||
      onStartRandomRoulette != old.onStartRandomRoulette;
}
