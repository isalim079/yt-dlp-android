/// In-app player: resolve streams, play adaptive/progressive, 403 fallback.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/constants/app_strings.dart';
import '../../core/exceptions/ytdlp_exception.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/platform_utils.dart';
import '../../core/utils/youtube_urls.dart';
import '../local/library_store.dart';
import '../models/app_settings.dart';
import '../models/browse_video.dart';
import '../models/playback_resolved.dart';
import '../models/video_format.dart';
import '../models/video_info.dart';
import '../providers/download_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/ytdlp_providers.dart';
import '../services/ytdlp_platform_channel.dart';
import '../services/ytdlp_service.dart';

/// UI snapshot for the in-app player.
@immutable
class PlayerUiState {
  /// Creates player UI state.
  const PlayerUiState({
    this.video,
    this.resolved,
    this.quality = PlaybackQuality.auto,
    this.expanded = false,
    this.loading = false,
    this.error,
    this.queue = const <BrowseVideo>[],
    this.queueIndex = 0,
    this.surfaceEpoch = 0,
  });

  /// Currently playing catalog item.
  final BrowseVideo? video;

  /// Last resolved streams.
  final PlaybackResolved? resolved;

  /// Selected quality.
  final PlaybackQuality quality;

  /// Fullscreen watch page vs mini-player.
  final bool expanded;

  /// Stream resolve / open in flight.
  final bool loading;

  /// User-facing error.
  final String? error;

  /// Optional play-all queue.
  final List<BrowseVideo> queue;

  /// Index in [queue].
  final int queueIndex;

  /// Bumped after the native [VideoController] is created so the watch
  /// surface rebuilds with a non-null controller.
  final int surfaceEpoch;

  /// Whether a session is active.
  bool get hasSession => video != null;

  /// Copy with overrides.
  PlayerUiState copyWith({
    BrowseVideo? video,
    PlaybackResolved? resolved,
    PlaybackQuality? quality,
    bool? expanded,
    bool? loading,
    String? error,
    bool clearError = false,
    List<BrowseVideo>? queue,
    int? queueIndex,
    int? surfaceEpoch,
    bool clearSession = false,
  }) {
    return PlayerUiState(
      video: clearSession ? null : (video ?? this.video),
      resolved: clearSession ? null : (resolved ?? this.resolved),
      quality: quality ?? this.quality,
      expanded: clearSession ? false : (expanded ?? this.expanded),
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      surfaceEpoch: clearSession ? 0 : (surfaceEpoch ?? this.surfaceEpoch),
    );
  }
}

