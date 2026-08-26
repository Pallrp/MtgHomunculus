import 'package:flutter/material.dart';

/// The card-lookup design tokens, taken from the Card Picker artifact.
///
/// Lifted directly from that page's CSS variables rather than re-derived, so the
/// two cannot drift: if the artifact changes, these change, and nothing in
/// between gets to have an opinion.
///
/// **Why not the app `ColorScheme`.** Material's roles carry meanings this
/// design does not use — `primaryContainer`, `errorContainer`, `tertiary` — and
/// mapping a six-colour palette onto them means every widget re-deciding which
/// role a colour "is". The tokens are the palette, named the way the design
/// names them.
class PickerTokens extends ThemeExtension<PickerTokens> {
  final Color ground;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color text;
  final Color textDim;
  final Color textFaint;

  /// The one accent. Everything interactive or deviating uses it, and nothing
  /// else does.
  final Color accent;
  final Color accentSoft;

  /// Destructive only. Never a warning, never an emphasis.
  final Color vermilion;

  /// The condition ramp — one pair per step, straight from the Last-Scan Bar
  /// artifact. Four distinct colours, not an interpolation: the design names
  /// them, so guessing the middle steps was wrong.
  final Color condLp;
  final Color condLpBg;
  final Color condMp;
  final Color condMpBg;
  final Color condHp;
  final Color condHpBg;
  final Color condDm;
  final Color condDmBg;

  /// Behind the camera feed.
  final Color viewfinder;

  const PickerTokens({
    required this.ground,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentSoft,
    required this.vermilion,
    required this.condLp,
    required this.condLpBg,
    required this.condMp,
    required this.condMpBg,
    required this.condHp,
    required this.condHpBg,
    required this.condDm,
    required this.condDmBg,
    required this.viewfinder,
  });

  /// Background and foreground for one condition, or null for Near Mint, which
  /// is passive and takes the ordinary muted chip.
  (Color fg, Color bg)? condition(int value) => switch (value) {
        1 => (condLp, condLpBg),
        2 => (condMp, condMpBg),
        3 => (condHp, condHpBg),
        4 => (condDm, condDmBg),
        _ => null,
      };

