// lib/services/payroll_calculator.dart
// v2.2: - Rates are HR-editable (settings/payroll); defaults = SSS 5% of MSC,
//         Pag-IBIG cap 200, OT 125%, rest day 130%, rest-day OT 169%, ND 10%,
//         BIR monthly withholding brackets.
//       - Centavo rounding on every amount so payslip rows add up.
//       - netPay clamped to 0 but the gap is exposed as deductionShortfall.
//       - 13th month is now earnedBasic / 12.
//       - otherIncomeAllowance is now the EARNED allowance (matches gross).
//       - Fixed: logs from today were dropped (fetch end was midnight).
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class TaxBracket {
  final double over;
  final double base;
  final double rate;

  const TaxBracket(this.over, this.base, this.rate);

  Map<String, dynamic> toMap() => {'over': over, 'base': base, 'rate': rate};

  static TaxBracket? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    double? n(dynamic v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
    final o = n(raw['over']);
    final b = n(raw['base']);
    final r = n(raw['rate']);
    if (o == null || b == null || r == null) return null;
    return TaxBracket(o, b, r);
  }
}

class PayrollSettings {
  final double sssEmployeeRate;
  final double sssMinMsc;
  final double sssMaxMsc;
  final double sssMscStep;
  final double philhealthTotalRate;
  final double philhealthFloor;
  final double philhealthCeiling;
  final double pagibigEmployeeRate;
  final double pagibigMax;
  final double pagibigLowSalaryThreshold;
  final double pagibigLowRate;
  final double ordinaryOtMultiplier;
  final double restDayRegularMultiplier;
  final double restDayOtMultiplier;
  final double nightDiffMultiplier;
  final List<TaxBracket> taxBrackets;

  static const List<TaxBracket> defaultTaxBrackets = <TaxBracket>[
    TaxBracket(0, 0, 0),
    TaxBracket(20833, 0, 0.15),
    TaxBracket(33333, 1875, 0.20),
    TaxBracket(66667, 8541.80, 0.25),
    TaxBracket(166667, 33541.80, 0.30),
    TaxBracket(666667, 183541.80, 0.35),
  ];

  const PayrollSettings({
    this.sssEmployeeRate = 0.05,
    this.sssMinMsc = 5000.0,
    this.sssMaxMsc = 35000.0,
    this.sssMscStep = 500.0,
    this.philhealthTotalRate = 0.05,
    this.philhealthFloor = 10000.0,
    this.philhealthCeiling = 100000.0,
    this.pagibigEmployeeRate = 0.02,
    this.pagibigMax = 200.0,
    this.pagibigLowSalaryThreshold = 1500.0,
    this.pagibigLowRate = 0.01,
    this.ordinaryOtMultiplier = 1.25,
    this.restDayRegularMultiplier = 1.30,
    this.restDayOtMultiplier = 1.69,
    this.nightDiffMultiplier = 0.10,
    this.taxBrackets = defaultTaxBrackets,
  });

  static const fallback = PayrollSettings();

  factory PayrollSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return fallback;
    const d = PayrollSettings();
    double gd(String k, double def) {
      final v = m[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? def;
      return def;
    }

    List<TaxBracket> brackets = defaultTaxBrackets;
    final rawB = m['taxBrackets'];
    if (rawB is List && rawB.isNotEmpty) {
      final parsed =
      rawB.map(TaxBracket.tryParse).whereType<TaxBracket>().toList()
        ..sort((a, b) => a.over.compareTo(b.over));
      if (parsed.length == rawB.length) brackets = parsed;
    }

    return PayrollSettings(
      sssEmployeeRate: gd('sssEmployeeRate', d.sssEmployeeRate),
      sssMinMsc: gd('sssMinMsc', d.sssMinMsc),
      sssMaxMsc: gd('sssMaxMsc', d.sssMaxMsc),
      sssMscStep: gd('sssMscStep', d.sssMscStep),
      philhealthTotalRate: gd('philhealthTotalRate', d.philhealthTotalRate),
      philhealthFloor: gd('philhealthFloor', d.philhealthFloor),
      philhealthCeiling: gd('philhealthCeiling', d.philhealthCeiling),
      pagibigEmployeeRate: gd('pagibigEmployeeRate', d.pagibigEmployeeRate),
      pagibigMax: gd('pagibigMax', d.pagibigMax),
      pagibigLowSalaryThreshold:
      gd('pagibigLowSalaryThreshold', d.pagibigLowSalaryThreshold),
      pagibigLowRate: gd('pagibigLowRate', d.pagibigLowRate),
      ordinaryOtMultiplier: gd('ordinaryOtMultiplier', d.ordinaryOtMultiplier),
      restDayRegularMultiplier:
      gd('restDayRegularMultiplier', d.restDayRegularMultiplier),
      restDayOtMultiplier: gd('restDayOtMultiplier', d.restDayOtMultiplier),
      nightDiffMultiplier: gd('nightDiffMultiplier', d.nightDiffMultiplier),
      taxBrackets: brackets,
    );
  }

