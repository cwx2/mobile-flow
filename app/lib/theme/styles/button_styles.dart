/// button_styles.dart — Button style compositions.
//
// Composes 4 button variants from design tokens.
// Styles depend on BuildContext to access the current theme's tokens.
//
// Consumed by:
//   - AppButton component
//   - context.buttonStyles extension

import 'package:flutter/material.dart';

import '../theme_extensions.dart';

/// Button style data (complete style description for one variant).
class ButtonStyleData {
  /// Gradient background (used by primary variant).
  final Gradient? gradient;

  /// Solid background color (used by non-gradient variants).
  final Color? backgroundColor;

  /// Foreground color (text, icons).
  final Color foreground;

  /// Border (used by secondary variant).
  final Border? border;

  /// Border radius.
  final double radius;

  /// Text style.
  final TextStyle textStyle;

  /// Press-down scale factor.
  final double pressScale;

  /// Optional shadow stack for stronger emphasis.
  final List<BoxShadow> shadows;

  const ButtonStyleData({
    this.gradient,
    this.backgroundColor,
    required this.foreground,
    this.border,
    required this.radius,
    required this.textStyle,
    this.pressScale = 0.96,
    this.shadows = const [],
  });
}

/// Button style factory (4 variants).
///
/// Usage: `context.buttonStyles.primary`
class AppButtonStyles {
  final BuildContext _context;
  const AppButtonStyles(this._context);

  /// Primary button: gradient background + dark text.
  ButtonStyleData get primary => ButtonStyleData(
        gradient: LinearGradient(
          colors: [
            _context.colors.primary,
            Color.lerp(
                _context.colors.primary, _context.colors.secondary, 0.35)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        foreground: _context.colors.onPrimary,
        radius: _context.radii.md,
        textStyle: _context.typography.labelLarge.copyWith(
          color: _context.colors.onPrimary,
        ),
        shadows: [
          BoxShadow(
            color: _context.colors.primary.withValues(
              alpha: _context.isDark ? 0.24 : 0.14,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      );

  /// Secondary button: dark panel + focused border.
  ButtonStyleData get secondary => ButtonStyleData(
        backgroundColor: _context.colors.surfaceElevated,
        foreground: _context.colors.onSurface,
        border: Border.all(
          color: _context.colors.borderFocused.withValues(alpha: 0.45),
          width: 1,
        ),
        radius: _context.radii.md,
        textStyle: _context.typography.labelLarge.copyWith(
          color: _context.colors.onSurface,
        ),
        shadows: [
          BoxShadow(
            color: _context.colors.scrim.withValues(
              alpha: _context.isDark ? 0.16 : 0.05,
            ),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      );

  /// Ghost button: brand-tinted transparent background.
  ButtonStyleData get ghost => ButtonStyleData(
        backgroundColor: _context.colors.primary.withValues(
          alpha: _context.isDark ? 0.10 : 0.08,
        ),
        foreground: _context.colors.primary,
        radius: _context.radii.md,
        textStyle: _context.typography.labelLarge.copyWith(
          color: _context.colors.primary,
        ),
      );

  /// Danger button: red-orange alert gradient.
  ButtonStyleData get danger => ButtonStyleData(
        gradient: LinearGradient(
          colors: [
            _context.colors.error,
            Color.lerp(_context.colors.error, _context.colors.warning, 0.25)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        foreground: _context.colors.onPrimary,
        radius: _context.radii.md,
        textStyle: _context.typography.labelLarge.copyWith(
          color: _context.colors.onPrimary,
        ),
        shadows: [
          BoxShadow(
            color: _context.colors.error.withValues(
              alpha: _context.isDark ? 0.22 : 0.12,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      );
}
