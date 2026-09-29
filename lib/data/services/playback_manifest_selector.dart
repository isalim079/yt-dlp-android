/// Selects playable streams from [PlaybackManifest] for media_kit.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/playback_manifest.dart';
import '../models/playback_resolved.dart';
import '../models/video_info.dart';

/// Priority: adaptive V+A for HD → progressive low → HLS → fail.
abstract final class PlaybackManifestSelector {
  /// Picks streams for [quality] and returns the legacy [PlaybackResolved]
  /// shape used by [PlayerController] / media_kit.
  static PlaybackResolved select(
    PlaybackManifest manifest, {
    PlaybackQuality quality = PlaybackQuality.auto,
  }) {
    final VideoInfo info = VideoInfo(
      title: manifest.title,
      thumbnail: manifest.thumbnail,
      duration: manifest.durationMs != null
          ? manifest.durationMs! ~/ 1000
          : null,
      uploader: manifest.uploader,
      url: manifest.webpageUrl ??
          'https://www.youtube.com/watch?v=${manifest.videoId}',
    );

    final List<int> heights = manifest.availableHeights;
    final String? hls = manifest.delivery.type == PlaybackDeliveryType.hls
        ? manifest.delivery.manifestUrl
        : null;

    if (manifest.delivery.type == PlaybackDeliveryType.hls &&
        manifest.delivery.manifestUrl != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.hls,
        headers: manifest.headers,
        quality: quality,
        hlsUrl: manifest.delivery.manifestUrl,
        progressiveUrl: _pickProgressive(manifest, quality)?.url,
        expiresAt: manifest.expiresAt,
        formatId: 'hls',
        availableHeights: heights,
      );
    }

    final VideoRepresentation? progressive =
        _pickProgressive(manifest, quality);
    final VideoRepresentation? video = _pickAdaptiveVideo(manifest, quality);
    final AudioRepresentation? audio = _pickAudio(manifest);

    // Prefer muxed progressive for explicit low quality (faster first frame).
    if (progressive != null &&
        (quality == PlaybackQuality.p360 || quality == PlaybackQuality.p480) &&
        progressive.height <= (quality.maxHeight ?? progressive.height)) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.progressive,
        headers: manifest.headers,
        quality: quality,
        progressiveUrl: progressive.url,
        hlsUrl: hls,
        height: progressive.height,
        expiresAt: manifest.expiresAt,
        formatId: progressive.id,
        availableHeights: heights,
      );
    }

    // Priority: separate video + audio (required for reliable 720p+).
    if (video != null && audio != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.adaptive,
        headers: manifest.headers,
        quality: quality,
        videoUrl: video.url,
        audioUrl: audio.url,
        progressiveUrl: progressive?.url,
        hlsUrl: hls,
        height: video.height,
        expiresAt: manifest.expiresAt,
        formatId: video.id,
        availableHeights: heights,
      );
    }

    if (progressive != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.progressive,
        headers: manifest.headers,
        quality: quality,
        progressiveUrl: progressive.url,
        hlsUrl: hls,
        height: progressive.height,
        expiresAt: manifest.expiresAt,
        formatId: progressive.id,
        availableHeights: heights,
      );
    }

    if (manifest.delivery.manifestUrl != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.hls,
        headers: manifest.headers,
        quality: quality,
        hlsUrl: manifest.delivery.manifestUrl,
        expiresAt: manifest.expiresAt,
        formatId: 'hls',
        availableHeights: heights,
      );
    }

    throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
  }

  static VideoRepresentation? _pickAdaptiveVideo(
    PlaybackManifest manifest,
    PlaybackQuality quality,
  ) {
    return _selectVideo(manifest.adaptiveVideo, quality);
  }

  static VideoRepresentation? _pickProgressive(
    PlaybackManifest manifest,
    PlaybackQuality quality,
  ) {
    return _selectVideo(manifest.progressiveVideo, quality);
  }

  static AudioRepresentation? _pickAudio(PlaybackManifest manifest) {
    if (manifest.audioStreams.isEmpty) {
      return null;
    }
    final List<AudioRepresentation> sorted =
        List<AudioRepresentation>.from(manifest.audioStreams);
    sorted.sort((AudioRepresentation a, AudioRepresentation b) {
      final int pref = (b.prefersMp4a ? 1 : 0).compareTo(a.prefersMp4a ? 1 : 0);
      if (pref != 0) {
        return pref;
      }
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return sorted.first;
  }

  static VideoRepresentation? _selectVideo(
    List<VideoRepresentation> all,
    PlaybackQuality quality,
  ) {
    if (all.isEmpty) {
      return null;
    }
    final int? targetH = quality.maxHeight;
    List<VideoRepresentation> pool = all;
    if (targetH != null) {
      // Prefer at-or-above target (closest), else highest below.
      final List<VideoRepresentation> atOrAbove =
          all.where((VideoRepresentation v) => v.height >= targetH).toList();
      if (atOrAbove.isNotEmpty) {
        atOrAbove.sort(
          (VideoRepresentation a, VideoRepresentation b) =>
              a.height.compareTo(b.height),
        );
        final int bestH = atOrAbove.first.height;
        pool = atOrAbove
            .where((VideoRepresentation v) => v.height == bestH)
            .toList();
      } else {
        final List<VideoRepresentation> below =
            all.where((VideoRepresentation v) => v.height < targetH).toList();
        if (below.isEmpty) {
          return null;
        }
        below.sort(
          (VideoRepresentation a, VideoRepresentation b) =>
              b.height.compareTo(a.height),
        );
        pool = <VideoRepresentation>[below.first];
      }
    }
    return _bestVideo(pool, quality);
  }

  /// AUTO = highest compatible. Mild H.264 preference below 1440; VP9/AV1 OK above.
  static VideoRepresentation? _bestVideo(
    List<VideoRepresentation> candidates,
    PlaybackQuality quality,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    final List<VideoRepresentation> pool =
        List<VideoRepresentation>.from(candidates);
    final int targetHint = quality.maxHeight ?? 0;
    final bool hiRes = quality == PlaybackQuality.auto || targetHint >= 1440;
    pool.sort((VideoRepresentation a, VideoRepresentation b) {
      if (a.height != b.height) {
        return b.height.compareTo(a.height);
      }
      final int codec = _codecScore(b, hiRes).compareTo(_codecScore(a, hiRes));
      if (codec != 0) {
        return codec;
      }
      final int ext = _extScore(b.ext).compareTo(_extScore(a.ext));
      if (ext != 0) {
        return ext;
      }
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return pool.first;
  }

  static int _codecScore(VideoRepresentation v, bool hiRes) {
    final String c = (v.codec ?? '').toLowerCase();
    final bool h264 = c.contains('avc') || c.contains('h264');
    final bool vp9 = c.contains('vp9');
    final bool av1 = c.contains('av01');
    if (hiRes) {
      if (av1 || vp9) {
        return 3;
      }
      if (h264) {
        return 2;
      }
      return 1;
    }
    if (h264) {
      return 3;
    }
    if (vp9) {
      return 2;
    }
    if (av1) {
      return 1;
    }
    return 0;
  }

  static int _extScore(String? ext) {
    return switch ((ext ?? '').toLowerCase()) {
      'mp4' => 2,
      'webm' => 1,
      _ => 0,
    };
  }
}
