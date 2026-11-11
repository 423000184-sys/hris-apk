// lib/services/payroll_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class WorkHoursConfig {
  final int standardMinutesPerDay;
  final int lunchBreakMinutes;
  final int lunchThresholdMinutes;
  final int graceMinutes;

  const WorkHoursConfig({
    this.standardMinutesPerDay = 480,
    this.lunchBreakMinutes = 60,
    this.lunchThresholdMinutes = 300,
    this.graceMinutes = 15,
  });

  static const fallback = WorkHoursConfig();

  factory WorkHoursConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return fallback;
    int gv(dynamic v, int d) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('$v') ?? d;
    }

    return WorkHoursConfig(
      standardMinutesPerDay: gv(m['standardMinutesPerDay'], 480).clamp(60, 1440),
      lunchBreakMinutes: gv(m['lunchBreakMinutes'], 60).clamp(0, 240),
      lunchThresholdMinutes: gv(m['lunchThresholdMinutes'], 300).clamp(60, 1440),
      graceMinutes: gv(m['graceMinutes'], 15).clamp(0, 60),
    );
  }
}

class PayrollBreakdown {
  final double regularPay;
  final double basicSalary;
  final double basicHours;
  final double absentAmount;
  final double absentHours;
  final double lateAmount;
  final double lateHours;
  final double undertimeAmount;
  final double undertimeHours;
  final double dayOffOtAmount;
  final double dayOffOtHours;
  final double overtimeAmount;
  final double overtimeHours;
  final double nightDiffAmount;
  final double nightDiffHours;
  final double holidayAmount;
  final double otherIncomeAllowance;
  final double totalAdjustmentsMade;
  final double grossPay;
  final double thirteenthMonth;
  final double silCredits;
  final double totalBenefits;
  final int workingDays;
  final int workingDaysPerMonth;
  final int presentDays;
  final int absentDays;
  final double dailyRate;
  final int workRawMinutes;
  final int workLunchMinutes;
  final int workNetMinutes;
  final int workOvertimeMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;
  final String salarySource;
  final double sss;
  final double philhealth;
  final double pagibig;
  final double taxableIncome;
  final double taxWithheld;
  final double totalLoanDeductions;
  final double totalDeductions;
  final double netPay;
  final double sickLeaveBalance;
  final double vacationLeaveBalance;
  final double riceAllowance;

  const PayrollBreakdown({
    required this.regularPay,
    required this.basicSalary,
    required this.basicHours,
    required this.absentAmount,
    required this.absentHours,
    required this.lateAmount,
    required this.lateHours,
    required this.undertimeAmount,
    required this.undertimeHours,
    required this.dayOffOtAmount,
    required this.dayOffOtHours,
    required this.overtimeAmount,
    required this.overtimeHours,
    required this.nightDiffAmount,
    required this.nightDiffHours,
    required this.holidayAmount,
    required this.otherIncomeAllowance,
    required this.totalAdjustmentsMade,
    required this.grossPay,
    required this.thirteenthMonth,
    required this.silCredits,
    required this.totalBenefits,
    required this.workingDays,
    required this.workingDaysPerMonth,
    required this.presentDays,
    required this.absentDays,
    required this.dailyRate,
    required this.workRawMinutes,
    required this.workLunchMinutes,
    required this.workNetMinutes,
    required this.workOvertimeMinutes,
    required this.daysWithLogs,
    required this.daysWithLunchApplied,
    required this.salarySource,
    required this.sss,
    required this.philhealth,
    required this.pagibig,
    required this.taxableIncome,
    required this.taxWithheld,
    required this.totalLoanDeductions,
    required this.totalDeductions,
    required this.netPay,
    required this.sickLeaveBalance,
    required this.vacationLeaveBalance,
    required this.riceAllowance,
  });

