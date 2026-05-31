/// status_dot.dart — Status indicator dot component.
///
/// Module: components/
/// Responsibility:
///   Animated indicator dot for 4 states: connected (green pulse),
///   disconnected (red static), connecting (yellow blink),
///   warning (orange slow blink).
///
/// Design pattern: Strategy Pattern (4 states)
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Status type.
enum StatusDotState { connected, disconnected, connecting, warning }

/// Status indicator dot.
class StatusDot extends StatefulWidget {
  final StatusDotState state;
  final double size;

  const StatusDot({
    super.key,
    required this.state,
    this.size = 10,
  });

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _configureAnimation();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _configureAnimation();
    }
  }

  void _configureAnimation() {
    _controller.stop();
    switch (widget.state) {
      case StatusDotState.connected:
        _controller.duration = const Duration(milliseconds: 1500);
        _controller.repeat(reverse: true);
      case StatusDotState.connecting:
        _controller.duration = const Duration(milliseconds: 800);
        _controller.repeat(reverse: true);
      case StatusDotState.warning:
        _controller.duration = const Duration(milliseconds: 2000);
        _controller.repeat(reverse: true);
      case StatusDotState.disconnected:
        _controller.value = 1.0;
    }
  }

  Color _resolveColor(BuildContext context) {
    final colors = context.colors;
    switch (widget.state) {
      case StatusDotState.connected:
        return colors.success;
      case StatusDotState.disconnected:
        return colors.error;
      case StatusDotState.connecting:
        return colors.warning;
      case StatusDotState.warning:
        // TODO: Move to theme tokens when warning color is added
        return const Color(0xFFFF8C00);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context);

    if (widget.state == StatusDotState.disconnected) {
      return _buildDot(color, 1.0, 1.0);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        if (widget.state == StatusDotState.connected) {
          // Pulse scale 1.0 ↔ 1.3
          final scale = 1.0 + _controller.value * 0.3;
          return _buildDot(color, 1.0, scale);
        } else {
          // Blink opacity 0.3 ↔ 1.0
          final opacity = 0.3 + _controller.value * 0.7;
          return _buildDot(color, opacity, 1.0);
        }
      },
    );
  }

  Widget _buildDot(Color color, double opacity, double scale) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