  Map<String, dynamic> toMap() => {
    'sssEmployeeRate': sssEmployeeRate,
    'sssMinMsc': sssMinMsc,
    'sssMaxMsc': sssMaxMsc,
    'sssMscStep': sssMscStep,
    'philhealthTotalRate': philhealthTotalRate,
    'philhealthFloor': philhealthFloor,
    'philhealthCeiling': philhealthCeiling,
    'pagibigEmployeeRate': pagibigEmployeeRate,
    'pagibigMax': pagibigMax,
    'pagibigLowSalaryThreshold': pagibigLowSalaryThreshold,
    'pagibigLowRate': pagibigLowRate,
    'ordinaryOtMultiplier': ordinaryOtMultiplier,
    'restDayRegularMultiplier': restDayRegularMultiplier,
    'restDayOtMultiplier': restDayOtMultiplier,
    'nightDiffMultiplier': nightDiffMultiplier,
    'taxBrackets': taxBrackets.map((b) => b.toMap()).toList(),
  };

  List<String> validate() {
    final e = <String>[];
    void rate(String n, double v) {
      if (v.isNaN || v < 0 || v > 1) e.add('$n must be between 0 and 1');
    }

    void mult(String n, double v) {
      if (v.isNaN || v < 1 || v > 5) e.add('$n must be between 1 and 5');
    }

    rate('sssEmployeeRate', sssEmployeeRate);
    rate('philhealthTotalRate', philhealthTotalRate);
    rate('pagibigEmployeeRate', pagibigEmployeeRate);
    rate('pagibigLowRate', pagibigLowRate);
    rate('nightDiffMultiplier', nightDiffMultiplier);
    mult('ordinaryOtMultiplier', ordinaryOtMultiplier);
    mult('restDayRegularMultiplier', restDayRegularMultiplier);
    mult('restDayOtMultiplier', restDayOtMultiplier);
    if (restDayOtMultiplier < restDayRegularMultiplier) {
      e.add('restDayOtMultiplier must be >= restDayRegularMultiplier');
    }
    if (sssMscStep <= 0) e.add('sssMscStep must be > 0');
    if (sssMinMsc <= 0 || sssMinMsc > sssMaxMsc) {
      e.add('SSS MSC range is invalid');
    }
    if (philhealthFloor <= 0 || philhealthFloor > philhealthCeiling) {
      e.add('PhilHealth floor/ceiling is invalid');
    }
    if (pagibigMax < 0) e.add('pagibigMax cannot be negative');
    if (taxBrackets.isEmpty) {
      e.add('At least one tax bracket is required');
    } else {
      if (taxBrackets.first.over != 0) {
        e.add('First tax bracket must start at 0');
      }
      for (var i = 0; i < taxBrackets.length; i++) {
        final b = taxBrackets[i];
        if (b.rate.isNaN || b.rate < 0 || b.rate > 1 || b.base < 0) {
          e.add('Tax bracket ${i + 1} has an invalid rate or base');
        }
        if (i > 0 && b.over <= taxBrackets[i - 1].over) {
          e.add('Tax brackets must be strictly ascending');
          break;
        }
      }
    }
    return e;
  }
}

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
      standardMinutesPerDay:
      gv(m['standardMinutesPerDay'], 480).clamp(60, 1440),
      lunchBreakMinutes: gv(m['lunchBreakMinutes'], 60).clamp(0, 240),
      lunchThresholdMinutes:
      gv(m['lunchThresholdMinutes'], 300).clamp(60, 1440),
      graceMinutes: gv(m['graceMinutes'], 15).clamp(0, 60),
    );
  }
}

