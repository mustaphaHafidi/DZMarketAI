import 'package:dzmarket/src/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Order.fromJson falls back to delivery_cost when shipping_cost is zero',
    () {
      final order = Order.fromJson({
        'id': 134,
        'product_id': 32,
        'buyer_id': 'buyer-1',
        'seller_id': 'seller-1',
        'status': 'shipped',
        'shipping_cost': 0,
        'delivery_cost': 700,
      });

      expect(order.deliveryCost, 700);
      expect(order.shippingCost, 700);
      expect(order.profit(), -700);
    },
  );

  test('Order.fromJson normalizes legacy product image URLs', () {
    final order = Order.fromJson({
      'id': 135,
      'product_id': 32,
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'status': 'pending',
      'product_image':
          'http://91.107.239.5:8000/storage/v1/object/public/products/user-1/demo.jpg',
    });

    expect(
      order.productImage,
      'https://api.dzmarket.pro/storage/v1/object/public/products/user-1/demo.jpg',
    );
  });
}
