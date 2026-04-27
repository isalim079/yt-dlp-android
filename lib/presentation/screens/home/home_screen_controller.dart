/// Handles business actions for the home metadata and download UI.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/exceptions/ytdlp_exception.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/connectivity_util.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/permission_handler_util.dart';
import '../../../data/models/playlist_info.dart';
import '../../../data/models/video_format.dart';
import '../../../data/models/video_info.dart';
import '../../../data/providers/app_navigation_providers.dart';
import '../../../data/providers/download_providers.dart';
import '../../../data/providers/home_feedback_providers.dart';
import '../../../data/providers/settings_providers.dart';
import '../../../data/providers/ytdlp_providers.dart';
import '../../widgets/common/app_snackbar.dart';
import '../settings/settings_screen.dart';

/// Immutable UI state for [HomeScreenController].
@immutable
class HomeScreenState {
  /// Creates home screen controller state.
  const HomeScreenState({
    this.isSearching = false,
    this.hasSearched = false,
    this.outputPath = '',
  });

  /// Whether a search round-trip is in flight.
  final bool isSearching;

  /// Whether the user has pressed Search at least once.
  final bool hasSearched;

  /// Resolved default folder label for the download footer.
  final String outputPath;

  /// Returns a copy with selective overrides.
  HomeScreenState copyWith({
    bool? isSearching,
    bool? hasSearched,
    String? outputPath,
  }) {
    return HomeScreenState(
      isSearching: isSearching ?? this.isSearching,
      hasSearched: hasSearched ?? this.hasSearched,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}

/// Coordinates search, clipboard, and persisted download path.
class HomeScreenController extends AutoDisposeNotifier<HomeScreenState> {
  @override
  HomeScreenState build() {
    return const HomeScreenState();
  }

  /// Normalizes [url] and runs metadata fetch when non-empty.
  Future<void> searchSubmitted(String url) async {
    final String trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }
    try {
      await search(trimmed);
    } on YtdlpException catch (e) {
      ref.read(homeSearchErrorProvider.notifier).state = e.message;
    }
  }

  /// Maps [error] to user-visible copy for the home error panel.
  String userFacingErrorMessage(Object error) {
    if (error is YtdlpException) {
      return error.message;
    }
    return AppStrings.errorUnknown;
  }

  /// Runs a metadata search for [url] and refreshes Riverpod futures.
  Future<void> search(String url) async {
    final String trimmed = url.trim();
    if (!await ConnectivityUtil.hasConnection()) {
      throw const YtdlpException(AppStrings.errorNoInternet);
    }
    state = state.copyWith(isSearching: true, hasSearched: true);
    ref.read(urlInputProvider.notifier).state = trimmed;
    ref.read(metadataRequestUrlProvider.notifier).state = trimmed;
    ref.invalidate(formatsProvider);
    ref.invalidate(videoInfoProvider);
    ref.invalidate(isPlaylistProvider);
    ref.invalidate(playlistInfoProvider);
    try {
      await ref.read(formatsProvider.future);
    } on Object catch (error, stackTrace) {
      AppLogger.e('Format fetch after search failed', error, stackTrace);
    } finally {
      state = state.copyWith(isSearching: false);
    }
  }

  /// Loads output path from settings provider.
  Future<void> loadOutputPath() async {
    final String outputPath = ref.read(outputPathProvider);
    state = state.copyWith(outputPath: outputPath);
  }

  /// Clears draft URL, metadata URL, and selected format.
  void clearSearch() {
    ref.read(urlInputProvider.notifier).state = '';
    ref.read(metadataRequestUrlProvider.notifier).state = '';
    ref.read(selectedFormatProvider.notifier).state = null;
    state = state.copyWith(hasSearched: false);
  }

  /// Pastes clipboard text into [controller] and updates [urlInputProvider].
  Future<void> pasteFromClipboard(TextEditingController controller) async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      final String? text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        AppLogger.d('pasteFromClipboard: empty clipboard');
        return;
      }
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      ref.read(urlInputProvider.notifier).state = text;
    } on Object catch (error, stackTrace) {
      AppLogger.w('pasteFromClipboard failed: $error\n$stackTrace');
    }
  }

  /// Pushes the settings screen onto the root navigator.
  void openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const SettingsScreen(),
      ),
    );
  }

  /// Queues a download and switches to the Downloads tab.
  Future<void> startDownload({
    required WidgetRef ref,
    required BuildContext context,
    required String url,
    required VideoFormat format,
    required VideoInfo videoInfo,
    required String outputPath,
  }) async {
    final String resolvedOutputPath = await _resolveAndValidateOutputPath(ref);
    if (!context.mounted) {
      return;
    }
    final bool allowed =
        await PermissionHandlerUtil.ensureStoragePermission(context);
    if (!allowed) {
      return;
    }
    await ref
        .read(downloadManagerProvider.notifier)
        .addDownload(
          url: url,
          format: format,
          outputPath: resolvedOutputPath,
          title: videoInfo.title,
          thumbnailUrl: videoInfo.thumbnail,
        );
    ref.read(tabIndexProvider.notifier).state = 1;
    if (context.mounted) {
      AppSnackbar.showSuccess(context, AppStrings.downloadStarted);
    }
    AppLogger.i('Download added: ${videoInfo.title}');
  }

  /// Enqueues every resolved playlist entry with the selected format.
  Future<void> startPlaylistDownloadsFromHome({
    required WidgetRef ref,
    required BuildContext context,
  }) async {
    final VideoFormat? format = ref.read(selectedFormatProvider);
    if (format == null) {
      if (context.mounted) {
        AppSnackbar.showError(context, AppStrings.selectFormat);
      }
      return;
    }
    final String outputPath = await _resolveAndValidateOutputPath(ref);
    final PlaylistInfo? info = ref.read(playlistInfoProvider).valueOrNull;
    if (info == null || info.entries.isEmpty) {
      if (context.mounted) {
        AppSnackbar.showError(context, AppStrings.errorGeneric);
      }
      return;
    }
    final String playlistUrl = ref.read(metadataRequestUrlProvider);
    if (!context.mounted) {
      return;
    }
    final bool allowed =
        await PermissionHandlerUtil.ensureStoragePermission(context);
    if (!allowed) {
      return;
    }
    await ref
        .read(downloadManagerProvider.notifier)
        .addPlaylistDownload(
          playlistUrl: playlistUrl,
          format: format,
          outputPath: outputPath,
          totalCount: info.count,
          entries: info.entries,
        );
    ref.read(tabIndexProvider.notifier).state = 1;
    if (context.mounted) {
      AppSnackbar.showSuccess(context, AppStrings.downloadStarted);
    }
    AppLogger.i('Playlist downloads queued: ${info.count} items');
  }

  Future<String> _resolveAndValidateOutputPath(WidgetRef ref) async {
    String path = ref.read(outputPathProvider);

    if (path.isEmpty) {
      path = '/storage/emulated/0/Download';
      AppLogger.w('Output path was empty, using default: $path');
    }

    final Directory dir = Directory(path);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
        AppLogger.i('Created output directory: $path');
      } catch (e, st) {
        final Directory appDir = await getApplicationDocumentsDirectory();
        path = '${appDir.path}/Downloads';
        await Directory(path).create(recursive: true);
        AppLogger.w('Fell back to app directory: $path\n$e\n$st');
      }
    }

    AppLogger.i('Download output path: $path');
    return path;
  }
}

/// Exposes [HomeScreenController] to the widget tree.
final AutoDisposeNotifierProvider<HomeScreenController, HomeScreenState>
homeScreenControllerProvider =
    NotifierProvider.autoDispose<HomeScreenController, HomeScreenState>(
      HomeScreenController.new,
    );
