import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/browse_video.dart';
import 'package:yxz_tube/data/models/playlist_info.dart';
import 'package:yxz_tube/data/services/browse_service.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

class _ListingYtdlp extends YtdlpService {
  _ListingYtdlp(this._onSource) : super(binaryPath: '/mock/yt-dlp');

  final PlaylistInfo Function(String source) _onSource;
  final List<String> sources = <String>[];

  @override
  Future<PlaylistInfo> fetchFlatListing(String source) async {
    sources.add(source);
    return _onSource(source);
  }
}

BrowseVideo _video(String id, {String title = 'Title', String? uploader}) {
  return BrowseVideo(
    id: id,
    title: title,
    url: 'https://www.youtube.com/watch?v=$id',
    uploader: uploader,
  );
}

PlaylistEntry _entry(String id, {String title = 'Result'}) {
  return PlaylistEntry(
    title: title,
    url: 'https://www.youtube.com/watch?v=$id',
    id: id,
  );
}

void main() {
  group('BrowseService.recommendationSeeds', () {
    test('returns empty when there is no search or watch activity', () {
      expect(
        BrowseService.recommendationSeeds(
          searchQueries: const <String>[],
          watched: const <BrowseVideo>[],
        ),
        isEmpty,
      );
    });

    test('uses recent searches, uploader, and shortened title uniquely', () {
      final List<String> seeds = BrowseService.recommendationSeeds(
        searchQueries: <String>['Cats', 'cats', 'lofi'],
        watched: <BrowseVideo>[
          _video(
            'aaaaaaaaaaa',
            title: 'Lofi mix for study | Channel Name',
            uploader: 'LoFi Girl',
          ),
        ],
      );
      expect(seeds, <String>['Cats', 'lofi', 'LoFi Girl', 'Lofi mix for study']);
    });
  });

  group('BrowseService.shortenedTitle', () {
    test('keeps the first words and drops a pipe suffix', () {
      expect(
        BrowseService.shortenedTitle(
          'Amazing guitar solo live | Official',
        ),
        'Amazing guitar solo live',
      );
    });
  });

  group('BrowseService.recommend', () {
    test('does not call yt-dlp when history is empty', () async {
      final _ListingYtdlp ytdlp = _ListingYtdlp(
        (String source) => throw StateError('unexpected $source'),
      );
      final BrowseService browse = BrowseService(ytdlp: ytdlp);
      final List<BrowseVideo> videos = await browse.recommend(
        searchQueries: const <String>[],
        watched: const <BrowseVideo>[],
      );
      expect(videos, isEmpty);
      expect(ytdlp.sources, isEmpty);
    });

    test('drops already-watched ids and caps results', () async {
      final _ListingYtdlp ytdlp = _ListingYtdlp((String source) {
        return PlaylistInfo(
          title: 'search',
          count: 3,
          url: source,
          entries: <PlaylistEntry>[
            _entry('watched00001'),
            _entry('fresh0000001'),
            _entry('fresh0000002'),
          ],
        );
      });
      final BrowseService browse = BrowseService(ytdlp: ytdlp);
      final List<BrowseVideo> videos = await browse.recommend(
        searchQueries: const <String>['cats'],
        watched: <BrowseVideo>[_video('watched00001', title: 'Seen')],
        limit: 20,
      );
      expect(videos.map((BrowseVideo v) => v.id).toList(), <String>[
        'fresh0000001',
        'fresh0000002',
      ]);
      expect(ytdlp.sources, isNotEmpty);
    });
  });
}
