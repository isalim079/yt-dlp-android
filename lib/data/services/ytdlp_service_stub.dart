/// Stub when `dart:io` is unavailable (e.g. web) — yt-dlp cannot run.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/app_settings.dart';
import '../models/playback_resolved.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';
import 'playback_json_cache.dart';

/// No-op [YtdlpService] for unsupported platforms.
class YtdlpService {
  /// Creates a stub service (binary path is ignored on web).
  const YtdlpService({required this.binaryPath});

  /// Ignored on web.
  final String binaryPath;

  /// Shared with the IO implementation so tests compile on every target.
  static final PlaybackJsonCache jsonCache = PlaybackJsonCache();

  /// Test hook; unused on web.
  static Future<String> Function(String url, String playerClient)? debugFetchJson;

  /// Test hook: drops stub caches.
  static void resetCachesForTest() {
    jsonCache.clear();
    debugFetchJson = null;
  }

  /// Mirrors the IO extractor-args builder so tests compile on every target.
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

  /// Stubbed download args builder for non-IO platforms.
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
    final List<String> args = <String>[
      '-f',
      formatId,
      '-o',
      outputTemplate,
      '--extractor-args',
      extractorArgsFor(client, poToken: poToken, visitorData: visitorData),
    ];
    if (mergeOutput || formatId.contains('+')) {
      args.addAll(<String>['--merge-output-format', 'mp4']);
    }
    args.add(url);
    return args;
  }

  /// Always throws [YtdlpException] on web.
  Future<String> fetchFormatsJson(
    String url, {
    String playerClient = 'default',
    String? poToken,
    String? visitorData,
    bool forceRefresh = false,
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// No-op on web.
  void invalidateFormatCache(String url) {}

  /// No-op on web.
  void invalidatePlaybackCaches(String url) {}

  /// Always throws [YtdlpException] on web.
  Future<List<VideoFormat>> fetchFormats(
    String url, {
    String playerClient = 'android',
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<VideoInfo> fetchVideoInfo(
    String url, {
    String playerClient = 'android',
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<PlaybackResolved> resolvePlayback(
    String url, {
    PlaybackQuality quality = PlaybackQuality.auto,
    String playerClient = 'default',
    bool forceRefresh = false,
    String? poToken,
    String? visitorData,
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<PlaylistInfo> fetchFlatListing(String source) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always returns `false` on web.
  Future<bool> isPlaylistUrl(String url) async => false;

  /// Always throws [YtdlpException] on web.
  Future<PlaylistInfo> fetchPlaylistInfo(String url) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }
}
