class BuyerReturnStats {
  const BuyerReturnStats({
    required this.buyerId,
    required this.returns6m,
    required this.returns12m,
    this.lastReturnAt,
    this.lastReturnCourier,
  });

  final String buyerId;
  final int returns6m;
  final int returns12m;
  final DateTime? lastReturnAt;
  final String? lastReturnCourier;

  factory BuyerReturnStats.fromJson(Map<String, dynamic> json) {
    return BuyerReturnStats(
      buyerId: json['buyer_id']?.toString() ?? '',
      returns6m: (json['returns_6m'] as num?)?.toInt() ?? 0,
      returns12m: (json['returns_12m'] as num?)?.toInt() ?? 0,
      lastReturnAt: json['last_return_at'] != null
          ? DateTime.tryParse(json['last_return_at'] as String)
          : null,
      lastReturnCourier: json['last_return_courier'] as String?,
    );
  }
}

