import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app_settings_scope.dart';
import '../models/game_effect.dart';
import '../models/player.dart';
import '../models/players_by_position.dart';
import 'gt_settings_scope.dart';
import 'player_grid_layout.dart';

class PlayerCard extends StatefulWidget {
  final Player player;
  // All players in the game, including self — needed to build the opponent rows.
  final List<Player> allPlayers;
  // attackerId is the opponent whose commander dealt the damage.
  final void Function(int delta) onLifeChange;
  final void Function(String attackerId, int delta) onCommanderDamage;
  // Pre-filtered by GameGrid — only effects for this player.
  final List<PlayerEffect> activeEffects;
  // Called when the user taps an effect badge on the card.
  final void Function(BuildContext context, PlayerEffect effect)? onEffectTap;

  const PlayerCard({
    super.key,
    required this.player,
    required this.allPlayers,
    required this.onLifeChange,
    required this.onCommanderDamage,
    this.activeEffects = const [],
    this.onEffectTap,
  });

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  bool _showingCommanderDamage = false;

  List<Player> get _opponents =>
      widget.allPlayers.where((p) => p.id != widget.player.id).toList();

  @override
  void didUpdateWidget(PlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Close the commander damage view if there are no longer any opponents
    // (e.g. new game started with a single player).
    if (_showingCommanderDamage && _opponents.isEmpty) {
      setState(() => _showingCommanderDamage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final opponents = _opponents;
    final borderColor = player.color.withValues(alpha: 0.6);
    const borderWidth = 1.5;
    final outlineColor = widget.activeEffects
        .map((e) => e.cardOutlineColor)
        .whereType<Color>()
        .firstOrNull;

    // TODO(settings): life history — long-press life total to view per-turn log

    // Reusable icon content — null when nothing to show.
    final effectIconsContent = widget.activeEffects.isEmpty
        ? null
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final effect in widget.activeEffects)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onEffectTap != null
                      ? () => widget.onEffectTap!(context, effect)
                      : null,
                  child: SizedBox(
                    width: 44,
                    height: 36,
                    child: Center(
                      child: effect.cardBadge(context),
                    ),
                  ),
                ),
            ],
          );

    // Commander damage summary — one shield+number per opponent who has dealt
    // commander damage. Hidden when none. Display only (no tap handler).
    final damagedBy = opponents
        .where((opp) => (player.commanderDamage[opp.id] ?? 0) > 0)
        .toList();
    final cmdDmgContent = damagedBy.isEmpty
        ? null
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: damagedBy.map((opp) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, color: opp.color, size: 13),
                  const SizedBox(width: 2),
                  Text(
                    '${player.commanderDamage[opp.id]}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                ],
              ),
            )).toList(),
          );

    // Life total view: gesture zone fills the full card; secondary content
    // (effect badges, commander damage) floats on top at the player's bottom
    // edge. Effect badge GestureDetectors are higher z-order in the Stack so
    // they win the gesture arena for their tap targets; the life zone catches
    // everything else — no conditional margins needed.
    final lifeTotalView = RotatedBox(
      key: const ValueKey('life'),
      quarterTurns: player.quarterTurns,
      child: Stack(
        children: [
          Positioned.fill(
            child: _LifeTotalArea(
              lifeTotal: player.lifeTotal,
              onLifeChange: widget.onLifeChange,
              onSwipe: opponents.isNotEmpty
                  ? () => setState(() => _showingCommanderDamage = true)
                  : null,
            ),
          ),
          // Commander damage indicators — display only, passes taps through.
          if (cmdDmgContent != null)
            Positioned(
              bottom: 0, left: 0, right: 0, height: 20,
              child: IgnorePointer(child: Center(child: cmdDmgContent)),
            ),
          // Effect badges sit above the damage row (or flush to the bottom
          // edge when no damage is shown). Their GestureDetectors intercept
          // taps in their bounds; life buttons handle the rest of the card.
          if (effectIconsContent != null)
            Positioned(
              bottom: cmdDmgContent != null ? 20.0 : 0.0,
              left: 0, right: 0, height: 36,
              child: Center(child: effectIconsContent),
            ),
        ],
      ),
    );

    // The container border stays in screen space regardless of which child is
    // shown. AnimatedSwitcher fades between the rotated life view and the
    // screen-space damage grid.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: outlineColor ?? Colors.transparent,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: _showingCommanderDamage
              ? Colors.transparent
              : player.color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _showingCommanderDamage && opponents.isNotEmpty
              ? _CommanderDamageView(
                  key: const ValueKey('cmd'),
                  self: player,
                  allPlayers: widget.allPlayers,
                  onDamageChange: widget.onCommanderDamage,
                  onClose: () => setState(() => _showingCommanderDamage = false),
                )
              : lifeTotalView,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Life total area
// ---------------------------------------------------------------------------

// Life total display with invisible tap areas on each half.
// Left half: decrement. Right half: increment.
// Tap: ±1. Hold: repeats ±10 every 500 ms.
// Shows a cumulative delta indicator that clears 5 s after the last change.
// onSwipe: if set, a fast horizontal drag opens the commander damage view.
class _LifeTotalArea extends StatefulWidget {
  final int lifeTotal;
  final void Function(int delta) onLifeChange;
  final VoidCallback? onSwipe;

  const _LifeTotalArea({
    required this.lifeTotal,
    required this.onLifeChange,
    this.onSwipe,
  });

  @override
  State<_LifeTotalArea> createState() => _LifeTotalAreaState();
}

class _LifeTotalAreaState extends State<_LifeTotalArea> {
  int _pendingDelta = 0;
  Timer? _clearTimer;

