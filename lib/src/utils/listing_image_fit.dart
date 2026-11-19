import 'package:dzmarket/src/utils/vehicle_specs.dart';
import 'package:flutter/painting.dart';

/// Keep the whole vehicle visible in fixed-ratio listing surfaces.
BoxFit listingImageFit(String? categorySlug) {
  return VehicleSpecs.isVehicleCategory(categorySlug)
      ? BoxFit.contain
      : BoxFit.cover;
}
