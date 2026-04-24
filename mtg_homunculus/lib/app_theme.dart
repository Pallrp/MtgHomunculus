import 'package:flutter/material.dart';

/// Shared constants that are not part of the MaterialApp theme system.
///
/// Scaffold and AppBar colors are now defined in MaterialApp.theme /
/// darkTheme in main.dart — do not add them back here.
class AppTheme {
  AppTheme._();

  // Dialog background is not cleanly driven by ThemeData, so it stays here.
  static const Color dialogBg = Color(0xFF2A2A2A);

  static final ShapeBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
}
