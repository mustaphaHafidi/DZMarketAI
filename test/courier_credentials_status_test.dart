import 'package:dzmarket/src/utils/courier_credentials_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('courier credential status parser handles valid values', () {
    expect(
      courierCredentialStatusFromValue('valid'),
      CourierCredentialStatus.valid,
    );
    expect(
      courierCredentialStatusFromValue('invalid'),
      CourierCredentialStatus.invalid,
    );
  });

  test('courier credential status parser falls back to unknown', () {
    expect(
      courierCredentialStatusFromValue(null),
      CourierCredentialStatus.unknown,
    );
    expect(
      courierCredentialStatusFromValue(''),
      CourierCredentialStatus.unknown,
    );
    expect(
      courierCredentialStatusFromValue('unexpected'),
      CourierCredentialStatus.unknown,
    );
  });
}
