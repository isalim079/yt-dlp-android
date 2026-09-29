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
import '../../core/utils/permission_handler_util.dart';
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
import '../services/playback_hd_fallback.dart';
import '../services/playback_po_token.dart';
import '../services/playback_seek.dart';
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
  int _streamErrorRetries = 0;
  String? _safeProgressiveUrl;
  Map<String, String> _safeProgressiveHeaders = const <String, String>{};

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

  /// Starts playback of [video], optionally with a [queue].
  Future<void> play(
    BrowseVideo video, {
    List<BrowseVideo>? queue,
    int index = 0,
    bool expanded = true,
  }) async {
    _streamErrorRetries = 0;
    _safeProgressiveUrl = null;
    state = state.copyWith(
      video: video,
      quality: PlaybackQuality.p360,
      expanded: expanded,
      loading: true,
      clearError: true,
      queue: queue ?? <BrowseVideo>[video],
      queueIndex: index,
    );
    if (Platform.isAndroid) {
      unawaited(
        PlaybackPoTokenService.ensureMinter(rethrowOnError: false),
      );
    }
    await _startAt360(
      forceRefresh: false,
      preservePosition: false,
      playerReady: _ensurePlayer(),
    );
  }

  /// Seeks relative to the current position (double-tap skip).
  Future<void> seekBy(Duration delta) async {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final Duration target = playbackClampSeek(
      player.state.position,
      delta,
      player.state.duration,
    );
    try {
      await player.seek(target).timeout(const Duration(seconds: 3));
    } on TimeoutException {
      AppLogger.w('seekBy timed out');
    }
  }

  /// Changes quality from cached JSON (HD warmer or preferred). One reopen.
  Future<void> setQuality(PlaybackQuality quality) async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    state = state.copyWith(quality: quality, loading: false, clearError: true);
    final Duration? keepAt = _player?.state.position;
    try {
      await _ensurePlayer();
      final PlaybackResolved resolved = await _resolveQualityFromCache(
        url: video.url,
        quality: quality,
      );
      if (state.video?.id != video.id) {
        return;
      }
      state = state.copyWith(resolved: resolved, quality: quality);
      // 360 = muxed progressive; everything else = adaptive A/V from HD cache.
      await _openResolved(
        resolved,
        allowProgressiveFallback: quality == PlaybackQuality.p360,
        preferProgressive: quality == PlaybackQuality.p360,
      );
      if (keepAt != null && keepAt.inMilliseconds > 500) {
        try {
          await _player?.seek(keepAt).timeout(const Duration(seconds: 3));
        } on TimeoutException {
          AppLogger.w('quality seek timed out');
        }
      }
    } on Object catch (error, stack) {
      AppLogger.e('setQuality failed', error, stack);
      if (state.video?.id == video.id) {
        state = state.copyWith(error: _friendlyError(error));
      }
    }
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
    );
  }

  /// Enters Android PiP when possible.
  Future<void> enterPip() async {
    if (!Platform.isAndroid) {
      return;
    }
    await YtdlpPlatformChannel.enterPictureInPicture();
  }

  /// Queues a download of the current video at [format], or best adaptive.
  Future<void> downloadCurrent({VideoFormat? format}) async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    final String outputPath = ref.read(outputPathProvider);
    final bool granted =
        await PermissionHandlerUtil.hasStoragePermission(
          outputPath: outputPath,
        ) ||
        await PermissionHandlerUtil.requestStoragePermission(
          outputPath: outputPath,
        );
    if (!granted) {
      return;
    }
    final VideoFormat selected =
        format ?? VideoFormat.downloadSelector();
    await ref.read(downloadManagerProvider.notifier).addDownload(
      url: video.url,
      format: selected,
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
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    // Emulators' EGL/gpu vo path stays black (media-kit#1343). MediaCodec
    // embed draws into the Surface instead. Keep gpu/auto-safe on devices.
    final VideoControllerConfiguration videoConfig = emulator
        ? const VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            enableHardwareAcceleration: true,
          )
        : const VideoControllerConfiguration(
            hwdec: 'auto-safe',
            enableHardwareAcceleration: true,
          );
    AppLogger.i(
      emulator
          ? 'player surface: emulator mediacodec_embed'
          : 'player surface: device gpu/auto-safe',
    );
    _videoController = VideoController(_player!, configuration: videoConfig);
    state = state.copyWith(surfaceEpoch: state.surfaceEpoch + 1);
    try {
      await _videoController!.platform.future.timeout(
        const Duration(seconds: 8),
      );
    } on TimeoutException {
      AppLogger.w('VideoController native init timed out');
    }
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
    await _applyNetworkCacheProperties(_player!);
  }

  Future<void> _applyNetworkCacheProperties(Player player) async {
    final PlatformPlayer? platform = player.platform;
    if (platform is! NativePlayer) {
      return;
    }
    try {
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('demuxer-readahead-secs', '15');
      await platform.setProperty('force-seekable', 'yes');
    } on Object catch (error) {
      AppLogger.w('mpv cache properties failed: $error');
    }
  }

  Future<void> _startAt360({
    required bool forceRefresh,
    required bool preservePosition,
    Future<void>? playerReady,
  }) async {
    final BrowseVideo? video = state.video;
    if (video == null) {
      return;
    }
    final int gen = ++_generation;
    _opening = true;
    final Future<void> ready = playerReady ?? _ensurePlayer();
    final Duration? keepAt = preservePosition ? _player?.state.position : null;
    try {
      final AppSettings settings =
          ref.read(settingsProvider).valueOrNull ?? AppSettings.defaults;
      final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
      await ready;
      await _waitForSurface();
      if (gen != _generation) {
        return;
      }
      final PlaybackResolved start = await resolvePlaybackStart(
        ytdlp: ytdlp,
        url: video.url,
        forceRefresh: forceRefresh,
        mintPoTokens: PlaybackPoTokenService.mint,
      );
      if (gen != _generation) {
        return;
      }
      _rememberSafeProgressive(start);
      state = state.copyWith(
        resolved: start,
        quality: PlaybackQuality.p360,
        loading: false,
        clearError: true,
      );
      final bool hasSafeProgressive = start.progressiveUrl != null &&
          start.progressiveUrl!.isNotEmpty &&
          !playbackUrlIsAndroidVr(start.progressiveUrl);
      await _openResolved(
        start,
        allowProgressiveFallback: true,
        preferProgressive: hasSafeProgressive,
      );
      if (gen != _generation) {
        return;
      }
      int resumeMs = 0;
      if (keepAt != null && keepAt.inMilliseconds > 500) {
        resumeMs = keepAt.inMilliseconds;
      } else if (!preservePosition) {
        resumeMs = await ref.read(libraryStoreProvider).positionFor(video.id);
      }
      final int minSeekMs = preservePosition ? 500 : 3000;
      if (resumeMs > minSeekMs) {
        try {
          await _player?.seek(Duration(milliseconds: resumeMs)).timeout(
            const Duration(seconds: 3),
          );
        } on TimeoutException {
          AppLogger.w('resume seek timed out');
        }
      }
      unawaited(
        ref.read(libraryActionsProvider).recordWatch(video, resumeMs),
      );
      if (Platform.isAndroid && settings.backgroundPlayback) {
        unawaited(YtdlpPlatformChannel.setPlaybackService(active: true));
      }
      unawaited(
        _warmHdInBackground(
          gen: gen,
          url: video.url,
          preferredClient: kPlaybackStartClient,
          start: start,
          ytdlp: ytdlp,
        ),
      );
    } on Object catch (error, stack) {
      AppLogger.e('open playback failed', error, stack);
      if (gen != _generation) {
        return;
      }
      state = state.copyWith(
        loading: false,
        error: _friendlyError(error),
      );
    } finally {
      if (gen == _generation) {
        _opening = false;
      }
    }
  }

  Future<void> _warmHdInBackground({
    required int gen,
    required String url,
    required String preferredClient,
    required PlaybackResolved start,
    required YtdlpService ytdlp,
  }) async {
    if (!playbackNeedsExtraClient(start)) {
      return;
    }
    try {
      final PlaybackResolved? hd = await warmPlaybackHdLadder(
        ytdlp: ytdlp,
        url: url,
        preferredClient: preferredClient,
        start: start,
        mintPoTokens: PlaybackPoTokenService.mint,
      );
      if (gen != _generation || hd == null) {
        return;
      }
      AppLogger.i(
        'HD ladder ready max=${playbackMaxAvailableHeight(hd)}',
      );
      // Picker only — never reopen and never replace safe progressive.
      state = state.copyWith(resolved: hd);
    } on Object catch (error, stack) {
      AppLogger.w('HD warm failed: $error\n$stack');
    }
  }

  Future<PlaybackResolved> _resolveQualityFromCache({
    required String url,
    required PlaybackQuality quality,
  }) async {
    final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
    // mweb (PO-warmed) first, then VR-if-tall, then start client, then safari.
    final List<String> clients = <String>[
      kPlaybackMwebClient,
      kPlaybackHdFallbackClient,
      kPlaybackStartClient,
      kPlaybackWebSafariClient,
    ];
    PlaybackResolved? best;
    for (final String client in clients.toSet()) {
      try {
        final PlaybackResolved resolved = await ytdlp.resolvePlayback(
          url,
          quality: quality,
          playerClient: client,
          forceRefresh: false,
        );
        // Skip VR-only-360 caches for non-360 quality picks.
        if (client == kPlaybackHdFallbackClient &&
            quality != PlaybackQuality.p360 &&
            playbackMaxAvailableHeight(resolved) < 720) {
          continue;
        }
        if (best == null || playbackFallbackImproves(best, resolved)) {
          best = resolved;
        }
        if (resolved.offersQuality(quality) &&
            (quality == PlaybackQuality.p360 ||
                quality == PlaybackQuality.auto ||
                !playbackNeedsExtraClient(resolved))) {
          return playbackKeepStartProgressive(
            state.resolved ?? resolved,
            resolved,
          );
        }
      } on Object catch (error) {
        AppLogger.w('quality resolve via $client failed: $error');
      }
    }
    if (best != null) {
      final PlaybackResolved? start = state.resolved;
      if (start != null) {
        return playbackKeepStartProgressive(start, best);
      }
      return best;
    }
    throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
  }

  Future<void> _waitForSurface() async {
    final VideoController? controller = _videoController;
    if (controller == null || controller.id.value != null) {
      return;
    }
    final Completer<void> ready = Completer<void>();
    void listener() {
      if (controller.id.value != null && !ready.isCompleted) {
        ready.complete();
      }
    }

    controller.id.addListener(listener);
    try {
      await ready.future.timeout(const Duration(milliseconds: 400));
    } on TimeoutException {
      // Video widget may attach on the first decoded frame.
    } finally {
      controller.id.removeListener(listener);
    }
  }

  Future<void> _openResolved(
    PlaybackResolved resolved, {
    required bool allowProgressiveFallback,
    bool preferProgressive = false,
  }) async {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final Map<String, String> headers = resolved.headers;
    try {
      final bool emulator = await PlatformUtils.isAndroidEmulator;
      final String? progressive = resolved.progressiveUrl;
      final bool progressiveOk = progressive != null &&
          progressive.isNotEmpty &&
          !playbackUrlIsAndroidVr(progressive);
      final bool useProgressive =
          (preferProgressive || emulator) && progressiveOk;
      AppLogger.i(
        'open playback format=${resolved.formatId} height=${resolved.height} '
        'mode=${resolved.mode.name} preferProgressive=$preferProgressive '
        'useProgressive=$useProgressive',
      );
      if (useProgressive) {
        await _openMedia(
          player,
          Media(progressive, httpHeaders: headers),
        );
        _logPlaybackVisibility();
        return;
      }
      if (preferProgressive && !progressiveOk) {
        // Prefer start safe progressive over any ANDROID_VR itag 18.
        final String? safe = _safeProgressiveUrl;
        if (safe != null &&
            safe.isNotEmpty &&
            !playbackUrlIsAndroidVr(safe)) {
          await _openMedia(
            player,
            Media(safe, httpHeaders: _safeProgressiveHeaders),
          );
          _logPlaybackVisibility();
          return;
        }
        // Fall through to adaptive / HLS when progressive is unavailable.
      }
      if (resolved.mode == PlaybackMode.hls &&
          resolved.hlsUrl != null &&
          resolved.hlsUrl!.isNotEmpty) {
        await _openMedia(
          player,
          Media(resolved.hlsUrl!, httpHeaders: headers),
        );
        _logPlaybackVisibility();
        return;
      }
      if (resolved.mode == PlaybackMode.adaptive &&
          resolved.videoUrl != null &&
          !playbackUrlIsAndroidVr(resolved.videoUrl)) {
        await _openMedia(
          player,
          Media(resolved.videoUrl!, httpHeaders: headers),
          play: false,
        );
        if (resolved.hasSeparateAudio) {
          try {
            await player.setAudioTrack(AudioTrack.uri(resolved.audioUrl!)).timeout(
              const Duration(seconds: 5),
            );
          } on TimeoutException {
            AppLogger.w('setAudioTrack timed out');
          }
        }
        try {
          await player.play().timeout(const Duration(seconds: 8));
        } on TimeoutException {
          AppLogger.w('player.play after adaptive attach timed out');
        }
        _logPlaybackVisibility();
        return;
      }
      if (playbackUrlIsAndroidVr(resolved.primaryUrl)) {
        throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
      }
      await _openMedia(
        player,
        Media(resolved.primaryUrl, httpHeaders: headers),
      );
      _logPlaybackVisibility();
    } on Object catch (error, stack) {
      AppLogger.w('primary open failed: $error\n$stack');
      if (allowProgressiveFallback) {
        final String? fallback = _safeProgressiveUrl ?? resolved.progressiveUrl;
        if (fallback != null &&
            fallback.isNotEmpty &&
            !playbackUrlIsAndroidVr(fallback) &&
            fallback != resolved.primaryUrl) {
          await _openMedia(
            player,
            Media(
              fallback,
              httpHeaders: _safeProgressiveUrl != null
                  ? _safeProgressiveHeaders
                  : headers,
            ),
          );
          _logPlaybackVisibility();
          return;
        }
      }
      rethrow;
    }
  }

  Future<void> _openMedia(
    Player player,
    Media media, {
    bool play = true,
  }) async {
    try {
      await player.open(media, play: play).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      AppLogger.w('player.open timed out; requesting play anyway');
      if (play) {
        try {
          await player.play();
        } on Object catch (error) {
          AppLogger.w('player.play after timeout failed: $error');
        }
      }
    }
  }

  void _logPlaybackVisibility() {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final VideoParams video = player.state.videoParams;
    AppLogger.i(
      'playback visibility: playing=${player.state.playing} '
      'buffering=${player.state.buffering} '
      'width=${video.w} height=${video.h} '
      'duration=${player.state.duration.inMilliseconds}ms',
    );
  }

  void _rememberSafeProgressive(PlaybackResolved resolved) {
    final String? url = resolved.progressiveUrl;
    if (url == null || url.isEmpty || playbackUrlIsAndroidVr(url)) {
      return;
    }
    _safeProgressiveUrl = url;
    _safeProgressiveHeaders = Map<String, String>.from(resolved.headers);
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
    AppLogger.w('player error: $message');
    // Never reopen the same dead URI (often ANDROID_VR itag 18).
    if (_streamErrorRetries >= 1) {
      state = state.copyWith(
        loading: false,
        error: AppStrings.errorPlaybackFailed,
      );
      return;
    }
    _streamErrorRetries += 1;
    state = state.copyWith(
      loading: true,
      error: AppStrings.errorPlaybackFailed,
    );
    await _startAt360(forceRefresh: true, preservePosition: true);
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
    if (error is TimeoutException ||
        lower.contains('timeout') ||
        lower.contains('timed out')) {
      return AppStrings.errorTimeout;
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
