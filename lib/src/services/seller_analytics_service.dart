import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerPeriodStats {
  const SellerPeriodStats({
    required this.label,
    required this.orders,
    required this.revenue,
    required this.expenses,
    required this.profit,
  });

  final String label;
  final int orders;
  final double revenue;
  final double expenses;
  final double profit;
}

class SellerDailyStat {
  const SellerDailyStat({
    required this.day,
    required this.orders,
    required this.revenue,
    required this.expenses,
    required this.profit,
  });

  final DateTime day;
  final int orders;
  final double revenue;
  final double expenses;
  final double profit;
}

class SellerOrderSummary {
  const SellerOrderSummary({
    required this.orderId,
    required this.productId,
    required this.productTitle,
    required this.productImage,
    required this.createdAt,
    required this.salePrice,
    required this.costPrice,
    required this.feeAmount,
    required this.deliveryCost,
    required this.profit,
  });

  final String orderId;
  final String productId;
  final String productTitle;
  final String? productImage;
  final DateTime createdAt;
  final double salePrice;
  final double costPrice;
  final double feeAmount;
  final double deliveryCost;
  final double profit;
}

class TopProductStat {
  const TopProductStat({
    required this.productId,
    required this.title,
    required this.imageUrl,
    required this.orders,
    required this.revenue,
    required this.profit,
  });

  final String productId;
  final String title;
  final String? imageUrl;
  final int orders;
  final double revenue;
  final double profit;
}

class ProductStockAlert {
  const ProductStockAlert({
    required this.productId,
    required this.title,
    required this.imageUrl,
    required this.stockQuantity,
    required this.soldCount,
  });

  final String productId;
  final String title;
  final String? imageUrl;
  final int stockQuantity;
  final int soldCount;
}

class SellerDashboardData {
  const SellerDashboardData({
    required this.periods,
    required this.daily,
    required this.topProducts,
    required this.orders,
    required this.lowStock,
  });

  final List<SellerPeriodStats> periods;
  final List<SellerDailyStat> daily;
  final List<TopProductStat> topProducts;
  final List<SellerOrderSummary> orders;
  final List<ProductStockAlert> lowStock;
}

class SellerTotals {
  const SellerTotals({
    required this.orders,
    required this.revenue,
    required this.expenses,
    required this.profit,
  });

  final int orders;
  final double revenue;
  final double expenses;
  final double profit;
}

class SellerAnalyticsService {
  Future<SellerTotals> fetchTotals(
    String sellerId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _fetchOrderRows(
      sellerId: sellerId,
      from: from,
      to: to,
    );
    double revenue = 0;
    double expenses = 0;
    var orders = 0;
    for (final row in rows) {
      final mapRow = row as Map<String, dynamic>;
      orders += 1;
      final sale = _saleValue(mapRow);
      final cost = _costValue(mapRow);
      final fees = _feesValue(mapRow);
      revenue += sale;
      expenses += cost + fees;
    }
    return SellerTotals(
      orders: orders,
      revenue: revenue,
      expenses: expenses,
      profit: revenue - expenses,
    );
  }

