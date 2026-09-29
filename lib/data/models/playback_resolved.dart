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

/// In-player quality ladder (Auto picks the highest available H.264 ≤ 1080).
enum PlaybackQuality {
  auto,
  p2160,
  p1440,
  p1080,
  p720,
  p480,
  p360;

  /// Picker label.
  String get label => switch (this) {
    PlaybackQuality.auto => 'Auto',
    PlaybackQuality.p2160 => '2160p',
    PlaybackQuality.p1440 => '1440p',
    PlaybackQuality.p1080 => '1080p',
    PlaybackQuality.p720 => '720p',
    PlaybackQuality.p480 => '480p',
    PlaybackQuality.p360 => '360p',
  };

  /// Maximum video height, or `null` for unlimited (Auto).
  int? get maxHeight => switch (this) {
    PlaybackQuality.auto => null,
    PlaybackQuality.p2160 => 2160,
    PlaybackQuality.p1440 => 1440,
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
    this.availableHeights = const <int>[],
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

  /// Distinct video heights in the JSON that have a direct HTTP URL.
  final List<int> availableHeights;

  /// Copy with overrides. Pass empty [progressiveUrl] to clear.
  PlaybackResolved copyWith({
    String? progressiveUrl,
    bool clearProgressive = false,
  }) {
    return PlaybackResolved(
      info: info,
      mode: mode,
      headers: headers,
      quality: quality,
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      progressiveUrl:
          clearProgressive ? null : (progressiveUrl ?? this.progressiveUrl),
      hlsUrl: hlsUrl,
      height: height,
      expiresAt: expiresAt,
      formatId: formatId,
      availableHeights: availableHeights,
    );
  }

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

  /// Whether [quality] should appear in the in-player picker.
  bool offersQuality(PlaybackQuality quality) {
    if (quality == PlaybackQuality.auto) {
      return true;
    }
    final int? maxH = quality.maxHeight;
    if (maxH == null) {
      return true;
    }
    final int minH = switch (quality) {
      PlaybackQuality.p2160 => 1441,
      PlaybackQuality.p1440 => 1081,
      PlaybackQuality.p1080 => 721,
      PlaybackQuality.p720 => 481,
      PlaybackQuality.p480 => 361,
      PlaybackQuality.p360 => 1,
      PlaybackQuality.auto => 0,
    };
    return availableHeights.any((int h) => h >= minH && h <= maxH);
  }
}

/// True when the user asked for HD+ but yt-dlp only returned ~360p.
bool playbackHeightTooLow(PlaybackResolved resolved, PlaybackQuality quality) {
  final int got = resolved.height ?? 0;
  if (got <= 0) {
    return false;
  }
  if (quality == PlaybackQuality.auto) {
    return got <= 360;
  }
  final int want = quality.maxHeight ?? 0;
  if (want < 720) {
    return false;
  }
  return got <= 360;
}

/// Extra extractor client only when the JSON has no HD HTTP URLs at all.
bool playbackNeedsExtraClient(PlaybackResolved resolved) {
  return !resolved.availableHeights.any((int height) => height >= 720);
}

/// Highest playable video height from HTTPS formats, else [PlaybackResolved.height].
int playbackMaxAvailableHeight(PlaybackResolved resolved) {
  if (resolved.availableHeights.isEmpty) {
    return resolved.height ?? 0;
  }
  return resolved.availableHeights.reduce(
    (int a, int b) => a > b ? a : b,
  );
}

/// True when [fallback] exposes a taller playable ladder than [preferred].
bool playbackFallbackImproves(
  PlaybackResolved preferred,
  PlaybackResolved fallback,
) {
  return playbackMaxAvailableHeight(fallback) >
      playbackMaxAvailableHeight(preferred);
}
