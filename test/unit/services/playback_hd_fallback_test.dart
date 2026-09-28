import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/exceptions/ytdlp_exception.dart';
import 'package:yxz_tube/data/models/playback_po_token.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_hd_fallback.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  group('resolvePlaybackStart', () {
    test('uses only the preferred client and returns 360', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payloadFullLadder(),
      });

      final PlaybackResolved resolved = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        forceRefresh: false,
      );

      expect(ytdlp.clients, <String>['android,web']);
      expect(resolved.height, 360);
      expect(resolved.progressiveUrl, isNotNull);
    });
  });

  group('warmPlaybackHdLadder', () {
    test('loads android_vr after 360 start and does not reopen via callback',
        () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payloadFullLadder(),
      });
      final PlaybackResolved start = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        forceRefresh: false,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        start: start,
      );

      expect(ytdlp.clients, <String>['android,web', kPlaybackHdFallbackClient]);
      expect(hd, isNotNull);
      expect(playbackMaxAvailableHeight(hd!), 2160);
      expect(hd.offersQuality(PlaybackQuality.p1080), isTrue);
      expect(start.height, 360);
    });

    test('skips mweb when android_vr already has HD', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payloadFullLadder(),
        kPlaybackMwebClient: _payloadFullLadder(),
      });
      int mints = 0;
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        start: start,
        mintPoTokens: (String videoId) async {
          mints += 1;
          return null;
        },
      );

      expect(mints, 0);
      expect(ytdlp.clients, <String>[kPlaybackHdFallbackClient]);
      expect(playbackMaxAvailableHeight(hd!), 2160);
    });

    test('mweb+PO runs only after VR still has no HD', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        kPlaybackHdFallbackClient: _payload360(),
        kPlaybackMwebClient: _payloadFullLadder(),
      });
      int mints = 0;
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        start: start,
        mintPoTokens: (String videoId) async {
          mints += 1;
          expect(videoId, 'sRWcJrMTtMI');
          return const PlaybackPoToken(
            player: 'PLAYERTOKEN',
            gvs: 'GVSTOKEN',
            visitorData: 'VISITOR',
          );
        },
      );

      expect(mints, 1);
      expect(
        ytdlp.clients.toSet(),
        <String>{kPlaybackHdFallbackClient, kPlaybackMwebClient},
      );
      expect(ytdlp.poTokens.single, contains('mweb.player+PLAYERTOKEN'));
      expect(playbackMaxAvailableHeight(hd!), 2160);
    });

    test('returns null when VR fails and start stays 360', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
      });
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: 'android,web',
        start: start,
      );

      expect(hd, isNull);
    });

    test('does not retry VR when start client is already android_vr', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        kPlaybackHdFallbackClient: _payload360(),
      });
      final PlaybackResolved start = PlaybackResolver.fromJson(
        _payload360(),
        quality: PlaybackQuality.p360,
      );

      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        preferredClient: kPlaybackHdFallbackClient,
        start: start,
      );

      expect(ytdlp.clients, isEmpty);
      expect(hd, isNull);
    });
  });
}

class _FakeYtdlp extends YtdlpService {
  _FakeYtdlp(this._jsonByClient) : super(binaryPath: '/mock/yt-dlp');

  final Map<String, String> _jsonByClient;
  final List<String> clients = <String>[];
  final List<String> poTokens = <String>[];

  @override
  Future<PlaybackResolved> resolvePlayback(
    String url, {
    PlaybackQuality quality = PlaybackQuality.auto,
    String playerClient = 'android,web',
    bool forceRefresh = false,
    String? poToken,
  }) async {
    clients.add(playerClient);
    if (poToken != null) {
      poTokens.add(poToken);
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
    'webpage_url': 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
    'thumbnail': 'https://i.ytimg.com/vi/sRWcJrMTtMI/hqdefault.jpg',
    'duration': 100,
    'uploader': 'Channel',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '18',
        'ext': 'mp4',
        'url': 'https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18',
        'height': 360,
        'vcodec': 'avc1',
        'acodec': 'mp4a.40.2',
        'tbr': 500,
        'protocol': 'https',
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
    'webpage_url': 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
    'thumbnail': 'https://i.ytimg.com/vi/sRWcJrMTtMI/hqdefault.jpg',
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
