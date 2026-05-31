/// typography_tokens.dart — Typography design tokens.
//
// Fourteen semantic text styles. Font families are configured by
// app_theme.dart via GoogleFonts; this file only defines size, weight,
// line-height, etc. Injected as a ThemeExtension with lerp support.
//
// Consumed by:
//   - context.typography extension

import 'package:flutter/material.dart';

/// Disables branded font loaders in test environments.
bool debugDisableCustomTypographyFonts = false;

/// App typography tokens (14 tiers).
class AppTypographyTokens extends ThemeExtension<AppTypographyTokens> {
  final TextStyle displayLarge; // 28sp/w800 — splash title
  final TextStyle headlineLarge; // 22sp/w700 — page headline
  final TextStyle headlineMedium; // 18sp/w600 — section title
  final TextStyle titleMedium; // 16sp/w600 — card title
  final TextStyle titleSmall; // 14sp/w600 — list item title
  final TextStyle bodyLarge; // 16sp/w400 — long-form body
  final TextStyle bodyMedium; // 14sp/w400 — standard body
  final TextStyle bodySmall; // 12sp/w400 — auxiliary text
  final TextStyle labelLarge; // 14sp/w500 — button text
  final TextStyle labelMedium; // 12sp/w500 — label text
  final TextStyle labelSmall; // 11sp/w500 — nav label
  final TextStyle codeLarge; // 14sp/mono — large code
  final TextStyle codeMedium; // 13sp/mono — standard code
  final TextStyle codeSmall; // 11sp/mono — small code

  const AppTypographyTokens({
    required this.displayLarge,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.codeLarge,
    required this.codeMedium,
    required this.codeSmall,
  });

  /// Create default typography tokens from a color.
  ///
  /// [color] default text color (typically onSurface).
  /// [displayStyle] transforms hero/title styles.
  /// [bodyStyle] transforms body/label styles.
  /// [monoStyle] transforms code styles.
  factory AppTypographyTokens.fromColor(
    Color color, {
    TextStyle Function(TextStyle style)? displayStyle,
    TextStyle Function(TextStyle style)? bodyStyle,
    TextStyle Function(TextStyle style)? monoStyle,
  }) {
    TextStyle apply(
      TextStyle base,
      TextStyle Function(TextStyle style)? builder,
    ) {
      return builder != null ? builder(base) : base;
    }

    return AppTypographyTokens(
      displayLarge: apply(
        TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.05,
          letterSpacing: -0.8,
        ),
        displayStyle,
      ),
      headlineLarge: apply(
        TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.1,
          letterSpacing: -0.4,
        ),
        displayStyle,
      ),
      headlineMedium: apply(
        TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.18,
          letterSpacing: -0.2,
        ),
        displayStyle,
      ),
      titleMedium: apply(
        TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
        displayStyle,
      ),
      titleSmall: apply(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.2,
        ),
        displayStyle,
      ),
      bodyLarge: apply(
        TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.5,
        ),
        bodyStyle,
      ),
      bodyMedium: apply(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.45,
        ),
        bodyStyle,
      ),
      bodySmall: apply(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.35,
        ),
        bodyStyle,
      ),
      labelLarge: apply(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.1,
        ),
        bodyStyle,
      ),
      labelMedium: apply(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.15,
        ),
        bodyStyle,
      ),
      labelSmall: apply(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.2,
        ),
        bodyStyle,
      ),
      codeLarge: apply(
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.5,
          fontFamily: 'monospace',
        ),
        monoStyle,
      ),
      codeMedium: apply(
        TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.45,
          fontFamily: 'monospace',
        ),
        monoStyle,
      ),
      codeSmall: apply(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: color,
          height: 1.35,
          fontFamily: 'monospace',
        ),
        monoStyle,
      ),
    );
  }

  @override
  AppTypographyTokens copyWith({
    TextStyle? displayLarge,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
    TextStyle? codeLarge,
    TextStyle? codeMedium,
    TextStyle? codeSmall,
  }) {
    return AppTypographyTokens(
      displayLarge: displayLarge ?? this.displayLarge,
      headlineLarge: headlineLarge ?? this.headlineLarge,
      headlineMedium: headlineMedium ?? this.headlineMedium,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      codeLarge: codeLarge ?? this.codeLarge,
      codeMedium: codeMedium ?? this.codeMedium,
      codeSmall: codeSmall ?? this.codeSmall,
    );
  }

  @override
  AppTypographyTokens lerp(AppTypographyTokens? other, double t) {
    if (other == null) return this;
    return AppTypographyTokens(
      displayLarge: TextStyle.lerp(displayLarge, other.displayLarge, t)!,
      headlineLarge: TextStyle.lerp(headlineLarge, other.headlineLarge, t)!,
      headlineMedium: TextStyle.lerp(headlineMedium, other.headlineMedium, t)!,
      titleMedium: TextStyle.lerp(titleMedium, other.titleMedium, t)!,
      titleSmall: TextStyle.lerp(titleSmall, other.titleSmall, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t)!,
      labelMedium: TextStyle.lerp(labelMedium, other.labelMedium, t)!,
      labelSmall: TextStyle.lerp(labelSmall, other.labelSmall, t)!,
      codeLarge: TextStyle.lerp(codeLarge, other.codeLarge, t)!,
      codeMedium: TextStyle.lerp(codeMedium, other.codeMedium, t)!,
      codeSmall: TextStyle.lerp(codeSmall, other.codeSmall, t)!,
    );
  }
}
