// lib/services/work_hours_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 🍱 Work Hours Service
///
/// Centralized computation ng net working hours — may automatic
/// lunch break deduction.
///
/// Formula:
///   raw = clockOut - clockIn
///   if raw > applyAfterMinutes:
///     net = raw - lunchBreakMinutes
///   else:
///     net = raw
///
///   if !allowOvertime && net > standardWorkMinutes:
///     net = standardWorkMinutes
class WorkHoursService {
  WorkHoursService._();
  static final instance = WorkHoursService._();

  final _configCol = FirebaseFirestore.instance
      .collection('settings')
      .doc('work_hours_config');

  // ─── Cache para hindi laging Firestore read ─────────────────
  WorkHoursConfig _config = const WorkHoursConfig();
  DateTime? _lastFetch;
  static const Duration _cacheTtl = Duration(minutes: 5);

  WorkHoursConfig get cachedConfig => _config;

  // ═══════════════════════════════════════════════════════════════
  // LOAD CONFIG (with cache)
  // ═══════════════════════════════════════════════════════════════
  Future<WorkHoursConfig> loadConfig({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheTtl) {
      return _config;
    }

    try {
      final doc = await _configCol.get();
      if (doc.exists && doc.data() != null) {
        _config = WorkHoursConfig.fromMap(doc.data()!);
        _lastFetch = DateTime.now();
        debugPrint(
            '🍱 [WorkHours] Config loaded — lunch=${_config.lunchBreakMinutes}min, '
                'applyAfter=${_config.applyAfterMinutes}min, '
                'standard=${_config.standardWorkMinutes}min, '
                'allowOT=${_config.allowOvertime}');
      } else {
        // Walang config — gumawa ng default
        await _saveDefaultConfig();
      }
    } catch (e) {
      debugPrint('⚠️ [WorkHours] Load error: $e — using defaults');
    }
    return _config;
  }

