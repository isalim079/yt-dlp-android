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

    test('explicit 1080p prefers 1080 VP9 over 360 H.264', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '248',
          ext: 'webm',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=248',
          height: 1080,
          vcodec: 'vp9',
          tbr: 3000,
        ),
        format(
          id: '18',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18',
          height: 360,
          vcodec: 'avc1',
          acodec: 'mp4a.40.2',
          tbr: 500,
        ),
        format(
          id: '140',
          ext: 'm4a',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140',
          acodec: 'mp4a.40.2',
          abr: 128,
        ),
      ]);
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: PlaybackQuality.p1080,
      );
      expect(resolved.mode, PlaybackMode.adaptive);
      expect(resolved.height, 1080);
      expect(resolved.videoUrl, contains('itag=248'));
    });

    test('explicit 1080p prefers H.264 over VP9 at the same height', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '248',
          ext: 'webm',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=248',
          height: 1080,
          vcodec: 'vp9',
          tbr: 5000,
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
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: PlaybackQuality.p1080,
      );
      expect(resolved.height, 1080);
      expect(resolved.videoUrl, contains('itag=137'));
    });

    test('explicit 1440p picks 1440 when present', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '271',
          ext: 'webm',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=271',
          height: 1440,
          vcodec: 'vp9',
          tbr: 6000,
        ),
        format(
          id: '137',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
          height: 1080,
          vcodec: 'avc1',
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
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: PlaybackQuality.p1440,
      );
      expect(resolved.height, 1440);
      expect(resolved.videoUrl, contains('itag=271'));
      expect(resolved.offersQuality(PlaybackQuality.p1440), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p2160), isFalse);
      expect(playbackNeedsExtraClient(resolved), isFalse);
    });

    test('1440 request plays 1080 from JSON when no 1440 HTTPS exists', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '137',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
          height: 1080,
          vcodec: 'avc1',
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
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        json,
        quality: PlaybackQuality.p1440,
      );
      expect(resolved.height, 1080);
      expect(playbackNeedsExtraClient(resolved), isFalse);
    });

    test('needs extra client only when JSON has no HD HTTP URLs', () {
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
      expect(resolved.height, 360);
      expect(playbackNeedsExtraClient(resolved), isTrue);
      expect(playbackMaxAvailableHeight(resolved), 360);
    });

    test('full HTTPS ladder offers 480 through 2160', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '401',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=401',
          height: 2160,
          vcodec: 'av01',
          tbr: 12000,
        ),
        format(
          id: '271',
          ext: 'webm',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=271',
          height: 1440,
          vcodec: 'vp9',
          tbr: 6000,
        ),
        format(
          id: '137',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
          height: 1080,
          vcodec: 'avc1',
          tbr: 4000,
        ),
        format(
          id: '136',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=136',
          height: 720,
          vcodec: 'avc1',
          tbr: 2000,
        ),
        format(
          id: '135',
          ext: 'mp4',
          url: 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=135',
          height: 480,
          vcodec: 'avc1',
          tbr: 1000,
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
      expect(resolved.offersQuality(PlaybackQuality.p2160), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p1440), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p1080), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p720), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p480), isTrue);
      expect(playbackNeedsExtraClient(resolved), isFalse);
      expect(playbackMaxAvailableHeight(resolved), 2160);
    });

    test('SABR formats without a URL do not unlock HD in the picker', () {
      final String json = payload(<Map<String, dynamic>>[
        format(
          id: '401',
          ext: 'mp4',
          height: 2160,
          vcodec: 'av01',
          tbr: 12000,
        ),
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
      expect(resolved.offersQuality(PlaybackQuality.p2160), isFalse);
      expect(resolved.offersQuality(PlaybackQuality.p360), isTrue);
      expect(playbackNeedsExtraClient(resolved), isTrue);
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
