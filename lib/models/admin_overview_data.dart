// lib/models/admin_overview_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

List<int> _asIntList(dynamic v, int length) {
  final out = List<int>.filled(length, 0);
  if (v is List) {
    final n = v.length < length ? v.length : length;
    for (var i = 0; i < n; i++) {
      out[i] = _asInt(v[i]);
    }
  }
  return out;
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// Immutable, defensively-parsed snapshot of the admin dashboard.
/// Comes from a single Firestore doc — never from raw log lists.
class AdminOverviewData {
  static const int chartBuckets = 8;

  final int totalEmployees;
  final int activeEmployees;
  final int yesterdayActive;
  final int changePercent;
  final int activePercent;
  final int clockedIn;
  final int lateArrivals;
  final int avgLateMinutes;
  final int outOfRange;
  final int totalAlerts;
  final List<int> chartData;
  final DateTime? updatedAt;

  const AdminOverviewData({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.yesterdayActive,
    required this.changePercent,
    required this.activePercent,
    required this.clockedIn,
    required this.lateArrivals,
    required this.avgLateMinutes,
    required this.outOfRange,
    required this.totalAlerts,
    required this.chartData,
    required this.updatedAt,
  });

  factory AdminOverviewData.empty() => const AdminOverviewData(
    totalEmployees: 0,
    activeEmployees: 0,
    yesterdayActive: 0,
    changePercent: 0,
    activePercent: 0,
    clockedIn: 0,
    lateArrivals: 0,
    avgLateMinutes: 0,
    outOfRange: 0,
    totalAlerts: 0,
    chartData: [0, 0, 0, 0, 0, 0, 0, 0],
    updatedAt: null,
  );

  factory AdminOverviewData.fromMap(Map<String, dynamic> m) {
    final total = _asInt(m['totalEmployees']);
    final active = _asInt(m['activeEmployees']);
    final late = _asInt(m['lateArrivals']);
    final out = _asInt(m['outOfRange']);

    // Recompute derived fields server-side input is already clamped here too.
    final activePercent = total <= 0
        ? 0
        : (((active / total) * 100).round()).clamp(0, 100);

    return AdminOverviewData(
      totalEmployees: total.clamp(0, 1000000),
      activeEmployees: active.clamp(0, 1000000),
      yesterdayActive: _asInt(m['yesterdayActive']).clamp(0, 1000000),
      changePercent: _asInt(m['changePercent']).clamp(-999, 999),
      activePercent: activePercent,
      clockedIn: _asInt(m['clockedIn']).clamp(0, 1000000),
      lateArrivals: late.clamp(0, 1000000),
      avgLateMinutes: _asInt(m['avgLateMinutes']).clamp(0, 24 * 60),
      outOfRange: out.clamp(0, 1000000),
      totalAlerts: _asInt(m['totalAlerts'], late + out).clamp(0, 1000000),
      chartData: _asIntList(m['chartData'], chartBuckets),
      updatedAt: _asDate(m['updatedAt']),
    );
  }
}