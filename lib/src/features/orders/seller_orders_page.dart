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
  final Set<String> _hiddenCancelledOrderIds = <String>{};
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
                        !_hiddenCancelledOrderIds.contains(o.id) &&
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
                      onDelete: () => _confirmCancel(
                        context,
                        orderId: order.id,
                        userId: userId,
                      ),
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

  Future<void> _confirmCancel(
    BuildContext context, {
    required String orderId,
    required String userId,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_cancelDialogTitleV2(context)),
          content: Text(_cancelDialogBodyV2(context)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_cancelDialogDismissLabelV2(context)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_cancelDialogConfirmLabelV2(context)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _orderService.cancelOrderBySeller(orderId: orderId);
      if (mounted) {
        setState(() {
          _hiddenCancelledOrderIds.add(orderId);
          _refreshEpoch++;
        });
      }
      await _triggerRefresh(userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_cancelledSnackLabelV2(context))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyCancelError(context, e))),
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

  // ignore: unused_element
  String _cancelDialogTitle(BuildContext context) =>
      L10n.t(context, 'Annuler la commande', 'إلغاء الطلب');

  // ignore: unused_element
  String _cancelDialogBody(BuildContext context) => L10n.t(
    context,
    "Cette action annulera la commande et informera l'acheteur.",
    'سيؤدي هذا الإجراء إلى إلغاء الطلب وإبلاغ المشتري.',
  );

  // ignore: unused_element
  String _cancelDialogDismissLabel(BuildContext context) =>
      L10n.t(context, 'Annuler', 'إلغاء');

  // ignore: unused_element
  String _cancelDialogConfirmLabel(BuildContext context) =>
      L10n.t(context, "Confirmer l'annulation", 'تأكيد الإلغاء');

  // ignore: unused_element
  String _cancelledSnackLabel(BuildContext context) => L10n.t(
    context,
    "Commande annulee. L'acheteur a ete informe.",
    'تم إلغاء الطلب وتم إبلاغ المشتري.',
  );
  String _cancelDialogTitleV2(BuildContext context) =>
      L10n.tr(context, 'seller_orders.delete_title');

  String _cancelDialogBodyV2(BuildContext context) =>
      L10n.tr(context, 'seller_orders.delete_confirm');

  String _cancelDialogDismissLabelV2(BuildContext context) =>
      L10n.tr(context, 'common.cancel');

  String _cancelDialogConfirmLabelV2(BuildContext context) =>
      L10n.tr(context, 'seller_orders.confirm_cancel_button');

  String _cancelledSnackLabelV2(BuildContext context) =>
      L10n.tr(context, 'seller_orders.cancelled');
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
    final resolvedPrice =
        order.salePrice ?? order.agreedPrice ?? order.productPrice;
    final priceText = resolvedPrice != null
        ? currency.format(resolvedPrice)
        : '-';
    final chatBuyerLabel = L10n.t(context, 'Chat acheteur', 'محادثة المشتري');
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
            Text(
              L10n.tr(
                context,
                'seller_orders.order_label',
                params: {'id': order.id},
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(priceText),
            if ((buyerReturnStats?.returns12m ?? 0) > 0) ...[
              const SizedBox(height: 6),
              _BuyerReturnSummary(stats: buyerReturnStats!),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
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
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/order/${order.id}/chat'),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(chatBuyerLabel),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/order/${order.id}/track'),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(L10n.tr(context, 'common.track')),
                ),
                if (canCancel)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(_cancelButtonLabelV2(context)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if ((order.labelUrl ?? '').isNotEmpty) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => onOpenLabel(order.id, order.labelUrl!),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: Text(L10n.tr(context, 'seller_orders.open_label')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                L10n.tr(context, 'shipments.label_retention_note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (!isArrangedOrder)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onGenerateLabel,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(_generateLabelButtonLabel(context)),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onManageArrangedDelivery,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(_arrangedDeliveryButtonLabel(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  String _cancelButtonLabel(BuildContext context) =>
      L10n.t(context, 'Annuler', 'إلغاء');

  String _generateLabelButtonLabel(BuildContext context) =>
      L10n.tr(context, 'seller_orders.generate_label');

  String _arrangedDeliveryButtonLabel(BuildContext context) =>
      L10n.t(context, 'Livraison a convenir', 'تسليم يتم بالاتفاق');
  String _cancelButtonLabelV2(BuildContext context) =>
      L10n.tr(context, 'common.cancel');
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
