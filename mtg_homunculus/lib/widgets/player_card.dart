import 'dart:async';
import 'package:flutter/material.dart';
import '../models/player.dart';

class PlayerCard extends StatelessWidget {
  final Player player;
  final bool isActive;
  final void Function(int delta) onLifeChange;

  const PlayerCard({
    super.key,
    required this.player,
    required this.onLifeChange,
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
          _TrackerPillsRow(playerColor: player.color),
          _LifeTotalArea(lifeTotal: player.lifeTotal, onLifeChange: onLifeChange),
        ],
      ),
    );
  }
}

// Top row: tracker pills + add-tracker button.
// Pills themselves are a placeholder until [GT-TRACKER] is implemented.
class _TrackerPillsRow extends StatelessWidget {
  final Color playerColor;

  const _TrackerPillsRow({required this.playerColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: [
          // Tracker pills will be inserted here as a list
          const Spacer(),
          GestureDetector(
            onTap: () {}, // add tracker — to be implemented
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.add, size: 14, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// Life total display with invisible tap areas on each half.
// Left half: decrement. Right half: increment.
// Tap: ±1. Hold: repeats ±10 every 0.8 s.
class _LifeTotalArea extends StatefulWidget {
  final int lifeTotal;
  final void Function(int delta) onLifeChange;

  const _LifeTotalArea({required this.lifeTotal, required this.onLifeChange});

  @override
  State<_LifeTotalArea> createState() => _LifeTotalAreaState();
}

class _LifeTotalAreaState extends State<_LifeTotalArea> {
  Timer? _holdTimer;

  // Called when a long press begins — starts repeating every 800 ms.
  void _startHolding(int delta) {
    _holdTimer?.cancel();
    widget.onLifeChange(delta);
    _holdTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      widget.onLifeChange(delta);
    });
  }

  // Called when the finger lifts — cancels the repeating timer.
  void _stopHolding() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  // Always cancel on dispose so we don't fire into a dead widget.
  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: SizedBox(
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Invisible tap regions that fill the full height
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onLifeChange(-1),
                    onLongPressStart: (_) => _startHolding(-10),
                    onLongPressEnd: (_) => _stopHolding(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onLifeChange(1),
                    onLongPressStart: (_) => _startHolding(10),
                    onLongPressEnd: (_) => _stopHolding(),
                  ),
                ),
              ],
            ),
            // Life total sits on top but passes all touch events through
            IgnorePointer(
              child: Text(
                '${widget.lifeTotal}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
