import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/models/buyer_return_stats.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/buyer_return_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOrderService extends OrderService {
  _FakeOrderService(this.orders);

  final List<Order> orders;

  @override
  Stream<List<Order>> streamOrdersForUser(String userId) =>
      Stream.value(orders);

  @override
  Future<void> refreshOrders(String userId) async {}
}

class _FakeBuyerReturnService extends BuyerReturnService {
  _FakeBuyerReturnService(this.stats);

  final Map<String, BuyerReturnStats> stats;

  @override
  Future<Map<String, BuyerReturnStats>> fetchForSeller() async => stats;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seller order card shows DZMarket returns summary and PDF note', (
    tester,
  ) async {
    final order = Order(
      id: 'order-1',
      productId: 'product-1',
      buyerId: 'buyer-1',
      sellerId: 'seller-1',
      status: OrderStatus.shipped,
      labelUrl: 'https://example.com/label.pdf',
      createdAt: DateTime(2026, 4, 19),
      productTitle: 'Chaussures',
      productPrice: 3200,
    );
    final stats = BuyerReturnStats(
      buyerId: 'buyer-1',
      returns6m: 1,
      returns12m: 2,
      lastReturnAt: DateTime(2026, 4, 10),
      lastReturnCourier: 'Yalidine',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        home: SellerOrdersPage(
          orderService: _FakeOrderService([order]),
          buyerReturnService: _FakeBuyerReturnService({'buyer-1': stats}),
          userIdOverride: 'seller-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Historique retours DZMarket'), findsOneWidget);
    expect(
      find.textContaining('Retours DZMarket : 1 sur 6 mois'),
      findsOneWidget,
    );
    expect(
      find.text('Basé uniquement sur les commandes passées sur DZMarket.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Le bordereau reste disponible pendant 6 mois'),
      findsOneWidget,
    );
  });
}
