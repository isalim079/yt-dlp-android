import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_manifest.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_manifest_builder.dart';
import 'package:yxz_tube/data/services/playback_manifest_selector.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';

void main() {
  group('PlaybackManifestBuilder', () {
    test('normalizes adaptive 1080 + audio + progressive 360', () {
      final PlaybackManifest m =
          PlaybackManifestBuilder.fromYtDlpJson(_json1080Adaptive());
      expect(m.schemaVersion, 1);
      expect(m.videoId, 'dQw4w9WgXcQ');
      expect(m.delivery.type, PlaybackDeliveryType.adaptiveDirect);
      expect(m.adaptiveVideo.map((VideoRepresentation v) => v.height),
          contains(1080));
      expect(m.audioStreams, isNotEmpty);
      expect(m.progressiveVideo.map((VideoRepresentation v) => v.height),
          contains(360));
      expect(m.availableHeights, containsAll(<int>[360, 720, 1080]));
    });
  });

  group('PlaybackManifestSelector', () {
    test('p1080 selects adaptive video+audio at 1080', () {
      final PlaybackManifest m =
          PlaybackManifestBuilder.fromYtDlpJson(_json1080Adaptive());
      final PlaybackResolved r = PlaybackManifestSelector.select(
        m,
        quality: PlaybackQuality.p1080,
      );
      expect(r.mode, PlaybackMode.adaptive);
      expect(r.height, 1080);
      expect(r.videoUrl, contains('itag=137'));
      expect(r.audioUrl, contains('itag=140'));
    });

    test('auto prefers H.264 adaptive ≤ 1080', () {
      final PlaybackResolved r = PlaybackResolver.fromJson(
        _json1080Adaptive(),
        quality: PlaybackQuality.auto,
      );
      expect(r.mode, PlaybackMode.adaptive);
      expect(r.height, lessThanOrEqualTo(1080));
      expect(r.videoUrl, isNotNull);
      expect(r.audioUrl, isNotNull);
    });
  });
}

String _json1080Adaptive() {
  return jsonEncode(<String, dynamic>{
    'id': 'dQw4w9WgXcQ',
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    'thumbnail': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '137',
        'ext': 'mp4',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137',
        'height': 1080,
        'width': 1920,
        'vcodec': 'avc1.640028',
        'acodec': 'none',
        'tbr': 4000,
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '136',
        'ext': 'mp4',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=136',
        'height': 720,
        'vcodec': 'avc1.4d401f',
        'acodec': 'none',
        'tbr': 2000,
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '18',
        'ext': 'mp4',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18',
        'height': 360,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'tbr': 500,
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'abr': 128,
        'protocol': 'https',
      },
    ],
  });
}
