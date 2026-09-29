import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/app_settings.dart';
import 'package:yxz_tube/data/models/video_format.dart';
import 'package:yxz_tube/data/services/download_format_catalog.dart';
import 'package:yxz_tube/data/services/playback_hd_fallback.dart';
import 'package:yxz_tube/data/services/playback_json_cache.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  group('downloadListingStrategies', () {
    test('never includes android_vr and skips mweb without PO', () {
      final List<ExtractionStrategy> withoutPo = downloadListingStrategies(
        hasPo: false,
      );
      expect(withoutPo, isNot(contains(ExtractionStrategy.mwebWithPot)));
      expect(
        withoutPo.map(extractionPlayerClient),
        isNot(contains('android_vr')),
      );
      expect(withoutPo, contains(ExtractionStrategy.defaultClients));
      expect(withoutPo, contains(ExtractionStrategy.android));
      expect(withoutPo, contains(ExtractionStrategy.webSafariHls));
      expect(withoutPo, isNot(contains(ExtractionStrategy.webEmbedded)));
    });

    test('includes mwebWithPot when PO is available', () {
      final List<ExtractionStrategy> withPo = downloadListingStrategies(
        hasPo: true,
      );
      expect(withPo, contains(ExtractionStrategy.mwebWithPot));
      expect(extractionPlayerClient(ExtractionStrategy.mwebWithPot), 'mweb');
      expect(
        withPo.map(extractionPlayerClient),
        isNot(contains('android_vr')),
      );
    });
  });

  group('DownloadFormatCatalog.mergeExtracts', () {
    test('progressive-only client + HD mweb yields 720/1080 in UI heights', () {
      final List<VideoFormat> progressiveOnly =
          DownloadFormatCatalog.entriesFromJson(
        _progressive360Json(),
        sourceClient: 'android',
      );
      final List<VideoFormat> mwebHd = DownloadFormatCatalog.entriesFromJson(
        _mwebHdJson(),
        sourceClient: 'mweb',
        poToken: 'mweb.player+P,mweb.gvs+G',
        visitorData: 'VIS',
      );

      expect(
        progressiveOnly
            .where((VideoFormat f) => !f.isAudioOnly)
            .map((VideoFormat f) => f.height),
        <int>[360],
      );
      expect(
        mwebHd
            .where((VideoFormat f) => !f.isAudioOnly)
            .map((VideoFormat f) => f.height)
            .toSet(),
        containsAll(<int>[720, 1080]),
      );

      final List<VideoFormat> merged = DownloadFormatCatalog.mergeExtracts(
        <DownloadStrategyExtract>[
          DownloadStrategyExtract(
            client: 'android',
            formats: progressiveOnly,
          ),
          DownloadStrategyExtract(client: 'mweb', formats: mwebHd),
        ],
      );

      final Set<int> heights = merged
          .where((VideoFormat f) => !f.isAudioOnly)
          .map((VideoFormat f) => f.height)
          .whereType<int>()
          .toSet();
      expect(heights, containsAll(<int>[360, 720, 1080]));

      final VideoFormat hd1080 = merged.firstWhere(
        (VideoFormat f) => f.height == 1080,
      );
      expect(hd1080.sourceClient, 'mweb');
      expect(hd1080.poToken, isNotNull);
      expect(hd1080.needsAudioMerge, isTrue);
      expect(hd1080.formatId, contains('+'));
    });

    test('prefers mp4 progressive over merge when same height', () {
      const VideoFormat progressive = VideoFormat(
        formatId: '18',
        extension: 'mp4',
        displayLabel: '360p',
        resolution: '360p',
        fileSize: 10,
        sourceClient: 'android',
      );
      const VideoFormat adaptive = VideoFormat(
        formatId: '134+140',
        extension: 'mp4',
        displayLabel: '360p',
        resolution: '360p',
        fileSize: 10,
        sourceClient: 'mweb',
        needsAudioMerge: true,
      );
      final List<VideoFormat> merged = DownloadFormatCatalog.mergeExtracts(
        <DownloadStrategyExtract>[
          const DownloadStrategyExtract(
            client: 'android',
            formats: <VideoFormat>[progressive],
          ),
          const DownloadStrategyExtract(
            client: 'mweb',
            formats: <VideoFormat>[adaptive],
          ),
        ],
      );
      expect(merged.single.formatId, '18');
      expect(merged.single.needsAudioMerge, isFalse);
    });
  });

  group('download args binding', () {
    test('selected entry sourceClient and PO flow into extractor-args', () {
      const YtdlpService service = YtdlpService(binaryPath: 'yt-dlp');
      final List<String> args = service.buildDownloadArgs(
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        formatId: '137+140',
        outputTemplate: '/tmp/%(title)s.%(ext)s',
        settings: AppSettings.defaults,
        playerClient: 'mweb',
        poToken: 'mweb.player+P,mweb.gvs+G',
        visitorData: 'VISITOR',
        mergeOutput: true,
      );

      final int extractorIdx = args.indexOf('--extractor-args');
      expect(extractorIdx, greaterThan(-1));
      expect(
        args[extractorIdx + 1],
        'youtube:player_client=mweb;'
        'po_token=mweb.player+P,mweb.gvs+G;'
        'visitor_data=VISITOR',
      );
      expect(args, contains('--merge-output-format'));
      expect(args, contains('mp4'));
      expect(args.join(' '), isNot(contains('android,web')));
    });

    test('formatId with + implies merge even without mergeOutput flag', () {
      const YtdlpService service = YtdlpService(binaryPath: 'yt-dlp');
      final List<String> args = service.buildDownloadArgs(
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        formatId: '137+140',
        outputTemplate: '/tmp/%(title)s.%(ext)s',
        settings: AppSettings.defaults,
        playerClient: 'android',
      );
      expect(args, contains('--merge-output-format'));
    });
  });

  group('PlaybackJsonCache TTL', () {
    test('stale entries miss after ttl and invalidateUrl clears strategies', () {
      final PlaybackJsonCache cache = PlaybackJsonCache(
        ttl: const Duration(milliseconds: 1),
      );
      const String url = 'https://www.youtube.com/watch?v=abc';
      cache.put(url, 'default|nopot|novis', '{"a":1}');
      cache.put(url, 'mweb|pot|vis', '{"b":2}');
      expect(cache.read(url, 'default|nopot|novis'), isNotNull);
      // Allow TTL to expire.
      return Future<void>.delayed(const Duration(milliseconds: 5)).then((_) {
        expect(cache.read(url, 'default|nopot|novis'), isNull);
        cache.put(url, 'default|nopot|novis', '{"a":1}');
        cache.put(url, 'mweb|pot|vis', '{"b":2}');
        cache.invalidateUrl(url);
        expect(cache.read(url, 'default|nopot|novis'), isNull);
        expect(cache.read(url, 'mweb|pot|vis'), isNull);
      });
    });
  });
}

String _progressive360Json() => '''
{"title":"Demo","formats":[
{"format_id":"18","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?itag=18","height":360,"vcodec":"avc1","acodec":"mp4a.40.2","filesize":5000000}
]}
''';

String _mwebHdJson() => '''
{"title":"Demo","formats":[
{"format_id":"137","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?itag=137","height":1080,"vcodec":"avc1.640028","acodec":"none","filesize":20000000},
{"format_id":"136","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?itag=136","height":720,"vcodec":"avc1.4d401f","acodec":"none","filesize":10000000},
{"format_id":"140","ext":"m4a","url":"https://rr.googlevideo.com/videoplayback?itag=140","vcodec":"none","acodec":"mp4a.40.2","abr":128,"filesize":3000000},
{"format_id":"18","ext":"mp4","url":"https://rr.googlevideo.com/videoplayback?itag=18","height":360,"vcodec":"avc1","acodec":"mp4a.40.2","filesize":5000000}
]}
''';
