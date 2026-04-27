import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults are correct', () {
      expect(AppSettings.defaults.themeMode, AppThemeMode.system);
      expect(AppSettings.defaults.maxConcurrentDownloads, 3);
      expect(AppSettings.defaults.embedThumbnail, true);
      expect(AppSettings.defaults.skipExistingFiles, true);
    });

    test('copyWith only updates specified fields', () {
      final AppSettings updated = AppSettings.defaults.copyWith(
        maxConcurrentDownloads: 5,
        themeMode: AppThemeMode.dark,
      );
      expect(updated.maxConcurrentDownloads, 5);
      expect(updated.themeMode, AppThemeMode.dark);
      expect(updated.embedThumbnail, AppSettings.defaults.embedThumbnail);
    });

    test('toJson and fromJson round-trip', () {
      final AppSettings original = AppSettings.defaults.copyWith(
        maxConcurrentDownloads: 2,
        downloadSubtitles: true,
        subtitleLanguage: 'bn',
      );
      final AppSettings restored = AppSettings.fromJson(original.toJson());
      expect(restored.maxConcurrentDownloads, 2);
      expect(restored.downloadSubtitles, true);
      expect(restored.subtitleLanguage, 'bn');
    });

    test('all enum labels are non-empty', () {
      for (final AppThemeMode m in AppThemeMode.values) {
        expect(m.label, isNotEmpty);
      }
      for (final DefaultQuality q in DefaultQuality.values) {
        expect(q.label, isNotEmpty);
      }
      for (final PreferredFormat f in PreferredFormat.values) {
        expect(f.label, isNotEmpty);
      }
    });
  });
}
