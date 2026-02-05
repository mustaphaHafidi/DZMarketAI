import 'package:dzmarket/src/models/driver_position.dart';
import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/services/driver_service.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:dzmarket/src/services/i18n.dart';
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
    return Scaffold(
      body: StreamBuilder<List<DriverPosition>>(
        stream: DriverService().streamPositions(widget.orderId),
        builder: (context, snapshot) {
          final positions = snapshot.data ?? const [];

          return StreamBuilder<Shipment?>(
            stream: ShippingService().streamShipment(widget.orderId),
            builder: (context, shipmentSnap) {
              final shipment = shipmentSnap.data;

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
                  body: Center(
                    child: Text(L10n.tr(context, 'track.waiting')),
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

              final carrierLine = [
                if (shipment?.carrier?.isNotEmpty ?? false) shipment!.carrier!,
                if (shipment?.option?.isNotEmpty ?? false) shipment!.option!,
              ].join(' Â· ');

              final carrierEvents = shipment?.events ?? const <ShipmentEvent>[];

              return Stack(
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
                                L10n.tr(context, 'track.order_label', params: {'id': widget.orderId}),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (carrierLine.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  carrierLine,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                ),
                              ],
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                  ),
                                )
                              else
                                ...carrierEvents.map(
                                  (e) => ListTile(
                                    leading: const Icon(
                                      Icons.local_shipping_outlined,
                                    ),
                                    title: Text(e.title),
                                    subtitle: Text([
                                      if (e.description?.isNotEmpty ?? false)
                                        e.description!,
                                      if (e.at != null)
                                        timeFormat.format(e.at!.toLocal()),
                                    ].join(' Â· ')),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                L10n.tr(context, 'track.driver_timeline'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              ...positions.map(
                                (p) => ListTile(
                                  leading: const Icon(
                                    Icons.navigation_outlined,
                                  ),
                                  title: Text(
                                    '${p.lat.toStringAsFixed(4)}, ${p.lng.toStringAsFixed(4)}',
                                  ),
                                  subtitle: Text(
                                    p.updatedAt?.toLocal().toString() ?? '',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: Text(L10n.tr(context, 'cta.chat')),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(Icons.refresh),
                                    label: Text(L10n.tr(context, 'cta.refresh')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}




