class PaymentEvent {
  const PaymentEvent({
    required this.id,
    required this.intentId,
    required this.status,
    this.note,
    this.createdAt,
  });

  final String id;
  final String intentId;
  final String status;
  final String? note;
  final DateTime? createdAt;

  factory PaymentEvent.fromJson(Map<String, dynamic> json) => PaymentEvent(
    id: json['id']?.toString() ?? '',
    intentId: json['intent_id']?.toString() ?? '',
    status: json['status'] as String? ?? '',
    note: json['note'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}
