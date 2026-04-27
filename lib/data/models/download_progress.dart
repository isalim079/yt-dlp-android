/// Live transfer progress parsed from yt-dlp stdout.
library;

/// Live progress snapshot for an active or completed download.
class DownloadProgress {
  /// Creates a progress snapshot.
  const DownloadProgress({
    required this.percent,
    required this.speed,
    required this.eta,
    required this.totalSize,
    this.downloadedSize,
    this.isMerging = false,
  });

  /// Completion ratio from `0.0` through `1.0`.
  final double percent;

  /// Current speed string (e.g. `2.30MiB/s`).
  final String speed;

  /// ETA string (e.g. `00:32`).
  final String eta;

  /// Total size string (e.g. `128.34MiB`).
  final String totalSize;

  /// Downloaded amount label when known.
  final String? downloadedSize;

  /// Whether ffmpeg merge is in progress after raw download.
  final bool isMerging;

  /// Human-readable percent for list tiles (`45.3%`).
  String get percentLabel => '${(percent * 100).toStringAsFixed(1)}%';

  /// Neutral placeholder used before the first progress line arrives.
  static DownloadProgress get zero => const DownloadProgress(
    percent: 0,
    speed: '--',
    eta: '--',
    totalSize: '--',
  );
}
