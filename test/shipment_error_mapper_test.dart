import 'package:dzmarket/src/utils/shipment_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses shipment error payload from JSON string', () {
    final parsed = parseShipmentErrorPayload(
      '{"ok":false,"error_code":"courier_credentials_invalid","message":"courier_credentials_invalid"}',
    );

    expect(parsed, isNotNull);
    expect(parsed?['error_code'], 'courier_credentials_invalid');
  });

  test('maps invalid courier credentials to actionable message', () {
    final message = mapCreateShipmentError(
      locale: 'fr',
      data: {
        'error_code': 'courier_credentials_invalid',
        'message': 'courier_credentials_invalid',
        'detail': {
          'error': {
            'message': 'API ID and/or Token are wrong',
            'code': 401,
            'description': 'Unauthorized',
          },
        },
      },
      courierName: 'Yalidine Express',
    );

    expect(message, contains('Yalidine Express'));
    expect(message, contains('Paramètres transporteurs'));
    expect(message, isNot(contains('API ID and/or Token are wrong')));
    expect(message, isNot(contains('{error}')));
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

  test('maps COD amount limit to friendly message', () {
    final message = mapCreateShipmentError(
      locale: 'fr',
      data: {
        'error_code': 'parcel_cod_amount_out_of_range',
        'message': 'parcel_cod_amount_out_of_range',
        'details': {'max': 150000, 'value': 20000000},
      },
      courierName: 'ZR Express',
    );

    expect(message, contains('150000'));
    expect(message, isNot(contains('parcel_cod_amount_out_of_range')));
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
