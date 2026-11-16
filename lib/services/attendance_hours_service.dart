// lib/services/attendance_hours_service.dart
// v2: 🔍 MULTI-FIELD + TYPE-AWARE FETCH
//   • Queries `timestamp` / `arrivalTime` / `departureTime` / legacy `date`
//     in parallel and merges by doc ID, so mobile receipts that only store
//     arrivalTime (IN) or departureTime (OUT) are no longer skipped.
//   • `_parseDateTime` is type-aware: an OUT prefers departureTime, an IN
//     prefers arrivalTime; falls back to the other field then `createdAt`
//     then the legacy `date`+`time` string pair.
//   • IN/OUT are paired by `type` (first IN ↔ last OUT of the day) instead
//     of first/last timestamp. Falls back to first/last when every log on
//     the day is untyped.
//   • Failures on a single time-field query (e.g. missing composite index)
//     log-and-continue, so the other fields still produce results.
//
// ⚠️ Note on the management page
//   `admin_payroll_management_page.dart` (v3.5) no longer calls this
//   service — it derives hours from `PayrollBreakdown.workRawMinutes`
//   etc. via `_hoursFromBreakdown()`. That means the detail page will
//   match `PayrollCalculator` exactly. This service remains for any
//   other consumer (list exports, employee-facing screens) and is now
//   safe to use with arrivalTime-only docs.
//
// 💡 Lunch / OT rules still come from `WorkHoursService` — that service
//    may apply different thresholds than `PayrollCalculator`. See the
//    comment near the bottom.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'work_hours_service.dart';

/// Attendance Hours Service
///
/// Computes hours per employee from attendance logs:
///   • Raw minutes (clock-out minus clock-in per day)
///   • Lunch deducted (via WorkHoursService rules)
///   • Net minutes (raw minus lunch)
///   • Overtime minutes (net above standard)
class AttendanceHoursService {
  AttendanceHoursService._();
  static final instance = AttendanceHoursService._();

  static const List<String> _timeFields = <String>[
    'timestamp',
    'arrivalTime',
    'departureTime',
  ];

  CollectionReference<Map<String, dynamic>> get _logsCol =>
      FirebaseFirestore.instance.collection('attendance_logs');

  /// Runs one range query and returns null on failure (e.g. missing index).
  /// A failure on one field must not abort the whole fetch.
  Future<QuerySnapshot<Map<String, dynamic>>?> _tryQuery(
    String field,
    Object start,
    Object end,
  ) async {
    try {
      return await _logsCol
          .where(field, isGreaterThanOrEqualTo: start)
          .where(field, isLessThanOrEqualTo: end)
          .get();
    } catch (e) {
      debugPrint('[HoursService] query on $field failed: $e');
      return null;
    }
  }

  /// Fetch hours summary for ALL employees in the period.
  ///
  /// Queries the 3 timestamp fields plus the legacy `date` string field in
  /// parallel, deduplicates by document ID, groups by employee + local date,
  /// and pairs first IN with last OUT per day.
  Future<Map<String, EmployeeHoursSummary>> fetchHoursMap({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      final start =
          DateTime(periodStart.year, periodStart.month, periodStart.day);
      final end = DateTime(
          periodEnd.year, periodEnd.month, periodEnd.day, 23, 59, 59);

      // Firestore treats each `.where` on the same field as a range filter,
      // so this pattern needs only single-field indexes (auto-created).
      final results =
          await Future.wait<QuerySnapshot<Map<String, dynamic>>?>([
        for (final f in _timeFields)
          _tryQuery(f, Timestamp.fromDate(start), Timestamp.fromDate(end)),
        _tryQuery('date', _fmtDate(start), _fmtDate(end)),
      ]);

      final docs = <String, Map<String, dynamic>>{};
      for (final snap in results) {
        if (snap == null) continue;
        for (final d in snap.docs) {
          docs[d.id] = d.data();
        }
      }

      debugPrint('[HoursService] Fetched ${docs.length} attendance logs');

      // employeeId -> localDateKey -> logs
      final grouped = <String, Map<String, List<_Log>>>{};

      for (final d in docs.values) {
        final empId =
            (d['employee_id'] ?? d['employeeId'] ?? '').toString().trim();
        if (empId.isEmpty) continue;

        final type = _typeOf(d);
        final ts = _parseDateTime(d, type);
        if (ts == null || ts.isBefore(start) || ts.isAfter(end)) continue;

        grouped
            .putIfAbsent(empId, () => <String, List<_Log>>{})
            .putIfAbsent(_fmtDate(ts), () => <_Log>[])
            .add(_Log(ts, type));
      }

      final result = <String, EmployeeHoursSummary>{};
      for (final entry in grouped.entries) {
        result[entry.key] = await _computeForEmployee(entry.value);
      }

      debugPrint('[HoursService] Computed for ${result.length} employees');
      return result;
    } catch (e) {
      debugPrint('[HoursService] Fetch error: $e');
      return <String, EmployeeHoursSummary>{};
    }
  }

