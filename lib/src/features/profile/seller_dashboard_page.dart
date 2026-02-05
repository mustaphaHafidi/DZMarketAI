import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/listings/product_detail_page.dart';
import 'package:dzmarket/src/services/seller_analytics_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class SellerDashboardPage extends StatefulWidget {
  const SellerDashboardPage({super.key});

  @override
  State<SellerDashboardPage> createState() => _SellerDashboardPageState();
}

class _SellerDashboardPageState extends State<SellerDashboardPage> {
  final _service = SellerAnalyticsService();
  _RangePreset _preset = _RangePreset.month;
  DateTimeRange? _customRange;
  Future<_DashboardBundle>? _future;
  String _query = '';
  final _minProfitCtrl = TextEditingController();
  final _minSaleCtrl = TextEditingController();
  final _maxSaleCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _minProfitCtrl.dispose();
    _minSaleCtrl.dispose();
    _maxSaleCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    DateTimeRange range;
    switch (_preset) {
      case _RangePreset.today:
        range = DateTimeRange(start: now.subtract(const Duration(days: 1)), end: now);
        break;
      case _RangePreset.week:
        range = DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);
        break;
      case _RangePreset.month:
        range = DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
        break;
      case _RangePreset.quarter:
        range = DateTimeRange(start: now.subtract(const Duration(days: 90)), end: now);
        break;
      case _RangePreset.custom:
        range = _customRange ??
            DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
        break;
    }
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    final current = _service.fetchDashboard(userId, from: start, to: end);
    final previousRange = _previousRange(DateTimeRange(start: start, end: end));
    final previousTotals = _service.fetchTotals(
      userId,
      from: previousRange.start,
      to: previousRange.end,
    );
    setState(() {
      _future = Future.wait([current, previousTotals]).then(
        (results) => _DashboardBundle(
          current: results[0] as SellerDashboardData,
          previous: results[1] as SellerTotals,
          range: DateTimeRange(start: start, end: end),
        ),
      );
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (range == null) return;
    setState(() {
      _customRange = range;
      _preset = _RangePreset.custom;
    });
    _reload();
  }

  Future<void> _exportCsv(List<SellerOrderSummary> orders) async {
    if (orders.isEmpty) return;
    final csv = _buildCsv(orders);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.tr(context, 'seller_dashboard.export_title')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(csv, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.tr(context, 'common.close')),
          ),
        ],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(L10n.tr(context, 'seller_dashboard.exported'))),
    );
  }

  String _buildCsv(List<SellerOrderSummary> orders) {
    final buffer = StringBuffer();
    buffer.writeln(
      'order_id,product_id,product_title,created_at,sale_price,cost_price,fees,delivery,profit',
    );
    for (final o in orders) {
      buffer.writeln(
        '${_csv(o.orderId)},${_csv(o.productId)},${_csv(o.productTitle)},'
        '${_csv(o.createdAt.toIso8601String())},'
        '${o.salePrice.toStringAsFixed(2)},'
        '${o.costPrice.toStringAsFixed(2)},'
        '${o.feeAmount.toStringAsFixed(2)},'
        '${o.deliveryCost.toStringAsFixed(2)},'
        '${o.profit.toStringAsFixed(2)}',
      );
    }
    return buffer.toString();
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(body: Center(child: Text(L10n.tr(context, 'profile.login_required'))));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'seller_dashboard.title')),
        actions: [
          IconButton(
            onPressed: () async {
              final bundle = await _future;
              if (!mounted || bundle == null) return;
              final filtered = _applyFilters(bundle.current.orders);
              await _exportCsv(filtered);
            },
            icon: const Icon(Icons.download_outlined),
            tooltip: L10n.tr(context, 'seller_dashboard.export_tooltip'),
          ),
        ],
      ),
      body: FutureBuilder<_DashboardBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(L10n.tr(context, 'common.load_error')));
          }
          final bundle = snapshot.data;
          if (bundle == null) {
            return Center(child: Text(L10n.tr(context, 'seller_dashboard.empty')));
          }
          final data = bundle.current;
          final localeCode = Localizations.localeOf(context).languageCode;
          final currency = NumberFormat.currency(
            locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
            symbol: 'DA',
          );
          final filteredOrders = _applyFilters(data.orders);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _RangeFilters(
                  preset: _preset,
                  onPresetChange: (preset) {
                    setState(() => _preset = preset);
                    _reload();
                  },
                  onCustomRange: _pickCustomRange,
                ),
                const SizedBox(height: 12),
                _FiltersRow(
                  onQueryChanged: (value) => setState(() => _query = value),
                  minProfitCtrl: _minProfitCtrl,
                  minSaleCtrl: _minSaleCtrl,
                  maxSaleCtrl: _maxSaleCtrl,
                ),
                const SizedBox(height: 12),
                _SectionTitle(
                  title: L10n.tr(context, 'seller_dashboard.section_overview'),
                ),
                const SizedBox(height: 8),
                _SummaryCards(stats: data.periods, currency: currency),
                const SizedBox(height: 8),
                _ComparisonRow(
                  current: _totalsFromOrders(data.orders),
                  previous: bundle.previous,
                  currency: currency,
                ),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: L10n.tr(context, 'seller_dashboard.section_sales_trend'),
                ),
                const SizedBox(height: 8),
                _RevenueProfitChart(daily: data.daily, currency: currency),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: L10n.tr(context, 'seller_dashboard.section_top_products'),
                ),
                const SizedBox(height: 8),
                _TopProductsList(items: data.topProducts, currency: currency),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: L10n.tr(context, 'seller_dashboard.section_stock_alerts'),
                ),
                const SizedBox(height: 8),
                _LowStockList(items: data.lowStock),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: L10n.tr(context, 'seller_dashboard.section_recent_orders'),
                ),
                const SizedBox(height: 8),
                _OrdersList(items: filteredOrders, currency: currency),
              ],
            ),
          );
        },
      ),
    );
  }

  DateTimeRange _previousRange(DateTimeRange range) {
    final delta = range.end.difference(range.start);
    final prevEnd = range.start.subtract(const Duration(seconds: 1));
    final prevStart = prevEnd.subtract(delta);
    return DateTimeRange(start: prevStart, end: prevEnd);
  }

  List<SellerOrderSummary> _applyFilters(List<SellerOrderSummary> orders) {
    final query = _query.trim().toLowerCase();
    final minProfit = double.tryParse(_minProfitCtrl.text.trim());
    final minSale = double.tryParse(_minSaleCtrl.text.trim());
    final maxSale = double.tryParse(_maxSaleCtrl.text.trim());
    return orders.where((o) {
      if (query.isNotEmpty &&
          !o.productTitle.toLowerCase().contains(query)) {
        return false;
      }
      if (minProfit != null && o.profit < minProfit) return false;
      if (minSale != null && o.salePrice < minSale) return false;
      if (maxSale != null && o.salePrice > maxSale) return false;
      return true;
    }).toList();
  }

  SellerTotals _totalsFromOrders(List<SellerOrderSummary> orders) {
    double revenue = 0;
    double expenses = 0;
    for (final order in orders) {
      revenue += order.salePrice;
      expenses += order.costPrice + order.feeAmount + order.deliveryCost;
    }
    return SellerTotals(
      orders: orders.length,
      revenue: revenue,
      expenses: expenses,
      profit: revenue - expenses,
    );
  }
}