  static const empty = PayrollBreakdown(
    regularPay: 0, basicSalary: 0, basicHours: 0, absentAmount: 0, absentHours: 0, lateAmount: 0, lateHours: 0, undertimeAmount: 0, undertimeHours: 0, dayOffOtAmount: 0, dayOffOtHours: 0, overtimeAmount: 0, overtimeHours: 0, nightDiffAmount: 0, nightDiffHours: 0, holidayAmount: 0, otherIncomeAllowance: 0, totalAdjustmentsMade: 0, grossPay: 0, thirteenthMonth: 0, silCredits: 0, totalBenefits: 0, workingDays: 0, workingDaysPerMonth: 22, presentDays: 0, absentDays: 0, dailyRate: 0, workRawMinutes: 0, workLunchMinutes: 0, workNetMinutes: 0, workOvertimeMinutes: 0, daysWithLogs: 0, daysWithLunchApplied: 0, salarySource: 'manual', sss: 0, philhealth: 0, pagibig: 0, taxableIncome: 0, taxWithheld: 0, totalLoanDeductions: 0, totalDeductions: 0, netPay: 0, sickLeaveBalance: 120, vacationLeaveBalance: 120, riceAllowance: 0,
  );
}

class _WorkHoursResult {
  final int rawMinutes, lunchMinutes, netMinutes, overtimeMinutes, daysWithLogs, daysWithLunchApplied;
  const _WorkHoursResult({this.rawMinutes = 0, this.lunchMinutes = 0, this.netMinutes = 0, this.overtimeMinutes = 0, this.daysWithLogs = 0, this.daysWithLunchApplied = 0});
}

class PayrollCalculator {
  PayrollCalculator._();

  static const double sssRate = 0.045;
  static const double philhealthRate = 0.025;
  static const double pagibigRate = 0.020;
  static const int defaultWorkingDays = 22;
  static const double _maxSalary = 10000000.0;
  static const int _maxLogsPerEmployee = 5000;
  static const int _maxPeriodDays = 62;

