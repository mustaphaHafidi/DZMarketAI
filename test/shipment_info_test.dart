import 'package:dzmarket/src/features/orders/widgets/shipment_info.dart';
import 'package:dzmarket/src/services/shipping_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shipment info renders arranged delivery card instead of tracking stepper',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          home: Scaffold(
            body: ShipmentInfo(
              orderId: 'order-1',
              service: ShippingService(),
              deliveryMethod: 'pickup',
              shippingOption: 'pickup',
            ),
          ),
        ),
      );

      expect(find.text('Livraison a convenir'), findsOneWidget);
      expect(
        find.text(
          'Le vendeur confirmera les details de remise via le chat. Aucun bordereau automatique.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.handshake_outlined), findsOneWidget);
    },
  );
}
