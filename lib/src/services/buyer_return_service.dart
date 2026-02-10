import 'package:dzmarket/src/models/buyer_return_stats.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';

class BuyerReturnService {
  Future<Map<String, BuyerReturnStats>> fetchForSeller() async {
    final data = await RateLimiter.instance.run(
      'buyer_return_stats.seller',
      () => supabase.rpc('get_buyer_return_stats_for_seller'),
    );
    final rows = data is List ? data : const [];
    final result = <String, BuyerReturnStats>{};
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        final stats = BuyerReturnStats.fromJson(row);
        if (stats.buyerId.isNotEmpty) {
          result[stats.buyerId] = stats;
        }
      } else if (row is Map) {
        final stats = BuyerReturnStats.fromJson(
          row.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (stats.buyerId.isNotEmpty) {
          result[stats.buyerId] = stats;
        }
      }
    }
    return result;
  }
}

