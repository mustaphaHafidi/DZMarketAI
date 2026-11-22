import 'package:dzmarket/src/features/profile/edit_product_page.dart';
import 'package:dzmarket/src/models/product.dart';
import 'package:dzmarket/src/services/i18n.dart';
import 'package:dzmarket/src/services/locale_service.dart';
import 'package:dzmarket/src/services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Product _product({required String categorySlug}) {
  return Product(
    id: 'listing-1',
    title: 'Grand i10',
    price: 1500000,
    ownerId: 'owner-1',
    categorySlug: categorySlug,
    category: categorySlug,
    brand: 'Hyundai',
    vehicleModel: 'Grand i10',
    vehicleYear: 2019,
    vehicleMileageKm: 85000,
    vehicleFuel: 'petrol',
    vehicleTransmission: 'manual',
    vehicleBodyType: 'hatchback',
    vehicleEngine: '1.2',
    vehiclePowerHp: 84,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await TranslationService.instance.load();
  });

  setUp(() {
    LocaleService.instance.locale.value = const Locale('fr');
  });

  testWidgets('vehicle edit shows vehicle fields and hides parcel controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditProductPage(product: _product(categorySlug: 'vehicles-cars')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.stock_label'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.size_label'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.vehicle_contact_phone_toggle'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    // The form grew taller (category picker + optional phone toggle), so the
    // vehicle-specific fields under test now sit past the initial viewport/
    // cache extent and need an incremental scroll to be mounted.
    final vehicleSectionFinder = find.text(
      L10n.trLocale('fr', 'listing.add.vehicle_section_title'),
      skipOffstage: false,
    );
    await tester.dragUntilVisible(
      vehicleSectionFinder,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(vehicleSectionFinder, findsOneWidget);
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.model_label'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.year_label'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.mileage_label'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.stock_label'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.size_label'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('standard edit keeps parcel controls and hides vehicle fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditProductPage(product: _product(categorySlug: 'electronics')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.vehicle_section_title'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.stock_label'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    // The form grew taller (category picker + optional phone toggle), so the
    // size field and parcel controls under test now sit past the initial
    // viewport/cache extent and need an incremental scroll to be mounted.
    final sizeLabelFinder = find.text(
      L10n.trLocale('fr', 'listing.add.size_label'),
      skipOffstage: false,
    );
    await tester.dragUntilVisible(
      sizeLabelFinder,
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(sizeLabelFinder, findsOneWidget);
    await tester.dragUntilVisible(
      find.byType(CheckboxListTile),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(
      find.text(
        L10n.trLocale('fr', 'listing.add.vehicle_contact_phone_toggle'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });
}
