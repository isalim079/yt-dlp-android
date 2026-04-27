/// Data model for one yt-dlp media format entry.
library;

import '../../core/constants/app_strings.dart';

/// Describes a single downloadable media format (e.g. from yt-dlp JSON).
///
/// Immutable value object with JSON deserialization for API layers.
class VideoFormat {
  /// Creates a [VideoFormat] with the given metadata.
  const VideoFormat({
    required this.formatId,
    required this.extension,
    required this.displayLabel,
    this.resolution,
    this.fps,
    this.fileSize,
    this.isAudioOnly = false,
    this.audioBitrate,
  });

  /// yt-dlp `format_id` (may be a single id or combined ids).
  final String formatId;

  /// File container / extension (e.g. `mp4`, `webm`, `m4a`).
  final String extension;

  /// Short label suitable for list tiles or dropdown entries.
  final String displayLabel;

  /// Pixel height label such as `1080p`, when applicable.
  final String? resolution;

  /// Frames per second when video; `null` if unknown or not applicable.
  final int? fps;

  /// Approximate file size in bytes; `null` if unknown.
  final int? fileSize;

  /// Whether this format is audio-only (no video stream).
  final bool isAudioOnly;

  /// Audio bitrate in kilobits per second when known.
  final double? audioBitrate;

  /// Human-readable file size (e.g. `128 MB`) or [AppStrings.fileSizeUnknown].
  String get formattedFileSize {
    if (fileSize == null) {
      return AppStrings.fileSizeUnknown;
    }
    return _formatBytes(fileSize!);
  }

  /// Builds a [VideoFormat] from a JSON map (typical yt-dlp `formats` entry).
  factory VideoFormat.fromJson(Map<String, dynamic> json) {
    final dynamic rawFps = json['fps'];
    final int? fps = rawFps is num ? rawFps.round() : null;

    final dynamic rawSize = json['filesize'] ?? json['filesize_approx'];
    final int? fileSize = rawSize is num ? rawSize.toInt() : null;

    final String vcodec = json['vcodec']?.toString() ?? '';
    final bool isAudioOnly =
        vcodec.isEmpty || vcodec == 'none' || vcodec == 'audio only';

    final int? height = json['height'] is num
        ? (json['height'] as num).toInt()
        : null;
    final String? resolution = height != null && height > 0
        ? '$height${AppStrings.formatVideoSuffix}'
        : (json['resolution']?.toString().isNotEmpty == true
              ? json['resolution']?.toString()
              : (json['format_note']?.toString().isNotEmpty == true
                    ? json['format_note']?.toString()
                    : null));

    final dynamic rawAbr = json['abr'];
    final double? audioBitrate = rawAbr is num ? rawAbr.toDouble() : null;

    final String ext = json['ext']?.toString() ?? '';
    final String extLabel = ext.isEmpty ? '' : ext.toUpperCase();
    final String sep = AppStrings.formatLabelSeparator;
    final String displayLabel = isAudioOnly
        ? '${AppStrings.formatAudioOnlyLabel} $extLabel$sep'
              '${audioBitrate != null ? '${audioBitrate.round()}kbps' : AppStrings.formatSizeUnknown}'
        : () {
            final String res = resolution?.isNotEmpty == true
                ? resolution!
                : AppStrings.formatSizeUnknown;
            final String sizePart = fileSize != null
                ? '${AppStrings.formatApproximatePrefix}'
                      '${_formatBytesShort(fileSize)}'
                : AppStrings.formatSizeUnknown;
            return '$res $extLabel$sep$sizePart';
          }();

    return VideoFormat(
      formatId: json['format_id']?.toString() ?? '',
      extension: ext,
      displayLabel: displayLabel,
      resolution: resolution,
      fps: fps,
      fileSize: fileSize,
      isAudioOnly: isAudioOnly,
      audioBitrate: audioBitrate,
    );
  }

  /// Returns a copy with any non-null argument replacing the current value.
  VideoFormat copyWith({
    String? formatId,
    String? extension,
    String? displayLabel,
    String? resolution,
    int? fps,
    int? fileSize,
    bool? isAudioOnly,
    double? audioBitrate,
  }) {
    return VideoFormat(
      formatId: formatId ?? this.formatId,
      extension: extension ?? this.extension,
      displayLabel: displayLabel ?? this.displayLabel,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      fileSize: fileSize ?? this.fileSize,
      isAudioOnly: isAudioOnly ?? this.isAudioOnly,
      audioBitrate: audioBitrate ?? this.audioBitrate,
    );
  }

  @override
  String toString() => 'VideoFormat($formatId, $displayLabel)';

  static String _formatBytesShort(int bytes) {
    const int k = 1024;
    if (bytes < k) {
      return '$bytes${AppStrings.fileSizeUnitBytes}';
    }
    final double kb = bytes / k;
    if (kb < k) {
      return '${kb.toStringAsFixed(0)}${AppStrings.fileSizeUnitKb}';
    }
    final double mb = kb / k;
    if (mb < k) {
      return '${mb.toStringAsFixed(1)}${AppStrings.fileSizeUnitMb}';
    }
    final double gb = mb / k;
    return '${gb.toStringAsFixed(1)}${AppStrings.fileSizeUnitGb}';
  }

  static String _formatBytes(int bytes) {
    const int k = 1024;
    if (bytes < k) {
      return '$bytes ${AppStrings.fileSizeUnitBytes}';
    }
    final double kb = bytes / k;
    if (kb < k) {
      return '${kb.toStringAsFixed(1)} ${AppStrings.fileSizeUnitKb}';
    }
    final double mb = kb / k;
    if (mb < k) {
      return '${mb.toStringAsFixed(1)} ${AppStrings.fileSizeUnitMb}';
    }
    final double gb = mb / k;
    return '${gb.toStringAsFixed(2)} ${AppStrings.fileSizeUnitGb}';
  }
}
