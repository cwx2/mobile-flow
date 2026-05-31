/// section_header.dart — Section header component.
///
/// Module: components/
/// Responsibility: Colored icon on the left + title text + optional
///   trailing action area on the right.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// Section header.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final EdgeInsets? padding;
  final double iconContainerSize;
  final double iconSize;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
    this.padding,
    this.iconContainerSize = 28,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(
        context.spacing.lg,
        context.spacing.xl,
        context.spacing.lg,
        context.spacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(context.radii.sm),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.28),
              ),
            ),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
          SizedBox(width: context.spacing.sm),
          Text(
            title,
            style: context.typography.labelLarge.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
