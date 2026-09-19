// lib/services/attendance_hours_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'work_hours_service.dart';

/// 🍱 Attendance Hours Service
///
/// Compute hours summary per employee from attendance logs:
///   • Raw minutes (clockOut - clockIn per day)
///   • Lunch deducted (via WorkHoursService rules)
///   • Net minutes (raw - lunch)
///   • Overtime minutes (net > standard)
class AttendanceHoursService {
  AttendanceHoursService._();
  static final instance = AttendanceHoursService._();

  final _logsCol = FirebaseFirestore.instance.collection('attendance_logs');

  /// Fetch hours summary for ALL employees in the period
  Future<Map<String, EmployeeHoursSummary>> fetchHoursMap({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      final snap = await _logsCol
          .where('date',
          isGreaterThanOrEqualTo: _fmtDate(periodStart))
          .where('date', isLessThanOrEqualTo: _fmtDate(periodEnd))
          .get();

      debugPrint(
          '🍱 [HoursService] Fetched ${snap.docs.length} attendance logs');

      // Group by employeeId + date
      final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};

      for (final doc in snap.docs) {
        final d = doc.data();
        final empId = (d['employee_id'] ?? d['employeeId'] ?? '').toString();
        final date = (d['date'] ?? '').toString();
        if (empId.isEmpty || date.isEmpty) continue;

        grouped.putIfAbsent(empId, () => {});
        grouped[empId]!.putIfAbsent(date, () => []);
        grouped[empId]![date]!.add(d);
      }

      // Compute per employee
      final result = <String, EmployeeHoursSummary>{};
      for (final entry in grouped.entries) {
        result[entry.key] = await _computeForEmployee(entry.value);
      }

      debugPrint(
          '🍱 [HoursService] Computed for ${result.length} employees');
      return result;
    } catch (e) {
      debugPrint('❌ [HoursService] Fetch error: $e');
      return {};
    }
  }

  /// Compute summary from grouped logs (date → logs)
  Future<EmployeeHoursSummary> _computeForEmployee(
      Map<String, List<Map<String, dynamic>>> byDate,
      ) async {
    int totalRaw = 0;
    int totalLunch = 0;
    int totalNet = 0;
    int totalOT = 0;
    int daysWithLogs = 0;
    int daysWithLunchApplied = 0;
    final dailyBreakdown = <DailyHours>[];

    for (final entry in byDate.entries) {
      final dateStr = entry.key;
      final logs = entry.value;

      final parsed = _pairInOut(logs);
      if (parsed == null) continue;

      final clockIn = parsed.$1;
      final clockOut = parsed.$2;

      final result = await WorkHoursService.instance.compute(
        clockIn: clockIn,
        clockOut: clockOut,
      );

      if (!result.isValid) continue;

      totalRaw += result.rawMinutes;
      totalLunch += result.lunchDeductionMinutes;
      totalNet += result.netMinutes;
      totalOT += result.overtimeMinutes;
      daysWithLogs++;
      if (result.lunchDeductionMinutes > 0) daysWithLunchApplied++;

      dailyBreakdown.add(DailyHours(
        date: dateStr,
        clockIn: clockIn,
        clockOut: clockOut,
        rawMinutes: result.rawMinutes,
        lunchMinutes: result.lunchDeductionMinutes,
        netMinutes: result.netMinutes,
        overtimeMinutes: result.overtimeMinutes,
      ));
    }

    // Sort by date descending
    dailyBreakdown.sort((a, b) => b.date.compareTo(a.date));

    return EmployeeHoursSummary(
      totalRawMinutes: totalRaw,
      totalLunchDeductedMinutes: totalLunch,
      totalNetMinutes: totalNet,
      totalOvertimeMinutes: totalOT,
      daysWithLogs: daysWithLogs,
      daysWithLunchApplied: daysWithLunchApplied,
      dailyBreakdown: dailyBreakdown,
    );
  }

  /// Pair first IN with last OUT per day
  (DateTime, DateTime)? _pairInOut(List<Map<String, dynamic>> logs) {
    final parsed = logs
        .map((d) => _parseDateTime(d))
        .whereType<DateTime>()
        .toList()
      ..sort();

    if (parsed.length < 2) return null;

    // Simple: first = IN, last = OUT
    return (parsed.first, parsed.last);
  }

  DateTime? _parseDateTime(Map<String, dynamic> d) {
    final ts = d['timestamp'];
    if (ts is Timestamp) return ts.toDate().toLocal();

    final dateStr = d['date']?.toString();
    final timeStr = d['time']?.toString();
    if (dateStr == null || timeStr == null) return null;

    try {
      return DateTime.parse('${dateStr}T$timeStr');
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════
class EmployeeHoursSummary {
  final int totalRawMinutes;
  final int totalLunchDeductedMinutes;
  final int totalNetMinutes;
  final int totalOvertimeMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;
  final List<DailyHours> dailyBreakdown;

  const EmployeeHoursSummary({
    required this.totalRawMinutes,
    required this.totalLunchDeductedMinutes,
    required this.totalNetMinutes,
    required this.totalOvertimeMinutes,
    required this.daysWithLogs,
    required this.daysWithLunchApplied,
    required this.dailyBreakdown,
  });

  static const empty = EmployeeHoursSummary(
    totalRawMinutes: 0,
    totalLunchDeductedMinutes: 0,
    totalNetMinutes: 0,
    totalOvertimeMinutes: 0,
    daysWithLogs: 0,
    daysWithLunchApplied: 0,
    dailyBreakdown: [],
  );

  String fmt(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String get rawDisplay => fmt(totalRawMinutes);
  String get lunchDisplay => fmt(totalLunchDeductedMinutes);
  String get netDisplay => fmt(totalNetMinutes);
  String get overtimeDisplay => fmt(totalOvertimeMinutes);
}

class DailyHours {
  final String date;
  final DateTime clockIn;
  final DateTime clockOut;
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;

  const DailyHours({
    required this.date,
    required this.clockIn,
    required this.clockOut,
    required this.rawMinutes,
    required this.lunchMinutes,
    required this.netMinutes,
    required this.overtimeMinutes,
  });
}