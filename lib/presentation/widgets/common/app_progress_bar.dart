/// Styled linear progress for determinate download ratios.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';

/// Thin wrapper around [LinearProgressIndicator] with clamped `0`–`1` input.
class AppProgressBar extends StatefulWidget {
  /// Creates a bar for the given completion [value].
  const AppProgressBar({
    super.key,
    required this.value,
    this.isIndeterminate = false,
    this.color,
    this.height,
  });

  /// Completion ratio between `0` and `1`.
  final double value;
  final bool isIndeterminate;

  /// Optional override for the filled segment color.
  final Color? color;

  /// Optional bar thickness; defaults to [AppDimensions.progressBarHeight].
  final double? height;

  @override
  State<AppProgressBar> createState() => _AppProgressBarState();
}

class _AppProgressBarState extends State<AppProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = Tween<double>(
      begin: 0,
      end: widget.value.clamp(0, 1).toDouble(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AppProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animation = Tween<double>(
        begin: oldWidget.value.clamp(0, 1).toDouble(),
        end: widget.value.clamp(0, 1).toDouble(),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final double h = widget.height ?? AppDimensions.progressBarHeight;
    final bool indeterminate = widget.isIndeterminate || widget.value <= 0;
    if (indeterminate) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusXs),
        child: SizedBox(
          height: h,
          child: LinearProgressIndicator(
            minHeight: h,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              widget.color ?? c.primary,
            ),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusXs),
          child: SizedBox(
            height: h,
            child: LinearProgressIndicator(
              value: _animation.value.clamp(0, 1).toDouble(),
              minHeight: h,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.color ?? c.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}
