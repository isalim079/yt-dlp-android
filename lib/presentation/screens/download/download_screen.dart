/// Shows all downloads — active, queued, completed, and failed, with interactive filter tabs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/permission_handler_util.dart';
import '../../../data/models/app_download_record.dart';
import '../../../data/models/download_item.dart';
import '../../../data/providers/app_navigation_providers.dart';
import '../../../data/providers/download_providers.dart';
import '../../../data/services/app_download_registry.dart';
import '../../../data/services/download_manager.dart';
import '../../../data/services/ytdlp_platform_channel.dart';
import '../../widgets/download/download_card.dart';
import '../settings/settings_screen.dart';
import 'downloaded_files_screen.dart';

/// Lists active and completed downloads with aggregate status and interactive filter tabs.
class DownloadScreen extends ConsumerStatefulWidget {
  /// Creates the downloads tab content.
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  StreamSubscription<DownloadItem>? _completionSub;
  bool _completionHooked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_completionHooked) {
      return;
    }
    _completionHooked = true;
    _completionSub = ref
        .read(downloadManagerProvider.notifier)
        .completionStream
        .listen((DownloadItem item) {
          if (!mounted) {
            return;
          }
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.transparent,
              elevation: 0,
              content: Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMd),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: AppDimensions.spaceSm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            AppStrings.downloadCompleteTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            item.title.length > 35
                                ? '${item.title.substring(0, 35)}...'
                                : item.title,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(downloadFilterTabProvider.notifier).state =
                            DownloadFilterTab.downloaded;
                      },
                      child: const Text(
                        AppStrings.playFile,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
  }

  @override
  void dispose() {
    _completionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final List<DownloadItem> queue = ref.watch(downloadQueueProvider);
    final DownloadManager manager = ref.watch(downloadManagerProvider.notifier);
    final List<DownloadItem> paused = ref.watch(pausedDownloadsProvider);
    final List<DownloadItem> completed = ref.watch(completedDownloadsProvider);
    final List<DownloadItem> failed = ref.watch(failedDownloadsProvider);
    final List<AppDownloadRecord> appDownloads = ref.watch(
      appDownloadRegistryProvider,
    );
    final DownloadFilterTab selectedTab = ref.watch(downloadFilterTabProvider);

    final List<DownloadItem> activeOrQueued = queue
        .where(
          (DownloadItem e) =>
              e.status == DownloadStatus.downloading ||
              e.status == DownloadStatus.queued,
        )
        .toList(growable: false);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        title: Text(
          AppStrings.downloadsTitle,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: c.textPrimary),
        ),
        actions: <Widget>[
          if (activeOrQueued.isNotEmpty ||
              paused.isNotEmpty ||
              completed.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: c.textPrimary),
              tooltip: 'Queue actions',
              onSelected: (String value) {
                switch (value) {
                  case 'pause_all':
                    HapticFeedback.mediumImpact();
                    manager.pauseAll();
                    break;
                  case 'resume_all':
                    HapticFeedback.mediumImpact();
                    manager.resumeAll();
                    break;
                  case 'clear_completed':
                    HapticFeedback.lightImpact();
                    manager.clearCompleted();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                if (activeOrQueued.isNotEmpty)
                  const PopupMenuItem<String>(
                    value: 'pause_all',
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.pause_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text(AppStrings.pauseAll),
                      ],
                    ),
                  ),
                if (paused.isNotEmpty)
                  const PopupMenuItem<String>(
                    value: 'resume_all',
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.play_circle_outline, size: 20),
                        SizedBox(width: 8),
                        Text(AppStrings.resumeAll),
                      ],
                    ),
                  ),
                if (completed.isNotEmpty)
                  const PopupMenuItem<String>(
                    value: 'clear_completed',
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.cleaning_services_outlined, size: 20),
                        SizedBox(width: 8),
                        Text(AppStrings.clearAllCompleted),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: AppStrings.sectionDownloaded,
            icon: Icon(Icons.folder_open_rounded, color: c.textPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const DownloadedFilesScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: AppStrings.settingsScreenTitle,
            icon: Icon(Icons.settings_outlined, color: c.textPrimary),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: <Widget>[
              // Interactive Filter Tabs Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMd,
                  vertical: AppDimensions.spaceSm,
                ),
                color: c.surface,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: <Widget>[
                      _FilterTabPill(
                        label: AppStrings.filterAll,
                        count: queue.length,
                        color: c.primary,
                        icon: Icons.list_alt_rounded,
                        isSelected: selectedTab == DownloadFilterTab.all,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(downloadFilterTabProvider.notifier).state =
                              DownloadFilterTab.all;
                        },
                      ),
                      _FilterTabPill(
                        label: AppStrings.sectionActive,
                        count: activeOrQueued.length,
                        color: c.primary,
                        icon: Icons.downloading_rounded,
                        isSelected: selectedTab == DownloadFilterTab.active,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(downloadFilterTabProvider.notifier).state =
                              DownloadFilterTab.active;
                        },
                      ),
                      if (paused.isNotEmpty || selectedTab == DownloadFilterTab.paused)
                        _FilterTabPill(
                          label: AppStrings.sectionPaused,
                          count: paused.length,
                          color: c.warning,
                          icon: Icons.pause_circle_outline_rounded,
                          isSelected: selectedTab == DownloadFilterTab.paused,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            ref.read(downloadFilterTabProvider.notifier).state =
                                DownloadFilterTab.paused;
                          },
                        ),
                      _FilterTabPill(
                        label: AppStrings.sectionDone,
                        count: completed.length,
                        color: c.success,
                        icon: Icons.check_circle_outline_rounded,
                        isSelected: selectedTab == DownloadFilterTab.done,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(downloadFilterTabProvider.notifier).state =
                              DownloadFilterTab.done;
                        },
                      ),
                      _FilterTabPill(
                        label: AppStrings.sectionFailed,
                        count: failed.length,
                        color: c.error,
                        icon: Icons.error_outline_rounded,
                        isSelected: selectedTab == DownloadFilterTab.failed,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(downloadFilterTabProvider.notifier).state =
                              DownloadFilterTab.failed;
                        },
                      ),
                      _FilterTabPill(
                        label: AppStrings.sectionDownloaded,
                        count: appDownloads.length,
                        color: const Color(0xFF673AB7),
                        icon: Icons.folder_special_rounded,
                        isSelected: selectedTab == DownloadFilterTab.downloaded,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(downloadFilterTabProvider.notifier).state =
                              DownloadFilterTab.downloaded;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Filtered Content
              Expanded(
                child: _buildFilteredBody(
                  context: context,
                  selectedTab: selectedTab,
                  queue: queue,
                  activeOrQueued: activeOrQueued,
                  paused: paused,
                  completed: completed,
                  failed: failed,
                  appDownloads: appDownloads,
                  manager: manager,
                  c: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredBody({
    required BuildContext context,
    required DownloadFilterTab selectedTab,
    required List<DownloadItem> queue,
    required List<DownloadItem> activeOrQueued,
    required List<DownloadItem> paused,
    required List<DownloadItem> completed,
    required List<DownloadItem> failed,
    required List<AppDownloadRecord> appDownloads,
    required DownloadManager manager,
    required AppUiColors c,
  }) {
    switch (selectedTab) {
      case DownloadFilterTab.downloaded:
        if (appDownloads.isEmpty) {
          return _EmptyTabState(
            icon: Icons.folder_special_rounded,
            title: AppStrings.noDownloadedFiles,
            subtitle: 'Files downloaded through this app will appear here for immediate access.',
            buttonLabel: AppStrings.navGoHome,
            onAction: () => ref.read(tabIndexProvider.notifier).state = 0,
          );
        }
        return _AppDownloadedListView(records: appDownloads);

      case DownloadFilterTab.active:
        if (activeOrQueued.isEmpty) {
          return _EmptyTabState(
            icon: Icons.downloading_rounded,
            title: 'No active downloads',
            subtitle: 'Paste a video URL on the Home tab to start downloading.',
            buttonLabel: AppStrings.navGoHome,
            onAction: () => ref.read(tabIndexProvider.notifier).state = 0,
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingScreenHorizontal,
            vertical: AppDimensions.paddingScreenVertical,
          ),
          children: <Widget>[
            _SectionHeader(
              title: AppStrings.sectionDownloading,
              count: activeOrQueued.length,
              color: c.primary,
            ),
            ...activeOrQueued.map(
              (DownloadItem e) => _AnimatedDownloadRow(
                key: ValueKey<String>(e.id),
                child: RepaintBoundary(
                  child: DownloadCard(itemId: e.id, manager: manager),
                ),
              ),
            ),
          ],
        );

      case DownloadFilterTab.paused:
        if (paused.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.pause_circle_outline_rounded,
            title: 'No paused downloads',
            subtitle: 'Downloads you pause will be kept ready to resume here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingScreenHorizontal,
            vertical: AppDimensions.paddingScreenVertical,
          ),
          children: <Widget>[
            _SectionHeader(
              title: AppStrings.sectionPaused,
              count: paused.length,
              color: c.warning,
            ),
            ...paused.map(
              (DownloadItem e) => _AnimatedDownloadRow(
                key: ValueKey<String>(e.id),
                child: RepaintBoundary(
                  child: DownloadCard(itemId: e.id, manager: manager),
                ),
              ),
            ),
          ],
        );

      case DownloadFilterTab.done:
        if (completed.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.check_circle_outline_rounded,
            title: 'No completed downloads in queue',
            subtitle: 'Items that finish downloading in this session will appear here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingScreenHorizontal,
            vertical: AppDimensions.paddingScreenVertical,
          ),
          children: <Widget>[
            _SectionHeader(
              title: AppStrings.sectionCompleted,
              count: completed.length,
              color: c.success,
            ),
            ...completed.map(
              (DownloadItem e) => _AnimatedDownloadRow(
                key: ValueKey<String>(e.id),
                child: RepaintBoundary(
                  child: DownloadCard(itemId: e.id, manager: manager),
                ),
              ),
            ),
          ],
        );

      case DownloadFilterTab.failed:
        if (failed.isEmpty) {
          return const _EmptyTabState(
            icon: Icons.sentiment_satisfied_alt_rounded,
            title: 'No failed downloads',
            subtitle: 'All queued items are working normally without any failures.',
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingScreenHorizontal,
            vertical: AppDimensions.paddingScreenVertical,
          ),
          children: <Widget>[
            _SectionHeader(
              title: AppStrings.sectionFailed,
              count: failed.length,
              color: c.error,
            ),
            ...failed.map(
              (DownloadItem e) => _AnimatedDownloadRow(
                key: ValueKey<String>(e.id),
                child: RepaintBoundary(
                  child: DownloadCard(itemId: e.id, manager: manager),
                ),
              ),
            ),
          ],
        );

      case DownloadFilterTab.all:
        if (queue.isEmpty) {
          return _EmptyDownloadsView(
            onGoHome: () => ref.read(tabIndexProvider.notifier).state = 0,
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingScreenHorizontal,
            vertical: AppDimensions.paddingScreenVertical,
          ),
          children: <Widget>[
            if (activeOrQueued.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: AppStrings.sectionDownloading,
                count: activeOrQueued.length,
                color: c.primary,
              ),
              ...activeOrQueued.map(
                (DownloadItem e) => _AnimatedDownloadRow(
                  key: ValueKey<String>(e.id),
                  child: RepaintBoundary(
                    child: DownloadCard(itemId: e.id, manager: manager),
                  ),
                ),
              ),
            ],
            if (paused.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: AppStrings.sectionPaused,
                count: paused.length,
                color: c.warning,
              ),
              ...paused.map(
                (DownloadItem e) => _AnimatedDownloadRow(
                  key: ValueKey<String>(e.id),
                  child: RepaintBoundary(
                    child: DownloadCard(itemId: e.id, manager: manager),
                  ),
                ),
              ),
            ],
            if (completed.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: AppStrings.sectionCompleted,
                count: completed.length,
                color: c.success,
              ),
              ...completed.map(
                (DownloadItem e) => _AnimatedDownloadRow(
                  key: ValueKey<String>(e.id),
                  child: RepaintBoundary(
                    child: DownloadCard(itemId: e.id, manager: manager),
                  ),
                ),
              ),
            ],
            if (failed.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: AppStrings.sectionFailed,
                count: failed.length,
                color: c.error,
              ),
              ...failed.map(
                (DownloadItem e) => _AnimatedDownloadRow(
                  key: ValueKey<String>(e.id),
                  child: RepaintBoundary(
                    child: DownloadCard(itemId: e.id, manager: manager),
                  ),
                ),
              ),
            ],
          ],
        );
    }
  }
}

