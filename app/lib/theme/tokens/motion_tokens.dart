/// motion_tokens.dart — Motion/animation design tokens.
//
// Unified global animation durations and curves for consistent motion rhythm.
// Includes 4 duration tiers and 4 curve types.
//
// Consumed by: context.motion extension

import 'package:flutter/material.dart';

/// App motion tokens.
class AppMotionTokens extends ThemeExtension<AppMotionTokens> {
  /// Fast animation (button feedback, micro-interactions)
  final Duration fast;

  /// Normal animation (page transitions, list items)
  final Duration normal;

  /// Slow animation (complex transitions, choreographed sequences)
  final Duration slow;

  /// Extra-slow animation (launch animations, brand reveals)
  final Duration xSlow;

  /// Standard ease-out curve (default for most animations)
  final Curve easeOut;

  /// Spring curve (button bounce, card release)
  final Curve spring;

  /// Deceleration curve (scroll inertia, natural stop)
  final Curve decelerate;

  /// Emphasized curve (important transitions, page switches)
  final Curve emphasized;

  const AppMotionTokens({
    this.fast = const Duration(milliseconds: 100),
    this.normal = const Duration(milliseconds: 200),
    this.slow = const Duration(milliseconds: 350),
    this.xSlow = const Duration(milliseconds: 500),
    this.easeOut = Curves.easeOutCubic,
    this.spring = Curves.easeOutBack,
    this.decelerate = Curves.decelerate,
    this.emphasized = Curves.easeInOutCubicEmphasized,
  });

  /// Create a spring simulation (for AnimationController.animateWith).
  SpringDescription get springDesc => const SpringDescription(
        mass: 1.0,
        stiffness: 300,
        damping: 20,
      );

  /// Navigation bar bounce spring (stiffer, faster).
  SpringDescription get navSpringDesc => const SpringDescription(
        mass: 1.0,
        stiffness: 500,
        damping: 15,
      );

  @override
  AppMotionTokens copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Duration? xSlow,
    Curve? easeOut,
    Curve? spring,
    Curve? decelerate,
    Curve? emphasized,
  }) {
    return AppMotionTokens(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      xSlow: xSlow ?? this.xSlow,
      easeOut: easeOut ?? this.easeOut,
      spring: spring ?? this.spring,
      decelerate: decelerate ?? this.decelerate,
      emphasized: emphasized ?? this.emphasized,
    );
  }

  @override
  AppMotionTokens lerp(AppMotionTokens? other, double t) {
    // Motion tokens don't need interpolation; return the target value directly.
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}
