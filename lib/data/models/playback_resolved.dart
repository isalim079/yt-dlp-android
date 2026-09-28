/// Resolved googlevideo / HLS URLs for in-app playback.
library;

import 'video_info.dart';

/// How the player should open streams.
enum PlaybackMode {
  /// Separate video + audio adaptive tracks.
  adaptive,

  /// Single muxed progressive file (lower quality, more reliable).
  progressive,

  /// HLS livestream or SABR fallback.
  hls,
}

/// In-player quality ladder (Auto picks the highest available).
enum PlaybackQuality {
  auto,
  p1080,
  p720,
  p480,
  p360;

  /// Picker label.
  String get label => switch (this) {
    PlaybackQuality.auto => 'Auto',
    PlaybackQuality.p1080 => '1080p',
    PlaybackQuality.p720 => '720p',
    PlaybackQuality.p480 => '480p',
    PlaybackQuality.p360 => '360p',
  };

  /// Maximum video height, or `null` for unlimited (Auto).
  int? get maxHeight => switch (this) {
    PlaybackQuality.auto => null,
    PlaybackQuality.p1080 => 1080,
    PlaybackQuality.p720 => 720,
    PlaybackQuality.p480 => 480,
    PlaybackQuality.p360 => 360,
  };
}

/// Playable URLs plus headers and expiry from a yt-dlp `-J` payload.
class PlaybackResolved {
  /// Creates a resolved playback bundle.
  const PlaybackResolved({
    required this.info,
    required this.mode,
    required this.headers,
    required this.quality,
    this.videoUrl,
    this.audioUrl,
    this.progressiveUrl,
    this.hlsUrl,
    this.height,
    this.expiresAt,
    this.formatId,
  });

  /// Video metadata from the same JSON.
  final VideoInfo info;

  /// Preferred open strategy.
  final PlaybackMode mode;

  /// HTTP headers that must be sent with CDN requests.
  final Map<String, String> headers;

  /// Quality that was requested when resolving.
  final PlaybackQuality quality;

  /// Video-only adaptive URL.
  final String? videoUrl;

  /// Audio-only adaptive URL.
  final String? audioUrl;

  /// Muxed progressive fallback.
  final String? progressiveUrl;

  /// HLS manifest when adaptive/progressive are missing.
  final String? hlsUrl;

  /// Selected video height when known.
  final int? height;

  /// CDN expiry; refresh before this time.
  final DateTime? expiresAt;

  /// yt-dlp format id for the video (or progressive) track.
  final String? formatId;

  /// Primary media URL the player should open first.
  String get primaryUrl {
    switch (mode) {
      case PlaybackMode.adaptive:
        return videoUrl ?? progressiveUrl ?? hlsUrl ?? '';
      case PlaybackMode.progressive:
        return progressiveUrl ?? videoUrl ?? hlsUrl ?? '';
      case PlaybackMode.hls:
        return hlsUrl ?? progressiveUrl ?? videoUrl ?? '';
    }
  }

  /// Whether this bundle can be handed to a player.
  bool get isPlayable => primaryUrl.isNotEmpty;

  /// Whether the CDN URL should be considered stale.
  bool get isExpired {
    if (expiresAt == null) {
      return false;
    }
    return DateTime.now().isAfter(
      expiresAt!.subtract(const Duration(minutes: 5)),
    );
  }

  /// Adaptive audio companion when [mode] is adaptive.
  bool get hasSeparateAudio =>
      mode == PlaybackMode.adaptive &&
      audioUrl != null &&
      audioUrl!.isNotEmpty;
}
