library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/providers/binary_path_provider.dart';
import '../../../data/providers/download_providers.dart';
import '../../../data/providers/settings_providers.dart';
import '../../widgets/common/app_snackbar.dart';

/// Displays all user preferences grouped into sections.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUiColors c = AppColors.of(context);
    final AsyncValue<AppSettings> settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text(AppStrings.settingsTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () => _showResetDialog(context, ref),
            child: Text(
              AppStrings.resetDefaults,
              style: TextStyle(color: c.error),
            ),
          ),
        ],
      ),
      body: settingsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  AppStrings.errorGeneric,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                FilledButton(
                  onPressed: () => ref.invalidate(settingsProvider),
                  child: const Text(AppStrings.retryButton),
                ),
              ],
            ),
          ),
        ),
        data: (AppSettings settings) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMd,
          ),
          children: <Widget>[
            _downloadLocationSection(context, ref, settings),
            _videoQualitySection(context, ref, settings),
            _downloadOptionsSection(context, ref, settings),
            _advancedSection(context, ref, settings),
            _speedLimitSection(context, ref, settings),
            _appearanceSection(context, ref, settings),
            _aboutSection(context, ref),
            const SizedBox(height: AppDimensions.spaceLg),
          ],
        ),
      ),
    );
  }

  Widget _downloadLocationSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionDownloadLocation,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.folder_outlined,
          title: AppStrings.tileDownloadLocation,
          subtitle: settings.outputPath,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final String? picked = await FilePicker.platform.getDirectoryPath();
            if (picked == null) {
              return;
            }
            final bool ok = await ref
                .read(settingsProvider.notifier)
                .updateOutputPath(picked);
            if (!context.mounted) {
              return;
            }
            if (ok) {
              AppSnackbar.showSuccess(context, AppStrings.locationUpdated);
            } else {
              AppSnackbar.showError(context, AppStrings.errorGeneric);
            }
          },
        ),
        _SettingsTile(
          icon: Icons.create_new_folder_outlined,
          title: AppStrings.tilePlaylistSubfolder,
          subtitle: AppStrings.tilePlaylistSubfolderSub,
          trailing: Switch.adaptive(
            value: settings.createSubfolderForPlaylists,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) =>
                        s.copyWith(createSubfolderForPlaylists: value),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _videoQualitySection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionVideoQuality,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.high_quality_outlined,
          title: AppStrings.tileDefaultQuality,
          subtitle: settings.defaultQuality.label,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showPicker<DefaultQuality>(
            context,
            title: AppStrings.chooseQualityTitle,
            options: DefaultQuality.values,
            selectedValue: settings.defaultQuality,
            labelBuilder: (DefaultQuality value) => value.label,
            onSelected: (DefaultQuality value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(defaultQuality: value),
                  );
            },
          ),
        ),
        _SettingsTile(
          icon: Icons.video_file_outlined,
          title: AppStrings.tilePreferredFormat,
          subtitle: settings.preferredFormat.label,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showPicker<PreferredFormat>(
            context,
            title: AppStrings.chooseFormatTitle,
            options: PreferredFormat.values,
            selectedValue: settings.preferredFormat,
            labelBuilder: (PreferredFormat value) => value.label,
            onSelected: (PreferredFormat value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(preferredFormat: value),
                  );
            },
          ),
        ),
        _SettingsTile(
          icon: Icons.auto_awesome_outlined,
          title: AppStrings.tileAutoSelectBest,
          subtitle: AppStrings.tileAutoSelectBestSub,
          trailing: Switch.adaptive(
            value: settings.autoSelectBestFormat,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(autoSelectBestFormat: value),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _downloadOptionsSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionDownloadOptions,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.download_for_offline_outlined,
          title: AppStrings.tileMaxConcurrent,
          subtitle:
              '${settings.maxConcurrentDownloads} ${AppStrings.downloadsAtOnceSuffix}',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showPicker<int>(
            context,
            title: AppStrings.chooseConcurrentTitle,
            options: const <int>[1, 2, 3, 4, 5],
            selectedValue: settings.maxConcurrentDownloads,
            labelBuilder: (int value) => '$value',
            onSelected: (int value) async {
              await ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) =>
                        s.copyWith(maxConcurrentDownloads: value),
                  );
              ref
                  .read(downloadManagerProvider.notifier)
                  .setMaxConcurrentDownloads(value);
            },
          ),
        ),
        _SettingsTile(
          icon: Icons.skip_next_outlined,
          title: AppStrings.tileSkipExisting,
          subtitle: AppStrings.tileSkipExistingSub,
          trailing: Switch.adaptive(
            value: settings.skipExistingFiles,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(skipExistingFiles: value),
                  );
            },
          ),
        ),
        _SettingsTile(
          icon: Icons.subtitles_outlined,
          title: AppStrings.tileDownloadSubs,
          subtitle: AppStrings.tileDownloadSubsSub,
          trailing: Switch.adaptive(
            value: settings.downloadSubtitles,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(downloadSubtitles: value),
                  );
            },
          ),
        ),
        if (settings.downloadSubtitles)
          _SettingsTile(
            icon: Icons.language_outlined,
            title: AppStrings.tileSubLanguage,
            subtitle: settings.subtitleLanguage.toUpperCase(),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPicker<String>(
              context,
              title: AppStrings.chooseSubLanguageTitle,
              options: AppStrings.subtitleLanguageOptions,
              selectedValue: settings.subtitleLanguage,
              labelBuilder: (String value) => value.toUpperCase(),
              onSelected: (String value) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSetting(
                      (AppSettings s) => s.copyWith(subtitleLanguage: value),
                    );
              },
            ),
          ),
      ],
    );
  }

  Widget _advancedSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionAdvanced,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.image_outlined,
          title: AppStrings.tileEmbedThumbnail,
          subtitle: AppStrings.tileEmbedThumbnailSub,
          trailing: Switch.adaptive(
            value: settings.embedThumbnail,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(embedThumbnail: value),
                  );
            },
          ),
        ),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: AppStrings.tileAddMetadata,
          subtitle: AppStrings.tileAddMetadataSub,
          trailing: Switch.adaptive(
            value: settings.addMetadata,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(addMetadata: value),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _speedLimitSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionSpeedLimit,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.speed_outlined,
          title: AppStrings.tileLimitSpeed,
          subtitle: AppStrings.tileLimitSpeedSub,
          trailing: Switch.adaptive(
            value: settings.limitDownloadSpeed,
            onChanged: (bool value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(limitDownloadSpeed: value),
                  );
            },
          ),
        ),
        if (settings.limitDownloadSpeed)
          _SettingsTile(
            icon: Icons.arrow_downward_rounded,
            title: AppStrings.tileMaxSpeed,
            subtitle: _formatSpeed(settings.maxDownloadSpeedKbps),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _showPicker<int>(
              context,
              title: AppStrings.chooseSpeedTitle,
              options: const <int>[256, 512, 1024, 2048, 5120, 10240, 0],
              selectedValue: settings.maxDownloadSpeedKbps,
              labelBuilder: _formatSpeed,
              onSelected: (int value) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSetting(
                      (AppSettings s) =>
                          s.copyWith(maxDownloadSpeedKbps: value),
                    );
              },
            ),
          ),
      ],
    );
  }

  Widget _appearanceSection(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    return _SettingsSection(
      title: AppStrings.sectionAppearance,
      children: <Widget>[
        _SettingsTile(
          icon: Icons.palette_outlined,
          title: AppStrings.tileTheme,
          subtitle: settings.themeMode.label,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showPicker<AppThemeMode>(
            context,
            title: AppStrings.chooseThemeTitle,
            options: AppThemeMode.values,
            selectedValue: settings.themeMode,
            labelBuilder: (AppThemeMode value) => value.label,
            onSelected: (AppThemeMode value) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSetting(
                    (AppSettings s) => s.copyWith(themeMode: value),
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _aboutSection(BuildContext context, WidgetRef ref) {
    final AsyncValue<String> versionAsync = ref.watch(ytdlpVersionProvider);
    return _SettingsSection(
      title: AppStrings.sectionAbout,
      children: <Widget>[
        const _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: AppStrings.tileAppVersion,
          subtitle: AppStrings.appVersion,
        ),
        _SettingsTile(
          icon: Icons.terminal_rounded,
          title: AppStrings.tileYtdlpVersion,
          subtitle: versionAsync.valueOrNull ?? AppStrings.loading,
        ),
        _SettingsTile(
          icon: Icons.bug_report_outlined,
          title: AppStrings.tileReportBug,
          subtitle: AppStrings.tileReportBugSub,
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () async {
            final Uri uri = Uri.parse(AppStrings.reportBugUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
        ),
        _SettingsTile(
          icon: Icons.delete_sweep_outlined,
          title: AppStrings.tileClearHistory,
          subtitle: AppStrings.tileClearHistorySub,
          titleColor: AppColors.of(context).error,
          iconColor: AppColors.of(context).error,
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _showClearHistoryDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showResetDialog(BuildContext context, WidgetRef ref) async {
    final AppUiColors c = AppColors.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.resetConfirmTitle),
          content: const Text(AppStrings.resetConfirmBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.buttonCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.resetConfirmButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await ref.read(settingsRepositoryProvider).resetToDefaults();
    if (!context.mounted) {
      return;
    }
    ref.invalidate(settingsProvider);
    AppSnackbar.showSuccess(context, AppStrings.settingsSaved);
  }

  Future<void> _showClearHistoryDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final AppUiColors c = AppColors.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.clearHistoryTitle),
          content: const Text(AppStrings.clearHistoryBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.buttonCancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.clearHistoryConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    ref.read(downloadManagerProvider.notifier).clearCompleted();
    AppSnackbar.showSuccess(context, AppStrings.historyCleared);
  }

  void _showPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> options,
    required T selectedValue,
    required String Function(T) labelBuilder,
    required void Function(T) onSelected,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _PickerSheet<T>(
          title: title,
          options: options,
          selectedValue: selectedValue,
          labelBuilder: labelBuilder,
          onSelected: onSelected,
        );
      },
    );
  }

  String _formatSpeed(int kbps) {
    if (kbps == 0) {
      return AppStrings.speedUnlimited;
    }
    if (kbps < 1024) {
      return '$kbps ${AppStrings.speedKbpsSuffix}';
    }
    return '${(kbps / 1024).toStringAsFixed(0)} ${AppStrings.speedMbpsSuffix}';
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionTitle(title: title),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            border: Border.all(color: c.border),
            color: c.surface,
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i != children.length - 1)
                  Divider(height: 1, thickness: 1, color: c.border),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;
  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return ListTile(
      enabled: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.paddingMd,
        vertical: AppDimensions.paddingSm,
      ),
      leading: Container(
        width: AppDimensions.spaceXl + AppDimensions.spaceSm,
        height: AppDimensions.spaceXl + AppDimensions.spaceSm,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          color: c.primary.withValues(alpha: 0.1),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: iconColor ?? c.primary,
          size: AppDimensions.iconMd,
        ),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: titleColor),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.textSecondary),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppDimensions.spacingLg,
        bottom: AppDimensions.spacingSm,
        left: AppDimensions.spacingSm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.of(context).primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final List<T> options;
  final T selectedValue;
  final String Function(T) labelBuilder;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.all(AppDimensions.paddingMd),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppDimensions.spaceSm),
            Container(
              width: AppDimensions.spaceXxl,
              height: AppDimensions.spaceXs,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Divider(height: AppDimensions.spaceLg, color: c.border),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final T option = options[index];
                  return ListTile(
                    title: Text(labelBuilder(option)),
                    trailing: option == selectedValue
                        ? Icon(Icons.check_rounded, color: c.primary)
                        : null,
                    onTap: () {
                      onSelected(option);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
