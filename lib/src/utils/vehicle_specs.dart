import 'package:dzmarket/src/services/i18n.dart';
import 'package:flutter/widgets.dart';

/// Shared codes/labels for the "Vehicules" category tree, reused by the
/// listing creation form, the browse filters, and the product detail page.
class VehicleSpecs {
  static const List<String> fuels = [
    'petrol',
    'diesel',
    'gpl',
    'electric',
    'hybrid',
  ];

  static const List<String> transmissions = ['manual', 'automatic'];

  static const List<String> bodyTypes = [
    'sedan',
    'suv',
    'hatchback',
    'utility',
    'motorcycle',
  ];

  /// True when [categorySlug] is the root "vehicles" category or one of its
  /// children (slugs are seeded as `vehicles-*`, see the DB migration).
  static bool isVehicleCategory(String? categorySlug) {
    if (categorySlug == null || categorySlug.isEmpty) return false;
    return categorySlug == 'vehicles' || categorySlug.startsWith('vehicles-');
  }

  static bool supportsRoadSpecs(String? categorySlug) {
    return categorySlug == 'vehicles-cars' ||
        categorySlug == 'vehicles-motorcycles' ||
        categorySlug == 'vehicles-utility' ||
        categorySlug == 'vehicles-trucks';
  }

  static bool supportsBodyType(String? categorySlug) {
    return categorySlug == 'vehicles-cars' ||
        categorySlug == 'vehicles-utility' ||
        categorySlug == 'vehicles-trucks';
  }

  static String fuelLabel(BuildContext context, String value) {
    return L10n.tr(context, 'vehicle.fuel.$value', fallback: value);
  }

  static String transmissionLabel(BuildContext context, String value) {
    return L10n.tr(context, 'vehicle.transmission.$value', fallback: value);
  }

  static String bodyTypeLabel(BuildContext context, String value) {
    return L10n.tr(context, 'vehicle.body.$value', fallback: value);
  }
}
