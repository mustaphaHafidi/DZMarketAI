import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isArrangedDelivery recognizes arranged delivery aliases', () {
    expect(
      isArrangedDelivery(
        deliveryMethod: 'pickup',
        shippingOption: null,
      ),
      isTrue,
    );
    expect(
      isArrangedDelivery(
        deliveryMethod: 'Livraison a convenir',
        shippingOption: null,
      ),
      isTrue,
    );
    expect(
      isArrangedDelivery(
        deliveryMethod: null,
        shippingOption: 'delivery-arranged',
      ),
      isTrue,
    );
    expect(
      isArrangedDelivery(
        deliveryMethod: 'cod',
        shippingOption: 'home',
      ),
      isFalse,
    );
  });
}