/// Filter tab pill button with real-time counter badge and active indicator.
class _FilterTabPill extends StatelessWidget {
  const _FilterTabPill({
    required this.label,
    required this.count,
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
      child: Material(
        color: isSelected
            ? color.withValues(alpha: 0.15)
            : c.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? color : c.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? color : c.textSecondary,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? color : c.textPrimary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color
                        : c.border.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: isSelected ? Colors.white : c.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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

/// Direct reactive view of files downloaded by this app.
class _AppDownloadedListView extends ConsumerWidget {
  const _AppDownloadedListView({required this.records});

  final List<AppDownloadRecord> records;

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(DateTime dt) {
    final String month = _months[dt.month - 1];
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '$month ${dt.day}, $hour:$minute';
  }

  Future<void> _playFile(BuildContext context, String path) async {
    HapticFeedback.lightImpact();
    try {
      await YtdlpPlatformChannel.openFile(path);
    } on Object catch (error, stackTrace) {
      AppLogger.e('Failed to open local file: $path', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.openFailed)),
        );
      }
    }
  }

  Future<void> _shareFile(BuildContext context, String path) async {
    HapticFeedback.lightImpact();
    try {
      await YtdlpPlatformChannel.shareFile(path);
    } on Object catch (error, stackTrace) {
      AppLogger.e('Failed to share local file: $path', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share file')),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    WidgetRef ref,
    AppDownloadRecord record,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text(AppStrings.deleteFileTitle),
        content: Text('Delete "${record.title}" from device?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(AppStrings.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(AppStrings.deleteFileConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final bool allowed =
        await PermissionHandlerUtil.ensureStoragePermission(context);
    if (!allowed) {
      return;
    }

    final bool deleted = await ref
        .read(downloadManagerProvider.notifier)
        .deleteDownloadedFile(record.id);

    if (!deleted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.deleteFileFailed)),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.deleteFileSuccess)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUiColors c = AppColors.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingScreenHorizontal,
        vertical: AppDimensions.paddingScreenVertical,
      ),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext ctx, int index) {
        final AppDownloadRecord record = records[index];

        return Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            side: BorderSide(color: c.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingMd,
              vertical: 6,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: record.isAudio
                    ? c.primary.withValues(alpha: 0.12)
                    : c.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                record.isAudio
                    ? Icons.audiotrack_rounded
                    : Icons.movie_rounded,
                color: record.isAudio ? c.primary : c.success,
                size: 24,
              ),
            ),
            title: Text(
              record.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${_formatBytes(record.fileSizeBytes)} • ${_formatDate(record.completedAt)} • ${record.formatLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: c.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: c.success.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.verified_rounded,
                              size: 11,
                              color: c.success,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'App Download',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: c.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: AppStrings.playFile,
                  onPressed: () => _playFile(ctx, record.filePath),
                  icon: Icon(
                    Icons.play_circle_fill_rounded,
                    color: c.primary,
                    size: 28,
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.shareFile,
                  onPressed: () => _shareFile(ctx, record.filePath),
                  icon: Icon(
                    Icons.share_outlined,
                    color: c.textSecondary,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.deleteFromDevice,
                  onPressed: () => _confirmAndDelete(ctx, ref, record),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: c.error,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Clean generic empty state for filter tabs.
class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: c.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: c.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: c.textSecondary,
              ),
            ),
            if (buttonLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: Text(buttonLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.primary,
                  side: BorderSide(color: c.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDownloadsView extends StatefulWidget {
  const _EmptyDownloadsView({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  State<_EmptyDownloadsView> createState() => _EmptyDownloadsViewState();
}

class _EmptyDownloadsViewState extends State<_EmptyDownloadsView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _controller,
              curve: Curves.elasticOut,
            ),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: c.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.download_outlined, size: 48, color: c.primary),
            ),
          ),
          const SizedBox(height: 24),
          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
            child: Column(
              children: <Widget>[
                Text(
                  AppStrings.noDownloadsYet,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Text(
                  AppStrings.noDownloadsSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FadeTransition(
            opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
            child: OutlinedButton.icon(
              onPressed: widget.onGoHome,
              icon: const Icon(Icons.home_rounded),
              label: const Text(AppStrings.navGoHome),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.primary,
                side: BorderSide(color: c.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide + fade entrance for each download row (runs once per widget instance).
class _AnimatedDownloadRow extends StatefulWidget {
  const _AnimatedDownloadRow({super.key, required this.child});

  final Widget child;

  @override
  State<_AnimatedDownloadRow> createState() => _AnimatedDownloadRowState();
}

class _AnimatedDownloadRowState extends State<_AnimatedDownloadRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0.08, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
