import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/core/exceptions/ytdlp_exception.dart';
import 'package:yt_downloader/data/services/format_parser.dart';

void main() {
  final String sampleJson = jsonEncode(<String, dynamic>{
    'title': 'Test Video',
    'thumbnail': 'https://example.com/thumb.jpg',
    'duration': 183,
    'uploader': 'Test Channel',
    'upload_date': '20240115',
    'view_count': 1500000,
    'webpage_url': 'https://youtube.com/watch?v=test',
    'formats': <Map<String, dynamic>>[
      <String, dynamic>{
        'format_id': '137',
        'ext': 'mp4',
        'height': 1080,
        'fps': 30.0,
        'filesize': 134217728,
        'acodec': 'none',
        'vcodec': 'avc1',
        'abr': null,
        'tbr': 4000.0,
      },
      <String, dynamic>{
        'format_id': '22',
        'ext': 'mp4',
        'height': 720,
        'fps': 30.0,
        'filesize': 67108864,
        'acodec': 'mp4a.40.2',
        'vcodec': 'avc1',
        'abr': 128.0,
        'tbr': 2000.0,
      },
      <String, dynamic>{
        'format_id': '140',
        'ext': 'm4a',
        'height': null,
        'fps': null,
        'filesize': 4194304,
        'acodec': 'mp4a.40.2',
        'vcodec': 'none',
        'abr': 128.0,
        'tbr': 128.0,
      },
      <String, dynamic>{
        'format_id': 'sb0',
        'ext': 'mhtml',
        'height': null,
        'fps': null,
        'filesize': null,
        'acodec': 'none',
        'vcodec': 'none',
        'abr': null,
        'tbr': null,
      },
    ],
  });

  group('FormatParser', () {
    test('filters mhtml formats', () {
      final formats = FormatParser.parseFormats(sampleJson);
      expect(formats.any((f) => f.extension == 'mhtml'), false);
    });

    test('returns correct count', () {
      final formats = FormatParser.parseFormats(sampleJson);
      expect(formats.length, 3);
    });

    test('audio-only format is last', () {
      final formats = FormatParser.parseFormats(sampleJson);
      expect(formats.last.isAudioOnly, true);
    });

    test('identifies video format correctly', () {
      final formats = FormatParser.parseFormats(sampleJson);
      final video = formats.firstWhere((f) => f.formatId == '137');
      expect(video.isAudioOnly, false);
      expect(video.resolution, '1080p');
    });

    test('identifies audio-only correctly', () {
      final formats = FormatParser.parseFormats(sampleJson);
      final audio = formats.firstWhere((f) => f.formatId == '140');
      expect(audio.isAudioOnly, true);
    });

    test('parseVideoInfo extracts all fields', () {
      final info = FormatParser.parseVideoInfo(sampleJson);
      expect(info.title, 'Test Video');
      expect(info.uploader, 'Test Channel');
      expect(info.duration, 183);
      expect(info.viewCount, 1500000);
    });

    test('handles null filesize gracefully', () {
      final String json = jsonEncode(<String, dynamic>{
        'title': 'T',
        'webpage_url': 'u',
        'formats': <Map<String, dynamic>>[
          <String, dynamic>{
            'format_id': '22',
            'ext': 'mp4',
            'height': 720,
            'fps': 30.0,
            'filesize': null,
            'filesize_approx': null,
            'acodec': 'mp4a',
            'vcodec': 'avc1',
            'abr': null,
            'tbr': null,
          },
        ],
      });

      final formats = FormatParser.parseFormats(json);
      expect(formats.first.fileSize, isNull);
      expect(formats.first.displayLabel.toLowerCase(), contains('unknown'));
    });

    test('throws on malformed JSON', () {
      expect(
        () => FormatParser.parseFormats('{{bad json'),
        throwsA(isA<YtdlpException>()),
      );
    });

    test('handles empty formats array', () {
      final String json = jsonEncode(<String, dynamic>{
        'title': 'T',
        'webpage_url': 'u',
        'formats': <Map<String, dynamic>>[],
      });
      expect(FormatParser.parseFormats(json), isEmpty);
    });
  });
}
