import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/browse_video.dart';
import 'package:yxz_tube/data/models/feed_page.dart';
import 'package:yxz_tube/data/providers/feed_providers.dart';

void main() {
  group('FeedPage', () {
    test('parses items and continuation', () {
      final FeedPage page = FeedPage.fromJson(<String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'dQw4w9WgXcQ',
            'title': 'Demo',
            'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
            'duration': 45,
            'isShort': true,
            'uploader': 'Channel',
          },
          <String, dynamic>{
            'id': 'aaaaaaaaaaa',
            'title': 'Long',
            'url': 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
            'duration': 600,
          },
        ],
        'continuation': 'token123',
      });
      expect(page.items.length, 2);
      expect(page.items.first.isShort, isTrue);
      expect(page.items.last.isShort, isFalse);
      expect(page.hasMore, isTrue);
      expect(page.continuation, 'token123');
    });

    test('empty continuation means exhausted', () {
      const FeedPage page = FeedPage(
        items: <BrowseVideo>[
          BrowseVideo(
            id: 'x',
            title: 't',
            url: 'https://www.youtube.com/watch?v=x',
          ),
        ],
      );
      expect(page.hasMore, isFalse);
    });
  });

  group('PagedFeedState dedupe helpers', () {
    test('AppTabs indices match YouTube-like order', () {
      expect(AppTabs.home, 0);
      expect(AppTabs.shorts, 1);
      expect(AppTabs.search, 2);
      expect(AppTabs.library, 3);
      expect(AppTabs.settings, 4);
    });

    test('dedupe keeps first id and drops duplicates', () {
      final List<BrowseVideo> out = PagedFeedController.dedupe(
        <BrowseVideo>[
          const BrowseVideo(
            id: 'a',
            title: '1',
            url: 'https://www.youtube.com/watch?v=a',
          ),
          const BrowseVideo(
            id: 'b',
            title: '2',
            url: 'https://www.youtube.com/watch?v=b',
          ),
          const BrowseVideo(
            id: 'a',
            title: '1b',
            url: 'https://www.youtube.com/watch?v=a',
          ),
        ],
      );
      expect(out.map((BrowseVideo v) => v.id), <String>['a', 'b']);
    });
  });

  group('BrowseVideo feed json', () {
    test('marks duration <= 60 as short', () {
      final BrowseVideo? v = BrowseVideo.tryFromFeedJson(<String, dynamic>{
        'id': 'shortid1234',
        'title': 'S',
        'url': 'https://www.youtube.com/shorts/shortid1234',
        'duration': 30,
      });
      expect(v, isNotNull);
      expect(v!.isShort, isTrue);
    });
  });
}
