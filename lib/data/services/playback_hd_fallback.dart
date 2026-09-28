/// One extra YouTube client when the preferred JSON has no playable HD.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_po_token.dart';
import '../models/playback_resolved.dart';
import 'ytdlp_service.dart';

/// Client that still returns direct HTTPS adaptive URLs for many SABR videos.
const String kPlaybackHdFallbackClient = 'android_vr,web';

/// Web client used with minted BotGuard PO tokens.
const String kPlaybackMwebClient = 'mweb';

/// Resolves playback, then tries Android VR, then mweb+PO tokens if HD is missing.
Future<PlaybackResolved> resolvePlaybackWithHdFallback({
  required YtdlpService ytdlp,
  required String url,
  required PlaybackQuality quality,
  required String preferredClient,
  required bool forceRefresh,
  Duration preferredTimeout = const Duration(seconds: 90),
  Duration fallbackTimeout = const Duration(seconds: 20),
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
}) async {
  PlaybackResolved? best;
  try {
    best = await ytdlp
        .resolvePlayback(
          url,
          quality: quality,
          playerClient: preferredClient,
          forceRefresh: forceRefresh,
        )
        .timeout(preferredTimeout);
    if (!playbackNeedsExtraClient(best)) {
      return best;
    }
    AppLogger.w(
      'playback JSON has no HD URLs (height=${best.height}); '
      'trying $kPlaybackHdFallbackClient',
    );
  } on Object catch (error, stack) {
    AppLogger.w('resolve via $preferredClient failed: $error\n$stack');
  }

  if (preferredClient != kPlaybackHdFallbackClient) {
    try {
      final PlaybackResolved fallback = await ytdlp
          .resolvePlayback(
            url,
            quality: quality,
            playerClient: kPlaybackHdFallbackClient,
            forceRefresh: true,
          )
          .timeout(fallbackTimeout);
      PlaybackResolved chosen = best ?? fallback;
      if (playbackFallbackImproves(chosen, fallback)) {
        chosen = fallback;
      }
      best = chosen;
      if (!playbackNeedsExtraClient(chosen)) {
        return chosen;
      }
    } on Object catch (error, stack) {
      AppLogger.w(
        'resolve via $kPlaybackHdFallbackClient failed: $error\n$stack',
      );
    }
  }

  if ((best == null || playbackNeedsExtraClient(best)) &&
      mintPoTokens != null) {
    final String? videoId = YoutubeUrls.videoId(url);
    if (videoId != null) {
      try {
        AppLogger.i('BotGuard mint then mweb for $videoId');
        final PlaybackPoToken? tokens = await mintPoTokens(videoId);
        if (tokens != null) {
          final PlaybackResolved mweb = await ytdlp
              .resolvePlayback(
                url,
                quality: quality,
                playerClient: kPlaybackMwebClient,
                forceRefresh: true,
                poToken: tokens.extractorValue,
              )
              .timeout(fallbackTimeout);
          if (best == null || playbackFallbackImproves(best, mweb)) {
            return mweb;
          }
        }
      } on Object catch (error, stack) {
        AppLogger.w('resolve via mweb+PO failed: $error\n$stack');
      }
    }
  }

  if (best != null) {
    return best;
  }
  throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
}