class PayrollBreakdown {
  final double regularPay;
  final double basicSalary;
  final double earnedBasic;
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
  final double earnedAllowance;
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

  /// How much the deductions exceed gross (netPay is clamped to 0).
  final double deductionShortfall;
  final double sickLeaveBalance;
  final double vacationLeaveBalance;
  final double riceAllowance;

  const PayrollBreakdown({
    required this.regularPay,
    required this.basicSalary,
    required this.earnedBasic,
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
    required this.earnedAllowance,
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
    this.deductionShortfall = 0.0,
    required this.sickLeaveBalance,
    required this.vacationLeaveBalance,
    required this.riceAllowance,
  });

  static const empty = PayrollBreakdown(
    regularPay: 0,
    basicSalary: 0,
    earnedBasic: 0,
    basicHours: 0,
    absentAmount: 0,
    absentHours: 0,
    lateAmount: 0,
    lateHours: 0,
    undertimeAmount: 0,
    undertimeHours: 0,
    dayOffOtAmount: 0,
    dayOffOtHours: 0,
    overtimeAmount: 0,
    overtimeHours: 0,
    nightDiffAmount: 0,
    nightDiffHours: 0,
    holidayAmount: 0,
    otherIncomeAllowance: 0,
    earnedAllowance: 0,
    totalAdjustmentsMade: 0,
    grossPay: 0,
    thirteenthMonth: 0,
    silCredits: 0,
    totalBenefits: 0,
    workingDays: 0,
    workingDaysPerMonth: 22,
    presentDays: 0,
    absentDays: 0,
    dailyRate: 0,
    workRawMinutes: 0,
    workLunchMinutes: 0,
    workNetMinutes: 0,
    workOvertimeMinutes: 0,
    daysWithLogs: 0,
    daysWithLunchApplied: 0,
    salarySource: 'manual',
    sss: 0,
    philhealth: 0,
    pagibig: 0,
    taxableIncome: 0,
    taxWithheld: 0,
    totalLoanDeductions: 0,
    totalDeductions: 0,
    netPay: 0,
    sickLeaveBalance: 120,
    vacationLeaveBalance: 120,
    riceAllowance: 0,
  );
}

class WorkHoursTotals {
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int regularOtMinutes;
  final int restDayRegularMinutes;
  final int restDayOtMinutes;
  final int nightDiffMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;

  const WorkHoursTotals({
    this.rawMinutes = 0,
    this.lunchMinutes = 0,
    this.netMinutes = 0,
    this.regularOtMinutes = 0,
    this.restDayRegularMinutes = 0,
    this.restDayOtMinutes = 0,
    this.nightDiffMinutes = 0,
    this.daysWithLogs = 0,
    this.daysWithLunchApplied = 0,
  });
}

class PayrollCalculator {
  PayrollCalculator._();

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

