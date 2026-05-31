/// radius_tokens.dart — Border radius design tokens.
//
// Six border-radius constants for a unified global radius scale.
//
// Consumed by: context.radii extension

import 'package:flutter/material.dart';

/// App border-radius tokens (6 tiers).
class AppRadiusTokens extends ThemeExtension<AppRadiusTokens> {
  final double xs; // 4dp — small tags
  final double sm; // 8dp — buttons, inputs
  final double md; // 12dp — cards
  final double lg; // 16dp — large cards, dialogs
  final double xl; // 24dp — bottom sheets
  final double full; // 999dp — capsule shape

  const AppRadiusTokens({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.full = 999,
  });

  /// Convenience: create a BorderRadius from a value.
  BorderRadius circular(double value) => BorderRadius.circular(value);

  @override
  AppRadiusTokens copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? full,
  }) {
    return AppRadiusTokens(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      full: full ?? this.full,
    );
  }

  @override
  AppRadiusTokens lerp(AppRadiusTokens? other, double t) {
    if (other == null) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppRadiusTokens(
      xs: l(xs, other.xs),
      sm: l(sm, other.sm),
      md: l(md, other.md),
      lg: l(lg, other.lg),
      xl: l(xl, other.xl),
      full: l(full, other.full),
    );
  }
}
