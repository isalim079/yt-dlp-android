import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/models/video_info.dart';
import 'package:yt_downloader/presentation/widgets/download/video_info_card.dart';

import '../../helpers/test_helpers.dart';

void main() {
  const VideoInfo info = VideoInfo(
    title: 'Spider-Man Trailer',
    url: 'https://youtube.com',
    uploader: 'Marvel',
    duration: 183,
    viewCount: 1500000,
    uploadDate: '20240115',
    thumbnail: null,
  );

  group('VideoInfoCard', () {
    testWidgets('shows video title', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(const VideoInfoCard(videoInfo: info)),
      );
      expect(find.text('Spider-Man Trailer'), findsOneWidget);
    });

    testWidgets('shows uploader name', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(const VideoInfoCard(videoInfo: info)),
      );
      expect(find.text('Marvel'), findsOneWidget);
    });

    testWidgets('shows formatted duration', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(const VideoInfoCard(videoInfo: info)),
      );
      expect(find.text('03:03'), findsOneWidget);
    });

    testWidgets('shows formatted view count', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(const VideoInfoCard(videoInfo: info)),
      );
      expect(find.textContaining('1.5M'), findsOneWidget);
    });

    testWidgets('does not overflow on small screen', (WidgetTester t) async {
      t.view.physicalSize = const Size(320 * 3, 568 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        TestHelpers.wrapWithApp(const VideoInfoCard(videoInfo: info)),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
