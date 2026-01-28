class Address {
  const Address({
    required this.id,
    required this.userId,
    required this.line1,
    this.line2,
    this.city,
    this.state,
    this.postalCode,
    this.country = 'DZ',
    this.label,
    this.fullName,
    this.phone,
  });

  final String id;
  final String userId;
  final String line1;
  final String? line2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String country;
  final String? label;
  final String? fullName;
  final String? phone;

  factory Address.fromJson(Map<String, dynamic> json) => Address(
    id: json['id']?.toString() ?? '',
    userId: json['user_id'] as String? ?? '',
    line1: json['line1'] as String? ?? '',
    line2: json['line2'] as String?,
    city: json['city'] as String?,
    state: json['state'] as String?,
    postalCode: json['postal_code'] as String?,
    country: json['country'] as String? ?? 'DZ',
    label: json['label'] as String?,
    fullName: json['full_name'] as String?,
    phone: json['phone'] as String?,
  );

  String summary() {
    return [
      if (label != null && label!.isNotEmpty) '$label:',
      line1,
      if (line2?.isNotEmpty ?? false) line2,
      if (postalCode?.isNotEmpty ?? false) postalCode,
      if (city?.isNotEmpty ?? false) city,
      if (state?.isNotEmpty ?? false) state,
      country,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' ');
  }
}