  /// Compute summary from grouped logs (localDateKey -> logs).
  ///
  /// NOTE: the lunch threshold and standard-minutes-per-day come from
  /// `WorkHoursService.instance.compute(...)`. If that service uses
  /// different thresholds than `PayrollCalculator`, the "Hours" card and
  /// the payslip can disagree slightly on OT pay. When you want a single
  /// source of truth, delete this call and reuse `PayrollBreakdown`
  /// directly (the management page already does that as of v3.5).
  Future<EmployeeHoursSummary> _computeForEmployee(
    Map<String, List<_Log>> byDate,
  ) async {
    int totalRaw = 0;
    int totalLunch = 0;
    int totalNet = 0;
    int totalOT = 0;
    int daysWithLogs = 0;
    int daysWithLunchApplied = 0;
    final dailyBreakdown = <DailyHours>[];

    for (final entry in byDate.entries) {
      final parsed = _pairInOut(entry.value);
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
        date: entry.key,
        clockIn: clockIn,
        clockOut: clockOut,
        rawMinutes: result.rawMinutes,
        lunchMinutes: result.lunchDeductionMinutes,
        netMinutes: result.netMinutes,
        overtimeMinutes: result.overtimeMinutes,
      ));
    }

    // Newest day first for the UI.
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

  /// Pairs the first IN with the last OUT of the day, by `type`.
  /// If every log on the day is untyped, falls back to first/last ts.
  (DateTime, DateTime)? _pairInOut(List<_Log> logs) {
    if (logs.isEmpty) return null;
    final sorted = List<_Log>.of(logs)..sort((a, b) => a.ts.compareTo(b.ts));

    DateTime? firstIn;
    DateTime? lastOut;
    for (final l in sorted) {
      if (l.type == _LogType.inLog && firstIn == null) firstIn = l.ts;
      if (l.type == _LogType.outLog) lastOut = l.ts;
    }

    // Legacy / ambiguous docs: if nothing carries a recognisable IN/OUT
    // type, assume the first punch is IN and the last is OUT.
    final untyped = sorted.every((l) => l.type == _LogType.unknown);
    if (untyped && sorted.length >= 2) {
      firstIn = sorted.first.ts;
      lastOut = sorted.last.ts;
    }

    if (firstIn == null || lastOut == null || !lastOut.isAfter(firstIn)) {
      return null;
    }
    return (firstIn, lastOut);
  }

  _LogType _typeOf(Map<String, dynamic> d) {
    final t = (d['type'] ?? d['status'] ?? '').toString().toUpperCase();
    if (t.contains('OUT')) return _LogType.outLog;
    if (t.contains('IN')) return _LogType.inLog;
    return _LogType.unknown;
  }

  /// Type-aware parse:
  ///   • OUT → departureTime, then arrivalTime
  ///   • IN  → arrivalTime, then departureTime
  ///   • then `timestamp`, then `createdAt`
  ///   • finally legacy `date` + `time` string pair
  DateTime? _parseDateTime(Map<String, dynamic> d, _LogType type) {
    final raw = d['timestamp'] ??
        (type == _LogType.outLog
            ? (d['departureTime'] ?? d['arrivalTime'])
            : (d['arrivalTime'] ?? d['departureTime'])) ??
        d['createdAt'];
    if (raw is Timestamp) return raw.toDate().toLocal();

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
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════
// INTERNAL LOG WRAPPER
// ═══════════════════════════════════════════════════════════════
enum _LogType { inLog, outLog, unknown }

class _Log {
  final DateTime ts;
  final _LogType type;
  const _Log(this.ts, this.type);
}

// ═══════════════════════════════════════════════════════════════
// MODELS (unchanged)
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
    this.dailyBreakdown = const <DailyHours>[],
  });

  /// Convenience factory for demo / preview data.
  const EmployeeHoursSummary.mock({
    this.totalRawMinutes = 0,
    this.totalLunchDeductedMinutes = 0,
    this.totalNetMinutes = 0,
    this.totalOvertimeMinutes = 0,
    this.daysWithLogs = 0,
    this.daysWithLunchApplied = 0,
    this.dailyBreakdown = const <DailyHours>[],
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