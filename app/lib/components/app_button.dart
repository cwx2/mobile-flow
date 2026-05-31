/// app_button.dart — App button component.
///
/// Module: components/
/// Responsibility:
///   Unified button with 4 variants (primary/secondary/ghost/danger).
///   Supports loading and disabled states, wrapped with PressableAnimator.
///
/// Design pattern: Strategy Pattern (4 variants)
library;

import 'package:flutter/material.dart';

import '../animation/pressable_animator.dart';
import '../theme/theme_extensions.dart';
import '../theme/styles/button_styles.dart';

/// Button variant.
enum AppButtonVariant { primary, secondary, ghost, danger }

/// App button.
class AppButton extends StatelessWidget {
  final String label;
  final AppButtonVariant variant;
  final VoidCallback? onTap;
  final bool loading;
  final bool disabled;
  final IconData? icon;
  final double? width;

  const AppButton({
    super.key,
    required this.label,
    this.variant = AppButtonVariant.primary,
    this.onTap,
    this.loading = false,
    this.disabled = false,
    this.icon,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle(context);
    final isDisabled = disabled || loading;
    final opacity = isDisabled ? 0.5 : 1.0;

    Widget content = Row(
      mainAxisSize: width != null ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: style.foreground,
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: style.foreground),
          const SizedBox(width: 8),
        ],
        Text(label, style: style.textStyle),
      ],
    );

    Widget button = AnimatedOpacity(
      opacity: opacity,
      duration: context.motion.fast,
      child: Container(
        width: width,
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.lg,
          vertical: context.spacing.md,
        ),
        decoration: BoxDecoration(
          gradient: style.gradient,
          color: style.gradient == null ? style.backgroundColor : null,
          borderRadius: BorderRadius.circular(style.radius),
          boxShadow: style.shadows,
          border: style.border != null
              ? Border.all(
                  color: (style.border as Border).top.color,
                  width: (style.border as Border).top.width,
                )
              : null,
        ),
        child: content,
      ),
    );

    return PressableAnimator(
      onTap: isDisabled ? null : onTap,
      enableHaptic: !isDisabled,
      child: button,
    );
  }

  ButtonStyleData _resolveStyle(BuildContext context) {
    final styles = context.buttonStyles;
    switch (variant) {
      case AppButtonVariant.primary:
        return styles.primary;
      case AppButtonVariant.secondary:
        return styles.secondary;
      case AppButtonVariant.ghost:
        return styles.ghost;
      case AppButtonVariant.danger:
        return styles.danger;
    }
  }
}
