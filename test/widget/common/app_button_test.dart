import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/presentation/widgets/common/app_button.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('AppButton', () {
    testWidgets('shows label', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(AppButton(label: 'Download', onPressed: () {})),
      );
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('shows spinner when isLoading', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          const AppButton(label: 'Download', isLoading: true),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('disabled when onPressed null', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          const AppButton(label: 'Download', onPressed: null),
        ),
      );
      final ElevatedButton btn = t.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('calls onPressed when tapped', (WidgetTester t) async {
      bool tapped = false;
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppButton(label: 'Go', onPressed: () => tapped = true),
        ),
      );
      await t.tap(find.byType(ElevatedButton));
      await t.pump();
      expect(tapped, true);
    });

    testWidgets('shows icon when provided', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppButton(
            label: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });
}
