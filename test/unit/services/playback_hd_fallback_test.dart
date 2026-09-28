import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/exceptions/ytdlp_exception.dart';
import 'package:yxz_tube/data/models/playback_po_token.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_hd_fallback.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  group('resolvePlaybackWithHdFallback', () {
    test('360-only preferred JSON triggers one android_vr retry', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payloadFullLadder(),
      });

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
      );

      expect(
        ytdlp.clients.toSet(),
        <String>{'android,web', kPlaybackHdFallbackClient},
      );
      expect(resolved.offersQuality(PlaybackQuality.p2160), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p1440), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p1080), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p720), isTrue);
      expect(resolved.offersQuality(PlaybackQuality.p480), isTrue);
      expect(playbackMaxAvailableHeight(resolved), 2160);
    });

    test('full preferred JSON does not retry android_vr', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payloadFullLadder(),
        kPlaybackHdFallbackClient: _payload360(),
      });
      int mints = 0;

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
        mintPoTokens: (String videoId) async {
          mints += 1;
          return null;
        },
      );

      expect(mints, 0);
      expect(ytdlp.clients, contains('android,web'));
      expect(resolved.height, 1080);
      expect(playbackNeedsExtraClient(resolved), isFalse);
    });

    test('fallback failure retains 360p preferred result', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
      });

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
      );

      expect(
        ytdlp.clients.toSet(),
        <String>{'android,web', kPlaybackHdFallbackClient},
      );
      expect(resolved.height, 360);
      expect(resolved.offersQuality(PlaybackQuality.p1080), isFalse);
    });

    test('android_vr preferred client does not retry itself', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        kPlaybackHdFallbackClient: _payload360(),
      });

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: kPlaybackHdFallbackClient,
        forceRefresh: false,
      );

      expect(ytdlp.clients, <String>[kPlaybackHdFallbackClient]);
      expect(resolved.height, 360);
    });

    test('mweb+PO runs only after VR still has no HD', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payload360(),
        kPlaybackMwebClient: _payloadFullLadder(),
      });
      int mints = 0;

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
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
        <String>{
          'android,web',
          kPlaybackHdFallbackClient,
          kPlaybackMwebClient,
        },
      );
      expect(ytdlp.poTokens.single, contains('mweb.player+PLAYERTOKEN'));
      expect(ytdlp.poTokens.single, contains('mweb.gvs+GVSTOKEN'));
      expect(resolved.offersQuality(PlaybackQuality.p2160), isTrue);
    });

    test('mint failure retains 360p after VR', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(<String, String>{
        'android,web': _payload360(),
        kPlaybackHdFallbackClient: _payload360(),
        kPlaybackMwebClient: _payloadFullLadder(),
      });

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
        mintPoTokens: (String videoId) async => null,
      );

      expect(
        ytdlp.clients.toSet(),
        <String>{'android,web', kPlaybackHdFallbackClient},
      );
      expect(resolved.height, 360);
    });

    test('onPlayable starts 360 before slower HD client finishes', () async {
      final _FakeYtdlp ytdlp = _FakeYtdlp(
        <String, String>{
          'android,web': _payload360(),
          kPlaybackHdFallbackClient: _payloadFullLadder(),
        },
        delays: <String, Duration>{
          'android,web': const Duration(milliseconds: 20),
          kPlaybackHdFallbackClient: const Duration(milliseconds: 80),
        },
      );
      final List<int> heights = <int>[];

      final PlaybackResolved resolved = await resolvePlaybackWithHdFallback(
        ytdlp: ytdlp,
        url: 'https://www.youtube.com/watch?v=sRWcJrMTtMI',
        quality: PlaybackQuality.auto,
        preferredClient: 'android,web',
        forceRefresh: false,
        onPlayable: (PlaybackResolved ready) {
          heights.add(playbackMaxAvailableHeight(ready));
        },
      );

      expect(heights.first, 360);
      expect(heights.last, 2160);
      expect(playbackMaxAvailableHeight(resolved), 2160);
    });
  });
}

class _FakeYtdlp extends YtdlpService {
  _FakeYtdlp(
    this._jsonByClient, {
    this.delays = const <String, Duration>{},
  }) : super(binaryPath: '/mock/yt-dlp');

  final Map<String, String> _jsonByClient;
  final Map<String, Duration> delays;
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
    final Duration delay = delays[playerClient] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
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
