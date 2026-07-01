import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Shipping: missing token/secret returns error', () async {
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

  test('Shipping: COD amount above courier max is blocked', () {
    final rules = ShippingService.parcelRulesFor(courierName: 'Ecotrack');
    final validation = ShippingService.validateParcel(
      rules: rules,
      weightKg: 2,
      heightCm: 20,
      widthCm: 20,
      lengthCm: 20,
      declaredValue: 120000,
      codAmount: 200000,
      insuranceActive: false,
    );

    expect(validation, isNotNull);
    expect(validation?.code, 'cod_amount_max');
    expect(validation?.params['max'], '150000');
  });
}
