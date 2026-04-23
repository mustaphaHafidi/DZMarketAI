import 'dart:convert';

import 'package:dzmarket/src/services/i18n.dart';

Map<String, dynamic>? parseShipmentErrorPayload(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _summarizeShipmentErrorDetail(Object? raw) {
  if (raw == null) return '';
  if (raw is Map) {
    final nested = raw['error'];
    if (nested is Map) {
      final nestedMessage = nested['message']?.toString().trim();
      if (nestedMessage != null && nestedMessage.isNotEmpty) {
        return nestedMessage;
      }
      final nestedDescription = nested['description']?.toString().trim();
      if (nestedDescription != null && nestedDescription.isNotEmpty) {
        return nestedDescription;
      }
    }
    final message = raw['message']?.toString().trim();
    if (message != null &&
        message.isNotEmpty &&
        message.toLowerCase() != 'courier_credentials_invalid') {
      return message;
    }
    final description = raw['description']?.toString().trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }
  }
  final parsed = parseShipmentErrorPayload(raw);
  if (parsed != null && !identical(parsed, raw)) {
    return _summarizeShipmentErrorDetail(parsed);
  }
  return raw.toString().trim();
}

String mapCreateShipmentError({
  required String locale,
  required Map<String, dynamic> data,
  required String courierName,
}) {
  final errorCode = data['error_code']?.toString().trim().toLowerCase() ?? '';
  final rawMessage = data['message']?.toString().trim() ?? 'Shipment failed';
  final detail = _summarizeShipmentErrorDetail(data['detail']);
  final normalizedCode = errorCode.isNotEmpty ? errorCode : rawMessage;

  switch (normalizedCode) {
    case 'courier_credentials_invalid':
      return L10n.trLocale(
        locale,
        'fulfillment.error_courier_credentials_invalid',
        params: {'courier': courierName},
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
      return detail.isNotEmpty ? detail : rawMessage;
  }
}