  Future<void> _saveDefaultConfig() async {
    try {
      await _configCol.set(_config.toMap());
      _lastFetch = DateTime.now();
      debugPrint('🍱 [WorkHours] Default config saved to Firestore');
    } catch (e) {
      debugPrint('⚠️ [WorkHours] Save default error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UPDATE CONFIG (admin action)
  // ═══════════════════════════════════════════════════════════════
  Future<void> updateConfig(WorkHoursConfig newConfig) async {
    try {
      await _configCol.set(newConfig.toMap(), SetOptions(merge: true));
      _config = newConfig;
      _lastFetch = DateTime.now();
      debugPrint('✅ [WorkHours] Config updated');
    } catch (e) {
      debugPrint('❌ [WorkHours] Update error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MAIN COMPUTATION
  // ═══════════════════════════════════════════════════════════════
  Future<WorkHoursResult> compute({
    required DateTime clockIn,
    required DateTime clockOut,
    int? overrideLunchBreakMinutes,
  }) async {
    await loadConfig();

    // Handle invalid input
    if (clockOut.isBefore(clockIn)) {
      return WorkHoursResult(
        clockIn: clockIn,
        clockOut: clockOut,
        rawMinutes: 0,
        lunchDeductionMinutes: 0,
        overtimeMinutes: 0,
        netMinutes: 0,
        isValid: false,
        note: 'Clock out is before clock in',
      );
    }

    final rawMinutes = clockOut.difference(clockIn).inMinutes;

    // Determine lunch deduction
    final lunchMinutes =
        overrideLunchBreakMinutes ?? _config.lunchBreakMinutes;
    final appliesLunch = rawMinutes >= _config.applyAfterMinutes;
    final lunchDeduction = appliesLunch ? lunchMinutes : 0;

    var netMinutes = rawMinutes - lunchDeduction;
    if (netMinutes < 0) netMinutes = 0;

    // Handle overtime cap
    int overtimeMinutes = 0;
    if (netMinutes > _config.standardWorkMinutes) {
      overtimeMinutes = netMinutes - _config.standardWorkMinutes;
      if (!_config.allowOvertime) {
        netMinutes = _config.standardWorkMinutes;
      }
    }

    return WorkHoursResult(
      clockIn: clockIn,
      clockOut: clockOut,
      rawMinutes: rawMinutes,
      lunchDeductionMinutes: lunchDeduction,
      overtimeMinutes: overtimeMinutes,
      netMinutes: netMinutes,
      isValid: true,
      note: appliesLunch
          ? 'Lunch break deducted (${lunchMinutes}min)'
          : 'No lunch deducted (raw < ${_config.applyAfterMinutes}min)',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPER — para sa formatting
  // ═══════════════════════════════════════════════════════════════
  String formatHours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  /// Compute salary from net minutes
  double computeSalary({
    required int netMinutes,
    required double hourlyRate,
  }) {
    return (netMinutes / 60.0) * hourlyRate;
  }
}

// ═══════════════════════════════════════════════════════════════
// CONFIG MODEL
// ═══════════════════════════════════════════════════════════════
class WorkHoursConfig {
  final int lunchBreakMinutes;
  final int applyAfterMinutes;
  final int standardWorkMinutes;
  final bool allowOvertime;

  const WorkHoursConfig({
    this.lunchBreakMinutes = 60,      // 1 hour default
    this.applyAfterMinutes = 360,     // apply after 6 hours
    this.standardWorkMinutes = 480,   // 8 hours standard
    this.allowOvertime = true,        // pay extra kung OT
  });

  factory WorkHoursConfig.fromMap(Map<String, dynamic> map) {
    return WorkHoursConfig(
      lunchBreakMinutes: (map['lunchBreakMinutes'] as num?)?.toInt() ?? 60,
      applyAfterMinutes: (map['applyAfterMinutes'] as num?)?.toInt() ?? 360,
      standardWorkMinutes:
      (map['standardWorkMinutes'] as num?)?.toInt() ?? 480,
      allowOvertime: map['allowOvertime'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'lunchBreakMinutes': lunchBreakMinutes,
    'applyAfterMinutes': applyAfterMinutes,
    'standardWorkMinutes': standardWorkMinutes,
    'allowOvertime': allowOvertime,
  };

  WorkHoursConfig copyWith({
    int? lunchBreakMinutes,
    int? applyAfterMinutes,
    int? standardWorkMinutes,
    bool? allowOvertime,
  }) {
    return WorkHoursConfig(
      lunchBreakMinutes: lunchBreakMinutes ?? this.lunchBreakMinutes,
      applyAfterMinutes: applyAfterMinutes ?? this.applyAfterMinutes,
      standardWorkMinutes: standardWorkMinutes ?? this.standardWorkMinutes,
      allowOvertime: allowOvertime ?? this.allowOvertime,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// RESULT MODEL
// ═══════════════════════════════════════════════════════════════
class WorkHoursResult {
  final DateTime clockIn;
  final DateTime clockOut;
  final int rawMinutes;
  final int lunchDeductionMinutes;
  final int overtimeMinutes;
  final int netMinutes;
  final bool isValid;
  final String note;

  const WorkHoursResult({
    required this.clockIn,
    required this.clockOut,
    required this.rawMinutes,
    required this.lunchDeductionMinutes,
    required this.overtimeMinutes,
    required this.netMinutes,
    required this.isValid,
    required this.note,
  });

  // Display helpers
  String get rawDisplay => _fmt(rawMinutes);
  String get lunchDisplay => _fmt(lunchDeductionMinutes);
  String get overtimeDisplay => _fmt(overtimeMinutes);
  String get netDisplay => _fmt(netMinutes);

  static String _fmt(int m) {
    if (m == 0) return '0m';
    final h = m ~/ 60;
    final min = m % 60;
    if (h == 0) return '${min}m';
    if (min == 0) return '${h}h';
    return '${h}h ${min}m';
  }
}