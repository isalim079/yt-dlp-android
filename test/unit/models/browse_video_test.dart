import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/utils/youtube_urls.dart';
import 'package:yxz_tube/data/models/browse_video.dart';
import 'package:yxz_tube/data/models/playlist_info.dart';

void main() {
  group('YoutubeUrls', () {
    test('extracts watch and short ids', () {
      expect(
        YoutubeUrls.videoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(YoutubeUrls.videoId('https://youtu.be/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(YoutubeUrls.videoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    });

    test('builds search and popular sources', () {
      expect(YoutubeUrls.searchSource('cats'), 'ytsearch20:cats');
      expect(YoutubeUrls.isSearchSource('ytsearch10:x'), isTrue);
      expect(YoutubeUrls.isSearchSource(YoutubeUrls.popularSources.first), isTrue);
      expect(YoutubeUrls.popularSources, contains('ytsearchdate25:music'));
      expect(YoutubeUrls.popularSources, contains('ytsearchdate25:gaming'));
      expect(YoutubeUrls.popularSources.last, 'ytsearch25:music');
    });
  });

  group('BrowseVideo', () {
    test('fromPlaylistEntry fills watch url and thumbnail', () {
      const PlaylistEntry entry = PlaylistEntry(
        title: 'Hello',
        url: 'dQw4w9WgXcQ',
        id: 'dQw4w9WgXcQ',
      );
      final BrowseVideo video = BrowseVideo.fromPlaylistEntry(entry);
      expect(video.url, contains('watch?v=dQw4w9WgXcQ'));
      expect(video.thumbnail, contains('dQw4w9WgXcQ'));
    });
  });
}
