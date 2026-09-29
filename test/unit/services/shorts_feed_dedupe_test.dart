import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/browse_video.dart';
import 'package:yxz_tube/data/models/feed_page.dart';
import 'package:yxz_tube/data/providers/feed_providers.dart';

BrowseVideo _v(String id) => BrowseVideo(
      id: id,
      title: id,
      url: 'https://www.youtube.com/watch?v=$id',
      isShort: true,
    );

void main() {
  group('fillUniquePages', () {
    test('overlapping pages only grow by new ids', () {
      final FeedFillResult result = fillUniquePages(
        existing: <BrowseVideo>[_v('a'), _v('b')],
        startContinuation: 't0',
        pages: <FeedPage>[
          FeedPage(
            items: <BrowseVideo>[_v('a'), _v('b'), _v('c')],
            continuation: 't1',
          ),
          FeedPage(
            items: <BrowseVideo>[_v('b'), _v('c'), _v('d')],
            continuation: 't2',
          ),
        ],
        minUnique: 8,
      );
      expect(result.items.map((BrowseVideo v) => v.id), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(result.added, 2);
      expect(result.continuation, 't2');
    });

    test('stops when minUnique new ids reached across pages', () {
      final FeedFillResult result = fillUniquePages(
        existing: const <BrowseVideo>[],
        startContinuation: null,
        pages: <FeedPage>[
          FeedPage(
            items: <BrowseVideo>[_v('1'), _v('2'), _v('3')],
            continuation: 'p1',
          ),
          // Heavy overlap with page 1.
          FeedPage(
            items: <BrowseVideo>[_v('2'), _v('3'), _v('4'), _v('5')],
            continuation: 'p2',
          ),
          FeedPage(
            items: <BrowseVideo>[
              _v('6'),
              _v('7'),
              _v('8'),
              _v('9'),
              _v('10'),
            ],
            continuation: 'p3',
          ),
        ],
        minUnique: 8,
      );
      expect(result.added, greaterThanOrEqualTo(8));
      expect(result.items.length, greaterThanOrEqualTo(8));
      // Should have stopped once minUnique hit (after page that crossed 8).
      expect(result.continuation, 'p3');
    });

    test('identical continuation with zero new ids exhausts', () {
      final FeedFillResult result = fillUniquePages(
        existing: <BrowseVideo>[_v('a'), _v('b')],
        startContinuation: 'same',
        pages: <FeedPage>[
          FeedPage(
            items: <BrowseVideo>[_v('a'), _v('b')],
            continuation: 'same',
          ),
        ],
        minUnique: 8,
      );
      expect(result.added, 0);
      expect(result.continuation, isNull);
      expect(result.hasMore, isFalse);
    });

    test('dedupe helper drops duplicate ids', () {
      expect(
        PagedFeedController.dedupe(<BrowseVideo>[
          _v('x'),
          _v('y'),
          _v('x'),
        ]).map((BrowseVideo v) => v.id),
        <String>['x', 'y'],
      );
    });
  });
}
