import 'package:dzmarket/src/utils/product_share_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a product share URL from the current web origin', () {
    final uri = buildProductShareUri(
      productId: '44',
      currentUri: Uri.parse('https://app.dzmarket.pro/?tab=listings'),
    );

    expect(uri.toString(), 'https://app.dzmarket.pro/product/44');
  });

  test('preserves local preview ports for local testing', () {
    final uri = buildProductShareUri(
      productId: '44',
      currentUri: Uri.parse('http://127.0.0.1:4319/product/44'),
    );

    expect(uri.toString(), 'http://127.0.0.1:4319/product/44');
  });

  test('falls back to the production host when current uri is file based', () {
    final uri = buildProductShareUri(
      productId: '44',
      currentUri: Uri.parse('file:///C:/src/dzmarket/build/web/index.html'),
    );

    expect(uri.toString(), 'https://app.dzmarket.pro/product/44');
  });
}
