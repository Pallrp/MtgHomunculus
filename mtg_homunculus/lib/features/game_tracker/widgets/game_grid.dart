import 'package:flutter/material.dart';
import '../models/game_effect.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/players_by_position.dart';
import '../models/tracker.dart';
import '../models/toolbelt_tool.dart';
import '../models/toolbelt_tools.dart';
import 'gt_game_scope.dart';
import 'player_card.dart';
import 'player_grid_layout.dart';

// Callbacks for all PlayerCard interactions, keyed by player id.
typedef OnLifeChange      = void Function(String playerId, int delta);
typedef OnTrackerChange   = void Function(String playerId, String trackerId, int delta);
typedef OnTrackerAdd      = void Function(String playerId, Tracker tracker);
typedef OnTrackerRemove   = void Function(String playerId, String trackerId);
typedef OnTrackerReorder  = void Function(String playerId, int oldIndex, int newIndex);
typedef OnPlayerTap       = void Function(String playerId); // used during choosingStarter
typedef OnCommanderDamage = void Function(String defenderId, String attackerId, int delta);

class GameGrid extends StatelessWidget {
  final GameState game;
  final bool choosingStarter;
  // Index (into game.players) of the card currently highlighted by GAMBA. -1 = none.
  final int gambaHighlightIndex;
  final OnLifeChange onLifeChange;
  final OnTrackerChange onTrackerChange;
  final OnTrackerAdd onTrackerAdd;
  final OnTrackerRemove onTrackerRemove;
  final OnTrackerReorder onTrackerReorder;
  final OnCommanderDamage onCommanderDamage;
  final OnPlayerTap? onPlayerTap;
  // Non-null while a tool-driven player-pick overlay is active.
  final PlayerPickRequest? playerPickRequest;
  // Player ID currently highlighted during the Random Player roulette spin.
  // Null when no roulette is running. Absorbs pointer to prevent accidental taps.
  final String? randomHighlightId;
  // Player ID who won the Random Player roulette. Shown with winner border
  // until the user taps "Done" on the diamond. Does not absorb pointer.
  final String? randomWinnerId;

  const GameGrid({
    super.key,
    required this.game,
    required this.onLifeChange,
    required this.onTrackerChange,
    required this.onTrackerAdd,
    required this.onTrackerRemove,
    required this.onTrackerReorder,
    required this.onCommanderDamage,
    this.choosingStarter = false,
    this.gambaHighlightIndex = -1,
    this.onPlayerTap,
    this.playerPickRequest,
    this.randomHighlightId,
    this.randomWinnerId,
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

    // edgeFlex: 3, sideFlex: 2 preserves the original 1.5× height ratio between
    // short-edge rows and individual side slots (3 vs sideCount×2).
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
    final isActive = game.activePlayerIndex == index;

    final isPickMode = playerPickRequest != null;
    // Absorb inner card gestures during any overlay that needs a clean tap target:
    // WHO'S STARTING, player-pick, or Random Player roulette spin.
    final absorbing = choosingStarter || isPickMode || randomHighlightId != null;

    Widget card = Padding(
      padding: const EdgeInsets.all(4),
      // AbsorbPointer blocks all inner gesture detectors (life total buttons,
      // tracker pills, etc.) during WHO'S STARTING and pick overlays so only
      // the outer tap handler fires.
      child: AbsorbPointer(
        absorbing: absorbing,
        child: PlayerCard(
          player: player,
          allPlayers: game.players,
          isActive: isActive && game.gameStarted,
          onLifeChange: (delta) => onLifeChange(player.id, delta),
          onTrackerChange: (id, delta) => onTrackerChange(player.id, id, delta),
          onTrackerAdd: (t) => onTrackerAdd(player.id, t),
          onTrackerRemove: (id) => onTrackerRemove(player.id, id),
          onTrackerReorder: (o, n) => onTrackerReorder(player.id, o, n),
          onCommanderDamage: (attackerId, delta) => onCommanderDamage(player.id, attackerId, delta),
          activeEffects: game.effectsForPlayer(player.id),
          onEffectTap: _onEffectTap,
        ),
      ),
    );

    // During pick overlay — all cards pulse; tap = pick that player.
    if (isPickMode) {
      card = GestureDetector(
        onTap: () => playerPickRequest!.onPick(player.id),
        child: _PulsingBorder(color: player.color, child: card),
      );
    }
    // During WHO'S STARTING, wrap with a tap detector and a border effect:
    //   • no animation yet  → all cards pulse (player is deciding)
    //   • animation running → only the current highlight flashes; others plain
    else if (choosingStarter && onPlayerTap != null) {
      final isGambaActive = gambaHighlightIndex != -1;
      final isGambaFlash  = gambaHighlightIndex == index;
      card = GestureDetector(
        onTap: () => onPlayerTap!(player.id),
        child: isGambaFlash
            ? _FlashBorder(color: player.color, child: card)
            : isGambaActive
                ? card
                : _PulsingBorder(color: player.color, child: card),
      );
    }

    // Random Player roulette overlays — applied last so they sit outermost.
    // These states don't coexist with pick-mode or choosingStarter, so there
    // is no visual conflict with the borders above.
    if (randomHighlightId == player.id) {
      card = _RandomSpinBorder(color: player.color, child: card);
    }
    if (randomWinnerId == player.id) {
      card = _RandomWinnerBorder(color: player.color, child: card);
    }

    return card;
  }
}

// Solid bright border shown on the card currently highlighted by GAMBA spin.
class _FlashBorder extends StatelessWidget {
  final Color color;
  final Widget child;
  const _FlashBorder({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 4),
      ),
      child: child,
    );
  }
}

// Subtle animated border that pulses during WHO'S STARTING selection.
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

// Thin, semi-transparent border shown on the card currently passing through
// the Random Player roulette. Deliberately subtle — signals "still deciding".
class _RandomSpinBorder extends StatelessWidget {
  final Color color;
  final Widget child;
  const _RandomSpinBorder({required this.color, required this.child});

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

// Bold border with a coloured glow shown on the Random Player roulette winner.
// High visual weight so players immediately read it as "the result".
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