  static const light = PickerTokens(
    ground: Color(0xFFF2F5F3),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFE7ECE9),
    line: Color(0xFFD2DBD6),
    text: Color(0xFF101815),
    textDim: Color(0xFF5D6B65),
    textFaint: Color(0xFF8A9891),
    accent: Color(0xFF1F9E6B),
    accentSoft: Color(0xFFD6F0E4),
    vermilion: Color(0xFFC4432F),
    condLp: Color(0xFFA67C10),
    condLpBg: Color(0xFFF7EDCE),
    condMp: Color(0xFFC2701F),
    condMpBg: Color(0xFFF8E4CE),
    condHp: Color(0xFFBE5327),
    condHpBg: Color(0xFFF8DBCB),
    condDm: Color(0xFFC4432F),
    condDmBg: Color(0xFFF8D5CE),
    viewfinder: Color(0xFF14201C),
  );

  static const dark = PickerTokens(
    ground: Color(0xFF0B1210),
    surface: Color(0xFF121B18),
    surface2: Color(0xFF1A2622),
    line: Color(0xFF26332E),
    text: Color(0xFFE8EFEB),
    textDim: Color(0xFF9AAAA3),
    textFaint: Color(0xFF6B7A74),
    accent: Color(0xFF5FD9A0),
    accentSoft: Color(0xFF17322A),
    vermilion: Color(0xFFE86A56),
    condLp: Color(0xFFE8C766),
    condLpBg: Color(0xFF33290F),
    condMp: Color(0xFFE89F58),
    condMpBg: Color(0xFF35240F),
    condHp: Color(0xFFE8825C),
    condHpBg: Color(0xFF35200F),
    condDm: Color(0xFFE86A56),
    condDmBg: Color(0xFF351A14),
    viewfinder: Color(0xFF0A100E),
  );

  /// Foil, and only foil.
  ///
  /// **Static.** A shimmer on every row would be unbearable at ten rows a
  /// screen, so the gradient carries the idea and the motion is left out.
  static const foil = LinearGradient(
    colors: [
      Color(0xFFF49AC1),
      Color(0xFFF6D96B),
      Color(0xFF8CE8A8),
      Color(0xFF7CC9F0),
      Color(0xFFC79CF0),
    ],
    stops: [0.0, 0.25, 0.5, 0.75, 1.0],
    begin: Alignment(-0.9, -0.4),
    end: Alignment(0.9, 0.4),
  );

  /// Readable on the foil gradient in either theme, which is why it is a
  /// constant rather than a token.
  static const onFoil = Color(0xFF1A1A1A);

  /// Measurements, from the artifact's reference table.
  static const rowHeight = 76.0;
  static const thumbWidth = 40.0;
  static const thumbHeight = 56.0;
  static const chevron = 34.0;
  static const mgmtBarHeight = 54.0;

  static const radius = 10.0;
  static const radiusSmall = 8.0;
  static const radiusChip = 4.0;

  static PickerTokens of(BuildContext context) =>
      Theme.of(context).extension<PickerTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  // ---------------------------------------------------------------------------
  // Type
  // ---------------------------------------------------------------------------

  /// Data, not prose: counts, collector numbers, chips, field labels.
  ///
  /// The artifact sets IBM Plex Mono here. There is no font package in this
  /// project and no bundled faces, so this resolves to the platform monospace —
  /// the *role* survives (numbers align, meta reads as data) even though the
  /// exact face does not. Swap to the real one by adding `google_fonts`.
  static const monoFamily = 'monospace';

  static TextStyle mono(
    BuildContext context, {
    double size = 11,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: color ?? of(context).textDim,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.25,
      );

  /// The uppercase mono label above a control.
  static TextStyle fieldLabel(BuildContext context) => mono(
        context,
        size: 10,
        letterSpacing: 1.0,
        color: of(context).textFaint,
      );

  // ---------------------------------------------------------------------------

  @override
  PickerTokens copyWith({
    Color? ground,
    Color? surface,
    Color? surface2,
    Color? line,
    Color? text,
    Color? textDim,
    Color? textFaint,
    Color? accent,
    Color? accentSoft,
    Color? vermilion,
    Color? condLp,
    Color? condLpBg,
    Color? condMp,
    Color? condMpBg,
    Color? condHp,
    Color? condHpBg,
    Color? condDm,
    Color? condDmBg,
    Color? viewfinder,
  }) =>
      PickerTokens(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        line: line ?? this.line,
        text: text ?? this.text,
        textDim: textDim ?? this.textDim,
        textFaint: textFaint ?? this.textFaint,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        vermilion: vermilion ?? this.vermilion,
        condLp: condLp ?? this.condLp,
        condLpBg: condLpBg ?? this.condLpBg,
        condMp: condMp ?? this.condMp,
        condMpBg: condMpBg ?? this.condMpBg,
        condHp: condHp ?? this.condHp,
        condHpBg: condHpBg ?? this.condHpBg,
        condDm: condDm ?? this.condDm,
        condDmBg: condDmBg ?? this.condDmBg,
        viewfinder: viewfinder ?? this.viewfinder,
      );

  @override
  PickerTokens lerp(ThemeExtension<PickerTokens>? other, double t) {
    if (other is! PickerTokens) return this;
    return PickerTokens(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      vermilion: Color.lerp(vermilion, other.vermilion, t)!,
      condLp: Color.lerp(condLp, other.condLp, t)!,
      condLpBg: Color.lerp(condLpBg, other.condLpBg, t)!,
      condMp: Color.lerp(condMp, other.condMp, t)!,
      condMpBg: Color.lerp(condMpBg, other.condMpBg, t)!,
      condHp: Color.lerp(condHp, other.condHp, t)!,
      condHpBg: Color.lerp(condHpBg, other.condHpBg, t)!,
      condDm: Color.lerp(condDm, other.condDm, t)!,
      condDmBg: Color.lerp(condDmBg, other.condDmBg, t)!,
      viewfinder: Color.lerp(viewfinder, other.viewfinder, t)!,
    );
  }
}
