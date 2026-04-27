/// Color design tokens for the app palette (light-only).
library;

import 'package:flutter/material.dart';

import '../theme/app_ui_colors.dart';

abstract final class AppColors {
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0F0F0);
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderFocus = Color(0xFFC62828);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
  static const Color primary = Color(0xFFC62828);
  static const Color primaryLight = Color(0xFFFFEBEE);
  static const Color primaryDark = Color(0xFF8E0000);
  static const Color secondary = Color(0xFF1565C0);
  static const Color secondaryLight = Color(0xFFE3F2FD);
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57F17);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color error = Color(0xFFB71C1C);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color unplayed = Color(0xFF1565C0);
  static const Color shadow = Color(0x1A000000);
  static const Color shadowMd = Color(0x29000000);

  /// Semantic UI colors for the active theme brightness.
  static AppUiColors of(BuildContext context) => AppUiColors.of(context);
}
