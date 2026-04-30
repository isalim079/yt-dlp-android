/// Primary and outlined buttons with optional loading and icons.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';

/// Full-width action button with loading and disabled states.
class AppButton extends StatefulWidget {
  /// Creates a button with the given [label].
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width = double.infinity,
    this.outlined = false,
  });

  /// Visible label (use [AppStrings] at call sites).
  final String label;

  /// Tap handler; `null` renders a disabled button.
  final VoidCallback? onPressed;

  /// When `true`, shows an indeterminate progress indicator.
  final bool isLoading;

  /// Optional leading icon.
  final Widget? icon;

  /// Minimum width of the button.
  final double width;

  /// When `true`, uses an outlined style instead of filled primary.
  final bool outlined;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final bool disabled = widget.onPressed == null || widget.isLoading;
    final BorderRadius radius = BorderRadius.circular(AppDimensions.radiusMd);
    final OutlinedBorder shape = RoundedRectangleBorder(borderRadius: radius);
    final Color contentColor = widget.outlined
        ? (disabled && !widget.isLoading ? c.textSecondary : c.primary)
        : (disabled && !widget.isLoading ? c.textSecondary : c.onPrimary);

    final Widget progress = SizedBox(
      height: AppDimensions.iconMd,
      width: AppDimensions.iconMd,
      child: CircularProgressIndicator.adaptive(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(contentColor),
      ),
    );

    final Widget labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          IconTheme(
            data: IconThemeData(
              size: AppDimensions.iconMd,
              color: contentColor,
            ),
            child: widget.icon!,
          ),
          const SizedBox(width: AppDimensions.spaceSm),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: contentColor,
            ),
          ),
        ),
      ],
    );

    final Widget child = widget.isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              progress,
              const SizedBox(width: AppDimensions.spaceSm),
              Text(
                widget.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: contentColor,
                ),
              ),
            ],
          )
        : labelRow;

    final Widget button;
    if (widget.outlined) {
      button = SizedBox(
        width: widget.width,
        height: AppDimensions.buttonHeight,
        child: OutlinedButton(
          onPressed: widget.isLoading ? () {} : (widget.onPressed == null ? null : widget.onPressed),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(widget.width, AppDimensions.buttonHeight),
            maximumSize: Size(widget.width, AppDimensions.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(
              color: widget.onPressed == null && !widget.isLoading ? c.border : c.primary,
            ),
            backgroundColor: widget.onPressed == null && !widget.isLoading
                ? c.surface
                : Colors.transparent,
            foregroundColor: widget.onPressed == null && !widget.isLoading
                ? c.textSecondary
                : c.primary,
            shape: shape,
          ),
          child: child,
        ),
      );
    } else {
      button = SizedBox(
        width: widget.width,
        height: AppDimensions.buttonHeight,
        child: ElevatedButton(
          onPressed: widget.isLoading ? () {} : (widget.onPressed == null ? null : widget.onPressed),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            minimumSize: Size(widget.width, AppDimensions.buttonHeight),
            maximumSize: Size(widget.width, AppDimensions.buttonHeight),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: widget.onPressed == null && !widget.isLoading
                ? c.border.withValues(alpha: 0.4)
                : c.primary,
            foregroundColor: widget.onPressed == null && !widget.isLoading
                ? c.textSecondary
                : c.onPrimary,
            disabledBackgroundColor: c.border.withValues(alpha: 0.35),
            disabledForegroundColor: c.textSecondary,
            shape: shape,
          ),
          child: child,
        ),
      );
    }

    return Listener(
      onPointerDown: (_) {
        if (!disabled) {
          setState(() => _scale = 0.97);
        }
      },
      onPointerUp: (_) => setState(() => _scale = 1),
      onPointerCancel: (_) => setState(() => _scale = 1),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 80),
        child: button,
      ),
    );
  }
}
