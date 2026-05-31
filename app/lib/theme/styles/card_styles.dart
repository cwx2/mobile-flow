/// card_styles.dart — Card style compositions.
//
// Composes 3 card variants from design tokens.
//
// Consumed by:
//   - GlassCard component
//   - context.cardStyles extension

import 'package:flutter/material.dart';

import '../theme_extensions.dart';

/// Card style data.
class CardStyleData {
  final Color backgroundColor;
  final double backgroundOpacity;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final bool enableBlur;
  final double blurSigma;

  const CardStyleData({
    required this.backgroundColor,
    this.backgroundOpacity = 1.0,
    required this.borderColor,
    this.borderWidth = 1,
    required this.radius,
    this.enableBlur = false,
    this.blurSigma = 12,
  });
}

/// Card style factory (3 variants).
class AppCardStyles {
  final BuildContext _context;
  const AppCardStyles(this._context);

  /// Frosted-glass card: blurred background + translucent.
  CardStyleData get glass => CardStyleData(
        backgroundColor: _context.colors.surface,
        backgroundOpacity: 0.72,
        borderColor: _context.colors.borderSubtle,
        radius: _context.radii.lg,
        enableBlur: true,
        blurSigma: 12,
      );

  /// Elevated card: solid background + subtle border.
  CardStyleData get elevated => CardStyleData(
        backgroundColor: _context.colors.surfaceElevated,
        borderColor: _context.colors.borderSubtle,
        radius: _context.radii.md,
      );

  /// Surface card: standard background.
  CardStyleData get surface => CardStyleData(
        backgroundColor: _context.colors.surface,
        borderColor: _context.colors.borderSubtle,
        radius: _context.radii.md,
      );
}
