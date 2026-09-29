/// Builds [PlaybackManifest] from yt-dlp `-J` JSON (on-device extractor adapter).
library;

import 'dart:convert';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/playback_manifest.dart';
import 'format_parser.dart';

/// Pure mapper: extractor JSON → application manifest. No yt-dlp process.
abstract final class PlaybackManifestBuilder {
  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  /// Parses a full yt-dlp dump into [PlaybackManifest].
  static PlaybackManifest fromYtDlpJson(String jsonString) {
    late final Map<String, dynamic> root;
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        throw const YtdlpException(AppStrings.errorParseVideoInformation);
      }
      root = Map<String, dynamic>.from(decoded);
    } on FormatException catch (e) {
      throw YtdlpException(
        AppStrings.errorParseVideoInformation,
        originalError: e,
      );
    }

    final info = FormatParser.parseVideoInfo(jsonString);
    final String videoId = YoutubeUrls.videoId(info.url) ??
        root['id']?.toString() ??
        '';
    final Map<String, String> headers = _mergeHeaders(root);
    final List<Map<String, dynamic>> formats = _formats(root);

    final List<VideoRepresentation> videos = <VideoRepresentation>[];
    final List<AudioRepresentation> audios = <AudioRepresentation>[];
    String? hlsUrl;
    DateTime? earliestExpire;

    for (final Map<String, dynamic> row in formats) {
      final String? url = _urlOf(row);
      if (url == null) {
        continue;
      }
      if (_isStoryboard(row)) {
        continue;
      }
      final String protocol = (row['protocol']?.toString() ?? '').toLowerCase();
      final String ext = (row['ext']?.toString() ?? '').toLowerCase();
      if (protocol.contains('m3u8') || ext == 'm3u8') {
        hlsUrl ??= url;
        earliestExpire = _earlier(earliestExpire, _expireOf(url));
        continue;
      }
      if (!url.startsWith('http')) {
        continue;
      }

      final String vcodec = (row['vcodec']?.toString() ?? '').toLowerCase();
      final String acodec = (row['acodec']?.toString() ?? '').toLowerCase();
      final bool hasV = vcodec.isNotEmpty && vcodec != 'none';
      final bool hasA = acodec.isNotEmpty && acodec != 'none';
      final String id = row['format_id']?.toString() ?? '';
      if (id.isEmpty) {
        continue;
      }

      earliestExpire = _earlier(earliestExpire, _expireOf(url));

      if (hasV && !hasA) {
        final int height = _readInt(row['height']) ?? 0;
        if (height <= 0) {
          continue;
        }
        videos.add(
          VideoRepresentation(
            id: id,
            url: url,
            height: height,
            width: _readInt(row['width']),
            fps: _readInt(row['fps']),
            bitrate: _bitrate(row),
            codec: row['vcodec']?.toString(),
            mimeType: _mimeVideo(ext),
            ext: ext.isEmpty ? null : ext,
            isVideoOnly: true,
            hdr: _isHdr(row),
          ),
        );
      } else if (hasV && hasA) {
        final int height = _readInt(row['height']) ?? 0;
        if (height <= 0) {
          continue;
        }
        videos.add(
          VideoRepresentation(
            id: id,
            url: url,
            height: height,
            width: _readInt(row['width']),
            fps: _readInt(row['fps']),
            bitrate: _bitrate(row),
            codec: row['vcodec']?.toString(),
            mimeType: _mimeVideo(ext),
            ext: ext.isEmpty ? null : ext,
            isVideoOnly: false,
            hdr: _isHdr(row),
          ),
        );
      } else if (!hasV && hasA) {
        audios.add(
          AudioRepresentation(
            id: id,
            url: url,
            bitrate: _audioBitrate(row),
            codec: row['acodec']?.toString(),
            mimeType: _mimeAudio(ext),
            ext: ext.isEmpty ? null : ext,
            sampleRate: _readInt(row['asr']),
            channels: _readInt(row['audio_channels']),
          ),
        );
      }
    }

    final bool isLive =
        root['is_live'] == true || root['live_status'] == 'is_live';
    final PlaybackDelivery delivery;
    if (isLive && hlsUrl != null) {
      delivery = PlaybackDelivery(
        type: PlaybackDeliveryType.hls,
        manifestUrl: hlsUrl,
      );
    } else if (videos.any((VideoRepresentation v) => v.isVideoOnly) &&
        audios.isNotEmpty) {
      delivery = const PlaybackDelivery(
        type: PlaybackDeliveryType.adaptiveDirect,
      );
    } else if (videos.any((VideoRepresentation v) => !v.isVideoOnly)) {
      delivery = const PlaybackDelivery(
        type: PlaybackDeliveryType.progressive,
      );
    } else if (hlsUrl != null) {
      delivery = PlaybackDelivery(
        type: PlaybackDeliveryType.hls,
        manifestUrl: hlsUrl,
      );
    } else {
      delivery = const PlaybackDelivery(
        type: PlaybackDeliveryType.progressive,
      );
    }

    final int? durationMs = info.duration != null
        ? info.duration! * 1000
        : null;

    return PlaybackManifest(
      schemaVersion: 1,
      videoId: videoId,
      title: info.title,
      source: 'youtube',
      delivery: delivery,
      videoStreams: videos,
      audioStreams: audios,
      headers: headers,
      durationMs: durationMs,
      expiresAt: earliestExpire,
      uploader: info.uploader,
      thumbnail: info.thumbnail,
      webpageUrl: info.url,
    );
  }

  static List<Map<String, dynamic>> _formats(Map<String, dynamic> root) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    final List<dynamic>? raw = root['formats'] as List<dynamic>?;
    if (raw == null) {
      return out;
    }
    for (final dynamic row in raw) {
      if (row is Map) {
        out.add(Map<String, dynamic>.from(row));
      }
    }
    return out;
  }

  static Map<String, String> _mergeHeaders(Map<String, dynamic> root) {
    final Map<String, String> headers = Map<String, String>.from(_defaultHeaders);
    final Object? raw = root['http_headers'];
    if (raw is Map) {
      raw.forEach((Object? key, Object? value) {
        if (key != null && value != null) {
          headers[key.toString()] = value.toString();
        }
      });
    }
    return headers;
  }

  static String? _urlOf(Map<String, dynamic> row) {
    final String? url = row['url']?.toString();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  static bool _isStoryboard(Map<String, dynamic> row) {
    final String note = (row['format_note']?.toString() ?? '').toLowerCase();
    final String formatId = (row['format_id']?.toString() ?? '').toLowerCase();
    return note.contains('storyboard') || formatId.contains('sb');
  }

  static bool _isHdr(Map<String, dynamic> row) {
    final String note = (row['format_note']?.toString() ?? '').toLowerCase();
    final String dyn = (row['dynamic_range']?.toString() ?? '').toLowerCase();
    return note.contains('hdr') || dyn.contains('hdr');
  }

  static int? _readInt(Object? value) {
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _bitrate(Map<String, dynamic> row) {
    final double? tbr = _readDouble(row['tbr']);
    if (tbr != null && tbr > 0) {
      return (tbr * 1000).round();
    }
    final int? vbr = _readInt(row['vbr']);
    if (vbr != null && vbr > 0) {
      return vbr * 1000;
    }
    return null;
  }

  static int? _audioBitrate(Map<String, dynamic> row) {
    final double? abr = _readDouble(row['abr']) ?? _readDouble(row['tbr']);
    if (abr != null && abr > 0) {
      return (abr * 1000).round();
    }
    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String? _mimeVideo(String ext) {
    return switch (ext) {
      'mp4' => 'video/mp4',
      'webm' => 'video/webm',
      _ => null,
    };
  }

  static String? _mimeAudio(String ext) {
    return switch (ext) {
      'm4a' || 'mp4' => 'audio/mp4',
      'webm' => 'audio/webm',
      _ => null,
    };
  }

  static DateTime? _expireOf(String url) {
    final RegExpMatch? m = RegExp(r'[?&]expire=(\d+)').firstMatch(url);
    if (m == null) {
      return null;
    }
    final int? epoch = int.tryParse(m.group(1)!);
    if (epoch == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  }

  static DateTime? _earlier(DateTime? a, DateTime? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.isBefore(b) ? a : b;
  }
}
