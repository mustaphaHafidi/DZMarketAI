import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final instance = LocationService._();

  Future<LocationData?> fetchLocation() async {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) return null;
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    String? wilaya;
    String? daira;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        wilaya = p.administrativeArea?.isNotEmpty == true
            ? p.administrativeArea
            : p.subAdministrativeArea;
        daira = p.locality?.isNotEmpty == true ? p.locality : p.subLocality;
      }
    } catch (_) {
      // Ignore reverse geocoding failure; we still keep coordinates.
    }
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      wilaya: wilaya,
      daira: daira,
    );
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    this.wilaya,
    this.daira,
  });

  final double latitude;
  final double longitude;
  final String? wilaya;
  final String? daira;
}
