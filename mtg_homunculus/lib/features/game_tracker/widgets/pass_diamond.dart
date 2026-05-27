import 'dart:math';
import 'package:flutter/material.dart';

// Visual clearance around the diamond for portal-scroll strips.
// 64 px square rotated 45° has a diagonal of ~90 px; add breathing room.
const double kPassDiamondClearance = 80.0;

/// Centred diamond button overlaid on the game grid.
///
/// All animation and roulette logic now lives in [GameTrackerScreen].
/// This widget is purely presentational — it shows the correct label/icon and
/// forwards taps to [onTap] (blocked while [gambaAnimating] is true).
///
/// States (controlled by caller):
///   toolbelt idle  — shows [icon] (e.g. handyman wrench)
///   choosingStarter — label "GAMBA", orange fill
///   gambaAnimating  — shows spinner, taps suppressed
///   overrideLabel   — shows supplied text (e.g. "Cancel", "OK"), dark-red fill
class PassDiamond extends StatefulWidget {
  /// Fires on tap. Suppressed while [gambaAnimating] is true.
  final VoidCallback onTap;
  /// True while GAMBA roulette is running — shows spinner, blocks taps.
  final bool gambaAnimating;
  /// True between game setup and the GAMBA tap (label "GAMBA", orange fill).
  final bool choosingStarter;
  /// When non-null, overrides the computed label (e.g. "Cancel", "OK").
  final String? overrideLabel;
  /// Icon shown in the default (idle) state. Ignored when label is shown.
  final IconData? icon;

  const PassDiamond({
    super.key,
    required this.onTap,
    this.gambaAnimating = false,
    this.choosingStarter = false,
    this.overrideLabel,
    this.icon,
  });

  @override
  State<PassDiamond> createState() => _PassDiamondState();
}

class _PassDiamondState extends State<PassDiamond>
    with SingleTickerProviderStateMixin {
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
    _pressCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.gambaAnimating) return;
    widget.onTap();
  }

  String get _label {
    if (widget.gambaAnimating) return '';
    if (widget.overrideLabel != null) return widget.overrideLabel!;
    if (widget.choosingStarter) return 'GAMBA';
    if (widget.icon != null) return ''; // icon shown instead of text
    return 'Pass';
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
          isAnimating: widget.gambaAnimating,
          choosingStarter: widget.choosingStarter,
          isOverride: widget.overrideLabel != null,
          icon: widget.icon,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DiamondShape extends StatelessWidget {
  final String label;
  final bool isAnimating;
  final bool choosingStarter;
  /// True when an overrideLabel is active — uses dark-red fill.
  final bool isOverride;
  final IconData? icon;

  const _DiamondShape({
    required this.label,
    required this.isAnimating,
    required this.choosingStarter,
    this.isOverride = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = choosingStarter
        ? const Color(0xFFE67E22) // orange for GAMBA
        : isOverride
            ? const Color(0xFF7A2D2D) // dark red for cancel / OK phase
            : const Color(0xFF3A3A3A); // default dark grey

    return Transform.rotate(
      angle: pi / 4, // 45° → square becomes diamond
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
          angle: -pi / 4, // un-rotate so content is upright
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
                : icon != null && label.isEmpty
                    ? Icon(icon, color: Colors.white, size: 22)
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
