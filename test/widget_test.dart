import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yxz_tube/app_bootstrap.dart';
import 'package:yxz_tube/core/constants/app_strings.dart';
import 'package:yxz_tube/data/providers/binary_path_provider.dart';

void main() {
  testWidgets('App loads home tab after binary path resolves', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          binaryPathProvider.overrideWith((Ref ref) async => '/mock/yt-dlp'),
        ],
        child: const YtDownloaderBootstrap(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(AppStrings.appName),
      ),
      findsOneWidget,
    );
  });
}
