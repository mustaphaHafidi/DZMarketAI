import 'package:dzmarket/src/features/orders/fulfillment_page.dart';
import 'package:dzmarket/src/models/buyer_return_stats.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/buyer_return_service.dart';
import 'package:dzmarket/src/services/label_url_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Liste des ventes du vendeur avec action de génération de bordereau.
class SellerOrdersPage extends StatefulWidget {
  const SellerOrdersPage({
    super.key,
    this.orderService,
    this.buyerReturnService,
    this.labelUrlService,
    this.userIdOverride,
  });

  final OrderService? orderService;
  final BuyerReturnService? buyerReturnService;
  final LabelUrlService? labelUrlService;
  final String? userIdOverride;

  @override
  State<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends State<SellerOrdersPage> {
  final RefreshController _refreshController = RefreshController();
  late final OrderService _orderService;
  late final BuyerReturnService _buyerReturnService;
  late final LabelUrlService _labelUrlService;
  Future<Map<String, BuyerReturnStats>>? _returnStatsFuture;
  int _refreshEpoch = 0;
  static const int _maxOrders = 30;

  @override
  void initState() {
    super.initState();
    _orderService = widget.orderService ?? OrderService();
    _buyerReturnService = widget.buyerReturnService ?? BuyerReturnService();
    _labelUrlService = widget.labelUrlService ?? LabelUrlService();
    _returnStatsFuture = _buyerReturnService.fetchForSeller();
  }

  Future<void> _triggerRefresh(String userId) async {
    await _refreshController.run(
      context,
      () => _orderService.refreshOrders(userId),
    );
    if (mounted) {
      _returnStatsFuture = _buyerReturnService.fetchForSeller();
      setState(() => _refreshEpoch++);
    }
  }

  bool _isOfferOnlyGhostOrder(Order order) {
    // Guardrail: offers must stay in chat only.
    // If an old/buggy flow produced a placeholder order without any checkout
    // metadata, hide it from "Mes ventes".
    final hasShippingMeta =
        (order.shippingOption?.trim().isNotEmpty ?? false) ||
        (order.deliveryMethod?.trim().isNotEmpty ?? false) ||
        (order.courierId?.trim().isNotEmpty ?? false) ||
        (order.courierName?.trim().isNotEmpty ?? false) ||
        (order.shippingAddressId?.trim().isNotEmpty ?? false);
    final hasFulfillmentMeta =
        (order.trackingNumber?.trim().isNotEmpty ?? false) ||
        (order.labelUrl?.trim().isNotEmpty ?? false);
    final hasPaymentMeta = (order.paymentMethod?.trim().isNotEmpty ?? false);
    return !hasShippingMeta && !hasFulfillmentMeta && !hasPaymentMeta;
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userIdOverride ?? supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        body: Center(
          child: Text(L10n.tr(context, 'seller_orders.login_required')),
        ),
      );
    }

    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );

    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'seller_orders.title'))),
      body: StreamBuilder<List<Order>>(
        key: ValueKey(_refreshEpoch),
        stream: _orderService.streamOrdersForUser(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders =
              (snapshot.data ?? const [])
                  .where(
                    (o) =>
                        o.sellerId == userId &&
                        o.status != OrderStatus.cancelled &&
                        !_isOfferOnlyGhostOrder(o),
                  )
                  .toList()
                ..sort(
                  (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                    a.createdAt ?? DateTime(0),
                  ),
                );
          final limited = orders.take(_maxOrders).toList();
          if (limited.isEmpty) {
            return Center(child: Text(L10n.tr(context, 'seller_orders.empty')));
          }
          return FutureBuilder<Map<String, BuyerReturnStats>>(
            future: _returnStatsFuture,
            builder: (context, statsSnapshot) {
              final statsMap = statsSnapshot.data ?? const {};
              return RefreshIndicator(
                onRefresh: () => _triggerRefresh(userId),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: limited.length,
                  itemBuilder: (context, index) {
                    final order = limited[index];
                    return _SellerOrderCard(
                      order: order,
                      currency: currency,
                      buyerReturnStats: statsMap[order.buyerId],
                      onGenerateLabel: () async {
                        final updated = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FulfillmentPage(orderId: order.id),
                          ),
                        );
                        if (updated == true && context.mounted) {
                          await _triggerRefresh(userId);
                        }
                      },
                      onOpenLabel: (orderId, labelUrl) => _openLabel(
                        context,
                        orderId: orderId,
                        labelUrl: labelUrl,
                      ),
                      onDelete: () => _confirmCancel(context, order.id),
                      onManageArrangedDelivery: () =>
                          context.push('/order/${order.id}/chat'),
                      canCancel:
                          order.status == OrderStatus.pending &&
                          (order.labelUrl == null || order.labelUrl!.isEmpty),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openLabel(
    BuildContext context, {
    required String orderId,
    required String labelUrl,
  }) async {
    final uri = await _labelUrlService.resolveFreshLabelUri(
      labelUrl,
      orderId: orderId,
    );
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tr(
                context,
                'shipments.label_refresh_failed',
                fallback:
                    'Bordereau indisponible ou expiré. Réessayez dans quelques secondes.',
              ),
            ),
          ),
        );
      }
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(L10n.tr(context, 'common.error'))));
    }
  }

  Future<void> _confirmCancel(BuildContext context, String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(L10n.tr(context, 'seller_orders.delete_title')),
          content: Text(L10n.tr(context, 'seller_orders.delete_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L10n.tr(context, 'common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(L10n.tr(context, 'seller_orders.delete_button')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _orderService.cancelOrderBySeller(orderId: orderId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'seller_orders.cancelled'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyCancelError(context, e)),
          ),
        );
      }
    }
  }

  String _friendlyCancelError(BuildContext context, Object error) {
    final raw = error.toString().trim();
    if (raw.startsWith('Bad state: ')) {
      return raw.substring('Bad state: '.length).trim();
    }
    if (raw.isNotEmpty) {
      return raw;
    }
    return L10n.tr(context, 'common.error');
  }
}

