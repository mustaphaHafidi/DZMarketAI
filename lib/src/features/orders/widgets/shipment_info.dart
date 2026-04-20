import 'package:dzmarket/src/models/tracking_progress.dart';
import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/services/label_url_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/widgets/arranged_delivery_card.dart';
import 'package:dzmarket/src/widgets/tracking_stepper.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ShipmentInfo extends StatelessWidget {
  const ShipmentInfo({
    super.key,
    required this.orderId,
    required this.service,
    this.orderCreatedAt,
    this.deliveryMethod,
    this.shippingOption,
  });
  static final LabelUrlService _labelUrlService = LabelUrlService();

  final String orderId;
  final ShippingService service;
  final DateTime? orderCreatedAt;
  final String? deliveryMethod;
  final String? shippingOption;

  @override
  Widget build(BuildContext context) {
    final isArrangedOrder = isArrangedDelivery(
      deliveryMethod: deliveryMethod,
      shippingOption: shippingOption,
    );
    if (isArrangedOrder) {
      return ArrangedDeliveryCard(
        title: L10n.tr(context, 'seller_orders.arranged_delivery'),
        description: L10n.tr(context, 'checkout.arranged_summary_note'),
        compact: true,
      );
    }
    return StreamBuilder<Shipment?>(
      stream: service.streamShipment(orderId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final s = snapshot.data;
        final presentation = TrackingPresentation.fromShipment(
          s,
          createdAt: orderCreatedAt,
        );
        final statusText = L10n.tr(
          context,
          presentation.displayStatusKey,
          fallback: presentation.displayStatusFallback,
        );
        if (s == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              TrackingStepper(presentation: presentation, compact: true),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(statusText),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                if ((s.carrier ?? '').isNotEmpty)
                  Chip(
                    label: Text(s.carrier!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TrackingStepper(presentation: presentation, compact: true),
            if ((s.trackingNumber ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  L10n.tr(
                    context,
                    'shipments.tracking_label',
                    params: {'tracking': s.trackingNumber ?? ''},
                  ),
                ),
              ),
            if ((s.labelUrl ?? '').isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  final uri = await _labelUrlService.resolveFreshLabelUri(
                    s.labelUrl,
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
                  await launchUrl(uri);
                },
                icon: const Icon(Icons.link),
                label: Text(L10n.tr(context, 'shipments.open_label')),
              ),
          ],
        );
      },
    );
  }
}