  static double toDbl(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      if (d.isNaN || d.isInfinite) return 0.0;
      return d.clamp(-_maxSalary, _maxSalary);
    }
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed == null || parsed.isNaN || parsed.isInfinite) return 0.0;
      return parsed.clamp(-_maxSalary, _maxSalary);
    }
    return 0.0;
  }

  static int toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static int countWeekdays(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 0;
    final span = end.difference(start).inDays;
    if (span > _maxPeriodDays * 2) end = start.add(Duration(days: _maxPeriodDays * 2));
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final stop = DateTime(end.year, end.month, end.day);
    int safety = 0;
    while (!cur.isAfter(stop) && safety < 1000) {
      if (cur.weekday >= DateTime.monday && cur.weekday <= DateTime.friday) count++;
      cur = cur.add(const Duration(days: 1));
      safety++;
    }
    return count;
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseTimestamp(Map<String, dynamic> data) {
    final raw = data['timestamp'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    final dateStr = data['date'] as String?;
    if (dateStr != null) return DateTime.tryParse('$dateStr ${data['time'] ?? '00:00'}');
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static String _logType(Map<String, dynamic> log) => (log['type'] ?? log['status'] ?? '').toString().toUpperCase();
  static bool _isIn(String type) => type.contains('IN') || type.contains('LOGIN') || type.contains('CLOCK_IN');
  static bool _isOut(String type) => type.contains('OUT') || type.contains('LOGOUT') || type.contains('CLOCK_OUT');

  static Set<String> _safeEmployeeIds(Map<String, dynamic> employee) {
    final ids = <String>{};
    for (final k in ['id', 'employeeId', 'employee_id', 'nfcTagId', 'authUid']) {
      final v = employee[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v.length <= 128) ids.add(v);
    }
    return ids;
  }

  static Future<Map<String, int>> fetchPresentDaysMap({required DateTime periodStart, required DateTime periodEnd}) async {
    final result = <String, Set<String>>{};
    try {
      final snap = await FirebaseFirestore.instance
      .collection('attendance_logs')
      .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
      .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
      .limit(5000).get();
      for (final d in snap.docs) {
        final data = d.data();
        final empId = (data['employee_id'] ?? data['employeeId'] ?? data['empId'] ?? '').toString().trim();
        if (empId.isEmpty) continue;
        final ts = _parseTimestamp(data);
        if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
        if (ts.weekday == DateTime.saturday || ts.weekday == DateTime.sunday) continue;
        if (!_isIn(_logType(data))) continue;
        result.putIfAbsent(empId, () => {}).add(_dateKey(ts));
      }
    } catch (e) { debugPrint('⚠️ fetchPresentDaysMap: $e'); }
    return result.map((k, v) => MapEntry(k, v.length));
  }

  static Future<int> _fetchSinglePresentDays({required Map<String, dynamic> employee, required DateTime periodStart, required DateTime periodEnd}) async {
    final ids = _safeEmployeeIds(employee);
    if (ids.isEmpty) return 0;
    final dates = <String>{};
    for (final id in ids) {
      try {
        final snap = await FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: id)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
        .limit(_maxLogsPerEmployee).get();
        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
          if (ts.weekday == DateTime.saturday || ts.weekday == DateTime.sunday) continue;
          if (_isIn(_logType(data))) dates.add(_dateKey(ts));
        }
      } catch (e) { debugPrint('⚠️ present days ($id): $e'); }
    }
    return dates.length;
  }

  static Future<_WorkHoursResult> _fetchWorkHours({required Map<String, dynamic> employee, required DateTime periodStart, required DateTime periodEnd, required WorkHoursConfig config}) async {
    final ids = _safeEmployeeIds(employee);
    if (ids.isEmpty) return const _WorkHoursResult();
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final id in ids) {
      try {
        final snap = await FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: id)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
        .limit(_maxLogsPerEmployee).get();
        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
          if (ts.weekday == DateTime.saturday || ts.weekday == DateTime.sunday) continue;
          byDay.putIfAbsent(_dateKey(ts), () => []).add({...data, '_ts': ts});
        }
      } catch (e) { debugPrint('⚠️ work hours ($id): $e'); }
    }
    int rawTotal = 0, lunchTotal = 0, netTotal = 0, otTotal = 0, daysWithLogs = 0, daysWithLunchApplied = 0;
    byDay.forEach((key, logs) {
      if (logs.isEmpty) return;
      logs.sort((a, b) => (a['_ts'] as DateTime).compareTo(b['_ts'] as DateTime));
      DateTime? firstIn, lastOut;
      for (final log in logs) {
        final type = _logType(log);
        final ts = log['_ts'] as DateTime;
        if (_isIn(type) && firstIn == null) firstIn = ts;
        if (_isOut(type)) lastOut = ts;
      }
      if (firstIn == null || lastOut == null || !lastOut.isAfter(firstIn)) return;
      final raw = lastOut.difference(firstIn).inMinutes;
      if (raw <= 0 || raw > 24 * 60) return;
      int lunch = 0;
      if (raw >= config.lunchThresholdMinutes) lunch = config.lunchBreakMinutes;
      final net = (raw - lunch).clamp(0, 24 * 60);
      final ot = net > config.standardMinutesPerDay ? net - config.standardMinutesPerDay : 0;
      rawTotal += raw; lunchTotal += lunch; netTotal += net; otTotal += ot; daysWithLogs++;
      if (lunch > 0) daysWithLunchApplied++;
    });
      return _WorkHoursResult(rawMinutes: rawTotal, lunchMinutes: lunchTotal, netMinutes: netTotal, overtimeMinutes: otTotal, daysWithLogs: daysWithLogs, daysWithLunchApplied: daysWithLunchApplied);
  }

  static Future<PayrollBreakdown> compute({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    int? presentDaysOverride,
    bool fetchAttendance = true,
    bool fetchWorkHoursData = true,
    double? overtimeHoursOverride,
    double? holidayAmountOverride,
    double? otherIncomeAllowanceOverride,
    double? taxWithheldOverride,
  }) async {
    if (periodEnd.isBefore(periodStart)) return PayrollBreakdown.empty;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final pStart = DateTime(periodStart.year, periodStart.month, periodStart.day);
    final pEnd = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);

    final dateHiredRaw = employee['dateHired'] ?? employee['createdAt'] ?? employee['date_hired'] ?? employee['created_at'];
    DateTime? hireDate;
    if (dateHiredRaw != null) {
      if (dateHiredRaw is Timestamp) hireDate = dateHiredRaw.toDate();
      if (dateHiredRaw is String) hireDate = DateTime.tryParse(dateHiredRaw);
    }

    // FIX: Kung walang valid na dateHired, i-set ang start date sa TODAY.
    if (hireDate == null) {
      hireDate = today;
    }

    final actualStart = hireDate.isAfter(pStart) ? DateTime(hireDate.year, hireDate.month, hireDate.day) : pStart;

    // ABSENCE CALCULATION: Hanggang kahapon lang!
    final absenceEnd = pEnd.isAfter(yesterday) ? yesterday : pEnd;
    final expectedDays = countWeekdays(actualStart, absenceEnd);

    final basic = toDbl(employee['basicSalary']);
    final totalAllowances = toDbl(employee['basicAllowance'] ?? employee['allowances']) +
    toDbl(employee['housingAllowance']) +
    toDbl(employee['transportAllowance']) +
    toDbl(employee['specialAllowance']);

    final effectiveWorkingDays = toInt(employee['workingDaysPerMonth'], defaultWorkingDays).clamp(1, 31);
    final savedDailyRate = toDbl(employee['dailyRate']);
    final dailyRate = savedDailyRate > 0 ? savedDailyRate : (basic / effectiveWorkingDays);
    final hourlyRate = dailyRate / 8.0;

    int present = presentDaysOverride ?? 0;
    if (presentDaysOverride == null && fetchAttendance) {
      present = await _fetchSinglePresentDays(employee: employee, periodStart: actualStart, periodEnd: today);
    }

    final earnedBasic = dailyRate * present;
    final earnedAllowance = (totalAllowances / effectiveWorkingDays) * present;

    final overtimeHours = overtimeHoursOverride ?? 0.0;
    final overtimeAmount = overtimeHours * hourlyRate;

    final gross = earnedBasic + earnedAllowance + overtimeAmount + (holidayAmountOverride ?? 0.0) + (otherIncomeAllowanceOverride ?? 0.0);

    final sss = earnedBasic * sssRate;
    final philhealth = earnedBasic * philhealthRate;
    final pagibig = earnedBasic * pagibigRate;

    final totalDeductions = sss + philhealth + pagibig + (taxWithheldOverride ?? 0.0);
    final netPay = gross - totalDeductions;

    final absent = (expectedDays - present).clamp(0, expectedDays);

    return PayrollBreakdown(
      regularPay: gross,
      basicSalary: basic,
      basicHours: present * 8.0,
      absentAmount: dailyRate * absent,
      absentHours: absent * 8.0,
      lateAmount: 0.0, lateHours: 0.0, undertimeAmount: 0.0, undertimeHours: 0.0, dayOffOtAmount: 0.0, dayOffOtHours: 0.0,
      overtimeAmount: overtimeAmount, overtimeHours: overtimeHours, nightDiffAmount: 0.0, nightDiffHours: 0.0,
      holidayAmount: holidayAmountOverride ?? 0.0,
      otherIncomeAllowance: totalAllowances,
      totalAdjustmentsMade: 0.0,
      grossPay: gross,
      thirteenthMonth: basic / 12,
      silCredits: dailyRate * 5,
      totalBenefits: (basic / 12) + (dailyRate * 5),
      workingDays: expectedDays + 1,
      workingDaysPerMonth: effectiveWorkingDays,
      presentDays: present,
      absentDays: absent,
      dailyRate: dailyRate,
      workRawMinutes: 0, workLunchMinutes: 0, workNetMinutes: 0, workOvertimeMinutes: 0, daysWithLogs: 0, daysWithLunchApplied: 0,
      salarySource: (employee['salarySource'] as String?)?.trim() ?? 'manual',
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      taxableIncome: gross,
      taxWithheld: taxWithheldOverride ?? 0.0,
      totalLoanDeductions: 0.0,
      totalDeductions: totalDeductions,
      netPay: netPay,
      sickLeaveBalance: 120.0, vacationLeaveBalance: 120.0, riceAllowance: 0.0,
    );
  }

  static String peso(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final posFromEnd = whole.length - i;
      buf.write(whole[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '₱${buf.toString()}.${parts.length > 1 ? parts[1] : '00'}';
  }
}
