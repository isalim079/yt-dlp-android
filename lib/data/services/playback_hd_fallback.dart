/// Extraction strategies + HD warm ladder for in-app playback.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_po_token.dart';
import '../models/playback_resolved.dart';
import 'ytdlp_service.dart';

/// Verified extraction strategies (not arbitrary client spam).
///
/// - [defaultClients]: yt-dlp built-in YouTube clients (no override).
/// - [poMwebBundle]: mweb with BotGuard PO + visitors, plus clients that
///   still expose HTTPS/HLS alongside SABR-only web.
/// - [httpsFallback]: clients known to return direct HTTPS / HLS without PO.
enum ExtractionStrategy {
  /// Let yt-dlp choose (`android_vr` / `web_safari` / `web_embedded` today).
  defaultClients,

  /// `mweb` + PO + visitor_data, plus HTTPS/HLS companions.
  poMwebBundle,

  /// HTTPS/HLS without requiring a web PO token.
  httpsFallback,
}

/// Player-client string for [ExtractionStrategy], or `default` for no override.
String extractionPlayerClient(ExtractionStrategy strategy) {
  switch (strategy) {
    case ExtractionStrategy.defaultClients:
      return 'default';
    case ExtractionStrategy.poMwebBundle:
      return 'mweb,android_vr,web_safari,web_embedded';
    case ExtractionStrategy.httpsFallback:
      return 'android_vr,web_safari,web_embedded';
  }
}

/// Last-resort / quality-cache client label (HTTPS fallback bundle).
const String kPlaybackStartClient = 'android_vr,web_safari,web_embedded';

/// Client that still returns direct HTTPS adaptive URLs for many SABR videos.
const String kPlaybackHdFallbackClient = 'android_vr,web';

/// Web client used with minted BotGuard PO tokens (alone).
const String kPlaybackMwebClient = 'mweb';

/// Safari web client; HLS often works without a GVS PO token.
const String kPlaybackWebSafariClient = 'web_safari';

/// Max wait for BotGuard mint before falling through.
const Duration kPlaybackMintTimeout = Duration(seconds: 10);

/// True when a googlevideo URL was minted for the ANDROID_VR client.
bool playbackUrlIsAndroidVr(String? url) {
  if (url == null || url.isEmpty) {
    return false;
  }
  final String lower = url.toLowerCase();
  return lower.contains('c=android_vr') || lower.contains('c%3dandroid_vr');
}

/// Drop ANDROID_VR progressive pollution so HLS/adaptive can be opened.
PlaybackResolved playbackSanitizeAndroidVr(PlaybackResolved resolved) {
  final bool progressiveVr = playbackUrlIsAndroidVr(resolved.progressiveUrl);
  final bool videoVr = playbackUrlIsAndroidVr(resolved.videoUrl);
  if (!progressiveVr && !videoVr) {
    return resolved;
  }

  final String? hls = resolved.hlsUrl;
  if (hls != null && hls.isNotEmpty && !playbackUrlIsAndroidVr(hls)) {
    AppLogger.i('sanitize: prefer HLS over ANDROID_VR progressive/adaptive');
    return PlaybackResolved(
      info: resolved.info,
      mode: PlaybackMode.hls,
      headers: resolved.headers,
      quality: resolved.quality,
      hlsUrl: hls,
      height: resolved.height,
      expiresAt: resolved.expiresAt,
      formatId: 'hls',
      availableHeights: resolved.availableHeights,
    );
  }

  if (videoVr) {
    AppLogger.w('sanitize: ANDROID_VR adaptive video rejected');
    if (resolved.progressiveUrl != null &&
        resolved.progressiveUrl!.isNotEmpty &&
        !progressiveVr) {
      return PlaybackResolved(
        info: resolved.info,
        mode: PlaybackMode.progressive,
        headers: resolved.headers,
        quality: resolved.quality,
        progressiveUrl: resolved.progressiveUrl,
        hlsUrl: resolved.hlsUrl,
        height: resolved.height,
        expiresAt: resolved.expiresAt,
        formatId: resolved.formatId,
        availableHeights: resolved.availableHeights,
      );
    }
  }

  if (progressiveVr) {
    AppLogger.w('sanitize: clearing ANDROID_VR progressive URL');
    return resolved.copyWith(clearProgressive: true);
  }
  return resolved;
}

