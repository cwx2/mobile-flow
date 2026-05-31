/// skeleton_loader.dart — Skeleton loading placeholder component.
///
/// Module: components/
/// Responsibility:
///   Loading placeholder component that uses ShimmerPainter for a
///   shimmer effect. Supports configurable line count, height, and
///   width range.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../animation/shimmer_painter.dart';
import '../theme/theme_extensions.dart';

/// Skeleton loading placeholder.
class SkeletonLoader extends StatefulWidget {
  final int lines;
  final double lineHeight;
  final double minWidthFraction;
  final double maxWidthFraction;

  const SkeletonLoader({
    super.key,
    this.lines = 3,
    this.lineHeight = 20,
    this.minWidthFraction = 0.4,
    this.maxWidthFraction = 0.8,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<double> _widthFractions;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Pre-generate random widths
    final rng = Random(42);
    _widthFractions = List.generate(widget.lines, (_) {
      return widget.minWidthFraction +
          rng.nextDouble() *
              (widget.maxWidthFraction - widget.minWidthFraction);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseColor = colors.surfaceVariant;
    final highlightColor = colors.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(widget.lines, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: context.spacing.sm),
              child: FractionallySizedBox(
                widthFactor: _widthFractions[i],
                child: CustomPaint(
                  painter: ShimmerPainter(
                    progress: _controller.value,
                    baseColor: baseColor,
                    highlightColor: highlightColor,
                  ),
                  child: Container(
                    height: widget.lineHeight,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(context.radii.xs),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
