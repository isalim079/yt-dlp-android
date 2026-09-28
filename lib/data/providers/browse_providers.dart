/// Browse (search / trending) providers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/library_store.dart';
import '../models/browse_video.dart';
import '../services/browse_service.dart';
import 'library_providers.dart';
import 'ytdlp_providers.dart';

/// [BrowseService] using the ready yt-dlp runtime.
final Provider<BrowseService> browseServiceProvider = Provider<BrowseService>((
  Ref ref,
) {
  return BrowseService(ytdlp: ref.watch(ytdlpServiceProvider));
});

/// Trending feed. Reloaded on invalidate.
final FutureProvider<List<BrowseVideo>> trendingProvider =
    FutureProvider<List<BrowseVideo>>((Ref ref) {
      return ref.watch(browseServiceProvider).trending();
    });

/// Current search query (submitted).
final StateProvider<String> searchQueryProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// Search results for [searchQueryProvider].
final FutureProvider<List<BrowseVideo>> searchResultsProvider =
    FutureProvider<List<BrowseVideo>>((Ref ref) async {
      final String query = ref.watch(searchQueryProvider).trim();
      if (query.isEmpty) {
        return <BrowseVideo>[];
      }
      return ref.watch(browseServiceProvider).search(query);
    });

/// Latest uploads from followed channels (capped).
final FutureProvider<List<BrowseVideo>> followedFeedProvider =
    FutureProvider<List<BrowseVideo>>((Ref ref) async {
      final List<FollowedChannel> channels = await ref.watch(
        followedChannelsProvider.future,
      );
      if (channels.isEmpty) {
        return <BrowseVideo>[];
      }
      final BrowseService browse = ref.watch(browseServiceProvider);
      final List<BrowseVideo> out = <BrowseVideo>[];
      for (final FollowedChannel channel in channels.take(5)) {
        try {
          final List<BrowseVideo> videos = await browse.channelUploads(
            channel.url,
          );
          out.addAll(videos.take(4));
        } on Object {
          // Skip a broken channel; others can still fill the feed.
        }
      }
      return out;
    });
