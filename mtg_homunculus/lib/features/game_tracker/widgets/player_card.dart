import 'dart:async';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/tracker.dart';
import 'manage_trackers_dialog.dart';

class PlayerCard extends StatelessWidget {
  final Player player;
  final bool isActive;
  final void Function(int delta) onLifeChange;
  final void Function(String trackerId, int delta) onTrackerChange;
  final void Function(Tracker tracker) onTrackerAdd;
  final void Function(String trackerId) onTrackerRemove;
  final void Function(int oldIndex, int newIndex) onTrackerReorder;

  const PlayerCard({
    super.key,
    required this.player,
    required this.onLifeChange,
    required this.onTrackerChange,
    required this.onTrackerAdd,
    required this.onTrackerRemove,
    required this.onTrackerReorder,
    this.isActive = false,
  });

  // Returns a lightened version of [base] for use as the active border color.
  // HSLColor lets us adjust lightness independently of hue/saturation.
  Color _lighten(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? _lighten(player.color)
        : player.color.withValues(alpha: 0.6);

    return Container(
      decoration: BoxDecoration(
        color: player.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: isActive ? 3.0 : 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TrackerPillsRow(
            trackers: player.trackers,
            playerColor: player.color,
            onTrackerChange: onTrackerChange,
            onTrackerRemove: onTrackerRemove,
            onManageTap: (context) => showDialog<void>(
              context: context,
              builder: (_) => ManageTrackersDialog(
                trackers: player.trackers,
                onAdd: onTrackerAdd,
                onRemove: onTrackerRemove,
                onReorder: onTrackerReorder,
              ),
            ),
          ),
          _LifeTotalArea(lifeTotal: player.lifeTotal, onLifeChange: onLifeChange),
        ],
      ),
    );
  }
}

// Top row: horizontally scrollable tracker pills + manage button.
class _TrackerPillsRow extends StatelessWidget {
  final List<Tracker> trackers;
  final Color playerColor;
  final void Function(String trackerId, int delta) onTrackerChange;
  final void Function(String trackerId) onTrackerRemove;
  final void Function(BuildContext context) onManageTap;

  const _TrackerPillsRow({
    required this.trackers,
    required this.playerColor,
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
                  onChange: (delta) => onTrackerChange(tracker.id, delta),
                  onRemove: () => onTrackerRemove(tracker.id),
                );
              },
            ),
          ),
          // Manage button — opens the tracker management dialog
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
  final void Function(int delta) onChange;
  final VoidCallback onRemove;

  const _TrackerPill({
    required this.tracker,
    required this.playerColor,
    required this.onChange,
    required this.onRemove,
  });

  void _showOptions(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _TrackerEditDialog(
        tracker: tracker,
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

// Centered dialog for adjusting a tracker value.
// Owns a local _value so the display updates live without closing the dialog.
// The parent's onChange is called on every adjustment so game state stays in sync.
class _TrackerEditDialog extends StatefulWidget {
  final Tracker tracker;
  final void Function(int delta) onChange;
  final VoidCallback onRemove;

  const _TrackerEditDialog({
    required this.tracker,
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
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    _adjust(-_value); // bring value back to 0
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

// Life total display with invisible tap areas on each half.
// Left half: decrement. Right half: increment.
// Tap: ±1. Hold: repeats ±10 every 500 ms.
// Shows a cumulative delta indicator that clears 5 s after the last change.
class _LifeTotalArea extends StatefulWidget {
  final int lifeTotal;
  final void Function(int delta) onLifeChange;

  const _LifeTotalArea({required this.lifeTotal, required this.onLifeChange});

  @override
  State<_LifeTotalArea> createState() => _LifeTotalAreaState();
}

class _LifeTotalAreaState extends State<_LifeTotalArea> {
  int _pendingDelta = 0;
  Timer? _clearTimer;

  // Intercepts each life change: forwards it to the parent callback,
  // accumulates it into the display delta, and resets the 5 s clear timer.
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
    return Padding(
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
            // Delta indicator — anchored to the bottom of the Stack so it
            // appears and disappears without affecting the life total position
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
  }
}

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
  Timer? _timer;

  void _startHolding() {
    widget.onActivate(widget.holdDelta);
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      widget.onActivate(widget.holdDelta);
    });
  }

  void _stopHolding() {
    _timer?.cancel();
    _timer = null;
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
      onTap: () => widget.onActivate(widget.tapDelta),
      onLongPressStart: (_) => _startHolding(),
      onLongPressEnd: (_) => _stopHolding(),
    );
  }
}
