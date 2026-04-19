import 'package:dzmarket/src/utils/label_url_resolver.dart';

class ShipmentEvent {
  ShipmentEvent.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String?,
      status = json['status'] as String?,
      i18nKey = json['i18n_key'] as String?,
      title = json['title'] as String? ?? '',
      description = json['description'] as String?,
      at = json['at'] != null ? DateTime.tryParse(json['at'] as String) : null;

  final String? key;
  final String? status;
  final String? i18nKey;
  final String title;
  final String? description;
  final DateTime? at;
}

class Shipment {
  const Shipment({
    required this.orderId,
    this.trackingNumber,
    this.labelUrl,
    this.status,
    this.carrier,
    this.option,
    this.deliveryMode,
    this.createdAt,
    this.events = const [],
  });

  final String orderId;
  final String? trackingNumber;
  final String? labelUrl;
  final String? status;
  final String? carrier;
  final String? option;
  final String? deliveryMode;
  final DateTime? createdAt;
  final List<ShipmentEvent> events;

  factory Shipment.fromJson(Map<String, dynamic> json) => Shipment(
    orderId: json['order_id']?.toString() ?? '',
    trackingNumber: json['tracking_number'] as String?,
    labelUrl: normalizeLabelUrl(json['label_url'] as String?),
    status: json['status'] as String?,
    carrier: json['carrier'] as String?,
    option: json['option'] as String?,
    deliveryMode: json['delivery_mode'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
    events: ((json['events'] as List?) ?? const [])
        .map((e) => ShipmentEvent.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
