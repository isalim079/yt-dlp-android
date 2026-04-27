/// Themed [DropdownButtonFormField] aligned with [AppTextField] styling.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';

/// Single-select dropdown with filled surface and rounded outline border.
class AppDropdown<T> extends StatelessWidget {
  /// Creates a dropdown bound to [items] and [value].
  const AppDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.labelBuilder,
    this.hint,
    this.enabled = true,
  });

  /// Selectable values; each must appear in [DropdownMenuItem.value].
  final List<T> items;

  /// Currently selected item, or `null` for hint-only state.
  final T? value;

  /// Notifies when the user picks another entry.
  final ValueChanged<T?>? onChanged;

  /// Builds the row shown for each [DropdownMenuItem] child.
  final Widget Function(BuildContext context, T item) labelBuilder;

  /// Shown when [value] is `null`.
  final String? hint;

  /// When `false`, the field is non-interactive.
  final bool enabled;

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

    return DropdownButtonFormField<T>(
      // Controlled selection; `value` updates when Riverpod state changes.
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      icon: Icon(Icons.expand_more_rounded, color: c.textSecondary),
      hint: hint != null
          ? Text(hint!, style: TextStyle(color: c.textSecondary))
          : null,
      items: items
          .map(
            (T e) =>
                DropdownMenuItem<T>(value: e, child: labelBuilder(context, e)),
          )
          .toList(growable: false),
      onChanged: enabled ? onChanged : null,
      style: TextStyle(color: c.textPrimary),
      dropdownColor: c.surface,
      decoration: InputDecoration(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMd,
          vertical: AppDimensions.paddingMd,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: focused,
        disabledBorder: border,
      ),
    );
  }
}
