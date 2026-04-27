/// Shows all downloads — active, queued, completed, and failed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/providers/app_navigation_providers.dart';
import '../../../data/models/download_item.dart';
import '../../../data/providers/download_providers.dart';
import '../../../data/services/download_manager.dart';
import '../../widgets/download/download_card.dart';
import '../settings/settings_screen.dart';

/// Lists active and completed downloads with aggregate status.
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
                      onPressed: () =>
                          ref.read(tabIndexProvider.notifier).state = 1,
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
    final List<DownloadItem> active = ref.watch(activeDownloadsProvider);
    final List<DownloadItem> completed = ref.watch(completedDownloadsProvider);
    final List<DownloadItem> failed = ref.watch(failedDownloadsProvider);

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
          if (completed.isNotEmpty)
            TextButton(
              onPressed: manager.clearCompleted,
              child: Text(AppStrings.clearCompleted),
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
      body: queue.isEmpty
          ? _EmptyDownloadsView(
              onGoHome: () => ref.read(tabIndexProvider.notifier).state = 0,
            )
          : Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingMd,
                    vertical: AppDimensions.spaceSm,
                  ),
                  color: c.surface,
                  child: Row(
                    children: <Widget>[
                      _StatBadge(
                        count: active.length,
                        label: AppStrings.sectionActive,
                        color: c.primary,
                      ),
                      const SizedBox(width: AppDimensions.spaceSm),
                      _StatBadge(
                        count: completed.length,
                        label: AppStrings.sectionDone,
                        color: c.success,
                      ),
                      const SizedBox(width: AppDimensions.spaceSm),
                      _StatBadge(
                        count: failed.length,
                        label: AppStrings.sectionFailed,
                        color: c.error,
                      ),
                      const Spacer(),
                      if (completed.isNotEmpty)
                        TextButton.icon(
                          onPressed: manager.clearCompleted,
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            size: 16,
                          ),
                          label: const Text(AppStrings.clearDone),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
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
                            child: DownloadCard(item: e, manager: manager),
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
                            child: DownloadCard(item: e, manager: manager),
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
                            child: DownloadCard(item: e, manager: manager),
                          ),
                        ),
                      ],
                    ],
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

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: <Widget>[
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
          ),
        ],
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
