import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/models/download_progress.dart';

void main() {
  group('DownloadProgress', () {
    test('percentLabel formats correctly', () {
      const DownloadProgress p = DownloadProgress(
        percent: 0.453,
        speed: '2.3MiB/s',
        eta: '00:32',
        totalSize: '128MiB',
      );

      expect(p.percentLabel, '45.3%');
    });

    test('zero is all empty state', () {
      final DownloadProgress z = DownloadProgress.zero;
      expect(z.percent, 0.0);
      expect(z.speed, '--');
    });

    test('isMerging defaults false', () {
      const DownloadProgress p = DownloadProgress(
        percent: 1.0,
        speed: '--',
        eta: '00:00',
        totalSize: '100MiB',
      );

      expect(p.isMerging, false);
    });
  });
}
