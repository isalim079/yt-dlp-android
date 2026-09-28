/// Shared thumbnail + title tile for browse / history / search.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/models/browse_video.dart';

/// Tappable video row/card.
class BrowseVideoTile extends StatelessWidget {
  /// Creates a tile.
  const BrowseVideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.compact = false,
  });

  /// Item to display.
  final BrowseVideo video;

  /// Open / play handler.
  final VoidCallback onTap;

  /// Horizontal compact card for Continue watching.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactCard(video: video, onTap: onTap);
    }
    final AppUiColors c = AppColors.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingMd,
          vertical: AppDimensions.spaceSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Thumb(url: video.thumbnail, duration: video.formattedDuration),
            const SizedBox(width: AppDimensions.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title.isEmpty ? AppStrings.notAvailable : video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceXs),
                  Text(
                    video.uploader ?? AppStrings.notAvailable,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.video, required this.onTap});

  final BrowseVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return SizedBox(
      width: 180,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              child: _Thumb(
                url: video.thumbnail,
                duration: video.formattedDuration,
                width: 180,
                height: 100,
              ),
            ),
            const SizedBox(height: AppDimensions.spaceXs),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    this.url,
    required this.duration,
    this.width = 140,
    this.height = 80,
  });

  final String? url;
  final String duration;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            child: url == null || url!.isEmpty
                ? ColoredBox(
                    color: c.border,
                    child: Icon(Icons.play_circle_outline, color: c.textSecondary),
                  )
                : CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => ColoredBox(
                      color: c.border,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
          ),
          if (duration != AppStrings.notAvailable)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  duration,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
