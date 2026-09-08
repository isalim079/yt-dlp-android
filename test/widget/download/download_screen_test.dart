import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/core/constants/app_strings.dart';
import 'package:yt_downloader/core/theme/app_theme.dart';
import 'package:yt_downloader/data/models/app_download_record.dart';
import 'package:yt_downloader/data/services/app_download_registry.dart';
import 'package:yt_downloader/presentation/screens/download/download_screen.dart';

class FakeAppDownloadRegistry extends AppDownloadRegistry {
  FakeAppDownloadRegistry(this._initial);

  final List<AppDownloadRecord> _initial;

  @override
  List<AppDownloadRecord> build() {
    return _initial;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('DownloadScreen renders interactive filter tabs with counters', (
    WidgetTester tester,
  ) async {
    final List<AppDownloadRecord> testRecords = <AppDownloadRecord>[
      AppDownloadRecord(
        id: 'rec_1',
        title: 'Flutter UI Masterclass',
        filePath: '/storage/download/flutter.mp4',
        fileName: 'flutter.mp4',
        url: 'https://youtube.com/watch?v=flutter',
        fileSizeBytes: 10485760, // 10 MB
        completedAt: DateTime.now(),
        formatLabel: '1080p',
        isAppDownload: true,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDownloadRegistryProvider.overrideWith(
            () => FakeAppDownloadRegistry(testRecords),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const DownloadScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify filter tabs are rendered
    expect(find.text(AppStrings.filterAll), findsOneWidget);
    expect(find.text(AppStrings.sectionActive), findsOneWidget);
    expect(find.text(AppStrings.sectionDone), findsOneWidget);
    expect(find.text(AppStrings.sectionFailed), findsOneWidget);
    expect(find.text(AppStrings.sectionDownloaded), findsOneWidget);

    // Tap the 'Downloaded' tab
    await tester.tap(find.text(AppStrings.sectionDownloaded));
    await tester.pumpAndSettle();

    // Verify downloaded item is displayed with App Download badge
    expect(find.text('Flutter UI Masterclass'), findsOneWidget);
    expect(find.text('App Download'), findsOneWidget);

    // Tap 'Active' tab
    await tester.tap(find.text(AppStrings.sectionActive));
    await tester.pumpAndSettle();

    // Since queue is empty, active empty state shows
    expect(find.text('No active downloads'), findsOneWidget);
  });
}
