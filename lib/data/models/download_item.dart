/// Domain models for queued download jobs and their lifecycle.
library;

import '../../core/constants/app_strings.dart';
import 'download_progress.dart';
import 'video_format.dart';

/// High-level state of a queued or active download job.
enum DownloadStatus {
  /// Waiting to start.
  queued,

  /// Transfer in progress.
  downloading,

  /// Finished successfully.
  completed,

  /// Stopped with an error.
  failed,
}

/// Represents one user-initiated download (single URL or playlist entry).
class DownloadItem {
  /// Creates a [DownloadItem].
  DownloadItem({
    required this.id,
    required this.url,
    required this.title,
    required this.selectedFormat,
    required this.outputPath,
    required this.status,
    required this.addedAt,
    this.progress,
    this.errorMessage,
    this.isPlaylist = false,
    this.playlistIndex,
    this.playlistTotal,
    this.thumbnailUrl,
    this.playlistGroupId,
    this.playlistTitle,
    this.isPlayed = false,
  });

  /// Stable identifier for list diffing and cancellation.
  final String id;

  /// Source media URL.
  final String url;

  /// Resolved title when metadata is available.
  final String title;

  /// User-selected [VideoFormat].
  final VideoFormat selectedFormat;

  /// Destination directory on disk.
  final String outputPath;

  /// Current lifecycle state.
  DownloadStatus status;

  /// Fine-grained progress when [status] is [DownloadStatus.downloading].
  DownloadProgress? progress;

  /// Human-readable failure reason when [status] is [DownloadStatus.failed].
  String? errorMessage;

  /// Whether this job is part of a playlist batch.
  final bool isPlaylist;

  /// One-based index within the playlist batch, when [isPlaylist] is true.
  final int? playlistIndex;

  /// Total videos in the playlist batch, when [isPlaylist] is true.
  final int? playlistTotal;

  /// Optional thumbnail for list UI.
  final String? thumbnailUrl;

  /// Optional logical playlist grouping id for grouped UI.
  final String? playlistGroupId;

  /// Optional display title of the playlist group.
  final String? playlistTitle;

  /// Whether user has already played this completed file.
  bool isPlayed;

  /// When the item was added to the queue.
  final DateTime addedAt;

  /// Short label for chips and accessibility.
  String get statusLabel {
    return switch (status) {
      DownloadStatus.queued => AppStrings.statusQueued,
      DownloadStatus.downloading => AppStrings.statusDownloading,
      DownloadStatus.completed => AppStrings.statusCompleted,
      DownloadStatus.failed => AppStrings.statusFailed,
    };
  }

  /// Whether the user can cancel this job while it is pending or active.
  bool get isCancellable =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;
}
