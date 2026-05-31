/// workbench_state_card.dart — Minimal state indicator for workbench screens.
///
/// Provides a consistent UI for empty, loading, blocked, and error states
/// across chat, terminal, files, and git screens.
/// Design: simple centered layout, no card borders, no glass effects.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Minimal state indicator for empty, loading, blocked, and error states.
///
/// Displays a tinted icon, optional badge text, title, description,
/// and optional action widget. No card borders or shadows — just
/// content centered on the background.
class WorkbenchStateCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color? tint;
  final Widget? action;
  final String? badge;
  final bool compact;

  const WorkbenchStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.tint,
    this.action,
    this.badge,
    this.compact = false,
  });

  @override
  State<WorkbenchStateCard> createState() => _WorkbenchStateCardState();
}

class _WorkbenchStateCardState extends State<WorkbenchStateCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
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
    final resolvedTint = widget.tint ?? colors.primary;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 32 : 48,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon — simple, no container box
              Icon(
                widget.icon,
                size: widget.compact ? 36 : 44,
                color: resolvedTint.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),

              // Badge — subtle text, no border
              if (widget.badge != null) ...[
                Text(
                  widget.badge!,
                  style: typography.labelSmall.copyWith(
                    color: resolvedTint,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Title
              Text(
                widget.title,
                style: typography.titleMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              // Description
              Text(
                widget.description,
                style: typography.bodySmall.copyWith(
                  color: colors.onSurfaceMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              // Action
              if (widget.action != null) ...[
                const SizedBox(height: 20),
                widget.action!,
              ],
            ],
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
