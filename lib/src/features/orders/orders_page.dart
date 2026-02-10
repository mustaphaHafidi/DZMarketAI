import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:dzmarket/src/services/payment_service.dart';
import 'package:dzmarket/src/services/payment_labels.dart';
import 'package:dzmarket/src/services/input_sanitizer.dart';
import 'package:dzmarket/src/services/rate_limiter.dart';
import 'package:dzmarket/src/services/review_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/widgets/refresh_controller.dart';
import 'package:dzmarket/src/features/orders/widgets/shipment_info.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final Set<String> _paying = {};
  final RefreshController _refreshController = RefreshController();
  static const int _maxOrders = 30;

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      return Scaffold(
        body: Center(
          child: Text(L10n.tr(context, 'auth.signin_prompt')),
        ),
      );
    }

    final localeCode = Localizations.localeOf(context).languageCode;
    final currency = NumberFormat.currency(
      locale: localeCode == 'ar' ? 'ar_DZ' : 'fr_DZ',
      symbol: 'DA',
    );
    final service = OrderService();
    final paymentService = PaymentService();

    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'orders.title'))),
      body: StreamBuilder<List<Order>>(
        stream: service.streamOrdersForUser(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data ?? const [];
          final filtered = orders.where((o) => o.buyerId == userId).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));
          final limited = filtered.take(_maxOrders).toList();
          if (limited.isEmpty) {
            return Center(
              child: Text(L10n.tr(context, 'orders.empty')),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _refreshController.run(
              context,
              () => service.refreshOrders(userId),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: limited.length,
              itemBuilder: (context, index) {
                final order = limited[index];
                return _OrderCard(
                  order: order,
                  currency: currency,
                  isPaying: _paying.contains(order.id),
                  onPay: order.status == OrderStatus.pending && order.productPrice != null
                      ? () => _payForOrder(
                            context,
                            order,
                            service,
                            paymentService,
                          )
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _payForOrder(
    BuildContext context,
    Order order,
    OrderService service,
    PaymentService paymentService,
  ) async {
    if (_paying.contains(order.id)) return;
    setState(() => _paying.add(order.id));
    try {
      final amount = order.productPrice ?? 0;
      if (amount <= 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(L10n.tr(context, 'payment.invalid_amount')),
            ),
          );
        }
        return;
      }

      await paymentService.createMockPaymentIntent(
        orderId: order.id,
        amount: amount,
      );
      await service.updateStatus(
        orderId: order.id,
        status: OrderStatus.paid,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'payment.recorded_mock')),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(L10n.tr(context, 'payment.error')),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _paying.remove(order.id));
      }
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currency,
    required this.isPaying,
    this.onPay,
  });

  final Order order;
  final NumberFormat currency;
  final VoidCallback? onPay;
  final bool isPaying;

  @override
  Widget build(BuildContext context) {
    final userId = supabase.auth.currentUser?.id;
    final reviewService = ReviewService();
    final shippingService = ShippingService();
    final priceText = order.productPrice != null
        ? currency.format(order.productPrice)
        : L10n.tr(
            context,
            'orders.order_fallback',
            params: {'id': order.id},
          );
    final paymentLabel = order.paymentMethod ?? 'cod';
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
                          'orders.product_fallback',
                          params: {'id': order.productId},
                        ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusChip(
                  status: order.status,
                  label: order.statusLabel(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(priceText),
            const SizedBox(height: 4),
            if (order.shippingOption != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Chip(
                  label: Text(order.shippingOption!),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.local_shipping_outlined, size: 16),
                ),
              ),
            if ((order.courierName ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Chip(
                  label: Text(order.courierName!),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.apartment_outlined, size: 16),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Chip(
                label: Text(
                  PaymentLabels.methodLabel(context, paymentLabel),
                ),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.payments_outlined, size: 16),
              ),
            ),
            ShipmentInfo(orderId: order.id, service: shippingService),
            const SizedBox(height: 8),
            Row(
              children: [
                if (order.status == OrderStatus.pending && paymentLabel != 'cod')
                  ElevatedButton.icon(
                    onPressed: isPaying ? null : onPay,
                    icon: isPaying
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.credit_card),
                    label: Text(
                      isPaying
                          ? L10n.tr(context, 'orders.pay_processing')
                          : L10n.tr(context, 'orders.pay'),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: L10n.tr(context, 'orders.chat'),
                  onPressed: () => context.push('/order/${order.id}/chat'),
                  icon: const Icon(Icons.chat_bubble_outline),
                ),
                IconButton(
                  tooltip: L10n.tr(context, 'orders.track'),
                  onPressed: () => context.push('/order/${order.id}/track'),
                  icon: const Icon(Icons.map_outlined),
                ),
                if (userId != null && order.buyerId == userId && order.status == OrderStatus.delivered)
                  FutureBuilder<bool>(
                    future: reviewService.hasReviewForOrder(order.id, userId),
                    builder: (context, snapshot) {
                      final already = snapshot.data ?? false;
                      if (already) return const SizedBox.shrink();
                      return IconButton(
                        tooltip: L10n.tr(context, 'orders.rate_seller'),
                        onPressed: () async {
                          await _showReviewDialog(context, order, reviewService);
                        },
                        icon: const Icon(Icons.star_border),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showReviewDialog(
  BuildContext context,
  Order order,
  ReviewService reviewService,
) async {
  final rating = ValueNotifier<double>(4);
  final comment = TextEditingController();
  final navigator = Navigator.of(context);
  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          L10n.tr(context, 'orders.review_title'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: rating,
              builder: (context, value, _) {
                return Column(
                  children: [
                    Slider(
                      value: value,
                      onChanged: (v) => rating.value = v,
                      min: 1,
                      max: 5,
                      divisions: 8,
                      label: value.toStringAsFixed(1),
                    ),
                    Text(
                      L10n.tr(
                        context,
                        'orders.review_rating',
                        params: {'rating': value.toStringAsFixed(1)},
                      ),
                    ),
                  ],
                );
              },
            ),
            TextField(
              controller: comment,
              decoration: InputDecoration(
                labelText: L10n.tr(context, 'orders.review_comment'),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: Text(
              L10n.tr(context, 'orders.review_cancel'),
            ),
          ),
          TextButton(
            onPressed: () async {
              final reviewerId = supabase.auth.currentUser?.id;
              if (reviewerId == null) return;
              final safeProductId =
                  InputSanitizer.sanitizeId(order.productId.toString(), maxLength: 64);
              final sellerId = order.sellerId.isNotEmpty
                  ? order.sellerId
                  : await RateLimiter.instance.run(
                      'products.owner.lookup',
                      () => supabase
                          .from('products')
                          .select('owner_id')
                          .eq('id', safeProductId)
                          .maybeSingle()
                          .then((value) => value?['owner_id']?.toString()),
                    );
              if (sellerId == null) return;
              final safeComment = InputSanitizer.sanitizeOptionalText(
                comment.text,
                maxLength: 400,
              );
              await reviewService.submitReview(
                orderId: order.id,
                reviewerId: reviewerId,
                userId: sellerId,
                rating: rating.value.round().clamp(1, 5),
                comment: safeComment,
              );
              if (context.mounted) navigator.pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      L10n.tr(context, 'orders.review_thanks'),
                    ),
                  ),
                );
              }
            },
            child: Text(
              L10n.tr(context, 'orders.review_submit'),
            ),
          ),
        ],
      );
    },
  );
  comment.dispose();
  rating.dispose();
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});

  final OrderStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case OrderStatus.paid:
        color = Colors.green;
        break;
      case OrderStatus.shipped:
        color = Colors.blue;
        break;
      case OrderStatus.delivered:
        color = Colors.teal;
        break;
      case OrderStatus.cancelled:
        color = Colors.red;
        break;
      case OrderStatus.pending:
        color = Colors.orange;
    }
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}






