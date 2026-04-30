library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_strings.dart';
import '../../core/utils/ytdlp_launch_command.dart';
import '../../core/utils/logger.dart';
import '../models/app_settings.dart';
import '../models/download_item.dart';
import '../models/download_progress.dart';
import '../models/playlist_info.dart';
import '../models/video_format.dart';
import '../providers/binary_path_provider.dart';
import '../providers/settings_providers.dart';
import '../providers/ytdlp_providers.dart';
import 'ytdlp_platform_channel.dart';

/// Manages queued downloads, concurrent yt-dlp processes, and progress.
class DownloadManager extends Notifier<List<DownloadItem>> {
  static const int _defaultMaxConcurrentDownloads = 3;
  static const String _playedKey = 'played_items';
  static const String _queueKey = 'download_queue_v1';

  static final RegExp _progressLine = RegExp(
    r'\[download\]\s+([\d.]+)%\s+of\s+([\d.]+\S+)\s+at\s+([\d.]+\S+)\s+ETA\s+(\S+)',
  );

  final List<DownloadItem> _queue = <DownloadItem>[];
  final Map<String, Process> _activeProcesses = <String, Process>{};
  final Set<String> _activeAndroidProcessIds = <String>{};
  final Map<String, bool> _reachedFullDownload = <String, bool>{};
  int _maxConcurrentDownloads = _defaultMaxConcurrentDownloads;

  /// Serializes slot checks and [Process.start] to avoid over-spawning.
  Future<void> _spawnGate = Future<void>.value();

  StreamController<DownloadItem>? _completionController;
  StreamSubscription<Map<dynamic, dynamic>>? _androidProgressSub;
  bool _progressListenerInitialized = false;

  DateTime _lastProgressUpdate = DateTime.now();
  static const Duration _progressThrottle = Duration(milliseconds: 250);

