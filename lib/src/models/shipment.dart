class ShipmentEvent {
  ShipmentEvent.fromJson(Map<String, dynamic> json)
      : title = json['title'] as String? ?? '',
        description = json['description'] as String?,
        at = json['at'] != null ? DateTime.tryParse(json['at'] as String) : null;

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
    this.events = const [],
  });

  final String orderId;
  final String? trackingNumber;
  final String? labelUrl;
  final String? status;
  final String? carrier;
  final String? option;
  final String? deliveryMode;
  final List<ShipmentEvent> events;

  factory Shipment.fromJson(Map<String, dynamic> json) => Shipment(
        orderId: json['order_id']?.toString() ?? '',
        trackingNumber: json['tracking_number'] as String?,
        labelUrl: json['label_url'] as String?,
        status: json['status'] as String?,
        carrier: json['carrier'] as String?,
        option: json['option'] as String?,
        deliveryMode: json['delivery_mode'] as String?,
        events: ((json['events'] as List?) ?? const [])
            .map((e) => ShipmentEvent.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}
