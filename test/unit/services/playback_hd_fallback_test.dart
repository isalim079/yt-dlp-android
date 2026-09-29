import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/constants/app_strings.dart';
import 'package:yxz_tube/core/exceptions/ytdlp_exception.dart';
import 'package:yxz_tube/data/models/playback_po_token.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_hd_fallback.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  group('playbackUrlIsAndroidVr', () {
    test('detects ANDROID_VR client stamp', () {
      expect(
        playbackUrlIsAndroidVr(
          'https://rr.googlevideo.com/videoplayback?itag=18&c=ANDROID_VR',
        ),
        isTrue,
      );
      expect(
        playbackUrlIsAndroidVr(
          'https://rr.googlevideo.com/videoplayback?itag=18&c=ANDROID',
        ),
        isFalse,
      );
    });
  });

  group('playbackSanitizeAndroidVr', () {
    test('prefers HLS when progressive is ANDROID_VR', () {
      final PlaybackResolved mixed = PlaybackResolver.fromJson(
        _payloadVrProgressiveWithHls(),
        quality: PlaybackQuality.auto,
      );
      final PlaybackResolved clean = playbackSanitizeAndroidVr(mixed);
      expect(clean.mode, PlaybackMode.hls);
      expect(playbackUrlIsAndroidVr(clean.primaryUrl), isFalse);
    });
  });

  group('resolvePlaybackStart', () {
    test('poMwebBundle first returns progressive when formats exist', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        extractionPlayerClient(ExtractionStrategy.poMwebBundle): _payload360(),
      });

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
        mintPoTokens: (String videoId) async {
          return const PlaybackPoToken(
            player: 'PLAYERTOKEN',
            gvs: 'GVSTOKEN',
            visitorData: 'VISITOR',
          );
        },
      );

      expect(
        ytdlp.clients.first,
        extractionPlayerClient(ExtractionStrategy.poMwebBundle),
      );
      expect(ytdlp.visitorData.single, 'VISITOR');
      expect(resolved.progressiveUrl, isNotNull);
      expect(resolved.height, 360);
    });

    test('falls through strategies when PO extract has no formats', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          extractionPlayerClient(ExtractionStrategy.httpsFallback):
              _payloadHls(),
        },
        emptyClients: <String>{
          extractionPlayerClient(ExtractionStrategy.poMwebBundle),
          extractionPlayerClient(ExtractionStrategy.defaultClients),
        },
      );

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
        mintPoTokens: (String videoId) async {
          return const PlaybackPoToken(
            player: 'P',
            gvs: 'G',
            visitorData: 'V',
          );
        },
      );

      expect(resolved.mode, PlaybackMode.hls);
      expect(
        ytdlp.clients,
        contains(extractionPlayerClient(ExtractionStrategy.httpsFallback)),
      );
    });

    test('does not fail solely because exact 360 is missing', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        extractionPlayerClient(ExtractionStrategy.defaultClients):
            _payload720Only(),
      });

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

      expect(resolved.isPlayable, isTrue);
      expect(resolved.height, 720);
    });

    test('throws ladder exhausted when all strategies fail', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{});

      expect(
        () => resolvePlaybackStart(
          ytdlp: ytdlp,
          url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
          forceRefresh: false,
        ),
        throwsA(
          isA<YtdlpException>().having(
            (YtdlpException e) => e.message,
            'message',
            AppStrings.errorPlaybackLadderExhausted,
          ),
        ),
      );
    });

    test('treats format-not-available as try-next-strategy', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          extractionPlayerClient(ExtractionStrategy.httpsFallback):
              _payloadHls(),
        },
        failClients: <String>{
          extractionPlayerClient(ExtractionStrategy.defaultClients),
        },
        failMessage: 'Requested format is not available',
      );

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

      expect(resolved.hlsUrl, isNotNull);
    });
  });

  group('playbackKeepStartProgressive', () {
    test('keeps muxed 360 when HD JSON has no progressive URL', () {
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );
      final PlaybackResolved hd = PlaybackResolver.fromJson(
        _payloadFullLadder(),
        quality: PlaybackQuality.auto,
      );

      final PlaybackResolved merged = playbackKeepStartProgressive(start, hd);

      expect(hd.progressiveUrl, isNull);
      expect(merged.progressiveUrl, start.progressiveUrl);
      expect(playbackMaxAvailableHeight(merged), 2160);
    });
  });

  group('warmPlaybackHdLadder', () {
    test('mweb bundle + visitor unlocks HD and keeps start progressive', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        extractionPlayerClient(ExtractionStrategy.poMwebBundle):
            _payloadFullLadder(),
      });
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        preferredClient: kPlaybackStartClient,
        start: start,
        mintPoTokens: (String videoId) async {
          return const PlaybackPoToken(
            player: 'PLAYERTOKEN',
            gvs: 'GVSTOKEN',
            visitorData: 'VISITOR',
          );
        },
      );

      expect(ytdlp.visitorData.single, 'VISITOR');
      expect(hd, isNotNull);
      expect(playbackMaxAvailableHeight(hd!), 2160);
      expect(hd.progressiveUrl, start.progressiveUrl);
    });
  });
}

