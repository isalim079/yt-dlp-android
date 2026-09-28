import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/exceptions/ytdlp_exception.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';

void main() {
  Map<String, dynamic> format({
    required String id,
    required String ext,
    String? url,
    int? height,
    String vcodec = 'none',
    String acodec = 'none',
    double? tbr,
    double? abr,
    String protocol = 'https',
  }) {
    return <String, dynamic>{
      'format_id': id,
      'ext': ext,
      'url': url,
      'height': height,
      'vcodec': vcodec,
      'acodec': acodec,
      'tbr': tbr,
      'abr': abr,
      'protocol': protocol,
    };
  }

  String payload(List<Map<String, dynamic>> formats, {bool live = false}) {
    return jsonEncode(<String, dynamic>{
      'title': 'Demo',
      'webpage_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'thumbnail': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      'duration': 100,
      'uploader': 'Channel',
      'is_live': live,
      'http_headers': <String, String>{'User-Agent': 'test-ua'},
      'formats': formats,
    });
  }

  group('PlaybackResolver', () {
    test('picks adaptive video+audio under quality cap', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '137',
          ext: 'mp4',
          url:
              'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
          height: 1080,
          vcodec: 'avc1',
          tbr: 4000,
        ),
        format(
          id: '136',
          ext: 'mp4',
          url:
              'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=136',
          height: 720,
          vcodec: 'avc1',
          tbr: 2000,
        ),
        format(
          id: '140',
          ext: 'm4a',
          url:
              'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140',
          acodec: 'mp4a.40.2',
          abr: 128,
        ),
        format(
          id: '22',
          ext: 'mp4',
          url:
              'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=22',
          height: 720,
          vcodec: 'avc1',
          acodec: 'mp4a.40.2',
          tbr: 2500,
        ),
      ]);

      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: PlaybackQuality.p720,
      );
      expect(resolved.mode, PlaybackMode.adaptive);
      expect(resolved.height, 720);
      expect(resolved.videoUrl, contains('itag=136'));
      expect(resolved.audioUrl, contains('itag=140'));
      expect(resolved.progressiveUrl, contains('itag=22'));
      expect(resolved.hasSeparateAudio, isTrue);
      expect(resolved.headers['User-Agent'], 'test-ua');
    });

    test('falls back to progressive when no adaptive pair', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '18',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999',
          height: 360,
          vcodec: 'avc1',
          acodec: 'mp4a.40.2',
          tbr: 500,
        ),
      ]);
      final PlaybackResolved resolved = PlaybackResolver.fromJson(json);
      expect(resolved.mode, PlaybackMode.progressive);
      expect(resolved.primaryUrl, contains('googlevideo'));
    });

    test('uses HLS for livestreams', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '91',
          ext: 'mp4',
          url: 'https://manifest.googlevideo.com/api/manifest/hls_playlist/x.m3u8',
          height: 360,
          vcodec: 'avc1',
          acodec: 'mp4a.40.2',
          protocol: 'm3u8_native',
        ),
      ], live: true);
      final PlaybackResolved resolved = PlaybackResolver.fromJson(json);
      expect(resolved.mode, PlaybackMode.hls);
      expect(resolved.hlsUrl, contains('.m3u8'));
    });

    test('prefers 1080p H.264 over 4K AV1 for Auto', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '401',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=401',
          height: 2160,
          vcodec: 'av01.0.16M.08',
          tbr: 12000,
        ),
        format(
          id: '137',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
          height: 1080,
          vcodec: 'avc1.640028',
          tbr: 4000,
        ),
        format(
          id: '140',
          ext: 'm4a',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140',
          acodec: 'mp4a.40.2',
          abr: 128,
        ),
      ]);
      final PlaybackResolved resolved = PlaybackResolver.fromJson(json);
      expect(resolved.mode, PlaybackMode.adaptive);
      expect(resolved.height, 1080);
      expect(resolved.videoUrl, contains('itag=137'));
    });

    test('throws when nothing is playable', () {
      final String json = payload(<Map<String, dynamic>>[
        format(id: 'sb0', ext: 'mhtml', vcodec: 'none'),
      ]);
      expect(
        () => PlaybackResolver.fromJson(json),
        throwsA(isA<YtdlpException>()),
      );
    });
  });
}
