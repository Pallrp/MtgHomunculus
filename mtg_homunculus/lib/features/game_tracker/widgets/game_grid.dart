import 'package:flutter/material.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/players_by_position.dart';
import '../models/toolbelt_tool.dart';
import '../models/toolbelt_tools.dart';
import 'gt_game_scope.dart';
import 'player_card.dart';
import 'player_grid_layout.dart';

typedef OnLifeChange      = void Function(String playerId, int delta);
typedef OnCommanderDamage = void Function(String defenderId, String attackerId, int delta);

class GameGrid extends StatelessWidget {
  final GameState game;
  final bool choosingStarter;
  // Index (into game.players) of the card currently highlighted by GAMBA spin. -1 = none.
  final int gambaHighlightIndex;
  // Index of the GAMBA winner during the OK phase. -1 = not in OK phase.
  final int gambaWinnerIndex;
  final OnLifeChange onLifeChange;
  final OnCommanderDamage onCommanderDamage;
  // Non-null while a tool-driven player-pick overlay is active.
  final PlayerPickRequest? playerPickRequest;
  // True while the Random Player roulette is spinning — absorbs pointer only.
  final bool randomAnimating;
  // Player ID currently highlighted by the Random Player roulette spin.
  final String? randomHighlightId;
  // Player ID who won the Random Player roulette. Shown with winner border
  // until the user taps "Done" on the diamond.
  final String? randomWinnerId;
  // Called when any card is tapped during the GAMBA OK phase.
  final VoidCallback? onConfirmStart;
  // Called when a card is tapped during the GAMBA waiting phase (before the
  // animation starts). Signals that players chose a starter outside the app.
  final VoidCallback? onSkipGamba;

  const GameGrid({
    super.key,
    required this.game,
    required this.onLifeChange,
    required this.onCommanderDamage,
    this.choosingStarter = false,
    this.gambaHighlightIndex = -1,
    this.gambaWinnerIndex = -1,
    this.playerPickRequest,
    this.randomAnimating = false,
    this.randomHighlightId,
    this.randomWinnerId,
    this.onConfirmStart,
    this.onSkipGamba,
  });

  @override
  Widget build(BuildContext context) {
    final players = game.players;

    if (players.length == 1) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 260),
          child: _buildCard(players[0]),
        ),
      );
    }

    return PlayerGridLayout<Player>(
      positions: PlayersByPosition.from(players, (p) => p.seatPosition),
      edgeFlex: 3,
      sideFlex: 2,
      slotBuilder: _buildCard,
    );
  }

  void _onEffectTap(BuildContext context, PlayerEffect effect) {
    for (final tool in kToolbeltTools) {
      if (tool is EffectTool && tool.handlesEffect(effect)) {
        tool.onTap(context);
        return;
      }
    }
  }

  Widget _buildCard(Player player) {
    final index = game.players.indexOf(player);

    final isPickMode      = playerPickRequest != null;
    final isOkPhase       = gambaWinnerIndex != -1;
    final isWinner        = gambaWinnerIndex == index;

    // Absorb inner card gestures so only the outermost tap target fires.
    final absorbing = choosingStarter || isPickMode || randomAnimating || isOkPhase;

    Widget card = Padding(
      padding: const EdgeInsets.all(4),
      child: AbsorbPointer(
        absorbing: absorbing,
        child: PlayerCard(
          player: player,
          allPlayers: game.players,
          onLifeChange: (delta) => onLifeChange(player.id, delta),
          onCommanderDamage: (attackerId, delta) => onCommanderDamage(player.id, attackerId, delta),
          activeEffects: game.effectsForPlayer(player.id),
          onEffectTap: _onEffectTap,
        ),
      ),
    );

    // Priority order: pick overlay → GAMBA OK phase → GAMBA spin/idle → Random winner.
    if (isPickMode) {
      card = GestureDetector(
        onTap: () => playerPickRequest!.onPick(player.id),
        child: _PulsingBorder(color: player.color, child: card),
      );
    } else if (isOkPhase) {
      card = GestureDetector(
        onTap: onConfirmStart,
        child: isWinner
            ? _GambaWinnerBorder(color: player.color, child: card)
            : card,
      );
    } else if (choosingStarter) {
      final isGambaActive = gambaHighlightIndex != -1;
      final isGambaFlash  = gambaHighlightIndex == index;
      if (isGambaActive) {
        // Animation running — show spin border on the current card, no tap.
        card = isGambaFlash
            ? _GambaSpinBorder(color: player.color, child: card)
            : card;
      } else {
        // Waiting for GAMBA tap — pulsing border; tapping skips GAMBA entirely.
        card = GestureDetector(
          onTap: onSkipGamba,
          child: _PulsingBorder(color: player.color, child: card),
        );
      }
    }

    if (randomHighlightId == player.id) {
      card = _GambaSpinBorder(color: player.color, child: card);
    }

    if (randomWinnerId == player.id) {
      card = _RandomWinnerBorder(color: player.color, child: card);
    }

    return card;
  }
}

// ---------------------------------------------------------------------------
// Border widgets
// ---------------------------------------------------------------------------

// Subtle animated border pulsing during WHO'S STARTING and pick-mode.
class _PulsingBorder extends StatefulWidget {
  final Color color;
  final Widget child;
  const _PulsingBorder({required this.color, required this.child});

  @override
  State<_PulsingBorder> createState() => _PulsingBorderState();
}

class _PulsingBorderState extends State<_PulsingBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.color.withValues(alpha: _anim.value),
            width: 3,
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// Thin, semi-transparent border shown while the GAMBA roulette is spinning.
// Deliberately subtle — signals "still choosing".
class _GambaSpinBorder extends StatelessWidget {
  final Color color;
  final Widget child;
  const _GambaSpinBorder({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

// Bold border with glow shown on the GAMBA winner during the OK phase.
// High visual weight so players immediately read it as "the result".
class _GambaWinnerBorder extends StatelessWidget {
  final Color color;
  final Widget child;
  const _GambaWinnerBorder({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }
}

// Bold border with glow shown on the Random Player roulette winner.
class _RandomWinnerBorder extends StatelessWidget {
  final Color color;
  final Widget child;
  const _RandomWinnerBorder({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }
}
