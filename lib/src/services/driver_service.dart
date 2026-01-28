import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/models/driver_position.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class DriverService {
  Stream<List<DriverPosition>> streamPositions(String orderId) {
    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    return RateLimiter.instance.stream(
      'driver.positions.stream',
      () => supabase
          .from(SupabaseTables.driverPositions)
          .stream(primaryKey: ['id'])
          .eq('order_id', safeOrderId)
          .order('updated_at')
          .map((rows) => rows.map(DriverPosition.fromJson).toList()),
    );
  }

  Future<void> pushPosition({
    required String orderId,
    required double lat,
    required double lng,
    double? heading,
  }) async {
    final driverId = supabase.auth.currentUser?.id;
    if (driverId == null) throw StateError('Driver must be signed in.');

    final safeOrderId = InputSanitizer.sanitizeId(orderId, maxLength: 64);
    await RateLimiter.instance.run(
      'driver.positions.insert',
      () => supabase.from(SupabaseTables.driverPositions).insert({
        'order_id': safeOrderId,
        'driver_id': driverId,
        'lat': lat,
        'lng': lng,
        'heading': heading,
      }),
    );
  }
}
