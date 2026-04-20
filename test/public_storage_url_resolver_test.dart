import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizePublicStorageUrl keeps empty and invalid values stable', () {
    expect(normalizePublicStorageUrl(null), '');
    expect(normalizePublicStorageUrl(''), '');
    expect(normalizePublicStorageUrl('not-a-url'), 'not-a-url');
  });

  test('normalizePublicStorageUrl rewrites legacy supabase public storage host', () {
    const raw =
        'https://maumwzbvzbcamvlivqpe.supabase.co/storage/v1/object/public/products/u1/demo.jpg';
    final normalized = normalizePublicStorageUrl(raw);
    final configured = Uri.tryParse(SupabaseOptions.supabaseUrl);

    if (configured == null ||
        !configured.hasScheme ||
        configured.host.trim().isEmpty) {
      expect(normalized, raw);
      return;
    }

    final resolved = Uri.parse(normalized);
    expect(resolved.scheme, configured.scheme);
    expect(resolved.host, configured.host);
    expect(
      resolved.path,
      '/storage/v1/object/public/products/u1/demo.jpg',
    );
  });

  test('normalizePublicStorageUrl rewrites internal public storage host', () {
    const raw =
        'http://kong:8000/storage/v1/object/public/avatars/u1/avatar.png';
    final normalized = normalizePublicStorageUrl(raw);
    final configured = Uri.tryParse(SupabaseOptions.supabaseUrl);

    if (configured == null ||
        !configured.hasScheme ||
        configured.host.trim().isEmpty) {
      expect(normalized, raw);
      return;
    }

    final resolved = Uri.parse(normalized);
    expect(resolved.scheme, configured.scheme);
    expect(resolved.host, configured.host);
    expect(
      resolved.path,
      '/storage/v1/object/public/avatars/u1/avatar.png',
    );
  });
}
