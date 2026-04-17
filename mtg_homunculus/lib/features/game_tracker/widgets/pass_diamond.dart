import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

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

  const PassDiamond({
    super.key,
    required this.playerOrder,
    required this.onPass,
    required this.onGamba,
    this.choosingStarter = false,
    this.onGambaHighlight,
  });

  @override
  State<PassDiamond> createState() => _PassDiamondState();
}

class _PassDiamondState extends State<PassDiamond>
    with SingleTickerProviderStateMixin {
  bool _animating = false;
  Timer? _timer;

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
    _timer?.cancel();
    _pressCtrl.dispose();
    super.dispose();
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

    final order = widget.playerOrder;
    final n = order.length;
    final random = Random();
    final pickSlot = random.nextInt(n); // index into order, not a player index
    // Total steps: a few full cycles plus landing exactly on pickSlot.
    // +1 so the last tick highlights the winner before onGamba fires.
    final totalCycles = 3 + random.nextInt(2); // 3–4 full loops
    final totalSteps = totalCycles * n + pickSlot + 1;

    int step = 0;
    // Sweep clockwise through order; decelerate over the last 40% of steps.
    void tick() {
      if (!mounted) return;
      widget.onGambaHighlight?.call(order[step % n]);
      step++;
      if (step >= totalSteps) {
        _timer?.cancel();
        setState(() => _animating = false);
        widget.onGamba(order[pickSlot]);
        return;
      }
      final progress = step / totalSteps;
      final intervalMs = progress < 0.6
          ? 80
          : (80 + ((progress - 0.6) / 0.4) * 420).round();
      _timer = Timer(Duration(milliseconds: intervalMs), tick);
    }

    _timer = Timer(const Duration(milliseconds: 100), tick);
  }

  String get _label {
    if (_animating) return '';
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
      child: ScaleTransition(
        scale: _scaleAnim,
        child: _DiamondShape(
          label: _label,
          isAnimating: _animating,
          choosingStarter: widget.choosingStarter,
        ),
      ),
    );
  }
}

class _DiamondShape extends StatelessWidget {
  final String label;
  final bool isAnimating;
  final bool choosingStarter;

  const _DiamondShape({
    required this.label,
    required this.isAnimating,
    required this.choosingStarter,
  });

  @override
  Widget build(BuildContext context) {
    final color = choosingStarter
        ? const Color(0xFFE67E22) // orange for GAMBA
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
