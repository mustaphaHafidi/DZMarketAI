import 'package:dzmarket/src/features/orders/fulfillment_page.dart';
import 'package:dzmarket/src/models/buyer_return_stats.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/buyer_return_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/label_url_resolver.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Liste des ventes du vendeur avec action de génération de bordereau.
class SellerOrdersPage extends StatefulWidget {
  const SellerOrdersPage({super.key});

  @override
  State<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends State<SellerOrdersPage> {
  final RefreshController _refreshController = RefreshController();
  final _orderService = OrderService();
  final _buyerReturnService = BuyerReturnService();
  Future<Map<String, BuyerReturnStats>>? _returnStatsFuture;
  int _refreshEpoch = 0;
  static const int _maxOrders = 30;

  @override
  void initState() {
    super.initState();
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
    final userId = supabase.auth.currentUser?.id;
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
                      onOpenLabel: (labelUrl) async {
                        final uri = resolveLabelUri(labelUrl);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      onDelete: () => _confirmDelete(context, order.id),
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

  Future<void> _confirmDelete(BuildContext context, String orderId) async {
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
              child: Text(L10n.tr(context, 'common.delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _orderService.updateStatus(
        orderId: orderId,
        status: OrderStatus.cancelled,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'seller_orders.cancelled'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.tr(
                context,
                'common.error_with',
                params: {'error': e.toString()},
              ),
            ),
          ),
        );
      }
    }
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
  final void Function(String labelUrl) onOpenLabel;
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      L10n.tr(
                        context,
                        'seller_orders.return_warning',
                        params: {
                          'count': '${buyerReturnStats?.returns12m ?? 0}',
                        },
                      ),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ],
                ),
              ),
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
                          icon: const Icon(Icons.delete_outline),
                          label: Text(L10n.tr(context, 'common.delete')),
                        ),
                      if ((order.labelUrl ?? '').isNotEmpty)
                        TextButton.icon(
                          onPressed: () => onOpenLabel(order.labelUrl!),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(
                            L10n.tr(context, 'seller_orders.open_label'),
                          ),
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
