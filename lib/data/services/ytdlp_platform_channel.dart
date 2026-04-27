/// Flutter bridge for Android youtubedl-android integration.
library;

import 'package:flutter/services.dart';

/// Flutter side of the MethodChannel bridge to youtubedl-android.
///
/// Used on Android only. Desktop uses process-based yt-dlp services.
class YtdlpPlatformChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.ytdownloader.app/ytdlp',
  );
  static const EventChannel _progressChannel = EventChannel(
    'com.ytdownloader.app/ytdlp_progress',
  );

  /// Initialize the youtubedl-android library.
  static Future<void> initialize() async {
    await _channel.invokeMethod<void>('initialize');
  }

  /// Returns the bundled yt-dlp version string.
  static Future<String> getVersion() async {
    final String? version = await _channel.invokeMethod<String>('getVersion');
    return version ?? 'unknown';
  }

  /// Fetches metadata/formats payload as raw yt-dlp JSON.
  static Future<String> fetchFormats(String url) async {
    final String? json = await _channel.invokeMethod<String>(
      'fetchFormats',
      <String, dynamic>{'url': url},
    );
    return json ?? '';
  }

  /// Returns whether the given URL resolves to a playlist.
  static Future<bool> isPlaylist(String url) async {
    final bool? value = await _channel.invokeMethod<bool>(
      'isPlaylist',
      <String, dynamic>{'url': url},
    );
    return value ?? false;
  }

  /// Fetches full flat-playlist JSON payload.
  static Future<String> fetchPlaylistInfo(String url) async {
    final String? json = await _channel.invokeMethod<String>(
      'fetchPlaylistInfo',
      <String, dynamic>{'url': url},
    );
    return json ?? '';
  }

  /// Starts an Android-native download and returns the process id.
  static Future<String> startDownload({
    required String url,
    required String formatId,
    required String outputPath,
    required String processId,
    required bool isPlaylist,
    required bool embedThumbnail,
    required bool addMetadata,
    required bool downloadSubtitles,
    required String subtitleLanguage,
    required bool skipExisting,
    required String rateLimit,
  }) async {
    final String? id = await _channel
        .invokeMethod<String>('download', <String, dynamic>{
          'url': url,
          'formatId': formatId,
          'outputPath': outputPath,
          'processId': processId,
          'isPlaylist': isPlaylist,
          'embedThumbnail': embedThumbnail,
          'addMetadata': addMetadata,
          'downloadSubtitles': downloadSubtitles,
          'subtitleLanguage': subtitleLanguage,
          'skipExisting': skipExisting,
          'rateLimit': rateLimit,
        });
    return id ?? processId;
  }

  /// Cancels a running Android-native download by process id.
  static Future<void> cancelDownload(String processId) async {
    await _channel.invokeMethod<void>('cancel', <String, dynamic>{
      'processId': processId,
    });
  }

  /// Broadcast stream of Android-native progress events.
  static Stream<Map<dynamic, dynamic>> get progressStream =>
      _progressChannel.receiveBroadcastStream().map((dynamic event) {
        if (event is Map<dynamic, dynamic>) {
          return event;
        }
        return <dynamic, dynamic>{};
      });
}
