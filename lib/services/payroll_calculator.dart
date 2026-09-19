// lib/services/payroll_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

// ══════════════════════════════════════════════════════════════
// 🍱 WORK HOURS CONFIG — default fallback
// ══════════════════════════════════════════════════════════════
class WorkHoursConfig {
  final int standardMinutesPerDay; // 8h = 480
  final int lunchBreakMinutes; // 1h = 60
  final int lunchThresholdMinutes; // if raw >= this, deduct lunch
  final int graceMinutes; // late grace (default 15)

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
      standardMinutesPerDay: gv(m['standardMinutesPerDay'], 480),
      lunchBreakMinutes: gv(m['lunchBreakMinutes'], 60),
      lunchThresholdMinutes: gv(m['lunchThresholdMinutes'], 300),
      graceMinutes: gv(m['graceMinutes'], 15),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PAYROLL BREAKDOWN
// ══════════════════════════════════════════════════════════════
class PayrollBreakdown {
  // ─── Earnings ─────────────────────────────────────────────
  final double basicSalary;
  final double allowances;
  final double overtimePay;
  final double grossPay;

  // ─── Benefits ────────────────────────────────────────────
  final double thirteenthMonth;
  final double silCredits;
  final double totalBenefits;

  // ─── Attendance ──────────────────────────────────────────
  final int workingDays;
  final int workingDaysPerMonth;
  final int presentDays;
  final int absentDays;
  final double dailyRate;
  final double absenceDeduction;

  // ─── 🍱 Work Hours ───────────────────────────────────────
  final int workRawMinutes;
  final int workLunchMinutes;
  final int workNetMinutes;
  final int workOvertimeMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;

  // ─── 💰 Salary metadata ──────────────────────────────────
  final String salarySource;

  // ─── Government ──────────────────────────────────────────
  final double sss;
  final double philhealth;
  final double pagibig;
  final double withholdingTax;

  // ─── Totals ──────────────────────────────────────────────
  final double totalDeductions;
  final double netPay;

  const PayrollBreakdown({
    required this.basicSalary,
    required this.allowances,
    required this.overtimePay,
    required this.grossPay,
    required this.thirteenthMonth,
    required this.silCredits,
    required this.totalBenefits,
    required this.workingDays,
    required this.workingDaysPerMonth,
    required this.presentDays,
    required this.absentDays,
    required this.dailyRate,
    required this.absenceDeduction,
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
    required this.withholdingTax,
    required this.totalDeductions,
    required this.netPay,
  });

  static const empty = PayrollBreakdown(
    basicSalary: 0,
    allowances: 0,
    overtimePay: 0,
    grossPay: 0,
    thirteenthMonth: 0,
    silCredits: 0,
    totalBenefits: 0,
    workingDays: 22,
    workingDaysPerMonth: 22,
    presentDays: 0,
    absentDays: 0,
    dailyRate: 0,
    absenceDeduction: 0,
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
    withholdingTax: 0,
    totalDeductions: 0,
    netPay: 0,
  );
}

// ══════════════════════════════════════════════════════════════
// 🍱 WORK HOURS RESULT — helper
// ══════════════════════════════════════════════════════════════
class _WorkHoursResult {
  final int rawMinutes;
  final int lunchMinutes;
  final int netMinutes;
  final int overtimeMinutes;
  final int daysWithLogs;
  final int daysWithLunchApplied;

  const _WorkHoursResult({
    this.rawMinutes = 0,
    this.lunchMinutes = 0,
    this.netMinutes = 0,
    this.overtimeMinutes = 0,
    this.daysWithLogs = 0,
    this.daysWithLunchApplied = 0,
  });
}

// ══════════════════════════════════════════════════════════════
// PAYROLL CALCULATOR
// ══════════════════════════════════════════════════════════════
class PayrollCalculator {
  PayrollCalculator._();

  static const double sssRate = 0.045;
  static const double philhealthRate = 0.025;
  static const double pagibigRate = 0.020;
  static const int defaultWorkingDays = 22;

