// lib/security/security_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SecurityUtils {
  /// Safe double conversion + GPS bounds validation.
  static double? safeDouble(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      if (d < -90 || d > 90) return null;
      return d;
    }
    return null;
  }

  static double? safeLng(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return null;
      if (d < -180 || d > 180) return null;
      return d;
    }
    return null;
  }

  static int safeInt(dynamic v, {int fallback = 0}) =>
      v is int ? v : (v is num ? v.toInt() : fallback);

  /// Mask employee name: "Juan Dela Cruz" → "Juan C."
  static String maskName(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Employee';
    if (parts.length == 1) {
      final first = parts.first;
      return first.length <= 1 ? '$first***' : '${first[0]}***';
    }
    return '${parts.first} ${parts.last[0]}.';
  }

  /// Mask employee ID: "abc123xyz" → "ab***yz"
  static String maskId(String id) {
    if (id.length <= 4) return '****';
    return '${id.substring(0, 2)}***${id.substring(id.length - 2)}';
  }

  /// Round distance to nearest 10m for display.
  static String displayDistance(double meters) {
    final rounded = (meters / 10).round() * 10;
    return '${rounded}m';
  }

  static DateTime? toDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is String) return DateTime.tryParse(ts);
    return null;
  }
}