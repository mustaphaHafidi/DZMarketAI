import 'package:dzmarket/src/utils/web_host_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isMarketingWebHost', () {
    test('returns true for root and www hosts on web', () {
      expect(
        isMarketingWebHost(host: 'www.dzmarket.pro', isWebOverride: true),
        isTrue,
      );
      expect(
        isMarketingWebHost(host: 'dzmarket.pro', isWebOverride: true),
        isTrue,
      );
    });

    test('returns false for app host or non-web', () {
      expect(
        isMarketingWebHost(host: 'app.dzmarket.pro', isWebOverride: true),
        isFalse,
      );
      expect(
        isMarketingWebHost(host: 'www.dzmarket.pro', isWebOverride: false),
        isFalse,
      );
    });
  });

  group('shouldShowMarketingLanding', () {
    test('shows marketing landing only on root path without app tab', () {
      expect(
        shouldShowMarketingLanding(
          matchedLocation: '/',
          uri: Uri.parse('https://www.dzmarket.pro/'),
          host: 'www.dzmarket.pro',
          isWebOverride: true,
        ),
        isTrue,
      );
      expect(
        shouldShowMarketingLanding(
          matchedLocation: '/',
          uri: Uri.parse('https://www.dzmarket.pro/?tab=listings'),
          host: 'www.dzmarket.pro',
          isWebOverride: true,
        ),
        isFalse,
      );
      expect(
        shouldShowMarketingLanding(
          matchedLocation: '/',
          uri: Uri.parse('https://app.dzmarket.pro/'),
          host: 'app.dzmarket.pro',
          isWebOverride: true,
        ),
        isFalse,
      );
    });
  });
}
