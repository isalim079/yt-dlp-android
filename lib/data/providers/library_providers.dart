/// Riverpod wiring for local library (history, playlists, channels).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/library_store.dart';
import '../models/browse_video.dart';
import '../services/browse_service.dart';
import 'ytdlp_providers.dart';

/// Section shown inside the Library tab.
enum LibrarySection { history, playlists, channels, downloads }

/// Active library subsection.
final StateProvider<LibrarySection> librarySectionProvider =
    StateProvider<LibrarySection>((Ref ref) => LibrarySection.history);

/// Singleton [LibraryStore].
final Provider<LibraryStore> libraryStoreProvider = Provider<LibraryStore>((
  Ref ref,
) {
  return LibraryStore.instance;
});

/// Watch history list.
final FutureProvider<List<WatchHistoryEntry>> watchHistoryProvider =
    FutureProvider<List<WatchHistoryEntry>>((Ref ref) {
      return ref.watch(libraryStoreProvider).history();
    });

/// Continue-watching strip.
final FutureProvider<List<WatchHistoryEntry>> continueWatchingProvider =
    FutureProvider<List<WatchHistoryEntry>>((Ref ref) {
      return ref.watch(libraryStoreProvider).continueWatching();
    });

/// Local playlists.
final FutureProvider<List<LocalPlaylist>> localPlaylistsProvider =
    FutureProvider<List<LocalPlaylist>>((Ref ref) {
      return ref.watch(libraryStoreProvider).playlists();
    });

/// Followed channels.
final FutureProvider<List<FollowedChannel>> followedChannelsProvider =
    FutureProvider<List<FollowedChannel>>((Ref ref) {
      return ref.watch(libraryStoreProvider).channels();
    });

/// Recent search keywords, newest first.
final FutureProvider<List<String>> searchHistoryProvider =
    FutureProvider<List<String>>((Ref ref) {
      return ref.watch(libraryStoreProvider).recentSearches();
    });

/// Home recommendations from local search + watch history.
///
/// Empty until the user has searched or watched; then `ytsearch` on those seeds.
final FutureProvider<List<BrowseVideo>> recommendedFeedProvider =
    FutureProvider<List<BrowseVideo>>((Ref ref) async {
      final List<String> searches = await ref.watch(
        searchHistoryProvider.future,
      );
      final List<WatchHistoryEntry> history = await ref.watch(
        watchHistoryProvider.future,
      );
      if (searches.isEmpty && history.isEmpty) {
        return const <BrowseVideo>[];
      }
      return BrowseService(ytdlp: ref.watch(ytdlpServiceProvider)).recommend(
        searchQueries: searches,
        watched: history.map((WatchHistoryEntry entry) => entry.video).toList(),
      );
    });

/// Convenience mutations that invalidate lists.
class LibraryActions {
  /// Creates actions bound to [ref].
  LibraryActions(this._ref);

  final Ref _ref;

  LibraryStore get _store => _ref.read(libraryStoreProvider);

  /// Records a watch event.
  Future<void> recordWatch(BrowseVideo video, int positionMs) async {
    await _store.upsertHistory(video: video, lastPositionMs: positionMs);
    _ref.invalidate(watchHistoryProvider);
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(recommendedFeedProvider);
  }

  /// Clears history.
  Future<void> clearHistory() async {
    await _store.clearHistory();
    _ref.invalidate(watchHistoryProvider);
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(recommendedFeedProvider);
  }

  /// Removes one video from watch history. Does not delete files.
  Future<void> deleteHistory(String videoId) async {
    await _store.deleteHistory(videoId);
    _ref.invalidate(watchHistoryProvider);
    _ref.invalidate(continueWatchingProvider);
    _ref.invalidate(recommendedFeedProvider);
  }

  /// Creates a playlist.
  Future<String> createPlaylist(String name) async {
    final String id = await _store.createPlaylist(name);
    _ref.invalidate(localPlaylistsProvider);
    return id;
  }

  /// Adds [video] to [playlistId].
  Future<void> addToPlaylist(String playlistId, BrowseVideo video) async {
    await _store.addToPlaylist(playlistId, video);
    _ref.invalidate(localPlaylistsProvider);
  }

  /// Removes one video from a playlist. Does not delete files.
  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    await _store.removeFromPlaylist(playlistId, videoId);
    _ref.invalidate(localPlaylistsProvider);
  }

  /// Deletes a playlist.
  Future<void> deletePlaylist(String playlistId) async {
    await _store.deletePlaylist(playlistId);
    _ref.invalidate(localPlaylistsProvider);
  }

  /// Follows a channel.
  Future<void> follow(FollowedChannel channel) async {
    await _store.followChannel(channel);
    _ref.invalidate(followedChannelsProvider);
  }

  /// Unfollows a channel.
  Future<void> unfollow(String channelId) async {
    await _store.unfollowChannel(channelId);
    _ref.invalidate(followedChannelsProvider);
  }

  /// Saves a submitted search keyword.
  Future<void> saveSearch(String query) async {
    await _store.addSearch(query);
    _ref.invalidate(searchHistoryProvider);
    _ref.invalidate(recommendedFeedProvider);
  }

  /// Removes one saved search keyword.
  Future<void> deleteSearch(String query) async {
    await _store.deleteSearch(query);
    _ref.invalidate(searchHistoryProvider);
    _ref.invalidate(recommendedFeedProvider);
  }
}

/// Library mutation helper.
final Provider<LibraryActions> libraryActionsProvider = Provider<LibraryActions>(
  (Ref ref) => LibraryActions(ref),
);