class _FakeYtdlp extends YtdlpService {
  _FakeYtdlp(
    this._jsonByClient, {
    this.failClients = const <String>{},
    this.emptyClients = const <String>{},
    this.failMessage = 'client failed',
  }) : super(binaryPath: '/mock/yt-dlp');

  final Map<String, String> _jsonByClient;
  final Set<String> failClients;
  final Set<String> emptyClients;
  final String failMessage;
  final List<String> clients = <String>[];
  final List<String> poTokens = <String>[];
  final List<String> visitorData = <String>[];

  @override
  Future<PlaybackResolved> resolvePlayback(
    String url, {
    PlaybackQuality quality = PlaybackQuality.auto,
    String playerClient = 'android',
    bool forceRefresh = false,
    String? poToken,
    String? visitorData,
  }) async {
    clients.add(playerClient);
    if (poToken != null) {
      poTokens.add(poToken);
    }
    if (visitorData != null) {
      this.visitorData.add(visitorData);
    }
    if (failClients.contains(playerClient)) {
      throw YtdlpException(failMessage);
    }
    if (emptyClients.contains(playerClient)) {
      throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
    }
    final String? json = _jsonByClient[playerClient];
    if (json == null) {
      throw const YtdlpException('client failed');
    }
    return PlaybackResolver.fromJson(json, quality: quality);
  }
}

String _payload360() {
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
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18&c=ANDROID',
        'height': 360,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'tbr': 500,
        'protocol': 'https',
      },
    ],
  });
}

String _payload720Only() {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '22',
        'ext': 'mp4',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=22&c=WEB',
        'height': 720,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'tbr': 2000,
        'protocol': 'https',
      },
    ],
  });
}

String _payloadHls() {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'manifest_url':
        'https://manifest.googlevideo.com/api/manifest/hls_variant/expire/1999999999/master.m3u8',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '96',
        'ext': 'mp4',
        'url':
            'https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1999999999/playlist.m3u8',
        'protocol': 'm3u8_native',
        'vcodec': 'none',
        'acodec': 'none',
      },
    ],
  });
}

String _payloadVrProgressiveWithHls() {
  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'manifest_url':
        'https://manifest.googlevideo.com/api/manifest/hls_variant/expire/1999999999/master.m3u8',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '18',
        'ext': 'mp4',
        'url':
            'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18&c=ANDROID_VR',
        'height': 360,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'protocol': 'https',
      },
      <String, dynamic>{
        'format_id': '96',
        'ext': 'mp4',
        'url':
            'https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1999999999/playlist.m3u8',
        'protocol': 'm3u8_native',
        'vcodec': 'none',
        'acodec': 'none',
      },
    ],
  });
}

String _payloadFullLadder() {
  Map<String, dynamic> video({
    required String id,
    required int height,
    required String vcodec,
    required String ext,
  }) {
    return <String, dynamic>{
      'format_id': id,
      'ext': ext,
      'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=$id',
      'height': height,
      'vcodec': vcodec,
      'acodec': 'none',
      'tbr': height * 4.0,
      'protocol': 'https',
    };
  }

  return jsonEncode(<String, dynamic>{
    'title': 'Demo',
    'webpage_url': 'https://www.youtube.com/watch?v=WA2Jhud25I8',
    'thumbnail': 'https://i.ytimg.com/vi/WA2Jhud25I8/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      video(id: '401', height: 2160, vcodec: 'av01', ext: 'mp4'),
      video(id: '271', height: 1440, vcodec: 'vp9', ext: 'webm'),
      video(id: '137', height: 1080, vcodec: 'avc1', ext: 'mp4'),
      video(id: '136', height: 720, vcodec: 'avc1', ext: 'mp4'),
      video(id: '135', height: 480, vcodec: 'avc1', ext: 'mp4'),
      <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140',
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'abr': 128,
        'protocol': 'https',
      },
    ],
  });
}
