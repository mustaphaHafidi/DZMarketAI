import 'package:dzmarket/src/models/shipment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ShipmentEvent parses tracking metadata fields', () {
    final event = ShipmentEvent.fromJson({
      'key': 'status:out_for_delivery',
      'status': 'out_for_delivery',
      'i18n_key': 'order.status.out_for_delivery',
      'title': 'Out for delivery',
      'description': 'Carrier update',
      'at': '2026-04-19T12:30:00Z',
    });

    expect(event.key, 'status:out_for_delivery');
    expect(event.status, 'out_for_delivery');
    expect(event.i18nKey, 'order.status.out_for_delivery');
    expect(event.title, 'Out for delivery');
    expect(event.description, 'Carrier update');
    expect(event.at?.toUtc().toIso8601String(), '2026-04-19T12:30:00.000Z');
  });

  test('Shipment parses createdAt and events with localized status fields', () {
    final shipment = Shipment.fromJson({
      'order_id': 140,
      'tracking_number': 'yal-YF22HF',
      'label_url': 'https://example.com/label.pdf',
      'status': 'shipped',
      'carrier': 'Yalidine Express',
      'option': 'home',
      'delivery_mode': 'delivery',
      'created_at': '2026-04-19T10:00:00Z',
      'events': [
        {
          'key': 'status:validated',
          'status': 'validated',
          'i18n_key': 'order.status.validated',
          'title': 'Label generated',
          'at': '2026-04-19T10:05:00Z',
        },
      ],
    });

    expect(shipment.orderId, '140');
    expect(shipment.status, 'shipped');
    expect(
      shipment.createdAt?.toUtc().toIso8601String(),
      '2026-04-19T10:00:00.000Z',
    );
    expect(shipment.events, hasLength(1));
    expect(shipment.events.first.status, 'validated');
    expect(shipment.events.first.i18nKey, 'order.status.validated');
  });
}
