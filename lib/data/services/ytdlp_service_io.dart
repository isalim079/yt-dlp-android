/// Spawns and supervises yt-dlp processes (list formats, download, metadata).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../../core/utils/ytdlp_launch_command.dart';
import '../models/app_settings.dart';
import '../models/playback_manifest.dart';
import '../models/playback_resolved.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';
import 'format_parser.dart';
import 'playback_json_cache.dart';
import 'playback_resolver.dart';
import 'ytdlp_platform_channel.dart';

/// Single entry point for invoking the bundled yt-dlp binary.
class YtdlpService {
  /// Requires the absolute path to the yt-dlp binary.
  ///
  /// Injected via Riverpod — never hardcoded.
  const YtdlpService({required this.binaryPath});

  /// Absolute path to the yt-dlp executable for this isolate.
  final String binaryPath;

  /// Builds yt-dlp arguments for a download using [settings].
  ///
  /// Prefer [playerClient]/[poToken]/[visitorData] from the selected catalog
  /// entry so download uses the same InnerTube client that listed the format.
  List<String> buildDownloadArgs({
    required String url,
    required String formatId,
    required String outputTemplate,
    required AppSettings settings,
    String? playerClient,
    String? poToken,
    String? visitorData,
    bool mergeOutput = false,
  }) {
    final String client =
        (playerClient != null && playerClient.trim().isNotEmpty)
        ? playerClient.trim()
        : settings.playerClient.ytDlpValue;
    final bool needsMerge =
        mergeOutput || formatId.contains('+');
    final List<String> args = <String>[
      '-f',
      formatId,
      '-o',
      outputTemplate,
      '--newline',
      '--no-warnings',
      '--progress',
      '--no-playlist',
      '--extractor-args',
      extractorArgsFor(client, poToken: poToken, visitorData: visitorData),
      '--parse-metadata',
      ':(?P<comment>Downloaded with yt-dlp App)',
    ];
    if (needsMerge) {
      args.addAll(<String>['--merge-output-format', 'mp4']);
    }
    if (settings.downloadSubtitles) {
      args.addAll(<String>[
        '--write-auto-sub',
        '--sub-lang',
        settings.subtitleLanguage,
      ]);
    }
    if (settings.embedThumbnail) {
      args.add('--embed-thumbnail');
    }
    if (settings.addMetadata) {
      args.add('--add-metadata');
    }
    if (settings.skipExistingFiles) {
      args.add('--no-overwrites');
    }
    if (settings.limitDownloadSpeed && settings.maxDownloadSpeedKbps > 0) {
      args.addAll(<String>[
        '--rate-limit',
        '${settings.maxDownloadSpeedKbps}K',
      ]);
    }
    if (settings.preferredFormat != PreferredFormat.mp4 &&
        settings.preferredFormat != PreferredFormat.mp3 &&
        settings.preferredFormat != PreferredFormat.m4a) {
      args.addAll(<String>['--recode-video', settings.preferredFormat.name]);
    }
    args.add(url);
    return args;
  }

