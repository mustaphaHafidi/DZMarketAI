import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Yalidine: missing token/secret returns error', () async {
    final service = ShippingService();

    final missingToken = await service.validateCredentialsDetailed(
      courierName: 'Yalidine Express',
      apiKey: '',
      apiSecret: '',
    );
    expect(missingToken['ok'], isFalse);
    expect(missingToken['message'], 'Token manquant');

    final missingSecret = await service.validateCredentialsDetailed(
      courierName: 'Yalidine Express',
      apiKey: 'test-token',
      apiSecret: '',
    );
    expect(missingSecret['ok'], isFalse);
    expect(missingSecret['message'], 'Secret manquant');
  });
}