  /// Round to centavos (half away from zero) so payslip rows add up exactly.
  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static int countWeekdays(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 0;
    final span = end.difference(start).inDays;
    if (span > _maxPeriodDays * 2) {
      end = start.add(Duration(days: _maxPeriodDays * 2));
    }
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final stop = DateTime(end.year, end.month, end.day);
    int safety = 0;
    while (!cur.isAfter(stop) && safety < 1000) {
      if (cur.weekday >= DateTime.monday && cur.weekday <= DateTime.friday) {
        count++;
      }
      cur = cur.add(const Duration(days: 1));
      safety++;
    }
    return count;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseTimestamp(Map<String, dynamic> data) {
    final raw = data['timestamp'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    final dateStr = data['date'] as String?;
    if (dateStr != null) {
      return DateTime.tryParse('$dateStr ${data['time'] ?? '00:00'}');
    }
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static String _logType(Map<String, dynamic> log) =>
      (log['type'] ?? log['status'] ?? '').toString().toUpperCase();
  static bool _isIn(String type) =>
      type.contains('IN') || type.contains('LOGIN') || type.contains('CLOCK_IN');
  static bool _isOut(String type) =>
      type.contains('OUT') ||
          type.contains('LOGOUT') ||
          type.contains('CLOCK_OUT');

  static Set<String> _safeEmployeeIds(Map<String, dynamic> employee) {
    final ids = <String>{};
    for (final k in ['id', 'employeeId', 'employee_id', 'nfcTagId', 'authUid']) {
      final v = employee[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v.length <= 128) ids.add(v);
    }
    return ids;
  }

  // ───────────────────────── Statutory contributions ─────────────────────────

  /// SSS employee share = rate x MSC bracket.
  static double calcSss(double monthlySalary, PayrollSettings s) {
    if (monthlySalary <= 0) return 0.0;
    final raw =
        ((monthlySalary + s.sssMscStep / 2) / s.sssMscStep).floor() *
            s.sssMscStep;
    final msc = raw < s.sssMinMsc
        ? s.sssMinMsc
        : (raw > s.sssMaxMsc ? s.sssMaxMsc : raw);
    return msc * s.sssEmployeeRate;
  }

  /// PhilHealth employee share = half of the total premium.
  static double calcPhilhealth(double monthlySalary, PayrollSettings s) {
    if (monthlySalary <= 0) return 0.0;
    final base = monthlySalary < s.philhealthFloor
        ? s.philhealthFloor
        : (monthlySalary > s.philhealthCeiling
        ? s.philhealthCeiling
        : monthlySalary);
    return base * s.philhealthTotalRate / 2;
  }

  /// Pag-IBIG employee share, capped at pagibigMax.
  static double calcPagibig(double monthlySalary, PayrollSettings s) {
    if (monthlySalary <= 0) return 0.0;
    if (monthlySalary <= s.pagibigLowSalaryThreshold) {
      return monthlySalary * s.pagibigLowRate;
    }
    final c = monthlySalary * s.pagibigEmployeeRate;
    return c > s.pagibigMax ? s.pagibigMax : c;
  }

  /// BIR monthly withholding tax: base + (taxable - over) x rate.
  static double calcWithholdingTax(double taxable, PayrollSettings s) {
    if (taxable <= 0) return 0.0;
    TaxBracket? hit;
    for (final b in s.taxBrackets) {
      if (taxable > b.over) {
        hit = b;
      } else {
        break;
      }
    }
    if (hit == null) return 0.0;
    return hit.base + (taxable - hit.over) * hit.rate;
  }

  /// Minutes between 10PM and 6AM inside [inTime, outTime].
  static int _calculateNdMinutes(DateTime inTime, DateTime outTime) {
    int ndMins = 0;
    DateTime current = DateTime(inTime.year, inTime.month, inTime.day, 22, 0);
    if (current.isAfter(inTime)) {
      current = current.subtract(const Duration(days: 1));
    }

    while (current.isBefore(outTime)) {
      DateTime ndEnd = current.add(const Duration(hours: 8));
      if (ndEnd.isAfter(inTime)) {
        DateTime effectiveStart = current.isAfter(inTime) ? current : inTime;
        DateTime effectiveEnd = ndEnd.isBefore(outTime) ? ndEnd : outTime;
        if (effectiveEnd.isAfter(effectiveStart)) {
          ndMins += effectiveEnd.difference(effectiveStart).inMinutes;
        }
      }
      current = current.add(const Duration(days: 1));
    }
    return ndMins;
  }

  // ───────────────────────────── Attendance fetching ─────────────────────────

  static Future<Map<String, int>> fetchPresentDaysMap({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final result = <String, Set<String>>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
          .where('timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
          .limit(5000)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final empId =
        (data['employee_id'] ?? data['employeeId'] ?? data['empId'] ?? '')
            .toString()
            .trim();
        if (empId.isEmpty) continue;
        final ts = _parseTimestamp(data);
        if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) {
          continue;
        }
        if (ts.weekday == DateTime.saturday || ts.weekday == DateTime.sunday) {
          continue;
        }
        if (!_isIn(_logType(data))) continue;
        result.putIfAbsent(empId, () => {}).add(_dateKey(ts));
      }
    } catch (e) {
      debugPrint('⚠️ fetchPresentDaysMap: $e');
    }
    return result.map((k, v) => MapEntry(k, v.length));
  }

  static Future<int> _fetchSinglePresentDays({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final ids = _safeEmployeeIds(employee);
    if (ids.isEmpty) return 0;
    final dates = <String>{};
    for (final id in ids) {
      try {
        var snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: id)
            .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
            .where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
            .limit(_maxLogsPerEmployee)
            .get();

        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('attendance_logs')
              .where('employeeId', isEqualTo: id)
              .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
              .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
              .limit(_maxLogsPerEmployee)
              .get();
        }

        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) {
            continue;
          }
          if (ts.weekday == DateTime.saturday ||
              ts.weekday == DateTime.sunday) {
            continue;
          }
          if (_isIn(_logType(data))) dates.add(_dateKey(ts));
        }
      } catch (e) {
        debugPrint('⚠️ present days ($id): $e');
      }
    }
    return dates.length;
  }

  static Future<WorkHoursTotals> _fetchWorkHours({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    required WorkHoursConfig config,
  }) async {
    final ids = _safeEmployeeIds(employee);
    if (ids.isEmpty) return const WorkHoursTotals();

    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final id in ids) {
      try {
        var snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: id)
            .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
            .where('timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
            .limit(_maxLogsPerEmployee)
            .get();

        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection('attendance_logs')
              .where('employeeId', isEqualTo: id)
              .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
              .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
              .limit(_maxLogsPerEmployee)
              .get();
        }

        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null || ts.isBefore(periodStart) || ts.isAfter(periodEnd)) {
            continue;
          }
          byDay.putIfAbsent(_dateKey(ts), () => []).add({...data, '_ts': ts});
        }
      } catch (e) {
        debugPrint('⚠️ work hours ($id): $e');
      }
    }

    int rawTotal = 0, lunchTotal = 0, netTotal = 0;
    int regularOtTotal = 0, restDayRegularTotal = 0, restDayOtTotal = 0;
    int ndTotal = 0;
    int daysWithLogs = 0, daysWithLunchApplied = 0;

    byDay.forEach((key, logs) {
      if (logs.isEmpty) return;
      logs.sort(
              (a, b) => (a['_ts'] as DateTime).compareTo(b['_ts'] as DateTime));

      final firstTs = logs.first['_ts'] as DateTime;
      final isWeekend = firstTs.weekday == DateTime.saturday ||
          firstTs.weekday == DateTime.sunday;

      DateTime? firstIn, lastOut;
      for (final log in logs) {
        final type = _logType(log);
        final ts = log['_ts'] as DateTime;
        if (_isIn(type) && firstIn == null) firstIn = ts;
        if (_isOut(type)) lastOut = ts;
      }

      if (firstIn == null || lastOut == null || !lastOut.isAfter(firstIn)) {
        return;
      }
      final raw = lastOut.difference(firstIn).inMinutes;
      if (raw <= 0 || raw > 24 * 60) return;

      int lunch = 0;
      if (raw >= config.lunchThresholdMinutes) lunch = config.lunchBreakMinutes;

      final net = (raw - lunch).clamp(0, 24 * 60);

      if (isWeekend) {
        final reg = net < config.standardMinutesPerDay
            ? net
            : config.standardMinutesPerDay;
        restDayRegularTotal += reg;
        restDayOtTotal += net - reg;
      } else if (net > config.standardMinutesPerDay) {
        regularOtTotal += (net - config.standardMinutesPerDay);
      }

      final ndMins = _calculateNdMinutes(firstIn, lastOut);
      ndTotal += ndMins;

      rawTotal += raw;
      lunchTotal += lunch;
      netTotal += net;
      daysWithLogs++;
      if (lunch > 0) daysWithLunchApplied++;
    });

    return WorkHoursTotals(
      rawMinutes: rawTotal,
      lunchMinutes: lunchTotal,
      netMinutes: netTotal,
      regularOtMinutes: regularOtTotal,
      restDayRegularMinutes: restDayRegularTotal,
      restDayOtMinutes: restDayOtTotal,
      nightDiffMinutes: ndTotal,
      daysWithLogs: daysWithLogs,
      daysWithLunchApplied: daysWithLunchApplied,
    );
  }

  // ─────────────────────────────── HR settings ───────────────────────────────

  static Future<PayrollSettings> fetchSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('payroll')
          .get();
      if (doc.exists) {
        final parsed = PayrollSettings.fromMap(doc.data());
        final errors = parsed.validate();
        if (errors.isEmpty) return parsed;
        debugPrint('⚠️ Invalid payroll settings, using fallback: $errors');
      }
    } catch (e) {
      debugPrint('Error fetching payroll settings: $e');
    }
    return PayrollSettings.fallback;
  }

  static Future<void> saveSettings(
      PayrollSettings s, {
        required String actorUid,
      }) async {
    final errors = s.validate();
    if (errors.isNotEmpty) throw ArgumentError(errors.join('; '));
    await FirebaseFirestore.instance.collection('settings').doc('payroll').set({
      ...s.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': actorUid,
    }, SetOptions(merge: true));
  }

  // ────────────────────────────────── Compute ────────────────────────────────

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
    PayrollSettings? settings,
  }) async {
    if (periodEnd.isBefore(periodStart)) return PayrollBreakdown.empty;

    final activeSettings = settings ?? await fetchSettings();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    // End of today, so today's logs are included (was midnight before).
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final fetchEnd = periodEnd.isAfter(endOfToday) ? endOfToday : periodEnd;
    final pStart =
    DateTime(periodStart.year, periodStart.month, periodStart.day);
    final pEnd = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);

    final dateHiredRaw = employee['dateHired'] ??
        employee['createdAt'] ??
        employee['date_hired'] ??
        employee['created_at'];
    DateTime? hireDate;
    if (dateHiredRaw is Timestamp) hireDate = dateHiredRaw.toDate();
    if (dateHiredRaw is String) hireDate = DateTime.tryParse(dateHiredRaw);
    hireDate ??= pStart;

    final actualStart = hireDate.isAfter(pStart)
        ? DateTime(hireDate.year, hireDate.month, hireDate.day)
        : pStart;
    final absenceEnd = pEnd.isAfter(yesterday) ? yesterday : pEnd;
    final expectedDays = countWeekdays(actualStart, absenceEnd);

    int present = presentDaysOverride ?? 0;
    if (presentDaysOverride == null && fetchAttendance) {
      present = await _fetchSinglePresentDays(
        employee: employee,
        periodStart: actualStart,
        periodEnd: fetchEnd,
      );
    }

    var workHours = const WorkHoursTotals();
    if (fetchWorkHoursData) {
      workHours = await _fetchWorkHours(
        employee: employee,
        periodStart: actualStart,
        periodEnd: fetchEnd,
        config: WorkHoursConfig.fallback,
      );
    }

    return computeFromData(
      employee: employee,
      expectedDays: expectedDays,
      present: present,
      workHours: workHours,
      settings: activeSettings,
      holidayAmount: holidayAmountOverride ?? 0.0,
      otherIncomeAllowance: otherIncomeAllowanceOverride ?? 0.0,
      taxWithheldOverride: taxWithheldOverride,
    );
  }

  static PayrollBreakdown computeFromData({
    required Map<String, dynamic> employee,
    required int expectedDays,
    required int present,
    required WorkHoursTotals workHours,
    required PayrollSettings settings,
    double holidayAmount = 0.0,
    double otherIncomeAllowance = 0.0,
    double? taxWithheldOverride,
  }) {
    final basic = toDbl(employee['basicSalary']);
    final totalAllowances =
        toDbl(employee['basicAllowance'] ?? employee['allowances']) +
            toDbl(employee['housingAllowance']) +
            toDbl(employee['transportAllowance']) +
            toDbl(employee['specialAllowance']);

    final workingDays =
    toInt(employee['workingDaysPerMonth'], defaultWorkingDays).clamp(1, 31);
    final savedDaily = toDbl(employee['dailyRate']);
    // Daily rate stays unrounded so 22 days x rate == basic exactly.
    final dailyRate = savedDaily > 0 ? savedDaily : basic / workingDays;
    final hourlyRate = dailyRate / 8.0;

    final earnedBasic = _r2(dailyRate * present);
    final earnedAllowance = _r2((totalAllowances / workingDays) * present);

    final otHours = workHours.regularOtMinutes / 60.0;
    final rdRegHours = workHours.restDayRegularMinutes / 60.0;
    final rdOtHours = workHours.restDayOtMinutes / 60.0;
    final ndHours = workHours.nightDiffMinutes / 60.0;

    // Multipliers come from HR-editable settings (settings/payroll).
    final otAmount =
    _r2(otHours * hourlyRate * settings.ordinaryOtMultiplier);
    final rdAmount = _r2(
        rdRegHours * hourlyRate * settings.restDayRegularMultiplier +
            rdOtHours * hourlyRate * settings.restDayOtMultiplier);
    final ndAmount = _r2(ndHours * hourlyRate * settings.nightDiffMultiplier);

    final gross = _r2(earnedBasic +
        earnedAllowance +
        otAmount +
        rdAmount +
        ndAmount +
        holidayAmount +
        otherIncomeAllowance);

    // Contributions are based on the contract monthly salary (not on
    // attendance), so absences never reduce SSS / PhilHealth / Pag-IBIG.
    final sss = earnedBasic > 0 ? _r2(calcSss(basic, settings)) : 0.0;
    final philhealth =
    earnedBasic > 0 ? _r2(calcPhilhealth(basic, settings)) : 0.0;
    final pagibig = earnedBasic > 0 ? _r2(calcPagibig(basic, settings)) : 0.0;

    final taxable = _r2(math.min(
        math.max(0.0, gross - sss - philhealth - pagibig), _maxSalary));
    final tax =
    _r2(taxWithheldOverride ?? calcWithholdingTax(taxable, settings));
    final totalDeductions = _r2(sss + philhealth + pagibig + tax);
    final absent = (expectedDays - present).clamp(0, expectedDays);

    // Net is never shown negative, but the gap is no longer hidden.
    final rawNet = _r2(gross - totalDeductions);
    final netPay = math.max(0.0, rawNet);
    final shortfall = math.max(0.0, -rawNet);

    final thirteenth = _r2(earnedBasic / 12);
    final sil = _r2(dailyRate * 5);

    return PayrollBreakdown(
      regularPay: gross,
      basicSalary: basic,
      earnedBasic: earnedBasic,
      basicHours: present * 8.0,
      absentAmount: _r2(dailyRate * absent),
      absentHours: absent * 8.0,
      lateAmount: 0.0,
      lateHours: 0.0,
      undertimeAmount: 0.0,
      undertimeHours: 0.0,
      dayOffOtAmount: rdAmount,
      dayOffOtHours: rdRegHours + rdOtHours,
      overtimeAmount: otAmount,
      overtimeHours: otHours,
      nightDiffAmount: ndAmount,
      nightDiffHours: ndHours,
      holidayAmount: holidayAmount,
      // Earned (not full-month) so payslip rows add up to gross.
      otherIncomeAllowance: _r2(earnedAllowance + otherIncomeAllowance),
      earnedAllowance: earnedAllowance,
      totalAdjustmentsMade: 0.0,
      grossPay: gross,
      thirteenthMonth: thirteenth,
      silCredits: sil,
      totalBenefits: _r2(thirteenth + sil),
      workingDays: expectedDays,
      workingDaysPerMonth: workingDays,
      presentDays: present,
      absentDays: absent,
      dailyRate: dailyRate,
      workRawMinutes: workHours.rawMinutes,
      workLunchMinutes: workHours.lunchMinutes,
      workNetMinutes: workHours.netMinutes,
      workOvertimeMinutes:
      workHours.regularOtMinutes + workHours.restDayOtMinutes,
      daysWithLogs: workHours.daysWithLogs,
      daysWithLunchApplied: workHours.daysWithLunchApplied,
      salarySource: (employee['salarySource'] as String?)?.trim() ?? 'manual',
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      taxableIncome: taxable,
      taxWithheld: tax,
      totalLoanDeductions: 0.0,
      totalDeductions: totalDeductions,
      netPay: netPay,
      deductionShortfall: shortfall,
      sickLeaveBalance: 120.0,
      vacationLeaveBalance: 120.0,
      riceAllowance: 0.0,
    );
  }

  static String peso(double v) {
    final isNegative = v < 0;
    final s = v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final posFromEnd = whole.length - i;
      buf.write(whole[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '${isNegative ? '-' : ''}₱${buf.toString()}.${parts.length > 1 ? parts[1] : '00'}';
  }
}