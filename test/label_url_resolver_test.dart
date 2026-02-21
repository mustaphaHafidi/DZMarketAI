import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/utils/label_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeLabelUrl keeps empty/invalid values stable', () {
    expect(normalizeLabelUrl(null), '');
    expect(normalizeLabelUrl(''), '');
    expect(normalizeLabelUrl('not-a-url'), 'not-a-url');
  });

  test('normalizeLabelUrl strips proxy ports for public api host', () {
    expect(
      normalizeLabelUrl('https://api.dzmarket.pro:8000/storage/v1/object/x'),
      'https://api.dzmarket.pro/storage/v1/object/x',
    );
    expect(
      normalizeLabelUrl('https://api.dzmarket.pro:8443/auth/v1/verify'),
      'https://api.dzmarket.pro/auth/v1/verify',
    );
  });

  test('normalizeLabelUrl does not rewrite non-api external host', () {
    final raw = 'https://cdn.example.com:8000/labels/111.pdf';
    expect(normalizeLabelUrl(raw), raw);
  });

  test('normalizeLabelUrl rewrites internal host when public base is known', () {
    const raw = 'http://kong:8000/storage/v1/object/sign/labels/111.pdf';
    final configured = Uri.tryParse(SupabaseOptions.supabaseUrl);
    final normalized = normalizeLabelUrl(raw);

    if (configured == null ||
        !configured.hasScheme ||
        configured.host.trim().isEmpty) {
      // Local test environment may not provide SUPABASE_URL.
      expect(normalized, raw);
      return;
    }

    final resolved = Uri.parse(normalized);
    expect(resolved.scheme, configured.scheme);
    expect(resolved.host, configured.host);
    expect(resolved.path, '/storage/v1/object/sign/labels/111.pdf');
  });

  test('resolveLabelUri returns null for empty and uri for valid links', () {
    expect(resolveLabelUri(''), isNull);
    final uri = resolveLabelUri('https://api.dzmarket.pro/storage/v1/object/x');
    expect(uri, isNotNull);
    expect(uri!.host, 'api.dzmarket.pro');
  });
}
