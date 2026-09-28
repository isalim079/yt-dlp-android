/// Fullscreen watch page with quality, download, and related channel videos.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_ui_colors.dart';
import '../../core/utils/permission_handler_util.dart';
import '../../data/models/browse_video.dart';
import '../../data/models/playback_resolved.dart';
import '../../data/providers/browse_providers.dart';
import '../../data/providers/library_providers.dart';
import '../../data/providers/player_provider.dart';
import '../../data/providers/settings_providers.dart';
import '../../data/local/library_store.dart';
import '../widgets/browse/browse_video_tile.dart';
import '../widgets/common/app_snackbar.dart';

/// Expanded in-app player.
class WatchPage extends ConsumerWidget {
  /// Creates the watch page.
  const WatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerUiState playerState = ref.watch(playerControllerProvider);
    final AppUiColors c = AppColors.of(context);
    final VideoController? controller = ref
        .read(playerControllerProvider.notifier)
        .videoController;
    final int surfaceEpoch = playerState.surfaceEpoch;
    final BrowseVideo? video = playerState.video;
    if (video == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: c.background,
      child: SafeArea(
        child: Column(
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  ColoredBox(
                    color: Colors.black,
                    child: controller == null
                        ? const Center(child: CircularProgressIndicator())
                        : Video(
                            key: ValueKey<int>(surfaceEpoch),
                            controller: controller,
                            controls: AdaptiveVideoControls,
                            wakelock: true,
                          ),
                  ),
                  if (playerState.loading)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              AppStrings.resolvingStream,
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).collapse(),
                    ),
                  ),
                ],
              ),
            ),
            if (playerState.error != null)
              Padding(
                padding: const EdgeInsets.all(AppDimensions.paddingMd),
                child: Text(
                  playerState.error!,
                  style: TextStyle(color: c.error),
                ),
              ),
            Expanded(
              child: ListView(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(AppDimensions.paddingMd),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          video.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppDimensions.spaceXs),
                        Text(
                          video.uploader ?? AppStrings.notAvailable,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingMd,
                    ),
                    child: Row(
                      children: <Widget>[
                        _ActionChip(
                          icon: Icons.download_rounded,
                          label: AppStrings.playerDownload,
                          onTap: () async {
                            final bool allowed =
                                await PermissionHandlerUtil.ensureStoragePermission(
                                  context,
                                  outputPath: ref.read(outputPathProvider),
                                );
                            if (!allowed) {
                              return;
                            }
                            await ref
                                .read(playerControllerProvider.notifier)
                                .downloadCurrent();
                            if (context.mounted) {
                              AppSnackbar.showSuccess(
                                context,
                                AppStrings.downloadStarted,
                              );
                            }
                          },
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        _ActionChip(
                          icon: Icons.high_quality_outlined,
                          label: playerState.quality.label,
                          onTap: () => _showQualitySheet(context, ref),
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        _ActionChip(
                          icon: Icons.speed_rounded,
                          label: AppStrings.playerSpeed,
                          onTap: () => _showSpeedSheet(context, ref),
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        _ActionChip(
                          icon: Icons.playlist_add_rounded,
                          label: AppStrings.addToPlaylist,
                          onTap: () => _showAddToPlaylist(context, ref, video),
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        _ActionChip(
                          icon: Icons.picture_in_picture_alt_rounded,
                          label: AppStrings.pipButton,
                          onTap: () => ref
                              .read(playerControllerProvider.notifier)
                              .enterPip(),
                        ),
                        if (video.channelUrl != null) ...<Widget>[
                          const SizedBox(width: AppDimensions.spaceSm),
                          _ActionChip(
                            icon: Icons.subscriptions_outlined,
                            label: AppStrings.followChannel,
                            onTap: () async {
                              await ref
                                  .read(playerControllerProvider.notifier)
                                  .followCurrentChannel();
                              if (context.mounted) {
                                AppSnackbar.showSuccess(
                                  context,
                                  AppStrings.channelFollowed,
                                );
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimensions.paddingMd,
                    ),
                    child: Text(
                      AppStrings.relatedVideos,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _RelatedList(channelUrl: video.channelUrl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context, WidgetRef ref) {
    const List<double> rates = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text(AppStrings.playerSpeed)),
              ...rates.map((double rate) {
                return ListTile(
                  title: Text('${rate}x'),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref
                        .read(playerControllerProvider.notifier)
                        .rawPlayer
                        ?.setRate(rate);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showQualitySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(title: Text(AppStrings.playerQuality)),
              ...PlaybackQuality.values.map((PlaybackQuality q) {
                return ListTile(
                  title: Text(q.label),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(playerControllerProvider.notifier).setQuality(q);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddToPlaylist(
    BuildContext context,
    WidgetRef ref,
    BrowseVideo video,
  ) async {
    final AsyncValue<List<LocalPlaylist>> playlists = ref.read(
      localPlaylistsProvider,
    );
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: playlists.maybeWhen(
            data: (List<LocalPlaylist> items) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(title: Text(AppStrings.addToPlaylist)),
                  if (items.isEmpty)
                    const ListTile(title: Text(AppStrings.playlistsEmpty)),
                  ...items.map((LocalPlaylist p) {
                    return ListTile(
                      title: Text(p.name),
                      onTap: () async {
                        await ref
                            .read(libraryActionsProvider)
                            .addToPlaylist(p.id, video);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (context.mounted) {
                          AppSnackbar.showSuccess(
                            context,
                            AppStrings.addedToPlaylist,
                          );
                        }
                      },
                    );
                  }),
                ],
              );
            },
            orElse: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 18, color: c.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _RelatedList extends ConsumerWidget {
  const _RelatedList({this.channelUrl});

  final String? channelUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channelUrl == null || channelUrl!.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<BrowseVideo>>(
      future: ref.read(browseServiceProvider).channelUploads(channelUrl!),
      builder: (BuildContext context, AsyncSnapshot<List<BrowseVideo>> snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          children: snap.data!
              .map(
                (BrowseVideo v) => BrowseVideoTile(
                  video: v,
                  onTap: () =>
                      ref.read(playerControllerProvider.notifier).play(v),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
