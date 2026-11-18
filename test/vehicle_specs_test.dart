import 'package:dzmarket/src/utils/vehicle_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VehicleSpecs.isVehicleCategory', () {
    test('true for the root vehicles category', () {
      expect(VehicleSpecs.isVehicleCategory('vehicles'), isTrue);
    });

    test('true for any vehicles-* child slug', () {
      expect(VehicleSpecs.isVehicleCategory('vehicles-cars'), isTrue);
      expect(VehicleSpecs.isVehicleCategory('vehicles-motorcycles'), isTrue);
      expect(VehicleSpecs.isVehicleCategory('vehicles-utility'), isTrue);
      expect(VehicleSpecs.isVehicleCategory('vehicles-trucks'), isTrue);
      expect(VehicleSpecs.isVehicleCategory('vehicles-equipment'), isTrue);
      expect(VehicleSpecs.isVehicleCategory('vehicles-boats'), isTrue);
    });

    test('false for unrelated categories', () {
      expect(VehicleSpecs.isVehicleCategory('fashion'), isFalse);
      expect(VehicleSpecs.isVehicleCategory('electronics'), isFalse);
      // Must not match on a loose substring, only the dedicated prefix.
      expect(VehicleSpecs.isVehicleCategory('non-vehicles-shop'), isFalse);
    });

    test('false for null or empty slug', () {
      expect(VehicleSpecs.isVehicleCategory(null), isFalse);
      expect(VehicleSpecs.isVehicleCategory(''), isFalse);
    });
  });

  group('VehicleSpecs code lists', () {
    test('fuels/transmissions/bodyTypes are non-empty with no duplicates', () {
      for (final list in [
        VehicleSpecs.fuels,
        VehicleSpecs.transmissions,
        VehicleSpecs.bodyTypes,
      ]) {
        expect(list, isNotEmpty);
        expect(list.toSet().length, list.length);
      }
    });
  });
}