  Future<SellerDashboardData> fetchDashboard(
    String sellerId, {
    DateTime? from,
    DateTime? to,
    int lowStockThreshold = 2,
  }) async {
    final safeSellerId = InputSanitizer.sanitizeId(sellerId, maxLength: 64);
    final now = DateTime.now().toUtc();
    final fromUtc = from?.toUtc();
    final toUtc = to?.toUtc();
    final data = await _fetchOrderRows(
      sellerId: safeSellerId,
      from: fromUtc,
      to: toUtc,
    );

    SellerPeriodStats calcStats(String label, DateTime from) {
      double revenue = 0;
      double expenses = 0;
      var orders = 0;
      for (final row in data) {
        final mapRow = row as Map<String, dynamic>;
        final createdAt = row['created_at'] != null
            ? DateTime.tryParse(row['created_at'] as String)
            : null;
        if (createdAt == null) continue;
        if (createdAt.isBefore(from)) continue;
        orders += 1;
        revenue += _saleValue(mapRow);
        expenses += _costValue(mapRow) + _feesValue(mapRow);
      }
      final profit = revenue - expenses;
      return SellerPeriodStats(
        label: label,
        orders: orders,
        revenue: revenue,
        expenses: expenses,
        profit: profit,
      );
    }

    final anchor = toUtc ?? now;
    final dailyPeriod =
        calcStats('Aujourd\'hui', anchor.subtract(const Duration(days: 1)));
    final weekly = calcStats('7 jours', anchor.subtract(const Duration(days: 7)));
    final monthly =
        calcStats('30 jours', anchor.subtract(const Duration(days: 30)));

    final productIds = <String>{};
    for (final row in data) {
      final id = row['product_id']?.toString();
      if (id != null && id.isNotEmpty) productIds.add(id);
    }

    List<dynamic> products;
    if (productIds.isEmpty) {
      products = <dynamic>[];
    } else {
      try {
        products = await RateLimiter.instance.run(
          'orders.analytics.products',
          () => supabase
              .from(SupabaseTables.products)
              .select('id,title,image_url,stock_quantity,sold_count')
              .filter('id', 'in', _inList(productIds.toList())),
        );
      } on PostgrestException {
        try {
          products = await RateLimiter.instance.run(
            'orders.analytics.products.fallback',
            () => supabase
                .from(SupabaseTables.products)
                .select('id,title,image_url')
                .filter('id', 'in', _inList(productIds.toList())),
          );
        } on PostgrestException {
          products = <dynamic>[];
        }
      }
    }

    final productMap = <String, Map<String, dynamic>>{};
    for (final row in products) {
      productMap[row['id'].toString()] = row as Map<String, dynamic>;
    }

    final orders = <SellerOrderSummary>[];
    final topMap = <String, _TopAgg>{};
    for (final row in data) {
      final productId = row['product_id']?.toString() ?? '';
      final createdAt = row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String)
          : now;
      final mapRow = row as Map<String, dynamic>;
      final sale = _saleValue(mapRow);
      final cost = _costValue(mapRow);
      final fees = _feesValue(mapRow);
      final profit = sale - cost - fees;
      final product = productMap[productId];
      final title = product?['title']?.toString() ?? 'Produit';
      final image = product?['image_url']?.toString();
      orders.add(SellerOrderSummary(
        orderId: row['id']?.toString() ?? '',
        productId: productId,
        productTitle: title,
        productImage: image,
        createdAt: createdAt ?? now,
        salePrice: sale,
        costPrice: cost,
        feeAmount: fees,
        deliveryCost:
            (row['delivery_cost'] as num?)?.toDouble() ??
                (row['shipping_cost'] as num?)?.toDouble() ??
                0,
        profit: profit,
      ));

      if (productId.isNotEmpty) {
        final agg = topMap.putIfAbsent(productId, () => _TopAgg());
        agg.orders += 1;
        agg.revenue += sale;
        agg.profit += profit;
      }
    }
    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final topProducts = topMap.entries
        .map((entry) {
          final product = productMap[entry.key];
          return TopProductStat(
            productId: entry.key,
            title: product?['title']?.toString() ?? 'Produit',
            imageUrl: product?['image_url']?.toString(),
            orders: entry.value.orders,
            revenue: entry.value.revenue,
            profit: entry.value.profit,
          );
        })
        .toList()
      ..sort((a, b) => b.profit.compareTo(a.profit));

    final dailyStats = _buildDailySeries(
      data,
      fromUtc ?? anchor.subtract(const Duration(days: 30)),
      toUtc ?? anchor,
      _saleValue,
      _costValue,
      _feesValue,
    );

