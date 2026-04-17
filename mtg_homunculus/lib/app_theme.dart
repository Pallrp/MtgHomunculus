import 'package:flutter/material.dart';

/// Shared color constants for the current dark theme.
///
/// Interim: these will be replaced by MaterialApp.theme once the settings
/// color profile system lands. Keep changes here rather than scattered across files.
class AppTheme {
  AppTheme._();

  static const Color scaffoldBg = Color(0xFF1A1A1A);
  static const Color appBarBg   = Color(0xFF242424);
  static const Color dialogBg   = Color(0xFF2A2A2A);

  static final ShapeBorder dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
}
