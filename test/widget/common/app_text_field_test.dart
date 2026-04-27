import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/presentation/widgets/common/app_text_field.dart';

import '../../helpers/test_helpers.dart';

void main() {
  group('AppTextField', () {
    testWidgets('shows hint text', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppTextField(
            controller: TextEditingController(),
            hintText: 'Paste URL here',
          ),
        ),
      );
      expect(find.text('Paste URL here'), findsOneWidget);
    });

    testWidgets('calls onChanged when typed', (WidgetTester t) async {
      String? val;
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppTextField(
            controller: TextEditingController(),
            hintText: 'URL',
            onChanged: (String v) => val = v,
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'https://youtube.com');
      expect(val, 'https://youtube.com');
    });

    testWidgets('shows suffix icon when provided', (WidgetTester t) async {
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppTextField(
            controller: TextEditingController(text: 'some url'),
            hintText: 'URL',
            suffixIcon: const Icon(Icons.clear),
          ),
        ),
      );
      await t.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('onSubmitted is called', (WidgetTester t) async {
      String? submitted;
      await t.pumpWidget(
        TestHelpers.wrapWithApp(
          AppTextField(
            controller: TextEditingController(),
            hintText: 'URL',
            onSubmitted: (String value) => submitted = value,
          ),
        ),
      );
      await t.enterText(find.byType(TextField), 'some url');
      await t.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 'some url');
    });
  });
}