  void _handleLifeChange(int delta) {
    widget.onLifeChange(delta);
    setState(() => _pendingDelta += delta);
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 5), () {
      setState(() => _pendingDelta = 0);
    });
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _HoldButton(tapDelta: -1, holdDelta: -10, onActivate: _handleLifeChange)),
                Expanded(child: _HoldButton(tapDelta: 1,  holdDelta: 10,  onActivate: _handleLifeChange)),
              ],
            ),
            IgnorePointer(
              child: Text(
                '${widget.lifeTotal}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
            if (_pendingDelta != 0)
              Positioned(
                bottom: 0,
                child: IgnorePointer(
                  child: Text(
                    _pendingDelta > 0 ? '+$_pendingDelta' : '$_pendingDelta',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.onSwipe == null) return content;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) {
          widget.onSwipe!();
        }
      },
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Commander damage view
// ---------------------------------------------------------------------------

class _CommanderDamageView extends StatelessWidget {
  final Player self;
  final List<Player> allPlayers;
  final void Function(String attackerId, int delta) onDamageChange;
  final VoidCallback onClose;

  const _CommanderDamageView({
    super.key,
    required this.self,
    required this.allPlayers,
    required this.onDamageChange,
    required this.onClose,
  });

  Widget _buildSlot(Player opponent) {
    final isSelf = opponent.id == self.id;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: isSelf
          ? _CmdOkCell(
              color: self.color,
              quarterTurns: self.quarterTurns,
              onClose: onClose,
            )
          : _CmdDamageCell(
              opponent: opponent,
              invoker: self,
              onChange: (delta) => onDamageChange(opponent.id, delta),
            ),
    );
  }

  List<Player>? _clockwiseFlatOrder() {
    final pos = self.seatPosition;
    if (pos != SeatPosition.topEdge && pos != SeatPosition.bottomEdge) {
      return null;
    }
    List<Player> byPos(SeatPosition p) =>
        allPlayers.where((pl) => pl.seatPosition == p).toList();
    final clockwise = [
      ...byPos(SeatPosition.topEdge),
      ...byPos(SeatPosition.rightSide),
      ...byPos(SeatPosition.bottomEdge),
      ...byPos(SeatPosition.leftSide).reversed,
    ];
    final selfIndex = clockwise.indexWhere((p) => p.id == self.id);
    return List.generate(
      clockwise.length - 1,
      (i) => clockwise[(selfIndex + 1 + i) % clockwise.length],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlayerGridLayout<Player>(
      positions: PlayersByPosition.from(allPlayers, (p) => p.seatPosition),
      edgeFlex: 2,
      sideFlex: 1,
      slotBuilder: _buildSlot,
      flatOrder: _clockwiseFlatOrder(),
      selfAtTop: self.seatPosition == SeatPosition.topEdge,
    );
  }
}

class _CmdOkCell extends StatelessWidget {
  final Color color;
  final int quarterTurns;
  final VoidCallback onClose;

  const _CmdOkCell({
    required this.color,
    required this.quarterTurns,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: GestureDetector(
        onTap: onClose,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
          ),
          child: Center(
            child: Icon(
              Icons.check_rounded,
              color: color.withValues(alpha: 0.9),
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _CmdDamageCell extends StatefulWidget {
  final Player opponent;
  final Player invoker;
  final void Function(int delta) onChange;

  const _CmdDamageCell({
    required this.opponent,
    required this.invoker,
    required this.onChange,
  });

  @override
  State<_CmdDamageCell> createState() => _CmdDamageCellState();
}

class _CmdDamageCellState extends State<_CmdDamageCell> {
  int _pendingDelta = 0;
  Timer? _clearTimer;

  void _handleChange(int delta) {
    final current = widget.invoker.commanderDamage[widget.opponent.id] ?? 0;
    final clamped = max(delta, -current);
    if (clamped == 0) return;
    widget.onChange(clamped);
    setState(() => _pendingDelta += clamped);
    _clearTimer?.cancel();
    _clearTimer = Timer(const Duration(seconds: 5), () {
      setState(() => _pendingDelta = 0);
    });
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.opponent.color;
    final damage = widget.invoker.commanderDamage[widget.opponent.id] ?? 0;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: RotatedBox(
        quarterTurns: widget.invoker.quarterTurns,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _HoldButton(tapDelta: -1, holdDelta: -10, onActivate: _handleChange)),
                Expanded(child: _HoldButton(tapDelta: 1,  holdDelta: 10,  onActivate: _handleChange)),
              ],
            ),
            IgnorePointer(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$damage',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  if (_pendingDelta != 0)
                    Text(
                      _pendingDelta > 0 ? '+$_pendingDelta' : '$_pendingDelta',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared hold-button widget
// ---------------------------------------------------------------------------

class _HoldButton extends StatefulWidget {
  final int tapDelta;
  final int holdDelta;
  final void Function(int delta) onActivate;

  const _HoldButton({
    required this.tapDelta,
    required this.holdDelta,
    required this.onActivate,
  });

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _timer;
  bool _holding = false;

  void _onTapDown(TapDownDetails _) {
    final ms = GtSettingsScope.of(context).holdDurationMs;
    _timer = Timer(Duration(milliseconds: ms), () {
      _holding = true;
      triggerHaptic(context);
      widget.onActivate(widget.holdDelta);
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        triggerHaptic(context);
        widget.onActivate(widget.holdDelta);
      });
    });
  }

  void _onTapUp(TapUpDetails _) {
    if (!_holding) {
      _timer?.cancel();
      _timer = null;
      triggerHaptic(context);
      widget.onActivate(widget.tapDelta);
    } else {
      _stopHolding();
    }
  }

  void _onTapCancel() {
    _timer?.cancel();
    _timer = null;
    _holding = false;
  }

  void _stopHolding() {
    _timer?.cancel();
    _timer = null;
    _holding = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
    );
  }
}
