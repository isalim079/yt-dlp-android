/// Paged Home / Shorts feed state for infinite scroll.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/logger.dart';
import '../local/library_store.dart';
import '../models/browse_video.dart';
import '../models/feed_page.dart';
import '../services/browse_service.dart';
import '../services/feed_service.dart';
import 'library_providers.dart';
import 'ytdlp_providers.dart';

/// Snapshot of an infinite feed.
@immutable
class PagedFeedState {
  /// Creates feed UI state.
  const PagedFeedState({
    this.items = const <BrowseVideo>[],
    this.continuation,
    this.loadingInitial = false,
    this.loadingMore = false,
    this.error,
  });

  /// Accumulated videos (deduped).
  final List<BrowseVideo> items;

  /// Next-page token.
  final String? continuation;

  /// First page in flight.
  final bool loadingInitial;

  /// Subsequent page in flight.
  final bool loadingMore;

  /// Last error message.
  final String? error;

  /// Whether another page may exist.
  bool get hasMore {
    final String? token = continuation;
    return token != null && token.isNotEmpty;
  }

  /// No more pages and not loading.
  bool get exhausted => !hasMore && !loadingInitial && !loadingMore;

  /// Copy with overrides.
  PagedFeedState copyWith({
    List<BrowseVideo>? items,
    String? continuation,
    bool clearContinuation = false,
    bool? loadingInitial,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) {
    return PagedFeedState(
      items: items ?? this.items,
      continuation:
          clearContinuation ? null : (continuation ?? this.continuation),
      loadingInitial: loadingInitial ?? this.loadingInitial,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

enum FeedKind { home, shorts }

/// How many unique items one loadMore / Shorts initial fill should aim for.
const int kFeedMinUniqueBatch = 8;

/// Max continuation follows inside one fill call.
const int kFeedMaxFillPages = 5;

/// Result of merging overlapping feed pages until enough unique IDs.
@immutable
class FeedFillResult {
  /// Creates a fill result.
  const FeedFillResult({
    required this.items,
    required this.continuation,
    required this.added,
  });

  /// Full deduped list after fill.
  final List<BrowseVideo> items;

  /// Next token (null when exhausted).
  final String? continuation;

  /// How many new unique ids were appended in this fill.
  final int added;

  /// Whether another page may exist.
  bool get hasMore {
    final String? token = continuation;
    return token != null && token.isNotEmpty;
  }
}

/// Pure fill-until-unique loop (unit-testable).
FeedFillResult fillUniquePages({
  required List<BrowseVideo> existing,
  required String? startContinuation,
  required List<FeedPage> pages,
  int minUnique = kFeedMinUniqueBatch,
}) {
  List<BrowseVideo> items = List<BrowseVideo>.from(existing);
  final Set<String> seen = <String>{
    for (final BrowseVideo v in items)
      if (v.id.isNotEmpty) v.id,
  };
  String? continuation = startContinuation;
  int added = 0;

  for (final FeedPage page in pages) {
    final int before = seen.length;
    for (final BrowseVideo v in page.items) {
      if (v.id.isEmpty || !seen.add(v.id)) {
        continue;
      }
      items.add(v);
      added += 1;
    }
    final int gained = seen.length - before;
    final String? next = page.continuation;
    if (gained == 0 &&
        next != null &&
        next.isNotEmpty &&
        next == continuation) {
      // Stuck token with no new ids — exhaust.
      continuation = null;
      break;
    }
    continuation = next;
    if (added >= minUnique) {
      break;
    }
    if (continuation == null || continuation.isEmpty) {
      break;
    }
  }

  return FeedFillResult(
    items: items,
    continuation: continuation,
    added: added,
  );
}

/// Shared paging logic for Home and Shorts.
class PagedFeedController extends Notifier<PagedFeedState> {
  /// Creates a controller for [kind].
  PagedFeedController(this.kind);

  /// Which feed this controller loads.
  final FeedKind kind;
  bool _loadMoreInFlight = false;

  @override
  PagedFeedState build() {
    Future<void>.microtask(loadInitial);
    return const PagedFeedState(loadingInitial: true);
  }

  FeedService get _feeds =>
      FeedService(ytdlp: ref.read(ytdlpServiceProvider));

  /// Pull-to-refresh / first open.
  Future<void> loadInitial() async {
    state = state.copyWith(
      loadingInitial: true,
      clearError: true,
      clearContinuation: true,
      items: const <BrowseVideo>[],
    );
    try {
      if (kind == FeedKind.shorts) {
        final FeedFillResult filled = await _fillFrom(
          existing: const <BrowseVideo>[],
          startContinuation: null,
          minUnique: kFeedMinUniqueBatch,
        );
        state = PagedFeedState(
          items: filled.items,
          continuation: filled.continuation,
          loadingInitial: false,
        );
        return;
      }

      FeedPage page = await _fetch(continuation: null);
      if (page.items.isEmpty) {
        page = await _mergeLocalRecommend(page);
      } else {
        page = await _prependLocalRecommend(page);
      }
      state = PagedFeedState(
        items: dedupe(page.items),
        continuation: page.continuation,
        loadingInitial: false,
      );
    } on Object catch (error) {
      state = PagedFeedState(
        loadingInitial: false,
        error: error.toString(),
      );
    }
  }

  /// Append pages until enough unique IDs (Shorts) or one page (Home).
  Future<void> loadMore() async {
    if (_loadMoreInFlight ||
        state.loadingInitial ||
        state.loadingMore ||
        !state.hasMore) {
      return;
    }
    _loadMoreInFlight = true;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      if (kind == FeedKind.shorts) {
        final FeedFillResult filled = await _fillFrom(
          existing: state.items,
          startContinuation: state.continuation,
          minUnique: kFeedMinUniqueBatch,
        );
        state = state.copyWith(
          items: filled.items,
          continuation: filled.continuation,
          clearContinuation: !filled.hasMore,
          loadingMore: false,
        );
        return;
      }

      final FeedPage page = await _fetch(continuation: state.continuation);
      final List<BrowseVideo> merged = dedupe(<BrowseVideo>[
        ...state.items,
        ...page.items,
      ]);
      final int added = merged.length - state.items.length;
      // Home: if zero new but same token, exhaust.
      final bool stuck = added == 0 &&
          page.continuation != null &&
          page.continuation == state.continuation;
      state = state.copyWith(
        items: merged,
        continuation: stuck ? null : page.continuation,
        clearContinuation: stuck || !page.hasMore,
        loadingMore: false,
      );
    } on Object catch (error) {
      state = state.copyWith(
        loadingMore: false,
        error: error.toString(),
      );
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<FeedFillResult> _fillFrom({
    required List<BrowseVideo> existing,
    required String? startContinuation,
    required int minUnique,
  }) async {
    List<BrowseVideo> items = List<BrowseVideo>.from(existing);
    String? token = startContinuation;
    int added = 0;
    int pages = 0;

    while (pages < kFeedMaxFillPages && added < minUnique) {
      pages += 1;
      final String? previous = token;
      final FeedPage page = await _fetch(continuation: token);
      final FeedFillResult step = fillUniquePages(
        existing: items,
        startContinuation: previous,
        pages: <FeedPage>[page],
        minUnique: minUnique,
      );
      final int gained = step.items.length - items.length;
      items = step.items;
      added += gained;
      token = step.continuation;

      if (gained == 0 &&
          (token == null ||
              token.isEmpty ||
              token == previous)) {
        token = null;
        break;
      }
      if (token == null || token.isEmpty) {
        break;
      }
    }

    AppLogger.i(
      'feed=${kind.name} fill added=$added uniqueTotal=${items.length} '
      'hasMore=${token != null && token.isNotEmpty}',
    );

    return FeedFillResult(
      items: items,
      continuation: token,
      added: added,
    );
  }

  Future<FeedPage> _fetch({String? continuation}) {
    switch (kind) {
      case FeedKind.home:
        return _feeds.homeFeed(continuation: continuation);
      case FeedKind.shorts:
        return _feeds.shortsFeed(continuation: continuation);
    }
  }

  Future<FeedPage> _mergeLocalRecommend(FeedPage empty) async {
    final List<BrowseVideo> local = await _localRecommend();
    if (local.isEmpty) {
      return empty;
    }
    return FeedPage(items: local, continuation: empty.continuation);
  }

  Future<FeedPage> _prependLocalRecommend(FeedPage page) async {
    final List<BrowseVideo> local = await _localRecommend();
    if (local.isEmpty) {
      return page;
    }
    return FeedPage(
      items: <BrowseVideo>[...local, ...page.items],
      continuation: page.continuation,
    );
  }

  Future<List<BrowseVideo>> _localRecommend() async {
    try {
      final List<String> searches =
          await ref.read(searchHistoryProvider.future);
      final List<WatchHistoryEntry> history =
          await ref.read(watchHistoryProvider.future);
      if (searches.isEmpty && history.isEmpty) {
        return const <BrowseVideo>[];
      }
      return await BrowseService(ytdlp: ref.read(ytdlpServiceProvider)).recommend(
        searchQueries: searches,
        watched: history
            .map((WatchHistoryEntry e) => e.video)
            .toList(),
        limit: 12,
      );
    } on Object {
      return const <BrowseVideo>[];
    }
  }

  /// Deduplicate by video id (public for unit tests).
  static List<BrowseVideo> dedupe(List<BrowseVideo> input) {
    final Set<String> seen = <String>{};
    final List<BrowseVideo> out = <BrowseVideo>[];
    for (final BrowseVideo v in input) {
      if (v.id.isEmpty || !seen.add(v.id)) {
        continue;
      }
      out.add(v);
    }
    return out;
  }
}

/// Test / empty override that never hits the network.
class IdlePagedFeedController extends PagedFeedController {
  /// Creates an idle home feed.
  IdlePagedFeedController() : super(FeedKind.home);

  @override
  PagedFeedState build() => const PagedFeedState();

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> loadMore() async {}
}

/// Infinite Home recommended feed.
final NotifierProvider<PagedFeedController, PagedFeedState>
    homePagedFeedProvider =
    NotifierProvider<PagedFeedController, PagedFeedState>(
  () => PagedFeedController(FeedKind.home),
);

/// Infinite Shorts feed.
final NotifierProvider<PagedFeedController, PagedFeedState>
    shortsPagedFeedProvider =
    NotifierProvider<PagedFeedController, PagedFeedState>(
  () => PagedFeedController(FeedKind.shorts),
);

/// Root tab indices (Home | Shorts | Search | Library | Settings).
abstract final class AppTabs {
  /// Home feed.
  static const int home = 0;

  /// Vertical Shorts.
  static const int shorts = 1;

  /// Search.
  static const int search = 2;

  /// Library / downloads.
  static const int library = 3;

  /// Settings.
  static const int settings = 4;
}
