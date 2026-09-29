/// Capability-based extraction strategies for in-app playback.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_po_token.dart';
import '../models/playback_resolved.dart';
import 'playback_stream_validate.dart';
import 'ytdlp_service.dart';

/// Capability-based strategies — not a hard-coded list of dead clients.
///
/// Order for start/warm (align with server): [webSafariHls] →
/// [defaultClients] → [mwebWithPot] (if tokens) → [android] → [webEmbedded].
enum ExtractionStrategy {
  /// Let current yt-dlp pick YouTube clients (no `player_client` override).
  defaultClients,

  /// Explicit `android` client (not `android_vr`, which is broken since Aug 2026).
  android,

  /// `mweb` only when a complete BotGuard GVS+player PO + visitor_data exists.
  mwebWithPot,

  /// Prefer HLS from `web_safari` when HTTPS adaptive is unavailable.
  webSafariHls,

  /// Last resort for embeddable videos only.
  webEmbedded,
}

/// yt-dlp `player_client` value, or `default` for no override.
String extractionPlayerClient(ExtractionStrategy strategy) {
  switch (strategy) {
    case ExtractionStrategy.defaultClients:
      return 'default';
    case ExtractionStrategy.android:
      return 'android';
    case ExtractionStrategy.mwebWithPot:
      return 'mweb';
    case ExtractionStrategy.webSafariHls:
      return 'web_safari';
    case ExtractionStrategy.webEmbedded:
      return 'web_embedded';
  }
}

/// Whether [strategy] requires a complete PO + visitor_data mint.
bool extractionRequiresPo(ExtractionStrategy strategy) {
  return strategy == ExtractionStrategy.mwebWithPot;
}

/// Preferred start / quality-cache label (yt-dlp default clients).
const String kPlaybackStartClient = 'default';

/// Explicit android client (quality switch / warm).
const String kPlaybackAndroidClient = 'android';

/// Deprecated VR bundle — kept only so old call sites compile; never used.
@Deprecated('android_vr is broken since Aug 2026; do not use')
const String kPlaybackHdFallbackClient = 'android';

/// Web client used with minted BotGuard PO tokens.
const String kPlaybackMwebClient = 'mweb';

/// Safari web client; HLS often works without a GVS PO token.
const String kPlaybackWebSafariClient = 'web_safari';

/// Embeddable-only last resort.
const String kPlaybackWebEmbeddedClient = 'web_embedded';

/// Max wait for BotGuard mint before skipping mwebWithPot.
const Duration kPlaybackMintTimeout = Duration(seconds: 10);

/// Append GVS PO token as `pot=` on googlevideo HTTPS URLs when missing.
///
/// Prefer passing PO tokens to yt-dlp extractor-args so URLs are minted fresh.
/// This helper is kept only for explicit mweb URL repair / tests — never use it
/// to "upgrade" an android `c=ANDROID` URL with a web BotGuard token.
String? playbackAppendGvsPot(String? url, String? pot) {
  if (url == null || url.isEmpty) {
    return url;
  }
  final String token = pot?.trim() ?? '';
  if (token.isEmpty) {
    return url;
  }
  final String lower = url.toLowerCase();
  if (!lower.contains('googlevideo.com')) {
    return url;
  }
  if (lower.contains('.m3u8') || lower.contains('manifest/hls')) {
    return url;
  }
  // Never splice a web PO onto an Android GVS signature.
  if (lower.contains('c=android') || lower.contains('c%3dandroid')) {
    return url;
  }
  if (lower.contains('pot=')) {
    return url;
  }
  final String sep = url.contains('?') ? '&' : '?';
  return '$url${sep}pot=${Uri.encodeQueryComponent(token)}';
}

/// Rewrite stream URLs with a GVS pot when available.
PlaybackResolved playbackWithGvsPot(PlaybackResolved resolved, String? pot) {
  final String token = pot?.trim() ?? '';
  if (token.isEmpty) {
    return resolved;
  }
  return PlaybackResolved(
    info: resolved.info,
    mode: resolved.mode,
    headers: resolved.headers,
    quality: resolved.quality,
    videoUrl: playbackAppendGvsPot(resolved.videoUrl, token),
    audioUrl: playbackAppendGvsPot(resolved.audioUrl, token),
    progressiveUrl: playbackAppendGvsPot(resolved.progressiveUrl, token),
    hlsUrl: resolved.hlsUrl,
    height: resolved.height,
    expiresAt: resolved.expiresAt,
    formatId: resolved.formatId,
    availableHeights: resolved.availableHeights,
  );
}

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

