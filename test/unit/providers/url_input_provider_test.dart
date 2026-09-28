import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/providers/app_navigation_providers.dart';
import 'package:yxz_tube/data/providers/ytdlp_providers.dart';

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
      container.read(tabIndexProvider.notifier).goTo(1);
      expect(container.read(tabIndexProvider), 1);
    });

    test('goBack restores the previous tab then stops', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final TabIndexController nav = container.read(tabIndexProvider.notifier);
      nav.goTo(1);
      nav.goTo(2);
      expect(nav.goBack(), isTrue);
      expect(container.read(tabIndexProvider), 1);
      expect(nav.goBack(), isTrue);
      expect(container.read(tabIndexProvider), 0);
      expect(nav.goBack(), isFalse);
      expect(container.read(tabIndexProvider), 0);
    });
  });
}
