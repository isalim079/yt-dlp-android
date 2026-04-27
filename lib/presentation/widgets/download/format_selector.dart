/// Dropdown and summary for choosing a [VideoFormat] before download.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../data/models/video_format.dart';
import '../../../data/providers/ytdlp_providers.dart';
import '../common/app_dropdown.dart';

/// Quality selector wired to [selectedFormatProvider].
class FormatSelector extends ConsumerWidget {
  /// Creates a selector for the given [formats] list.
  const FormatSelector({super.key, required this.formats});

  /// Non-empty formats returned by yt-dlp.
  final List<VideoFormat> formats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final VideoFormat? selected = ref.watch(selectedFormatProvider);

    VideoFormat? dropdownValue = selected;
    if (dropdownValue != null) {
      final int idx = formats.indexWhere(
        (VideoFormat f) => f.formatId == dropdownValue!.formatId,
      );
      dropdownValue = idx >= 0 ? formats[idx] : null;
    }

    final VideoFormat? summary = dropdownValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          AppStrings.selectFormat,
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        AppDropdown<VideoFormat>(
          items: formats,
          value: dropdownValue,
          onChanged: (VideoFormat? next) {
            ref.read(selectedFormatProvider.notifier).state = next;
          },
          labelBuilder: (BuildContext ctx, VideoFormat f) {
            final TextStyle? mainStyle = Theme.of(
              ctx,
            ).textTheme.bodyMedium?.copyWith(color: c.textPrimary);
            final String res = (f.resolution?.isNotEmpty ?? false)
                ? f.resolution!
                : AppStrings.notAvailable;
            final String ext = f.extension.isNotEmpty
                ? f.extension.toUpperCase()
                : AppStrings.notAvailable;
            final String label =
                '${f.displayLabel}${AppStrings.formatLabelSeparator}$res · $ext';

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  f.isAudioOnly
                      ? Icons.audiotrack_outlined
                      : Icons.videocam_outlined,
                  color: f.isAudioOnly ? c.secondary : c.primary,
                  size: AppDimensions.iconMd,
                ),
                const SizedBox(width: AppDimensions.spaceSm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: mainStyle,
                  ),
                ),
              ],
            );
          },
        ),
        if (summary != null) ...<Widget>[
          const SizedBox(height: AppDimensions.spaceMd),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spaceMd,
              vertical: AppDimensions.spaceSm,
            ),
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    () {
                      final String resChip =
                          (summary.resolution?.isNotEmpty ?? false)
                          ? summary.resolution!
                          : AppStrings.notAvailable;
                      final String extChip = summary.extension.isNotEmpty
                          ? summary.extension.toUpperCase()
                          : '';
                      final String mid = extChip.isEmpty
                          ? resChip
                          : '$resChip $extChip';
                      return '${AppStrings.formatSelectedPrefix}'
                          '$mid'
                          '${AppStrings.formatLabelSeparator}'
                          '${summary.formattedFileSize}'
                          '${AppStrings.formatSelectedSuffix}';
                    }(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: c.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
