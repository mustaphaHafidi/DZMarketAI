import 'dart:math';

import 'package:dzmarket/src/services/auth_service.dart';
import 'package:dzmarket/src/services/product_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/test_env.dart';
import '../test/test_supabase.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Creates a disposable seller account (same throwaway pattern as
  // auth_flow_test.dart), then a real "vehicles-cars" listing with the
  // vehicle_* fields, verifies the round-trip against the real database,
  // and deletes it. Skips cleanly -- not a failure -- when the
  // "vehicles-cars" category does not exist yet in this environment,
  // which is expected until the vehicle-category migration is applied.
  testWidgets('Vehicles: create + round-trip + cleanup', (tester) async {
    if (!TestEnv.hasSupabaseCreds) {
      return;
    }
    await ensureSupabaseInitialized(
      url: TestEnv.supabaseUrl!,
      anonKey: TestEnv.supabaseAnonKey!,
    );

    final client = Supabase.instance.client;
    final auth = AuthService.instance;

    final rnd = Random().nextInt(1000000);
    final email = 'test+veh$rnd@dzmarket.dev';
    final password = 'Passw0rd!$rnd';
    final signup = await auth.signUp(email, password);
    if (signup.user == null) {
      return;
    }

    try {
      final category = await client
          .from('categories')
          .select('id')
          .eq('slug', 'vehicles-cars')
          .maybeSingle();
      if (category == null) {
        // Expected until the vehicle-category migration is applied.
        return;
      }

      final title = 'TEST vehicule integ $rnd';
      final productService = ProductService();
      await productService.createProduct(
        title: title,
        price: 1800000,
        imageUrls: const [
          'https://api.dzmarket.pro/storage/v1/object/public/products/test/placeholder1.jpg',
          'https://api.dzmarket.pro/storage/v1/object/public/products/test/placeholder2.jpg',
        ],
        categoryId: category['id'].toString(),
        condition: 'used',
        vehicleModel: 'Clio 4',
        vehicleYear: 2015,
        vehicleMileageKm: 120000,
        vehicleFuel: 'diesel',
        vehicleTransmission: 'manual',
        vehicleBodyType: 'hatchback',
        locationWilaya: 'Alger',
        deliveryOptions: const ['pickup'],
      );

      final created = await client
          .from('products')
          .select(
            'id,vehicle_model,vehicle_year,vehicle_mileage_km,'
            'vehicle_fuel,vehicle_transmission,vehicle_body_type',
          )
          .eq('owner_id', client.auth.currentUser!.id)
          .ilike('title', title)
          .maybeSingle();

      expect(created, isNotNull, reason: 'Created vehicle listing not found');
      if (created == null) return;

      expect(created['vehicle_model'], 'Clio 4');
      expect((created['vehicle_year'] as num?)?.toInt(), 2015);
      expect((created['vehicle_mileage_km'] as num?)?.toInt(), 120000);
      expect(created['vehicle_fuel'], 'diesel');
      expect(created['vehicle_transmission'], 'manual');
      expect(created['vehicle_body_type'], 'hatchback');

      await productService.deleteProduct(created['id']);
    } finally {
      await auth.signOut();
    }
  }, skip: !TestEnv.hasSupabaseCreds);
}
