/// app_text_field.dart — App text field component.
///
/// Module: components/
/// Responsibility:
///   Unified styled text field with animated border on focus.
///   Supports prefix icon, suffix icon, and error state.
library;

import 'package:flutter/material.dart';

import '../theme/theme_extensions.dart';

/// App text field.
class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLength;
  final int maxLines;
  final int minLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLength,
    this.maxLines = 1,
    this.minLines = 1,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final hasError = errorText != null && errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: minLines,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: context.typography.bodyMedium,
          cursorColor: colors.primary,
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            hintStyle: context.typography.bodyMedium.copyWith(
              color: colors.onSurfaceMuted,
            ),
            labelStyle: context.typography.bodySmall.copyWith(
              color: colors.onSurfaceVariant,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 20, color: colors.onSurfaceVariant)
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: colors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radii.md),
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radii.md),
              borderSide: BorderSide(
                color: hasError ? colors.error : colors.borderSubtle,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(radii.md),
              borderSide: BorderSide(
                color: hasError ? colors.error : colors.borderFocused,
                width: 1.5,
              ),
            ),
            contentPadding: EdgeInsets.all(context.spacing.md),
            counterText: '',
          ),
        ),
        if (hasError) ...[
          SizedBox(height: context.spacing.xs),
          Padding(
            padding: EdgeInsets.only(left: context.spacing.md),
            child: Text(
              errorText!,
              style: context.typography.bodySmall.copyWith(color: colors.error),
            ),
          ),
        ],
      ],
    );
  }
}
