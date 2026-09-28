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

/// Called as soon as any playable result exists, then again if a taller ladder
/// arrives. Used to start playback before slower HD clients finish.
typedef PlaybackPlayableCallback = void Function(PlaybackResolved resolved);

/// Resolves playback, racing the preferred client with Android VR.
///
/// [onPlayable] is invoked immediately when the first stream is ready, then
/// again if a later client exposes a taller HTTPS ladder. mweb+PO runs only
/// if neither client has HD.
Future<PlaybackResolved> resolvePlaybackWithHdFallback({
  required YtdlpService ytdlp,
  required String url,
  required PlaybackQuality quality,
  required String preferredClient,
  required bool forceRefresh,
  Duration preferredTimeout = const Duration(seconds: 90),
  Duration fallbackTimeout = const Duration(seconds: 20),
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
  PlaybackPlayableCallback? onPlayable,
}) async {
  PlaybackResolved? best;

  void consider(PlaybackResolved next) {
    if (best == null || playbackFallbackImproves(best!, next)) {
      best = next;
      onPlayable?.call(next);
    }
  }

  Future<PlaybackResolved?> fetchClient(
    String client, {
    required bool force,
    String? poToken,
    required Duration timeout,
  }) async {
    try {
      return await ytdlp
          .resolvePlayback(
            url,
            quality: quality,
            playerClient: client,
            forceRefresh: force,
            poToken: poToken,
          )
          .timeout(timeout);
    } on Object catch (error, stack) {
      AppLogger.w('resolve via $client failed: $error\n$stack');
      return null;
    }
  }

  final List<Future<void>> inflight = <Future<void>>[
    fetchClient(
      preferredClient,
      force: forceRefresh,
      timeout: preferredTimeout,
    ).then((PlaybackResolved? resolved) {
      if (resolved != null) {
        consider(resolved);
      }
    }),
  ];

  if (preferredClient != kPlaybackHdFallbackClient) {
    inflight.add(
      fetchClient(
        kPlaybackHdFallbackClient,
        force: true,
        timeout: fallbackTimeout,
      ).then((PlaybackResolved? resolved) {
        if (resolved != null) {
          consider(resolved);
          AppLogger.i(
            'android_vr result height=${resolved.height} '
            'max=${playbackMaxAvailableHeight(resolved)} '
            'needsMweb=${playbackNeedsExtraClient(best ?? resolved)}',
          );
        }
      }),
    );
  }

  await Future.wait(inflight);

  if (best != null && !playbackNeedsExtraClient(best!)) {
    return best!;
  }

  if (mintPoTokens != null) {
    final String? videoId = YoutubeUrls.videoId(url);
    if (videoId != null) {
      try {
        AppLogger.i('BotGuard mint then mweb for $videoId');
        final PlaybackPoToken? tokens = await mintPoTokens(videoId);
        if (tokens != null) {
          final PlaybackResolved? mweb = await fetchClient(
            kPlaybackMwebClient,
            force: true,
            poToken: tokens.extractorValue,
            timeout: fallbackTimeout,
          );
          if (mweb != null) {
            consider(mweb);
          }
        }
      } on Object catch (error, stack) {
        AppLogger.w('resolve via mweb+PO failed: $error\n$stack');
      }
    }
  }

  if (best != null) {
    return best!;
  }
  throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
}
