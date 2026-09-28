import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/core/constants/app_strings.dart';
import 'package:yxz_tube/data/models/browse_video.dart';
import 'package:yxz_tube/presentation/widgets/browse/browse_video_tile.dart';

import '../../helpers/test_helpers.dart';

void main() {
  const BrowseVideo video = BrowseVideo(
    id: 'abc123',
    title: 'Continue this one',
    url: 'https://www.youtube.com/watch?v=abc123',
    duration: 120,
  );

  testWidgets('compact tile without onRemove has no close control', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      TestHelpers.wrapWithApp(
        BrowseVideoTile(video: video, compact: true, onTap: () {}),
      ),
    );

    expect(find.text('Continue this one'), findsOneWidget);
    expect(find.byKey(const Key('continueWatchingRemove')), findsNothing);
  });

  testWidgets('compact tile close control calls onRemove only', (
    WidgetTester tester,
  ) async {
    var tapped = false;
    var removed = false;
    await tester.pumpWidget(
      TestHelpers.wrapWithApp(
        BrowseVideoTile(
          video: video,
          compact: true,
          onTap: () => tapped = true,
          onRemove: () => removed = true,
        ),
      ),
    );

    expect(find.byTooltip(AppStrings.removeFromLibrary), findsOneWidget);
    await tester.tap(find.byKey(const Key('continueWatchingRemove')));
    await tester.pump();

    expect(removed, isTrue);
    expect(tapped, isFalse);
  });
}
