import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:dzmarket/src/features/orders/fulfillment_page.dart';
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
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/utils/public_storage_url_resolver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _RecentOrdersFilter { all, pending, shipped, delivered }

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
  _RecentOrdersFilter _recentFilter = _RecentOrdersFilter.all;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    setState(() {
      _totalsFuture = _analytics.fetchTotals(userId, from: from, to: now);
    });
  }

  List<Order> _applyRecentFilter(List<Order> orders) {
    switch (_recentFilter) {
      case _RecentOrdersFilter.pending:
        return orders
            .where(
              (order) =>
                  order.status == OrderStatus.pending ||
                  order.status == OrderStatus.paid,
            )
            .toList();
      case _RecentOrdersFilter.shipped:
        return orders
            .where((order) => order.status == OrderStatus.shipped)
            .toList();
      case _RecentOrdersFilter.delivered:
        return orders
            .where((order) => order.status == OrderStatus.delivered)
            .toList();
      case _RecentOrdersFilter.all:
        return orders;
    }
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
            _SectionTitle(
              title: L10n.tr(context, 'seller_dashboard.section_overview'),
            ),
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
                final totals =
                    snapshot.data ??
                    const SellerTotals(
                      orders: 0,
                      revenue: 0,
                      expenses: 0,
                      profit: 0,
                    );
                return _KpiRow(
                  revenue: currency.format(totals.revenue),
                  orders: totals.orders.toString(),
                  profit: currency.format(totals.profit),
                );
              },
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<Order>>(
              stream: _orderService.streamOrdersForUser(userId),
              builder: (context, snapshot) {
                final now = DateTime.now();
                final startOfToday = DateTime(now.year, now.month, now.day);
                final orders = snapshot.data ?? const [];
                final sellerOrders =
                    orders
                        .where(
                          (o) =>
                              o.sellerId == userId &&
                              o.status != OrderStatus.cancelled,
                        )
                        .toList()
                      ..sort(
                        (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                          a.createdAt ?? DateTime(0),
                        ),
                      );
                bool isPendingState(Order order) =>
                    order.status == OrderStatus.pending ||
                    order.status == OrderStatus.paid;
                bool hasLabel(Order order) =>
                    (order.labelUrl ?? '').trim().isNotEmpty;

                final pendingToShipOrders =
                    sellerOrders.where((order) {
                      return isPendingState(order) &&
                          !hasLabel(order) &&
                          !isArrangedDelivery(
                            deliveryMethod: order.deliveryMethod,
                            shippingOption: order.shippingOption,
                          );
                    }).toList()..sort((a, b) {
                      final aCreated = a.createdAt ?? DateTime(2100);
                      final bCreated = b.createdAt ?? DateTime(2100);
                      return aCreated.compareTo(bCreated);
                    });

                final pendingLabels = pendingToShipOrders.length;
                final overduePending = pendingToShipOrders.where((order) {
                  final created = order.createdAt;
                  if (created == null) return false;
                  return now.difference(created).inHours >= 24;
                }).length;
                final arrangedPending = sellerOrders.where((order) {
                  return isPendingState(order) &&
                      isArrangedDelivery(
                        deliveryMethod: order.deliveryMethod,
                        shippingOption: order.shippingOption,
                      );
                }).length;
                final todayOrders = sellerOrders.where((order) {
                  final created = order.createdAt;
                  if (created == null) return false;
                  return !created.isBefore(startOfToday);
                }).length;
                final filteredRecent = _applyRecentFilter(sellerOrders);

                return StreamBuilder<List<Product>>(
                  stream: _productService.streamProductsForOwner(userId),
                  builder: (context, productSnapshot) {
                    final products = productSnapshot.data ?? const [];
                    final productMap = {
                      for (final product in products) product.id: product,
                    };
                    final lowStock = products.where((p) {
                      return !p.isArchived &&
                          p.stockQuantity <= _lowStockThreshold;
                    }).length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle(
                          title: L10n.tr(
                            context,
                            'seller_dashboard.today_title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _OpsMetricsGrid(
                          cards: [
                            _OpsMetricData(
                              icon: Icons.shopping_bag_outlined,
                              label: L10n.tr(
                                context,
                                'seller_dashboard.today_new_orders',
                              ),
                              value: todayOrders.toString(),
                            ),
                            _OpsMetricData(
                              icon: Icons.local_shipping_outlined,
                              label: L10n.tr(
                                context,
                                'seller_dashboard.today_to_ship',
                              ),
                              value: pendingLabels.toString(),
                            ),
                            _OpsMetricData(
                              icon: Icons.alarm_on_outlined,
                              label: L10n.tr(
                                context,
                                'seller_dashboard.today_overdue',
                              ),
                              value: overduePending.toString(),
                              highlighted: overduePending > 0,
                            ),
                            _OpsMetricData(
                              icon: Icons.handshake_outlined,
                              label: L10n.tr(
                                context,
                                'seller_dashboard.today_arranged',
                              ),
                              value: arrangedPending.toString(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: L10n.tr(
                            context,
                            'seller_dashboard.urgent_title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.picture_as_pdf_outlined,
                          title: L10n.tr(
                            context,
                            'seller_dashboard.urgent_pending',
                          ),
                          subtitle: L10n.tr(
                            context,
                            'seller_dashboard.urgent_pending_hint',
                          ),
                          count: pendingLabels,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SellerOrdersPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.alarm_on_outlined,
                          title: L10n.tr(
                            context,
                            'seller_dashboard.urgent_overdue',
                          ),
                          subtitle: L10n.tr(
                            context,
                            'seller_dashboard.urgent_overdue_hint',
                          ),
                          count: overduePending,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SellerOrdersPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.handshake_outlined,
                          title: L10n.tr(
                            context,
                            'seller_dashboard.urgent_arranged',
                          ),
                          subtitle: L10n.tr(
                            context,
                            'seller_dashboard.urgent_arranged_hint',
                          ),
                          count: arrangedPending,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SellerOrdersPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ActionTile(
                          icon: Icons.inventory_2_outlined,
                          title: L10n.tr(
                            context,
                            'seller_dashboard.urgent_low_stock',
                          ),
                          subtitle: L10n.tr(
                            context,
                            'seller_dashboard.urgent_low_stock_hint',
                          ),
                          count: lowStock,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MyListingsPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: L10n.tr(
                            context,
                            'seller_dashboard.work_queue_title',
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (pendingToShipOrders.isEmpty)
                          Text(
                            L10n.tr(
                              context,
                              'seller_dashboard.work_queue_empty',
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (final order in pendingToShipOrders.take(5))
                                _WorkQueueOrderCard(
                                  order: order,
                                  product: productMap[order.productId],
                                  isOverdue:
                                      order.createdAt != null &&
                                      now
                                              .difference(order.createdAt!)
                                              .inHours >=
                                          24,
                                  onProcess: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          FulfillmentPage(orderId: order.id),
                                    ),
                                  ),
                                ),
                              if (pendingToShipOrders.length > 5)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SellerOrdersPage(),
                                      ),
                                    ),
                                    child: Text(
                                      L10n.tr(
                                        context,
                                        'seller_dashboard.work_queue_view_all',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: L10n.tr(
                            context,
                            'seller_dashboard.section_recent_orders',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              selected:
                                  _recentFilter == _RecentOrdersFilter.all,
                              label: Text(
                                L10n.tr(context, 'seller_dashboard.filter_all'),
                              ),
                              onSelected: (_) {
                                setState(
                                  () => _recentFilter = _RecentOrdersFilter.all,
                                );
                              },
                            ),
                            ChoiceChip(
                              selected:
                                  _recentFilter == _RecentOrdersFilter.pending,
                              label: Text(
                                L10n.tr(
                                  context,
                                  'seller_dashboard.filter_pending',
                                ),
                              ),
                              onSelected: (_) {
                                setState(
                                  () => _recentFilter =
                                      _RecentOrdersFilter.pending,
                                );
                              },
                            ),
                            ChoiceChip(
                              selected:
                                  _recentFilter == _RecentOrdersFilter.shipped,
                              label: Text(
                                L10n.tr(
                                  context,
                                  'seller_dashboard.filter_shipped',
                                ),
                              ),
                              onSelected: (_) {
                                setState(
                                  () => _recentFilter =
                                      _RecentOrdersFilter.shipped,
                                );
                              },
                            ),
                            ChoiceChip(
                              selected:
                                  _recentFilter ==
                                  _RecentOrdersFilter.delivered,
                              label: Text(
                                L10n.tr(
                                  context,
                                  'seller_dashboard.filter_delivered',
                                ),
                              ),
                              onSelected: (_) {
                                setState(
                                  () => _recentFilter =
                                      _RecentOrdersFilter.delivered,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _RecentOrdersList(
                          orders: filteredRecent,
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
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsMetricData {
  const _OpsMetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;
}

class _OpsMetricsGrid extends StatelessWidget {
  const _OpsMetricsGrid({required this.cards});

  final List<_OpsMetricData> cards;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: cards.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 2.7,
      ),
      itemBuilder: (context, index) {
        final item = cards[index];
        return _OpsMetricCard(data: item);
      },
    );
  }
}

class _OpsMetricCard extends StatelessWidget {
  const _OpsMetricCard({required this.data});

  final _OpsMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = data.highlighted
        ? Colors.orange.withValues(alpha: 0.55)
        : scheme.outlineVariant.withValues(alpha: 0.5);
    final background = data.highlighted
        ? Colors.orange.withValues(alpha: 0.08)
        : scheme.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            data.icon,
            size: 18,
            color: data.highlighted ? Colors.orange.shade700 : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ],
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

class _WorkQueueOrderCard extends StatelessWidget {
  const _WorkQueueOrderCard({
    required this.order,
    required this.product,
    required this.isOverdue,
    required this.onProcess,
  });

  final Order order;
  final Product? product;
  final bool isOverdue;
  final VoidCallback onProcess;

  @override
  Widget build(BuildContext context) {
    final title =
        order.productTitle ??
        product?.title ??
        L10n.tr(
          context,
          'seller_orders.product_label',
          params: {'id': order.productId},
        );
    final createdAtText = order.createdAt == null
        ? '-'
        : DateFormat('dd/MM HH:mm').format(order.createdAt!);
    final courierText = (order.courierName ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isOverdue
              ? Colors.orange.withValues(alpha: 0.55)
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProductThumb(url: order.productImage ?? product?.imageUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isOverdue)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      L10n.tr(context, 'seller_dashboard.overdue_badge'),
                    ),
                    backgroundColor: Colors.orange.withValues(alpha: 0.15),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                order.statusLabel(context),
                if (courierText.isNotEmpty) courierText,
                createdAtText,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onProcess,
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(L10n.tr(context, 'seller_orders.generate_label')),
              ),
            ),
          ],
        ),
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
    final title =
        order.productTitle ??
        product?.title ??
        L10n.tr(
          context,
          'seller_orders.product_label',
          params: {'id': order.productId},
        );
    final date = order.createdAt == null
        ? ''
        : DateFormat('dd/MM').format(order.createdAt!);
    final priceValue =
        order.productPrice ?? order.salePrice ?? order.agreedPrice ?? 0;
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
    final safeUrl = normalizePublicStorageUrl(InputSanitizer.safeUrl(url));
    if (safeUrl.isEmpty) {
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
