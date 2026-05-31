/// rose_pine_dawn.dart — Signal Paper theme definition.
//
// Light theme complete token definitions.
// Legacy filename retained to minimize import churn.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../tokens/color_tokens.dart';
import '../tokens/typography_tokens.dart';
import '../tokens/spacing_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/motion_tokens.dart';

class RosePineDawn {
  RosePineDawn._();

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
    background: Color(0xFFEEF4FA),
    surface: Color(0xFFF7FBFF),
    surfaceVariant: Color(0xFFECF3FB),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFE3EDF8),
    onSurface: Color(0xFF0F1728),
    onSurfaceVariant: Color(0xFF5F6F89),
    onSurfaceMuted: Color(0xFF8896AD),
    primary: Color(0xFF18C7A4),
    primaryContainer: Color(0xFFD8F9F0),
    onPrimary: Color(0xFF04231E),
    secondary: Color(0xFF2E79FF),
    secondaryContainer: Color(0xFFDEEBFF),
    error: Color(0xFFE45D6A),
    errorContainer: Color(0xFFFADDE1),
    warning: Color(0xFFE39A2E),
    warningContainer: Color(0xFFFFE8C4),
    success: Color(0xFF169B67),
    successContainer: Color(0xFFD5F4E7),
    border: Color(0xFFCAD8EB),
    borderSubtle: Color(0xFFDCE7F4),
    borderFocused: Color(0xFF18C7A4),
    scrim: Color(0x66000000),
  );

  static final typography = AppTypographyTokens.fromColor(
    const Color(0xFF0F1728),
    displayStyle: _displayFont,
    bodyStyle: _bodyFont,
    monoStyle: _monoFont,
  );

  static const spacing = AppSpacingTokens();

  static const radius = AppRadiusTokens();

  static const motion = AppMotionTokens();

  /// All ThemeExtension instances.
  static List<ThemeExtension> get extensions => [
        colors,
        typography,
        spacing,
        radius,
        motion,
      ];
}
