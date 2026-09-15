// lib/services/payroll_calculator.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class PayrollBreakdown {
  final double basicSalary;
  final double allowances;
  final double overtimePay;
  final double grossPay;

  final double thirteenthMonth;
  final double silCredits;
  final double totalBenefits;

  final int workingDays;
  final int presentDays;
  final int absentDays;
  final double dailyRate;
  final double absenceDeduction;

  final double sss;
  final double philhealth;
  final double pagibig;
  final double withholdingTax;

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
    required this.presentDays,
    required this.absentDays,
    required this.dailyRate,
    required this.absenceDeduction,
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
    presentDays: 0,
    absentDays: 0,
    dailyRate: 0,
    absenceDeduction: 0,
    sss: 0,
    philhealth: 0,
    pagibig: 0,
    withholdingTax: 0,
    totalDeductions: 0,
    netPay: 0,
  );
}

class PayrollCalculator {
  PayrollCalculator._();

  static const double sssRate = 0.045;
  static const double philhealthRate = 0.025;
  static const double pagibigRate = 0.020;
  static const int defaultWorkingDays = 22;

  static double toDbl(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

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
    final raw = data['timestamp'];
    if (raw is Timestamp) return raw.toDate();
    final dateStr = data['date'] as String?;
    if (dateStr != null) {
      final timeStr = (data['time'] ?? '00:00').toString();
      return DateTime.tryParse('$dateStr $timeStr');
    }
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

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

        final type = (data['type'] ?? '').toString().toUpperCase();
        final isIn = type.contains('IN') || type.contains('LOGIN');
        if (!isIn) continue;

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
          final type = (data['type'] ?? '').toString().toUpperCase();
          if (type.contains('IN') || type.contains('LOGIN')) {
            dates.add(_dateKey(ts));
          }
        }
      } catch (e) {
        debugPrint('⚠️ present days ($id): $e');
      }
    }
    return dates.length;
  }

  static Future<PayrollBreakdown> compute({
    required Map<String, dynamic> employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    int? presentDaysOverride,
    bool fetchAttendance = true,
  }) async {
    final basic = toDbl(employee['basicSalary']);
    final allowances = toDbl(employee['allowances']) +
        toDbl(employee['housingAllowance']) +
        toDbl(employee['transportAllowance']) +
        toDbl(employee['specialAllowance']);
    final overtime = toDbl(employee['overtimePay']);
    final gross = basic + allowances + overtime;

    final workingDays = countWeekdays(periodStart, periodEnd) > 0
        ? countWeekdays(periodStart, periodEnd)
        : defaultWorkingDays;
    final dailyRate = workingDays > 0 ? basic / workingDays : 0.0;

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

    final thirteenth = basic / 12;
    final silCredits = dailyRate * 5;
    final totalBenefits = thirteenth + silCredits;

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
      presentDays: present,
      absentDays: absent,
      dailyRate: dailyRate,
      absenceDeduction: absenceDeduction,
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      withholdingTax: withholdingTax,
      totalDeductions: totalDeductions,
      netPay: netPay,
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