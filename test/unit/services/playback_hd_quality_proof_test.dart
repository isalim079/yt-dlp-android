import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_manifest.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_manifest_builder.dart';
import 'package:yxz_tube/data/services/playback_manifest_selector.dart';

void main() {
  group('PlaybackManifestSelector HD', () {
    test('1080p prefers adaptive V+A at 1080', () {
      final PlaybackResolved r = PlaybackManifestSelector.select(
        PlaybackManifestBuilder.fromYtDlpJson(_json()),
        quality: PlaybackQuality.p1080,
      );
      expect(r.mode, PlaybackMode.adaptive);
      expect(r.height, 1080);
      expect(r.videoUrl, isNotNull);
      expect(r.audioUrl, isNotNull);
    });

    test('auto may select above 1080 when present', () {
      final PlaybackResolved r = PlaybackManifestSelector.select(
        PlaybackManifestBuilder.fromYtDlpJson(_json4k()),
        quality: PlaybackQuality.auto,
      );
      expect(r.height, greaterThanOrEqualTo(1080));
      expect(r.mode, PlaybackMode.adaptive);
    });

    test('2160p falls back honestly to 1440 when needed', () {
      final PlaybackResolved r = PlaybackManifestSelector.select(
        PlaybackManifestBuilder.fromYtDlpJson(_json1440Only()),
        quality: PlaybackQuality.p2160,
      );
      expect(r.height, 1440);
    });
  });

  group('PlaybackQualityContract', () {
    test('parses fallbackReason', () {
      final PlaybackManifest m = PlaybackManifest.fromJson(
        jsonDecode(_contractJson()) as Map<String, dynamic>,
      );
      expect(m.quality?.fallbackReason, 'NO_COMPATIBLE_2160P_STREAM');
      expect(m.quality?.qualityFallback, isTrue);
    });
  });
}

String _json() => jsonEncode(<String, dynamic>{
      'id': 'dQw4w9WgXcQ',
      'title': 'Demo',
      'webpage_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'duration': 100,
      'uploader': 'Ch',
      'formats': <Map<String, dynamic>>[
        <String, dynamic>{
          'format_id': '18',
          'ext': 'mp4',
          'url': 'https://rr.example/p?expire=1999999999',
          'height': 360,
          'vcodec': 'avc1',
          'acodec': 'mp4a.40.2',
          'protocol': 'https',
        },
        <String, dynamic>{
          'format_id': '137',
          'ext': 'mp4',
          'url': 'https://rr.example/v?expire=1999999999',
          'height': 1080,
          'vcodec': 'avc1.640028',
          'acodec': 'none',
          'tbr': 4000,
          'protocol': 'https',
        },
        <String, dynamic>{
          'format_id': '140',
          'ext': 'm4a',
          'url': 'https://rr.example/a?expire=1999999999',
          'vcodec': 'none',
          'acodec': 'mp4a.40.2',
          'abr': 128,
          'protocol': 'https',
        },
      ],
    });

String _json4k() => jsonEncode(<String, dynamic>{
      'id': 'dQw4w9WgXcQ',
      'title': 'Demo',
      'webpage_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'duration': 100,
      'uploader': 'Ch',
      'formats': <Map<String, dynamic>>[
        <String, dynamic>{
          'format_id': '313',
          'ext': 'webm',
          'url': 'https://rr.example/4k?expire=1999999999',
          'height': 2160,
          'vcodec': 'vp9',
          'acodec': 'none',
          'tbr': 20000,
          'protocol': 'https',
        },
        <String, dynamic>{
          'format_id': '140',
          'ext': 'm4a',
          'url': 'https://rr.example/a?expire=1999999999',
          'vcodec': 'none',
          'acodec': 'mp4a.40.2',
          'abr': 128,
          'protocol': 'https',
        },
      ],
    });

String _json1440Only() => jsonEncode(<String, dynamic>{
      'id': 'dQw4w9WgXcQ',
      'title': 'Demo',
      'webpage_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'duration': 100,
      'uploader': 'Ch',
      'formats': <Map<String, dynamic>>[
        <String, dynamic>{
          'format_id': '271',
          'ext': 'webm',
          'url': 'https://rr.example/1440?expire=1999999999',
          'height': 1440,
          'vcodec': 'vp9',
          'acodec': 'none',
          'protocol': 'https',
        },
        <String, dynamic>{
          'format_id': '140',
          'ext': 'm4a',
          'url': 'https://rr.example/a?expire=1999999999',
          'vcodec': 'none',
          'acodec': 'mp4a.40.2',
          'protocol': 'https',
        },
      ],
    });

String _contractJson() => jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'videoId': 'x',
      'title': 't',
      'source': 'youtube',
      'delivery': <String, String>{'type': 'direct'},
      'videoStreams': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': '1',
          'url': 'https://example.com/v',
          'height': 1440,
          'isVideoOnly': true,
        },
      ],
      'audioStreams': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'a',
          'url': 'https://example.com/a',
        },
      ],
      'headers': <String, String>{},
      'quality': <String, dynamic>{
        'requestedQuality': '2160p',
        'selectedQuality': '1440p',
        'qualityFallback': true,
        'fallbackReason': 'NO_COMPATIBLE_2160P_STREAM',
      },
    });
