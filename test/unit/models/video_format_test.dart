import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/constants/app_strings.dart';
import 'package:yt_downloader/data/models/video_format.dart';

void main() {
  group('VideoFormat', () {
    test('fromJson parses video format correctly', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'format_id': '137',
        'ext': 'mp4',
        'height': 1080,
        'fps': 30.0,
        'filesize': 134217728,
        'acodec': 'none',
        'vcodec': 'avc1.640028',
        'abr': null,
        'tbr': 4000.0,
      };

      final VideoFormat format = VideoFormat.fromJson(json);
      expect(format.formatId, '137');
      expect(format.extension, 'mp4');
      expect(format.resolution, '1080p');
      expect(format.isAudioOnly, false);
      expect(format.fileSize, 134217728);
    });

    test('isAudioOnly true when vcodec is none', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'height': null,
        'fps': null,
        'filesize': 4194304,
        'acodec': 'mp4a.40.2',
        'vcodec': 'none',
        'abr': 128.0,
        'tbr': 128.0,
      };

      final VideoFormat format = VideoFormat.fromJson(json);
      expect(format.isAudioOnly, true);
    });

    test('formattedFileSize returns MB string', () {
      const VideoFormat format = VideoFormat(
        formatId: '137',
        extension: 'mp4',
        displayLabel: 'test',
        fileSize: 134217728,
      );

      expect(format.formattedFileSize, contains(AppStrings.fileSizeUnitMb));
    });

    test('formattedFileSize handles null', () {
      const VideoFormat format = VideoFormat(
        formatId: '137',
        extension: 'mp4',
        displayLabel: 'test',
        fileSize: null,
      );

      expect(format.formattedFileSize.toLowerCase(), contains('unknown'));
    });

    test('copyWith creates correct copy', () {
      const VideoFormat original = VideoFormat(
        formatId: '137',
        extension: 'mp4',
        displayLabel: '1080p MP4',
        resolution: '1080p',
      );

      final VideoFormat copy = original.copyWith(resolution: '720p');
      expect(copy.resolution, '720p');
      expect(original.resolution, '1080p');
    });
  });
}
