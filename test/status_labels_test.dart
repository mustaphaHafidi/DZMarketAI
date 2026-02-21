import 'package:dzmarket/src/models/offer.dart';
import 'package:dzmarket/src/models/order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Order status label localizes in Arabic', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            const order = Order(
              id: '1',
              productId: 'p1',
              buyerId: 'b1',
              sellerId: 's1',
              status: OrderStatus.paid,
            );
            return Text(order.statusLabel(context));
          },
        ),
      ),
    );

    expect(find.text('مدفوع'), findsOneWidget);
  });

  testWidgets('Offer status label localizes in Arabic', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('fr'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            const offer = Offer(
              id: '1',
              productId: 'p1',
              buyerId: 'b1',
              sellerId: 's1',
              amount: 100,
              status: OfferStatus.accepted,
            );
            return Text(offer.statusLabel(context));
          },
        ),
      ),
    );

    expect(find.text('مقبول'), findsOneWidget);
  });
}
