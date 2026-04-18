import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app_theme.dart';
import '../models/player.dart';
import '../models/players_by_position.dart';
import '../models/tracker.dart';
import 'gt_settings_scope.dart';
import 'manage_trackers_dialog.dart';
import 'player_grid_layout.dart';

class PlayerCard extends StatefulWidget {
  final Player player;
  // All players in the game, including self — needed to build the opponent rows.
  final List<Player> allPlayers;
  final bool isActive;
  final void Function(int delta) onLifeChange;
  final void Function(String trackerId, int delta) onTrackerChange;
  final void Function(Tracker tracker) onTrackerAdd;
  final void Function(String trackerId) onTrackerRemove;
  final void Function(int oldIndex, int newIndex) onTrackerReorder;
  // attackerId is the opponent whose commander dealt the damage.
  final void Function(String attackerId, int delta) onCommanderDamage;

  const PlayerCard({
    super.key,
    required this.player,
    required this.allPlayers,
    required this.onLifeChange,
    required this.onTrackerChange,
    required this.onTrackerAdd,
    required this.onTrackerRemove,
    required this.onTrackerReorder,
    required this.onCommanderDamage,
    this.isActive = false,
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

  // Returns a lightened version of [base] for use as the active border color.
  Color _lighten(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final opponents = _opponents;
    final borderColor = widget.isActive
        ? _lighten(player.color)
        : player.color.withValues(alpha: 0.6);

    final trackerRow = _TrackerPillsRow(
      trackers: player.trackers,
      playerColor: player.color,
      quarterTurns: player.quarterTurns,
      onTrackerChange: widget.onTrackerChange,
      onTrackerRemove: widget.onTrackerRemove,
      onManageTap: (context) => showDialog<void>(
        context: context,
        builder: (_) => ManageTrackersDialog(
          trackers: player.trackers,
          quarterTurns: player.quarterTurns,
          onAdd: widget.onTrackerAdd,
          onRemove: widget.onTrackerRemove,
          onReorder: widget.onTrackerReorder,
        ),
      ),
    );

    final lifeArea = Expanded(
      child: _LifeTotalArea(
        lifeTotal: player.lifeTotal,
        onLifeChange: widget.onLifeChange,
        onSwipe: opponents.isNotEmpty
            ? () => setState(() => _showingCommanderDamage = true)
            : null,
      ),
    );

    // One shield icon + damage number per opponent who has dealt commander
    // damage. Icon uses the opponent's full color; number is plain white.
    // Hidden entirely when no commander damage has been received.
    final damagedBy = opponents
        .where((opp) => (player.commanderDamage[opp.id] ?? 0) > 0)
        .toList();
    final cmdDmgRow = damagedBy.isEmpty
        ? const SizedBox.shrink()
        : SizedBox(
            height: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: damagedBy.map((opp) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, color: opp.color, size: 13),
                    const SizedBox(width: 2),
                    Text(
                      '${player.commanderDamage[opp.id]}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          );

    // Life total content — tracker row + life area — wrapped in a RotatedBox so
    // the player reads it from their seat. Scoped to this child only so the
    // damage view below is unaffected by the rotation.
    final lifeTotalView = RotatedBox(
      key: const ValueKey('life'),
      quarterTurns: player.quarterTurns,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        // For bottomEdge the tracker row sits at the widget top (outer edge).
        // For every other seat the card is rotated so trackers go at the bottom.
        children: player.seatPosition == SeatPosition.bottomEdge
            ? [trackerRow, cmdDmgRow, lifeArea]
            : [lifeArea, cmdDmgRow, trackerRow],
      ),
    );

    // The container border stays in screen space regardless of which child is
    // shown. AnimatedSwitcher fades between the rotated life view and the
    // screen-space damage grid. Background clears to transparent during the
    // damage view so cell colors render against the dark game background.
    return Container(
      decoration: BoxDecoration(
        color: _showingCommanderDamage
            ? Colors.transparent
            : player.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: widget.isActive ? 3.0 : 1.5,
        ),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Tracker pill row
// ---------------------------------------------------------------------------

// Horizontally scrollable tracker pills + manage button (always trailing).
class _TrackerPillsRow extends StatelessWidget {
  final List<Tracker> trackers;
  final Color playerColor;
  final int quarterTurns;
  final void Function(String trackerId, int delta) onTrackerChange;
  final void Function(String trackerId) onTrackerRemove;
  final void Function(BuildContext context) onManageTap;

  const _TrackerPillsRow({
    required this.trackers,
    required this.playerColor,
    required this.quarterTurns,
    required this.onTrackerChange,
    required this.onTrackerRemove,
    required this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              itemCount: trackers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final tracker = trackers[index];
                return _TrackerPill(
                  tracker: tracker,
                  playerColor: playerColor,
                  quarterTurns: quarterTurns,
                  onChange: (delta) => onTrackerChange(tracker.id, delta),
                  onRemove: () => onTrackerRemove(tracker.id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onManageTap(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.add, size: 13, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// A single tracker pill. Tap = +1. Hold = centered edit dialog.
class _TrackerPill extends StatelessWidget {
  final Tracker tracker;
  final Color playerColor;
  final int quarterTurns;
  final void Function(int delta) onChange;
  final VoidCallback onRemove;

  const _TrackerPill({
    required this.tracker,
    required this.playerColor,
    required this.quarterTurns,
    required this.onChange,
    required this.onRemove,
  });

  void _showOptions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _TrackerEditDialog(
        tracker: tracker,
        quarterTurns: quarterTurns,
        onChange: onChange,
        onRemove: onRemove,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValue = tracker.value > 0;

    return GestureDetector(
      onTap: () => onChange(1),
      onLongPress: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: playerColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: playerColor.withValues(alpha: hasValue ? 0.8 : 0.4),
            width: 1,
          ),
        ),
        child: Text(
          hasValue ? '${tracker.icon} ${tracker.value}' : tracker.icon,
          style: const TextStyle(fontSize: 16, height: 1),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tracker edit dialog
// ---------------------------------------------------------------------------

// Centered dialog for adjusting a tracker value.
// Owns a local _value so the display updates live without closing the dialog.
class _TrackerEditDialog extends StatefulWidget {
  final Tracker tracker;
  final int quarterTurns;
  final void Function(int delta) onChange;
  final VoidCallback onRemove;

  const _TrackerEditDialog({
    required this.tracker,
    required this.quarterTurns,
    required this.onChange,
    required this.onRemove,
  });

  @override
  State<_TrackerEditDialog> createState() => _TrackerEditDialogState();
}

class _TrackerEditDialogState extends State<_TrackerEditDialog> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.tracker.value;
  }

  void _adjust(int delta) {
    widget.onChange(delta);
    setState(() => _value += delta);
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: widget.quarterTurns * pi / 2,
      child: Dialog(
        backgroundColor: AppTheme.dialogBg,
        shape: AppTheme.dialogShape,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.tracker.icon}  ${widget.tracker.name}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _DialogAdjustButton(label: '−', onTap: () => _adjust(-1)),
                  Text(
                    '$_value',
                    style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  _DialogAdjustButton(label: '+', onTap: () => _adjust(1)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {
                      _adjust(-_value);
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Reset',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      widget.onRemove();
                    },
                    child: Text(
                      'Remove',
                      style: TextStyle(color: Colors.red.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// +/- button used inside _TrackerEditDialog.
class _DialogAdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DialogAdjustButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 28),
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
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: SizedBox(
        height: 160,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Each button is its own widget with its own independent timer
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _HoldButton(tapDelta: -1, holdDelta: -10, onActivate: _handleLifeChange)),
                Expanded(child: _HoldButton(tapDelta: 1,  holdDelta: 10,  onActivate: _handleLifeChange)),
              ],
            ),
            // Life total — always centered, never moves
            IgnorePointer(
              child: Text(
                '${widget.lifeTotal}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
            // Delta indicator — anchored to the bottom of the Stack
            if (_pendingDelta != 0)
              Positioned(
                bottom: 0,
                child: IgnorePointer(
                  child: Text(
                    _pendingDelta > 0 ? '+$_pendingDelta' : '$_pendingDelta',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
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
      // A fast horizontal drag opens the commander damage view.
      // _HoldButton only handles taps and long-presses, so no conflict.
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

// Replaces the life total area when the player swipes the card.
// Mirrors the board layout: each player occupies the same grid slot as on the
// main screen. The self slot shows an Ok/close cell; opponent slots show a
// compact damage tracker (tap ±1, hold ±10).
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

  // Opponents in clockwise turn order starting from the seat after self.
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

// The self slot in the commander damage grid — tapping it closes the view.
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

// An opponent slot in the commander damage grid.
// Tap: ±1, hold: ±10. Shows current damage + pending delta.
class _CmdDamageCell extends StatefulWidget {
  final Player opponent;
  // The player who opened this damage view — provides quarterTurns for text
  // rotation and the live commanderDamage map for clamping negatives.
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
    // Commander damage cannot go below 0.
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  if (_pendingDelta != 0)
                    Text(
                      _pendingDelta > 0 ? '+$_pendingDelta' : '$_pendingDelta',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
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

// A transparent pressable area with independent hold-repeat logic.
// Each instance owns its own Timer so simultaneous presses can't interfere.
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
  // _timer serves double duty: first as the hold-threshold delay, then
  // replaced with the repeat timer once the threshold fires.
  Timer? _timer;
  bool _holding = false;

  void _onTapDown(TapDownDetails _) {
    final ms = GtSettingsScope.of(context).holdDurationMs;
    _timer = Timer(Duration(milliseconds: ms), () {
      _holding = true;
      widget.onActivate(widget.holdDelta);
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        widget.onActivate(widget.holdDelta);
      });
    });
  }

  void _onTapUp(TapUpDetails _) {
    if (!_holding) {
      // Threshold never fired — treat as a tap.
      _timer?.cancel();
      _timer = null;
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