class _SellerOrderCard extends StatelessWidget {
  const _SellerOrderCard({
    required this.order,
    required this.currency,
    required this.buyerReturnStats,
    required this.onGenerateLabel,
    required this.onOpenLabel,
    required this.onDelete,
    required this.onManageArrangedDelivery,
    required this.canCancel,
  });

  final Order order;
  final NumberFormat currency;
  final BuyerReturnStats? buyerReturnStats;
  final VoidCallback onGenerateLabel;
  final void Function(String orderId, String labelUrl) onOpenLabel;
  final VoidCallback onDelete;
  final VoidCallback onManageArrangedDelivery;
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final isArrangedOrder = isArrangedDelivery(
      deliveryMethod: order.deliveryMethod,
      shippingOption: order.shippingOption,
    );
    final priceText = order.productPrice != null
        ? currency.format(order.productPrice)
        : L10n.tr(
            context,
            'seller_orders.order_label',
            params: {'id': order.id},
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.productTitle ??
                        L10n.tr(
                          context,
                          'seller_orders.product_label',
                          params: {'id': order.productId.toString()},
                        ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  label: Text(order.statusLabel(context)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(priceText),
            if ((buyerReturnStats?.returns12m ?? 0) > 0) ...[
              const SizedBox(height: 6),
              _BuyerReturnSummary(stats: buyerReturnStats!),
            ],
            const SizedBox(height: 4),
            if (order.shippingOption != null)
              Chip(
                label: Text(order.shippingOption!),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.local_shipping_outlined, size: 16),
              ),
            if ((order.courierName ?? '').isNotEmpty)
              Chip(
                label: Text(order.courierName!),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.apartment_outlined, size: 16),
              ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: L10n.tr(context, 'common.chat'),
                  onPressed: () => context.push('/order/${order.id}/chat'),
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
                IconButton(
                  tooltip: L10n.tr(context, 'common.track'),
                  onPressed: () => context.push('/order/${order.id}/track'),
                  icon: const Icon(Icons.map_outlined),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (canCancel)
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(
                            L10n.tr(context, 'seller_orders.delete_button'),
                          ),
                        ),
                      if ((order.labelUrl ?? '').isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  onOpenLabel(order.id, order.labelUrl!),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: Text(
                                L10n.tr(context, 'seller_orders.open_label'),
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Text(
                                L10n.tr(
                                  context,
                                  'shipments.label_retention_note',
                                ),
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        )
                      else if (!isArrangedOrder)
                        FilledButton.icon(
                          onPressed: onGenerateLabel,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: Text(
                            L10n.tr(context, 'seller_orders.generate_label'),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: onManageArrangedDelivery,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text(
                            L10n.tr(context, 'seller_orders.arranged_delivery'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyerReturnSummary extends StatelessWidget {
  const _BuyerReturnSummary({required this.stats});

  final BuyerReturnStats stats;

  @override
  Widget build(BuildContext context) {
    final lastReturnAt = stats.lastReturnAt?.toLocal();
    final dateLabel = lastReturnAt == null
        ? null
        : _formatLastReturnDate(context, lastReturnAt);
    final courier = stats.lastReturnCourier?.trim();
    final hasCourier = courier != null && courier.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_toggle_off_rounded,
                size: 18,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L10n.tr(context, 'seller_orders.returns_dzmarket_title'),
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            L10n.tr(
              context,
              'seller_orders.returns_dzmarket_counts',
              params: {
                'count6': '${stats.returns6m}',
                'count12': '${stats.returns12m}',
              },
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            L10n.tr(context, 'seller_orders.returns_scope_note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (dateLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              L10n.tr(
                context,
                hasCourier
                    ? 'seller_orders.returns_last_return_with_courier'
                    : 'seller_orders.returns_last_return',
                params: {'date': dateLabel, if (hasCourier) 'courier': courier},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  String _formatLastReturnDate(BuildContext context, DateTime date) {
    final localeCode = Localizations.localeOf(context).languageCode;
    try {
      return DateFormat.yMMMd(
        localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      ).format(date);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(date);
    }
  }
}
