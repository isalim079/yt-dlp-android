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
import '../providers/api_providers.dart';
import '../providers/download_providers.dart';
import '../providers/library_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/ytdlp_providers.dart';
import '../services/playback_hd_fallback.dart';
import '../services/playback_po_token.dart';
import '../services/playback_seek.dart';
import '../services/playback_source_router.dart';
import '../services/playback_stream_validate.dart';
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
    this.shortsMode = false,
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

  /// Vertical Shorts tab owns the surface (hide WatchPage + mini bar).
  final bool shortsMode;

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
    bool? shortsMode,
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
      shortsMode: clearSession ? false : (shortsMode ?? this.shortsMode),
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
    bool shortsMode = false,
  }) async {
    _streamErrorRetries = 0;
    _safeProgressiveUrl = null;
    state = state.copyWith(
      video: video,
      quality: PlaybackQuality.p360,
      expanded: shortsMode ? false : expanded,
      shortsMode: shortsMode,
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
      final bool low = quality == PlaybackQuality.p360 ||
          quality == PlaybackQuality.p480;
      await _openResolved(
        resolved,
        allowProgressiveFallback: low,
        preferProgressive: quality == PlaybackQuality.p360,
        preferAdaptive: !low,
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
      final PlaybackSourceRouter router =
          ref.read(playbackSourceRouterProvider);
      await ready;
      await _waitForSurface();
      if (gen != _generation) {
        return;
      }
      final RoutedPlayback routed = await router.resolveStart(
        url: video.url,
        forceRefresh: forceRefresh,
      );
      final PlaybackResolved start = routed.resolved;
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
      final bool emulator = await PlatformUtils.isAndroidEmulator;
      await _openResolved(
        start,
        allowProgressiveFallback: true,
        preferProgressive: hasSafeProgressive || emulator,
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
          start: start,
          router: router,
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
    required PlaybackResolved start,
    required PlaybackSourceRouter router,
  }) async {
    try {
      final RoutedPlayback? hd = await router.warmHd(url: url, start: start);
      if (gen != _generation || hd == null) {
        return;
      }
      final PlaybackResolved upgraded = hd.resolved;
      AppLogger.i(
        'HD ladder ready max=${playbackMaxAvailableHeight(upgraded)} '
        'fromServer=${hd.fromServer} height=${upgraded.height}',
      );
      state = state.copyWith(
        resolved: upgraded,
        quality: PlaybackQuality.auto,
      );
      final int startH = start.height ?? 0;
      final int hdH = upgraded.height ?? 0;
      final bool canAdaptive = upgraded.videoUrl != null &&
          upgraded.videoUrl!.isNotEmpty &&
          upgraded.hasSeparateAudio;
      if (hdH > startH && canAdaptive && !_opening) {
        final Duration keepAt = _player?.state.position ?? Duration.zero;
        AppLogger.i(
          'HD reopen adaptive height=$hdH (was $startH) pos=${keepAt.inSeconds}s',
        );
        await _openResolved(
          upgraded,
          allowProgressiveFallback: true,
          preferProgressive: false,
          preferAdaptive: true,
        );
        if (gen != _generation) {
          return;
        }
        if (keepAt.inMilliseconds > 500) {
          try {
            await _player?.seek(keepAt).timeout(const Duration(seconds: 3));
          } on TimeoutException {
            AppLogger.w('HD resume seek timed out');
          }
        }
        await _assertActualHeight(upgraded);
      }
    } on Object catch (error, stack) {
      AppLogger.w('HD warm failed: $error\n$stack');
    }
  }

  Future<PlaybackResolved> _resolveQualityFromCache({
    required String url,
    required PlaybackQuality quality,
  }) async {
    final PlaybackSourceRouter router = ref.read(playbackSourceRouterProvider);
    try {
      final RoutedPlayback routed = await router.resolve(
        url: url,
        quality: quality,
        forceRefresh: false,
      );
      return playbackKeepStartProgressive(
        state.resolved ?? routed.resolved,
        routed.resolved,
      );
    } on Object catch (error) {
      AppLogger.w('router quality resolve failed: $error');
    }
    final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
    // Capability-based clients — never android_vr.
    final List<String> clients = <String>[
      kPlaybackStartClient,
      kPlaybackAndroidClient,
      kPlaybackMwebClient,
      kPlaybackWebSafariClient,
      kPlaybackWebEmbeddedClient,
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
        if (playbackUrlIsAndroidVr(resolved.primaryUrl)) {
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
    bool preferAdaptive = false,
  }) async {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final Map<String, String> headers = resolved.headers;
    final String? progressive = resolved.progressiveUrl;
    final bool progressiveOk = progressive != null &&
        progressive.isNotEmpty &&
        !playbackUrlIsAndroidVr(progressive);
    final String? hls = resolved.hlsUrl;
    final bool hlsOk = hls != null && hls.isNotEmpty;
    final String? video = resolved.videoUrl;
    final bool adaptiveOk = video != null &&
        video.isNotEmpty &&
        !playbackUrlIsAndroidVr(video);

    final List<_OpenAttempt> attempts = <_OpenAttempt>[];
    if (preferProgressive && progressiveOk) {
      attempts.add(
        _OpenAttempt('progressive', progressive, headers: headers),
      );
    }
    // HD / explicit ≥720: adaptive V+A first (README quality proof).
    if (preferAdaptive && adaptiveOk) {
      attempts.add(
        _OpenAttempt(
          'adaptive',
          video,
          headers: headers,
          audioUrl: resolved.hasSeparateAudio ? resolved.audioUrl : null,
        ),
      );
    }
    if (hlsOk && !preferAdaptive) {
      attempts.add(_OpenAttempt('hls', hls, headers: headers));
    }
    if (progressiveOk && !preferProgressive) {
      attempts.add(
        _OpenAttempt('progressive', progressive, headers: headers),
      );
    }
    if (adaptiveOk && !preferAdaptive) {
      attempts.add(
        _OpenAttempt(
          'adaptive',
          video,
          headers: headers,
          audioUrl: resolved.hasSeparateAudio ? resolved.audioUrl : null,
        ),
      );
    }
    if (hlsOk && preferAdaptive) {
      attempts.add(_OpenAttempt('hls', hls, headers: headers));
    }
    if (allowProgressiveFallback) {
      final String? safe = _safeProgressiveUrl;
      if (safe != null &&
          safe.isNotEmpty &&
          !playbackUrlIsAndroidVr(safe) &&
          !attempts.any((_OpenAttempt a) => a.url == safe)) {
        attempts.add(
          _OpenAttempt('safe-progressive', safe, headers: _safeProgressiveHeaders),
        );
      }
    }

    if (attempts.isEmpty) {
      throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
    }

    Object? lastError;
    for (var i = 0; i < attempts.length; i++) {
      final _OpenAttempt attempt = attempts[i];
      try {
        AppLogger.i(
          'open attempt ${i + 1}/${attempts.length} kind=${attempt.kind} '
          'hasAudio=${attempt.audioUrl != null}',
        );
      await _applyHttpHeaderFields(player, attempt.headers);
      // Probe before open so we don't hand dead itag=140 audio to media_kit.
      if (attempt.audioUrl != null && attempt.audioUrl!.isNotEmpty) {
        final StreamValidationResult probe = await validatePlaybackStreams(
          PlaybackResolved(
            info: resolved.info,
            mode: PlaybackMode.adaptive,
            headers: attempt.headers,
            quality: resolved.quality,
            videoUrl: attempt.url,
            audioUrl: attempt.audioUrl,
            height: resolved.height,
            expiresAt: resolved.expiresAt,
            formatId: resolved.formatId,
            availableHeights: resolved.availableHeights,
          ),
        );
        if (!probe.ok) {
          AppLogger.w(
            'skip adaptive open: probe failed v=${probe.videoStatus} '
            'a=${probe.audioStatus}',
          );
          continue;
        }
      }
      final bool started = await _openAttempt(player, attempt);
        _logPlaybackVisibility();
        if (started) {
          if (preferAdaptive ||
              (resolved.height ?? 0) >= 720 ||
              state.quality == PlaybackQuality.auto) {
            await _assertActualHeight(resolved);
          }
          return;
        }
        AppLogger.w('open stalled on ${attempt.kind}; trying next');
      } on Object catch (error, stack) {
        lastError = error;
        AppLogger.w('open ${attempt.kind} failed: $error\n$stack');
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw const YtdlpException(AppStrings.errorNoPlaybackStreams);
  }

  Future<bool> _openAttempt(Player player, _OpenAttempt attempt) async {
    if (attempt.audioUrl != null && attempt.audioUrl!.isNotEmpty) {
      await _applyHttpHeaderFields(player, attempt.headers);
      await _openMedia(
        player,
        Media(attempt.url, httpHeaders: attempt.headers),
        play: false,
      );
      try {
        await player
            .setAudioTrack(AudioTrack.uri(attempt.audioUrl!))
            .timeout(const Duration(seconds: 5));
      } on TimeoutException {
        AppLogger.w('setAudioTrack timed out');
      }
      try {
        await player.play().timeout(const Duration(seconds: 8));
      } on TimeoutException {
        AppLogger.w('player.play after adaptive attach timed out');
      }
    } else {
      await _openMedia(
        player,
        Media(attempt.url, httpHeaders: attempt.headers),
      );
    }
    return _waitUntilPlaybackAlive();
  }

  /// Propagate CDN headers to mpv so external audio tracks can fetch too.
  Future<void> _applyHttpHeaderFields(
    Player player,
    Map<String, String> headers,
  ) async {
    if (headers.isEmpty) {
      return;
    }
    try {
      final String joined = headers.entries
          .map((MapEntry<String, String> e) => '${e.key}: ${e.value}')
          .join('\r\n');
      final dynamic platform = player.platform;
      await platform.setProperty('http-header-fields', joined);
    } on Object catch (e) {
      AppLogger.w('http-header-fields set failed: $e');
    }
  }

  /// README §23: selected HD must not silently play as ~360.
  Future<void> _assertActualHeight(PlaybackResolved resolved) async {
    final Player? player = _player;
    if (player == null) {
      return;
    }
    final int expected = resolved.height ?? 0;
    if (expected < 720) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final VideoParams params = player.state.videoParams;
    final int actualH = params.h ?? 0;
    final int actualW = params.w ?? 0;
    AppLogger.i(
      'playback height assert expected=$expected actual=${actualW}x$actualH '
      'quality=${state.quality.name} mode=${resolved.mode.name}',
    );
    if (actualH > 0 && actualH < 900 && expected >= 1080) {
      AppLogger.w(
        'PLAYBACK_QUALITY_MISMATCH expected>=$expected actual=$actualH',
      );
      unawaited(_reportQualityMismatch(
        expectedHeight: expected,
        actualWidth: actualW,
        actualHeight: actualH,
      ));
    }
  }

  Future<void> _reportQualityMismatch({
    required int expectedHeight,
    required int actualWidth,
    required int actualHeight,
  }) async {
    try {
      final BrowseVideo? video = state.video;
      if (video == null) {
        return;
      }
      final String? id = YoutubeUrls.videoId(video.url);
      if (id == null) {
        return;
      }
      final AppSettings settings =
          ref.read(settingsProvider).valueOrNull ?? AppSettings.defaults;
      if (settings.apiBaseUrl.trim().isEmpty) {
        return;
      }
      await ref.read(yxzApiClientProvider).postJson(
        '/api/v1/playback/quality-mismatch',
        body: <String, dynamic>{
          'videoId': id,
          'requestedQuality': state.quality.label,
          'selectedQuality': '${expectedHeight}p',
          'actualWidth': actualWidth,
          'actualHeight': actualHeight,
        },
      );
    } on Object catch (e) {
      AppLogger.w('quality-mismatch report failed: $e');
    }
  }

  /// True when the player leaves the endless buffer state with a real stream.
  Future<bool> _waitUntilPlaybackAlive({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final Player? player = _player;
    if (player == null) {
      return false;
    }
    final DateTime deadline = DateTime.now().add(timeout);
    Duration lastPos = player.state.position;
    while (DateTime.now().isBefore(deadline)) {
      final PlayerState s = player.state;
      final VideoParams video = s.videoParams;
      final bool hasFrame = (video.w ?? 0) > 0 && (video.h ?? 0) > 0;
      final bool advancing = s.position > lastPos;
      lastPos = s.position;
      if (s.playing && (hasFrame || advancing || s.duration.inMilliseconds > 0)) {
        if (!s.buffering || hasFrame || advancing) {
          return true;
        }
      }
      // Soft success: duration known and not stuck with zero size forever.
      if (s.duration.inMilliseconds > 0 && hasFrame) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final PlayerState end = player.state;
    final VideoParams video = end.videoParams;
    final bool hasFrame = (video.w ?? 0) > 0 && (video.h ?? 0) > 0;
    return end.playing && hasFrame;
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
    AppLogger.w('player error (GVS?): $message');
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
    // Invalidate + remint + fresh extract WITH PO — never reopen dead URLs.
    try {
      final YtdlpService ytdlp = ref.read(ytdlpServiceProvider);
      final PlaybackResolved fresh = await resolvePlaybackAfterGvsFailure(
        ytdlp: ytdlp,
        url: video.url,
        mintPoTokens: PlaybackPoTokenService.mint,
      );
      if (state.video?.id != video.id) {
        return;
      }
      _rememberSafeProgressive(fresh);
      state = state.copyWith(
        resolved: fresh,
        quality: PlaybackQuality.p360,
        loading: false,
        clearError: true,
      );
      final Duration keepAt = _player?.state.position ?? Duration.zero;
      await _openResolved(
        fresh,
        allowProgressiveFallback: true,
        preferProgressive: true,
      );
      if (keepAt.inMilliseconds > 500) {
        try {
          await _player?.seek(keepAt).timeout(const Duration(seconds: 3));
        } on TimeoutException {
          AppLogger.w('GVS recovery seek timed out');
        }
      }
    } on Object catch (error, stack) {
      AppLogger.e('GVS recovery failed', error, stack);
      await _startAt360(forceRefresh: true, preservePosition: true);
    }
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

class _OpenAttempt {
  const _OpenAttempt(
    this.kind,
    this.url, {
    required this.headers,
    this.audioUrl,
  });

  final String kind;
  final String url;
  final Map<String, String> headers;
  final String? audioUrl;
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
