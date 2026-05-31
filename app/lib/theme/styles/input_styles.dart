/// input_styles.dart — Input field style compositions.
//
// Composes input field styles from design tokens.
//
// Consumed by:
//   - AppTextField component
//   - context.inputStyles extension

import 'package:flutter/material.dart';

import '../theme_extensions.dart';

/// Input field style data.
class InputStyleData {
  final Color backgroundColor;
  final Color borderColor;
  final Color borderFocusedColor;
  final Color textColor;
  final Color hintColor;
  final double radius;
  final TextStyle textStyle;
  final TextStyle hintStyle;
  final EdgeInsets contentPadding;

  const InputStyleData({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderFocusedColor,
    required this.textColor,
    required this.hintColor,
    required this.radius,
    required this.textStyle,
    required this.hintStyle,
    required this.contentPadding,
  });
}

/// Input field style factory.
class AppInputStyles {
  final BuildContext _context;
  const AppInputStyles(this._context);

  /// Chat input field style.
  InputStyleData get chat => InputStyleData(
        backgroundColor: _context.colors.surfaceVariant,
        borderColor: _context.colors.borderSubtle,
        borderFocusedColor: _context.colors.borderFocused,
        textColor: _context.colors.onSurface,
        hintColor: _context.colors.onSurfaceMuted,
        radius: _context.radii.lg,
        textStyle: _context.typography.bodyMedium,
        hintStyle: _context.typography.bodyMedium.copyWith(
          color: _context.colors.onSurfaceMuted,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: _context.spacing.lg,
          vertical: _context.spacing.md,
        ),
      );

  /// Form input field style.
  InputStyleData get form => InputStyleData(
        backgroundColor: _context.colors.surfaceVariant,
        borderColor: _context.colors.borderSubtle,
        borderFocusedColor: _context.colors.borderFocused,
        textColor: _context.colors.onSurface,
        hintColor: _context.colors.onSurfaceMuted,
        radius: _context.radii.md,
        textStyle: _context.typography.bodyMedium,
        hintStyle: _context.typography.bodyMedium.copyWith(
          color: _context.colors.onSurfaceMuted,
        ),
        contentPadding: EdgeInsets.all(_context.spacing.md),
      );
}
