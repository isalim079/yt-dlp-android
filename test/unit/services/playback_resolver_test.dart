import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/exceptions/ytdlp_exception.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';

void main() {
  group('PlaybackResolver quality selection', () {
    test('requests 360 and picks 360 when present', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _ladder(<int>[144, 240, 360, 720]),
        quality: PlaybackQuality.p360,
      );
      expect(resolved.height, 360);
      expect(resolved.mode, PlaybackMode.progressive);
    });

    test('requests 360 and picks closest below when 360 missing', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _ladder(<int>[144, 240, 720]),
        quality: PlaybackQuality.p360,
      );
      expect(resolved.height, 240);
    });

    test('requests 360 with only 720/1080 picks lowest above', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _ladder(<int>[720, 1080]),
        quality: PlaybackQuality.p360,
      );
      expect(resolved.isPlayable, isTrue);
      expect(resolved.height, 720);
    });

    test('progressive muxed preferred over adaptive for p360', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _progressiveAndAdaptive(),
        quality: PlaybackQuality.p360,
      );
      expect(resolved.mode, PlaybackMode.progressive);
      expect(resolved.progressiveUrl, isNotNull);
    });

    test('separate video+audio when no progressive', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _adaptiveOnly(),
        quality: PlaybackQuality.auto,
      );
      expect(resolved.mode, PlaybackMode.adaptive);
      expect(resolved.videoUrl, isNotNull);
      expect(resolved.audioUrl, isNotNull);
    });

    test('no usable formats throws', () {
      expect(
        () => PlaybackResolver.fromJson(
          jsonEncode(<String, dynamic>{
            'title': 'x',
            'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
            'formats': <Map<String, dynamic>>[
              <String, dynamic>{
                'format_id': 'sb0',
                'ext': 'mhtml',
                'url': 'https://example.com/sb',
                'vcodec': 'none',
                'acodec': 'none',
              },
            ],
          }),
          quality: PlaybackQuality.auto,
        ),
        throwsA(isA<YtdlpException>()),
      );
    });

    test('classifies acodec/vcodec none correctly', () {
      final PlaybackResolved resolved = PlaybackResolver.fromJson(
        _adaptiveOnly(),
        quality: PlaybackQuality.auto,
      );
      expect(resolved.hasSeparateAudio, isTrue);
      expect(resolved.mode, isNot(PlaybackMode.progressive));
    });
  });
}

String _ladder(List<int> heights) {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      for (final int h in heights)
        <String, dynamic>{
          'format_id': 'p$h',
          'ext': 'mp4',
          'url':
              'https://rr.googlevideo.com/videoplayback?expire=1999999999&h=$h',
          'height': h,
          'vcodec': 'avc1',
          'acodec': 'mp4a.40.2',
          'tbr': h.toDouble(),
          'protocol': 'https',
        },
    ],
  });
}

String _progressiveAndAdaptive() {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '18',
        'ext': 'mp4',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&p=1',
        'height': 360,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '137',
        'ext': 'mp4',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&v=1',
        'height': 1080,
        'vcodec': 'avc1',
        'acodec': 'none',
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&a=1',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'protocol': 'https',
      },
    ],
  });
}

String _adaptiveOnly() {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '136',
        'ext': 'mp4',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&v=1',
        'height': 720,
        'vcodec': 'avc1',
        'acodec': 'none',
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&a=1',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'protocol': 'https',
      },
    ],
  });
}
