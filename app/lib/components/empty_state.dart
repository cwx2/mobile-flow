/// empty_state.dart — Empty state placeholder component.
///
/// Module: components/
/// Responsibility:
///   Unified empty state display: icon + title + description + optional action.
///   Wrapped in GlassCard, with scale + fade-in entrance animation.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';
import 'glass_card.dart';

/// Empty state component.
class EmptyState extends StatefulWidget {
  final IconData icon;
  final Color? iconColor;
  final double iconSize;
  final String title;
  final String? description;
  final Widget? action;
  final bool useGlassCard;

  const EmptyState({
    super.key,
    required this.icon,
    this.iconColor,
    this.iconSize = 64,
    required this.title,
    this.description,
    this.action,
    this.useGlassCard = true,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(widget.icon, size: widget.iconSize, color: widget.iconColor ?? colors.primary),
        SizedBox(height: context.spacing.lg),
        Text(widget.title, style: typography.titleMedium),
        if (widget.description != null) ...[
          SizedBox(height: context.spacing.sm),
          Text(
            widget.description!,
            style: typography.bodySmall.copyWith(color: colors.onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.action != null) ...[
          SizedBox(height: context.spacing.lg),
          widget.action!,
        ],
      ],
    );

    if (widget.useGlassCard) {
      content = GlassCard(
        padding: EdgeInsets.all(context.spacing.xl),
        child: content,
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Center(child: content),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
