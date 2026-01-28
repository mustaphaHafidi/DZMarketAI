class DriverPosition {
  const DriverPosition({
    required this.orderId,
    required this.driverId,
    required this.lat,
    required this.lng,
    this.heading,
    this.updatedAt,
  });

  final String orderId;
  final String driverId;
  final double lat;
  final double lng;
  final double? heading;
  final DateTime? updatedAt;

  factory DriverPosition.fromJson(Map<String, dynamic> json) => DriverPosition(
    orderId: json['order_id']?.toString() ?? '',
    driverId: json['driver_id'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0,
    heading: (json['heading'] as num?)?.toDouble(),
    updatedAt: json['updated_at'] != null
        ? DateTime.tryParse(json['updated_at'] as String)
        : null,
  );
}
