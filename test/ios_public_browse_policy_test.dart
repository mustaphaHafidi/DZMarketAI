import 'package:dzmarket/src/utils/ios_public_browse_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allowsIosAnonymousBrowse', () {
    test('enabled only on native iOS', () {
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
    test('allows listings root on native iOS', () {
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
    });

    test('blocks chat and profile tabs on native iOS', () {
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

    test('allows product detail on native iOS only', () {
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
          matchedLocation: '/product/:id',
          uri: Uri.parse('/product/42'),
          platform: TargetPlatform.android,
          isWebOverride: false,
        ),
        isFalse,
      );
    });
  });
}
