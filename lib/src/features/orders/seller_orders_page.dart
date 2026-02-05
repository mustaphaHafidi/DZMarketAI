import 'package:dzmarket/src/features/orders/fulfillment_page.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
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
  int _refreshEpoch = 0;

  Future<void> _triggerRefresh(String userId) async {
    await _refreshController.run(
      context,
      () => _orderService.refreshOrders(userId),
    );
    if (mounted) {
      setState(() => _refreshEpoch++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        body: Center(child: Text(L10n.tr(context, 'seller_orders.login_required'))),
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
          final orders = (snapshot.data ?? const [])
              .where((o) =>
                  o.sellerId == userId && o.status != OrderStatus.cancelled)
              .toList()
            ..sort((a, b) =>
                (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          if (orders.isEmpty) {
            return Center(child: Text(L10n.tr(context, 'seller_orders.empty')));
          }
          return RefreshIndicator(
            onRefresh: () => _triggerRefresh(userId),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                return _SellerOrderCard(
                  order: order,
                  currency: currency,
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
                    final uri = Uri.tryParse(labelUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  onDelete: () => _confirmDelete(context, order.id),
                );
              },
            ),
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
    required this.onGenerateLabel,
    required this.onOpenLabel,
    required this.onDelete,
  });

  final Order order;
  final NumberFormat currency;
  final VoidCallback onGenerateLabel;
  final void Function(String labelUrl) onOpenLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                const Spacer(),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(L10n.tr(context, 'common.delete')),
                ),
                const SizedBox(width: 8),
                if ((order.labelUrl ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => onOpenLabel(order.labelUrl!),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(L10n.tr(context, 'seller_orders.open_label')),
                  )
                else
                  FilledButton.icon(
                    onPressed: onGenerateLabel,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(L10n.tr(context, 'seller_orders.generate_label')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
