/// Displays a single download item with progress, status, and actions.
library;

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/open_folder.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/download_item.dart';
import '../../../data/services/download_manager.dart';
import '../common/app_progress_bar.dart';
import 'circular_progress_ring.dart';

/// One row in the downloads list with metadata and controls.
class DownloadCard extends StatelessWidget {
  /// Creates a card for [item] bound to [manager].
  const DownloadCard({super.key, required this.item, required this.manager});

  /// Job shown in this card.
  final DownloadItem item;

  /// Coordinator invoked by action buttons.
  final DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double percent = item.progress?.percent ?? 0;
    final bool indeterminate = percent <= 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(AppDimensions.paddingMd),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        border: Border.all(color: c.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ThumbnailPreview(item: item, manager: manager, percent: percent),
              const SizedBox(width: AppDimensions.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceXs),
                    Row(
                      children: <Widget>[
                        _FormatBadge(label: item.selectedFormat.displayLabel),
                        const SizedBox(width: AppDimensions.spaceSm),
                        _StatusBadge(status: item.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (item.status == DownloadStatus.downloading) ...<Widget>[
            const SizedBox(height: AppDimensions.spaceSm),
            AppProgressBar(
              value: item.progress?.percent ?? 0,
              isIndeterminate: indeterminate,
            ),
            const SizedBox(height: AppDimensions.spaceXs),
            Row(
              children: <Widget>[
                Text(
                  item.progress?.percentLabel ?? AppStrings.statusPreparing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (item.progress?.isMerging == true)
                  const _PulsingChip(label: AppStrings.statusProcessing)
                else
                  Text(
                    '${item.progress?.speed ?? '--'}'
                    '${AppStrings.formatLabelSeparator}'
                    'ETA ${item.progress?.eta ?? '--'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
          if (item.status == DownloadStatus.queued) ...<Widget>[
            const SizedBox(height: AppDimensions.spaceSm),
            Row(
              children: <Widget>[
                const _PulsingDot(color: AppColors.warning),
                const SizedBox(width: AppDimensions.spaceXs),
                Text(
                  AppStrings.waitingInQueuePlain,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: c.warning,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (item.status == DownloadStatus.failed &&
              item.errorMessage != null) ...<Widget>[
            const SizedBox(height: AppDimensions.spaceSm),
            Container(
              padding: const EdgeInsets.all(AppDimensions.spaceSm),
              decoration: BoxDecoration(
                color: c.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: c.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                item.errorMessage!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: c.error),
              ),
            ),
          ],
          if (item.status == DownloadStatus.completed) ...<Widget>[
            const SizedBox(height: AppDimensions.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingSm,
                vertical: AppDimensions.spacingXs,
              ),
              decoration: BoxDecoration(
                color: c.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.folder_outlined,
                    size: AppDimensions.iconSm,
                    color: c.success,
                  ),
                  const SizedBox(width: AppDimensions.spacingXs),
                  Expanded(
                    child: Text(
                      item.outputPath,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: c.success,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppDimensions.spaceSm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (item.status == DownloadStatus.completed)
                  _ActionChip(
                    icon: Icons.play_circle_filled_rounded,
                    label: AppStrings.playFile,
                    color: c.primary,
                    filled: true,
                    onTap: () => _showPlayerPicker(context, item),
                  ),
                if (item.isCancellable)
                  _ActionChip(
                    icon: Icons.stop_circle_outlined,
                    label: AppStrings.cancelDownload,
                    color: c.error,
                    filled: false,
                    onTap: () => _showCancelConfirmation(context),
                  ),
                if (item.status == DownloadStatus.failed)
                  _ActionChip(
                    icon: Icons.refresh_rounded,
                    label: AppStrings.retryDownload,
                    color: c.primary,
                    filled: true,
                    onTap: () => manager.retryDownload(item.id),
                  ),
                if (item.status == DownloadStatus.completed ||
                    item.status == DownloadStatus.failed)
                  _ActionChip(
                    icon: Icons.delete_outline_rounded,
                    label: AppStrings.removeDownload,
                    color: c.error,
                    filled: false,
                    onTap: () => manager.removeDownload(item.id),
                  ),
                if (item.status == DownloadStatus.completed)
                  _ActionChip(
                    icon: Icons.folder_open_rounded,
                    label: AppStrings.openFolder,
                    color: c.textSecondary,
                    filled: false,
                    onTap: () => openSystemFolder(
                      item.outputPath,
                      snackbarContext: context,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPlayerPicker(
    BuildContext context,
    DownloadItem item,
  ) async {
    manager.markAsPlayed(item.id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _PlayerPickerSheet(item: item);
      },
    );
  }

  Future<void> _showCancelConfirmation(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final AppUiColors c = AppColors.of(context);
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppDimensions.bottomSheetRadius),
            ),
          ),
          padding: const EdgeInsets.all(AppDimensions.paddingMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              Text(
                AppStrings.cancelDownloadTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              Text(
                AppStrings.cancelDownloadBody,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: AppDimensions.spaceLg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(AppStrings.keepDownloading),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: c.error),
                      onPressed: () {
                        Navigator.of(context).pop();
                        manager.cancelDownload(item.id);
                        HapticFeedback.lightImpact();
                      },
                      child: const Text(AppStrings.cancelDownloadConfirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    final Color bg;
    final Color fg;
    final String label;
    final bool spin = status == DownloadStatus.downloading;

    switch (status) {
      case DownloadStatus.downloading:
        bg = c.primaryLight;
        fg = c.primary;
        label = AppStrings.statusDownloading;
      case DownloadStatus.queued:
        bg = AppColors.warningLight;
        fg = c.warning;
        label = AppStrings.statusQueued;
      case DownloadStatus.completed:
        bg = AppColors.successLight;
        fg = c.success;
        label = AppStrings.statusCompleted;
      case DownloadStatus.failed:
        bg = AppColors.errorLight;
        fg = c.error;
        label = AppStrings.statusFailed;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceSm,
        vertical: AppDimensions.spaceXs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (spin)
            SizedBox(
              width: AppDimensions.iconSm,
              height: AppDimensions.iconSm,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else
            Icon(_iconFor(status), size: AppDimensions.iconSm, color: fg),
          const SizedBox(width: AppDimensions.spaceXs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(DownloadStatus s) {
    return switch (s) {
      DownloadStatus.queued => Icons.schedule_rounded,
      DownloadStatus.completed => Icons.check_rounded,
      DownloadStatus.failed => Icons.error_outline_rounded,
      DownloadStatus.downloading => Icons.download_rounded,
    };
  }
}

class _ActionChip extends StatefulWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_ActionChip> createState() => _ActionChipState();
}

class _ActionChipState extends State<_ActionChip> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppDimensions.spaceSm),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _scale = 0.97),
        onTapUp: (_) => setState(() => _scale = 1),
        onTapCancel: () => setState(() => _scale = 1),
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 100),
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spaceMd,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: widget.filled ? widget.color : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimensions.chipRadius),
              border: Border.all(
                color: widget.filled ? widget.color : c.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.icon,
                  size: 14,
                  color: widget.filled ? Colors.white : widget.color,
                ),
                const SizedBox(width: AppDimensions.spaceXs),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: widget.filled ? Colors.white : widget.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceSm,
        vertical: AppDimensions.spaceXxs,
      ),
      decoration: BoxDecoration(
        color: c.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: c.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ThumbnailPreview extends StatelessWidget {
  const _ThumbnailPreview({
    required this.item,
    required this.manager,
    required this.percent,
  });

  final DownloadItem item;
  final DownloadManager manager;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item.thumbnailUrl!,
                  width: AppDimensions.thumbnailWidth,
                  height: AppDimensions.thumbnailHeight,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    width: AppDimensions.thumbnailWidth,
                    height: AppDimensions.thumbnailHeight,
                    color: AppColors.surfaceAlt,
                  ),
                  errorWidget: (_, _, _) => Container(
                    width: AppDimensions.thumbnailWidth,
                    height: AppDimensions.thumbnailHeight,
                    color: AppColors.surfaceAlt,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_rounded,
                      color: c.textSecondary,
                    ),
                  ),
                )
              : Container(
                  width: AppDimensions.thumbnailWidth,
                  height: AppDimensions.thumbnailHeight,
                  color: AppColors.surfaceAlt,
                ),
        ),
        if (item.status == DownloadStatus.downloading)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
              alignment: Alignment.center,
              child: CircularProgressRing(percent: percent),
            ),
          ),
        if (item.status == DownloadStatus.completed)
          const Positioned(
            bottom: 4,
            right: 4,
            child: _ThumbMark(color: AppColors.success, icon: Icons.check),
          ),
        if (item.status == DownloadStatus.failed)
          const Positioned(
            bottom: 4,
            right: 4,
            child: _ThumbMark(color: AppColors.error, icon: Icons.close),
          ),
        if (item.status == DownloadStatus.completed && !item.isPlayed)
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.unplayed,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.unplayed.withValues(alpha: 0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ThumbMark extends StatelessWidget {
  const _ThumbMark({required this.color, required this.icon});
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

class _PulsingChip extends StatefulWidget {
  const _PulsingChip({required this.label});
  final String label;

  @override
  State<_PulsingChip> createState() => _PulsingChipState();
}

class _PulsingChipState extends State<_PulsingChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceSm,
          vertical: AppDimensions.spaceXs,
        ),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: c.warning,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.6,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

class _PlayerPickerSheet extends StatelessWidget {
  const _PlayerPickerSheet({required this.item});

  final DownloadItem item;

  Future<void> _openWithIntent(
    BuildContext context,
    String filePath,
    String? packageName,
  ) async {
    Navigator.of(context).pop();
    try {
      if (packageName != null) {
        final Uri packageUri = Uri.parse(
          'intent://${Uri.encodeComponent(filePath)}#Intent;type=video/*;'
          'package=$packageName;end',
        );
        if (await canLaunchUrl(packageUri)) {
          await launchUrl(packageUri);
          return;
        }
      }
      await const MethodChannel(
        'com.ytdownloader.app/ytdlp',
      ).invokeMethod<void>('openFile', <String, dynamic>{'path': filePath});
    } on Object catch (e, st) {
      AppLogger.e('Failed to open file', e, st);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.openFailed)));
      }
    }
  }

  Future<String> _resolvePlayablePath() async {
    final Directory dir = Directory(item.outputPath);
    if (!await dir.exists()) {
      return '${item.outputPath}/${item.title}.mp4';
    }
    final List<String> exts = <String>['.mp4', '.mkv', '.webm', '.m4a', '.mp3'];
    await for (final FileSystemEntity entity in dir.list()) {
      if (entity is! File) {
        continue;
      }
      final String lower = entity.path.toLowerCase();
      if (exts.any((String ext) => lower.endsWith(ext))) {
        return entity.path;
      }
    }
    return '${item.outputPath}/${item.title}.mp4';
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return FutureBuilder<String>(
      future: _resolvePlayablePath(),
      builder: (BuildContext context, AsyncSnapshot<String> snap) {
        final String path = snap.data ?? '${item.outputPath}/${item.title}.mp4';
        return Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppDimensions.bottomSheetRadius),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: AppDimensions.spaceSm),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.paddingMd),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.play_circle_outline_rounded,
                        size: 24,
                        color: c.primary,
                      ),
                      const SizedBox(width: AppDimensions.spaceSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              AppStrings.openWith,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: c.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                _PlayerOption(
                  icon: Icons.video_library_rounded,
                  label: AppStrings.openWithSystem,
                  subtitle: AppStrings.openWithSystemSub,
                  onTap: () => _openWithIntent(context, path, null),
                ),
                _PlayerOption(
                  icon: Icons.play_arrow_rounded,
                  label: AppStrings.openWithVlc,
                  subtitle: AppStrings.playerPackageVlc,
                  onTap: () => _openWithIntent(
                    context,
                    path,
                    AppStrings.playerPackageVlc,
                  ),
                ),
                _PlayerOption(
                  icon: Icons.movie_rounded,
                  label: AppStrings.openWithMx,
                  subtitle: AppStrings.playerPackageMx,
                  onTap: () => _openWithIntent(
                    context,
                    path,
                    AppStrings.playerPackageMx,
                  ),
                ),
                _PlayerOption(
                  icon: Icons.smart_display_rounded,
                  label: AppStrings.openWithMpv,
                  subtitle: AppStrings.playerPackageMpv,
                  onTap: () => _openWithIntent(
                    context,
                    path,
                    AppStrings.playerPackageMpv,
                  ),
                ),
                SizedBox(
                  height:
                      MediaQuery.of(context).padding.bottom +
                      AppDimensions.spaceLg,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerOption extends StatelessWidget {
  const _PlayerOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: c.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c.primary, size: 22),
      ),
      title: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      onTap: onTap,
    );
  }
}

/// Section title with optional count chip.
class DownloadSectionHeader extends StatelessWidget {
  /// Creates a header for [title] with [count] items.
  const DownloadSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

  /// Heading text.
  final String title;

  /// Number badge; hidden when zero.
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimensions.spaceMd,
        bottom: AppDimensions.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: c.textSecondary,
            ),
          ),
          if (count > 0) ...<Widget>[
            const SizedBox(width: AppDimensions.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.spaceSm,
                vertical: AppDimensions.spaceXxs,
              ),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(
                '$count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty state when the download queue has no rows.
class EmptyDownloadsView extends StatelessWidget {
  /// Creates the empty placeholder.
  const EmptyDownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.download_done_rounded, size: 64, color: c.border),
            const SizedBox(height: AppDimensions.spaceLg),
            Text(
              AppStrings.noDownloadsYet,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyLarge?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(
              AppStrings.noDownloadsSubtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
