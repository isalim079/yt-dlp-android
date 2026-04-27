/// Spawns and supervises yt-dlp processes (list formats, download, metadata).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/ytdlp_launch_command.dart';
import '../models/app_settings.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';
import 'format_parser.dart';
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
  List<String> buildDownloadArgs({
    required String url,
    required String formatId,
    required String outputTemplate,
    required AppSettings settings,
  }) {
    final List<String> args = <String>[
      '-f',
      formatId,
      '-o',
      outputTemplate,
      '--newline',
      '--no-warnings',
      '--progress',
      '--no-playlist',
    ];
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

  static String? _metadataJsonUrl;
  static String? _metadataJsonBody;

  /// Fetches all available formats for a given URL.
  ///
  /// Runs: `yt-dlp -J --no-playlist --no-warnings <url>`
  /// Returns a list of [VideoFormat] sorted by quality (best first).
  /// Throws [YtdlpException] on failure.
  Future<List<VideoFormat>> fetchFormats(String url) async {
    try {
      if (Platform.isAndroid) {
        final String json = await YtdlpPlatformChannel.fetchFormats(url);
        final List<VideoFormat> list = FormatParser.parseFormats(json);
        if (list.isEmpty) {
          throw const YtdlpException(AppStrings.errorNoFormats);
        }
        AppLogger.i('Resolved ${list.length} formats for metadata request');
        return list;
      }
      final String json = await _ensureSingleVideoJson(url);
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
      throw YtdlpException(AppStrings.errorUnknown, originalError: error);
    }
  }

  /// Fetches basic video metadata (title, thumbnail, duration, uploader).
  ///
  /// Reuses the same JSON payload as [fetchFormats] for the same [url]
  /// within this service instance (no second `-J` process).
  Future<VideoInfo> fetchVideoInfo(String url) async {
    try {
      if (Platform.isAndroid) {
        final String json = await YtdlpPlatformChannel.fetchFormats(url);
        return FormatParser.parseVideoInfo(json);
      }
      final String json = await _ensureSingleVideoJson(url);
      return FormatParser.parseVideoInfo(json);
    } on YtdlpException {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLogger.e('fetchVideoInfo failed', error, stackTrace);
      throw YtdlpException(AppStrings.errorUnknown, originalError: error);
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
        return YtdlpPlatformChannel.isPlaylist(url);
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
      throw YtdlpException(AppStrings.errorUnknown, originalError: error);
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
  Future<_YtdlpResult> _runProcess(List<String> arguments) async {
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
      ).timeout(const Duration(seconds: 30));
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

  /// Ensures a single `-J` JSON payload is available for [url] on this service.
  Future<String> _ensureSingleVideoJson(String url) async {
    if (_metadataJsonUrl == url && _metadataJsonBody != null) {
      AppLogger.d('Reusing in-memory yt-dlp JSON for the current URL');
      return _metadataJsonBody!;
    }
    if (Platform.isAndroid) {
      _validateUrl(url);
      final String body = await YtdlpPlatformChannel.fetchFormats(url);
      if (body.trim().isEmpty) {
        throw const YtdlpException(AppStrings.errorProcessFailed);
      }
      _metadataJsonUrl = url;
      _metadataJsonBody = body;
      return body;
    }
    _validateUrl(url);
    final _YtdlpResult result = await _runProcess(<String>[
      '-J',
      '--no-playlist',
      '--no-warnings',
      url,
    ]);
    if (!result.isSuccess) {
      final String msg = result.stderr.trim().isNotEmpty
          ? result.stderr.trim()
          : AppStrings.errorProcessFailed;
      throw YtdlpException(msg);
    }
    final String body = result.stdout;
    if (body.trim().isEmpty) {
      throw const YtdlpException(AppStrings.errorProcessFailed);
    }
    _metadataJsonUrl = url;
    _metadataJsonBody = body;
    return body;
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
