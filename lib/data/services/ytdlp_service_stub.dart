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
  static String extractorArgsFor(String playerClient, {String? poToken}) {
    final String client =
        playerClient.trim().isEmpty ? 'android,web' : playerClient.trim();
    final String token = poToken?.trim() ?? '';
    if (token.isEmpty) {
      return 'youtube:player_client=$client';
    }
    return 'youtube:player_client=$client;po_token=$token';
  }

  /// Stubbed download args builder for non-IO platforms.
  List<String> buildDownloadArgs({
    required String url,
    required String formatId,
    required String outputTemplate,
    required AppSettings settings,
  }) {
    return <String>[
      url,
      formatId,
      outputTemplate,
      settings.preferredFormat.name,
    ];
  }

  /// Always throws [YtdlpException] on web.
  Future<List<VideoFormat>> fetchFormats(
    String url, {
    String playerClient = 'android,web',
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<VideoInfo> fetchVideoInfo(
    String url, {
    String playerClient = 'android,web',
  }) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<PlaybackResolved> resolvePlayback(
    String url, {
    PlaybackQuality quality = PlaybackQuality.auto,
    String playerClient = 'android,web',
    bool forceRefresh = false,
    String? poToken,
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
