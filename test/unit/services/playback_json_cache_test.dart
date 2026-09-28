import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/playback_json_cache.dart';
import 'package:yxz_tube/data/services/playback_resolver.dart';

void main() {
  group('PlaybackJsonCache', () {
    test('quality changes reuse one extract for the same url and client', () async {
      final PlaybackJsonCache cache = PlaybackJsonCache();
      const String url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      int loads = 0;
      Future<String> load() async {
        loads += 1;
        return _payload1080And360();
      }

      final String first = await cache.remember(
        url: url,
        playerClient: 'android,web',
        load: load,
      );
      final String second = await cache.remember(
        url: url,
        playerClient: 'android,web',
        load: load,
      );

      expect(loads, 1);
      expect(cache.missCount, 1);
      expect(identical(first, second) || first == second, isTrue);

      final PlaybackResolved auto = PlaybackResolver.fromJson(first);
      final PlaybackResolved hd = PlaybackResolver.fromJson(
        first,
        quality: PlaybackQuality.p1080,
      );
      final PlaybackResolved qhd = PlaybackResolver.fromJson(
        first,
        quality: PlaybackQuality.p1440,
      );
      expect(auto.height, 1080);
      expect(hd.height, 1080);
      expect(qhd.height, 1080);
      expect(playbackNeedsExtraClient(hd), isFalse);
      expect(cache.read(url, 'tv'), isNull);
    });
  });
}

String _payload1080And360() {
  return '''
{"title":"Demo","webpage_url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ","thumbnail":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg","duration":100,"uploader":"Channel","formats":[
{"format_id":"137","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137","height":1080,"vcodec":"avc1","acodec":"none","tbr":4000,"protocol":"https"},
{"format_id":"18","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18","height":360,"vcodec":"avc1","acodec":"mp4a.40.2","tbr":500,"protocol":"https"},
{"format_id":"140","ext":"m4a","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140","vcodec":"none","acodec":"mp4a.40.2","abr":128,"protocol":"https"}
]}
''';
}