/// Whether [resolved] is safe to open after VR sanitization.
bool playbackStartIsAcceptable(PlaybackResolved resolved) {
  final PlaybackResolved clean = playbackSanitizeAndroidVr(resolved);
  if (!clean.isPlayable) {
    return false;
  }
  if (playbackUrlIsAndroidVr(clean.primaryUrl)) {
    return false;
  }
  return true;
}

/// PO-first start: poMwebBundle → default → httpsFallback.
///
/// Never fails merely because an exact height (e.g. 360) is missing — the
/// resolver picks the closest available playable format from `formats[]`.
Future<PlaybackResolved> resolvePlaybackStart({
  required YtdlpService ytdlp,
  required String url,
  required bool forceRefresh,
  Duration timeout = const Duration(seconds: 90),
  Duration mintTimeout = kPlaybackMintTimeout,
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
}) async {
  final String? videoId = YoutubeUrls.videoId(url);
  PlaybackPoToken? tokens;

  if (mintPoTokens != null && videoId != null) {
    try {
      AppLogger.i('BotGuard mint for start $videoId');
      tokens = await mintPoTokens(videoId).timeout(mintTimeout);
      if (tokens != null && !tokens.isComplete) {
        AppLogger.w('BotGuard mint incomplete; continuing without PO');
        tokens = null;
      }
    } on Object catch (error, stack) {
      AppLogger.w('BotGuard mint failed: $error\n$stack');
      tokens = null;
    }
  }

  final List<ExtractionStrategy> strategies = <ExtractionStrategy>[
    if (tokens != null) ExtractionStrategy.poMwebBundle,
    ExtractionStrategy.defaultClients,
    ExtractionStrategy.httpsFallback,
  ];

  for (final ExtractionStrategy strategy in strategies) {
    final PlaybackResolved? resolved = await _tryStrategy(
      ytdlp: ytdlp,
      url: url,
      strategy: strategy,
      forceRefresh: forceRefresh,
      timeout: timeout,
      tokens: tokens,
    );
    if (resolved != null) {
      return resolved;
    }
  }

  throw const YtdlpException(AppStrings.errorPlaybackLadderExhausted);
}

Future<PlaybackResolved?> _tryStrategy({
  required YtdlpService ytdlp,
  required String url,
  required ExtractionStrategy strategy,
  required bool forceRefresh,
  required Duration timeout,
  PlaybackPoToken? tokens,
}) async {
  final String client = extractionPlayerClient(strategy);
  final bool usePo =
      strategy == ExtractionStrategy.poMwebBundle && tokens != null;

  // Prefer a capped quality first for fast start, then any playable format.
  for (final PlaybackQuality quality in <PlaybackQuality>[
    PlaybackQuality.p360,
    PlaybackQuality.auto,
  ]) {
    final PlaybackResolved? raw = await _fetchClient(
      ytdlp: ytdlp,
      url: url,
      quality: quality,
      client: client,
      forceRefresh: forceRefresh,
      timeout: timeout,
      poToken: usePo ? tokens.extractorValue : null,
      visitorData: usePo ? tokens.visitorData : null,
    );
    if (raw == null) {
      continue;
    }
    final PlaybackResolved clean = playbackSanitizeAndroidVr(raw);
    AppLogger.i(
      'strategy=${strategy.name} quality=${quality.name} '
      'mode=${clean.mode.name} height=${clean.height} '
      'heights=${clean.availableHeights.length} playable=${clean.isPlayable}',
    );
    if (playbackStartIsAcceptable(clean)) {
      return clean;
    }
  }
  return null;
}