List<ExtractionStrategy> _startStrategies({required bool hasPo}) {
  // Align with server ladder: web_safari (HLS / GVS-PO-light) before mweb.
  if (hasPo) {
    return <ExtractionStrategy>[
      ExtractionStrategy.webSafariHls,
      ExtractionStrategy.defaultClients,
      ExtractionStrategy.mwebWithPot,
      ExtractionStrategy.android,
      ExtractionStrategy.webEmbedded,
    ];
  }
  return <ExtractionStrategy>[
    ExtractionStrategy.webSafariHls,
    ExtractionStrategy.defaultClients,
    ExtractionStrategy.android,
    ExtractionStrategy.webEmbedded,
  ];
}

/// Default-first start. Never forces a fixed format ID or dead `android_vr`.
///
/// Extracts full `formats[]` then selects the closest playable height for
/// [PlaybackQuality.p360] preference (falls up when 360 is missing).
Future<PlaybackResolved> resolvePlaybackStart({
  required YtdlpService ytdlp,
  required String url,
  required bool forceRefresh,
  Duration timeout = const Duration(seconds: 90),
  Duration mintTimeout = kPlaybackMintTimeout,
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
  bool validateStreams = false,
}) async {
  final String? videoId = YoutubeUrls.videoId(url);

  // Mint FIRST — then extract WITH tokens. Never open a URL then mint.
  PlaybackPoToken? tokens;
  if (mintPoTokens != null && videoId != null) {
    try {
      AppLogger.i('BotGuard mint before extract videoId=$videoId');
      tokens = await mintPoTokens(videoId).timeout(mintTimeout);
      if (tokens != null && !tokens.isComplete) {
        AppLogger.w('BotGuard mint incomplete; mwebWithPot unavailable');
        tokens = null;
      } else if (tokens != null) {
        AppLogger.i(
          'BotGuard ready player+GVS; forcing fresh extract for $videoId',
        );
        // Pre-token JSON must not be reused with a new token context.
        ytdlp.invalidatePlaybackCaches(url);
      }
    } on Object catch (error, stack) {
      AppLogger.w('BotGuard mint failed: $error\n$stack');
      tokens = null;
    }
  }

  final bool refresh = forceRefresh || tokens != null;
  PlaybackResolved? best;
  for (final ExtractionStrategy strategy in _startStrategies(
    hasPo: tokens != null,
  )) {
    final PlaybackResolved? resolved = await _tryStrategy(
      ytdlp: ytdlp,
      url: url,
      strategy: strategy,
      forceRefresh: refresh,
      timeout: timeout,
      tokens: tokens,
      quality: PlaybackQuality.p360,
    );
    if (resolved == null) {
      continue;
    }
    if (!validateStreams) {
      return resolved;
    }
    final StreamValidationResult probe = await validatePlaybackStreams(resolved);
    if (probe.ok) {
      return resolved;
    }
    AppLogger.w(
      'strategy=${strategy.name} failed stream validate: ${probe.detail} '
      'v=${probe.videoStatus} a=${probe.audioStatus}',
    );
    // Keep last playable as soft fallback if every probe fails.
    best = resolved;
  }

  if (best != null) {
    AppLogger.w('returning last candidate without successful probe');
    return best;
  }

  throw const YtdlpException(AppStrings.errorPlaybackLadderExhausted);
}

/// Invalidate caches, remint PO, re-extract, validate — for 403/GVS recovery.
Future<PlaybackResolved> resolvePlaybackAfterGvsFailure({
  required YtdlpService ytdlp,
  required String url,
  Duration timeout = const Duration(seconds: 90),
  Future<PlaybackPoToken?> Function(String videoId)? mintPoTokens,
}) async {
  AppLogger.i('GVS recovery: invalidate + remint + fresh extract');
  ytdlp.invalidatePlaybackCaches(url);
  return resolvePlaybackStart(
    ytdlp: ytdlp,
    url: url,
    forceRefresh: true,
    timeout: timeout,
    mintPoTokens: mintPoTokens,
    validateStreams: true,
  );
}

