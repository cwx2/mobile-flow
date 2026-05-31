/// spacing_tokens.dart — Spacing design tokens.
//
// Eight spacing constants for a unified global spacing scale.
//
// Consumed by: context.spacing extension

import 'package:flutter/material.dart';

/// App spacing tokens (8 tiers).
class AppSpacingTokens extends ThemeExtension<AppSpacingTokens> {
  final double xxs; // 2dp
  final double xs; // 4dp
  final double sm; // 8dp
  final double md; // 12dp
  final double lg; // 16dp
  final double xl; // 24dp
  final double xxl; // 32dp
  final double xxxl; // 48dp

  const AppSpacingTokens({
    this.xxs = 2,
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.xxl = 32,
    this.xxxl = 48,
  });

  /// Convenience: create symmetric padding from a value.
  EdgeInsets insets(double value) => EdgeInsets.all(value);

  /// Convenience: create horizontal padding from a value.
  EdgeInsets insetsH(double value) => EdgeInsets.symmetric(horizontal: value);

  /// Convenience: create vertical padding from a value.
  EdgeInsets insetsV(double value) => EdgeInsets.symmetric(vertical: value);

  @override
  AppSpacingTokens copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
  }) {
    return AppSpacingTokens(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
    );
  }

  @override
  AppSpacingTokens lerp(AppSpacingTokens? other, double t) {
    if (other == null) return this;
    return AppSpacingTokens(
      xxs: _lerpDouble(xxs, other.xxs, t),
      xs: _lerpDouble(xs, other.xs, t),
      sm: _lerpDouble(sm, other.sm, t),
      md: _lerpDouble(md, other.md, t),
      lg: _lerpDouble(lg, other.lg, t),
      xl: _lerpDouble(xl, other.xl, t),
      xxl: _lerpDouble(xxl, other.xxl, t),
      xxxl: _lerpDouble(xxxl, other.xxxl, t),
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
