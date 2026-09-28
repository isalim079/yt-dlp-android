/// Browse listings: search, popular, and channel uploads via yt-dlp.
library;

import '../../core/utils/logger.dart';
import '../../core/utils/youtube_urls.dart';
import '../models/browse_video.dart';
import '../models/playlist_info.dart';
import 'ytdlp_service.dart';

/// Thin wrapper around flat yt-dlp listings.
class BrowseService {
  /// Creates a browse service bound to [ytdlp].
  const BrowseService({required this.ytdlp});

  /// Underlying extractor.
  final YtdlpService ytdlp;

  /// Search results for [query].
  Future<List<BrowseVideo>> search(String query, {int count = 20}) async {
    final PlaylistInfo info = await ytdlp.fetchFlatListing(
      YoutubeUrls.searchSource(query, count: count),
    );
    return info.entries.map(BrowseVideo.fromPlaylistEntry).toList();
  }

  /// Personalized Home rows from recent searches and watched videos.
  ///
  /// Returns an empty list without calling yt-dlp when there is no activity.
  Future<List<BrowseVideo>> recommend({
    required List<String> searchQueries,
    required List<BrowseVideo> watched,
    int limit = 20,
  }) async {
    final List<String> seeds = recommendationSeeds(
      searchQueries: searchQueries,
      watched: watched,
    );
    if (seeds.isEmpty) {
      return const <BrowseVideo>[];
    }

    final Set<String> seen = <String>{
      for (final BrowseVideo video in watched)
        if (video.id.isNotEmpty) video.id,
    };
    final List<BrowseVideo> out = <BrowseVideo>[];
    int searches = 0;
    for (final String seed in seeds) {
      if (out.length >= limit || searches >= 3) {
        break;
      }
      try {
        final List<BrowseVideo> results = await search(seed, count: 12);
        searches += 1;
        for (final BrowseVideo video in results) {
          if (video.id.isEmpty || !seen.add(video.id)) {
            continue;
          }
          out.add(video);
          if (out.length >= limit) {
            break;
          }
        }
      } on Object {
        AppLogger.w('Recommend search failed for "$seed"');
      }
    }
    return out;
  }

  /// Query seeds for [recommend], newest activity first, unique, no yt-dlp.
  static List<String> recommendationSeeds({
    required List<String> searchQueries,
    required List<BrowseVideo> watched,
    int maxSearchQueries = 5,
    int maxWatched = 3,
  }) {
    final List<String> seeds = <String>[];
    final Set<String> seen = <String>{};

    void addSeed(String raw) {
      final String value = raw.trim();
      if (value.isEmpty) {
        return;
      }
      final String key = value.toLowerCase();
      if (!seen.add(key)) {
        return;
      }
      seeds.add(value);
    }

    for (final String query in searchQueries.take(maxSearchQueries)) {
      addSeed(query);
    }
    for (final BrowseVideo video in watched.take(maxWatched)) {
      addSeed(video.uploader ?? '');
      addSeed(shortenedTitle(video.title));
    }
    return seeds;
  }

  /// Short search phrase from a video title (first words, drop suffix).
  static String shortenedTitle(String title) {
    String text = title.trim();
    if (text.isEmpty) {
      return '';
    }
    final int pipe = text.indexOf('|');
    if (pipe > 8) {
      text = text.substring(0, pipe);
    }
    final int dash = text.indexOf(' - ');
    if (dash > 8) {
      text = text.substring(0, dash);
    }
    return text
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .take(6)
        .join(' ')
        .trim();
  }

  /// Popular videos from the first Home source that returns entries.
  Future<List<BrowseVideo>> trending() async {
    Object? lastError;
    StackTrace? lastStack;
    for (final String source in YoutubeUrls.popularSources) {
      try {
        final PlaylistInfo info = await ytdlp.fetchFlatListing(source);
        final List<BrowseVideo> videos =
            info.entries.map(BrowseVideo.fromPlaylistEntry).toList();
        if (videos.isNotEmpty) {
          return videos;
        }
      } on Object catch (error, stackTrace) {
        AppLogger.w('Home listing failed for $source');
        lastError = error;
        lastStack = stackTrace;
      }
    }
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, lastStack ?? StackTrace.current);
    }
    return const <BrowseVideo>[];
  }

  /// Latest uploads from a channel URL.
  Future<List<BrowseVideo>> channelUploads(String channelUrl) async {
    final String source =
        YoutubeUrls.channelVideosUrl(channelUrl) ?? channelUrl;
    final PlaylistInfo info = await ytdlp.fetchFlatListing(source);
    return info.entries.map(BrowseVideo.fromPlaylistEntry).toList();
  }

  /// Playlist / channel listing with title.
  Future<PlaylistInfo> listing(String source) {
    return ytdlp.fetchFlatListing(source);
  }
}
