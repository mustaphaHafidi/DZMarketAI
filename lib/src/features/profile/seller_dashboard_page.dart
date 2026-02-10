import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/features/profile/my_listings_page.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:dzmarket/src/services/seller_analytics_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SellerDashboardPage extends StatefulWidget {
  const SellerDashboardPage({super.key});

  @override
  State<SellerDashboardPage> createState() => _SellerDashboardPageState();
}

class _SellerDashboardPageState extends State<SellerDashboardPage> {
  static const int _lowStockThreshold = 2;

  final _analytics = SellerAnalyticsService();
  final _orderService = OrderService();
  final _productService = ProductService();
  Future<SellerTotals>? _totalsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    setState(() {
      _totalsFuture = _analytics.fetchTotals(userId, from: from, to: now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        body: Center(child: Text(L10n.tr(context, 'profile.login_required'))),
      );
    }

    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.tr(context, 'seller_dashboard.title')),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: L10n.tr(context, 'common.refresh'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle(title: L10n.tr(context, 'seller_dashboard.section_overview')),
            const SizedBox(height: 4),
            Text(
              L10n.tr(context, 'seller_dashboard.subtitle_30d'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            FutureBuilder<SellerTotals>(
              future: _totalsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final totals = snapshot.data ??
                    const SellerTotals(orders: 0, revenue: 0, expenses: 0, profit: 0);
                return _KpiRow(
                  revenue: currency.format(totals.revenue),
                  orders: totals.orders.toString(),
                  profit: currency.format(totals.profit),
                );
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle(title: L10n.tr(context, 'seller_dashboard.urgent_title')),
            const SizedBox(height: 8),
            StreamBuilder<List<Order>>(
              stream: _orderService.streamOrdersForUser(userId),
              builder: (context, snapshot) {
                final orders = snapshot.data ?? const [];
                final sellerOrders = orders
                    .where((o) =>
                        o.sellerId == userId && o.status != OrderStatus.cancelled)
                    .toList()
                  ..sort((a, b) => (b.createdAt ?? DateTime(0))
                      .compareTo(a.createdAt ?? DateTime(0)));
                final pendingLabels = sellerOrders.where((o) {
                  final hasLabel = (o.labelUrl ?? '').isNotEmpty;
                  return o.status == OrderStatus.pending && !hasLabel;
                }).length;

                return StreamBuilder<List<Product>>(
                  stream: _productService.streamProductsForOwner(userId),
                  builder: (context, productSnapshot) {
                    final products = productSnapshot.data ?? const [];
                    final productMap = {
                      for (final product in products) product.id: product,
                    };
                    final lowStock = products.where((p) {
                      return !p.isArchived && p.stockQuantity <= _lowStockThreshold;
                    }).length;

                    return Column(
                      children: [
                        _ActionTile(
                          icon: Icons.picture_as_pdf_outlined,
                          title: L10n.tr(context, 'seller_dashboard.urgent_pending'),
                          subtitle:
                              L10n.tr(context, 'seller_dashboard.urgent_pending_hint'),
                          count: pendingLabels,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SellerOrdersPage()),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.inventory_2_outlined,
                          title: L10n.tr(context, 'seller_dashboard.urgent_low_stock'),
                          subtitle:
                              L10n.tr(context, 'seller_dashboard.urgent_low_stock_hint'),
                          count: lowStock,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MyListingsPage()),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: L10n.tr(context, 'seller_dashboard.section_recent_orders'),
                        ),
                        const SizedBox(height: 8),
                        _RecentOrdersList(
                          orders: sellerOrders,
                          currency: currency,
                          productMap: productMap,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.revenue,
    required this.orders,
    required this.profit,
  });

  final String revenue;
  final String orders;
  final String profit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: L10n.tr(context, 'seller_dashboard.revenue'),
            value: revenue,
            icon: Icons.payments_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: L10n.tr(context, 'seller_dashboard.orders'),
            value: orders,
            icon: Icons.shopping_bag_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: L10n.tr(context, 'seller_dashboard.profit'),
            value: profit,
            icon: Icons.trending_up_outlined,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = count.toString();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Chip(label: Text(badge)),
        onTap: onTap,
      ),
    );
  }
}

class _RecentOrdersList extends StatelessWidget {
  const _RecentOrdersList({
    required this.orders,
    required this.currency,
    required this.productMap,
  });

  final List<Order> orders;
  final NumberFormat currency;
  final Map<String, Product> productMap;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Text(L10n.tr(context, 'seller_dashboard.orders_empty'));
    }
    final recent = orders.take(6).toList();
    return Column(
      children: [
        for (final order in recent)
          _OrderTile(
            order: order,
            currency: currency,
            product: productMap[order.productId],
          ),
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.order,
    required this.currency,
    required this.product,
  });

  final Order order;
  final NumberFormat currency;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final title = order.productTitle ??
        product?.title ??
        L10n.tr(
          context,
          'seller_orders.product_label',
          params: {'id': order.productId},
        );
    final date = order.createdAt == null
        ? ''
        : DateFormat('dd/MM').format(order.createdAt!);
    final priceValue = order.productPrice ?? order.salePrice ?? order.agreedPrice ?? 0;
    return ListTile(
      leading: _ProductThumb(url: order.productImage ?? product?.imageUrl),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${order.statusLabel(context)}${date.isNotEmpty ? ' - $date' : ''}',
      ),
      trailing: Text(currency.format(priceValue)),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final safeUrl = InputSanitizer.safeUrl(url);
    if (safeUrl == null) {
      return const CircleAvatar(child: Icon(Icons.inventory_2_outlined));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: CachedNetworkImage(
        imageUrl: safeUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HtmlImage,
        errorWidget: (_, __, ___) =>
            const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
      ),
    );
  }
}
