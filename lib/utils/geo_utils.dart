// lib/utils/geo_utils.dart
// ═══════════════════════════════════════════════════════════════════
// GEO UTILITIES — Accurate Haversine distance + validation
// ═══════════════════════════════════════════════════════════════════
import 'dart:math' as math;

class GeoUtils {
  GeoUtils._();

  static const double earthRadiusMeters = 6371000.0; // WGS-84 mean

  /// ✅ HAVERSINE — accurate distance sa meters (great-circle)
  static double haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static bool isValidLat(double v) => v >= -90.0 && v <= 90.0 && v.isFinite;
  static bool isValidLng(double v) =>
      v >= -180.0 && v <= 180.0 && v.isFinite;
  static bool isValidRadius(double v) =>
      v >= 20.0 && v <= 5000.0 && v.isFinite;

  /// Effective radius = base radius + GPS accuracy buffer (max 50m)
  static double effectiveRadius(double radius, double gpsAccuracy) {
    final buffer = gpsAccuracy.isFinite ? gpsAccuracy.clamp(0.0, 50.0) : 0.0;
    return radius + buffer;
  }
}