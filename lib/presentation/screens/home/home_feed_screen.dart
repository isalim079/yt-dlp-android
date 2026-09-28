/// YouTube-like Home: continue watching, followed channels, popular.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/permission_handler_util.dart';
import '../../../core/utils/share_intent_handler.dart';
import '../../../data/local/library_store.dart';
import '../../../data/models/browse_video.dart';
import '../../../data/providers/browse_providers.dart';
import '../../../data/providers/library_providers.dart';
import '../../../data/providers/player_provider.dart';
import '../../widgets/browse/browse_video_tile.dart';
import 'home_screen.dart';

/// Feed home tab.
class HomeFeedScreen extends ConsumerStatefulWidget {
  /// Creates the feed home.
  const HomeFeedScreen({super.key});

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PermissionHandlerUtil.ensureStoragePermission(context);
      ShareIntentHandler.initialize(ref);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(trendingProvider);
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(followedFeedProvider);
    await Future.wait(<Future<Object?>>[
      ref.read(trendingProvider.future),
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
    final AsyncValue<List<BrowseVideo>> trending = ref.watch(trendingProvider);

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
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            continueWatching.maybeWhen(
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
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            followed.maybeWhen(
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
            trending.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace stack) => Padding(
                padding: const EdgeInsets.all(AppDimensions.paddingLg),
                child: Column(
                  children: <Widget>[
                    const Text(
                      AppStrings.homeFeedEmpty,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),
                    FilledButton(
                      onPressed: () => ref.invalidate(trendingProvider),
                      child: const Text(AppStrings.retryButton),
                    ),
                  ],
                ),
              ),
              data: (List<BrowseVideo> videos) {
                if (videos.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Text(AppStrings.homeFeedEmpty),
                  );
                }
                return _VerticalSection(
                  title: AppStrings.trendingNow,
                  videos: videos,
                );
              },
            ),
            const SizedBox(height: 88),
          ],
        ),
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
