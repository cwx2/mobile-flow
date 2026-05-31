/// counter_animator.dart — Animated number counter component.
///
/// Module: animation/
/// Responsibility:
///   Transitions number changes with a vertical scroll animation
///   (old number slides up and out + new number slides in from below).
///   Used for count badges on Tab labels, Git change counts, etc.
///
/// Used by:
///   - GitScreen Tab labels, status indicators
library;

import 'package:flutter/material.dart';

/// Animated number scroll component.
///
/// When [value] changes, the old value slides up and out while
/// the new value slides in from below.
class AnimatedCounter extends StatelessWidget {
  /// Current numeric value.
  final int value;

  /// Text style.
  final TextStyle? style;

  /// Animation duration.
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) {
        // Determine whether this is the entering or exiting value
        final isEntering = child.key == ValueKey<int>(value);
        final slideOffset = isEntering
            ? Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            : Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1));

        return SlideTransition(
          position: slideOffset.animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Text(
        '$value',
        key: ValueKey<int>(value),
        style: style,
      ),
    );
  }
}
