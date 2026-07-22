import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Ported from requestLocationPermission()/reverseGeocode() in
/// main-actions.js. Uses the device GPS (geolocator) instead of the
/// browser's navigator.geolocation, then reverse-geocodes through the
/// same OpenStreetMap Nominatim endpoint the web app uses, so both apps
/// produce the same "City, Country" label.
class LocationService {
  /// Returns a human-readable "City, Country" label, or null if location
  /// couldn't be obtained (permission denied, GPS off, or reverse-geocode
  /// failed with no fallback). Mirrors the try/catch + Addis Ababa
  /// fallback string in the web app.
  static Future<LocationResult?> fetchLocation({required String lang}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );

    final cityName = await _reverseGeocode(pos.latitude, pos.longitude, lang);
    final displayName = cityName ?? (lang == 'am' ? 'አዲስ አበባ, ኢትዮጵያ' : 'Addis Ababa, Ethiopia');

    return LocationResult(
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      cityName: displayName,
    );
  }

  static Future<String?> _reverseGeocode(double lat, double lng, String lang) async {
    try {
      final langParam = lang == 'am' ? 'am,en' : 'en';
      final res = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&accept-language=$langParam'),
        headers: {'Accept-Language': langParam},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map<String, dynamic>?) ?? {};
      final city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '') as String;
      final country = (addr['country'] ?? '') as String;
      if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
      final displayName = (data['display_name'] as String?) ?? '';
      final parts = displayName.split(',').take(2).map((s) => s.trim()).join(', ');
      return parts.isEmpty ? null : parts;
    } catch (_) {
      return null;
    }
  }
}

class LocationResult {
  final double lat;
  final double lng;
  final double accuracy;
  final String cityName;

  LocationResult({required this.lat, required this.lng, required this.accuracy, required this.cityName});

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'cityName': cityName,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
}