  // ─── Safe parsers ─────────────────────────────────────────
  static double toDbl(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  static int toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  // ─── Weekday count ────────────────────────────────────────
  static int countWeekdays(DateTime start, DateTime end) {
    int count = 0;
    DateTime cur = DateTime(start.year, start.month, start.day);
    final stop = DateTime(end.year, end.month, end.day);
    while (!cur.isAfter(stop)) {
      if (cur.weekday >= DateTime.monday &&
          cur.weekday <= DateTime.friday) {
        count++;
      }
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseTimestamp(Map<String, dynamic> data) {
    final raw = data['timestamp'] ?? data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);

    final dateStr = data['date'] as String?;
    if (dateStr != null) {
      final timeStr = (data['time'] ?? '00:00').toString();
      return DateTime.tryParse('$dateStr $timeStr');
    }
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static String _logType(Map<String, dynamic> log) =>
      (log['type'] ?? log['status'] ?? '').toString().toUpperCase();

  static bool _isIn(String type) =>
      type.contains('IN') ||
          type.contains('LOGIN') ||
          type.contains('CLOCK_IN') ||
          type.contains('TIME IN') ||
          type.contains('TIME_IN');

  static bool _isOut(String type) =>
      type.contains('OUT') ||
          type.contains('LOGOUT') ||
          type.contains('CLOCK_OUT') ||
          type.contains('TIME OUT') ||
          type.contains('TIME_OUT');

  // ═══════════════════════════════════════════════════════════
  // PRESENT DAYS MAP (bulk)
  // ═══════════════════════════════════════════════════════════
  static Future<Map<String, int>> fetchPresentDaysMap({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final result = <String, Set<String>>{};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .get();

      for (final d in snap.docs) {
        final data = d.data();
        final empId = (data['employee_id'] ??
            data['employeeId'] ??
            data['empId'] ??
            '')
            .toString()
            .trim();
        if (empId.isEmpty) continue;

        final ts = _parseTimestamp(data);
        if (ts == null) continue;
        if (ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
        if (ts.weekday == DateTime.saturday ||
            ts.weekday == DateTime.sunday) {
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

  // ═══════════════════════════════════════════════════════════
  // SINGLE PRESENT DAYS
  // ═══════════════════════════════════════════════════════════
  static Future<int> _fetchSinglePresentDays({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final ids = <String>{};
    for (final k in [
      'id',
      'employeeId',
      'employee_id',
      'nfcTagId',
      'authUid'
    ]) {
      final v = employee[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) ids.add(v);
    }
    if (ids.isEmpty) return 0;

    final dates = <String>{};
    for (final id in ids) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: id)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null) continue;
          if (ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
          if (ts.weekday == DateTime.saturday ||
              ts.weekday == DateTime.sunday) {
            continue;
          }
          if (_isIn(_logType(data))) {
            dates.add(_dateKey(ts));
          }
        }
      } catch (e) {
        debugPrint('⚠️ present days ($id): $e');
      }
    }
    return dates.length;
  }

  // ═══════════════════════════════════════════════════════════
  // 🍱 FETCH WORK HOURS (raw / lunch / net / OT)
  // ═══════════════════════════════════════════════════════════
  static Future<_WorkHoursResult> _fetchWorkHours({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    required WorkHoursConfig config,
  }) async {
    final ids = <String>{};
    for (final k in [
      'id',
      'employeeId',
      'employee_id',
      'nfcTagId',
      'authUid'
    ]) {
      final v = employee[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) ids.add(v);
    }
    if (ids.isEmpty) return const _WorkHoursResult();

    final Map<String, List<Map<String, dynamic>>> byDay = {};

    for (final id in ids) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: id)
            .get();

        for (final d in snap.docs) {
          final data = d.data();
          final ts = _parseTimestamp(data);
          if (ts == null) continue;
          if (ts.isBefore(periodStart) || ts.isAfter(periodEnd)) continue;
          if (ts.weekday == DateTime.saturday ||
              ts.weekday == DateTime.sunday) {
            continue;
          }
          final key = _dateKey(ts);
          byDay.putIfAbsent(key, () => []).add({...data, '_ts': ts});
        }
      } catch (e) {
        debugPrint('⚠️ work hours ($id): $e');
      }
    }

    int rawTotal = 0;
    int lunchTotal = 0;
    int netTotal = 0;
    int otTotal = 0;
    int daysWithLogs = 0;
    int daysWithLunchApplied = 0; // ✅ FIXED: naka-deklara na

    byDay.forEach((key, logs) {
      if (logs.isEmpty) return;

      logs.sort((a, b) {
        final ta = a['_ts'] as DateTime;
        final tb = b['_ts'] as DateTime;
        return ta.compareTo(tb);
      });

      DateTime? firstIn;
      DateTime? lastOut;

      for (final log in logs) {
        final type = _logType(log);
        final ts = log['_ts'] as DateTime;
        if (_isIn(type) && firstIn == null) firstIn = ts;
        if (_isOut(type)) lastOut = ts;
      }

      if (firstIn == null && logs.isNotEmpty) {
        firstIn = logs.first['_ts'] as DateTime;
      }
      if (lastOut == null && logs.length > 1) {
        lastOut = logs.last['_ts'] as DateTime;
      }

      if (firstIn == null || lastOut == null) {
        for (final log in logs) {
          final rawIn = log['timeIn'] ?? log['clockIn'] ?? log['in'];
          final rawOut = log['timeOut'] ?? log['clockOut'] ?? log['out'];
          final pIn = rawIn is Timestamp ? rawIn.toDate() : null;
          final pOut = rawOut is Timestamp ? rawOut.toDate() : null;
          if (pIn != null && pOut != null) {
            firstIn = pIn;
            lastOut = pOut;
            break;
          }
        }
      }

      if (firstIn == null || lastOut == null) return;
      if (!lastOut.isAfter(firstIn)) return;

      final raw = lastOut.difference(firstIn).inMinutes;
      if (raw <= 0) return;

      int lunch = 0;
      if (raw >= config.lunchThresholdMinutes) {
        lunch = config.lunchBreakMinutes;
      }

      final net = (raw - lunch).clamp(0, 24 * 60);
      final ot =
      net > config.standardMinutesPerDay ? net - config.standardMinutesPerDay : 0;

      rawTotal += raw;
      lunchTotal += lunch;
      netTotal += net;
      otTotal += ot;
      daysWithLogs++;
      if (lunch > 0) daysWithLunchApplied++; // ✅ OK na
    });

    return _WorkHoursResult(
      rawMinutes: rawTotal,
      lunchMinutes: lunchTotal,
      netMinutes: netTotal,
      overtimeMinutes: otTotal,
      daysWithLogs: daysWithLogs,
      daysWithLunchApplied: daysWithLunchApplied, // ✅ OK na
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 📥 FETCH WorkHoursConfig
  // ═══════════════════════════════════════════════════════════
  static Future<WorkHoursConfig> fetchWorkHoursConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('work_hours_config')
          .get();
      if (doc.exists) {
        return WorkHoursConfig.fromMap(doc.data());
      }
    } catch (e) {
      debugPrint('⚠️ fetchWorkHoursConfig: $e');
    }
    return WorkHoursConfig.fallback;
  }

  // ═══════════════════════════════════════════════════════════
  // 🧮 MAIN COMPUTE
  // ═══════════════════════════════════════════════════════════
  static Future<PayrollBreakdown> compute({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    int? presentDaysOverride,
    bool fetchAttendance = true,
    bool fetchWorkHoursData = true,
    WorkHoursConfig? workHoursConfig,
  }) async {
    // ─── 💰 Salary fields ──────────────────────────────────
    final basic = toDbl(employee['basicSalary']);

    final basicAllow = toDbl(
      employee['basicAllowance'] ?? employee['allowances'],
    );
    final housingAllow = toDbl(employee['housingAllowance']);
    final transportAllow = toDbl(employee['transportAllowance']);
    final specialAllow = toDbl(employee['specialAllowance']);

    final allowances =
        basicAllow + housingAllow + transportAllow + specialAllow;
    final overtime = toDbl(employee['overtimePay']);
    final gross = basic + allowances + overtime;

    // ─── 📅 Working days ───────────────────────────────────
    final workingDays = countWeekdays(periodStart, periodEnd) > 0
        ? countWeekdays(periodStart, periodEnd)
        : defaultWorkingDays;

    final configuredWorkingDays =
    toInt(employee['workingDaysPerMonth'], defaultWorkingDays);
    final effectiveWorkingDays =
    configuredWorkingDays > 0 ? configuredWorkingDays : defaultWorkingDays;

    final savedDailyRate = toDbl(employee['dailyRate']);
    final dailyRate = savedDailyRate > 0
        ? savedDailyRate
        : (basic > 0 ? basic / effectiveWorkingDays : 0.0);

    final salarySource =
        (employee['salarySource'] as String?)?.trim() ?? 'manual';

    // ─── 👤 Present days ───────────────────────────────────
    int present = presentDaysOverride ?? 0;
    if (presentDaysOverride == null && fetchAttendance) {
      present = await _fetchSinglePresentDays(
        employee: employee,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
    }
    final absent = (workingDays - present).clamp(0, workingDays);

    final absenceDeduction = dailyRate * absent;

    // ─── 🍱 Work hours ─────────────────────────────────────
    _WorkHoursResult workHours = const _WorkHoursResult();
    if (fetchWorkHoursData) {
      final cfg = workHoursConfig ?? await fetchWorkHoursConfig();
      workHours = await _fetchWorkHours(
        employee: employee,
        periodStart: periodStart,
        periodEnd: periodEnd,
        config: cfg,
      );
    }

    // ─── 🎁 Benefits ───────────────────────────────────────
    final thirteenth = basic / 12;
    final silCredits = dailyRate * 5;
    final totalBenefits = thirteenth + silCredits;

    // ─── 🏛️ Government ─────────────────────────────────────
    final sss = basic * sssRate;
    final philhealth = basic * philhealthRate;
    final pagibig = basic * pagibigRate;
    const withholdingTax = 0.0;

    final totalDeductions =
        absenceDeduction + sss + philhealth + pagibig + withholdingTax;
    final netPay = gross - totalDeductions;

    return PayrollBreakdown(
      basicSalary: basic,
      allowances: allowances,
      overtimePay: overtime,
      grossPay: gross,
      thirteenthMonth: thirteenth,
      silCredits: silCredits,
      totalBenefits: totalBenefits,
      workingDays: workingDays,
      workingDaysPerMonth: effectiveWorkingDays,
      presentDays: present,
      absentDays: absent,
      dailyRate: dailyRate,
      absenceDeduction: absenceDeduction,
      workRawMinutes: workHours.rawMinutes,
      workLunchMinutes: workHours.lunchMinutes,
      workNetMinutes: workHours.netMinutes,
      workOvertimeMinutes: workHours.overtimeMinutes,
      daysWithLogs: workHours.daysWithLogs,
      daysWithLunchApplied: workHours.daysWithLunchApplied,
      salarySource: salarySource,
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      withholdingTax: withholdingTax,
      totalDeductions: totalDeductions,
      netPay: netPay,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 💱 PESO FORMATTER
  // ═══════════════════════════════════════════════════════════
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