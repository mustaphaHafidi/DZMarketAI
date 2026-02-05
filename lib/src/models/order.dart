import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/widgets.dart';

enum OrderStatus { pending, paid, shipped, delivered, cancelled }

class Order {
  const Order({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    this.driverId,
    this.status = OrderStatus.pending,
    this.trackingNumber,
    this.labelUrl,
    this.createdAt,
    this.productTitle,
    this.productImage,
    this.productPrice,
    this.shippingAddressId,
    this.shippingOption,
    this.paymentMethod,
    this.paymentStatus,
    this.agreedPrice,
    this.salePrice,
    this.costPrice,
    this.feeAmount,
    this.deliveryCost,
    this.deliveryMethod,
    this.courierId,
    this.courierName,
    this.shippingCost,
  });

  final String id;
  final String productId;
  final String buyerId;
  final String sellerId;
  final String? driverId;
  final OrderStatus status;
  final String? trackingNumber;
  final String? labelUrl;
  final DateTime? createdAt;

  // De-normalized fields to avoid extra queries.
  final String? productTitle;
  final String? productImage;
  final double? productPrice;
  final String? shippingAddressId;
  final String? shippingOption;
  final String? paymentMethod;
  final String? paymentStatus;
  final double? agreedPrice;
  final double? salePrice;
  final double? costPrice;
  final double? feeAmount;
  final double? deliveryCost;
  final String? deliveryMethod;
  final String? courierId;
  final String? courierName;
  final double? shippingCost;

  factory Order.fromJson(Map<String, dynamic> json) {
    final statusString = (json['status'] as String?) ?? 'pending';
    return Order(
      id: json['id']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      buyerId: json['buyer_id'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      driverId: json['driver_id'] as String?,
      status: _statusFromString(statusString),
      trackingNumber: json['tracking_number'] as String?,
      labelUrl: json['label_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      productTitle:
          json['product']?['title'] as String? ??
          json['product_title'] as String?,
      productImage:
          json['product']?['image_url'] as String? ??
          json['product_image'] as String?,
      productPrice:
          (json['product']?['price'] as num?)?.toDouble() ??
          (json['product_price'] as num?)?.toDouble(),
      shippingAddressId: json['shipping_address_id']?.toString(),
      shippingOption: json['shipping_option'] as String?,
      paymentMethod: json['payment_method'] as String?,
      paymentStatus: json['payment_status'] as String? ?? json['intent_status'] as String?,
      agreedPrice: (json['agreed_price'] as num?)?.toDouble(),
      salePrice: (json['sale_price'] as num?)?.toDouble(),
      costPrice: (json['cost_price'] as num?)?.toDouble(),
      feeAmount: (json['fee_amount'] as num?)?.toDouble(),
      deliveryCost: (json['delivery_cost'] as num?)?.toDouble(),
      deliveryMethod: json['delivery_method'] as String?,
      courierId: json['courier_id']?.toString(),
      courierName: json['courier_name'] as String?,
      shippingCost: (json['shipping_cost'] as num?)?.toDouble(),
    );
  }

  double profit() {
    final sale = salePrice ?? agreedPrice ?? productPrice ?? 0;
    final cost = costPrice ?? 0;
    final fees = feeAmount ?? 0;
    final delivery = deliveryCost ?? shippingCost ?? 0;
    return sale - cost - fees - delivery;
  }

  static OrderStatus _statusFromString(String status) {
    switch (status) {
      case 'paid':
        return OrderStatus.paid;
      case 'shipped':
        return OrderStatus.shipped;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending;
    }
  }

  String statusLabel(BuildContext context) {
    switch (status) {
      case OrderStatus.paid:
        return L10n.tr(context, 'orders.status_paid');
      case OrderStatus.shipped:
        return L10n.tr(context, 'orders.status_shipped');
      case OrderStatus.delivered:
        return L10n.tr(context, 'orders.status_delivered');
      case OrderStatus.cancelled:
        return L10n.tr(context, 'orders.status_cancelled');
      case OrderStatus.pending:
        return L10n.tr(context, 'orders.status_pending');
    }
  }
}

