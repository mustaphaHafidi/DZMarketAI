import 'package:dzmarket/src/services/push_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushNotificationService.shouldMirrorForegroundMessageLocally', () {
    test('keeps Android foreground mirroring for visible notifications', () {
      final result =
          PushNotificationService.shouldMirrorForegroundMessageLocally(
            platform: TargetPlatform.android,
            hasNotificationPayload: true,
          );

      expect(result, isTrue);
    });

    test('avoids duplicate visible notifications on iOS foreground', () {
      final result =
          PushNotificationService.shouldMirrorForegroundMessageLocally(
            platform: TargetPlatform.iOS,
            hasNotificationPayload: true,
          );

      expect(result, isFalse);
    });

    test('keeps local mirroring on iOS for data-only foreground messages', () {
      final result =
          PushNotificationService.shouldMirrorForegroundMessageLocally(
            platform: TargetPlatform.iOS,
            hasNotificationPayload: false,
          );

      expect(result, isTrue);
    });
  });
}
