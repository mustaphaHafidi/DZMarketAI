import 'package:dzmarket/src/features/listings/interest_ranking.dart';
import 'package:dzmarket/src/features/listings/listings_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Product _product(String id, {String? categoryId}) => Product(
  id: id,
  title: 'Produit $id',
  price: 1000,
  ownerId: 'owner-$id',
  categoryId: categoryId,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        anonKey: 'test',
      );
    }
  });

  testWidgets(
    'Listings page: no "Selon vos interets" section for a signed-out visitor',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ListingsPage()));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // No saved searches / favorites signal is possible while signed out,
      // so the discovery section must stay hidden and default behavior
      // (guest browse banner) must still render exactly as before.
      expect(find.text('Selon vos intérêts'), findsNothing);
      expect(
        find.text('Parcourez librement. Connectez-vous pour agir.'),
        findsOneWidget,
      );

      // The old visible "Selon vos intérêts" row/dismiss button must not
      // exist for any user state: there is no widget left in the tree that
      // can render it anymore, signed in or not.
      expect(find.text('Masquer'), findsNothing);
    },
  );

  testWidgets(
    'Listings page: browseResetSignal listener is wired and disposed safely',
    (tester) async {
      final resetSignal = ValueNotifier<int>(0);
      await tester.pumpWidget(
        MaterialApp(home: ListingsPage(browseResetSignal: resetSignal)),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Re-tapping the already-active Browse tab fires this signal; with
      // nothing to reset (signed-out, no favorites-only mode) it must be
      // a no-op, never a crash.
      resetSignal.value++;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Disposing the page must not leave a dangling listener on the
      // shared notifier (the exact bug this fix could silently reintroduce).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      resetSignal.value++;
      expect(tester.takeException(), isNull);
    },
  );

  group('applyInterestRanking', () {
    test('no interest detected: order unchanged', () {
      final products = [_product('1'), _product('2', categoryId: 'shoes')];
      final result = applyInterestRanking(
        products,
        interestCategoryId: null,
        hasActiveUserFilters: false,
      );
      expect(result, same(products));
    });

    test(
      'interest detected, no active filters: matching listings move to the '
      'front, none removed, relative order kept within each group',
      () {
        final shoe1 = _product('shoe-1', categoryId: 'shoes');
        final bag1 = _product('bag-1', categoryId: 'bags');
        final shoe2 = _product('shoe-2', categoryId: 'shoes');
        final bag2 = _product('bag-2', categoryId: 'bags');
        final products = [bag1, shoe1, bag2, shoe2];

        final result = applyInterestRanking(
          products,
          interestCategoryId: 'shoes',
          hasActiveUserFilters: false,
        );

        expect(result, [shoe1, shoe2, bag1, bag2]);
        expect(result.toSet(), products.toSet());
      },
    );

    test(
      'active search/filter/sort takes priority: interest never overrides it',
      () {
        final products = [
          _product('bag-1', categoryId: 'bags'),
          _product('shoe-1', categoryId: 'shoes'),
        ];
        final result = applyInterestRanking(
          products,
          interestCategoryId: 'shoes',
          hasActiveUserFilters: true,
        );
        expect(result, same(products));
      },
    );

    test(
      'already-favorited listing is never boosted, even if its category '
      'matches: it stays with the rest, in its original relative order',
      () {
        final shoe1 = _product('shoe-1', categoryId: 'shoes');
        final shoeFav = _product('shoe-fav', categoryId: 'shoes');
        final bag1 = _product('bag-1', categoryId: 'bags');
        final products = [bag1, shoeFav, shoe1];

        final result = applyInterestRanking(
          products,
          interestCategoryId: 'shoes',
          hasActiveUserFilters: false,
          favoriteIds: {'shoe-fav'},
        );

        expect(result, [shoe1, bag1, shoeFav]);
        expect(result.toSet(), products.toSet());
      },
    );
  });
}
