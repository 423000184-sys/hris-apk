// lib/screens/admin_payroll_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import '../utils/file_download.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/payroll_calculator.dart';
import '../services/attendance_hours_service.dart';
import '../services/demo_mode_service.dart';

class AdminPayrollPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final Function(Map<String, dynamic>) onSelectEmployee;

  const AdminPayrollPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.onSelectEmployee,
  });

  @override
  State<AdminPayrollPage> createState() => _AdminPayrollPageState();
}

class _AdminPayrollPageState extends State<AdminPayrollPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  String _selectedPayPeriod = 'Current Month';
  String _selectedDepartment = 'All Departments';
  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, int> _presentDaysMap = {};
  Map<String, EmployeeHoursSummary> _hoursMap = {};
  bool _loadingAttendance = true;
  bool _exporting = false;

  final _SecurityGuard _guard = _SecurityGuard();
  bool _isAdminVerified = false;

  DateTime get _periodStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }

  DateTime get _periodEnd {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0, 23, 59, 59);
  }

  @override
  void initState() {
    super.initState();
    if (_isDemo) {
      _isAdminVerified = true;
      _loadingAttendance = false;
      _presentDaysMap = {};
    } else {
      _verifyAndLoad();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _sanitize(dynamic raw, {int maxLen = 200}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  String _safeError(Object e) {
    if (kDebugMode) return e.toString();
    return 'Something went wrong. Please try again.';
  }

  Future<bool> _ensureAdmin() async {
    if (_isDemo) return true;
    return FirebaseAuth.instance.currentUser != null;
  }

  void _toast(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor: error ? tc.red : (success ? tc.green : tc.orange),
      ),
    );
  }

  Future<void> _verifyAndLoad() async {
    if (_isDemo) return;
    final ok = await _ensureAdmin();
    if (!mounted) return;
    if (!ok) {
      _isAdminVerified = false;
      setState(() => _loadingAttendance = false);
      _toast('Walang permission. Admin-only page.', error: true);
      return;
    }
    _isAdminVerified = true;
    await _loadAll();
  }

  Future<void> _loadAll() async {
    if (_isDemo) return;
    if (!_isAdminVerified) return;
    setState(() => _loadingAttendance = true);

    try {
      final results = await Future.wait([
        PayrollCalculator.fetchPresentDaysMap(
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        ),
        AttendanceHoursService.instance.fetchHoursMap(
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _presentDaysMap = results[0] as Map<String, int>;
        _hoursMap = results[1] as Map<String, EmployeeHoursSummary>;
        _loadingAttendance = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ payroll loadAll: $e');
      if (!mounted) return;
      setState(() => _loadingAttendance = false);
      _toast(_safeError(e), error: true);
    }
  }

  EmployeeHoursSummary _getHoursFor(Map<String, dynamic> emp) {
    if (_isDemo) return EmployeeHoursSummary.empty;
    for (final k in ['id', 'employeeId', 'employee_id', 'nfcTagId', 'authUid']) {
      final key = emp[k]?.toString().trim();
      if (key != null && key.isNotEmpty && _hoursMap.containsKey(key)) {
        return _hoursMap[key]!;
      }
    }
    return EmployeeHoursSummary.empty;
  }

  PayrollBreakdown _computeForEmp(Map<String, dynamic> emp) {
    int? present;
    for (final k in ['id', 'employeeId', 'employee_id', 'nfcTagId', 'authUid']) {
      final key = emp[k]?.toString().trim();
      if (key != null && key.isNotEmpty && _presentDaysMap.containsKey(key)) {
        present = _presentDaysMap[key];
        break;
      }
    }

    final hrs = _getHoursFor(emp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final periodEndDateOnly = DateTime(_periodEnd.year, _periodEnd.month, _periodEnd.day);

    DateTime calcStart = _periodStart;
    final dateHiredRaw = emp['dateHired'] ?? emp['createdAt'] ?? emp['date_hired'] ?? emp['created_at'];
    bool hasValidHireDate = false;

    if (dateHiredRaw != null) {
      DateTime? dh;
      if (dateHiredRaw is Timestamp) dh = dateHiredRaw.toDate();
      if (dateHiredRaw is String) dh = DateTime.tryParse(dateHiredRaw);
      if (dh != null) {
        final hireDate = DateTime(dh.year, dh.month, dh.day);
        if (hireDate.isAfter(calcStart)) calcStart = hireDate;
        hasValidHireDate = true;
      }
    }

    if (!hasValidHireDate) {
      calcStart = DateTime(now.year, now.month, now.day);
    }

    final DateTime calcEndAbsence = periodEndDateOnly.isAfter(yesterday) ? yesterday : periodEndDateOnly;

    int expectedDays = 0;
    if (!calcStart.isAfter(calcEndAbsence)) {
      DateTime tempDate = DateTime(calcStart.year, calcStart.month, calcStart.day);
      final finalEnd = DateTime(calcEndAbsence.year, calcEndAbsence.month, calcEndAbsence.day);
      while (tempDate.isBefore(finalEnd) || tempDate.isAtSameMomentAs(finalEnd)) {
        if (tempDate.weekday != DateTime.saturday && tempDate.weekday != DateTime.sunday) {
          expectedDays++;
        }
        tempDate = tempDate.add(const Duration(days: 1));
      }
    }

    final basic = PayrollCalculator.toDbl(emp['basicSalary']);
    final allowances = PayrollCalculator.toDbl(emp['basicAllowance'] ?? emp['allowances']) + PayrollCalculator.toDbl(emp['housingAllowance']) + PayrollCalculator.toDbl(emp['transportAllowance']) + PayrollCalculator.toDbl(emp['specialAllowance']);
    final workingDaysPerMonth = PayrollCalculator.toInt(emp['workingDaysPerMonth'], 22);
    final savedDaily = PayrollCalculator.toDbl(emp['dailyRate']);
    final dailyRate = savedDaily > 0 ? savedDaily : (workingDaysPerMonth > 0 ? basic / workingDaysPerMonth : 0.0);

    final p = present ?? 0;
    final absent = (expectedDays - p).clamp(0, expectedDays).toInt();

    final earnedBasic = dailyRate * p;
    final earnedAllowance = (allowances / workingDaysPerMonth) * p;
    final gross = earnedBasic + earnedAllowance;

    final sss = earnedBasic * PayrollCalculator.sssRate;
    final ph = earnedBasic * PayrollCalculator.philhealthRate;
    final pi = earnedBasic * PayrollCalculator.pagibigRate;

    final net = gross - (sss + ph + pi);

    return PayrollBreakdown(
      regularPay: gross, basicSalary: basic, basicHours: p * 8.0,
      absentAmount: dailyRate * absent, absentHours: absent * 8.0,
      lateAmount: 0, lateHours: 0, undertimeAmount: 0, undertimeHours: 0, dayOffOtAmount: 0, dayOffOtHours: 0,
      overtimeAmount: 0, overtimeHours: 0, nightDiffAmount: 0, nightDiffHours: 0, holidayAmount: 0,
      otherIncomeAllowance: allowances, totalAdjustmentsMade: 0, grossPay: gross,
      thirteenthMonth: basic / 12, silCredits: dailyRate * 5, totalBenefits: (basic / 12) + (dailyRate * 5),
      workingDays: expectedDays + 1, workingDaysPerMonth: workingDaysPerMonth, presentDays: p, absentDays: absent,
      dailyRate: dailyRate, workRawMinutes: hrs.totalNetMinutes, workLunchMinutes: 0, workNetMinutes: hrs.totalNetMinutes,
      workOvertimeMinutes: 0, daysWithLogs: p, daysWithLunchApplied: 0, salarySource: 'manual',
      sss: sss, philhealth: ph, pagibig: pi, taxableIncome: gross, taxWithheld: 0, totalLoanDeductions: 0,
      totalDeductions: sss + ph + pi, netPay: net, sickLeaveBalance: 120, vacationLeaveBalance: 120, riceAllowance: 0,
    );
  }

  Future<void> _exportPayrollToCsv() async {}

  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_loadingAttendance && !_isDemo) return Center(child: Text('Admin access required'));

    if (_loadingAttendance) {
      return Container(
        color: tc.background,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<Map<String, dynamic>> sourceEmployees = _isDemo ? <Map<String, dynamic>>[] : widget.employees;

    final filtered = sourceEmployees.where((emp) {
      final name = (emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}').toString().toLowerCase();
      return emp['terminated'] != true && (_searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase()));
    }).toList();

    double totalNet = 0;
    double totalDeductions = 0;
    double totalAbsences = 0;
    int totalNetMinutes = 0;
    int pendingCount = 0;

    for (final emp in filtered) {
      final b = _computeForEmp(emp);
      totalNet += b.netPay;
      totalDeductions += b.totalDeductions;
      totalAbsences += b.absentAmount;
      totalNetMinutes += _getHoursFor(emp).totalNetMinutes;
      final s = (emp['payrollStatus'] ?? 'Processed').toString().toLowerCase();
      if (s == 'pending' || s == 'on hold') pendingCount++;
    }

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: BsContainer(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPageHeader(), const SizedBox(height: 20),
              _buildSearchBar(), const SizedBox(height: 12),
              _buildFilters(), const SizedBox(height: 16),
              _buildStatsRow(totalNet, pendingCount, totalDeductions, totalAbsences, totalNetMinutes, 0),
              const SizedBox(height: 20),
              _buildTable(filtered), const SizedBox(height: 16),
              Text('Showing ${filtered.length} employees', style: TextStyle(fontSize: 12, color: tc.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Payroll Management', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: tc.text)),
          Text('Manage and review employee disbursements — absences at lunch break auto-deducted.', style: TextStyle(fontSize: 13, color: tc.muted)),
        ])),
        OutlinedButton.icon(onPressed: (_loadingAttendance || _isDemo) ? null : _loadAll, icon: Icon(Icons.refresh, size: 16), label: Text('Refresh')),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: (_exporting || _loadingAttendance || _isDemo) ? null : _exportPayrollToCsv,
          icon: Icon(Icons.download, size: 16),
          label: Text('Export to CSV'),
          style: ElevatedButton.styleFrom(backgroundColor: tc.orange, foregroundColor: Colors.white),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Search by name or employee ID...',
        prefixIcon: Icon(Icons.search, color: tc.muted),
        filled: true,
        fillColor: tc.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: tc.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: tc.border)),
      ),
      onChanged: (v) => setState(() => _searchQuery = v),
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: tc.card, border: Border.all(color: tc.border), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPayPeriod,
              isDense: true,
              style: TextStyle(fontSize: 12, color: tc.text),
              items: ['Current Month'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: tc.card, border: Border.all(color: tc.border), borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDepartment,
              isDense: true,
              style: TextStyle(fontSize: 12, color: tc.text),
              items: ['All Departments'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(double totalNet, int pending, double totalDed, double totalAbs, int totalNetMinutes, int totalOT) {
    final totalHoursStr = '${(totalNetMinutes / 60).toStringAsFixed(0)}h';
    final totalOTStr = '${(totalOT / 60).toStringAsFixed(0)}h';

    return Row(
      children: [
        Expanded(child: _statCard('TOTAL NET DISBURSEMENT', PayrollCalculator.peso(totalNet), Icons.money, false)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('TOTAL HOURS', totalHoursStr, Icons.access_time, false)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('OVERTIME HOURS', totalOTStr, Icons.more_time, false)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('TOTAL DEDUCTIONS', PayrollCalculator.peso(totalDed), Icons.trending_down, true)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('ABSENCE KALTAS', PayrollCalculator.peso(totalAbs), Icons.event_busy, true)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('PENDING', '$pending Employees', Icons.pending_actions, false)),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, bool danger) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: tc.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tc.muted))),
              Icon(icon, size: 16, color: tc.muted),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: danger ? tc.red : tc.text)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FIXED TABLE TO STRETCH TO THE END
  // ══════════════════════════════════════════════════════════════
  Widget _buildTable(List<Map<String, dynamic>> employees) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: tc.border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder( // <-- Added to get the max width of the screen
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox( // <-- Forces the table to stretch to the end
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(tc.surface),
              columns: [
                _col('EMPLOYEE'),
                _col('BASIC'),
                _col('HOURS'),
                _col('ABSENCES'),
                _col('GOVT (9%)'),
                _col('NET PAY'),
                _col('STATUS'),
                _col('ACTION')
              ],
              rows: employees.map((emp) {
                final b = _computeForEmp(emp);
                final hrs = _getHoursFor(emp);
                final name = emp['name'] ?? '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}';
              final id = emp['id'] ?? emp['employeeId'] ?? emp['employee_id'] ?? '---';
              final govt = b.sss + b.philhealth + b.pagibig + b.taxWithheld;
              final status = (emp['payrollStatus'] ?? 'Processed').toString().toUpperCase();

              return DataRow(cells: [
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: tc.text)),
                    Text('ID: $id', style: TextStyle(fontSize: 10, color: tc.muted)),
                  ],
                )),
                DataCell(Text(PayrollCalculator.peso(b.basicSalary), style: TextStyle(color: tc.text))),
                DataCell(Text('${(hrs.totalNetMinutes / 60).toStringAsFixed(0)}h', style: TextStyle(color: tc.text))),
                DataCell(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${b.absentDays} day/s', style: TextStyle(color: b.absentDays > 0 ? tc.red : tc.green, fontWeight: FontWeight.w600)),
                    Text('-${PayrollCalculator.peso(b.absentAmount)}', style: TextStyle(fontSize: 10, color: tc.muted)),
                  ],
                )),
                DataCell(Text('-${PayrollCalculator.peso(govt)}', style: TextStyle(color: tc.red))),
                DataCell(Text(PayrollCalculator.peso(b.netPay), style: TextStyle(color: tc.orangeText, fontWeight: FontWeight.bold))),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'PROCESSED' ? tc.green.withOpacity(0.1) : tc.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: status == 'PROCESSED' ? tc.green.withOpacity(0.3) : tc.orange.withOpacity(0.3)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: status == 'PROCESSED' ? tc.green : tc.orange),
                    ),
                  ),
                ),
                DataCell(
                  IconButton(
                    icon: Icon(Icons.visibility, size: 18, color: tc.muted),
                    onPressed: () => widget.onSelectEmployee(emp),
                  ),
                ),
              ]);
              }).toList(),
            ),
            ),
          );
        },
        ),
      ),
    );
  }

  DataColumn _col(String label) => DataColumn(label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tc.muted)));
}

class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 2);
  bool tryAcquire(String key) {
    final now = DateTime.now();
    final last = _lastCall[key];
    if (last != null && now.difference(last) < _minInterval) return false;
    _lastCall[key] = now; return true;
  }
}
