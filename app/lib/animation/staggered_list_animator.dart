/// staggered_list_animator.dart — Staggered list animation mixin.
///
/// Module: animation/
/// Responsibility:
///   Provides staggered entrance animations for list items (waterfall effect).
///   Each item is delayed by staggerDelay, using SlideTransition + FadeTransition.
///
/// Used by:
///   - FilesScreen, GitScreen, ChatScreen, and other list-based pages
///
/// Design pattern: Mixin Pattern
library;

import 'package:flutter/material.dart';

/// Staggered list animation mixin.
///
/// Usage:
/// 1. State class with StaggeredListAnimator
/// 2. Call initStagger(itemCount: n) in initState
/// 3. Wrap list items with buildStaggeredItem(index, child)
mixin StaggeredListAnimator on State<StatefulWidget>, TickerProviderStateMixin {
  AnimationController? _staggerController;

  /// Initialize staggered animation.
  ///
  /// [itemCount] number of list items.
  /// [staggerDelay] delay per item (default 40ms).
  /// [itemDuration] animation duration per item (default 200ms).
  void initStagger({
    required int itemCount,
    Duration staggerDelay = const Duration(milliseconds: 40),
    Duration itemDuration = const Duration(milliseconds: 200),
  }) {
    _staggerController?.dispose();
    if (itemCount <= 0) return;

    // Total duration = last item's start time + single item duration,
    // clamped to a maximum of 600ms
    final totalMs = ((itemCount - 1) * staggerDelay.inMilliseconds +
            itemDuration.inMilliseconds)
        .clamp(itemDuration.inMilliseconds, 600);

    _staggerController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _staggerController!.forward();
  }

  /// Replay the animation (call when data refreshes).
  void replayStagger() {
    _staggerController?.forward(from: 0);
  }

  /// Wrap a list item with staggered entrance animation.
  ///
  /// [index] list item index.
  /// [child] original list item Widget.
  /// [staggerDelay] delay per item (default 40ms).
  /// [itemDuration] animation duration per item (default 200ms).
  Widget buildStaggeredItem(
    int index,
    Widget child, {
    Duration staggerDelay = const Duration(milliseconds: 40),
    Duration itemDuration = const Duration(milliseconds: 200),
  }) {
    if (_staggerController == null) return child;

    final totalMs = _staggerController!.duration!.inMilliseconds;
    final startMs = index * staggerDelay.inMilliseconds;
    final endMs = startMs + itemDuration.inMilliseconds;

    // Normalize to 0.0 ~ 1.0
    final start = (startMs / totalMs).clamp(0.0, 1.0);
    final end = (endMs / totalMs).clamp(0.0, 1.0);

    if (start >= end) return child;

    final animation = CurvedAnimation(
      parent: _staggerController!,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  /// Dispose animation resources (no need to call manually in dispose).
  void disposeStagger() {
    _staggerController?.dispose();
    _staggerController = null;
  }
}