  /// Raw yt-dlp `-J` JSON for [url] (shared cache with playback / catalog).
  Future<String> fetchFormatsJson(
    String url, {
    String playerClient = 'default',
    String? poToken,
    String? visitorData,
    bool forceRefresh = false,
  }) async {
    try {
      return await _ensureSingleVideoJson(
        url,
        playerClient: playerClient,
        forceRefresh: forceRefresh,
        poToken: poToken,
        visitorData: visitorData,
      );
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchFormatsJson failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Drops cached `-J` bodies for [url] (all strategies).
  void invalidateFormatCache(String url) {
    jsonCache.invalidateUrl(url);
  }

  /// Drops JSON + resolved playback caches for [url] (all qualities/clients).
  void invalidatePlaybackCaches(String url) {
    invalidateFormatCache(url);
    final List<String> keys = _playbackCache.keys
        .where((String k) => k.startsWith('$url|'))
        .toList(growable: false);
    for (final String k in keys) {
      _playbackCache.remove(k);
    }
    AppLogger.i('invalidatePlaybackCaches url=$url dropped=${keys.length}');
  }

  static String extractorArgsFor(
    String playerClient, {
    String? poToken,
    String? visitorData,
  }) {
    final String client = playerClient.trim();
    final List<String> parts = <String>[];
    if (client.isNotEmpty && client.toLowerCase() != 'default') {
      parts.add('player_client=$client');
    }
    final String token = poToken?.trim() ?? '';
    if (token.isNotEmpty) {
      parts.add('po_token=$token');
    }
    final String visitor = visitorData?.trim() ?? '';
    if (visitor.isNotEmpty) {
      parts.add('visitor_data=$visitor');
    }
    if (parts.isEmpty) {
      return 'youtube:';
    }
    return 'youtube:${parts.join(';')}';
  }

  static final PlaybackJsonCache jsonCache = PlaybackJsonCache();
  static final Map<String, PlaybackResolved> _playbackCache =
      <String, PlaybackResolved>{};

  /// Test hook: intercepts `-J` so quality-switch tests can count extracts.
  @visibleForTesting
  static Future<String> Function(String url, String playerClient)? debugFetchJson;

  /// Test hook: drops JSON and resolved-URL caches.
  static void resetCachesForTest() {
    jsonCache.clear();
    _playbackCache.clear();
    debugFetchJson = null;
  }

  /// Fetches all available formats for a given URL.
  ///
  /// Runs: `yt-dlp -J --no-playlist --no-warnings <url>`
  /// Returns a list of [VideoFormat] sorted by quality (best first).
  /// Throws [YtdlpException] on failure.
  Future<List<VideoFormat>> fetchFormats(
    String url, {
    String playerClient = 'android',
  }) async {
    try {
      final String json = await _ensureSingleVideoJson(
        url,
        playerClient: playerClient,
      );
      final List<VideoFormat> list = FormatParser.parseFormats(json);
      if (list.isEmpty) {
        throw const YtdlpException(AppStrings.errorNoFormats);
      }
      AppLogger.i('Resolved ${list.length} formats for metadata request');
      return list;
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchFormats failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Fetches basic video metadata (title, thumbnail, duration, uploader).
  ///
  /// Reuses the same JSON payload as [fetchFormats] for the same [url]
  /// within this service instance (no second `-J` process).
  Future<VideoInfo> fetchVideoInfo(
    String url, {
    String playerClient = 'android',
  }) async {
    try {
      final String json = await _ensureSingleVideoJson(
        url,
        playerClient: playerClient,
      );
      return FormatParser.parseVideoInfo(json);
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchVideoInfo failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Resolves playable CDN / HLS URLs for in-app playback.
  Future<PlaybackResolved> resolvePlayback(
    String url, {
    PlaybackQuality quality = PlaybackQuality.auto,
    String playerClient = 'default',
    bool forceRefresh = false,
    String? poToken,
    String? visitorData,
  }) async {
    try {
      _validateUrl(url);
      final String resolvedKey =
          '$url|${quality.name}|$playerClient|${poToken ?? ''}|${visitorData ?? ''}';
      if (!forceRefresh) {
        final PlaybackResolved? cached = _playbackCache[resolvedKey];
        if (cached != null && !cached.isExpired) {
          return cached;
        }
      }
      String json = await _ensureSingleVideoJson(
        url,
        playerClient: playerClient,
        forceRefresh: forceRefresh,
        poToken: poToken,
        visitorData: visitorData,
      );
      PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: quality,
      );
      final PlaybackManifest manifest =
          PlaybackResolver.manifestFromJson(json);
      AppLogger.i(
        'resolvePlayback client=$playerClient quality=${quality.name} '
        'mode=${resolved.mode.name} height=${resolved.height} '
        'delivery=${manifest.delivery.type.name} '
        'vStreams=${manifest.videoStreams.length} '
        'aStreams=${manifest.audioStreams.length} '
        'heights=${resolved.availableHeights} '
        'hasPo=${poToken != null && poToken.isNotEmpty} '
        'hasVisitor=${visitorData != null && visitorData.isNotEmpty}',
      );
      if (!forceRefresh && resolved.isExpired) {
        json = await _ensureSingleVideoJson(
          url,
          playerClient: playerClient,
          forceRefresh: true,
          poToken: poToken,
          visitorData: visitorData,
        );
        resolved = PlaybackResolver.fromJson(json, quality: quality);
      }
      if (!resolved.isPlayable) {
        throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
      }
      _playbackCache[resolvedKey] = resolved;
      return resolved;
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('resolvePlayback failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Flat listing for search, popular, channel uploads, or playlists.
  Future<PlaylistInfo> fetchFlatListing(String source) async {
    try {
      if (!YoutubeUrls.isSearchSource(source)) {
        _validateUrl(source);
      }
      if (Platform.isAndroid) {
        final String json = await YtdlpPlatformChannel.fetchPlaylistInfo(source);
        return FormatParser.parsePlaylistInfo(json);
      }
      final _YtdlpResult result = await _runProcess(<String>[
        '--flat-playlist',
        '--dump-single-json',
        '--no-warnings',
        '--no-update',
        '--playlist-end',
        '40',
        source,
      ], timeout: const Duration(seconds: 60));
      if (!result.isSuccess) {
        final String msg = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : AppStrings.errorProcessFailed;
        throw YtdlpException(msg);
      }
      return FormatParser.parsePlaylistInfo(result.stdout);
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchFlatListing failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Checks if a given URL points to a playlist.
  ///
  /// Runs: `yt-dlp --flat-playlist --dump-single-json --playlist-items 1 <url>`
  /// Returns `true` when the JSON root `_type` is `playlist`.
  Future<bool> isPlaylistUrl(String url) async {
    try {
      _validateUrl(url);
      if (Platform.isAndroid) {
        return await YtdlpPlatformChannel.isPlaylist(url);
      }
      final _YtdlpResult result = await _runProcess(<String>[
        '--flat-playlist',
        '--dump-single-json',
        '--playlist-items',
        '1',
        url,
      ]);
      if (!result.isSuccess) {
        final String msg = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : AppStrings.errorProcessFailed;
        throw YtdlpException(msg);
      }
      final String body = result.stdout.trim();
      if (body.isEmpty) {
        return false;
      }
      try {
        final Object? decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded['_type']?.toString() == 'playlist';
        }
      } on FormatException catch (e, stackTrace) {
        AppLogger.w('isPlaylistUrl JSON parse failed: $e\n$stackTrace');
        throw YtdlpException(
          AppStrings.errorParseVideoInformation,
          originalError: e,
        );
      }
      return false;
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('isPlaylistUrl failed', error, stackTrace);
      throw YtdlpException(AppStrings.errorUnknown, originalError: error);
    }
  }

  /// Fetches basic info for a playlist (title, count, entries preview).
  ///
  /// Runs: `yt-dlp --flat-playlist --dump-single-json <url>`
  Future<PlaylistInfo> fetchPlaylistInfo(String url) async {
    try {
      _validateUrl(url);
      if (Platform.isAndroid) {
        final String json = await YtdlpPlatformChannel.fetchPlaylistInfo(url);
        return FormatParser.parsePlaylistInfo(json);
      }
      final _YtdlpResult result = await _runProcess(<String>[
        '--flat-playlist',
        '--dump-single-json',
        url,
      ]);
      if (!result.isSuccess) {
        final String msg = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : AppStrings.errorProcessFailed;
        throw YtdlpException(msg);
      }
      return FormatParser.parsePlaylistInfo(result.stdout);
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchPlaylistInfo failed', error, stackTrace);
      throw _mapToYtdlpException(error);
    }
  }

  /// Validates that the URL is non-empty and matches a supported pattern.
  ///
  /// Supported hosts include `youtube.com`, `youtu.be`, and YouTube music.
  void _validateUrl(String url) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const YtdlpException(AppStrings.errorInvalidUrl);
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      throw const YtdlpException(AppStrings.errorInvalidUrl);
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const YtdlpException(AppStrings.errorInvalidUrl);
    }
    final String host = uri.host.toLowerCase();
    final bool youtubeHost =
        host == 'youtu.be' ||
        host == 'www.youtube.com' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'music.youtube.com' ||
        host == 'www.youtube-nocookie.com';
    if (!youtubeHost) {
      throw const YtdlpException(AppStrings.errorInvalidUrl);
    }
  }

  /// Central method that runs yt-dlp with [arguments] (excluding binary path).
  ///
  /// Applies UTF-8 IO env, captures stdout/stderr, and enforces a timeout.
  Future<_YtdlpResult> _runProcess(
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isAndroid) {
      throw const YtdlpException(
        'Android must use YtdlpPlatformChannel, not Process.run',
      );
    }
    try {
      final YtdlpLaunchCommand cmd = YtdlpLaunchCommand.from(
        binaryPath,
        arguments,
      );
      final ProcessResult result = await Process.run(
        cmd.executable,
        cmd.arguments,
        environment: <String, String>{'PYTHONIOENCODING': 'utf-8'},
        runInShell: false,
      ).timeout(timeout);
      return _YtdlpResult(
        stdout: _stdoutToString(result.stdout),
        stderr: _stdoutToString(result.stderr),
        exitCode: result.exitCode,
      );
    } on TimeoutException catch (e) {
      throw YtdlpException(AppStrings.errorTimeout, originalError: e);
    }
  }

  static String _stdoutToString(Object? out) {
    if (out is String) {
      return out;
    }
    if (out is List<int>) {
      return utf8.decode(out, allowMalformed: true);
    }
    return out?.toString() ?? '';
  }

  /// Ensures a single `-J` JSON payload is available for [url] + [playerClient].
  ///
  /// Quality is not part of the cache key; callers re-parse the same body.
  Future<String> _ensureSingleVideoJson(
    String url, {
    String playerClient = 'default',
    bool forceRefresh = false,
    String? poToken,
    String? visitorData,
  }) async {
    final bool hasPo = poToken != null && poToken.isNotEmpty;
    final bool hasVisitor = visitorData != null && visitorData.isNotEmpty;
    // Strategy identity — never reuse a pot-less body for a pot extract.
    final String strategy = playerClient.trim().isEmpty
        ? 'default'
        : playerClient.trim();
    final String cacheClient =
        '$strategy|${hasPo ? 'pot' : 'nopot'}|${hasVisitor ? 'vis' : 'novis'}';
    if (!forceRefresh) {
      final String? cached = jsonCache.read(url, cacheClient);
      if (cached != null) {
        AppLogger.d('Reusing in-memory yt-dlp JSON for $cacheClient');
        return cached;
      }
    }
    jsonCache.missCount += 1;
    final String body = await _fetchSingleVideoJson(
      url,
      playerClient: playerClient,
      poToken: poToken,
      visitorData: visitorData,
    );
    jsonCache.put(url, cacheClient, body);
    return body;
  }

  Future<String> _fetchSingleVideoJson(
    String url, {
    required String playerClient,
    String? poToken,
    String? visitorData,
  }) async {
    _validateUrl(url);
    final Future<String> Function(String url, String playerClient)? hook =
        debugFetchJson;
    if (hook != null) {
      return hook(url, playerClient);
    }
    late final String body;
    if (Platform.isAndroid) {
      body = await YtdlpPlatformChannel.fetchFormats(
        url,
        playerClient: playerClient,
        poToken: poToken,
        visitorData: visitorData,
      ).timeout(const Duration(seconds: 90));
    } else {
      final _YtdlpResult result = await _runProcess(<String>[
        '--dump-single-json',
        '--no-playlist',
        '--no-warnings',
        '--ignore-no-formats-error',
        '--extractor-args',
        extractorArgsFor(
          playerClient,
          poToken: poToken,
          visitorData: visitorData,
        ),
        url,
      ], timeout: const Duration(seconds: 90));
      if (!result.isSuccess) {
        final String msg = result.stderr.trim().isNotEmpty
            ? result.stderr.trim()
            : AppStrings.errorProcessFailed;
        throw YtdlpException(msg);
      }
      body = result.stdout;
    }
    if (body.trim().isEmpty) {
      throw const YtdlpException(AppStrings.errorProcessFailed);
    }
    return body;
  }

  YtdlpException _mapToYtdlpException(Object error) {
    final String raw = error.toString();
    final String lower = raw.toLowerCase();

    if (lower.contains('video unavailable') ||
        lower.contains('no longer available') ||
        lower.contains('copyright claim')) {
      final String message = lower.contains('\nerror: [youtube]')
          ? AppStrings.errorPlaylistUnavailableItems
          : AppStrings.errorVideoUnavailable;
      return YtdlpException(message, originalError: error);
    }

    if (lower.contains('http error 403') || lower.contains('forbidden')) {
      return YtdlpException(AppStrings.errorForbidden, originalError: error);
    }

    if (lower.contains('requested format is not available')) {
      // Exact height/format selector miss — not a permanent YouTube break.
      return YtdlpException(
        AppStrings.errorNoPlaybackStreams,
        originalError: error,
      );
    }

    if (lower.contains('sabr') ||
        lower.contains('nsig') ||
        lower.contains('signature') ||
        lower.contains('javascript runtime') ||
        lower.contains('js runtime')) {
      return YtdlpException(
        AppStrings.errorExtractionBroken,
        originalError: error,
      );
    }

    if (error is TimeoutException || lower.contains('timeout')) {
      return YtdlpException(AppStrings.errorTimeout, originalError: error);
    }

    return YtdlpException(AppStrings.errorUnknown, originalError: error);
  }
}

/// stdout/stderr/exitCode bundle for yt-dlp invocations.
class _YtdlpResult {
  /// Wraps process output fields.
  const _YtdlpResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  /// Raw standard output text.
  final String stdout;

  /// Raw standard error text.
  final String stderr;

  /// Process exit status.
  final int exitCode;

  /// Whether the process exited with code `0`.
  bool get isSuccess => exitCode == 0;
}
