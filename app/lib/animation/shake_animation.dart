/// shake_animation.dart — Shake animation component.
///
/// Module: animation/
/// Responsibility:
///   Horizontal shake effect for connection failure, input error, etc.
///   Offsets ±offset horizontally, repeating count times.
///
/// Used by:
///   - ConnectScreen button shake on connection failure
library;

import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Shake animation wrapper.
///
/// Call [ShakeAnimationState.shake] to trigger the shake.
class ShakeAnimation extends StatefulWidget {
  final Widget child;

  /// Horizontal offset amount (dp).
  final double offset;

  /// Number of shakes.
  final int count;

  /// Total duration.
  final Duration duration;

  const ShakeAnimation({
    super.key,
    required this.child,
    this.offset = 8,
    this.count = 3,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<ShakeAnimation> createState() => ShakeAnimationState();
}

class ShakeAnimationState extends State<ShakeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  /// Trigger the shake animation.
  void shake() {
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        // Use sin function to produce left-right oscillation
        final dx = math.sin(_controller.value * widget.count * math.pi * 2) *
            widget.offset *
            (1 - _controller.value); // Gradually decay
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
