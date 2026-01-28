enum PaymentStatus {
  requiresPaymentMethod,
  requiresCapture,
  succeeded,
  failed,
  canceled,
}

class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.status,
    this.provider,
    this.clientSecret,
    this.amount,
    this.currency,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String orderId;
  final String userId;
  final PaymentStatus status;
  final String? provider;
  final String? clientSecret;
  final double? amount;
  final String? currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PaymentIntent.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'requires_payment_method';
    return PaymentIntent(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      userId: json['user_id'] as String? ?? '',
      status: _statusFromString(statusStr),
      provider: json['provider'] as String?,
      clientSecret: json['client_secret'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  static PaymentStatus _statusFromString(String value) {
    switch (value) {
      case 'requires_capture':
        return PaymentStatus.requiresCapture;
      case 'succeeded':
        return PaymentStatus.succeeded;
      case 'failed':
        return PaymentStatus.failed;
      case 'canceled':
        return PaymentStatus.canceled;
      case 'requires_payment_method':
      default:
        return PaymentStatus.requiresPaymentMethod;
    }
  }
}
