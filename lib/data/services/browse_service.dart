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
