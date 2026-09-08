import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/data/models/app_download_record.dart';
import 'package:yt_downloader/data/models/download_item.dart';
import 'package:yt_downloader/data/models/video_format.dart';
import 'package:yt_downloader/data/services/app_download_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppDownloadRegistry registry;
  late Directory tempDir;

  const VideoFormat testFormat = VideoFormat(
    formatId: '22',
    extension: 'mp4',
    displayLabel: '720p MP4',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('app_reg_test');
    container = ProviderContainer();
    registry = container.read(appDownloadRegistryProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppDownloadRegistry', () {
    test('registers completed download and saves file metadata', () async {
      final File file = File('${tempDir.path}/sample_video.mp4');
      await file.writeAsString('video data');

      final DownloadItem item = DownloadItem(
        id: 'item_101',
        url: 'https://youtube.com/watch?v=sample',
        title: 'sample_video',
        selectedFormat: testFormat,
        outputPath: tempDir.path,
        status: DownloadStatus.completed,
        addedAt: DateTime.now(),
      );

      await registry.registerCompleted(item, resolvedFilePath: file.path);

      final List<AppDownloadRecord> records =
          container.read(appDownloadRegistryProvider);
      expect(records.length, 1);
      expect(records.first.id, 'item_101');
      expect(records.first.title, 'sample_video');
      expect(records.first.filePath, file.path);
      expect(records.first.isAppDownload, true);
      expect(records.first.fileSizeBytes, greaterThan(0));
    });

    test('deleteRecord deletes file from disk and updates state', () async {
      final File file = File('${tempDir.path}/to_delete.mp4');
      await file.writeAsString('delete me');
      expect(await file.exists(), true);

      final DownloadItem item = DownloadItem(
        id: 'item_to_delete',
        url: 'https://youtube.com/watch?v=del',
        title: 'to_delete',
        selectedFormat: testFormat,
        outputPath: tempDir.path,
        status: DownloadStatus.completed,
        addedAt: DateTime.now(),
      );

      await registry.registerCompleted(item, resolvedFilePath: file.path);
      expect(container.read(appDownloadRegistryProvider).length, 1);

      final bool deleted =
          await registry.deleteRecord('item_to_delete', deleteFileFromDisk: true);
      expect(deleted, true);
      expect(await file.exists(), false);
      expect(container.read(appDownloadRegistryProvider), isEmpty);
    });
  });
}
