import 'dart:math';
import 'package:flutter/material.dart';
import '../models/roulette_animation.dart';

// Visual clearance around the diamond for portal-scroll strips.
// 64 px square rotated 45° has a diagonal of ~90 px; add breathing room.
const double kPassDiamondClearance = 80.0;

// The diamond button overlaid on the game grid.
//
// States:
//   normal (2+ players): label "Pass" — advances turn
//   normal (1 player):   label "Reset" — resets non-permanent trackers
//   choosingStarter:     label "GAMBA" — triggers roulette animation
//
// The GAMBA animation cycles a highlight index through [playerCount] values,
// decelerating until it lands on [gambaPick]. The caller provides the final
// pick; the widget owns only the animation.

class PassDiamond extends StatefulWidget {
  // Player indices in clockwise board order — drives both the roulette sweep
  // and the Pass label logic.
  final List<int> playerOrder;
  final bool choosingStarter;
  // Called when tapped in normal mode (single player = reset, multi = pass).
  final VoidCallback onPass;
  // Called when tapped in GAMBA mode. Returns the selected player index.
  final void Function(int pickedIndex) onGamba;
  // Called each tick of the GAMBA animation with the currently highlighted index.
  // Use this to flash a border on the corresponding PlayerCard in GameGrid.
  final void Function(int index)? onGambaHighlight;
  // Called when a directional swipe is detected on the diamond.
  // Axis.horizontal = left/right swipe; Axis.vertical = up/down swipe.
  final void Function(Axis)? onSwipe;
  // When non-null, overrides the computed label (e.g. "Cancel" during pick overlay).
  // Swipe gestures are suppressed while an override label is active.
  final String? overrideLabel;

  const PassDiamond({
    super.key,
    required this.playerOrder,
    required this.onPass,
    required this.onGamba,
    this.choosingStarter = false,
    this.onGambaHighlight,
    this.onSwipe,
    this.overrideLabel,
  });

  @override
  State<PassDiamond> createState() => _PassDiamondState();
}

class _PassDiamondState extends State<PassDiamond>
    with SingleTickerProviderStateMixin {
  bool _animating = false;
  final RouletteAnimation _roulette = RouletteAnimation();
  Axis? _lockedAxis;

  late final AnimationController _pressCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _roulette.cancel();
    _pressCtrl.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _) {
    _lockedAxis = null;
    _pressCtrl.reverse();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_lockedAxis != null) return;
    final dx = details.delta.dx.abs();
    final dy = details.delta.dy.abs();
    if (dx > 3 || dy > 3) {
      _lockedAxis = dx >= dy ? Axis.horizontal : Axis.vertical;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    final axis = _lockedAxis;
    _lockedAxis = null;
    if (axis == null || widget.onSwipe == null || _animating || widget.overrideLabel != null) return;
    final velocity = axis == Axis.horizontal
        ? details.velocity.pixelsPerSecond.dx.abs()
        : details.velocity.pixelsPerSecond.dy.abs();
    if (velocity > 200) widget.onSwipe!(axis);
  }

  void _handleTap() {
    if (_animating) return;
    if (widget.choosingStarter) {
      _startGamba();
    } else {
      widget.onPass();
    }
  }

  void _startGamba() {
    if (_animating) return;
    setState(() => _animating = true);

    // Sweep clockwise through player order — RouletteAnimation handles the
    // deceleration curve and random pick identically to the Random Player tool.
    _roulette.start<int>(
      items: widget.playerOrder,
      onHighlight: (index) => widget.onGambaHighlight?.call(index),
      onComplete: (index) {
        setState(() => _animating = false);
        widget.onGamba(index);
      },
      isMounted: () => mounted,
    );
  }

  String get _label {
    if (_animating) return '';
    if (widget.overrideLabel != null) return widget.overrideLabel!;
    if (widget.choosingStarter) return 'GAMBA';
    return widget.playerOrder.length == 1 ? 'Reset' : 'Pass';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        _handleTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: _DiamondShape(
          label: _label,
          isAnimating: _animating,
          choosingStarter: widget.choosingStarter,
          isCancel: widget.overrideLabel != null,
        ),
      ),
    );
  }
}

class _DiamondShape extends StatelessWidget {
  final String label;
  final bool isAnimating;
  final bool choosingStarter;
  final bool isCancel;

  const _DiamondShape({
    required this.label,
    required this.isAnimating,
    required this.choosingStarter,
    this.isCancel = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = choosingStarter
        ? const Color(0xFFE67E22) // orange for GAMBA
        : isCancel
            ? const Color(0xFF7A2D2D) // dark red for cancel/pick mode
            : const Color(0xFF3A3A3A);

    return Transform.rotate(
      angle: pi / 4, // 45° to make a diamond from a square
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Transform.rotate(
          angle: -pi / 4, // un-rotate the label so text is upright
          child: Center(
            child: isAnimating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
