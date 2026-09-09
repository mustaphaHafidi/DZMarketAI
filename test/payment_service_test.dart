import 'package:dzmarket/src/services/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mock payments are disabled for cash-on-delivery flow', () async {
    await expectLater(
      PaymentService().createMockPaymentIntent(
        orderId: 'order-1',
        amount: 1000,
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