  void _throttledEmit() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastProgressUpdate) > _progressThrottle) {
      _lastProgressUpdate = now;
      state = List<DownloadItem>.unmodifiable(_queue);
    }
  }

  /// Emits each [DownloadItem] when its status becomes [DownloadStatus.completed].
  Stream<DownloadItem> get completionStream {
    _completionController ??= StreamController<DownloadItem>.broadcast();
    return _completionController!.stream;
  }

  @override
  List<DownloadItem> build() {
    unawaited(_loadQueueState());
    unawaited(_loadPlayedState());
    ref.onDispose(() {
      _disposeProcesses();
      _androidProgressSub?.cancel();
      _androidProgressSub = null;
      _completionController?.close();
      _completionController = null;
    });
    if (Platform.isAndroid) {
      _initProgressListener();
    }
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final AppSettings? settings = next.valueOrNull;
      if (settings == null) {
        return;
      }
      _maxConcurrentDownloads = settings.maxConcurrentDownloads;
      _emit();
      _startNextQueued();
    });
    return <DownloadItem>[];
  }

  /// Immutable view of all jobs in FIFO order.
  List<DownloadItem> get queue => List<DownloadItem>.unmodifiable(_queue);

  /// Jobs currently receiving bytes.
  List<DownloadItem> get activeDownloads => _queue
      .where((DownloadItem i) => i.status == DownloadStatus.downloading)
      .toList(growable: false);

  /// Finished jobs.
  List<DownloadItem> get completedDownloads => _queue
      .where((DownloadItem i) => i.status == DownloadStatus.completed)
      .toList(growable: false);

  /// Jobs that stopped with an error or cancellation.
  List<DownloadItem> get failedDownloads => _queue
      .where((DownloadItem i) => i.status == DownloadStatus.failed)
      .toList(growable: false);

  /// Jobs waiting for a free slot.
  List<DownloadItem> get queuedDownloads => _queue
      .where((DownloadItem i) => i.status == DownloadStatus.queued)
      .toList(growable: false);

  /// Whether any transfer is actively running.
  bool get hasActiveDownloads =>
      _activeProcesses.isNotEmpty || _activeAndroidProcessIds.isNotEmpty;

  /// Adds a single video download to the queue and starts it when possible.
  ///
  /// Returns the new [DownloadItem.id].
  Future<String> addDownload({
    required String url,
    required VideoFormat format,
    required String outputPath,
    String? title,
    String? thumbnailUrl,
  }) async {
    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    final DownloadItem item = DownloadItem(
      id: id,
      url: url,
      title: title ?? url,
      selectedFormat: format,
      outputPath: outputPath,
      status: DownloadStatus.queued,
      addedAt: DateTime.now(),
      thumbnailUrl: thumbnailUrl,
    );
    _queue.add(item);
    _emit();
    _startNextQueued();
    return id;
  }

  /// Enqueues one job per [entries] row sharing the same [format].
  ///
  /// [playlistUrl] and [totalCount] mirror playlist metadata for callers;
  /// actual URLs come from [entries]. Starts up to [_maxConcurrentDownloads]
  /// workers immediately.
  Future<void> addPlaylistDownload({
    required String playlistUrl,
    required VideoFormat format,
    required String outputPath,
    required int totalCount,
    required List<PlaylistEntry> entries,
  }) async {
    if (entries.isEmpty) {
      AppLogger.w(
        'addPlaylistDownload: empty entries for playlistUrl=$playlistUrl',
      );
      return;
    }
    final int base = DateTime.now().microsecondsSinceEpoch;
    final String playlistGroupId = base.toString();
    final int total = totalCount > 0 ? totalCount : entries.length;
    for (int i = 0; i < entries.length; i++) {
      final PlaylistEntry e = entries[i];
      final DownloadItem item = DownloadItem(
        id: '${base}_$i',
        url: e.url,
        title: e.title.isNotEmpty ? e.title : e.url,
        selectedFormat: format,
        outputPath: outputPath,
        status: DownloadStatus.queued,
        addedAt: DateTime.now(),
        isPlaylist: true,
        playlistIndex: i + 1,
        playlistTotal: total,
        playlistGroupId: playlistGroupId,
        playlistTitle: playlistUrl,
      );
      _queue.add(item);
    }
    _emit();
    _startNextQueued();
  }

  Future<T> _serializedSpawn<T>(Future<T> Function() action) async {
    final Completer<void> gate = Completer<void>();
    final Future<void> previous = _spawnGate;
    _spawnGate = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  /// Drains streams and finalizes status after [process] was registered.
  Future<void> _finishDownloadProcess(
    DownloadItem item,
    Process process,
  ) async {
    final StringBuffer stderrBuf = StringBuffer();

    Future<void> drainStdout() async {
      try {
        await for (final String line
            in process.stdout
                .transform(systemEncoding.decoder)
                .transform(const LineSplitter())) {
          _parseProgressLine(item.id, line);
        }
      } on Object catch (error, stackTrace) {
        AppLogger.w('stdout drain ${item.id}: $error\n$stackTrace');
      }
    }

    Future<void> drainStderr() async {
      try {
        await for (final String line
            in process.stderr
                .transform(systemEncoding.decoder)
                .transform(const LineSplitter())) {
          stderrBuf.writeln(line);
        }
      } on Object catch (error, stackTrace) {
        AppLogger.w('stderr drain ${item.id}: $error\n$stackTrace');
      }
    }

    await Future.wait<void>(<Future<void>>[drainStdout(), drainStderr()]);

    final int code = await process.exitCode;
    _activeProcesses.remove(item.id);

    final DownloadItem? again = _findItem(item.id);
    if (again == null) {
      _emit();
      _startNextQueued();
      return;
    }

    if (again.status == DownloadStatus.failed &&
        again.errorMessage == AppStrings.errorDownloadCancelled) {
      _emit();
      _startNextQueued();
      return;
    }

    if (code == 0) {
      again.status = DownloadStatus.completed;
      again.progress = DownloadProgress(
        percent: 1,
        speed: again.progress?.speed ?? '--',
        eta: '00:00',
        totalSize: again.progress?.totalSize ?? '--',
        downloadedSize: again.progress?.downloadedSize,
        isMerging: false,
      );
      AppLogger.i('Download completed: ${again.title}');
      _completionController?.add(again);
      unawaited(_savePlayedState());
    } else {
      again.status = DownloadStatus.failed;
      again.errorMessage = stderrBuf.isNotEmpty
          ? stderrBuf.toString().trim()
          : AppStrings.errorProcessFailed;
      AppLogger.e('Download failed: ${again.title} (exit $code)');
    }
    _emit();
    _startNextQueued();
  }

  /// Reserves a slot and spawns yt-dlp, or returns `null` if not started.
  ///
  /// Call only while holding [_serializedSpawn] from [_pumpQueueBody].
  Future<Process?> _beginSpawn(DownloadItem item) async {
    if (_activeProcesses.containsKey(item.id) ||
        _activeAndroidProcessIds.contains(item.id)) {
      return null;
    }
    if (item.status != DownloadStatus.queued) {
      return null;
    }
    if (_activeCount >= _maxConcurrentDownloads) {
      return null;
    }

    final String binaryPath = await ref.read(binaryPathProvider.future);
    final String outTemplate = p.join(item.outputPath, '%(title)s.%(ext)s');
    final AppSettings settings = ref.read(settingsProvider).requireValue;
    final List<String> args = ref
        .read(ytdlpServiceProvider)
        .buildDownloadArgs(
          url: item.url,
          formatId: item.selectedFormat.formatId,
          outputTemplate: outTemplate,
          settings: settings,
        );

    if (Platform.isAndroid) {
      AppLogger.i(
        'Starting Android download: '
        'id=${item.id} format=${item.selectedFormat.formatId} '
        'url=${item.url} output=${item.outputPath}',
      );
      _initProgressListener();
      try {
        final String processId = await YtdlpPlatformChannel.startDownload(
          url: item.url,
          formatId: item.selectedFormat.formatId,
          outputPath: item.outputPath,
          processId: item.id,
          isPlaylist: item.isPlaylist,
          embedThumbnail: settings.embedThumbnail,
          addMetadata: settings.addMetadata,
          downloadSubtitles: settings.downloadSubtitles,
          subtitleLanguage: settings.subtitleLanguage,
          skipExisting: settings.skipExistingFiles,
          rateLimit:
              settings.limitDownloadSpeed && settings.maxDownloadSpeedKbps > 0
              ? '${settings.maxDownloadSpeedKbps}K'
              : '',
        );
        _activeAndroidProcessIds.add(processId);
        AppLogger.i('Platform channel download started: $processId');
        item.status = DownloadStatus.downloading;
        item.progress = DownloadProgress.zero;
        _emit();
      } on Object catch (error, stackTrace) {
        AppLogger.e(
          'Failed to start download via platform channel',
          error,
          stackTrace,
        );
        item.status = DownloadStatus.failed;
        item.errorMessage = error.toString();
        _emit();
      }
      return null;
    }

    try {
      final YtdlpLaunchCommand cmd = YtdlpLaunchCommand.from(binaryPath, args);
      final Process process = await Process.start(
        cmd.executable,
        cmd.arguments,
        environment: const <String, String>{'PYTHONIOENCODING': 'utf-8'},
        mode: ProcessStartMode.normal,
      );
      _activeProcesses[item.id] = process;
      item.status = DownloadStatus.downloading;
      item.progress = DownloadProgress.zero;
      _emit();
      return process;
    } on Object catch (error, stackTrace) {
      AppLogger.e('Process.start failed for ${item.id}', error, stackTrace);
      item.status = DownloadStatus.failed;
      item.errorMessage = AppStrings.errorProcessFailed;
      _emit();
      return null;
    }
  }

  /// Parses one yt-dlp stdout line and updates live progress.
  void _parseProgressLine(String itemId, String line) {
    final DownloadItem? item = _findItem(itemId);
    if (item == null || item.status != DownloadStatus.downloading) {
      return;
    }

    if (line.contains('[Merger]')) {
      item.progress = DownloadProgress(
        percent: item.progress?.percent.clamp(0, 1) ?? 1,
        speed: AppStrings.statusFinalizing,
        eta: item.progress?.eta ?? '--',
        totalSize: item.progress?.totalSize ?? '--',
        downloadedSize: item.progress?.downloadedSize,
        isMerging: true,
      );
      _throttledEmit();
      return;
    }

    final RegExpMatch? m = _progressLine.firstMatch(line);
    if (m == null) {
      return;
    }
    final double raw = double.tryParse(m.group(1) ?? '0') ?? 0;
    final double pct = (raw / 100).clamp(0, 1);
    item.progress = DownloadProgress(
      percent: pct,
      speed: m.group(3) ?? '--',
      eta: m.group(4) ?? '--',
      totalSize: m.group(2) ?? '--',
      isMerging: false,
    );
    _throttledEmit();
  }

  /// Kills the yt-dlp process for [itemId] and marks the job failed.
  Future<void> cancelDownload(String itemId) async {
    if (Platform.isAndroid && _activeAndroidProcessIds.contains(itemId)) {
      try {
        await YtdlpPlatformChannel.cancelDownload(itemId);
      } on Object catch (error, stackTrace) {
        AppLogger.w('android cancel failed $itemId: $error\n$stackTrace');
      }
      _activeAndroidProcessIds.remove(itemId);
    }
    final Process? proc = _activeProcesses[itemId];
    final DownloadItem? item = _findItem(itemId);
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigkill);
      } on Object catch (error, stackTrace) {
        AppLogger.w('kill failed $itemId: $error\n$stackTrace');
      }
      _activeProcesses.remove(itemId);
    }
    if (item != null) {
      item.status = DownloadStatus.failed;
      item.errorMessage = AppStrings.errorDownloadCancelled;
      _emit();
      if (item.outputPath.isNotEmpty) {
        await _deletePartialFiles(item.outputPath, item.title);
      }
    }
    _startNextQueued();
  }

  /// Re-queues a failed job and attempts download again.
  Future<void> retryDownload(String itemId) async {
    final DownloadItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    item.status = DownloadStatus.queued;
    item.progress = null;
    item.errorMessage = null;
    _emit();
    _startNextQueued();
  }

  /// Removes a finished or failed job; cancels first if still active.
  Future<void> removeDownload(String itemId) async {
    if (_activeProcesses.containsKey(itemId)) {
      await cancelDownload(itemId);
    }
    _queue.removeWhere((DownloadItem e) => e.id == itemId);
    _emit();
  }

  /// Drops all completed jobs from the queue.
  void clearCompleted() {
    _queue.removeWhere(
      (DownloadItem e) => e.status == DownloadStatus.completed,
    );
    _emit();
    unawaited(_savePlayedState());
  }

  /// Fills free concurrency slots with the next queued jobs.
  void _startNextQueued() {
    unawaited(_pumpQueue());
  }

  /// Starts queued jobs until the concurrency cap is reached.
  Future<void> _pumpQueue() async {
    await _serializedSpawn(() async {
      while (true) {
        if (_activeCount >= _maxConcurrentDownloads) {
          break;
        }
        final DownloadItem? next = _firstSpawnableQueued();
        if (next == null) {
          break;
        }
        final Process? process = await _beginSpawn(next);
        if (process == null) {
          if (Platform.isAndroid &&
              _activeAndroidProcessIds.contains(next.id)) {
            continue;
          }
          continue;
        }
        unawaited(_finishDownloadProcess(next, process));
      }
    });
  }

  DownloadItem? _firstSpawnableQueued() {
    final String? activePlaylistGroupId = _activePlaylistGroupId();
    if (activePlaylistGroupId != null) {
      for (final DownloadItem e in _queue) {
        if (e.status != DownloadStatus.queued) {
          continue;
        }
        if (e.isPlaylist && e.playlistGroupId == activePlaylistGroupId) {
          return e;
        }
      }
      return null;
    }

    DownloadItem? firstPlaylistQueued;
    for (final DownloadItem e in _queue) {
      if (e.status == DownloadStatus.queued && e.isPlaylist) {
        firstPlaylistQueued = e;
        break;
      }
    }
    if (firstPlaylistQueued != null) {
      if (_activeCount > 0) {
        return null;
      }
      return firstPlaylistQueued;
    }

    for (final DownloadItem e in _queue) {
      if (e.status == DownloadStatus.queued) {
        return e;
      }
    }
    return null;
  }

  String? _activePlaylistGroupId() {
    for (final DownloadItem item in _queue) {
      if (item.status == DownloadStatus.downloading && item.isPlaylist) {
        return item.playlistGroupId;
      }
    }
    return null;
  }

  DownloadItem? _findItem(String id) {
    try {
      return _queue.firstWhere((DownloadItem e) => e.id == id);
    } on StateError {
      return null;
    }
  }

  Future<void> _deletePartialFiles(String outputPath, String title) async {
    try {
      final Directory dir = Directory(outputPath);
      if (!await dir.exists()) {
        return;
      }
      final String slug = _slugPrefix(title);
      await for (final FileSystemEntity e in dir.list()) {
        if (e is! File) {
          continue;
        }
        final String name = p.basename(e.path);
        final bool partial =
            name.endsWith('.part') ||
            name.endsWith('.ytdl') ||
            name.contains('.part.');
        if (!partial) {
          continue;
        }
        if (slug.isEmpty || name.contains(slug)) {
          await e.delete();
          AppLogger.d('Deleted partial file ${e.path}');
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.w('partial cleanup: $error\n$stackTrace');
    }
  }

  String _slugPrefix(String title) {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final int n = trimmed.length > 24 ? 24 : trimmed.length;
    return trimmed
        .substring(0, n)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  /// Updates the concurrency cap and starts waiting jobs if possible.
  void setMaxConcurrentDownloads(int value) {
    final int safe = value.clamp(1, 5);
    if (_maxConcurrentDownloads == safe) {
      return;
    }
    _maxConcurrentDownloads = safe;
    _emit();
    _startNextQueued();
  }

  void _emit() {
    state = List<DownloadItem>.unmodifiable(_queue);
    unawaited(_saveQueueState());
  }

  /// Marks a completed item as opened by the user.
  void markAsPlayed(String itemId) {
    final DownloadItem? item = _findItem(itemId);
    if (item == null) {
      return;
    }
    item.isPlayed = true;
    _emit();
    unawaited(_savePlayedState());
  }

  void _disposeProcesses() {
    for (final Process proc in _activeProcesses.values) {
      try {
        proc.kill(ProcessSignal.sigkill);
      } on Object catch (_) {}
    }
    _activeProcesses.clear();
    _activeAndroidProcessIds.clear();
    _reachedFullDownload.clear();
    _progressListenerInitialized = false;
  }

  int get _activeCount =>
      _activeProcesses.length + _activeAndroidProcessIds.length;

  void _handleAndroidProgress(Map<dynamic, dynamic> event) {
    final String processId = (event['processId'] ?? '').toString();
    if (processId.isEmpty) {
      return;
    }
    final DownloadItem? item = _findItem(processId);
    if (item == null) {
      AppLogger.w('Progress event for unknown processId: $processId');
      return;
    }

    final String? status = event['status']?.toString();
    if (status == 'completed') {
      _activeAndroidProcessIds.remove(processId);
      _reachedFullDownload.remove(processId);
      item.status = DownloadStatus.completed;
      item.progress = DownloadProgress(
        percent: 1,
        speed: item.progress?.speed ?? '--',
        eta: '00:00',
        totalSize: item.progress?.totalSize ?? '--',
        downloadedSize: item.progress?.downloadedSize,
        isMerging: false,
      );
      AppLogger.i('Download completed: ${item.title}');
      _completionController?.add(item);
      unawaited(_savePlayedState());
      _emit();
      _startNextQueued();
      return;
    }

    if (status == 'failed') {
      _activeAndroidProcessIds.remove(processId);
      final String errorMsg =
          event['error']?.toString() ?? AppStrings.errorProcessFailed;
      final bool alreadyComplete = _reachedFullDownload[processId] ?? false;
      final bool isPostProcessingBug =
          errorMsg.contains('NoneType') ||
          errorMsg.contains('has no attribute') ||
          errorMsg.contains('AtomicParsley') ||
          errorMsg.contains('mutagen');

      if (alreadyComplete && isPostProcessingBug) {
        AppLogger.w('Post-processing failed but file is complete: $errorMsg');
        item.status = DownloadStatus.completed;
        item.progress = const DownloadProgress(
          percent: 1.0,
          speed: '--',
          eta: '0:00',
          totalSize: '--',
        );
        _completionController?.add(item);
      } else {
        item.status = DownloadStatus.failed;
        item.errorMessage = errorMsg;
        AppLogger.e('Download failed: ${item.title} — $errorMsg');
      }
      _reachedFullDownload.remove(processId);
      _emit();
      _startNextQueued();
      return;
    }

    if (item.status != DownloadStatus.downloading) {
      return;
    }

    final double rawPercent = (event['percent'] as num?)?.toDouble() ?? -1.0;
    final String eta = event['eta']?.toString() ?? '--';
    final String line = event['line']?.toString() ?? '';
    final bool isPostProcessing =
        line.contains('[Metadata]') ||
        line.contains('[EmbedThumbnail]') ||
        line.contains('[FFmpegMetadata]') ||
        line.contains('[AtomicParsley]') ||
        line.contains('Adding metadata') ||
        line.contains('Embedding thumbnail');

    if (line.contains('has already been downloaded') || line.contains('100%')) {
      _reachedFullDownload[processId] = true;
    }

    if (isPostProcessing) {
      item.progress = DownloadProgress(
        percent: 0.99,
        speed: 'Processing...',
        eta: '--',
        totalSize: item.progress?.totalSize ?? '--',
        downloadedSize: item.progress?.downloadedSize,
        isMerging: true,
      );
      item.status = DownloadStatus.downloading;
      _throttledEmit();
      return;
    }

    if (rawPercent >= 0.0) {
      final double normalized = rawPercent > 1
          ? (rawPercent / 100.0).clamp(0.0, 1.0)
          : rawPercent.clamp(0.0, 1.0);
      item.progress = DownloadProgress(
        percent: normalized,
        speed: _extractSpeed(line),
        eta: eta,
        totalSize: _extractTotalSize(line),
        downloadedSize: item.progress?.downloadedSize,
        isMerging: false,
      );
      final String titlePreview = item.title.substring(
        0,
        min(30, item.title.length),
      );
      AppLogger.d('⬇ ${rawPercent.toStringAsFixed(1)}% — $titlePreview...');
    } else {
      item.progress = DownloadProgress(
        percent: item.progress?.percent ?? 0.0,
        speed: 'Preparing...',
        eta: '--',
        totalSize: item.progress?.totalSize ?? '--',
        downloadedSize: item.progress?.downloadedSize,
        isMerging: false,
      );
    }
    item.status = DownloadStatus.downloading;
    _throttledEmit();
  }

  void _initProgressListener() {
    if (_progressListenerInitialized) {
      return;
    }
    _progressListenerInitialized = true;
    _androidProgressSub = YtdlpPlatformChannel.progressStream.listen(
      _handleAndroidProgress,
      onError: (Object e, StackTrace st) {
        AppLogger.e('Progress stream error', e, st);
      },
      onDone: () {
        AppLogger.w('Progress stream closed');
      },
    );
  }

  String _extractSpeed(String line) {
    final RegExpMatch? match = RegExp(r'at\s+([\d.]+\S+/s)').firstMatch(line);
    return match?.group(1) ?? '--';
  }

  String _extractTotalSize(String line) {
    final RegExpMatch? match = RegExp(r'of\s+([\d.]+\s*\S+)').firstMatch(line);
    return match?.group(1) ?? '--';
  }

  Future<void> _savePlayedState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> played = _queue
        .where((DownloadItem item) => item.isPlayed)
        .map((DownloadItem item) => item.id)
        .toList(growable: false);
    await prefs.setStringList(_playedKey, played);
  }

  Future<void> _loadPlayedState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Set<String> played =
        prefs.getStringList(_playedKey)?.toSet() ?? <String>{};
    if (played.isEmpty) {
      return;
    }
    bool changed = false;
    for (final DownloadItem item in _queue) {
      if (played.contains(item.id)) {
        item.isPlayed = true;
        changed = true;
      }
    }
    if (changed) {
      _emit();
    }
  }

  Future<void> _saveQueueState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> data = _queue
        .map((DownloadItem item) => <String, dynamic>{
              'id': item.id,
              'url': item.url,
              'title': item.title,
              'formatId': item.selectedFormat.formatId,
              'formatExt': item.selectedFormat.extension,
              'formatLabel': item.selectedFormat.displayLabel,
              'outputPath': item.outputPath,
              'status': item.status.name,
              'errorMessage': item.errorMessage,
              'isPlaylist': item.isPlaylist,
              'playlistIndex': item.playlistIndex,
              'playlistTotal': item.playlistTotal,
              'thumbnailUrl': item.thumbnailUrl,
              'playlistGroupId': item.playlistGroupId,
              'playlistTitle': item.playlistTitle,
              'isPlayed': item.isPlayed,
              'addedAtMs': item.addedAt.millisecondsSinceEpoch,
            })
        .toList(growable: false);
    await prefs.setString(_queueKey, jsonEncode(data));
  }

  Future<void> _loadQueueState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return;
      }
      _queue.clear();
      for (final dynamic entry in decoded) {
        if (entry is! Map<dynamic, dynamic>) {
          continue;
        }
        final Map<dynamic, dynamic> map = entry;
        final DownloadStatus parsedStatus = _parseStatus(
          map['status']?.toString() ?? DownloadStatus.queued.name,
        );
        final DownloadStatus status = parsedStatus == DownloadStatus.downloading
            ? DownloadStatus.failed
            : parsedStatus;
        final String? resumedError = parsedStatus == DownloadStatus.downloading
            ? 'Interrupted. Please retry.'
            : map['errorMessage']?.toString();

        final DownloadItem item = DownloadItem(
          id: map['id']?.toString() ?? '',
          url: map['url']?.toString() ?? '',
          title: map['title']?.toString() ?? '',
          selectedFormat: VideoFormat(
            formatId: map['formatId']?.toString() ?? '',
            extension: map['formatExt']?.toString() ?? '',
            displayLabel: map['formatLabel']?.toString() ?? '',
          ),
          outputPath: map['outputPath']?.toString() ?? '',
          status: status,
          addedAt: DateTime.fromMillisecondsSinceEpoch(
            (map['addedAtMs'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ),
          errorMessage: resumedError,
          isPlaylist: (map['isPlaylist'] as bool?) ?? false,
          playlistIndex: (map['playlistIndex'] as num?)?.toInt(),
          playlistTotal: (map['playlistTotal'] as num?)?.toInt(),
          thumbnailUrl: map['thumbnailUrl']?.toString(),
          playlistGroupId: map['playlistGroupId']?.toString(),
          playlistTitle: map['playlistTitle']?.toString(),
          isPlayed: (map['isPlayed'] as bool?) ?? false,
        );
        _queue.add(item);
      }
      _emit();
    } on Object catch (error, stackTrace) {
      AppLogger.w('Failed to restore queue state: $error\n$stackTrace');
    }
  }

  DownloadStatus _parseStatus(String value) {
    for (final DownloadStatus status in DownloadStatus.values) {
      if (status.name == value) {
        return status;
      }
    }
    return DownloadStatus.queued;
  }
}
