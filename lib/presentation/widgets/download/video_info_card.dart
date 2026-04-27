/// Compact preview of a resolved [VideoInfo] row (thumbnail + metadata).
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/video_info.dart';

/// Card showing thumbnail, title, uploader, duration, and view count.
class VideoInfoCard extends StatelessWidget {
  /// Creates a card for the given [videoInfo].
  const VideoInfoCard({super.key, required this.videoInfo});

  /// Metadata displayed in the card.
  final VideoInfo videoInfo;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(AppDimensions.paddingMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Thumbnail(url: videoInfo.thumbnail),
          const SizedBox(width: AppDimensions.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  videoInfo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                _MetaRow(
                  icon: Icons.person_outline,
                  text: videoInfo.uploader ?? AppStrings.notAvailable,
                ),
                const SizedBox(height: AppDimensions.spaceXs),
                _MetaRow(
                  icon: Icons.timer_outlined,
                  text: videoInfo.formattedDuration,
                ),
                const SizedBox(height: AppDimensions.spaceXs),
                _MetaRow(
                  icon: Icons.visibility_outlined,
                  text: videoInfo.formattedViewCount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    const double w = 100;
    const double h = 68;

    if (url == null || url!.isEmpty) {
      return _thumbPlaceholder(c);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: w,
        height: h,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (BuildContext context, String _) => Container(
          width: w,
          height: h,
          color: c.border.withValues(alpha: 0.45),
        ),
        errorWidget: (BuildContext context, String _, Object _) =>
            _thumbPlaceholder(c),
      ),
    );
  }

  Widget _thumbPlaceholder(AppUiColors c) {
    return Container(
      width: 100,
      height: 68,
      decoration: BoxDecoration(
        color: c.border.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        color: c.textSecondary,
        size: AppDimensions.iconMd,
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: c.textSecondary);

    return Row(
      children: <Widget>[
        Icon(icon, size: AppDimensions.iconSm, color: c.textSecondary),
        const SizedBox(width: AppDimensions.spaceXs),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: style,
          ),
        ),
      ],
    );
  }
}
