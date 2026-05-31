/// app_theme.dart — Theme assembly entry point.
//
// Assembles all Token Layer ThemeExtensions into ThemeData.
// Provides buildDarkTheme() and buildDawnTheme() factory methods.
//
// Consumed by:
//   - main.dart's MaterialApp.theme

import 'package:flutter/material.dart';

import 'themes/rose_pine_dark.dart';
import 'themes/rose_pine_dawn.dart';

/// Theme builder.
class AppTheme {
  AppTheme._();

  static TextTheme _buildTextTheme(dynamic typography) {
    return TextTheme(
      displayLarge: typography.displayLarge,
      headlineLarge: typography.headlineLarge,
      headlineMedium: typography.headlineMedium,
      titleLarge: typography.titleMedium,
      titleMedium: typography.titleSmall,
      bodyLarge: typography.bodyLarge,
      bodyMedium: typography.bodyMedium,
      bodySmall: typography.bodySmall,
      labelLarge: typography.labelLarge,
      labelMedium: typography.labelMedium,
      labelSmall: typography.labelSmall,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required dynamic colors,
    required dynamic typography,
    required List<ThemeExtension<dynamic>> extensions,
  }) {
    final textTheme = _buildTextTheme(typography);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.surfaceElevated,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.secondary,
        onSecondary: colors.onSurface,
        error: colors.error,
        onError: colors.onPrimary,
        surface: colors.surface,
        onSurface: colors.onSurface,
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor:
            colors.background.withValues(alpha: isDark ? 0.92 : 0.88),
        foregroundColor: colors.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: typography.headlineMedium,
        iconTheme: IconThemeData(color: colors.onSurfaceVariant),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceElevated,
        modalBackgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceDim,
        contentTextStyle:
            typography.bodyMedium.copyWith(color: colors.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.primary;
          return colors.onSurfaceMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.primary.withValues(alpha: isDark ? 0.36 : 0.28);
          }
          return colors.surfaceVariant;
        }),
        trackOutlineColor: WidgetStateProperty.all(colors.borderSubtle),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceVariant,
        hintStyle: typography.bodyMedium.copyWith(color: colors.onSurfaceMuted),
        labelStyle:
            typography.labelMedium.copyWith(color: colors.onSurfaceVariant),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.borderFocused, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: isDark ? 0.32 : 0.22),
        selectionHandleColor: colors.primary,
      ),
      extensions: extensions,
    );
  }

  /// Build the dark Signal Console theme.
  static ThemeData buildDark() {
    return _buildTheme(
      brightness: Brightness.dark,
      colors: RosePineDark.colors,
      typography: RosePineDark.typography,
      extensions: RosePineDark.extensions,
    );
  }

  /// Build the light Signal Console theme.
  static ThemeData buildDawn() {
    return _buildTheme(
      brightness: Brightness.light,
      colors: RosePineDawn.colors,
      typography: RosePineDawn.typography,
      extensions: RosePineDawn.extensions,
    );
  }
}
