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
  group('extractionPlayerClient', () {
    test('never returns android_vr', () {
      for (final ExtractionStrategy s in ExtractionStrategy.values) {
        expect(extractionPlayerClient(s), isNot(contains('android_vr')));
      }
    });

    test('default uses no override label', () {
      expect(
        extractionPlayerClient(ExtractionStrategy.defaultClients),
        'default',
      );
    });
  });

  group('resolvePlaybackStart', () {
    test('tries default clients first', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'default': _payload360(),
      });

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

      expect(ytdlp.clients.first, 'default');
      expect(resolved.height, 360);
    });

    test('falls to android when default empty', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          'android': _payload360(),
        },
        emptyClients: <String>{'default'},
      );

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

      expect(ytdlp.clients, contains('android'));
      expect(resolved.isPlayable, isTrue);
    });

    test('mwebWithPot only when mint complete', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'default': _payload360(),
        'mweb': _payloadFullLadder(),
      });

      await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
        mintPoTokens: (String id) async => const PlaybackPoToken(
          player: 'P',
          gvs: 'G',
          visitorData: 'V',
        ),
      );

      // default succeeds first — mweb not required
      expect(ytdlp.clients.first, 'default');
      expect(ytdlp.clients, isNot(contains('mweb')));
    });

    test('uses mwebWithPot when earlier strategies fail', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          'mweb': _payloadFullLadder(),
        },
        emptyClients: <String>{'default', 'android'},
      );

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
        mintPoTokens: (String id) async => const PlaybackPoToken(
          player: 'P',
          gvs: 'G',
          visitorData: 'V',
        ),
      );

      expect(ytdlp.clients, contains('mweb'));
      expect(ytdlp.visitorData, isNotEmpty);
      expect(playbackMaxAvailableHeight(resolved), 2160);
    });

    test('skips mweb when mint missing', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          'web_safari': _payloadHls(),
        },
        emptyClients: <String>{'default', 'android'},
      );

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

      expect(ytdlp.clients, isNot(contains('mweb')));
      expect(resolved.mode, PlaybackMode.hls);
    });

    test('does not fail solely because exact 360 is missing', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'default': _payload720Only(),
      });

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=WA2Jhud25I8',
        forceRefresh: false,
      );

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
  });

  group('warmPlaybackHdLadder', () {
    test('mweb+visitor unlocks HD and keeps start progressive', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          'mweb': _payloadFullLadder(),
        },
        emptyClients: <String>{'default', 'android'},
      );
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

      expect(ytdlp.visitorData, contains('VISITOR'));
      expect(hd, isNotNull);
      expect(playbackMaxAvailableHeight(hd!), 2160);
      expect(hd.progressiveUrl, start.progressiveUrl);
    });
  });

  group('playbackAppendGvsPot', () {
    test('appends pot to googlevideo https urls once', () {
      const String url =
          'https://rr.googlevideo.com/videoplayback?expire=1&itag=18';
      final String? withPot = playbackAppendGvsPot(url, 'TOKEN');
      expect(withPot, contains('pot=TOKEN'));
      expect(playbackAppendGvsPot(withPot, 'TOKEN'), withPot);
    });

    test('skips m3u8 manifests', () {
      const String hls =
          'https://manifest.googlevideo.com/api/manifest/hls_playlist/x.m3u8';
      expect(playbackAppendGvsPot(hls, 'TOKEN'), hls);
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
    String playerClient = 'default',
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
