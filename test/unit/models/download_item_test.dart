import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/models/download_item.dart';
import 'package:yt_downloader/data/models/video_format.dart';

void main() {
  const VideoFormat fmt = VideoFormat(
    formatId: '22',
    extension: 'mp4',
    displayLabel: '720p MP4',
  );

  DownloadItem make(DownloadStatus status) {
    return DownloadItem(
      id: 'id1',
      url: 'https://youtube.com',
      title: 'Test',
      selectedFormat: fmt,
      outputPath: '/Download',
      status: status,
      addedAt: DateTime(2024),
    );
  }

  group('DownloadItem', () {
    test(
      'isCancellable true when downloading',
      () => expect(make(DownloadStatus.downloading).isCancellable, true),
    );

    test(
      'isCancellable true when queued',
      () => expect(make(DownloadStatus.queued).isCancellable, true),
    );

    test(
      'isCancellable false when completed',
      () => expect(make(DownloadStatus.completed).isCancellable, false),
    );

    test(
      'isCancellable false when failed',
      () => expect(make(DownloadStatus.failed).isCancellable, false),
    );

    test(
      'isCancellable true when paused',
      () => expect(make(DownloadStatus.paused).isCancellable, true),
    );

    test(
      'isPausable true when downloading',
      () => expect(make(DownloadStatus.downloading).isPausable, true),
    );

    test(
      'isPausable true when queued',
      () => expect(make(DownloadStatus.queued).isPausable, true),
    );

    test(
      'isPausable false when paused, completed, or failed',
      () {
        expect(make(DownloadStatus.paused).isPausable, false);
        expect(make(DownloadStatus.completed).isPausable, false);
        expect(make(DownloadStatus.failed).isPausable, false);
      },
    );

    test(
      'isResumable true only when paused',
      () {
        expect(make(DownloadStatus.paused).isResumable, true);
        expect(make(DownloadStatus.downloading).isResumable, false);
        expect(make(DownloadStatus.queued).isResumable, false);
        expect(make(DownloadStatus.completed).isResumable, false);
        expect(make(DownloadStatus.failed).isResumable, false);
      },
    );

    test('statusLabel non-empty for all statuses', () {
      for (final DownloadStatus s in DownloadStatus.values) {
        expect(make(s).statusLabel, isNotEmpty);
      }
      expect(make(DownloadStatus.paused).statusLabel, 'Paused');
    });
  });
}
