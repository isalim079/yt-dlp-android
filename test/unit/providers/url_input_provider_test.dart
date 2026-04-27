import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_downloader/data/providers/app_navigation_providers.dart';
import 'package:yt_downloader/data/providers/ytdlp_providers.dart';

void main() {
  group('urlInputProvider', () {
    test('starts empty', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(urlInputProvider), '');
    });

    test('updates correctly', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(urlInputProvider.notifier).state =
          'https://youtube.com/watch?v=test';
      expect(
        container.read(urlInputProvider),
        'https://youtube.com/watch?v=test',
      );
    });

    test('can be reset to empty', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(urlInputProvider.notifier).state = 'some url';
      container.read(urlInputProvider.notifier).state = '';
      expect(container.read(urlInputProvider), '');
    });
  });

  group('selectedFormatProvider', () {
    test('starts null', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedFormatProvider), isNull);
    });
  });

  group('tabIndexProvider', () {
    test('starts at 0', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(tabIndexProvider), 0);
    });

    test('can switch to tab 1', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(tabIndexProvider.notifier).state = 1;
      expect(container.read(tabIndexProvider), 1);
    });
  });
}
