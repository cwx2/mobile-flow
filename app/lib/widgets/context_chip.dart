/// context_chip.dart — Compact chip for a single context reference.
///
/// Displays a [ContextReference] as a pill-shaped chip with a type icon,
/// truncated display name, and a remove button. Designed for mobile:
/// compact height (~28px), horizontal padding, and pill border radius.
///
/// Used in a horizontally scrollable row above the ChatInputBar text
/// field. Each chip reads its icon and display name from the
/// [ContextReference] model, keeping this widget stateless and thin.
///
/// See also: [ContextReference.displayName], [ContextReference.icon].
library;

import 'package:flutter/material.dart';

import '../models/context_reference.dart';
import '../theme/theme_extensions.dart';

/// Compact chip displaying a context reference with icon, name, and remove button.
///
/// Shown in a horizontally scrollable row above the ChatInputBar text field.
/// The chip uses design system tokens for colors and typography, and reads
/// its visual content from the [reference] model (icon, displayName).
///
/// [onRemove] is called when the user taps the X button to dismiss the chip.
class ContextChip extends StatelessWidget {
  /// The context reference to display.
  final ContextReference reference;

  /// Called when the user taps the remove (X) button.
  final VoidCallback onRemove;

  /// Create a context chip.
  const ContextChip({
    super.key,
    required this.reference,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 8, right: 4),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border.all(color: colors.borderSubtle, width: 0.5),
        // Pill shape — half of height for fully rounded ends.
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Type-specific icon (small, 14px).
          Icon(
            reference.icon,
            size: 14,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          // Truncated display name — constrained to avoid overflow.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              reference.displayName,
              style: typography.labelSmall.copyWith(
                color: colors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 2),
          // Remove button (small X icon, 12px).
          GestureDetector(
            onTap: onRemove,
            // Slightly larger hit target than the visual icon for usability.
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 12,
                color: colors.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
