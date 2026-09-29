/// Vertical Shorts feed (YouTube-style swipe).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/models/browse_video.dart';
import '../../../data/providers/feed_providers.dart';
import '../../../data/providers/player_provider.dart';

/// Full-bleed vertical Shorts pager.
class ShortsFeedScreen extends ConsumerStatefulWidget {
  /// Creates the Shorts tab.
  const ShortsFeedScreen({super.key});

  @override
  ConsumerState<ShortsFeedScreen> createState() => _ShortsFeedScreenState();
}

class _ShortsFeedScreenState extends ConsumerState<ShortsFeedScreen> {
  final PageController _pageController = PageController();
  int _index = 0;
  bool _started = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _playAt(int index, List<BrowseVideo> items) async {
    if (index < 0 || index >= items.length) {
      return;
    }
    await ref.read(playerControllerProvider.notifier).play(
          items[index],
          queue: items,
          index: index,
          expanded: false,
          shortsMode: true,
        );
    final int remaining = items.length - index - 1;
    if (remaining < 3 || index >= items.length - 5) {
      unawaited(ref.read(shortsPagedFeedProvider.notifier).loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final PagedFeedState feed = ref.watch(shortsPagedFeedProvider);
    final PlayerUiState player = ref.watch(playerControllerProvider);
    final VideoController? controller =
        ref.read(playerControllerProvider.notifier).videoController;
    final List<BrowseVideo> items = feed.items;

    if (!_started && items.isNotEmpty) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_playAt(0, items));
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: feed.loadingInitial && items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : feed.error != null && items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.paddingLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          AppStrings.shortsEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textPrimary),
                        ),
                        const SizedBox(height: AppDimensions.spaceMd),
                        FilledButton(
                          onPressed: () => ref
                              .read(shortsPagedFeedProvider.notifier)
                              .loadInitial(),
                          child: const Text(AppStrings.retryButton),
                        ),
                      ],
                    ),
                  ),
                )
              : items.isEmpty
                  ? Center(
                      child: Text(
                        AppStrings.shortsEmpty,
                        style: TextStyle(color: c.textSecondary),
                      ),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      scrollDirection: Axis.vertical,
                      itemCount: items.length,
                      onPageChanged: (int page) {
                        setState(() => _index = page);
                        unawaited(_playAt(page, items));
                      },
                      itemBuilder: (BuildContext context, int index) {
                        final BrowseVideo video = items[index];
                        final bool active = index == _index;
                        return Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            if (active &&
                                controller != null &&
                                player.video?.id == video.id)
                              Video(
                                controller: controller,
                                controls: NoVideoControls,
                                fit: BoxFit.contain,
                              )
                            else
                              ColoredBox(
                                color: Colors.black,
                                child: video.thumbnail != null
                                    ? Image.network(
                                        video.thumbnail!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (
                                          BuildContext context,
                                          Object error,
                                          StackTrace? stack,
                                        ) =>
                                            const SizedBox.shrink(),
                                      )
                                    : null,
                              ),
                            if (player.loading && active)
                              const Center(child: CircularProgressIndicator()),
                            Positioned(
                              left: 16,
                              right: 72,
                              bottom: 48,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (video.uploader != null)
                                    Text(
                                      '@${video.uploader}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    video.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (feed.loadingMore && index == items.length - 1)
                              const Positioned(
                                bottom: 16,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
    );
  }
}
