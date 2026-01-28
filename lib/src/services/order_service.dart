import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:rxdart/rxdart.dart';

class OrderService {
  Stream<List<Order>> streamOrdersForUser(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    final buyerStream = RateLimiter.instance.stream(
      'orders.buyer.stream',
      () => supabase
          .from(SupabaseTables.orders)
          .stream(primaryKey: ['id'])
          .eq('buyer_id', safeUserId)
          .order('created_at'),
    );

    final sellerStream = RateLimiter.instance.stream(
      'orders.seller.stream',
      () => supabase
          .from(SupabaseTables.orders)
          .stream(primaryKey: ['id'])
          .eq('seller_id', safeUserId)
          .order('created_at'),
    );

    final driverStream = RateLimiter.instance.stream(
      'orders.driver.stream',
      () => supabase
          .from(SupabaseTables.orders)
          .stream(primaryKey: ['id'])
          .eq('driver_id', safeUserId)
          .order('created_at'),
    );

    return Rx.combineLatest3<
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Map<String, dynamic>>,
        List<Order>>(
      buyerStream,
      sellerStream,
      driverStream,
      (buyer, seller, driver) {
        final merged = <String, Map<String, dynamic>>{};
        for (final row in buyer) {
          merged[row['id'].toString()] = row;
        }
        for (final row in seller) {
          merged[row['id'].toString()] = row;
        }
        for (final row in driver) {
          merged[row['id'].toString()] = row;
        }
        return merged.values.map(Order.fromJson).toList();
      },
    );
  }

  Future<String?> createOrder({
    required String productId,
    String? shippingOption,
    String? addressId,
    String paymentMethod = 'cod',
    String? deliveryMethod,
    double? agreedPrice,
    String? courierId,
    String? courierName,
    double? shippingCost,
    double? feeAmount,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('User must be signed in to create an order');
    final safeProductId = InputSanitizer.sanitizeId(productId, maxLength: 64);
    final safeShippingOption =
        InputSanitizer.sanitizeOptionalText(shippingOption, maxLength: 60);
    final safeAddressId = InputSanitizer.sanitizeOptionalText(addressId, maxLength: 64);
    final safePaymentMethod =
        InputSanitizer.sanitizeText(paymentMethod, maxLength: 20);
    final safeDeliveryMethod =
        InputSanitizer.sanitizeOptionalText(deliveryMethod, maxLength: 40);
    final safeCourierId =
        InputSanitizer.sanitizeOptionalText(courierId, maxLength: 64);
    final safeCourierName =
        InputSanitizer.sanitizeOptionalText(courierName, maxLength: 80);

    if (feeAmount != null && feeAmount < 0) {
      throw FormatException('Frais invalides.');
    }

    final response = await RateLimiter.instance.run(
      'orders.create.rpc',
      () => supabase.rpc(
        'create_order',
        params: {
          'p_product_id': safeProductId,
          'p_shipping_address_id': safeAddressId,
          'p_payment_method': safePaymentMethod,
          'p_shipping_option': safeShippingOption,
          'p_delivery_method': safeDeliveryMethod,
          'p_agreed_price': agreedPrice,
          'p_courier_id': safeCourierId,
          'p_courier_name': safeCourierName,
          'p_shipping_cost': shippingCost,
          'p_fee_amount': feeAmount,
        },
      ),
    );
    if (response == null) return null;
    return response.toString();
  }

  Future<void> assignDriver({
    required String orderId,
    required String driverId,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeDriverId = InputSanitizer.sanitizeId(driverId, maxLength: 64);
    await RateLimiter.instance.run(
      'orders.update.driver',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'driver_id': safeDriverId})
          .eq('id', safeOrderId),
    );
  }

  Future<void> updateStatus({
    required String orderId,
    required OrderStatus status,
    String? courierId,
    String? courierName,
    String? trackingNumber,
    String? deliveryMethod,
    double? shippingCost,
    double? feeAmount,
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeCourierId =
        InputSanitizer.sanitizeOptionalText(courierId, maxLength: 64);
    final safeCourierName =
        InputSanitizer.sanitizeOptionalText(courierName, maxLength: 80);
    final safeTracking =
        InputSanitizer.sanitizeOptionalText(trackingNumber, maxLength: 80);
    final safeDelivery =
        InputSanitizer.sanitizeOptionalText(deliveryMethod, maxLength: 40);
    if (feeAmount != null && feeAmount < 0) {
      throw FormatException('Frais invalides.');
    }
    await RateLimiter.instance.run(
      'orders.update.status',
      () => supabase.from(SupabaseTables.orders).update({
        'status': status.name,
        if (safeCourierId != null) 'courier_id': safeCourierId,
        if (safeCourierName != null) 'courier_name': safeCourierName,
        if (safeTracking != null) 'tracking_number': safeTracking,
        if (safeDelivery != null) 'delivery_method': safeDelivery,
        if (shippingCost != null) 'shipping_cost': shippingCost,
        if (shippingCost != null) 'delivery_cost': shippingCost,
        if (feeAmount != null) 'fee_amount': feeAmount,
      }).eq('id', safeOrderId),
    );
  }

  Future<void> updatePaymentStatus({
    required String orderId,
    required String paymentStatus, // pending|paid|failed
  }) async {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    final safeStatus =
        InputSanitizer.sanitizeText(paymentStatus, maxLength: 20);
    await RateLimiter.instance.run(
      'orders.update.payment',
      () => supabase
          .from(SupabaseTables.orders)
          .update({'payment_status': safeStatus}).eq('id', safeOrderId),
    );
  }
}
