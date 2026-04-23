import 'package:dzmarket/src/features/orders/seller_orders_page.dart';
import 'package:dzmarket/src/models/buyer_return_stats.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:dzmarket/src/services/buyer_return_service.dart';
import 'package:dzmarket/src/services/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

class _FakeOrderService extends OrderService {
  _FakeOrderService(this.orders) {
    _controller.onListen = () {
      _controller.add(List<Order>.from(orders));
    };
  }

  final List<Order> orders;
  final StreamController<List<Order>> _controller =
      StreamController<List<Order>>.broadcast();

  @override
  Stream<List<Order>> streamOrdersForUser(String userId) => _controller.stream;

  @override
  Future<void> refreshOrders(String userId) async {}

  @override
  Future<void> cancelOrderBySeller({required String orderId}) async {
    orders.removeWhere((order) => order.id == orderId);
    _controller.add(List<Order>.from(orders));
  }
}

class _FakeBuyerReturnService extends BuyerReturnService {
  _FakeBuyerReturnService(this.stats);

  final Map<String, BuyerReturnStats> stats;

  @override
  Future<Map<String, BuyerReturnStats>> fetchForSeller() async => stats;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MaterialApp wrapApp({
    required Locale locale,
    required Widget child,
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );
  }

  Order pendingOrder() => Order(
    id: 'order-pending',
    productId: 'product-1',
    buyerId: 'buyer-1',
    sellerId: 'seller-1',
    status: OrderStatus.pending,
    createdAt: DateTime(2026, 4, 23),
    productTitle: 'Produit 45',
    productPrice: 40000,
    courierName: 'Yalidine Express',
    shippingOption: 'home',
  );

  testWidgets('pending seller order shows cancel action in French', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('fr'),
        child: SellerOrdersPage(
          orderService: _FakeOrderService([pendingOrder()]),
          buyerReturnService: _FakeBuyerReturnService(const {}),
          userIdOverride: 'seller-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Supprimer'), findsNothing);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(find.text('Annuler la commande'), findsOneWidget);
    expect(
      find.text(
        "Cette action annulera la commande et informera l'acheteur.",
      ),
      findsOneWidget,
    );
    expect(find.text("Confirmer l'annulation"), findsOneWidget);
  });

  testWidgets('pending seller order shows cancel dialog in Arabic', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('ar'),
        child: SellerOrdersPage(
          orderService: _FakeOrderService([pendingOrder()]),
          buyerReturnService: _FakeBuyerReturnService(const {}),
          userIdOverride: 'seller-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Supprimer'), findsNothing);

    final cancelButtons = find.byWidgetPredicate(
      (widget) => widget is Text && widget.data == 'إلغاء',
    );
    expect(cancelButtons, findsOneWidget);

    await tester.tap(cancelButtons);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'إلغاء الطلب',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'تأكيد الإلغاء',
      ),
      findsOneWidget,
    );
  });

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
      wrapApp(
        locale: const Locale('fr'),
        child: SellerOrdersPage(
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
    expect(find.textContaining('DZMarket'), findsWidgets);
    expect(
      find.textContaining('Le bordereau reste disponible pendant 6 mois'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling a seller order removes it from the list immediately', (
    tester,
  ) async {
    final service = _FakeOrderService([pendingOrder()]);

    await tester.pumpWidget(
      wrapApp(
        locale: const Locale('fr'),
        child: SellerOrdersPage(
          orderService: service,
          buyerReturnService: _FakeBuyerReturnService(const {}),
          userIdOverride: 'seller-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Produit 45'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Confirmer l'annulation"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Produit 45'), findsNothing);
    expect(
      find.text("Commande annulée. L'acheteur a été informé."),
      findsOneWidget,
    );
  });
}
