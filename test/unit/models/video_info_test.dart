import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/constants/app_strings.dart';
import 'package:yt_downloader/data/models/video_info.dart';

void main() {
  group('VideoInfo', () {
    test('formattedDuration MM:SS', () {
      const VideoInfo info = VideoInfo(title: 'T', url: 'u', duration: 183);
      expect(info.formattedDuration, '03:03');
    });

    test('formattedDuration HH:MM:SS', () {
      const VideoInfo info = VideoInfo(title: 'T', url: 'u', duration: 3723);
      expect(info.formattedDuration, '01:02:03');
    });

    test('formattedDuration null returns not available marker', () {
      const VideoInfo info = VideoInfo(title: 'T', url: 'u', duration: null);
      expect(info.formattedDuration, AppStrings.notAvailable);
    });

    test('formattedViewCount millions', () {
      const VideoInfo info = VideoInfo(
        title: 'T',
        url: 'u',
        viewCount: 1500000,
      );
      expect(info.formattedViewCount, contains('1.5M'));
    });

    test('formattedViewCount thousands', () {
      const VideoInfo info = VideoInfo(title: 'T', url: 'u', viewCount: 45000);
      expect(info.formattedViewCount, contains('45.0K'));
    });

    test('formattedUploadDate parses YYYYMMDD', () {
      const VideoInfo info = VideoInfo(
        title: 'T',
        url: 'u',
        uploadDate: '20240115',
      );
      expect(info.formattedUploadDate, '2024-01-15');
    });

    test('formattedUploadDate null returns not available marker', () {
      const VideoInfo info = VideoInfo(title: 'T', url: 'u', uploadDate: null);
      expect(info.formattedUploadDate, AppStrings.notAvailable);
    });
  });
}
