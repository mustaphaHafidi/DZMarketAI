import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/widgets.dart';

enum OfferStatus { pending, accepted, rejected, expired, cancelled }

class Offer {
  const Offer({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.amount,
    this.status = OfferStatus.pending,
    this.message,
    this.createdAt,
    this.respondedAt,
    this.counterAmount,
    this.agreedAmount,
    this.counterBy,
  });

  final String id;
  final String productId;
  final String buyerId;
  final String sellerId;
  final double amount;
  final OfferStatus status;
  final String? message;
  final DateTime? createdAt;
  final DateTime? respondedAt;
  final double? counterAmount;
  final double? agreedAmount;
  final String? counterBy;

  factory Offer.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'pending';
    return Offer(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      buyerId: json['buyer_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: _statusFromString(statusStr),
      message: json['message'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      respondedAt: json['responded_at'] != null
          ? DateTime.tryParse(json['responded_at'] as String)
          : null,
      counterAmount: (json['counter_amount'] as num?)?.toDouble(),
      agreedAmount: (json['agreed_amount'] as num?)?.toDouble(),
      counterBy: json['counter_by'] as String?,
    );
  }

  static OfferStatus _statusFromString(String value) {
    switch (value) {
      case 'accepted':
        return OfferStatus.accepted;
      case 'rejected':
        return OfferStatus.rejected;
      case 'expired':
        return OfferStatus.expired;
      case 'cancelled':
        return OfferStatus.cancelled;
      default:
        return OfferStatus.pending;
    }
  }

  String statusLabel(BuildContext context) {
    switch (status) {
      case OfferStatus.accepted:
        return L10n.tr(context, 'offers.status_accepted');
      case OfferStatus.rejected:
        return L10n.tr(context, 'offers.status_rejected');
      case OfferStatus.expired:
        return L10n.tr(context, 'offers.status_expired');
      case OfferStatus.cancelled:
        return L10n.tr(context, 'offers.status_cancelled');
      case OfferStatus.pending:
        return L10n.tr(context, 'offers.status_pending');
    }
  }
}

