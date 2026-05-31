/// pressable_animator.dart — Press animation component.
///
/// Module: animation/
/// Responsibility:
///   Wraps any Widget to provide press-to-scale + spring bounce-back + haptic feedback.
///   This is the most essential micro-interaction component in the entire UI system.
///
/// Used by:
///   - GlassCard, AppButton, navigation items, list items, and all tappable elements
///
/// Design pattern: Composite Widget
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Press animation wrapper.
///
/// Scales down to [pressScale] (default 0.96) on press,
/// springs back to 1.0 on release using a spring curve,
/// and triggers [HapticFeedback.lightImpact].
class PressableAnimator extends StatefulWidget {
  /// Child widget.
  final Widget child;

  /// Tap callback.
  final VoidCallback? onTap;

  /// Long press callback.
  final VoidCallback? onLongPress;

  /// Scale factor when pressed (0.96 = shrink by 4%).
  final double pressScale;

  /// Whether to enable haptic feedback.
  final bool enableHaptic;

  const PressableAnimator({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressScale = 0.96,
    this.enableHaptic = true,
  });

  @override
  State<PressableAnimator> createState() => _PressableAnimatorState();
}

class _PressableAnimatorState extends State<PressableAnimator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
      reverseCurve: Curves.easeOutBack,
    ));
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _isPressed = true;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (!_isPressed) return;
    _isPressed = false;
    _controller.reverse();
  }

  void _onTapCancel() {
    if (!_isPressed) return;
    _isPressed = false;
    _controller.reverse();
  }

  void _onTap() {
    if (widget.onTap == null) return;
    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
