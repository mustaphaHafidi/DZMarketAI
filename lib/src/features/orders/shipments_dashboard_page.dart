import 'package:dzmarket/src/features/orders/fulfillment_page.dart';
import 'package:dzmarket/src/services/label_url_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seller dashboard for shipments with quick status change and label access.
class ShipmentsDashboardPage extends StatelessWidget {
  const ShipmentsDashboardPage({super.key});

  static final LabelUrlService _labelUrlService = LabelUrlService();

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'pending':
        return L10n.tr(context, 'orders.status_pending');
      case 'paid':
        return L10n.tr(context, 'orders.status_paid');
      case 'shipped':
        return L10n.tr(context, 'orders.status_shipped');
      case 'delivered':
        return L10n.tr(context, 'orders.status_delivered');
      case 'cancelled':
        return L10n.tr(context, 'orders.status_cancelled');
      default:
        return status;
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
    final service = ShippingService();
    final dateFmt = DateFormat('dd/MM HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text(L10n.tr(context, 'shipments.title'))),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: service.streamSellerShipments(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return Center(child: Text(L10n.tr(context, 'shipments.empty')));
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = rows[i];
              final status = (r['status'] as String?) ?? 'pending';
              final carrier = r['carrier'] as String? ?? '-';
              final courierId = (r['courier_id'] as String?) ?? '';
              final tracking = r['tracking_number'] as String? ?? '-';
              final cost = r['shipping_cost'] != null
                  ? (r['shipping_cost'] as num).toStringAsFixed(0)
                  : null;
              final labelUrl = r['label_url'] as String?;
              final deliveryMethod = r['delivery_method'] as String?;
              final shippingOption = r['shipping_option'] as String?;
              final createdAt = r['created_at'] != null
                  ? DateTime.tryParse(r['created_at'] as String)
                  : null;
              final orderId = r['order_id']?.toString() ?? '?';
              final statusLabel = _statusLabel(context, status);
              final isCancelled = status == 'cancelled';
              final carrierKey = (courierId.isNotEmpty ? courierId : carrier)
                  .toLowerCase();
              final isIntegratedCarrier =
                  carrierKey.contains('yalidine') ||
                  carrierKey.contains('ecotrack') ||
                  carrierKey.contains('zrexpress') ||
                  carrierKey.contains('guepex');
              final allowManualStatus = !isIntegratedCarrier && !isCancelled;
              final isArrangedOrder = isArrangedDelivery(
                deliveryMethod: deliveryMethod,
                shippingOption: shippingOption,
              );
              final canGenerateLabel =
                  labelUrl == null && !isCancelled && !isArrangedOrder;
              return ListTile(
                title: Text(
                  L10n.tr(
                    context,
                    'shipments.order_label',
                    params: {'id': orderId, 'carrier': carrier},
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.tr(
                        context,
                        'shipments.status_label',
                        params: {'status': statusLabel},
                      ),
                    ),
                    Text(
                      L10n.tr(
                        context,
                        'shipments.tracking_label',
                        params: {'tracking': tracking},
                      ),
                    ),
                    if (cost != null)
                      Text(
                        L10n.tr(
                          context,
                          'shipments.fee_label',
                          params: {'amount': cost},
                        ),
                      ),
                    if (createdAt != null)
                      Text(
                        L10n.tr(
                          context,
                          'shipments.created_label',
                          params: {'date': dateFmt.format(createdAt)},
                        ),
                      ),
                    if (labelUrl != null)
                      Text(
                        L10n.tr(context, 'shipments.label_ready'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (!allowManualStatus)
                      Text(
                        L10n.tr(context, 'shipments.auto_status'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    if (isCancelled)
                      Text(
                        L10n.tr(context, 'shipments.cancelled_no_label'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (isArrangedOrder)
                      Text(
                        L10n.tr(context, 'shipments.arranged_no_label'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (allowManualStatus)
                          TextButton.icon(
                            onPressed: () =>
                                _showStatusSheet(context, orderId, status),
                            icon: const Icon(Icons.sync_outlined, size: 18),
                            label: Text(
                              L10n.tr(context, 'shipments.change_status'),
                            ),
                          ),
                        if (canGenerateLabel)
                          TextButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      FulfillmentPage(orderId: orderId),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.local_shipping_outlined,
                              size: 18,
                            ),
                            label: Text(
                              L10n.tr(context, 'shipments.generate_label'),
                            ),
                          ),
                        if (labelUrl != null)
                          TextButton.icon(
                            onPressed: () =>
                                _openLabel(context, labelUrl, orderId: orderId),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            label: Text(
                              L10n.tr(context, 'shipments.open_label'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                trailing: labelUrl != null
                    ? IconButton(
                        icon: const Icon(Icons.link),
                        onPressed: () =>
                            _openLabel(context, labelUrl, orderId: orderId),
                      )
                    : null,
                onTap: allowManualStatus
                    ? () => _showStatusSheet(context, orderId, status)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  void _showStatusSheet(BuildContext context, String orderId, String current) {
    final service = ShippingService();
    final statuses = ['pending', 'paid', 'shipped', 'delivered'];
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: statuses
                .map(
                  (s) => ListTile(
                    title: Text(_statusLabel(context, s)),
                    trailing: s == current ? const Icon(Icons.check) : null,
                    onTap: () async {
                      await service.updateShipmentStatus(
                        orderId: orderId,
                        status: s,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Future<void> _openLabel(
    BuildContext context,
    String url, {
    String? orderId,
  }) async {
    final uri = await _labelUrlService.resolveFreshLabelUri(
      url,
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
    if (await canLaunchUrl(uri)) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.tr(context, 'common.error'))),
        );
      }
    }
  }
}
