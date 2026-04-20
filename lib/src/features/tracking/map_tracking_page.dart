import 'package:dzmarket/src/models/driver_position.dart';
import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/models/tracking_progress.dart';
import 'package:dzmarket/src/config/supabase_options.dart';
import 'package:dzmarket/src/services/driver_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/supabase_service.dart';
import 'package:dzmarket/src/utils/delivery_mode_utils.dart';
import 'package:dzmarket/src/widgets/arranged_delivery_card.dart';
import 'package:dzmarket/src/widgets/tracking_stepper.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class MapTrackingPage extends StatefulWidget {
  const MapTrackingPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<MapTrackingPage> createState() => _MapTrackingPageState();
}

class _MapTrackingPageState extends State<MapTrackingPage> {
  GoogleMapController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.Hm();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from(SupabaseTables.orders)
          .stream(primaryKey: ['id'])
          .eq('id', widget.orderId),
      builder: (context, orderSnap) {
        final order = orderSnap.data?.isNotEmpty == true
            ? Map<String, dynamic>.from(orderSnap.data!.first)
            : null;
        final isArrangedOrder = isArrangedDelivery(
          deliveryMethod: order?['delivery_method']?.toString(),
          shippingOption: order?['shipping_option']?.toString(),
        );
        final orderCreatedAt = order?['created_at'] != null
            ? DateTime.tryParse(order!['created_at'] as String)
            : null;
        final arrangedStatus = _statusLabel(
          context,
          order?['status']?.toString() ?? 'pending',
        );

        return StreamBuilder<Shipment?>(
          stream: ShippingService().streamShipment(widget.orderId),
          builder: (context, shipmentSnap) {
            final shipment = shipmentSnap.data;
            final presentation = TrackingPresentation.fromShipment(
              shipment,
              createdAt: orderCreatedAt,
            );
            final carrierLine = [
              if (shipment?.carrier?.isNotEmpty ?? false) shipment!.carrier!,
              if (shipment?.option?.isNotEmpty ?? false) shipment!.option!,
            ].join(' - ');
            final carrierEvents = shipment?.events ?? const <ShipmentEvent>[];

            if (isArrangedOrder) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(
                    L10n.tr(
                      context,
                      'track.title',
                      params: {'id': widget.orderId},
                    ),
                  ),
                ),
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      L10n.tr(
                        context,
                        'track.order_label',
                        params: {'id': widget.orderId},
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    ArrangedDeliveryCard(
                      title: L10n.tr(
                        context,
                        'seller_orders.arranged_delivery',
                      ),
                      description: L10n.tr(
                        context,
                        'checkout.arranged_summary_note',
                      ),
                      statusLabel: arrangedStatus,
                    ),
                    if (orderCreatedAt != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        L10n.tr(
                          context,
                          'shipments.created_label',
                          params: {
                            'date': DateFormat('dd/MM HH:mm').format(
                              orderCreatedAt,
                            ),
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }

            return StreamBuilder<List<DriverPosition>>(
              stream: DriverService().streamPositions(widget.orderId),
              builder: (context, snapshot) {
                final positions = snapshot.data ?? const [];

                if (positions.isEmpty) {
                  return Scaffold(
                    appBar: AppBar(
                      title: Text(
                        L10n.tr(
                          context,
                          'track.title',
                          params: {'id': widget.orderId},
                        ),
                      ),
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          L10n.tr(
                            context,
                            'track.order_label',
                            params: {'id': widget.orderId},
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (carrierLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            carrierLine,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ],
                        if ((shipment?.trackingNumber ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            L10n.tr(
                              context,
                              'shipments.tracking_label',
                              params: {'tracking': shipment!.trackingNumber!},
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TrackingStepper(presentation: presentation),
                        const SizedBox(height: 16),
                        Text(
                          L10n.tr(context, 'track.carrier_timeline'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (carrierEvents.isEmpty)
                          Text(
                            L10n.tr(context, 'track.no_carrier_scans'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          )
                        else
                          ...carrierEvents.map(
                            (event) => ListTile(
                              leading: const Icon(Icons.local_shipping_outlined),
                              title: Text(_eventTitle(context, event)),
                              subtitle: Text(
                                [
                                  if (event.description?.isNotEmpty ?? false)
                                    event.description!,
                                  if (event.at != null)
                                    timeFormat.format(event.at!.toLocal()),
                                ].join(' - '),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                final latest = positions.last;
                final marker = Marker(
                  markerId: const MarkerId('driver'),
                  position: LatLng(latest.lat, latest.lng),
                  rotation: latest.heading ?? 0,
                  infoWindow: InfoWindow(
                    title: L10n.tr(context, 'track.driver'),
                    snippet: latest.updatedAt?.toIso8601String(),
                  ),
                );

                return Scaffold(
                  body: Stack(
                    children: [
                      GoogleMap(
                        myLocationButtonEnabled: false,
                        markers: {marker},
                        initialCameraPosition: CameraPosition(
                          target: LatLng(latest.lat, latest.lng),
                          zoom: 14,
                        ),
                        onMapCreated: (controller) {
                          _controller = controller;
                        },
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 8,
                        left: 8,
                        child: FloatingActionButton.small(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: const Icon(Icons.arrow_back),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: DraggableScrollableSheet(
                          initialChildSize: 0.3,
                          minChildSize: 0.22,
                          maxChildSize: 0.68,
                          builder: (context, controller) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 12,
                                    offset: const Offset(0, -4),
                                  ),
                                ],
                              ),
                              child: ListView(
                                controller: controller,
                                padding: const EdgeInsets.all(16),
                                children: [
                                  Center(
                                    child: Container(
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    L10n.tr(
                                      context,
                                      'track.order_label',
                                      params: {'id': widget.orderId},
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (carrierLine.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      carrierLine,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  TrackingStepper(
                                    presentation: presentation,
                                    compact: true,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${L10n.tr(context, 'track.last_update')}: ${latest.updatedAt?.toLocal()}',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${L10n.tr(context, 'track.position')}: '
                                    '${latest.lat.toStringAsFixed(4)}, ${latest.lng.toStringAsFixed(4)}',
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    L10n.tr(context, 'track.carrier_timeline'),
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  if (carrierEvents.isEmpty)
                                    Text(
                                      L10n.tr(context, 'track.no_carrier_scans'),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    )
                                  else
                                    ...carrierEvents.map(
                                      (event) => ListTile(
                                        leading: const Icon(
                                          Icons.local_shipping_outlined,
                                        ),
                                        title: Text(_eventTitle(context, event)),
                                        subtitle: Text(
                                          [
                                            if (event.description?.isNotEmpty ??
                                                false)
                                              event.description!,
                                            if (event.at != null)
                                              timeFormat.format(
                                                event.at!.toLocal(),
                                              ),
                                          ].join(' - '),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    L10n.tr(context, 'track.driver_timeline'),
                                    style: Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  ...positions.map(
                                    (position) => ListTile(
                                      leading: const Icon(
                                        Icons.navigation_outlined,
                                      ),
                                      title: Text(
                                        '${position.lat.toStringAsFixed(4)}, ${position.lng.toStringAsFixed(4)}',
                                      ),
                                      subtitle: Text(
                                        position.updatedAt?.toLocal().toString() ??
                                            '',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status) {
      case 'pending':
        return L10n.tr(context, 'orders.status_pending');
      case 'paid':
        return L10n.tr(context, 'orders.status_paid');
      case 'shipped':
        return L10n.tr(context, 'tracking.status.in_transit');
      case 'out_for_delivery':
        return L10n.tr(context, 'order.status.out_for_delivery');
      case 'delivered':
        return L10n.tr(context, 'orders.status_delivered');
      case 'cancelled':
        return L10n.tr(context, 'orders.status_cancelled');
      default:
        return status;
    }
  }

  String _eventTitle(BuildContext context, ShipmentEvent event) {
    final i18nKey = event.i18nKey;
    if (i18nKey != null && i18nKey.isNotEmpty) {
      return L10n.tr(context, i18nKey, fallback: event.title);
    }
    final status = event.status;
    if (status != null && status.isNotEmpty) {
      return L10n.tr(context, 'order.status.$status', fallback: event.title);
    }
    return event.title;
  }
}
