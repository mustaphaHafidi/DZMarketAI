import 'package:dzmarket/src/models/payment_event.dart';
import 'package:dzmarket/src/models/payment_intent.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class PaymentService {
  Stream<List<PaymentIntent>> streamPaymentsForUser(String userId) {
    final safeUserId = InputSanitizer.sanitizeId(userId, maxLength: 64);
    return RateLimiter.instance.stream(
      'payments.stream',
      () => supabase
          .from('payment_intents')
          .stream(primaryKey: ['id'])
          .eq('user_id', safeUserId)
          .order('created_at')
          .map((rows) => rows.map(PaymentIntent.fromJson).toList()),
    );
  }

  Future<void> createMockPaymentIntent({
    required String orderId,
    required double amount,
    String currency = 'DZD',
  }) async {
    throw UnsupportedError(
      'Mock payment is disabled. DZMarket currently uses cash on delivery.',
    );
  }

  Future<Map<String, dynamic>> createRealPaymentIntent({
    required String orderId,
    required double amount,
    String currency = 'DZD',
  }) async {
    throw UnsupportedError('Real payment intent is not configured.');
  }

  Stream<List<PaymentEvent>> streamEvents(String intentId) {
    final safeIntentId = InputSanitizer.sanitizeId(intentId, maxLength: 64);
    return RateLimiter.instance.stream(
      'payments.events.stream',
      () => supabase
          .from('payment_events')
          .stream(primaryKey: ['id'])
          .eq('intent_id', safeIntentId)
          .order('created_at')
          .map((rows) => rows.map(PaymentEvent.fromJson).toList()),
    );
  }
}
