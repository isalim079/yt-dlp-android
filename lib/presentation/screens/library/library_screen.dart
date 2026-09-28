/// Library tab: history, local playlists, followed channels, downloads.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/youtube_urls.dart';
import '../../../data/local/library_store.dart';
import '../../../data/models/browse_video.dart';
import '../../../data/providers/browse_providers.dart';
import '../../../data/providers/library_providers.dart';
import '../../../data/providers/player_provider.dart';
import '../../widgets/browse/browse_video_tile.dart';
import '../../widgets/common/app_snackbar.dart';
import '../download/download_screen.dart';

/// Library shell with subsection chips.
class LibraryScreen extends ConsumerWidget {
  /// Creates the library tab.
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUiColors c = AppColors.of(context);
    final LibrarySection section = ref.watch(librarySectionProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text(AppStrings.libraryTitle),
        actions: <Widget>[
          if (section == LibrarySection.history)
            IconButton(
              tooltip: AppStrings.clearWatchHistory,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(libraryActionsProvider).clearHistory();
                if (context.mounted) {
                  AppSnackbar.showSuccess(
                    context,
                    AppStrings.watchHistoryCleared,
                  );
                }
              },
            ),
          if (section == LibrarySection.playlists)
            IconButton(
              tooltip: AppStrings.newPlaylist,
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _createPlaylist(context, ref),
            ),
          if (section == LibrarySection.channels)
            IconButton(
              tooltip: AppStrings.followChannel,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => _followChannel(context, ref),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMd,
              vertical: AppDimensions.spaceSm,
            ),
            child: Row(
              children: <Widget>[
                _chip(ref, LibrarySection.history, AppStrings.libraryHistory),
                _chip(ref, LibrarySection.playlists, AppStrings.libraryPlaylists),
                _chip(ref, LibrarySection.channels, AppStrings.libraryChannels),
                _chip(ref, LibrarySection.downloads, AppStrings.navDownloads),
              ],
            ),
          ),
          Expanded(child: _sectionBody(section)),
        ],
      ),
    );
  }

  Widget _chip(WidgetRef ref, LibrarySection value, String label) {
    final bool selected = ref.watch(librarySectionProvider) == value;
    return Padding(
      padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            ref.read(librarySectionProvider.notifier).state = value,
      ),
    );
  }

  Widget _sectionBody(LibrarySection section) {
    switch (section) {
      case LibrarySection.history:
        return const _HistoryBody();
      case LibrarySection.playlists:
        return const _PlaylistsBody();
      case LibrarySection.channels:
        return const _ChannelsBody();
      case LibrarySection.downloads:
        return const DownloadScreen(embedded: true);
    }
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text(AppStrings.newPlaylist),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: AppStrings.playlistNameHint,
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(AppStrings.createPlaylist),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) {
      return;
    }
    await ref.read(libraryActionsProvider).createPlaylist(name);
  }

  Future<void> _followChannel(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text(AppStrings.followChannel),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://www.youtube.com/@channel',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(AppStrings.followChannel),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) {
      return;
    }
    try {
      final listing = await ref.read(browseServiceProvider).listing(url);
      final String id = YoutubeUrls.channelId(url) ?? url;
      await ref.read(libraryActionsProvider).follow(
        FollowedChannel(
          id: id,
          title: listing.title.isEmpty ? id : listing.title,
          url: YoutubeUrls.channelVideosUrl(url) ?? url,
          followedAt: DateTime.now(),
        ),
      );
      if (context.mounted) {
        AppSnackbar.showSuccess(context, AppStrings.channelFollowed);
      }
    } on Object {
      if (context.mounted) {
        AppSnackbar.showError(context, AppStrings.errorGeneric);
      }
    }
  }
}

class _HistoryBody extends ConsumerWidget {
  const _HistoryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WatchHistoryEntry>> history = ref.watch(
      watchHistoryProvider,
    );
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) =>
          const Center(child: Text(AppStrings.errorGeneric)),
      data: (List<WatchHistoryEntry> rows) {
        if (rows.isEmpty) {
          return const Center(child: Text(AppStrings.historyEmpty));
        }
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (BuildContext context, int index) {
            final WatchHistoryEntry e = rows[index];
            return BrowseVideoTile(
              video: e.video,
              onTap: () =>
                  ref.read(playerControllerProvider.notifier).play(e.video),
            );
          },
        );
      },
    );
  }
}

