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

  test('isArrangedOrderSystemEvent recognizes arranged order lifecycle events', () {
    expect(
      isArrangedOrderSystemEvent(
        i18nKey: 'order.system.created',
        isOfferEvent: false,
        deliveryMethod: 'pickup',
        shippingOption: null,
      ),
      isTrue,
    );
    expect(
      isArrangedOrderSystemEvent(
        i18nKey: 'order.system.pickup_request',
        isOfferEvent: false,
        deliveryMethod: null,
        shippingOption: null,
      ),
      isTrue,
    );
    expect(
      isArrangedOrderSystemEvent(
        i18nKey: 'order.system.created',
        isOfferEvent: false,
        deliveryMethod: 'cod',
        shippingOption: 'home',
      ),
      isFalse,
    );
    expect(
      isArrangedOrderSystemEvent(
        i18nKey: 'offer.system.accepted',
        isOfferEvent: true,
        deliveryMethod: 'pickup',
        shippingOption: null,
      ),
      isFalse,
    );
  });
}
