import 'package:dzmarket/src/services/app_error_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppErrorService.isSkippableAppError', () {
    test('skips non-fatal errors when no authenticated user is present', () {
      final skipped = AppErrorService.isSkippableAppError(
        message: 'SocketException: Failed host lookup',
        context: 'listings.refresh',
        fatal: false,
        hasAuthenticatedUser: false,
      );

      expect(skipped, isTrue);
    });

    test('skips known realtime JWT noise for authenticated users', () {
      final skipped = AppErrorService.isSkippableAppError(
        message:
            'RealtimeSubscribeException(channelError, InvalidJWTToken, details: null)',
        context: 'chat_hub.watch_conversations',
        fatal: false,
        hasAuthenticatedUser: true,
      );

      expect(skipped, isTrue);
    });

    test('skips offline noise in known transient contexts', () {
      final skipped = AppErrorService.isSkippableAppError(
        message: 'SocketException: Failed host lookup api.dzmarket.pro',
        context: 'profile.load_locations',
        fatal: false,
        hasAuthenticatedUser: true,
      );

      expect(skipped, isTrue);
    });

    test('keeps actionable RLS errors', () {
      final skipped = AppErrorService.isSkippableAppError(
        message:
            'new row violates row-level security policy for table "profiles"',
        context: 'profile.save',
        fatal: false,
        hasAuthenticatedUser: true,
      );

      expect(skipped, isFalse);
    });

    test('skips non-actionable media decode noise', () {
      final skipped = AppErrorService.isSkippableAppError(
        message: 'EncodingError: The source image cannot be decoded.',
        context: 'my_listings.avatar',
        fatal: false,
        hasAuthenticatedUser: true,
      );

      expect(skipped, isTrue);
    });

    test('skips public storage 400 noise when UI falls back gracefully', () {
      final skipped = AppErrorService.isSkippableAppError(
        message:
            'HttpException: Invalid statusCode: 400, uri = https://api.dzmarket.pro/storage/v1/object/public/products/user/file.jpg',
        context: 'my_listings.avatar',
        fatal: false,
        hasAuthenticatedUser: true,
      );

      expect(skipped, isTrue);
    });

    test('keeps fatal errors even without authenticated user', () {
      final skipped = AppErrorService.isSkippableAppError(
        message: 'StateError: fatal bootstrap failure',
        context: 'main.bootstrap',
        fatal: true,
        hasAuthenticatedUser: false,
      );

      expect(skipped, isFalse);
    });
  });
}
