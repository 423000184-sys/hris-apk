// lib/services/employee_hours_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'work_hours_service.dart';

/// 🍱 Employee Hours Service
///
/// Computes net work hours para sa ISANG employee lang.
/// Ginagamit sa employee side — dashboard, clock screen, history.
class EmployeeHoursService {
  EmployeeHoursService._();
  static final instance = EmployeeHoursService._();

  final _logsCol = FirebaseFirestore.instance.collection('attendance_logs');

  // ═══════════════════════════════════════════════════════════════
  // TODAY'S HOURS — para sa dashboard/clock screen
  // ═══════════════════════════════════════════════════════════════
  Future<TodayHours> getTodayHours(String employeeId) async {
    if (employeeId.isEmpty) return TodayHours.empty;
    final todayStr = _fmtDate(DateTime.now());

    try {
      final snap = await _logsCol
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: todayStr)
          .get()
          .timeout(const Duration(seconds: 10));

      if (snap.docs.isEmpty) return TodayHours.empty;

      final parsed = snap.docs
          .map((d) => _parseDateTime(d.data()))
          .whereType<DateTime>()
          .toList()
        ..sort();

      if (parsed.isEmpty) return TodayHours.empty;

      // Only clock in — no clock out yet
      if (parsed.length < 2) {
        return TodayHours(
          clockIn: parsed.first,
          clockOut: null,
          rawMinutes: 0,
          lunchMinutes: 0,
          netMinutes: 0,
          overtimeMinutes: 0,
          isComplete: false,
        );
      }

      final clockIn = parsed.first;
      final clockOut = parsed.last;

      final result = await WorkHoursService.instance.compute(
        clockIn: clockIn,
        clockOut: clockOut,
      );

      return TodayHours(
        clockIn: clockIn,
        clockOut: clockOut,
        rawMinutes: result.rawMinutes,
        lunchMinutes: result.lunchDeductionMinutes,
        netMinutes: result.netMinutes,
        overtimeMinutes: result.overtimeMinutes,
        isComplete: true,
      );
    } catch (e) {
      debugPrint('⚠️ [EmpHours] Today error: $e');
      return TodayHours.empty;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // WEEK / MONTH SUMMARY
  // ═══════════════════════════════════════════════════════════════
  Future<PeriodHours> getWeekSummary(String employeeId) async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(
        startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return _computePeriod(employeeId, start, now);
  }

  Future<PeriodHours> getMonthSummary(String employeeId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return _computePeriod(employeeId, start, now);
  }

  Future<PeriodHours> _computePeriod(
      String employeeId,
      DateTime start,
      DateTime end,
      ) async {
    if (employeeId.isEmpty) return PeriodHours.empty;

    try {
      final snap = await _logsCol
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isGreaterThanOrEqualTo: _fmtDate(start))
          .where('date', isLessThanOrEqualTo: _fmtDate(end))
          .get()
          .timeout(const Duration(seconds: 15));

      // Group by date
      final byDate = <String, List<Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final date = (d['date'] ?? '').toString();
        if (date.isEmpty) continue;
        byDate.putIfAbsent(date, () => []).add(d);
      }

      int totalRaw = 0;
      int totalLunch = 0;
      int totalNet = 0;
      int totalOT = 0;
      int days = 0;
      final dailyList = <DailyHours>[];

      for (final entry in byDate.entries) {
        final parsed = entry.value
            .map((d) => _parseDateTime(d))
            .whereType<DateTime>()
            .toList()
          ..sort();

        if (parsed.length < 2) continue;

        final clockIn = parsed.first;
        final clockOut = parsed.last;

        final result = await WorkHoursService.instance.compute(
          clockIn: clockIn,
          clockOut: clockOut,
        );

        if (!result.isValid) continue;

        totalRaw += result.rawMinutes;
        totalLunch += result.lunchDeductionMinutes;
        totalNet += result.netMinutes;
        totalOT += result.overtimeMinutes;
        days++;

        dailyList.add(DailyHours(
          date: entry.key,
          clockIn: clockIn,
          clockOut: clockOut,
          rawMinutes: result.rawMinutes,
          lunchMinutes: result.lunchDeductionMinutes,
          netMinutes: result.netMinutes,
          overtimeMinutes: result.overtimeMinutes,
        ));
      }

      dailyList.sort((a, b) => b.date.compareTo(a.date));

      return PeriodHours(
        rawMinutes: totalRaw,
        lunchMinutes: totalLunch,
        netMinutes: totalNet,
        overtimeMinutes: totalOT,
        daysWithLogs: days,
        dailyBreakdown: dailyList,
      );
    } catch (e) {
      debugPrint('⚠️ [EmpHours] Period error: $e');
      return PeriodHours.empty;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
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

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ═══════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════
class TodayHours {
  final DateTime? clockIn;
  final DateTime? clockOut;
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;
  final bool isComplete;

  const TodayHours({
    required this.clockIn,
    required this.clockOut,
    required this.rawMinutes,
    required this.lunchMinutes,
    required this.netMinutes,
    required this.overtimeMinutes,
    required this.isComplete,
  });

  static const empty = TodayHours(
    clockIn: null,
    clockOut: null,
    rawMinutes: 0,
    lunchMinutes: 0,
    netMinutes: 0,
    overtimeMinutes: 0,
    isComplete: false,
  );

  bool get hasClockedIn => clockIn != null;

  String get rawDisplay => _fmt(rawMinutes);
  String get lunchDisplay => _fmt(lunchMinutes);
  String get netDisplay => _fmt(netMinutes);
  String get overtimeDisplay => _fmt(overtimeMinutes);

  static String _fmt(int m) {
    if (m <= 0) return '0m';
    final h = m ~/ 60;
    final mm = m % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h ${mm}m';
  }
}

class PeriodHours {
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;
  final int daysWithLogs;
  final List<DailyHours> dailyBreakdown;

  const PeriodHours({
    required this.rawMinutes,
    required this.lunchMinutes,
    required this.netMinutes,
    required this.overtimeMinutes,
    required this.daysWithLogs,
    this.dailyBreakdown = const [],
  });

  static const empty = PeriodHours(
    rawMinutes: 0,
    lunchMinutes: 0,
    netMinutes: 0,
    overtimeMinutes: 0,
    daysWithLogs: 0,
    dailyBreakdown: [],
  );

  String get rawDisplay => _fmt(rawMinutes);
  String get lunchDisplay => _fmt(lunchMinutes);
  String get netDisplay => _fmt(netMinutes);
  String get overtimeDisplay => _fmt(overtimeMinutes);

  static String _fmt(int m) {
    if (m <= 0) return '0m';
    final h = m ~/ 60;
    final mm = m % 60;
    if (h == 0) return '${mm}m';
    if (mm == 0) return '${h}h';
    return '${h}h ${mm}m';
  }
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