Future<PlaybackResolved?> _tryStrategy({
  required YtdlpService ytdlp,
  required String url,
  required ExtractionStrategy strategy,
  required bool forceRefresh,
  required Duration timeout,
  required PlaybackQuality quality,
  PlaybackPoToken? tokens,
}) async {
  if (extractionRequiresPo(strategy) &&
      (tokens == null || !tokens.isComplete)) {
    AppLogger.w('skip ${strategy.name}: missing PO/visitor_data');
    return null;
  }

  final String client = extractionPlayerClient(strategy);
  final bool usePo = extractionRequiresPo(strategy);
  final PlaybackPoToken? pot = usePo ? tokens : null;

  final PlaybackResolved? raw = await _fetchClient(
    ytdlp: ytdlp,
    url: url,
    quality: quality,
    client: client,
    forceRefresh: forceRefresh,
    timeout: timeout,
    poToken: pot?.extractorValueFor(client),
    visitorData: pot?.visitorData,
  );
  if (raw == null) {
    return null;
  }

  // Tokens already applied during extraction — do NOT splice pot= onto URLs.
  final PlaybackResolved clean = playbackSanitizeAndroidVr(raw);
  _logResolvedSafe(
    strategy: strategy.name,
    client: client,
    hasPo: pot != null,
    resolved: clean,
  );
  if (playbackStartIsAcceptable(clean)) {
    return clean;
  }
  // Same JSON, try unrestricted selection if capped pick was unusable.
  if (quality != PlaybackQuality.auto) {
    final PlaybackResolved? auto = await _fetchClient(
      ytdlp: ytdlp,
      url: url,
      quality: PlaybackQuality.auto,
      client: client,
      forceRefresh: false,
      timeout: timeout,
      poToken: pot?.extractorValueFor(client),
      visitorData: pot?.visitorData,
    );
    if (auto != null) {
      final PlaybackResolved cleanAuto = playbackSanitizeAndroidVr(auto);
      if (playbackStartIsAcceptable(cleanAuto)) {
        return cleanAuto;
      }
    }
  }
  return null;
}

void _logResolvedSafe({
  required String strategy,
  required String client,
  required bool hasPo,
  required PlaybackResolved resolved,
}) {
  AppLogger.i(
    'strategy=$strategy client=$client po=${hasPo ? 'present' : 'none'} '
    'mode=${resolved.mode.name} height=${resolved.height} '
    'heights=${resolved.availableHeights} '
    'video=${_itagOf(resolved.videoUrl)} audio=${_itagOf(resolved.audioUrl)} '
    'progressive=${_itagOf(resolved.progressiveUrl)} '
    'playable=${resolved.isPlayable}',
  );
}

String _itagOf(String? url) {
  if (url == null || url.isEmpty) {
    return '-';
  }
  final RegExpMatch? m = RegExp(r'[?&]itag=(\d+)').firstMatch(url);
  return m?.group(1) ?? 'ok';
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
        } else if (tokens != null) {
          ytdlp.invalidatePlaybackCaches(url);
        }
      } on Object catch (error, stack) {
        AppLogger.w('HD warm mint failed: $error\n$stack');
      }
    }
  }

  for (final ExtractionStrategy strategy in _startStrategies(
    hasPo: tokens != null,
  )) {
    if (!playbackNeedsExtraClient(best)) {
      break;
    }
    final PlaybackResolved? clean = await _tryStrategy(
      ytdlp: ytdlp,
      url: url,
      strategy: strategy,
      forceRefresh: true,
      timeout: timeout,
      tokens: tokens,
      quality: PlaybackQuality.auto,
    );
    if (clean == null) {
      continue;
    }
    if (playbackUrlIsAndroidVr(clean.progressiveUrl) &&
        playbackMaxAvailableHeight(clean) < 720) {
      AppLogger.w('HD warm discarded VR-polluted low ladder');
      continue;
    }
    if (playbackFallbackImproves(best, clean)) {
      best = clean;
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
    AppLogger.w('resolve via $client failed: $error\n$stack');
    return null;
  }
}
