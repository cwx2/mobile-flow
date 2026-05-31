/// rose_pine_dark.dart — Signal Night theme definition.
//
// Dark theme complete token definitions.
// Legacy filename retained to minimize import churn.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tokens/color_tokens.dart';
import '../tokens/typography_tokens.dart';
import '../tokens/spacing_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/motion_tokens.dart';

class RosePineDark {
  RosePineDark._();

  static TextStyle _displayFont(TextStyle style) =>
      debugDisableCustomTypographyFonts
          ? style
          : GoogleFonts.spaceGrotesk(textStyle: style);

  static TextStyle _bodyFont(TextStyle style) =>
      debugDisableCustomTypographyFonts
          ? style
          : GoogleFonts.ibmPlexSans(textStyle: style);

  static TextStyle _monoFont(TextStyle style) =>
      debugDisableCustomTypographyFonts
          ? style
          : GoogleFonts.jetBrainsMono(textStyle: style);

  static const colors = AppColorTokens(
    background: Color(0xFF0A0F1C),
    surface: Color(0xFF10182A),
    surfaceVariant: Color(0xFF162238),
    surfaceElevated: Color(0xFF1C2C47),
    surfaceDim: Color(0xFF050B16),
    onSurface: Color(0xFFF3F7FF),
    onSurfaceVariant: Color(0xFFA9B7D1),
    onSurfaceMuted: Color(0xFF6F7D96),
    primary: Color(0xFF43E6C3),
    primaryContainer: Color(0xFF173A3A),
    onPrimary: Color(0xFF041412),
    secondary: Color(0xFF69A8FF),
    secondaryContainer: Color(0xFF142E51),
    error: Color(0xFFFF6B7A),
    errorContainer: Color(0xFF47202A),
    warning: Color(0xFFFFB454),
    warningContainer: Color(0xFF4A3415),
    success: Color(0xFF3DDB8C),
    successContainer: Color(0xFF12382A),
    border: Color(0xFF35507A),
    borderSubtle: Color(0xFF24324D),
    borderFocused: Color(0xFF7AF5DD),
    scrim: Color(0xCC09111B),
  );

  static final typography = AppTypographyTokens.fromColor(
    const Color(0xFFF3F7FF),
    displayStyle: _displayFont,
    bodyStyle: _bodyFont,
    monoStyle: _monoFont,
  );

  static const spacing = AppSpacingTokens();

  static const radius = AppRadiusTokens();

  static const motion = AppMotionTokens();

  /// All ThemeExtension instances (injected into ThemeData.extensions).
  static List<ThemeExtension> get extensions => [
        colors,
        typography,
        spacing,
        radius,
        motion,
      ];
}
