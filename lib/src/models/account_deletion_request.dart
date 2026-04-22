class AccountDeletionRequestSummary {
  const AccountDeletionRequestSummary({
    required this.id,
    required this.status,
    required this.requestedAt,
    this.processedAt,
    this.updatedAt,
    this.reason,
    this.adminNote,
  });

  final int id;
  final String status;
  final DateTime requestedAt;
  final DateTime? processedAt;
  final DateTime? updatedAt;
  final String? reason;
  final String? adminNote;

  bool get isOpen => status == 'pending' || status == 'processing';

  bool get isTerminal =>
      status == 'completed' || status == 'rejected' || status == 'cancelled';

  bool get canSubmitNewRequest => !isOpen;

  factory AccountDeletionRequestSummary.fromJson(Map<String, dynamic> json) {
    return AccountDeletionRequestSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status']?.toString() ?? 'pending').trim().toLowerCase(),
      requestedAt:
          DateTime.tryParse(
            json['requested_at']?.toString() ?? '',
          )?.toLocal() ??
          DateTime.now(),
      processedAt: DateTime.tryParse(
        json['processed_at']?.toString() ?? '',
      )?.toLocal(),
      updatedAt: DateTime.tryParse(
        json['updated_at']?.toString() ?? '',
      )?.toLocal(),
      reason: json['reason']?.toString(),
      adminNote: json['admin_note']?.toString(),
    );
  }
}
