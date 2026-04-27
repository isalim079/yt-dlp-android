/// Consistent [SnackBar] helpers for success, error, and info feedback.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';

/// Static helpers for themed snack bars.
abstract final class AppSnackbar {
  /// Short success toast with check icon.
  static void showSuccess(BuildContext context, String message) {
    _show(
      context,
      message,
      background: AppColors.of(context).success,
      foreground: Colors.white,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  /// Short error toast with alert icon.
  static void showError(BuildContext context, String message) {
    _show(
      context,
      message,
      background: AppColors.of(context).error,
      foreground: Colors.white,
      icon: Icons.error_outline_rounded,
    );
  }

  /// Neutral info toast on surface color.
  static void showInfo(BuildContext context, String message) {
    final AppUiColors c = AppColors.of(context);
    _show(
      context,
      message,
      background: c.surface,
      foreground: c.textPrimary,
      icon: Icons.info_outline_rounded,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color background,
    required Color foreground,
    required IconData icon,
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        margin: const EdgeInsets.all(AppDimensions.paddingMd),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        ),
        duration: const Duration(seconds: 3),
        content: Row(
          children: <Widget>[
            Icon(icon, color: foreground, size: AppDimensions.iconMd),
            const SizedBox(width: AppDimensions.spaceSm),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}
