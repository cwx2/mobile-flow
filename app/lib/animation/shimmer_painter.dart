/// shimmer_painter.dart — Skeleton screen shimmer painter.
///
/// Module: animation/
/// Responsibility:
///   Draws a left-to-right gloss sweep effect on loading placeholder blocks
///   using LinearGradient. Driven by an AnimationController with a 1.5s cycle.
///
/// Used by:
///   - SkeletonLoader component
library;

import 'package:flutter/material.dart';

/// Shimmer effect painter.
///
/// [progress] is driven by an AnimationController (0.0 → 1.0 loop).
class ShimmerPainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final Color highlightColor;

  ShimmerPainter({
    required this.progress,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Shimmer band width is 40% of the container width
    final shimmerWidth = size.width * 0.4;
    // Shimmer band slides from outside the left edge to outside the right edge
    final dx = -shimmerWidth + (size.width + shimmerWidth * 2) * progress;

    final gradient = LinearGradient(
      colors: [baseColor, highlightColor, baseColor],
      stops: const [0.0, 0.5, 1.0],
    );

    final rect = Rect.fromLTWH(dx, 0, shimmerWidth, size.height);
    final paint = Paint()..shader = gradient.createShader(rect);

    // Clip to the container bounds
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(ShimmerPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
