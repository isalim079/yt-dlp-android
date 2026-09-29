/// YouTube-like Home: continue watching, followed channels, infinite recommended.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/share_intent_handler.dart';
import '../../../data/local/library_store.dart';
import '../../../data/models/browse_video.dart';
import '../../../data/providers/app_navigation_providers.dart';
import '../../../data/providers/browse_providers.dart';
import '../../../data/providers/feed_providers.dart';
import '../../../data/providers/library_providers.dart';
import '../../../data/providers/player_provider.dart';
import '../../widgets/browse/browse_video_tile.dart';
import '../../widgets/common/app_snackbar.dart';
import 'home_screen.dart';

/// Feed home tab.
class HomeFeedScreen extends ConsumerStatefulWidget {
  /// Creates the feed home.
  const HomeFeedScreen({super.key});

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShareIntentHandler.initialize(ref);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 800) {
      ref.read(homePagedFeedProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(watchHistoryProvider);
    ref.invalidate(searchHistoryProvider);
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(followedFeedProvider);
    await ref.read(homePagedFeedProvider.notifier).loadInitial();
    await Future.wait(<Future<Object?>>[
      ref.read(continueWatchingProvider.future),
      ref.read(followedFeedProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final AsyncValue<List<WatchHistoryEntry>> continueWatching = ref.watch(
      continueWatchingProvider,
    );
    final AsyncValue<List<BrowseVideo>> followed = ref.watch(
      followedFeedProvider,
    );
    final PagedFeedState feed = ref.watch(homePagedFeedProvider);
    final List<WatchHistoryEntry> continueRows =
        continueWatching.valueOrNull ?? const <WatchHistoryEntry>[];
    final List<BrowseVideo> followedRows =
        followed.valueOrNull ?? const <BrowseVideo>[];
    final List<BrowseVideo> recommendedRows = feed.items;
    final bool showEmptyHome =
        !continueWatching.isLoading &&
        !followed.isLoading &&
        !feed.loadingInitial &&
        continueRows.isEmpty &&
        followedRows.isEmpty &&
        recommendedRows.isEmpty;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.pasteUrlTitle,
            icon: const Icon(Icons.link_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HomeScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: continueWatching.maybeWhen(
                data: (List<WatchHistoryEntry> rows) {
                  if (rows.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _HorizontalSection(
                    title: AppStrings.continueWatching,
                    children: rows
                        .map(
                          (WatchHistoryEntry e) => Padding(
                            padding: const EdgeInsets.only(
                              right: AppDimensions.spaceSm,
                            ),
                            child: BrowseVideoTile(
                              video: e.video,
                              compact: true,
                              onTap: () => ref
                                  .read(playerControllerProvider.notifier)
                                  .play(e.video),
                              onRemove: () async {
                                await ref
                                    .read(libraryActionsProvider)
                                    .deleteHistory(e.video.id);
                                if (context.mounted) {
                                  AppSnackbar.showSuccess(
                                    context,
                                    AppStrings.removedFromLibrary,
                                  );
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            SliverToBoxAdapter(
              child: followed.maybeWhen(
                data: (List<BrowseVideo> videos) {
                  if (videos.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _VerticalSection(
                    title: AppStrings.fromYourChannels,
                    videos: videos,
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            if (feed.loadingInitial && recommendedRows.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (feed.error != null && recommendedRows.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppDimensions.paddingLg),
                  child: Column(
                    children: <Widget>[
                      const Text(
                        AppStrings.homeFeedEmpty,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      FilledButton(
                        onPressed: () => ref
                            .read(homePagedFeedProvider.notifier)
                            .loadInitial(),
                        child: const Text(AppStrings.retryButton),
                      ),
                    ],
                  ),
                ),
              )
            else if (recommendedRows.isNotEmpty) ...<Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimensions.paddingMd,
                    AppDimensions.spaceLg,
                    AppDimensions.paddingMd,
                    AppDimensions.spaceSm,
                  ),
                  child: Text(
                    AppStrings.recommendedForYou,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                    final BrowseVideo v = recommendedRows[index];
                    return BrowseVideoTile(
                      video: v,
                      onTap: () =>
                          ref.read(playerControllerProvider.notifier).play(v),
                    );
                  },
                  childCount: recommendedRows.length,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: feed.loadingMore
                        ? const CircularProgressIndicator()
                        : feed.exhausted
                            ? Text(
                                AppStrings.homeFeedEnd,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
            if (showEmptyHome)
              SliverToBoxAdapter(
                child: _EmptyHome(
                  onSearch: () =>
                      ref.read(tabIndexProvider.notifier).goTo(AppTabs.search),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 88)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.paddingLg,
        64,
        AppDimensions.paddingLg,
        AppDimensions.spaceXl,
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.search_rounded,
            size: 64,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          Text(
            AppStrings.homeEmptyFeedTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          Text(
            AppStrings.homeEmptyFeedSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),
          FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
            label: const Text(AppStrings.homeEmptyFeedAction),
          ),
        ],
      ),
    );
  }
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimensions.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMd,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          SizedBox(
            height: 150,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMd,
              ),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalSection extends ConsumerWidget {
  const _VerticalSection({required this.title, required this.videos});

  final String title;
  final List<BrowseVideo> videos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.paddingMd,
            AppDimensions.spaceLg,
            AppDimensions.paddingMd,
            AppDimensions.spaceSm,
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...videos.map(
          (BrowseVideo v) => BrowseVideoTile(
            video: v,
            onTap: () => ref.read(playerControllerProvider.notifier).play(v),
          ),
        ),
      ],
    );
  }
}
