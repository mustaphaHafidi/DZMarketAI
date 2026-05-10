import 'package:dzmarket/src/utils/ios_public_browse_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allowsAnonymousBrowse', () {
    test('enabled on every platform', () {
      expect(
        allowsAnonymousBrowse(
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        allowsAnonymousBrowse(
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        allowsAnonymousBrowse(
          platform: TargetPlatform.iOS,
          isWebOverride: true,
        ),
        isTrue,
      );
    });
  });

  group('allowsIosAnonymousBrowse', () {
    test('legal gate remains enabled only on native iOS', () {
      expect(
        allowsIosAnonymousBrowse(
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        allowsIosAnonymousBrowse(
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isFalse,
      );
      expect(
        allowsIosAnonymousBrowse(
          platform: TargetPlatform.iOS,
          isWebOverride: true,
        ),
        isFalse,
      );
    });
  });

  group('isAnonymousRouteAllowed', () {
    test('allows listings root for anonymous users', () {
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/',
          uri: Uri.parse('/?tab=listings'),
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/',
          uri: Uri.parse('/'),
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/',
          uri: Uri.parse('/?tab=listings'),
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isTrue,
      );
    });

    test('blocks chat and profile tabs for anonymous users', () {
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/',
          uri: Uri.parse('/?tab=chat'),
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isFalse,
      );
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/',
          uri: Uri.parse('/?tab=profile'),
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isFalse,
      );
    });

    test('allows product detail for anonymous users', () {
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/product/:id',
          uri: Uri.parse('/product/42'),
          platform: TargetPlatform.iOS,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/product/42',
          uri: Uri.parse('/product/42'),
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isTrue,
      );
      expect(
        isAnonymousRouteAllowed(
          matchedLocation: '/product/:id',
          uri: Uri.parse('/product/42'),
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isTrue,
      );
    });
  });
}
