import 'package:dzmarket/src/utils/shipment_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps invalid courier credentials to actionable message', () {
    final message = mapCreateShipmentError(
      locale: 'fr',
      data: {
        'error_code': 'courier_credentials_invalid',
        'message': 'courier_credentials_invalid',
        'detail': 'Token invalide',
      },
      courierName: 'Yalidine Express',
    );

    expect(message, contains('Yalidine Express'));
    expect(message, contains('Paramètres transporteurs'));
  });

  test('maps missing courier settings to explicit message', () {
    final message = mapCreateShipmentError(
      locale: 'fr',
      data: {
        'error_code': 'missing_courier_settings',
        'message': 'Missing courier settings',
      },
      courierName: 'Yalidine Express',
    );

    expect(message, contains('Yalidine Express'));
    expect(message, contains('Aucun identifiant'));
  });

  test('keeps unknown shipment errors unchanged', () {
    const raw = 'Unexpected carrier error';
    final message = mapCreateShipmentError(
      locale: 'fr',
      data: {'message': raw},
      courierName: 'Yalidine Express',
    );

    expect(message, raw);
  });
}