/// Owns the media_kit [Player] for the app lifetime after first play.
class PlayerController extends Notifier<PlayerUiState> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;
  Timer? _historyTimer;
  int _generation = 0;
  bool _opening = false;

  /// Underlying player, created lazily.
  Player? get rawPlayer => _player;

  /// Video output controller, created lazily.
  VideoController? get videoController => _videoController;

  @override
  PlayerUiState build() {
    ref.onDispose(() {
      unawaited(_tearDown());
    });
    return const PlayerUiState();
  }

  PlaybackQuality _qualityFromSettings(AppSettings settings) {
    return switch (settings.playbackQuality) {
      PlaybackQualitySetting.auto => PlaybackQuality.auto,
      PlaybackQualitySetting.p1080 => PlaybackQuality.p1080,
      PlaybackQualitySetting.p720 => PlaybackQuality.p720,
      PlaybackQualitySetting.p480 => PlaybackQuality.p480,
      PlaybackQualitySetting.p360 => PlaybackQuality.p360,
    };
  }

  /// Starts playback of [video], optionally with a [queue].
  Future<void> play(
    BrowseVideo video, {
    List<BrowseVideo>? queue,
    int index = 0,
    bool expanded = true,
    PlaybackQuality? quality,
  }) async {
    final AppSettings? settings = ref.read(settingsProvider).valueOrNull;
    final PlaybackQuality q =
        quality ?? _qualityFromSettings(settings ?? AppSettings.defaults);
    state = state.copyWith(
      video: video,
      quality: q,
      expanded: expanded,
      loading: true,
      clearError: true,
      queue: queue ?? <BrowseVideo>[video],
      queueIndex: index,
    );
    await _ensurePlayer();
    await _openCurrent(forceRefresh: false);
  }

  /// Changes quality and re-resolves.
  Future<void> setQuality(PlaybackQuality quality) async {
    if (state.video == null) {
      return;
    }
    state = state.copyWith(quality: quality, loading: true, clearError: true);
    await _openCurrent(forceRefresh: true);
  }

  /// Expands the watch page.
  void expand() {
    if (state.hasSession) {
      state = state.copyWith(expanded: true);
    }
  }

  /// Collapses to mini-player.
  void collapse() {
    state = state.copyWith(expanded: false);
  }

  /// Stops playback and hides the player.
  Future<void> stop() async {
    _historyTimer?.cancel();
    try {
      await _player?.stop();
    } on Object catch (error, stack) {
      AppLogger.w('player stop failed: $error\n$stack');
    }
    if (Platform.isAndroid) {
      unawaited(
        YtdlpPlatformChannel.setPlaybackService(active: false),
      );
    }
    state = state.copyWith(clearSession: true, loading: false, clearError: true);
  }

  /// Plays the next queued item.
  Future<void> playNext() async {
    if (state.queue.isEmpty) {
      return;
    }
    final int next = state.queueIndex + 1;
    if (next >= state.queue.length) {
      return;
    }
    await play(
      state.queue[next],
      queue: state.queue,
      index: next,
      expanded: state.expanded,
      quality: state.quality,
    );
  }

  /// Enters Android PiP when possible.
  Future<void> enterPip() async {
    if (!Platform.isAndroid) {
      return;
    }
    await YtdlpPlatformChannel.enterPictureInPicture();
  }

  /// Queues a download of the current video at best adaptive quality.
  Future<void> downloadCurrent() async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    final String outputPath = ref.read(outputPathProvider);
    const VideoFormat format = VideoFormat(
      formatId: 'bv*+ba/b',
      extension: 'mp4',
      displayLabel: 'Best available (auto)',
    );
    await ref.read(downloadManagerProvider.notifier).addDownload(
      url: video.url,
      format: format,
      outputPath: outputPath,
      title: video.title,
      thumbnailUrl: video.thumbnail,
    );
  }

  Future<void> _ensurePlayer() async {
    if (_player != null) {
      return;
    }
    final bool emulator = await PlatformUtils.isAndroidEmulator;
    _player = Player(
      configuration: const PlayerConfiguration(
        title: AppStrings.appName,
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !emulator,
        hwdec: emulator ? 'no' : 'auto-safe',
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );
    state = state.copyWith(surfaceEpoch: state.surfaceEpoch + 1);
    _errorSub = _player!.stream.error.listen((String message) {
      unawaited(_onPlayerError(message));
    });
    _completedSub = _player!.stream.completed.listen((bool done) {
      if (done && !_opening) {
        unawaited(playNext());
      }
    });
    _positionSub = _player!.stream.position.listen((Duration position) {
      _maybeWriteHistory(position);
    });
  }

  Future<void> _openCurrent({required bool forceRefresh}) async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    final int gen = ++_generation;
    _opening = true;
    try {
      final AppSettings settings =
          ref.read(settingsProvider).valueOrNull ?? AppSettings.defaults;
      final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
      PlaybackResolved resolved = await ytdlp.resolvePlayback(
        video.url,
        quality: state.quality,
        playerClient: settings.playerClient.ytDlpValue,
        forceRefresh: forceRefresh,
      );
      if (gen != _generation) {
        return;
      }
      state = state.copyWith(resolved: resolved);
      await _openResolved(resolved, allowProgressiveFallback: true);
      if (gen != _generation) {
        return;
      }
      final int resume = await ref
          .read(libraryStoreProvider)
          .positionFor(video.id);
      if (resume > 3000) {
        await _player?.seek(Duration(milliseconds: resume));
      }
      unawaited(
        ref.read(libraryActionsProvider).recordWatch(video, resume),
      );
      if (Platform.isAndroid && settings.backgroundPlayback) {
        unawaited(YtdlpPlatformChannel.setPlaybackService(active: true));
      }
      state = state.copyWith(loading: false, clearError: true);
    } on Object catch (error, stack) {
      AppLogger.e('open playback failed', error, stack);
      if (gen != _generation) {
        return;
      }
      final bool retried = await _retryWithFallbackClient(video, gen);
      if (!retried && gen == _generation) {
        state = state.copyWith(
          loading: false,
          error: _friendlyError(error),
        );
      }
    } finally {
      if (gen == _generation) {
        _opening = false;
      }
    }
  }

  Future<void> _openResolved(
    PlaybackResolved resolved, {
    required bool allowProgressiveFallback,
  }) async {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final Map<String, String> headers = resolved.headers;
    Media(resolved.primaryUrl, httpHeaders: headers);
    if (resolved.videoUrl != null) {
      Media(resolved.videoUrl!, httpHeaders: headers);
    }
    if (resolved.audioUrl != null) {
      Media(resolved.audioUrl!, httpHeaders: headers);
    }
    if (resolved.progressiveUrl != null) {
      Media(resolved.progressiveUrl!, httpHeaders: headers);
    }
    try {
      final bool emulator = await PlatformUtils.isAndroidEmulator;
      if (emulator &&
          resolved.progressiveUrl != null &&
          resolved.progressiveUrl!.isNotEmpty) {
        await player.open(
          Media(resolved.progressiveUrl!, httpHeaders: headers),
          play: true,
        );
        return;
      }
      if (resolved.mode == PlaybackMode.adaptive &&
          resolved.videoUrl != null) {
        await player.open(
          Media(resolved.videoUrl!, httpHeaders: headers),
          play: true,
        );
        if (resolved.hasSeparateAudio) {
          await player.setAudioTrack(AudioTrack.uri(resolved.audioUrl!));
        }
        return;
      }
      await player.open(
        Media(resolved.primaryUrl, httpHeaders: headers),
        play: true,
      );
    } on Object catch (error, stack) {
      AppLogger.w('primary open failed: $error\n$stack');
      if (allowProgressiveFallback &&
          resolved.progressiveUrl != null &&
          resolved.progressiveUrl != resolved.primaryUrl) {
        await player.open(
          Media(resolved.progressiveUrl!, httpHeaders: headers),
          play: true,
        );
        return;
      }
      rethrow;
    }
  }

  Future<bool> _retryWithFallbackClient(BrowseVideo video, int gen) async {
    try {
      final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
      final PlaybackResolved resolved = await ytdlp.resolvePlayback(
        video.url,
        quality: state.quality,
        playerClient: PlayerClientPreset.androidVr.ytDlpValue,
        forceRefresh: true,
      );
      if (gen != _generation) {
        return true;
      }
      state = state.copyWith(resolved: resolved);
      await _openResolved(resolved, allowProgressiveFallback: true);
      state = state.copyWith(loading: false, clearError: true);
      return true;
    } on Object catch (error, stack) {
      AppLogger.e('fallback client playback failed', error, stack);
      return false;
    }
  }

  Future<void> _onPlayerError(String message) async {
    if (_opening) {
      return;
    }
    final String lower = message.toLowerCase();
    if (!(lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('failed to open') ||
        lower.contains('http error'))) {
      return;
    }
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    AppLogger.w('player error, re-resolving: $message');
    state = state.copyWith(loading: true, error: AppStrings.errorPlaybackFailed);
    await _openCurrent(forceRefresh: true);
  }

  void _maybeWriteHistory(Duration position) {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(seconds: 4), () {
      final BrowseVideo? video = state.video;
      if (video == null) {
        return;
      }
      unawaited(
        ref.read(libraryActionsProvider).recordWatch(
          video,
          position.inMilliseconds,
        ),
      );
    });
  }

  String _friendlyError(Object error) {
    if (error is YtdlpException) {
      return error.message;
    }
    final String lower = error.toString().toLowerCase();
    if (lower.contains('403') || lower.contains('forbidden')) {
      return AppStrings.errorForbidden;
    }
    return AppStrings.errorExtractionBroken;
  }

  Future<void> _tearDown() async {
    _historyTimer?.cancel();
    await _errorSub?.cancel();
    await _completedSub?.cancel();
    await _positionSub?.cancel();
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  /// Follows the current video's channel when a URL is known.
  Future<void> followCurrentChannel() async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    final String? channelUrl = video.channelUrl;
    if (channelUrl == null || channelUrl.isEmpty) {
      return;
    }
    final String id =
        YoutubeUrls.channelId(channelUrl) ?? channelUrl;
    await ref.read(libraryActionsProvider).follow(
      FollowedChannel(
        id: id,
        title: video.uploader ?? id,
        url: channelUrl,
        followedAt: DateTime.now(),
      ),
    );
  }
}

/// App-wide player controller.
final NotifierProvider<PlayerController, PlayerUiState> playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);

/// Convenience: play from [VideoInfo].
extension PlayerControllerVideoInfo on PlayerController {
  /// Plays a resolved [VideoInfo] row.
  Future<void> playVideoInfo(VideoInfo info) {
    return play(BrowseVideo.fromVideoInfo(info));
  }
}
