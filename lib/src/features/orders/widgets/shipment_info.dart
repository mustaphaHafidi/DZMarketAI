import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/services/label_url_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ShipmentInfo extends StatelessWidget {
  const ShipmentInfo({super.key, required this.orderId, required this.service});
  static final LabelUrlService _labelUrlService = LabelUrlService();

  final String orderId;
  final ShippingService service;

  @override
  Widget build(BuildContext context) {
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
        if (s == null) {
          return Text(
            L10n.tr(context, 'shipments.pending'),
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(s.status ?? 'pending'),
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
            if ((s.trackingNumber ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
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
