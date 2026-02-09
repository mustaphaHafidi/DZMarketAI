import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ecotrack: missing token returns error', () async {
    final service = ShippingService();

    final missingToken = await service.validateCredentialsDetailed(
      courierName: 'Ecotrack',
      apiKey: '',
      apiSecret: '',
    );
    expect(missingToken['ok'], isFalse);
    expect(missingToken['message'], 'Token manquant');
  });
}