    List<dynamic> lowStockRows;
    try {
      lowStockRows = await RateLimiter.instance.run(
        'products.low_stock',
        () => supabase
            .from(SupabaseTables.products)
            .select('id,title,image_url,stock_quantity,sold_count')
            .eq('owner_id', safeSellerId)
            .eq('is_archived', false)
            .lte('stock_quantity', lowStockThreshold)
            .order('stock_quantity'),
      );
    } on PostgrestException {
      lowStockRows = <dynamic>[];
    }
    final lowStock = lowStockRows
        .map(
          (row) => ProductStockAlert(
            productId: row['id']?.toString() ?? '',
            title: row['title']?.toString() ?? 'Produit',
            imageUrl: row['image_url']?.toString(),
            stockQuantity: (row['stock_quantity'] as num?)?.toInt() ?? 0,
            soldCount: (row['sold_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();

    return SellerDashboardData(
      periods: [dailyPeriod, weekly, monthly],
      daily: dailyStats,
      topProducts: topProducts,
      orders: orders,
      lowStock: lowStock,
    );
  }

  List<SellerDailyStat> _buildDailySeries(
    List<dynamic> rows,
    DateTime from,
    DateTime to,
    double Function(Map<String, dynamic>) saleValue,
    double Function(Map<String, dynamic>) costValue,
    double Function(Map<String, dynamic>) feesValue,
  ) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final days = end.difference(start).inDays;
    final map = <String, _DailyAgg>{};
    for (final row in rows) {
      final mapRow = row as Map<String, dynamic>;
      final createdAt = row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String)
          : null;
      if (createdAt == null) continue;
      final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
      final key = day.toIso8601String();
      final agg = map.putIfAbsent(key, () => _DailyAgg(day));
      agg.orders += 1;
      final sale = saleValue(mapRow);
      final cost = costValue(mapRow);
      final fees = feesValue(mapRow);
      agg.revenue += sale;
      agg.expenses += cost + fees;
    }
    final stats = <SellerDailyStat>[];
    for (var i = 0; i <= days; i++) {
      final day = start.add(Duration(days: i));
      final key = day.toIso8601String();
      final agg = map[key];
      final revenue = agg?.revenue ?? 0;
      final expenses = agg?.expenses ?? 0;
      stats.add(SellerDailyStat(
        day: day,
        orders: agg?.orders ?? 0,
        revenue: revenue,
        expenses: expenses,
        profit: revenue - expenses,
      ));
    }
    return stats;
  }

  Future<List<dynamic>> _fetchOrderRows({
    required String sellerId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      return await RateLimiter.instance.run(
        'orders.analytics',
        () {
          var query = supabase
              .from(SupabaseTables.orders)
              .select(
                  'id,product_id,sale_price,agreed_price,cost_price,fee_amount,delivery_cost,shipping_cost,created_at,status')
              .eq('seller_id', sellerId)
              .eq('status', 'delivered');
          if (from != null) {
            query = query.gte('created_at', from.toIso8601String());
          }
          if (to != null) {
            query = query.lte('created_at', to.toIso8601String());
          }
          return query;
        },
      );
    } on PostgrestException {
      try {
        return await RateLimiter.instance.run(
          'orders.analytics.fallback',
          () {
            var query = supabase
                .from(SupabaseTables.orders)
                .select('id,product_id,agreed_price,shipping_cost,created_at,status')
                .eq('seller_id', sellerId)
                .eq('status', 'delivered');
            if (from != null) {
              query = query.gte('created_at', from.toIso8601String());
            }
            if (to != null) {
              query = query.lte('created_at', to.toIso8601String());
            }
            return query;
          },
        );
      } on PostgrestException {
        return <dynamic>[];
      }
    } catch (_) {
      return <dynamic>[];
    }
  }

  double _saleValue(Map<String, dynamic> row) {
    final sale = (row['sale_price'] as num?)?.toDouble();
    final agreed = (row['agreed_price'] as num?)?.toDouble();
    return sale ?? agreed ?? 0;
  }

  double _costValue(Map<String, dynamic> row) {
    return (row['cost_price'] as num?)?.toDouble() ?? 0;
  }

  double _feesValue(Map<String, dynamic> row) {
    final fee = (row['fee_amount'] as num?)?.toDouble() ?? 0;
    final delivery =
        (row['delivery_cost'] as num?)?.toDouble() ??
            (row['shipping_cost'] as num?)?.toDouble() ??
            0;
    return fee + delivery;
  }

  String _inList(List<String> ids) {
    final cleaned = ids.where((id) => id.trim().isNotEmpty).toList();
    final quoted = cleaned.map((id) => '"$id"').join(',');
    return '($quoted)';
  }
}

class _TopAgg {
  int orders = 0;
  double revenue = 0;
  double profit = 0;
}

class _DailyAgg {
  _DailyAgg(this.day);
  final DateTime day;
  int orders = 0;
  double revenue = 0;
  double expenses = 0;
}
