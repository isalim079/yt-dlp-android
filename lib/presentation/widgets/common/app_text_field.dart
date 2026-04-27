/// Single-line text field with shared decoration and semantics.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';

/// Styled text field for URLs and short inputs.
class AppTextField extends StatelessWidget {
  /// Creates a configured text field.
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
  });

  /// Optional external controller for form integration.
  final TextEditingController? controller;

  /// Hint when empty (use [AppStrings] at call sites).
  final String? hintText;

  /// Floating label (use [AppStrings] at call sites).
  final String? labelText;

  /// Emits edits upstream.
  final ValueChanged<String>? onChanged;

  /// Invoked when the user submits the keyboard action.
  final ValueChanged<String>? onSubmitted;

  /// Leading icon inside the field.
  final Widget? prefixIcon;

  /// Trailing widget inside the field.
  final Widget? suffixIcon;

  /// When `false`, the field is read-only and dimmed.
  final bool enabled;

  /// Validation or network error text shown below the field.
  final String? errorText;

  /// Keyboard layout for URL vs plain text entry.
  final TextInputType? keyboardType;

  /// IME action key (e.g. search) on soft keyboards.
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      borderSide: BorderSide(color: c.border),
    );
    final OutlineInputBorder focused = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      borderSide: BorderSide(color: c.primary, width: 2),
    );

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: c.surface,
        hintText: hintText,
        labelText: labelText,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMd,
          vertical: AppDimensions.paddingMd,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focused,
        disabledBorder: border,
        errorBorder: border.copyWith(borderSide: BorderSide(color: c.error)),
        focusedErrorBorder: focused.copyWith(
          borderSide: BorderSide(color: c.error, width: 2),
        ),
        hintStyle: TextStyle(color: c.textSecondary),
        labelStyle: TextStyle(color: c.textSecondary),
        constraints: const BoxConstraints(
          minHeight: AppDimensions.textFieldHeight,
        ),
      ),
    );
  }
}
