/// Persistent mini-player over the bottom navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/providers/player_provider.dart';

/// Compact bar that keeps playback visible while browsing.
class MiniPlayerBar extends ConsumerWidget {
  /// Creates the mini-player.
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PlayerUiState playerState = ref.watch(playerControllerProvider);
    if (!playerState.hasSession || playerState.expanded) {
      return const SizedBox.shrink();
    }
    final AppUiColors c = AppColors.of(context);
    final VideoController? controller = ref
        .read(playerControllerProvider.notifier)
        .videoController;
    return Material(
      color: c.surface,
      elevation: 8,
      child: InkWell(
        onTap: () => ref.read(playerControllerProvider.notifier).expand(),
        child: SizedBox(
          height: 64,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 112,
                height: 64,
                child: controller == null
                    ? ColoredBox(color: c.border)
                    : Video(
                        controller: controller,
                        controls: NoVideoControls,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: AppDimensions.spaceSm),
              Expanded(
                child: Text(
                  playerState.video?.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () {
                  ref.read(playerControllerProvider.notifier).rawPlayer?.play();
                },
              ),
              IconButton(
                icon: const Icon(Icons.pause_rounded),
                onPressed: () {
                  ref.read(playerControllerProvider.notifier).rawPlayer?.pause();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  ref.read(playerControllerProvider.notifier).stop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