/// Background HD JSON. Never meant to open the player by itself.
Future<PlaybackResolved?> warmPlaybackHdLadder({
  required YtdlpService ytdlp,
  required String url,
  required String preferredClient,
  required PlaybackResolved start,
  Duration timeout = const Duration(seconds: 20),
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
}) async {
  PlaybackResolved best = start;
  PlaybackPoToken? tokens;

  if (mintPoTokens != null) {
    final String? videoId = YoutubeUrls.videoId(url);
    if (videoId != null) {
      try {
        tokens = await mintPoTokens(videoId);
        if (tokens != null && !tokens.isComplete) {
          tokens = null;
        }
      } on Object catch (error, stack) {
        AppLogger.w('HD warm mint failed: $error\n$stack');
      }
    }
  }

  final List<ExtractionStrategy> strategies = <ExtractionStrategy>[
    if (tokens != null) ExtractionStrategy.poMwebBundle,
    ExtractionStrategy.defaultClients,
    ExtractionStrategy.httpsFallback,
  ];

  for (final ExtractionStrategy strategy in strategies) {
    if (!playbackNeedsExtraClient(best) && strategy != strategies.first) {
      break;
    }
    final bool usePo =
        strategy == ExtractionStrategy.poMwebBundle && tokens != null;
    final PlaybackResolved? raw = await _fetchClient(
      ytdlp: ytdlp,
      url: url,
      quality: PlaybackQuality.auto,
      client: extractionPlayerClient(strategy),
      forceRefresh: true,
      timeout: timeout,
      poToken: usePo ? tokens.extractorValue : null,
      visitorData: usePo ? tokens.visitorData : null,
    );
    if (raw == null) {
      continue;
    }
    final PlaybackResolved clean = playbackSanitizeAndroidVr(raw);
    // Skip VR-only ~360 ladders.
    if (playbackMaxAvailableHeight(clean) < 720 &&
        playbackUrlIsAndroidVr(clean.progressiveUrl)) {
      AppLogger.w('HD warm discarded VR-only ladder');
      continue;
    }
    if (playbackFallbackImproves(best, clean)) {
      best = clean;
    }
    if (!playbackNeedsExtraClient(best)) {
      break;
    }
  }

  // Optional legacy VR client when still short on HD and not already VR.
  if (playbackNeedsExtraClient(best) &&
      preferredClient != kPlaybackHdFallbackClient) {
    final PlaybackResolved? vr = await _fetchClient(
      ytdlp: ytdlp,
      url: url,
      quality: PlaybackQuality.auto,
      client: kPlaybackHdFallbackClient,
      forceRefresh: true,
      timeout: timeout,
    );
    if (vr != null) {
      final int maxH = playbackMaxAvailableHeight(vr);
      if (maxH >= 720 && playbackFallbackImproves(best, vr)) {
        best = playbackSanitizeAndroidVr(vr);
      } else {
        AppLogger.w('android_vr discarded (max=$maxH, need >=720)');
      }
    }
  }

  if (identical(best, start) || !playbackFallbackImproves(start, best)) {
    return null;
  }
  return playbackKeepStartProgressive(start, best);
}

/// Always keep the start muxed URL when it is non-VR and playable.
PlaybackResolved playbackKeepStartProgressive(
  PlaybackResolved start,
  PlaybackResolved hd,
) {
  final String? startProgressive = start.progressiveUrl;
  if (startProgressive == null || startProgressive.isEmpty) {
    return hd;
  }
  if (playbackUrlIsAndroidVr(startProgressive)) {
    return hd;
  }
  return hd.copyWith(progressiveUrl: startProgressive);
}

Future<PlaybackResolved?> _fetchClient({
  required YtdlpService ytdlp,
  required String url,
  required PlaybackQuality quality,
  required String client,
  required bool forceRefresh,
  required Duration timeout,
  String? poToken,
  String? visitorData,
}) async {
  try {
    return await ytdlp
        .resolvePlayback(
          url,
          quality: quality,
          playerClient: client,
          forceRefresh: forceRefresh,
          poToken: poToken,
          visitorData: visitorData,
        )
        .timeout(timeout);
  } on Object catch (error, stack) {
    // Empty formats / SABR-only / format-not-available → try next strategy.
    AppLogger.w('resolve via $client failed: $error\n$stack');
    return null;
  }
}
