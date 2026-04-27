/// Stub when `dart:io` is unavailable (e.g. web) — yt-dlp cannot run.
library;

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/app_settings.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';

/// No-op [YtdlpService] for unsupported platforms.
class YtdlpService {
  /// Creates a stub service (binary path is ignored on web).
  const YtdlpService({required this.binaryPath});

  /// Ignored on web.
  final String binaryPath;

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
  Future<List<VideoFormat>> fetchFormats(String url) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always throws [YtdlpException] on web.
  Future<VideoInfo> fetchVideoInfo(String url) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }

  /// Always returns `false` on web.
  Future<bool> isPlaylistUrl(String url) async => false;

  /// Always throws [YtdlpException] on web.
  Future<PlaylistInfo> fetchPlaylistInfo(String url) async {
    throw const YtdlpException(AppStrings.errorUnknown);
  }
}
