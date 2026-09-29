import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_resolved.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  tearDown(YtdlpService.resetCachesForTest);

  test('Auto then 1080/1440 reuses one yt-dlp extract', () async {
    int extracts = 0;
    YtdlpService.debugFetchJson = (String url, String playerClient) async {
      extracts += 1;
      expect(playerClient, 'default');
      return _payload();
    };

    final YtdlpService service = YtdlpService(binaryPath: '/mock/yt-dlp');
    const String url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';

    final PlaybackResolved auto = await service.resolvePlayback(url);
    final PlaybackResolved hd = await service.resolvePlayback(
      url,
      quality: PlaybackQuality.p1080,
    );
    final PlaybackResolved qhd = await service.resolvePlayback(
      url,
      quality: PlaybackQuality.p1440,
    );

    expect(extracts, 1);
    expect(YtdlpService.jsonCache.missCount, 1);
    expect(auto.height, 1080);
    expect(hd.height, 1080);
    expect(qhd.height, 1080);
  });
}

String _payload() {
  return '''
{"title":"Demo","webpage_url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ","thumbnail":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg","duration":100,"uploader":"Channel","formats":[
{"format_id":"137","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=137","height":1080,"vcodec":"avc1","acodec":"none","tbr":4000,"protocol":"https"},
{"format_id":"18","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=18","height":360,"vcodec":"avc1","acodec":"mp4a.40.2","tbr":500,"protocol":"https"},
{"format_id":"140","ext":"m4a","url":"https://rr.googlevideo.com/videoplayback?expire=1999999999&itag=140","vcodec":"none","acodec":"mp4a.40.2","abr":128,"protocol":"https"}
]}
''';
}