class _PlaylistsBody extends ConsumerWidget {
  const _PlaylistsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LocalPlaylist>> playlists = ref.watch(
      localPlaylistsProvider,
    );
    return playlists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) =>
          const Center(child: Text(AppStrings.errorGeneric)),
      data: (List<LocalPlaylist> items) {
        return ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text(AppStrings.importPlaylist),
              onTap: () => _importPlaylist(context, ref),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text(AppStrings.playlistsEmpty)),
              ),
            ...items.map((LocalPlaylist p) {
              return ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(p.name),
                subtitle: Text('${p.items.length}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () =>
                      ref.read(libraryActionsProvider).deletePlaylist(p.id),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _PlaylistDetail(playlist: p),
                    ),
                  );
                },
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _importPlaylist(BuildContext context, WidgetRef ref) async {
    final TextEditingController controller = TextEditingController();
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text(AppStrings.importPlaylist),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://www.youtube.com/playlist?list=…',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text(AppStrings.importPlaylist),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) {
      return;
    }
    try {
      final listing = await ref.read(browseServiceProvider).listing(url);
      final String id = await ref
          .read(libraryActionsProvider)
          .createPlaylist(
            listing.title.isEmpty ? AppStrings.libraryPlaylists : listing.title,
          );
      for (final entry in listing.entries) {
        await ref
            .read(libraryActionsProvider)
            .addToPlaylist(id, BrowseVideo.fromPlaylistEntry(entry));
      }
      if (context.mounted) {
        AppSnackbar.showSuccess(context, AppStrings.playlistImported);
      }
    } on Object {
      if (context.mounted) {
        AppSnackbar.showError(context, AppStrings.errorGeneric);
      }
    }
  }
}

class _PlaylistDetail extends ConsumerWidget {
  const _PlaylistDetail({required this.playlist});

  final LocalPlaylist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LocalPlaylist>> latest = ref.watch(
      localPlaylistsProvider,
    );
    final LocalPlaylist current = latest.maybeWhen(
      data: (List<LocalPlaylist> all) => all.firstWhere(
        (LocalPlaylist p) => p.id == playlist.id,
        orElse: () => playlist,
      ),
      orElse: () => playlist,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(current.name),
        actions: <Widget>[
          TextButton(
            onPressed: current.items.isEmpty
                ? null
                : () {
                    ref.read(playerControllerProvider.notifier).play(
                      current.items.first,
                      queue: current.items,
                    );
                  },
            child: const Text(AppStrings.playAll),
          ),
        ],
      ),
      body: ListView(
        children: current.items
            .map(
              (BrowseVideo v) => BrowseVideoTile(
                video: v,
                onTap: () => ref.read(playerControllerProvider.notifier).play(
                  v,
                  queue: current.items,
                  index: current.items.indexOf(v),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ChannelsBody extends ConsumerWidget {
  const _ChannelsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FollowedChannel>> channels = ref.watch(
      followedChannelsProvider,
    );
    return channels.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) =>
          const Center(child: Text(AppStrings.errorGeneric)),
      data: (List<FollowedChannel> items) {
        if (items.isEmpty) {
          return const Center(child: Text(AppStrings.channelsEmpty));
        }
        return ListView(
          children: items
              .map(
                (FollowedChannel ch) => ListTile(
                  leading: const Icon(Icons.subscriptions_outlined),
                  title: Text(ch.title),
                  subtitle: Text(ch.url),
                  trailing: IconButton(
                    tooltip: AppStrings.unfollowChannel,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () =>
                        ref.read(libraryActionsProvider).unfollow(ch.id),
                  ),
                  onTap: () async {
                    final List<BrowseVideo> videos = await ref
                        .read(browseServiceProvider)
                        .channelUploads(ch.url);
                    if (videos.isEmpty) {
                      return;
                    }
                    await ref.read(playerControllerProvider.notifier).play(
                      videos.first,
                      queue: videos,
                    );
                  },
                ),
              )
              .toList(),
        );
      },
    );
  }
}
