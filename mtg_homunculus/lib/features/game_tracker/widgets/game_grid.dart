import 'package:flutter/material.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/tracker.dart';
import 'player_card.dart';

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

    final topEdge    = players.where((p) => p.seatPosition == SeatPosition.topEdge).toList();
    final bottomEdge = players.where((p) => p.seatPosition == SeatPosition.bottomEdge).toList();
    final leftSide   = players.where((p) => p.seatPosition == SeatPosition.leftSide).toList();
    final rightSide  = players.where((p) => p.seatPosition == SeatPosition.rightSide).toList();

    return Column(
      children: [
        // Top short-edge player (full width)
        if (topEdge.isNotEmpty)
          Expanded(
            flex: 1,
            child: _buildCard(topEdge.first),
          ),

        // Main two-column area — columns are always equal width so the layout
        // stays centred under the diamond regardless of player counts per side.
        if (leftSide.isNotEmpty || rightSide.isNotEmpty)
          Expanded(
            flex: leftSide.length + rightSide.length,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (leftSide.isNotEmpty)
                  Expanded(
                    child: Column(
                      children: leftSide
                          .map((p) => Expanded(child: _buildCard(p)))
                          .toList(),
                    ),
                  ),
                if (rightSide.isNotEmpty)
                  Expanded(
                    child: Column(
                      children: rightSide
                          .map((p) => Expanded(child: _buildCard(p)))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),

        // Bottom short-edge player (full width)
        if (bottomEdge.isNotEmpty)
          Expanded(
            flex: 1,
            child: _buildCard(bottomEdge.first),
          ),
      ],
    );
  }

  Widget _buildCard(Player player) {
    final index = game.players.indexOf(player);
    final isActive = game.activePlayerIndex == index;

    Widget card = Padding(
      padding: const EdgeInsets.all(4),
      // AbsorbPointer blocks all inner gesture detectors (life total buttons,
      // tracker pills, etc.) during WHO'S STARTING so only the outer tap
      // handler for player selection fires.
      child: AbsorbPointer(
        absorbing: choosingStarter,
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
        ),
      ),
    );

    // During WHO'S STARTING, wrap with a tap detector and pulse highlight.
    // During GAMBA animation, flash the currently spinning card instead.
    if (choosingStarter && onPlayerTap != null) {
      final isGambaFlash = gambaHighlightIndex == index;
      card = GestureDetector(
        onTap: () => onPlayerTap!(player.id),
        child: isGambaFlash
            ? _FlashBorder(color: player.color, child: card)
            : _PulsingBorder(color: player.color, child: card),
      );
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
