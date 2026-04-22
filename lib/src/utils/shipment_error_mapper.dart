import 'package:dzmarket/src/services/i18n.dart';

String mapCreateShipmentError({
  required String locale,
  required Map<String, dynamic> data,
  required String courierName,
}) {
  final errorCode = data['error_code']?.toString().trim().toLowerCase() ?? '';
  final rawMessage = data['message']?.toString().trim() ?? 'Shipment failed';
  final detail = data['detail']?.toString().trim() ?? rawMessage;
  final normalizedCode = errorCode.isNotEmpty ? errorCode : rawMessage;

  switch (normalizedCode) {
    case 'courier_credentials_invalid':
      return L10n.trLocale(
        locale,
        'fulfillment.error_courier_credentials_invalid',
        params: {'courier': courierName, 'error': detail},
      );
    case 'missing_courier_settings':
      return L10n.trLocale(
        locale,
        'fulfillment.error_missing_courier_settings',
        params: {'courier': courierName},
      );
    case 'courier_rate_limited':
      return L10n.trLocale(locale, 'fulfillment.error_courier_rate_limited');
    default:
      return rawMessage;
  }
}
