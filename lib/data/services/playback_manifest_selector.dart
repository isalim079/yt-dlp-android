/// Selects playable streams from [PlaybackManifest] for media_kit.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/playback_manifest.dart';
import '../models/playback_resolved.dart';
import '../models/video_info.dart';

/// Priority (architecture §7): HLS live → adaptive V+A → progressive → HLS → fail.
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

    // Priority: separate video + audio (required for reliable 1080p+).
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
    final int? maxH = quality.maxHeight;
    List<VideoRepresentation> pool = all;
    if (maxH != null) {
      final List<VideoRepresentation> atOrBelow =
          all.where((VideoRepresentation v) => v.height <= maxH).toList();
      if (atOrBelow.isNotEmpty) {
        pool = atOrBelow;
      } else {
        final List<VideoRepresentation> above =
            all.where((VideoRepresentation v) => v.height > maxH).toList();
        if (above.isEmpty) {
          return null;
        }
        above.sort(
          (VideoRepresentation a, VideoRepresentation b) =>
              a.height.compareTo(b.height),
        );
        pool = <VideoRepresentation>[above.first];
      }
    }
    return _bestVideo(pool, quality);
  }

  /// Prefer H.264 ≤ 1080 for Auto; otherwise highest height + H.264 + bitrate.
  static VideoRepresentation? _bestVideo(
    List<VideoRepresentation> candidates,
    PlaybackQuality quality,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    List<VideoRepresentation> pool = candidates;
    if (quality == PlaybackQuality.auto) {
      final List<VideoRepresentation> capped = candidates
          .where((VideoRepresentation c) => c.height <= 1080)
          .toList();
      if (capped.isNotEmpty) {
        pool = capped;
      }
    }
    pool = List<VideoRepresentation>.from(pool);
    pool.sort((VideoRepresentation a, VideoRepresentation b) {
      final int codec = (b.isH264 ? 1 : 0).compareTo(a.isH264 ? 1 : 0);
      if (codec != 0) {
        return codec;
      }
      if (a.height != b.height) {
        return b.height.compareTo(a.height);
      }
      final int ext = _extScore(b.ext).compareTo(_extScore(a.ext));
      if (ext != 0) {
        return ext;
      }
      return (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    });
    return pool.first;
  }

  static int _extScore(String? ext) {
    return switch ((ext ?? '').toLowerCase()) {
      'mp4' => 2,
      'webm' => 1,
      _ => 0,
    };
  }
}
