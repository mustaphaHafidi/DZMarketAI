import 'package:dzmarket/src/models/shipment.dart';
import 'package:dzmarket/src/models/tracking_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending order older than 48h shows label reminder', () {
    final presentation = TrackingPresentation.fromData(
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 50)),
    );

    expect(presentation.currentStep, TrackingStepId.ordered);
    expect(presentation.alert?.messageKey, 'tracking.alert.label_reminder');
  });

  test('pending order older than 72h escalates auto cancel alert', () {
    final presentation = TrackingPresentation.fromData(
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 73)),
    );

    expect(presentation.alert?.messageKey, 'tracking.alert.auto_cancel_soon');
  });

  test('label generated without carrier progress shows dropoff overdue', () {
    final presentation = TrackingPresentation.fromData(
      status: 'shipped',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 97)),
    );

    expect(presentation.currentStep, TrackingStepId.labelReady);
    expect(presentation.alert?.messageKey, 'tracking.alert.dropoff_overdue');
  });

  test('carrier progress event advances shipment to in transit', () {
    final presentation = TrackingPresentation.fromData(
      status: 'shipped',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
      events: [
        ShipmentEvent.fromJson({'status': 'shipped', 'title': 'shipped'}),
      ],
    );

    expect(presentation.currentStep, TrackingStepId.inTransit);
    expect(presentation.alert, isNull);
  });

  test('out for delivery status maps to dedicated step', () {
    final presentation = TrackingPresentation.fromData(
      status: 'out_for_delivery',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 24)),
    );

    expect(presentation.currentStep, TrackingStepId.outForDelivery);
    expect(presentation.displayStatusKey, 'order.status.out_for_delivery');
  });

  test('returned shipment exposes return alert', () {
    final presentation = TrackingPresentation.fromData(
      status: 'returned_to_sender',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    );

    expect(presentation.alert?.messageKey, 'tracking.alert.returned_to_sender');
  });

  test('system reminder event forces reminder alert even before 48h', () {
    final presentation = TrackingPresentation.fromData(
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      systemEventKey: 'order.system.label_reminder',
    );

    expect(presentation.alert?.messageKey, 'tracking.alert.label_reminder');
  });

  test('carrier scan reminder event forces dropoff overdue alert', () {
    final presentation = TrackingPresentation.fromData(
      status: 'shipped',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      systemEventKey: 'order.system.carrier_scan_reminder',
    );

    expect(presentation.alert?.messageKey, 'tracking.alert.dropoff_overdue');
  });

  test('free text out for delivery event maps to dedicated step', () {
    final presentation = TrackingPresentation.fromData(
      status: 'shipped',
      trackingNumber: 'ABC123',
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime.now().subtract(const Duration(hours: 24)),
      events: [
        ShipmentEvent.fromJson({
          'title': 'Out for delivery',
          'description': 'Carrier update',
        }),
      ],
    );

    expect(presentation.currentStep, TrackingStepId.outForDelivery);
    expect(presentation.displayStatusKey, 'order.status.out_for_delivery');
  });

  test('shipment created with validated status stays on label ready step', () {
    final recentCreatedAt = DateTime.now()
        .subtract(const Duration(hours: 12))
        .toUtc()
        .toIso8601String();
    final shipment = Shipment.fromJson({
      'order_id': 142,
      'status': 'validated',
      'tracking_number': 'TRACK-1',
      'label_url': 'https://example.com/label.pdf',
      'created_at': recentCreatedAt,
      'events': [
        {
          'status': 'validated',
          'i18n_key': 'order.status.validated',
          'title': 'Label generated',
          'at': '2026-04-19T10:05:00Z',
        },
      ],
    });

    final presentation = TrackingPresentation.fromShipment(shipment);

    expect(presentation.currentStep, TrackingStepId.labelReady);
    expect(presentation.alert, isNull);
  });
}
