import 'package:flutter/material.dart';

class SafeScreen extends StatelessWidget {
  final Widget child;
  final bool safeTop;
  final bool safeBottom;
  final bool safeLeft;
  final bool safeRight;

  const SafeScreen({
    super.key,
    required this.child,
    this.safeTop = true,
    this.safeBottom = true,
    this.safeLeft = true,
    this.safeRight = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: safeTop,
      bottom: safeBottom,
      left: safeLeft,
      right: safeRight,
      child: child,
    );
  }
}
