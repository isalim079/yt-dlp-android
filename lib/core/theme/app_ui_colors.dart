/// Theme extension for semantic UI colors used by widgets.
library;

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Resolved palette for surfaces, borders, and typography accents.
@immutable
class AppUiColors extends ThemeExtension<AppUiColors> {
  /// Creates the extension with all semantic fields.
  const AppUiColors({
    required this.primary,
    required this.primaryLight,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.error,
    required this.success,
    required this.warning,
    required this.onPrimary,
  });

  /// Brand primary (deep red).
  final Color primary;

  /// Lighter primary tint for chips and highlights.
  final Color primaryLight;

  /// Secondary accent (e.g. audio icons).
  final Color secondary;

  /// Scaffold background.
  final Color background;

  /// Cards and inputs fill.
  final Color surface;

  /// Default borders and dividers.
  final Color border;

  /// Primary text color.
  final Color textPrimary;

  /// Secondary / hint text color.
  final Color textSecondary;

  /// Error state color.
  final Color error;

  /// Success state color.
  final Color success;

  /// Warning state color.
  final Color warning;

  /// Text/icons on top of [primary].
  final Color onPrimary;

  /// Light palette instance.
  static const AppUiColors light = AppUiColors(
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    secondary: AppColors.secondary,
    background: AppColors.background,
    surface: AppColors.surface,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    error: AppColors.error,
    success: AppColors.success,
    warning: AppColors.warning,
    onPrimary: Colors.white,
  );

  /// Kept for compatibility; app runs light mode only.
  static const AppUiColors dark = light;

  /// Resolves this extension from [context].
  static AppUiColors of(BuildContext context) {
    final AppUiColors? ext = Theme.of(context).extension<AppUiColors>();
    assert(ext != null, 'ThemeData must register AppUiColors extension');
    return ext!;
  }

  @override
  AppUiColors copyWith({
    Color? primary,
    Color? primaryLight,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? error,
    Color? success,
    Color? warning,
    Color? onPrimary,
  }) {
    return AppUiColors(
      primary: primary ?? this.primary,
      primaryLight: primaryLight ?? this.primaryLight,
      secondary: secondary ?? this.secondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      error: error ?? this.error,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      onPrimary: onPrimary ?? this.onPrimary,
    );
  }

  @override
  AppUiColors lerp(ThemeExtension<AppUiColors>? other, double t) {
    if (other is! AppUiColors) {
      return this;
    }
    return AppUiColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}
