/// color_tokens.dart — Semantic color design tokens for the theme system.
//
// Atomic layer of the design system — semantic color variables.
// Injected into ThemeData via Flutter 3's ThemeExtension<T> pattern,
// accessed through Theme.of(context).extension<AppColorTokens>().
// Implements lerp for smooth theme transitions (dark ↔ light interpolation).
//
// Consumed by:
//   - theme_extensions.dart's context.colors extension
//   - Style layer composition classes
//
// Dependencies:
//   - None (pure Flutter)

import 'package:flutter/material.dart';

/// App color tokens (24 semantic colors).
///
/// Follows Material 3 semantic naming conventions with a custom palette.
/// Each color has a clear purpose; hardcoding Color(0xFF...) in business code is prohibited.
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  /// Base page background color
  final Color background;

  /// Container background for cards, panels, etc.
  final Color surface;

  /// Secondary container background (e.g. input fields, code blocks)
  final Color surfaceVariant;

  /// Elevated container background (e.g. dialogs, dropdown menus)
  final Color surfaceElevated;

  /// Dimmer background than [background] (e.g. terminal interior)
  final Color surfaceDim;

  /// Primary text color on surface
  final Color onSurface;

  /// Secondary text color on surface
  final Color onSurfaceVariant;

  /// Muted text color on surface (hints, placeholders)
  final Color onSurfaceMuted;

  /// Primary accent color (brand color)
  final Color primary;

  /// Primary container background (desaturated variant)
  final Color primaryContainer;

  /// Text color on primary
  final Color onPrimary;

  /// Secondary accent color
  final Color secondary;

  /// Secondary container background
  final Color secondaryContainer;

  /// Error / danger color
  final Color error;

  /// Error container background
  final Color errorContainer;

  /// Warning color
  final Color warning;

  /// Warning container background
  final Color warningContainer;

  /// Success color
  final Color success;

  /// Success container background
  final Color successContainer;

  /// Standard border color
  final Color border;

  /// Subtle border color (dividers, guide lines)
  final Color borderSubtle;

  /// Focused border color (input focus state)
  final Color borderFocused;

  /// Scrim overlay color (dialog backdrop)
  final Color scrim;

  const AppColorTokens({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.surfaceDim,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.onSurfaceMuted,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.secondary,
    required this.secondaryContainer,
    required this.error,
    required this.errorContainer,
    required this.warning,
    required this.warningContainer,
    required this.success,
    required this.successContainer,
    required this.border,
    required this.borderSubtle,
    required this.borderFocused,
    required this.scrim,
  });

  @override
  AppColorTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceElevated,
    Color? surfaceDim,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? onSurfaceMuted,
    Color? primary,
    Color? primaryContainer,
    Color? onPrimary,
    Color? secondary,
    Color? secondaryContainer,
    Color? error,
    Color? errorContainer,
    Color? warning,
    Color? warningContainer,
    Color? success,
    Color? successContainer,
    Color? border,
    Color? borderSubtle,
    Color? borderFocused,
    Color? scrim,
  }) {
    return AppColorTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderFocused: borderFocused ?? this.borderFocused,
      scrim: scrim ?? this.scrim,
    );
  }

  /// Color interpolation for theme transitions (supports AnimatedTheme smooth crossfade)
  @override
  AppColorTokens lerp(AppColorTokens? other, double t) {
    if (other == null) return this;
    return AppColorTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant:
          Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryContainer:
          Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderFocused: Color.lerp(borderFocused, other.borderFocused, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}
