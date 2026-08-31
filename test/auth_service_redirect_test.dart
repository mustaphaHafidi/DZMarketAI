import 'package:dzmarket/src/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService.buildEmailRedirectUrl', () {
    test('builds recovery callback with normalized Arabic locale', () {
      final url = AuthService.instance.buildEmailRedirectUrl(
        flow: 'recovery',
        locale: 'ar-DZ',
        next: '/reset-password',
      );

      final uri = Uri.parse(url);
      expect(uri.scheme, 'https');
      expect(uri.host, 'app.dzmarket.pro');
      expect(uri.path, '/auth/callback');
      expect(uri.queryParameters['type'], 'recovery');
      expect(uri.queryParameters['lang'], 'ar');
      expect(uri.queryParameters['next'], '/reset-password');
    });

    test('builds signup callback with French fallback locale', () {
      final url = AuthService.instance.buildEmailRedirectUrl(
        flow: 'signup',
        locale: 'en',
        next: '/sign-in?confirmed=1',
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters['type'], 'signup');
      expect(uri.queryParameters['lang'], 'fr');
      expect(uri.queryParameters['next'], '/sign-in?confirmed=1');
    });
  });
}
