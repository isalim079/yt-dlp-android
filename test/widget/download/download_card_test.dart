import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/models/download_item.dart';
import 'package:yt_downloader/data/models/download_progress.dart';
import 'package:yt_downloader/data/models/video_format.dart';
import 'package:yt_downloader/data/services/download_manager.dart';
import 'package:yt_downloader/presentation/widgets/download/download_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  const VideoFormat fmt = VideoFormat(
    formatId: '22',
    extension: 'mp4',
    displayLabel: '720p MP4',
  );

  DownloadItem makeItem(DownloadStatus status) {
    return DownloadItem(
      id: 'id1',
      url: 'https://youtube.com',
      title: 'Test Video Title',
      selectedFormat: fmt,
      outputPath: '/Download',
      status: status,
      addedAt: DateTime(2024),
    );
  }

  group('DownloadCard', () {
    testWidgets('shows title', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(
            item: makeItem(DownloadStatus.queued),
            manager: DownloadManager(),
          ),
        ),
      );
      expect(find.text('Test Video Title'), findsOneWidget);
    });

    testWidgets('shows progress bar when downloading', (WidgetTester t) async {
      final DownloadItem item = makeItem(DownloadStatus.downloading)
        ..progress = const DownloadProgress(
          percent: 0.45,
          speed: '2MiB/s',
          eta: '00:30',
          totalSize: '128MiB',
        );
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(item: item, manager: DownloadManager()),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows cancel button when downloading', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(
            item: makeItem(DownloadStatus.downloading),
            manager: DownloadManager(),
          ),
        ),
      );
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows retry button when failed', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(
            item: makeItem(DownloadStatus.failed),
            manager: DownloadManager(),
          ),
        ),
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows remove button when completed', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(
            item: makeItem(DownloadStatus.completed),
            manager: DownloadManager(),
          ),
        ),
      );
      expect(find.text('Remove'), findsOneWidget);
    });

    testWidgets('does not overflow on narrow screen', (WidgetTester t) async {
      t.view.physicalSize = const Size(320 * 3, 568 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          DownloadCard(
            item: makeItem(DownloadStatus.downloading),
            manager: DownloadManager(),
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
