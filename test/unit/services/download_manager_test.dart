import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/data/models/app_settings.dart';
import 'package:yt_downloader/data/models/download_item.dart';
import 'package:yt_downloader/data/models/video_format.dart';
import 'package:yt_downloader/data/providers/download_providers.dart';
import 'package:yt_downloader/data/providers/settings_providers.dart';
import 'package:yt_downloader/data/services/download_manager.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async {
    return AppSettings.defaults.copyWith(maxConcurrentDownloads: 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const VideoFormat testFormat = VideoFormat(
    formatId: '22',
    extension: 'mp4',
    displayLabel: '720p MP4',
  );

  late ProviderContainer container;
  late DownloadManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWith(FakeSettingsNotifier.new),
      ],
    );
    manager = container.read(downloadManagerProvider.notifier);
  });

  tearDown(() {
    container.dispose();
  });

  group('DownloadManager pause and resume controls', () {
    test('pauseDownload sets queued item to paused and resumes back to queued', () async {
      final String id = await manager.addDownload(
        url: 'https://youtube.com/watch?v=abc',
        title: 'Test Video',
        format: testFormat,
        outputPath: '/tmp',
      );

      final DownloadItem? item = manager.findItem(id);
      expect(item, isNotNull);
      expect(item!.status, DownloadStatus.queued);
      expect(item.isPausable, true);

      await manager.pauseDownload(id);
      expect(item.status, DownloadStatus.paused);
      expect(manager.pausedDownloads.map((DownloadItem i) => i.id), contains(id));
      expect(item.isResumable, true);

      await manager.resumeDownload(id);
      expect(item.status, DownloadStatus.queued);
      expect(manager.pausedDownloads, isEmpty);
    });

    test('pauseAll and resumeAll batch controls', () async {
      final String id1 = await manager.addDownload(
        url: 'https://youtube.com/watch?v=1',
        title: 'Video 1',
        format: testFormat,
        outputPath: '/tmp',
      );
      final String id2 = await manager.addDownload(
        url: 'https://youtube.com/watch?v=2',
        title: 'Video 2',
        format: testFormat,
        outputPath: '/tmp',
      );

      await manager.pauseAll();
      expect(manager.pausedDownloads.length, 2);

      await manager.resumeAll();
      expect(manager.pausedDownloads.length, 0);
      expect(manager.findItem(id1)?.status, DownloadStatus.queued);
      expect(manager.findItem(id2)?.status, DownloadStatus.queued);
    });

    test('clearCompleted removes completed items from queue', () async {
      final String id = await manager.addDownload(
        url: 'https://youtube.com/watch?v=done',
        title: 'Done Video',
        format: testFormat,
        outputPath: '/tmp',
      );
      final DownloadItem? item = manager.findItem(id);
      item!.status = DownloadStatus.completed;

      expect(manager.completedDownloads.length, 1);
      manager.clearCompleted();
      expect(manager.completedDownloads, isEmpty);
      expect(manager.findItem(id), isNull);
    });

    test('deleteDownloadedFile removes item and deletes physical file', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp('yt_test');
      final File testFile = File('${tempDir.path}/test_delete_video.mp4');
      await testFile.writeAsString('test content');
      expect(await testFile.exists(), true);

      final String id = await manager.addDownload(
        url: 'https://youtube.com/watch?v=delete',
        title: 'test_delete_video',
        format: testFormat,
        outputPath: tempDir.path,
      );
      final DownloadItem? item = manager.findItem(id);
      item!.status = DownloadStatus.completed;

      final bool deleted = await manager.deleteDownloadedFile(id);
      expect(deleted, true);
      expect(manager.findItem(id), isNull);
      expect(await testFile.exists(), false);

      await tempDir.delete(recursive: true);
    });
  });
}
