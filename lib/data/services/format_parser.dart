/// Responsible for parsing raw yt-dlp JSON output into clean Dart models.
library;

import 'dart:convert';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';

/// Converts raw yt-dlp format payloads into typed models.
///
/// Never runs any process — only parses data.
abstract final class FormatParser {
  /// Parses the full JSON string from yt-dlp `-J` output.
  ///
  /// Returns a deduplicated, cleaned list of [VideoFormat] rows.
  static List<VideoFormat> parseFormats(String jsonString) {
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const YtdlpException(AppStrings.errorParseVideoInformation);
      }
      final List<dynamic>? rawFormats = decoded['formats'] as List<dynamic>?;
      if (rawFormats == null) {
        return <VideoFormat>[];
      }
      final List<VideoFormat> parsed = <VideoFormat>[];
      for (final dynamic row in rawFormats) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        if (_shouldDropFormat(row)) {
          continue;
        }
        final String? fid = row['format_id']?.toString();
        if (fid == null || fid.isEmpty) {
          continue;
        }
        parsed.add(_parseFormat(row));
      }
      final List<VideoFormat> deduped = _dedupeByResolution(parsed);
      return _sortFormats(deduped);
    } on FormatException catch (e) {
      throw YtdlpException(
        AppStrings.errorParseVideoInformation,
        originalError: e,
      );
    }
  }

  /// Extracts video metadata from the same yt-dlp `-J` JSON output.
  static VideoInfo parseVideoInfo(String jsonString) {
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const YtdlpException(AppStrings.errorParseVideoInformation);
      }
      final Map<String, dynamic> m = decoded;
      final String title = m['title']?.toString() ?? '';
      final String url =
          m['webpage_url']?.toString() ??
          m['original_url']?.toString() ??
          m['url']?.toString() ??
          '';
      final String? thumb = _pickThumbnail(m);
      final int? duration = _readInt(m['duration']);
      final String? uploader = m['uploader']?.toString();
      final String? uploadDate = m['upload_date']?.toString();
      final int? views = _readInt(m['view_count']);
      return VideoInfo(
        title: title,
        url: url,
        thumbnail: thumb,
        duration: duration,
        uploader: uploader,
        uploadDate: uploadDate,
        viewCount: views,
      );
    } on FormatException catch (e) {
      throw YtdlpException(
        AppStrings.errorParseVideoInformation,
        originalError: e,
      );
    }
  }

  /// Parses flat playlist JSON from yt-dlp `--flat-playlist` output.
  static PlaylistInfo parsePlaylistInfo(String jsonString) {
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const YtdlpException(AppStrings.errorParseVideoInformation);
      }
      final Map<String, dynamic> m = decoded;
      final String title = m['title']?.toString() ?? '';
      final String url =
          m['webpage_url']?.toString() ??
          m['original_url']?.toString() ??
          m['url']?.toString() ??
          '';
      final int count =
          _readInt(m['playlist_count']) ??
          (m['entries'] is List ? (m['entries'] as List).length : 0);
      final List<PlaylistEntry> entries = <PlaylistEntry>[];
      final List<dynamic>? raw = m['entries'] as List<dynamic>?;
      if (raw != null) {
        for (final dynamic e in raw) {
          if (e is! Map<String, dynamic>) {
            continue;
          }
          final String et = e['title']?.toString() ?? '';
          final String eu =
              e['url']?.toString() ?? e['webpage_url']?.toString() ?? '';
          if (eu.isEmpty) {
            continue;
          }
          entries.add(PlaylistEntry(title: et, url: eu));
        }
      }
      return PlaylistInfo(
        title: title,
        count: count,
        entries: entries,
        url: url,
      );
    } on FormatException catch (e) {
      throw YtdlpException(
        AppStrings.errorParseVideoInformation,
        originalError: e,
      );
    }
  }

  /// Maps a single format JSON map to a [VideoFormat].
  static VideoFormat _parseFormat(Map<String, dynamic> json) {
    final String formatId = json['format_id']?.toString() ?? '';
    final String extension = json['ext']?.toString() ?? '';

    final String vcodec = json['vcodec']?.toString() ?? '';
    final bool isAudioOnly =
        vcodec.isEmpty || vcodec == 'none' || vcodec == 'audio only';

    final int? height = _readInt(json['height']);
    final String? resolution = height != null && height > 0
        ? '$height${AppStrings.formatVideoSuffix}'
        : (json['resolution']?.toString().isNotEmpty == true
              ? json['resolution']?.toString()
              : null);

    final dynamic rawFps = json['fps'];
    final int? fps = rawFps is num ? rawFps.round() : null;

    final int? fileSize =
        _readInt(json['filesize']) ?? _readInt(json['filesize_approx']);

    final dynamic rawAbr = json['abr'];
    final double? audioBitrate = rawAbr is num ? rawAbr.toDouble() : null;

    final String displayLabel = _buildDisplayLabel(
      extension: extension,
      resolution: resolution,
      isAudioOnly: isAudioOnly,
      fileSize: fileSize,
      audioBitrate: audioBitrate,
    );

    return VideoFormat(
      formatId: formatId,
      extension: extension,
      displayLabel: displayLabel,
      resolution: resolution,
      fps: fps,
      fileSize: fileSize,
      isAudioOnly: isAudioOnly,
      audioBitrate: audioBitrate,
    );
  }

  static bool _shouldDropFormat(Map<String, dynamic> row) {
    final String ext = row['ext']?.toString().toLowerCase() ?? '';
    if (ext == 'mhtml' || ext == 'none') {
      return true;
    }
    final String? proto = row['protocol']?.toString().toLowerCase();
    if (proto == 'mhtml') {
      return true;
    }
    final String note = row['format_note']?.toString().toLowerCase() ?? '';
    if (note.contains('storyboard')) {
      return true;
    }
    final String vcodec = row['vcodec']?.toString().toLowerCase() ?? '';
    if (vcodec.contains('mjpeg') && note.contains('storyboard')) {
      return true;
    }
    return false;
  }

  static String _buildDisplayLabel({
    required String extension,
    required String? resolution,
    required bool isAudioOnly,
    required int? fileSize,
    required double? audioBitrate,
  }) {
    final String extLabel = extension.isEmpty ? '' : extension.toUpperCase();
    final String sep = AppStrings.formatLabelSeparator;
    if (isAudioOnly) {
      final String ab = audioBitrate != null
          ? '${audioBitrate.round()}kbps'
          : AppStrings.formatSizeUnknown;
      return '${AppStrings.formatAudioOnlyLabel} $extLabel$sep$ab';
    }
    final String res = resolution?.isNotEmpty == true
        ? resolution!
        : AppStrings.formatSizeUnknown;
    final String sizePart = fileSize != null
        ? '${AppStrings.formatApproximatePrefix}${_humanBytes(fileSize)}'
        : AppStrings.formatSizeUnknown;
    return '$res $extLabel$sep$sizePart';
  }

  static String _humanBytes(int bytes) {
    const int k = 1024;
    if (bytes < k) {
      return '$bytes${AppStrings.fileSizeUnitBytes}';
    }
    final double kb = bytes / k;
    if (kb < k) {
      return '${kb.toStringAsFixed(0)}${AppStrings.fileSizeUnitKb}';
    }
    final double mb = kb / k;
    if (mb < k) {
      return '${mb.toStringAsFixed(1)}${AppStrings.fileSizeUnitMb}';
    }
    final double gb = mb / k;
    return '${gb.toStringAsFixed(1)}${AppStrings.fileSizeUnitGb}';
  }

  static List<VideoFormat> _dedupeByResolution(List<VideoFormat> input) {
    final Map<String, VideoFormat> best = <String, VideoFormat>{};
    for (final VideoFormat f in input) {
      final String key = f.isAudioOnly
          ? 'a|${f.formatId}'
          : 'v|${_heightKey(f)}|${f.extension.toLowerCase()}';
      final VideoFormat? existing = best[key];
      if (existing == null) {
        best[key] = f;
        continue;
      }
      final int a = existing.fileSize ?? -1;
      final int b = f.fileSize ?? -1;
      if (b > a) {
        best[key] = f;
      }
    }
    return best.values.toList();
  }

  static int _heightKey(VideoFormat f) {
    if (f.resolution == null) {
      return -1;
    }
    final RegExpMatch? m = RegExp(r'(\d+)').firstMatch(f.resolution!);
    if (m == null) {
      return -1;
    }
    return int.tryParse(m.group(1)!) ?? -1;
  }

  static List<VideoFormat> _sortFormats(List<VideoFormat> list) {
    list.sort((VideoFormat a, VideoFormat b) {
      if (a.isAudioOnly != b.isAudioOnly) {
        return a.isAudioOnly ? 1 : -1;
      }
      if (!a.isAudioOnly) {
        final int ha = _heightKey(a);
        final int hb = _heightKey(b);
        if (ha != hb) {
          return hb.compareTo(ha);
        }
        final int sa = a.fileSize ?? -1;
        final int sb = b.fileSize ?? -1;
        return sb.compareTo(sa);
      }
      final double aa = a.audioBitrate ?? -1;
      final double ab = b.audioBitrate ?? -1;
      return ab.compareTo(aa);
    });
    return list;
  }

  static String? _pickThumbnail(Map<String, dynamic> m) {
    final String? t = m['thumbnail']?.toString();
    if (t != null && t.isNotEmpty) {
      return t;
    }
    final dynamic thumbs = m['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty) {
      final Object? last = thumbs.last;
      if (last is Map<String, dynamic>) {
        return last['url']?.toString();
      }
    }
    return null;
  }

  static int? _readInt(Object? v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return null;
  }
}
