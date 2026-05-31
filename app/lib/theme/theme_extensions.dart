/// theme_extensions.dart — BuildContext theme extension methods.
//
// Provides convenient context.colors / context.typography / context.spacing /
// context.radii / context.motion / context.buttonStyles accessors,
// avoiding verbose Theme.of(context).extension<T>() calls.
//
// Consumed by:
//   - All Component and Screen files

import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/typography_tokens.dart';
import 'tokens/spacing_tokens.dart';
import 'tokens/radius_tokens.dart';
import 'tokens/motion_tokens.dart';
import 'styles/button_styles.dart';
import 'styles/card_styles.dart';
import 'styles/input_styles.dart';

/// Theme token + style convenience accessors.
extension AppThemeX on BuildContext {
  // ── Token Layer ──

  /// Color tokens (24 semantic colors).
  AppColorTokens get colors => Theme.of(this).extension<AppColorTokens>()!;

  /// Typography tokens (14 tiers).
  AppTypographyTokens get typography =>
      Theme.of(this).extension<AppTypographyTokens>()!;

  /// Spacing tokens (8 tiers).
  AppSpacingTokens get spacing => Theme.of(this).extension<AppSpacingTokens>()!;

  /// Border-radius tokens (6 tiers).
  AppRadiusTokens get radii => Theme.of(this).extension<AppRadiusTokens>()!;

  /// Motion tokens (durations + curves).
  AppMotionTokens get motion => Theme.of(this).extension<AppMotionTokens>()!;

  // ── Style Layer ──

  /// Button styles (primary / secondary / ghost / danger).
  AppButtonStyles get buttonStyles => AppButtonStyles(this);

  /// Card styles (glass / elevated / surface).
  AppCardStyles get cardStyles => AppCardStyles(this);

  /// Input styles (chat / form).
  AppInputStyles get inputStyles => AppInputStyles(this);

  // ── Helpers ──

  /// Whether the current theme is dark.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
