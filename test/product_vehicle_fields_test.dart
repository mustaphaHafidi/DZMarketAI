import 'package:dzmarket/src/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Product.fromJson vehicle fields', () {
    test('parses all vehicle_* columns when present', () {
      final product = Product.fromJson({
        'id': '1',
        'title': 'Golf 7',
        'price': 2500000,
        'owner_id': 'owner-1',
        'vehicle_model': 'Golf 7',
        'vehicle_year': 2019,
        'vehicle_mileage_km': 85000,
        'vehicle_fuel': 'diesel',
        'vehicle_transmission': 'manual',
        'vehicle_body_type': 'hatchback',
        'vehicle_engine': '1.5 dCi',
        'vehicle_power_hp': 90,
        'contact_phone': '+213555010203',
      });

      expect(product.vehicleModel, 'Golf 7');
      expect(product.vehicleYear, 2019);
      expect(product.vehicleMileageKm, 85000);
      expect(product.vehicleFuel, 'diesel');
      expect(product.vehicleTransmission, 'manual');
      expect(product.vehicleBodyType, 'hatchback');
      expect(product.vehicleEngine, '1.5 dCi');
      expect(product.vehiclePowerHp, 90);
      expect(product.contactPhone, '+213555010203');
    });

    test(
      'defaults every vehicle_* field to null for a non-vehicle listing',
      () {
        final product = Product.fromJson({
          'id': '2',
          'title': 'Robe',
          'price': 3500,
          'owner_id': 'owner-2',
        });

        expect(product.vehicleModel, isNull);
        expect(product.vehicleYear, isNull);
        expect(product.vehicleMileageKm, isNull);
        expect(product.vehicleFuel, isNull);
        expect(product.vehicleTransmission, isNull);
        expect(product.vehicleBodyType, isNull);
        expect(product.vehicleEngine, isNull);
        expect(product.vehiclePowerHp, isNull);
        expect(product.contactPhone, isNull);
      },
    );
  });
}
