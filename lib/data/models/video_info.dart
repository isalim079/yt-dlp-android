/// Basic metadata for a single video from yt-dlp `-J` JSON.
library;

import '../../core/constants/app_strings.dart';

/// Metadata fields shown before a download starts.
class VideoInfo {
  /// Creates a [VideoInfo] value.
  const VideoInfo({
    required this.title,
    required this.url,
    this.thumbnail,
    this.duration,
    this.uploader,
    this.uploadDate,
    this.viewCount,
  });

  /// Video title.
  final String title;

  /// Canonical watch URL for the item.
  final String url;

  /// Best thumbnail URL when provided by yt-dlp.
  final String? thumbnail;

  /// Duration in whole seconds, when known.
  final int? duration;

  /// Channel or uploader display name.
  final String? uploader;

  /// Raw `upload_date` field (`YYYYMMDD`) from yt-dlp.
  final String? uploadDate;

  /// View count when exposed by the extractor.
  final int? viewCount;

  /// Duration as `HH:MM:SS` or `MM:SS`.
  String get formattedDuration {
    if (duration == null) {
      return AppStrings.notAvailable;
    }
    final int total = duration!;
    final int hours = total ~/ 3600;
    final int minutes = (total % 3600) ~/ 60;
    final int seconds = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }

  /// Upload date as `YYYY-MM-DD` when [uploadDate] is valid `YYYYMMDD`.
  String get formattedUploadDate {
    if (uploadDate == null || uploadDate!.length != 8) {
      return AppStrings.notAvailable;
    }
    final String y = uploadDate!.substring(0, 4);
    final String m = uploadDate!.substring(4, 6);
    final String d = uploadDate!.substring(6, 8);
    return '$y-$m-$d';
  }

  /// Compact view count such as `1.2M` plus a localized suffix.
  String get formattedViewCount {
    if (viewCount == null) {
      return AppStrings.notAvailable;
    }
    final int n = viewCount!;
    if (n < 1000) {
      return '$n${AppStrings.viewCountSuffix}';
    }
    if (n < 1000000) {
      final double k = n / 1000;
      return '${k.toStringAsFixed(1)}${AppStrings.viewCountThousandSuffix}'
          '${AppStrings.viewCountSuffix}';
    }
    if (n < 1000000000) {
      final double m = n / 1000000;
      return '${m.toStringAsFixed(1)}${AppStrings.viewCountMillionSuffix}'
          '${AppStrings.viewCountSuffix}';
    }
    final double b = n / 1000000000;
    return '${b.toStringAsFixed(2)}${AppStrings.viewCountBillionSuffix}'
        '${AppStrings.viewCountSuffix}';
  }
}
