/// Picks playable adaptive / progressive / HLS URLs from yt-dlp `-J` JSON.
library;

import 'dart:convert';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../models/playback_resolved.dart';
import '../models/video_info.dart';
import 'format_parser.dart';

/// Pure parser: JSON in, [PlaybackResolved] out. Never runs yt-dlp.
abstract final class PlaybackResolver {
  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  /// Resolves streams for [quality] from a full yt-dlp `-J` body.
  static PlaybackResolved fromJson(
    String jsonString, {
    PlaybackQuality quality = PlaybackQuality.auto,
  }) {
    late final Map<String, dynamic> root;
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const YtdlpException(AppStrings.errorParseVideoInformation);
      }
      root = decoded;
    } on FormatException catch (e) {
      throw YtdlpException(
        AppStrings.errorParseVideoInformation,
        originalError: e,
      );
    }

    final VideoInfo info = FormatParser.parseVideoInfo(jsonString);
    final Map<String, String> headers = _mergeHeaders(root);
    final bool isLive = root['is_live'] == true || root['live_status'] == 'is_live';
    final List<Map<String, dynamic>> formats = _formats(root);

    final String? hls = _pickHls(formats, root);
    if (isLive && hls != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.hls,
        headers: headers,
        quality: quality,
        hlsUrl: hls,
        progressiveUrl: _pickProgressive(formats, quality)?.url,
        expiresAt: _expireOf(hls),
        formatId: 'hls',
      );
    }

    final _Picked? video = _pickVideoOnly(formats, quality);
    final _Picked? audio = _pickAudioOnly(formats);
    final _Picked? progressive = _pickProgressive(formats, quality);

    if (video != null && audio != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.adaptive,
        headers: headers,
        quality: quality,
        videoUrl: video.url,
        audioUrl: audio.url,
        progressiveUrl: progressive?.url,
        hlsUrl: hls,
        height: video.height,
        expiresAt: _earliestExpire(<String?>[video.url, audio.url]),
        formatId: video.formatId,
      );
    }

    if (progressive != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.progressive,
        headers: headers,
        quality: quality,
        progressiveUrl: progressive.url,
        hlsUrl: hls,
        height: progressive.height,
        expiresAt: _expireOf(progressive.url),
        formatId: progressive.formatId,
      );
    }

    if (hls != null) {
      return PlaybackResolved(
        info: info,
        mode: PlaybackMode.hls,
        headers: headers,
        quality: quality,
        hlsUrl: hls,
        expiresAt: _expireOf(hls),
        formatId: 'hls',
      );
    }

    throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
  }

  static List<Map<String, dynamic>> _formats(Map<String, dynamic> root) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    final List<dynamic>? raw = root['formats'] as List<dynamic>?;
    if (raw == null) {
      return out;
    }
    for (final dynamic row in raw) {
      if (row is Map<String, dynamic>) {
        out.add(row);
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

  static _Picked? _pickVideoOnly(
    List<Map<String, dynamic>> formats,
    PlaybackQuality quality,
  ) {
    final int? maxH = quality.maxHeight;
    final List<_Picked> candidates = <_Picked>[];
    for (final Map<String, dynamic> row in formats) {
      if (!_hasDirectUrl(row)) {
        continue;
      }
      if (_isStoryboard(row)) {
        continue;
      }
      final String vcodec = (row['vcodec']?.toString() ?? '').toLowerCase();
      final String acodec = (row['acodec']?.toString() ?? '').toLowerCase();
      if (vcodec.isEmpty || vcodec == 'none') {
        continue;
      }
      if (acodec.isNotEmpty && acodec != 'none') {
        continue;
      }
      final int height = _readInt(row['height']) ?? 0;
      if (maxH != null && height > maxH) {
        continue;
      }
      if (height <= 0) {
        continue;
      }
      candidates.add(
        _Picked(
          url: _urlOf(row)!,
          height: height,
          formatId: row['format_id']?.toString() ?? '',
          ext: row['ext']?.toString() ?? '',
          tbr: _readDouble(row['tbr']) ?? 0,
          vcodec: vcodec,
        ),
      );
    }
    return _bestVideo(candidates, quality);
  }

  static _Picked? _pickAudioOnly(List<Map<String, dynamic>> formats) {
    final List<_Picked> candidates = <_Picked>[];
    for (final Map<String, dynamic> row in formats) {
      if (!_hasDirectUrl(row)) {
        continue;
      }
      final String vcodec = (row['vcodec']?.toString() ?? '').toLowerCase();
      final String acodec = (row['acodec']?.toString() ?? '').toLowerCase();
      final bool audioOnly =
          vcodec.isEmpty || vcodec == 'none' || vcodec == 'audio only';
      if (!audioOnly || acodec.isEmpty || acodec == 'none') {
        continue;
      }
      candidates.add(
        _Picked(
          url: _urlOf(row)!,
          height: 0,
          formatId: row['format_id']?.toString() ?? '',
          ext: row['ext']?.toString() ?? '',
          tbr: _readDouble(row['abr']) ?? _readDouble(row['tbr']) ?? 0,
          vcodec: vcodec,
        ),
      );
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((_Picked a, _Picked b) {
      final int extScore = _audioExtScore(b.ext).compareTo(_audioExtScore(a.ext));
      if (extScore != 0) {
        return extScore;
      }
      return b.tbr.compareTo(a.tbr);
    });
    return candidates.first;
  }

  static _Picked? _pickProgressive(
    List<Map<String, dynamic>> formats,
    PlaybackQuality quality,
  ) {
    final int? maxH = quality.maxHeight;
    final List<_Picked> candidates = <_Picked>[];
    for (final Map<String, dynamic> row in formats) {
      if (!_hasDirectUrl(row)) {
        continue;
      }
      if (_isStoryboard(row)) {
        continue;
      }
      final String vcodec = (row['vcodec']?.toString() ?? '').toLowerCase();
      final String acodec = (row['acodec']?.toString() ?? '').toLowerCase();
      if (vcodec.isEmpty || vcodec == 'none') {
        continue;
      }
      if (acodec.isEmpty || acodec == 'none') {
        continue;
      }
      final int height = _readInt(row['height']) ?? 0;
      if (maxH != null && height > maxH) {
        continue;
      }
      candidates.add(
        _Picked(
          url: _urlOf(row)!,
          height: height,
          formatId: row['format_id']?.toString() ?? '',
          ext: row['ext']?.toString() ?? '',
          tbr: _readDouble(row['tbr']) ?? 0,
          vcodec: vcodec,
        ),
      );
    }
    return _bestVideo(candidates, quality);
  }

  /// Prefers H.264 at or under 1080p for Auto so 4K AV1/HDR does not black-screen.
  static _Picked? _bestVideo(
    List<_Picked> candidates,
    PlaybackQuality quality,
  ) {
    if (candidates.isEmpty) {
      return null;
    }
    List<_Picked> pool = candidates;
    if (quality == PlaybackQuality.auto) {
      final List<_Picked> capped = candidates
          .where((_Picked c) => c.height <= 1080)
          .toList();
      if (capped.isNotEmpty) {
        pool = capped;
      }
    }
    pool.sort((_Picked a, _Picked b) {
      final int codec = _videoCodecScore(
        b.vcodec,
      ).compareTo(_videoCodecScore(a.vcodec));
      if (codec != 0) {
        return codec;
      }
      if (a.height != b.height) {
        return b.height.compareTo(a.height);
      }
      final int extScore = _extScore(b.ext).compareTo(_extScore(a.ext));
      if (extScore != 0) {
        return extScore;
      }
      return b.tbr.compareTo(a.tbr);
    });
    return pool.first;
  }

  static String? _pickHls(
    List<Map<String, dynamic>> formats,
    Map<String, dynamic> root,
  ) {
    final String? manifest = root['manifest_url']?.toString();
    if (manifest != null && manifest.contains('.m3u8')) {
      return manifest;
    }
    for (final Map<String, dynamic> row in formats) {
      final String proto = (row['protocol']?.toString() ?? '').toLowerCase();
      final String url = _urlOf(row) ?? '';
      if (proto.contains('m3u8') || url.contains('.m3u8')) {
        if (url.isNotEmpty) {
          return url;
        }
      }
      final String? man = row['manifest_url']?.toString();
      if (man != null && man.contains('.m3u8')) {
        return man;
      }
    }
    return null;
  }

  static bool _hasDirectUrl(Map<String, dynamic> row) {
    return _urlOf(row) != null;
  }

  static String? _urlOf(Map<String, dynamic> row) {
    final String? url = row['url']?.toString();
    if (url != null && url.startsWith('http')) {
      return url;
    }
    return null;
  }

  static bool _isStoryboard(Map<String, dynamic> row) {
    final String ext = (row['ext']?.toString() ?? '').toLowerCase();
    if (ext == 'mhtml') {
      return true;
    }
    final String note = (row['format_note']?.toString() ?? '').toLowerCase();
    return note.contains('storyboard');
  }

  static int _videoCodecScore(String vcodec) {
    final String c = vcodec.toLowerCase();
    if (c.contains('avc') || c.contains('h264')) {
      return 5;
    }
    if (c.contains('vp9') || c.contains('vp09')) {
      return 3;
    }
    if (c.contains('av01') || c.contains('av1')) {
      return 1;
    }
    return 2;
  }

  static int _extScore(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp4':
        return 3;
      case 'webm':
        return 2;
      default:
        return 1;
    }
  }

  static int _audioExtScore(String ext) {
    switch (ext.toLowerCase()) {
      case 'm4a':
        return 3;
      case 'webm':
        return 2;
      default:
        return 1;
    }
  }

  static DateTime? _expireOf(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    final String? raw = uri.queryParameters['expire'];
    if (raw == null) {
      return null;
    }
    final int? seconds = int.tryParse(raw);
    if (seconds == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
        .toLocal();
  }

  static DateTime? _earliestExpire(List<String?> urls) {
    DateTime? earliest;
    for (final String? url in urls) {
      final DateTime? exp = _expireOf(url);
      if (exp == null) {
        continue;
      }
      if (earliest == null || exp.isBefore(earliest)) {
        earliest = exp;
      }
    }
    return earliest;
  }

  static int? _readInt(Object? v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse(v?.toString() ?? '');
  }

  static double? _readDouble(Object? v) {
    if (v is num) {
      return v.toDouble();
    }
    return double.tryParse(v?.toString() ?? '');
  }
}

class _Picked {
  const _Picked({
    required this.url,
    required this.height,
    required this.formatId,
    required this.ext,
    required this.tbr,
    this.vcodec = '',
  });

  final String url;
  final int height;
  final String formatId;
  final String ext;
  final double tbr;
  final String vcodec;
}
