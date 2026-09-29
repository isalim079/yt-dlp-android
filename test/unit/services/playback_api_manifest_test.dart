import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_manifest.dart';
import 'package:yxz_tube/data/services/api/api_exception.dart';

void main() {
  group('PlaybackManifest.fromJson', () {
    test('maps direct delivery and quality contract', () {
      final PlaybackManifest m = PlaybackManifest.fromJson(<String, dynamic>{
        'schemaVersion': 1,
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Demo',
        'source': 'youtube',
        'delivery': <String, dynamic>{'type': 'direct'},
        'videoStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '137',
            'url': 'https://example.com/v.mp4',
            'height': 1080,
            'isVideoOnly': true,
            'codec': 'avc1',
          },
        ],
        'audioStreams': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '140',
            'url': 'https://example.com/a.m4a',
            'codec': 'mp4a',
          },
        ],
        'headers': <String, String>{'Referer': 'https://www.youtube.com/'},
        'quality': <String, dynamic>{
          'requestedQuality': '1080p',
          'selectedQuality': '1080p',
          'qualityFallback': false,
        },
      });
      expect(m.delivery.type, PlaybackDeliveryType.adaptiveDirect);
      expect(m.isPlayable, isTrue);
      expect(m.quality?.selectedQuality, '1080p');
    });
  });

  group('classifyApiFailure', () {
    test('geo is restricted — no local fallback', () {
      final ApiFailureKind k = classifyApiFailure(
        statusCode: 451,
        code: 'EXTRACTOR_GEO_BLOCKED',
      );
      expect(k, ApiFailureKind.restricted);
      expect(
        ApiException(
          code: 'EXTRACTOR_GEO_BLOCKED',
          message: 'geo',
          kind: k,
        ).allowsLocalFallback,
        isFalse,
      );
    });

    test('5xx is transport — allows local fallback', () {
      final ApiFailureKind k = classifyApiFailure(
        statusCode: 503,
        code: 'INTERNAL_ERROR',
      );
      expect(k, ApiFailureKind.transport);
    });
  });
}
