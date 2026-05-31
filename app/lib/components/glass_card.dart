/// glass_card.dart — Frosted glass card component.
///
/// Module: components/
/// Responsibility:
///   iOS-style frosted glass card. Uses BackdropFilter + RepaintBoundary
///   for blurred background, supports press animation and fallback for
///   low-end devices.
///
/// Used by:
///   - Empty state pages, settings groups, connection page form areas, etc.
///
/// Design pattern: Composite Widget
library;

import 'dart:ui';

import 'package:flutter/material.dart';

import '../animation/pressable_animator.dart';
import '../theme/theme_extensions.dart';

/// Frosted glass card.
///
/// Uses [BackdropFilter] for a semi-transparent blurred background.
/// On low-end devices, set [enableBlur] = false to fall back to
/// a solid semi-transparent surface.
class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enableBlur;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.enableBlur = true,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final isDark = context.isDark;
    final br = borderRadius ?? BorderRadius.circular(radii.lg);

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            enableBlur
                ? colors.surfaceElevated.withValues(alpha: isDark ? 0.78 : 0.92)
                : colors.surfaceElevated,
            colors.surface.withValues(alpha: isDark ? 0.9 : 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: br,
        border: Border.all(
          color: (enableBlur ? colors.border : colors.borderSubtle).withValues(
            alpha: isDark ? 0.72 : 0.88,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.scrim.withValues(alpha: isDark ? 0.18 : 0.07),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: colors.primary.withValues(alpha: isDark ? 0.06 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: padding ?? EdgeInsets.all(context.spacing.lg),
      child: child,
    );

    if (enableBlur) {
      card = ClipRRect(
        borderRadius: br,
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: card,
          ),
        ),
      );
    }

    if (onTap != null) {
      card = PressableAnimator(onTap: onTap, child: card);
    }

    return card;
  }
}
