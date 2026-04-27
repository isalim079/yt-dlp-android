/// Material 3 [ThemeData] factories built from app design tokens.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import 'app_ui_colors.dart';

/// Builds [ThemeData] for light mode from design tokens.
abstract final class AppTheme {
  static ThemeData get light {
    const ColorScheme scheme = ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
    );

    final TextTheme textTheme = _textTheme(
      displayColor: AppColors.textPrimary,
      bodyColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      extensions: const <ThemeExtension<dynamic>>[AppUiColors.light],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: AppDimensions.cardElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.inputRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  static TextTheme _textTheme({
    required Color displayColor,
    required Color bodyColor,
  }) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: AppDimensions.fontSizeDisplay,
        fontWeight: FontWeight.w400,
        color: displayColor,
      ),
      headlineMedium: TextStyle(
        fontSize: AppDimensions.fontSizeHeadline,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      titleLarge: TextStyle(
        fontSize: AppDimensions.fontSizeTitle,
        fontWeight: FontWeight.w600,
        color: displayColor,
      ),
      titleMedium: TextStyle(
        fontSize: AppDimensions.fontSizeTitleSmall,
        fontWeight: FontWeight.w500,
        color: bodyColor,
      ),
      titleSmall: TextStyle(
        fontSize: AppDimensions.fontSizeBodySmall,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      bodyLarge: TextStyle(
        fontSize: AppDimensions.fontSizeBody,
        fontWeight: FontWeight.w400,
        color: bodyColor,
      ),
      bodyMedium: TextStyle(
        fontSize: AppDimensions.fontSizeBodySmall,
        fontWeight: FontWeight.w400,
        color: bodyColor,
      ),
      labelLarge: TextStyle(
        fontSize: AppDimensions.fontSizeLabel,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      labelMedium: TextStyle(
        fontSize: AppDimensions.fontSizeCaption,
        fontWeight: FontWeight.w500,
        color: bodyColor,
      ),
      bodySmall: TextStyle(
        fontSize: AppDimensions.fontSizeCaption,
        fontWeight: FontWeight.w400,
        color: bodyColor.withValues(alpha: 0.85),
      ),
    );
  }
}
