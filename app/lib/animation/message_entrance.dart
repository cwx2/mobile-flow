/// message_entrance.dart — Chat message entrance animation.
///
/// Module: animation/
/// Responsibility:
///   Provides a slide + fade entrance for chat messages.
///   User messages slide in from the right, AI messages from the left.
///   Plays once on first build, then stays fully visible.
///
/// Used by:
///   - ChatBubble (wraps each message)
library;

import 'package:flutter/material.dart';

/// Entrance animation direction.
enum EntranceDirection { left, right }

/// Slide + fade entrance animation wrapper.
///
/// Plays a one-shot animation on first build: the child slides in
/// from [direction] with a concurrent fade-in. After the animation
/// completes, the child remains fully visible with zero overhead.
class MessageEntrance extends StatefulWidget {
  final Widget child;
  final EntranceDirection direction;
  final Duration duration;

  const MessageEntrance({
    super.key,
    required this.child,
    this.direction = EntranceDirection.left,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  State<MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<MessageEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    // Slide offset: left messages come from (-0.08, 0), right from (0.08, 0)
    final dx = widget.direction == EntranceDirection.left ? -0.08 : 0.08;
    _slideAnimation = Tween<Offset>(
      begin: Offset(dx, 0),
      end: Offset.zero,
    ).animate(curved);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
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
