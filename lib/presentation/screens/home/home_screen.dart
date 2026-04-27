/// The main screen of the app. Users paste a URL, search for formats,
/// select quality, and initiate download from here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/permission_handler_util.dart';
import '../../../core/utils/share_intent_handler.dart';
import '../../../data/models/playlist_info.dart';
import '../../../data/models/video_format.dart';
import '../../../data/models/video_info.dart';
import '../../../data/providers/connectivity_provider.dart';
import '../../../data/providers/home_feedback_providers.dart';
import '../../../data/providers/permission_provider.dart';
import '../../../data/providers/settings_providers.dart';
import '../../../data/providers/ytdlp_providers.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/download/format_selector.dart';
import '../../widgets/download/video_info_card.dart';
import 'home_screen_controller.dart';

/// Primary surface for entering a media URL and starting downloads.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the home tab content.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(urlInputProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissionsOnStartup();
      await ref.read(storagePermissionCheckerProvider.future);
      ShareIntentHandler.initialize(ref);
    });
  }

  @override
  void dispose() {
    ShareIntentHandler.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    ref.listen<String>(urlInputProvider, (String? previous, String next) {
      if (previous == next) {
        return;
      }
      ref.read(selectedFormatProvider.notifier).state = null;
      if (_urlController.text != next) {
        _urlController.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });

    ref.listen<String?>(homeSearchErrorProvider, (
      String? previous,
      String? next,
    ) {
      if (next == null || next.isEmpty) {
        return;
      }
      if (context.mounted) {
        AppSnackbar.showError(context, next);
      }
      ref.read(homeSearchErrorProvider.notifier).state = null;
    });

    ref.listen<int>(shareIntentCounterProvider, (int? previous, int next) {
      if (next <= 0) {
        return;
      }
      if ((previous ?? 0) < next && context.mounted) {
        AppSnackbar.showInfo(context, AppStrings.shareIntentReceived);
      }
    });

    final String draftUrl = ref.watch(urlInputProvider);
    final String metadataUrl = ref.watch(metadataRequestUrlProvider);
    final AsyncValue<List<VideoFormat>> formatsAsync = ref.watch(
      formatsProvider,
    );
    final AsyncValue<VideoInfo?> videoAsync = ref.watch(videoInfoProvider);
    final AsyncValue<bool> playlistAsync = ref.watch(isPlaylistProvider);
    final AsyncValue<PlaylistInfo?> playlistInfoAsync = ref.watch(
      playlistInfoProvider,
    );
    final VideoFormat? selectedFormat = ref.watch(selectedFormatProvider);
    final HomeScreenState homeState = ref.watch(homeScreenControllerProvider);
    final HomeScreenController homeCtrl = ref.read(
      homeScreenControllerProvider.notifier,
    );
    final String outputPath = ref.watch(outputPathProvider);
    final AsyncValue<bool> connectivityAsync = ref.watch(connectivityProvider);
    final bool hasStoragePermission = ref.watch(storagePermissionProvider);
    final bool isOffline = connectivityAsync.maybeWhen(
      data: (bool connected) => !connected,
      orElse: () => false,
    );

    final bool urlEmpty = draftUrl.trim().isEmpty;
    final bool showLoadingSkeleton =
        formatsAsync.isLoading &&
        metadataUrl.isNotEmpty &&
        !formatsAsync.hasError;

    final VideoInfo? videoInfo = switch (videoAsync) {
      AsyncData<VideoInfo?>(:final value) => value,
      _ => null,
    };
    final bool showVideoCard = videoInfo != null;

    final List<VideoFormat>? formatsList = switch (formatsAsync) {
      AsyncData<List<VideoFormat>>(:final value) => value,
      _ => null,
    };
    final bool showFormatSelector =
        formatsList != null && formatsList.isNotEmpty;
    final bool showNoFormats =
        formatsList != null &&
        formatsList.isEmpty &&
        metadataUrl.isNotEmpty &&
        !playlistAsync.maybeWhen(data: (bool v) => v, orElse: () => false) &&
        !formatsAsync.isLoading &&
        !formatsAsync.hasError;

    final bool showDownload = selectedFormat != null && videoInfo != null;
    final bool isPlaylist = playlistAsync.maybeWhen(
      data: (bool v) => v,
      orElse: () => false,
    );
    final bool hasPlaylistEntries = playlistInfoAsync.maybeWhen(
      data: (PlaylistInfo? pi) => pi != null && pi.entries.isNotEmpty,
      orElse: () => false,
    );

    final List<String> errorMessages = <String>[];
    if (formatsAsync.hasError) {
      errorMessages.add(homeCtrl.userFacingErrorMessage(formatsAsync.error!));
    }
    if (videoAsync.hasError) {
      errorMessages.add(homeCtrl.userFacingErrorMessage(videoAsync.error!));
    }

    final bool showPlaylistChip =
        homeState.hasSearched &&
        playlistAsync.maybeWhen(data: (bool v) => v, orElse: () => false);

    final bool showHomeEmpty =
        !homeState.hasSearched && draftUrl.trim().isEmpty;

    return Scaffold(
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: Icon(
          Icons.play_circle_fill_rounded,
          color: c.primary,
          size: AppDimensions.iconLg,
        ),
        title: Text(
          AppStrings.appName,
          style: textTheme.headlineMedium?.copyWith(color: c.textPrimary),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: AppStrings.settingsScreenTitle,
            icon: Icon(Icons.settings_outlined, color: c.textPrimary),
            onPressed: () => homeCtrl.openSettings(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: c.border),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isOffline
                ? const _OfflineBanner(key: ValueKey<String>('offline'))
                : const SizedBox.shrink(key: ValueKey<String>('online')),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  left: AppDimensions.paddingMd,
                  right: AppDimensions.paddingMd,
                  top: AppDimensions.paddingMd,
                  bottom:
                      MediaQuery.of(context).padding.bottom +
                      MediaQuery.of(context).viewInsets.bottom +
                      AppDimensions.spacingXl * 2,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (!hasStoragePermission)
                      _PermissionWarningBanner(
                        onGrant: () async {
                          final bool granted = await PermissionHandlerUtil
                              .requestStoragePermission();
                          if (granted) {
                            ref.read(storagePermissionProvider.notifier).state =
                                true;
                            return;
                          }
                          if (context.mounted) {
                            await PermissionHandlerUtil.showPermissionDeniedDialog(
                              context,
                            );
                          }
                        },
                      ),
                    AppTextField(
                      controller: _urlController,
                      hintText: AppStrings.urlHint,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.search,
                      onChanged: (String v) {
                        ref.read(urlInputProvider.notifier).state = v;
                      },
                      onSubmitted: (String v) {
                        ref
                            .read(homeScreenControllerProvider.notifier)
                            .searchSubmitted(v);
                      },
                      prefixIcon: Icon(
                        Icons.link_rounded,
                        color: c.textSecondary,
                      ),
                      suffixIcon: draftUrl.isEmpty
                          ? null
                          : IconButton(
                              tooltip: AppStrings.buttonClear,
                              icon: Icon(
                                Icons.clear_rounded,
                                color: c.textSecondary,
                              ),
                              onPressed: () {
                                _urlController.clear();
                                ref.read(urlInputProvider.notifier).state = '';
                              },
                            ),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: Icon(
                          Icons.content_paste_rounded,
                          size: AppDimensions.iconSm,
                          color: c.primary,
                        ),
                        label: Text(
                          AppStrings.pasteFromClipboard,
                          style: textTheme.labelMedium?.copyWith(
                            color: c.primary,
                          ),
                        ),
                        side: BorderSide(
                          color: c.primary.withValues(alpha: 0.45),
                        ),
                        backgroundColor: c.surface,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            homeCtrl.pasteFromClipboard(_urlController),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingLg),
                    AppButton(
                      label: AppStrings.searchButton,
                      icon: const Icon(Icons.search_rounded),
                      isLoading:
                          formatsAsync.isLoading && metadataUrl.isNotEmpty,
                      onPressed: urlEmpty || isOffline
                          ? null
                          : () => homeCtrl.searchSubmitted(draftUrl),
                    ),
                    if (showHomeEmpty) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      const _HomeEmptyState(),
                    ],
                    if (showPlaylistChip) ...<Widget>[
                      const SizedBox(height: AppDimensions.spaceMd),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          avatar: Icon(
                            Icons.playlist_play_rounded,
                            size: AppDimensions.iconSm,
                            color: c.primary,
                          ),
                          label: Text(
                            AppStrings.playlistBanner,
                            style: textTheme.labelMedium?.copyWith(
                              color: c.primary,
                            ),
                          ),
                          side: BorderSide(
                            color: c.primary.withValues(alpha: 0.4),
                          ),
                          backgroundColor: c.surface,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                    if (showLoadingSkeleton) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      const _LoadingSkeleton(),
                    ],
                    if (showVideoCard) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      _RevealPanel(
                        animateKey: metadataUrl,
                        child: VideoInfoCard(videoInfo: videoInfo),
                      ),
                    ],
                    if (isPlaylist) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      Material(
                        color: c.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusMd,
                        ),
                        child: InkWell(
                          onTap: hasPlaylistEntries
                              ? () => homeCtrl.startPlaylistDownloadsFromHome(
                                    ref: ref,
                                    context: context,
                                  )
                              : null,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMd,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimensions.paddingMd,
                              vertical: AppDimensions.spaceSm,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  Icons.playlist_play_rounded,
                                  color: c.primary,
                                  size: AppDimensions.iconMd,
                                ),
                                const SizedBox(width: AppDimensions.spaceSm),
                                Expanded(
                                  child: Text(
                                    playlistInfoAsync.maybeWhen(
                                      data: (PlaylistInfo? pi) => pi != null
                                          ? AppStrings.playlistVideosLine(
                                              pi.count,
                                            )
                                          : AppStrings.playlistBanner,
                                      loading: () => AppStrings.loading,
                                      orElse: () => AppStrings.playlistBanner,
                                    ),
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: c.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (!hasPlaylistEntries)
                                  SizedBox(
                                    width: AppDimensions.iconSm,
                                    height: AppDimensions.iconSm,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.primary,
                                    ),
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: c.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      AppButton(
                        label: AppStrings.downloadButton,
                        icon: const Icon(Icons.download_rounded),
                        isLoading: !hasPlaylistEntries,
                        onPressed: hasPlaylistEntries
                            ? () => homeCtrl.startPlaylistDownloadsFromHome(
                                  ref: ref,
                                  context: context,
                                )
                            : null,
                      ),
                    ],
                    if (showFormatSelector) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      _RevealPanel(
                        animateKey: metadataUrl,
                        child: FormatSelector(formats: formatsList),
                      ),
                    ],
                    if (showNoFormats) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      Text(
                        AppStrings.noFormatsFound,
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                    if (showDownload) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      AppButton(
                        label: AppStrings.downloadButton,
                        icon: const Icon(Icons.download_rounded),
                        onPressed: () => homeCtrl.startDownload(
                          ref: ref,
                          context: context,
                          url: metadataUrl.isNotEmpty
                              ? metadataUrl
                              : draftUrl.trim(),
                          format: selectedFormat,
                          videoInfo: videoInfo,
                          outputPath: outputPath,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spaceSm),
                      Text(
                        AppStrings.videoWillBeSavedTo,
                        style: textTheme.bodySmall?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      Text(
                        outputPath.isEmpty
                            ? AppStrings.notAvailable
                            : outputPath,
                        style: textTheme.bodySmall?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                    if (errorMessages.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppDimensions.spacingLg),
                      _HomeErrorPanel(
                        messages: errorMessages,
                        onRetry: () {
                          ref.invalidate(formatsProvider);
                          ref.invalidate(videoInfoProvider);
                          ref.invalidate(isPlaylistProvider);
                          ref.invalidate(playlistInfoProvider);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissionsOnStartup() async {
    final bool granted = await PermissionHandlerUtil.requestStoragePermission();
    if (!granted && mounted) {
      AppLogger.w('Storage permission not granted on startup');
    } else {
      ref.read(storagePermissionProvider.notifier).state = true;
      AppLogger.i('Storage permission granted');
    }
  }
}

/// Fade + slight vertical slide when a panel first appears.
class _RevealPanel extends StatelessWidget {
  const _RevealPanel({required this.animateKey, required this.child});

  final String animateKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(animateKey),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (BuildContext context, double t, Widget? _) {
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(0, 0.05 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.of(context).warning,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppDimensions.spacingSm,
          horizontal: AppDimensions.paddingMd,
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.wifi_off_rounded,
              color: Colors.white,
              size: AppDimensions.iconSm,
            ),
            const SizedBox(width: AppDimensions.spaceSm),
            Expanded(
              child: Text(
                AppStrings.offlineMessage,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionWarningBanner extends StatelessWidget {
  const _PermissionWarningBanner({required this.onGrant});

  final Future<void> Function() onGrant;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    const Color warn = Color(0xFFF57F17);
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
      padding: const EdgeInsets.all(AppDimensions.paddingMd),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: warn.withValues(alpha: 0.5)),
        color: warn.withValues(alpha: 0.1),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            color: warn,
            size: AppDimensions.iconMd,
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  AppStrings.permissionDeniedTitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: warn,
                  ),
                ),
                Text(
                  'Grant permission to save downloaded videos',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onGrant, child: const Text('Grant')),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        Icon(
          Icons.smart_display_outlined,
          size: AppDimensions.iconXl + AppDimensions.iconLg,
          color: c.border,
        ),
        const SizedBox(height: AppDimensions.spacingMd),
        Text(
          AppStrings.homeEmptyTitle,
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        Text(
          AppStrings.homeEmptySubtitle,
          textAlign: TextAlign.center,
          maxLines: 3,
          style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: AppDimensions.spacingLg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppDimensions.spaceSm,
          runSpacing: AppDimensions.spaceSm,
          children: <Widget>[
            Chip(
              label: Text(
                AppStrings.homeUrlHintWatch,
                style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
              ),
              side: BorderSide(color: c.border),
              backgroundColor: c.surface,
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(
                AppStrings.homeUrlHintShort,
                style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
              ),
              side: BorderSide(color: c.border),
              backgroundColor: c.surface,
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              label: Text(
                AppStrings.homeUrlHintPlaylist,
                style: textTheme.bodySmall?.copyWith(color: c.textSecondary),
              ),
              side: BorderSide(color: c.border),
              backgroundColor: c.surface,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeErrorPanel extends StatelessWidget {
  const _HomeErrorPanel({required this.messages, required this.onRetry});

  final List<String> messages;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: c.error.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(AppDimensions.paddingMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, color: c.error),
          const SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  AppStrings.errorTitle,
                  style: textTheme.titleSmall?.copyWith(
                    color: c.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceXs),
                ...messages.map(
                  (String m) => Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppDimensions.spaceXs,
                    ),
                    child: Text(
                      m,
                      style: textTheme.bodySmall?.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(AppStrings.retryButton)),
        ],
      ),
    );
  }
}

/// Pulsing grey placeholders while metadata futures resolve.
class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton();

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.4,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);

    return FadeTransition(
      opacity: _opacity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: c.border.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          Container(
            height: AppDimensions.buttonHeight,
            decoration: BoxDecoration(
              color: c.border.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
          ),
        ],
      ),
    );
  }
}
