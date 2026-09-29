/// Server-primary playback resolve with classified local yt-dlp fallback.
library;

import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_manifest.dart';
import '../models/playback_resolved.dart';
import 'api/api_exception.dart';
import 'api/playback_api_repository.dart';
import 'playback_hd_fallback.dart';
import 'playback_manifest_selector.dart';
import 'playback_po_token.dart';
import 'ytdlp_service.dart';

/// Result of a routed resolve (includes source for debugging/UI).
class RoutedPlayback {
  /// Creates a routed result.
  const RoutedPlayback({
    required this.resolved,
    required this.fromServer,
    this.qualityFallback = false,
    this.selectedQualityLabel,
  });

  /// Streams ready for media_kit.
  final PlaybackResolved resolved;

  /// True when the production API supplied the manifest.
  final bool fromServer;

  /// Server selected lower than requested.
  final bool qualityFallback;

  /// Server selected quality label when known.
  final String? selectedQualityLabel;
}

/// Chooses server vs local extraction using failure classification.
class PlaybackSourceRouter {
  /// Creates the router.
  PlaybackSourceRouter({
    required this.ytdlp,
    required this.preferServer,
    required this.apiBaseUrl,
    this.apiRepository,
  });

  /// Local yt-dlp service (offline path).
  final YtdlpService ytdlp;

  /// When true and [apiBaseUrl] is set, try server first.
  final bool preferServer;

  /// Playback API origin (empty disables server path).
  final String apiBaseUrl;

  /// Optional prebuilt repository (tests).
  final PlaybackApiRepository? apiRepository;

  /// Resolve start streams (progressive-friendly).
  Future<RoutedPlayback> resolveStart({
    required String url,
    bool forceRefresh = false,
  }) async {
    return resolve(
      url: url,
      quality: PlaybackQuality.p360,
      forceRefresh: forceRefresh,
      preferProgressiveStart: true,
    );
  }

  /// Resolve for [quality].
  Future<RoutedPlayback> resolve({
    required String url,
    PlaybackQuality quality = PlaybackQuality.auto,
    bool forceRefresh = false,
    bool preferProgressiveStart = false,
  }) async {
    final String? videoId = YoutubeUrls.videoId(url);
    if (preferServer &&
        apiBaseUrl.trim().isNotEmpty &&
        videoId != null &&
        videoId.isNotEmpty &&
        apiRepository != null) {
      try {
        final PlaybackManifest manifest = await apiRepository!.fetchPlayback(
          videoId: videoId,
          quality: preferProgressiveStart ? PlaybackQuality.p360 : quality,
          forceRefresh: forceRefresh,
        );
        if (!manifest.isPlayable) {
          throw ApiException(
            code: 'EXTRACTOR_NO_STREAM',
            message: 'Server returned empty streams',
            kind: ApiFailureKind.transport,
            retryable: true,
          );
        }
        final PlaybackResolved resolved = PlaybackManifestSelector.select(
          manifest,
          quality: preferProgressiveStart ? PlaybackQuality.p360 : quality,
        );
        AppLogger.i(
          'playback source=server videoId=$videoId '
          'mode=${resolved.mode.name} height=${resolved.height} '
          'fallback=${manifest.quality?.qualityFallback}',
        );
        return RoutedPlayback(
          resolved: resolved,
          fromServer: true,
          qualityFallback: manifest.quality?.qualityFallback ?? false,
          selectedQualityLabel: manifest.quality?.selectedQuality,
        );
      } on ApiException catch (e) {
        AppLogger.w('server playback failed: ${e.code} ${e.message}');
        if (!e.allowsLocalFallback) {
          throw YtdlpException(e.message);
        }
        // fall through to local
      } on Object catch (e) {
        AppLogger.w('server playback transport error: $e');
        // fall through to local
      }
    }

    final PlaybackResolved local = preferProgressiveStart
        ? await resolvePlaybackStart(
            ytdlp: ytdlp,
            url: url,
            forceRefresh: forceRefresh,
            mintPoTokens: PlaybackPoTokenService.mint,
          )
        : await ytdlp.resolvePlayback(
            url,
            quality: quality,
            forceRefresh: forceRefresh,
          );
    AppLogger.i(
      'playback source=local mode=${local.mode.name} height=${local.height}',
    );
    return RoutedPlayback(resolved: local, fromServer: false);
  }

  /// Warm HD ladder — server Auto/1080 first, else local warm.
  Future<RoutedPlayback?> warmHd({
    required String url,
    required PlaybackResolved start,
  }) async {
    final String? videoId = YoutubeUrls.videoId(url);
    if (preferServer &&
        apiBaseUrl.trim().isNotEmpty &&
        videoId != null &&
        videoId.isNotEmpty &&
        apiRepository != null) {
      try {
        final PlaybackManifest manifest = await apiRepository!.fetchPlayback(
          videoId: videoId,
          quality: PlaybackQuality.auto,
        );
        final PlaybackResolved resolved = PlaybackManifestSelector.select(
          manifest,
          quality: PlaybackQuality.auto,
        );
        if ((resolved.height ?? 0) <= (start.height ?? 0) &&
            resolved.mode == start.mode) {
          return null;
        }
        return RoutedPlayback(
          resolved: resolved,
          fromServer: true,
          qualityFallback: manifest.quality?.qualityFallback ?? false,
          selectedQualityLabel: manifest.quality?.selectedQuality,
        );
      } on ApiException catch (e) {
        if (!e.allowsLocalFallback) {
          return null;
        }
      } on Object {
        // local warm below
      }
    }
    final PlaybackResolved? hd = await warmPlaybackHdLadder(
      ytdlp: ytdlp,
      url: url,
      preferredClient: 'android',
      start: start,
      mintPoTokens: PlaybackPoTokenService.mint,
    );
    if (hd == null) {
      return null;
    }
    return RoutedPlayback(resolved: hd, fromServer: false);
  }
}