enum _RangePreset { today, week, month, quarter, custom }

class _RangeFilters extends StatelessWidget {
  const _RangeFilters({
    required this.preset,
    required this.onPresetChange,
    required this.onCustomRange,
  });

  final _RangePreset preset;
  final ValueChanged<_RangePreset> onPresetChange;
  final VoidCallback onCustomRange;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          selected: preset == _RangePreset.today,
          label: Text(L10n.tr(context, 'seller_dashboard.range_24h')),
          onSelected: (_) => onPresetChange(_RangePreset.today),
        ),
        FilterChip(
          selected: preset == _RangePreset.week,
          label: Text(L10n.tr(context, 'seller_dashboard.range_7d')),
          onSelected: (_) => onPresetChange(_RangePreset.week),
        ),
        FilterChip(
          selected: preset == _RangePreset.month,
          label: Text(L10n.tr(context, 'seller_dashboard.range_30d')),
          onSelected: (_) => onPresetChange(_RangePreset.month),
        ),
        FilterChip(
          selected: preset == _RangePreset.quarter,
          label: Text(L10n.tr(context, 'seller_dashboard.range_90d')),
          onSelected: (_) => onPresetChange(_RangePreset.quarter),
        ),
        ActionChip(
          label: Text(L10n.tr(context, 'seller_dashboard.range_custom')),
          onPressed: onCustomRange,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.stats,
    required this.currency,
  });

  final List<SellerPeriodStats> stats;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: stats
          .map(
            (item) => Expanded(
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currency.format(item.revenue),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        L10n.tr(
                          context,
                          'seller_dashboard.summary_profit',
                          params: {'profit': currency.format(item.profit)},
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        L10n.tr(
                          context,
                          'seller_dashboard.orders_short',
                          params: {'count': item.orders.toString()},
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _RevenueProfitChart extends StatelessWidget {
  const _RevenueProfitChart({
    required this.daily,
    required this.currency,
  });

  final List<SellerDailyStat> daily;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(child: Text(L10n.tr(context, 'seller_dashboard.no_data'))),
      );
    }
    final maxValue = daily
        .map((e) => e.revenue > e.profit ? e.revenue : e.profit)
        .fold<double>(0, (a, b) => a > b ? a : b);
    return Container(
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: CustomPaint(
        painter: _RevenueProfitPainter(daily: daily, maxValue: maxValue),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            L10n.tr(
              context,
              'seller_dashboard.max_label',
              params: {'value': currency.format(maxValue)},
            ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _RevenueProfitPainter extends CustomPainter {
  _RevenueProfitPainter({required this.daily, required this.maxValue});

  final List<SellerDailyStat> daily;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final revenuePaint = Paint()
      ..color = Colors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final profitPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final count = daily.length;
    if (count < 2) return;
    final dx = size.width / (count - 1);
    final revenuePath = Path();
    final profitPath = Path();
    for (var i = 0; i < count; i++) {
      final rev = daily[i].revenue;
      final profit = daily[i].profit;
      final yRev = maxValue <= 0 ? size.height : size.height - (rev / maxValue) * size.height;
      final yProfit =
          maxValue <= 0 ? size.height : size.height - (profit / maxValue) * size.height;
      final x = i * dx;
      if (i == 0) {
        revenuePath.moveTo(x, yRev);
        profitPath.moveTo(x, yProfit);
      } else {
        revenuePath.lineTo(x, yRev);
        profitPath.lineTo(x, yProfit);
      }
    }
    canvas.drawPath(revenuePath, revenuePaint);
    canvas.drawPath(profitPath, profitPaint);
    final dotPaint = Paint()..color = Colors.teal;
    for (var i = 0; i < count; i++) {
      final rev = daily[i].revenue;
      final x = i * dx;
      final y = maxValue <= 0 ? size.height : size.height - (rev / maxValue) * size.height;
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopProductsList extends StatelessWidget {
  const _TopProductsList({required this.items, required this.currency});

  final List<TopProductStat> items;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(L10n.tr(context, 'seller_dashboard.no_products_sold'));
    }
    final top = items.take(5).toList();
    return Column(
      children: [
        for (final item in top)
          ListTile(
            leading: _ProductThumb(url: item.imageUrl),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              L10n.tr(
                context,
                'seller_dashboard.orders_short',
                params: {'count': item.orders.toString()},
              ),
            ),
            trailing: Text(currency.format(item.profit)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(productId: item.productId),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _LowStockList extends StatelessWidget {
  const _LowStockList({required this.items});

  final List<ProductStockAlert> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(L10n.tr(context, 'seller_dashboard.low_stock_empty'));
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            leading: _ProductThumb(
              url: item.imageUrl,
              fallback: Icons.warning_amber_outlined,
            ),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${L10n.tr(context, 'listing.detail.stock', params: {'value': item.stockQuantity.toString()})}'
              ' • '
              '${L10n.tr(context, 'listing.detail.sold', params: {'value': item.soldCount.toString()})}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: L10n.tr(context, 'seller_dashboard.restock'),
              onPressed: () => _restock(context, item),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(productId: item.productId),
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _restock(BuildContext context, ProductStockAlert item) async {
    final controller = TextEditingController(text: '${item.stockQuantity}');
      final value = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(L10n.tr(context, 'seller_dashboard.restock')),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: L10n.tr(context, 'seller_dashboard.new_stock_label'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L10n.tr(context, 'common.cancel')),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed < 0) return;
                Navigator.pop(context, parsed);
              },
              child: Text(L10n.tr(context, 'common.save')),
            ),
          ],
        ),
    );
    if (value == null) return;
    await ProductService().updateProduct(
      id: item.productId,
      stockQuantity: value,
    );
  }
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.items, required this.currency});

  final List<SellerOrderSummary> items;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(L10n.tr(context, 'seller_dashboard.orders_empty'));
    }
    final recent = items.take(10).toList();
    return Column(
      children: [
        for (final item in recent)
          ListTile(
            leading: _ProductThumb(
              url: item.productImage,
              fallback: Icons.shopping_bag_outlined,
            ),
            title: Text(item.productTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              L10n.tr(
                context,
                'seller_dashboard.order_profit',
                params: {
                  'date': DateFormat('dd/MM').format(item.createdAt),
                  'profit': currency.format(item.profit),
                },
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(currency.format(item.salePrice)),
                Text(
                  L10n.tr(
                    context,
                    'seller_dashboard.order_fees',
                    params: {
                      'fees': currency.format(item.feeAmount + item.deliveryCost),
                    },
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({
    required this.url,
    this.fallback = Icons.inventory_2_outlined,
  });

  final String? url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final safeUrl = _allowlistedUrl(InputSanitizer.safeUrl(url));
    if (safeUrl == null) {
      return CircleAvatar(child: Icon(fallback));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CachedNetworkImage(
        imageUrl: safeUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
        errorWidget: (_, __, ___) => CircleAvatar(child: Icon(fallback)),
      ),
    );
  }

}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.onQueryChanged,
    required this.minProfitCtrl,
    required this.minSaleCtrl,
    required this.maxSaleCtrl,
  });

  final ValueChanged<String> onQueryChanged;
  final TextEditingController minProfitCtrl;
  final TextEditingController minSaleCtrl;
  final TextEditingController maxSaleCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: L10n.tr(context, 'seller_dashboard.search_hint'),
          ),
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: minSaleCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'seller_dashboard.min_sale'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: maxSaleCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'seller_dashboard.max_sale'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: minProfitCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: L10n.tr(context, 'seller_dashboard.min_profit'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

}

String? _allowlistedUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host.contains('supabase.co') || host.contains('localhost')) {
    return uri.toString();
  }
  return null;
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.current,
    required this.previous,
    required this.currency,
  });

  final SellerTotals current;
  final SellerTotals previous;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DeltaCard(
            label: L10n.tr(context, 'seller_dashboard.revenue'),
            value: currency.format(current.revenue),
            delta: _percent(current.revenue, previous.revenue),
          ),
        ),
        Expanded(
          child: _DeltaCard(
            label: L10n.tr(context, 'seller_dashboard.profit'),
            value: currency.format(current.profit),
            delta: _percent(current.profit, previous.profit),
          ),
        ),
        Expanded(
          child: _DeltaCard(
            label: L10n.tr(context, 'seller_dashboard.orders'),
            value: current.orders.toString(),
            delta: _percent(current.orders.toDouble(), previous.orders.toDouble()),
          ),
        ),
      ],
    );
  }

  double? _percent(double current, double previous) {
    if (previous == 0) return null;
    return ((current - previous) / previous) * 100;
  }
}

class _DeltaCard extends StatelessWidget {
  const _DeltaCard({
    required this.label,
    required this.value,
    required this.delta,
  });

  final String label;
  final String value;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final deltaValue = delta;
    final isUp = deltaValue != null && deltaValue >= 0;
    final deltaText = deltaValue == null
        ? L10n.tr(context, 'common.not_available')
        : '${deltaValue.toStringAsFixed(1)}%';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  deltaValue == null
                      ? Icons.remove
                      : isUp
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                  size: 14,
                  color: deltaValue == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : isUp
                          ? Colors.green
                          : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  deltaText,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBundle {
  const _DashboardBundle({
    required this.current,
    required this.previous,
    required this.range,
  });

  final SellerDashboardData current;
  final SellerTotals previous;
  final DateTimeRange range;
}

