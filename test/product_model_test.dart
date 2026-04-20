import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('displayableImageUrls normalizes and deduplicates public storage urls', () {
    const legacyUrl =
        'https://maumwzbvzbcamvlivqpe.supabase.co/storage/v1/object/public/products/u1/demo.jpg';
    const currentUrl =
        'https://api.dzmarket.pro/storage/v1/object/public/products/u1/demo.jpg';

    final product = Product(
      id: '1',
      title: 'Sneakers',
      price: 100,
      ownerId: 'owner-1',
      imageUrls: const [legacyUrl, currentUrl],
    );

    final urls = product.displayableImageUrls();
    final configured = Uri.tryParse(SupabaseOptions.supabaseUrl);
    if (configured == null ||
        !configured.hasScheme ||
        configured.host.trim().isEmpty) {
      expect(urls, [legacyUrl, currentUrl]);
      return;
    }

    expect(urls, hasLength(1));
    expect(urls.first, currentUrl);
  });
}
