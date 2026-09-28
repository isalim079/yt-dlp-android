/// Fast 360 start, then a background HD ladder for the quality picker.
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

/// Preferred-client extract forced to 360p. Does not start android_vr or mweb.
Future<PlaybackResolved> resolvePlaybackStart({
  required YtdlpService ytdlp,
  required String url,
  required String preferredClient,
  required bool forceRefresh,
  Duration timeout = const Duration(seconds: 90),
}) async {
  try {
    final PlaybackResolved resolved = await ytdlp
        .resolvePlayback(
          url,
          quality: PlaybackQuality.p360,
          playerClient: preferredClient,
          forceRefresh: forceRefresh,
        )
        .timeout(timeout);
    if (!resolved.isPlayable) {
      throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
    }
    return resolved;
  } on YtdlpException {
    rethrow;
  } on Object catch (error, stack) {
    AppLogger.w('resolve start via $preferredClient failed: $error\n$stack');
    throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
  }
}

/// Background HD JSON. Never meant to open the player by itself.
///
/// Tries [kPlaybackHdFallbackClient], then mweb+PO if still no height ≥ 720.
/// Returns null when nothing taller than [start] is available.
Future<PlaybackResolved?> warmPlaybackHdLadder({
  required YtdlpService ytdlp,
  required String url,
  required String preferredClient,
  required PlaybackResolved start,
  Duration timeout = const Duration(seconds: 20),
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
}) async {
  PlaybackResolved best = start;

  if (preferredClient != kPlaybackHdFallbackClient) {
    final PlaybackResolved? vr = await _fetchClient(
      ytdlp: ytdlp,
      url: url,
      quality: PlaybackQuality.auto,
      client: kPlaybackHdFallbackClient,
      forceRefresh: true,
      timeout: timeout,
    );
    if (vr != null) {
      AppLogger.i(
        'android_vr result height=${vr.height} '
        'max=${playbackMaxAvailableHeight(vr)} '
        'needsMweb=${playbackNeedsExtraClient(vr)}',
      );
      if (playbackFallbackImproves(best, vr)) {
        best = vr;
      }
    }
  }

  if (playbackNeedsExtraClient(best) && mintPoTokens != null) {
    final String? videoId = YoutubeUrls.videoId(url);
    if (videoId != null) {
      try {
        AppLogger.i('BotGuard mint then mweb for $videoId');
        final PlaybackPoToken? tokens = await mintPoTokens(videoId);
        if (tokens != null) {
          final PlaybackResolved? mweb = await _fetchClient(
            ytdlp: ytdlp,
            url: url,
            quality: PlaybackQuality.auto,
            client: kPlaybackMwebClient,
            forceRefresh: true,
            poToken: tokens.extractorValue,
            timeout: timeout,
          );
          if (mweb != null && playbackFallbackImproves(best, mweb)) {
            best = mweb;
          }
        }
      } on Object catch (error, stack) {
        AppLogger.w('resolve via mweb+PO failed: $error\n$stack');
      }
    }
  }

  if (identical(best, start) || !playbackFallbackImproves(start, best)) {
    return null;
  }
  return best;
}

Future<PlaybackResolved?> _fetchClient({
  required YtdlpService ytdlp,
  required String url,
  required PlaybackQuality quality,
  required String client,
  required bool forceRefresh,
  required Duration timeout,
  String? poToken,
}) async {
  try {
    return await ytdlp
        .resolvePlayback(
          url,
          quality: quality,
          playerClient: client,
          forceRefresh: forceRefresh,
          poToken: poToken,
        )
        .timeout(timeout);
  } on Object catch (error, stack) {
    AppLogger.w('resolve via $client failed: $error\n$stack');
    return null;
  }
}
