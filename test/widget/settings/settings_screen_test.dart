import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yt_downloader/core/constants/app_strings.dart';
import 'package:yt_downloader/core/theme/app_theme.dart';
import 'package:yt_downloader/data/models/app_settings.dart';
import 'package:yt_downloader/data/providers/settings_providers.dart';
import 'package:yt_downloader/presentation/screens/settings/settings_screen.dart';

class MockSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('SettingsScreen builds without Material assertion errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsProvider.overrideWith(MockSettingsNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: const SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsScreenTitle), findsOneWidget);
    expect(find.text(AppStrings.sectionDownloadLocation), findsOneWidget);
    expect(find.text(AppStrings.sectionVideoQuality), findsOneWidget);
  });
}
