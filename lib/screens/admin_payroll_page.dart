// lib/screens/admin_payroll_page.dart
// v2.4: 🎭 Demo Mode Support (Mock Employees & Export Blocking)
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
import '../services/demo_mode_service.dart'; // 🎭 Added

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

  // 🎭 Demo Mode Getter
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

  // ─── SECURITY GUARDS ────────────────────────────────────────
  final _SecurityGuard _guard = _SecurityGuard();
  bool _isAdminVerified = false;

  static const int _maxSearchLen = 100;

  DateTime get _periodStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }

  DateTime get _periodEnd {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0, 23, 59, 59);
  }

  // 🎭 MOCK EMPLOYEES
  List<Map<String, dynamic>> _getMockEmployees() {
    return [
      {
        'id': 'demo_emp_1',
        'employeeId': 'DEMO-001',
        'name': 'John Doe',
        'firstName': 'John',
        'lastName': 'Doe',
        'department': 'Operation',
        'role': 'Manager',
        'basicSalary': 45000.0,
        'allowances': 5000.0,
        'workingDaysPerMonth': 22,
        'payrollStatus': 'PROCESSED',
        'accountNumber': '1234567890',
        'bankName': 'BDO',
      },
      {
        'id': 'demo_emp_2',
        'employeeId': 'DEMO-002',
        'name': 'Jane Smith',
        'firstName': 'Jane',
        'lastName': 'Smith',
        'department': 'Accounting',
        'role': 'Accountant',
        'basicSalary': 25000.0,
        'allowances': 3000.0,
        'workingDaysPerMonth': 22,
        'payrollStatus': 'PENDING',
        'accountNumber': '0987654321',
        'bankName': 'BPI',
      },
      {
        'id': 'demo_emp_3',
        'employeeId': 'DEMO-003',
        'name': 'Mike Johnson',
        'firstName': 'Mike',
        'lastName': 'Johnson',
        'department': 'HR/Admin',
        'role': 'Driver',
        'basicSalary': 16000.0,
        'allowances': 1500.0,
        'workingDaysPerMonth': 22,
        'payrollStatus': 'PROCESSED',
        'accountNumber': '1122334455',
        'bankName': 'Metrobank',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    if (_isDemo) {
      _isAdminVerified = true;
      _loadingAttendance = false;
      // Mock attendance data so it doesn't show 0s
      _presentDaysMap = {
        'demo_emp_1': 22,
        'demo_emp_2': 20,
        'demo_emp_3': 18,
      };
    } else {
      _verifyAndLoad();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // 🔒 SECURITY HELPERS
  // ══════════════════════════════════════════════════════════════
  void _demoBlock() {
    _toast('Action disabled in Demo Mode.', error: true);
  }

  static String _sanitize(dynamic raw, {int maxLen = 200}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  String _safeError(Object e) {
    if (kDebugMode) return e.toString();
    return 'Something went wrong. Please try again.';
  }

  Future<User?> _currentAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      await u.getIdToken(true);
      return u;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureAdmin() async {
    if (_isDemo) return true;
    return FirebaseAuth.instance.currentUser != null;
  }

  /// 🚨 CSV INJECTION DEFENSE
  String _csvSanitizeCell(dynamic raw) {
    var s = (raw ?? '').toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    if (s.isNotEmpty) {
      final first = s[0];
      if (first == '=' ||
          first == '+' ||
          first == '-' ||
          first == '@' ||
          first == '\t' ||
          first == '\r' ||
          first == '\n') {
        s = "'$s";
      }
    }
    return s;
  }

  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _csvCell(dynamic raw) => _csvEscape(_csvSanitizeCell(raw));

  String _maskAccount(String? acct) {
    if (acct == null || acct.isEmpty) return '';
    final clean = acct.replaceAll(RegExp(r'\s'), '');
    if (clean.length <= 4) return '****';
    return '${'*' * (clean.length - 4)}${clean.substring(clean.length - 4)}';
  }

  Future<void> _audit({
    required String action,
    required String targetId,
    required String targetType,
    Map<String, dynamic>? metadata,
  }) async {
    if (_isDemo) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_action',
        'action': action,
        'targetId': targetId,
        'targetType': targetType,
        'actorUid': uid,
        'metadata': metadata ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ payroll audit failed: $e');
    }
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

  // ══════════════════════════════════════════════════════════════
  // LOAD + ADMIN GUARD
  // ══════════════════════════════════════════════════════════════
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
    if (_isDemo) {
      return EmployeeHoursSummary.empty;
    }
    for (final k in [
      'id',
      'employeeId',
      'employee_id',
      'nfcTagId',
      'authUid'
    ]) {
      final key = emp[k]?.toString().trim();
      if (key != null && key.isNotEmpty && _hoursMap.containsKey(key)) {
        return _hoursMap[key]!;
      }
    }
    return EmployeeHoursSummary.empty;
  }

  // ══════════════════════════════════════════════════════════════
  // PAYROLL COMPUTATION
  // ══════════════════════════════════════════════════════════════
  PayrollBreakdown _computeForEmp(Map<String, dynamic> emp) {
    int? present;
    for (final k in [
      'id',
      'employeeId',
      'employee_id',
      'nfcTagId',
      'authUid'
    ]) {
      final key = emp[k]?.toString().trim();
      if (key != null && key.isNotEmpty && _presentDaysMap.containsKey(key)) {
        present = _presentDaysMap[key];
        break;
      }
    }

    final hrs = _getHoursFor(emp);

    final workingDays = PayrollCalculator.countWeekdays(
      _periodStart,
      _periodEnd,
    );
    final basic = PayrollCalculator.toDbl(emp['basicSalary']);
    final allowances =
        PayrollCalculator.toDbl(emp['basicAllowance'] ?? emp['allowances']) +
            PayrollCalculator.toDbl(emp['housingAllowance']) +
            PayrollCalculator.toDbl(emp['transportAllowance']) +
            PayrollCalculator.toDbl(emp['specialAllowance']);
    final overtime = PayrollCalculator.toDbl(emp['overtimePay']);
    final gross = basic + allowances + overtime;

    final configuredWD = PayrollCalculator.toInt(
      emp['workingDaysPerMonth'],
      22,
    );
    final workingDaysPerMonth = configuredWD > 0 ? configuredWD : 22;
    final salarySource = (emp['salarySource'] as String?) ?? 'manual';

    final savedDaily = PayrollCalculator.toDbl(emp['dailyRate']);
    final dailyRate = savedDaily > 0
        ? savedDaily
        : (workingDaysPerMonth > 0 ? basic / workingDaysPerMonth : 0.0);

    final wd = workingDays > 0 ? workingDays : 22;
    final p = present ?? 0;
    final absent = (wd - p).clamp(0, wd).toInt();
    final absenceDeduction = dailyRate * absent;

    final sss = basic * PayrollCalculator.sssRate;
    final ph = basic * PayrollCalculator.philhealthRate;
    final pi = basic * PayrollCalculator.pagibigRate;
    const tax = 0.0;

    final totalDed = absenceDeduction + sss + ph + pi + tax;
    final net = gross - totalDed;

    final netMinutes = hrs.totalNetMinutes;
    final lunchMinutes = hrs.totalLunchDeductedMinutes;
    final otMinutes = hrs.totalOvertimeMinutes;
    final rawMinutes = netMinutes + lunchMinutes;

    final taxable =
    (gross - (sss + ph + pi)).clamp(0.0, double.infinity).toDouble();

    return PayrollBreakdown(
      // Regular + Basic
      regularPay: basic + allowances,
      basicSalary: basic,
      basicHours: p * 8.0,

      // Attendance deductions (positive para sa display)
      absentAmount: absenceDeduction,
      absentHours: absent * 8.0,

      // Wala pang data source — default zero
      lateAmount: 0.0,
      lateHours: 0.0,
      undertimeAmount: 0.0,
      undertimeHours: 0.0,
      dayOffOtAmount: 0.0,
      dayOffOtHours: 0.0,

      // Overtime
      overtimeAmount: overtime,
      overtimeHours: otMinutes / 60.0,

      // Premium — wala pang source
      nightDiffAmount: 0.0,
      nightDiffHours: 0.0,
      holidayAmount: 0.0,

      // Other earnings
      otherIncomeAllowance: allowances,
      totalAdjustmentsMade: 0.0,

      // Gross
      grossPay: gross,

      // Benefits
      thirteenthMonth: basic / 12,
      silCredits: dailyRate * 5,
      totalBenefits: (basic / 12) + (dailyRate * 5),

      // Attendance context
      workingDays: wd,
      workingDaysPerMonth: workingDaysPerMonth,
      presentDays: p,
      absentDays: absent,
      dailyRate: dailyRate,

      // Work hours context
      workRawMinutes: rawMinutes,
      workLunchMinutes: lunchMinutes,
      workNetMinutes: netMinutes,
      workOvertimeMinutes: otMinutes,
      daysWithLogs: p,
      daysWithLunchApplied: lunchMinutes > 0 ? p : 0,

      salarySource: salarySource,

      // Deductions
      sss: sss,
      philhealth: ph,
      pagibig: pi,
      taxableIncome: taxable,
      taxWithheld: tax,
      totalLoanDeductions: 0.0,
      totalDeductions: totalDed,
      netPay: net,

      // Leave & other income
      sickLeaveBalance:
      PayrollCalculator.toDbl(emp['sickLeaveBalance']).abs() > 0
          ? PayrollCalculator.toDbl(emp['sickLeaveBalance'])
          : 120.0,
      vacationLeaveBalance:
      PayrollCalculator.toDbl(emp['vacationLeaveBalance']).abs() > 0
          ? PayrollCalculator.toDbl(emp['vacationLeaveBalance'])
          : 120.0,
      riceAllowance: PayrollCalculator.toDbl(emp['riceAllowance']),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 📤 CSV EXPORT
  // ══════════════════════════════════════════════════════════════
  Future<void> _exportPayrollToCsv() async {
    if (_isDemo) return _demoBlock();
    if (_exporting) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('Walang permission. Admin-only action.', error: true);
      return;
    }

    if (!_guard.tryAcquire('export_payroll')) {
      _toast('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    final safeQuery = _sanitize(_searchQuery, maxLen: _maxSearchLen)
        .toLowerCase();

    const canonicalDepts = <String>[
      'HR/Admin',
      'Accounting',
      'Operation',
    ];

    final departments = <String>['All Departments', ...canonicalDepts];

    final seenLower = departments.map((d) => d.toLowerCase()).toSet();
    for (var emp in (_isDemo ? _getMockEmployees() : widget.employees)) {
      final dept = emp['department']?.toString().trim();
      if (dept == null || dept.isEmpty) continue;
      if (seenLower.contains(dept.toLowerCase())) continue;
      departments.add(dept);
      seenLower.add(dept.toLowerCase());
    }

    final filtered = (_isDemo ? _getMockEmployees() : widget.employees).where((emp) {
      final name = (emp['name'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .toLowerCase();
      final id =
      (emp['id'] ?? emp['employeeId'] ?? '').toString().toLowerCase();
      final dept = (emp['department'] ?? '').toString();

      final matchesSearch = safeQuery.isEmpty ||
          name.contains(safeQuery) ||
          id.contains(safeQuery);
      final matchesDept = _selectedDepartment == 'All Departments' ||
          dept.toLowerCase() == _selectedDepartment.toLowerCase();

      return emp['terminated'] != true && matchesSearch && matchesDept;
    }).toList();

    if (filtered.isEmpty) {
      _toast('No employees to export.', error: true);
      return;
    }

    setState(() => _exporting = true);

    try {
      const headers = <String>[
        'employee_id',
        'document_id',
        'name',
        'first_name',
        'last_name',
        'email',
        'department',
        'role',
        'device_name',
        'bank_name',
        'account_number',
        'payroll_status',
        'salary_source',
        'pay_period',
        'period_start',
        'period_end',
        'basic_salary',
        'allowances',
        'overtime_pay',
        'gross_pay',
        'thirteenth_month',
        'sil_credits',
        'total_benefits',
        'working_days',
        'working_days_per_month',
        'present_days',
        'absent_days',
        'daily_rate',
        'absence_deduction',
        'work_raw_hours',
        'work_lunch_hours',
        'work_net_hours',
        'work_overtime_hours',
        'days_with_logs',
        'days_with_lunch_applied',
        'sss',
        'philhealth',
        'pagibig',
        'withholding_tax',
        'total_deductions',
        'net_pay',
      ];

      final buffer = StringBuffer();
      buffer.write('\uFEFF');
      buffer.write(headers.map(_csvCell).join(','));
      buffer.write('\r\n');

      for (final emp in filtered) {
        final b = _computeForEmp(emp);

        final fullName = (emp['name'] ??
            '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
            .toString()
            .trim();

        final row = <String>[
          _csvCell(emp['employeeId'] ?? emp['employee_id'] ?? ''),
          _csvCell(emp['id'] ?? ''),
          _csvCell(fullName),
          _csvCell(emp['firstName'] ?? ''),
          _csvCell(emp['lastName'] ?? ''),
          _csvCell(emp['email'] ?? ''),
          _csvCell(emp['department'] ?? ''),
          _csvCell(emp['role'] ?? ''),
          _csvCell(emp['deviceName'] ?? ''),
          _csvCell(emp['bankName'] ?? ''),
          _csvCell(_maskAccount(emp['accountNumber']?.toString())),
          _csvCell(emp['payrollStatus'] ?? 'Processed'),
          _csvCell(emp['salarySource'] ?? 'manual'),
          _csvCell(_selectedPayPeriod),
          _csvCell(DateFormat('yyyy-MM-dd').format(_periodStart)),
          _csvCell(DateFormat('yyyy-MM-dd').format(_periodEnd)),
          _csvCell(b.basicSalary.toStringAsFixed(2)),
          _csvCell(b.otherIncomeAllowance.toStringAsFixed(2)),
          _csvCell(b.overtimeAmount.toStringAsFixed(2)),
          _csvCell(b.grossPay.toStringAsFixed(2)),
          _csvCell(b.thirteenthMonth.toStringAsFixed(2)),
          _csvCell(b.silCredits.toStringAsFixed(2)),
          _csvCell(b.totalBenefits.toStringAsFixed(2)),
          _csvCell(b.workingDays.toString()),
          _csvCell(b.workingDaysPerMonth.toString()),
          _csvCell(b.presentDays.toString()),
          _csvCell(b.absentDays.toString()),
          _csvCell(b.dailyRate.toStringAsFixed(2)),
          _csvCell(b.absentAmount.toStringAsFixed(2)),
          _csvCell(_minutesToHours(b.workRawMinutes)),
          _csvCell(_minutesToHours(b.workLunchMinutes)),
          _csvCell(_minutesToHours(b.workNetMinutes)),
          _csvCell(_minutesToHours(b.workOvertimeMinutes)),
          _csvCell(b.daysWithLogs.toString()),
          _csvCell(b.daysWithLunchApplied.toString()),
          _csvCell(b.sss.toStringAsFixed(2)),
          _csvCell(b.philhealth.toStringAsFixed(2)),
          _csvCell(b.pagibig.toStringAsFixed(2)),
          _csvCell(b.taxWithheld.toStringAsFixed(2)),
          _csvCell(b.totalDeductions.toStringAsFixed(2)),
          _csvCell(b.netPay.toStringAsFixed(2)),
        ];

        buffer.write(row.join(','));
        buffer.write('\r\n');
      }

      final tsStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final periodTag =
      _sanitize(_selectedPayPeriod, maxLen: 30).replaceAll(' ', '_').toLowerCase();
      final fileName = 'payroll_${periodTag}_$tsStr.csv';

      final savedPath = await downloadTextFile(
        filename: fileName,
        content: buffer.toString(),
      );

      unawaited(_audit(
        action: 'export_payroll_csv',
        targetId: fileName,
        targetType: 'payroll_export',
        metadata: {
          'employee_count': filtered.length,
          'pay_period': _selectedPayPeriod,
          'department': _selectedDepartment,
          'had_search': _searchQuery.isNotEmpty,
          'success': savedPath != null,
        },
      ));

      if (!mounted) return;

      if (savedPath != null) {
        _toast(
          'Exported ${filtered.length} employee(s) → $fileName',
          success: true,
        );
      } else {
        _toast('Export failed or cancelled.', error: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Payroll CSV export error: $e');
      if (!mounted) return;
      _toast(_safeError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _minutesToHours(int minutes) {
    if (minutes <= 0) return '0.00';
    return (minutes / 60.0).toStringAsFixed(2);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_loadingAttendance && !_isDemo) {
      return Container(
        color: tc.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 48, color: tc.red),
                const SizedBox(height: 12),
                Text('Admin access required',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tc.text)),
                const SizedBox(height: 6),
                Text(
                  'Kailangan ng admin role para makita ang payroll.',
                  style: TextStyle(fontSize: 13, color: tc.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    const canonicalDepts = <String>[
      'HR/Admin',
      'Accounting',
      'Operation',
    ];

    final departments = <String>['All Departments', ...canonicalDepts];

    final sourceEmployees = _isDemo ? _getMockEmployees() : widget.employees;

    final seenLower = departments.map((d) => d.toLowerCase()).toSet();
    for (var emp in sourceEmployees) {
      final dept = emp['department']?.toString().trim();
      if (dept == null || dept.isEmpty) continue;
      if (seenLower.contains(dept.toLowerCase())) continue;
      departments.add(dept);
      seenLower.add(dept.toLowerCase());
    }

    final filtered = sourceEmployees.where((emp) {
      final name = (emp['name'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .toLowerCase();
      final id =
      (emp['id'] ?? emp['employeeId'] ?? '').toString().toLowerCase();
      final dept = (emp['department'] ?? '').toString();

      final matchesSearch = _searchQuery.isEmpty ||
          name.contains(_searchQuery.toLowerCase()) ||
          id.contains(_searchQuery.toLowerCase());
      final matchesDept = _selectedDepartment == 'All Departments' ||
          dept.toLowerCase() == _selectedDepartment.toLowerCase();

      return emp['terminated'] != true && matchesSearch && matchesDept;
    }).toList();

    double totalNet = 0;
    double totalDeductions = 0;
    double totalAbsences = 0;
    int totalNetMinutes = 0;
    int totalOTMinutes = 0;
    int pendingCount = 0;

    for (final emp in filtered) {
      final b = _computeForEmp(emp);
      final hrs = _getHoursFor(emp);
      totalNet += b.netPay;
      totalDeductions += b.totalDeductions;
      totalAbsences += b.absentAmount;
      totalNetMinutes += hrs.totalNetMinutes;
      totalOTMinutes += hrs.totalOvertimeMinutes;

      final s =
      (emp['payrollStatus'] ?? 'Processed').toString().toLowerCase();
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
              // 🎭 DEMO BANNER
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 24),
              ],
              _buildPageHeader(),
              const SizedBox(height: 20),
              _buildSearchBar(),
              const SizedBox(height: 16),
              _buildStatsRow(
                totalNet,
                pendingCount,
                totalDeductions,
                totalAbsences,
                totalNetMinutes,
                totalOTMinutes,
              ),
              const SizedBox(height: 20),
              _buildFiltersRow(departments),
              const SizedBox(height: 16),
              if (_loadingAttendance)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: tc.orange),
                      ),
                      const SizedBox(width: 10),
                      Text('Kinukuha ang attendance at hours logs...',
                          style: TextStyle(fontSize: 12, color: tc.muted)),
                    ],
                  ),
                ),
              _buildTable(filtered),
              const SizedBox(height: 16),
              Text(
                'Showing ${filtered.length} of ${sourceEmployees.length} employees',
                style: TextStyle(fontSize: 12, color: tc.muted),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.orange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, color: tc.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tc.orange,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Showing sample data. Exporting payroll is disabled.',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
      final narrow = w < 720;

      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payroll Management',
              style: TextStyle(
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w800,
                  color: tc.text,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(
              'Manage and review employee disbursements — absences at lunch break auto-deducted.',
              style: TextStyle(fontSize: 13, color: tc.muted)),
        ],
      );

      final refresh = OutlinedButton.icon(
        onPressed: (_loadingAttendance || _isDemo) ? null : _loadAll,
        icon: Icon(Icons.refresh, size: 16, color: _isDemo ? tc.muted : tc.text),
        label: Text('Refresh',
            style: TextStyle(
                color: _isDemo ? tc.muted : tc.text, fontWeight: FontWeight.w600, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          backgroundColor: tc.card,
          side: BorderSide(color: tc.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      final export = ElevatedButton.icon(
        onPressed:
        (_exporting || _loadingAttendance || _isDemo) ? null : _exportPayrollToCsv,
        icon: _exporting
            ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : Icon(Icons.download, size: 16, color: _isDemo ? tc.muted : Colors.white),
        label: Text(
          _exporting ? 'Exporting...' : 'Export to CSV',
          style: TextStyle(
              color: _isDemo ? tc.muted : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isDemo ? tc.border : tc.orange,
          disabledBackgroundColor: tc.orange.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: export),
              const SizedBox(width: 10),
              refresh,
            ]),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: title),
          const SizedBox(width: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            refresh,
            const SizedBox(width: 10),
            export,
          ]),
        ],
      );
    });
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 18, color: tc.muted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            maxLength: _maxSearchLen,
            onChanged: (v) {
              final cleaned = _sanitize(v, maxLen: _maxSearchLen);
              setState(() => _searchQuery = cleaned);
            },
            style: TextStyle(color: tc.text, fontSize: 14),
            cursorColor: tc.orange,
            decoration: InputDecoration(
              hintText: 'Search by name or employee ID...',
              hintStyle: TextStyle(color: tc.muted, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: tc.muted),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _searchQuery = '');
            },
          ),
      ]),
    );
  }

  Widget _buildStatsRow(
      double totalNet,
      int pending,
      double totalDed,
      double totalAbs,
      int totalNetMinutes,
      int totalOTMinutes,
      ) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
      final wide = w >= 1100;
      const gap = 16.0;

      String fmtHours(int m) {
        final h = m ~/ 60;
        final mm = m % 60;
        if (mm == 0) return '${h}h';
        return '${h}h ${mm}m';
      }

      final cards = <Widget>[
        _statCard('TOTAL NET DISBURSEMENT', PayrollCalculator.peso(totalNet),
            Icons.account_balance_wallet_outlined, false),
        _statCard('TOTAL HOURS', fmtHours(totalNetMinutes),
            Icons.schedule_rounded, false),
        _statCard('OVERTIME HOURS', fmtHours(totalOTMinutes),
            Icons.timer_rounded, false),
        _statCard('TOTAL DEDUCTIONS', PayrollCalculator.peso(totalDed),
            Icons.trending_down_rounded, true),
        _statCard('ABSENCE KALTAS', PayrollCalculator.peso(totalAbs),
            Icons.event_busy_outlined, true),
        _statCard('PENDING', '$pending Employees',
            Icons.pending_actions_rounded, false),
      ];

      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: gap),
            ]
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(height: gap),
          ]
        ],
      );
    });
  }

  Widget _statCard(String title, String value, IconData icon, bool danger) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tc.muted,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: danger ? tc.red : tc.text),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.border),
            ),
            child: Icon(icon, size: 28, color: tc.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow(List<String> departments) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          height: 42,
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedPayPeriod,
              dropdownColor: tc.card,
              icon:
              Icon(Icons.keyboard_arrow_down, size: 16, color: tc.muted),
              items: const ['Current Month', 'Last Month'].map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(p,
                      style: TextStyle(
                          fontSize: 13,
                          color: tc.text,
                          fontWeight: FontWeight.w500)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedPayPeriod = v);
              },
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          height: 42,
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDepartment,
              dropdownColor: tc.card,
              icon:
              Icon(Icons.keyboard_arrow_down, size: 16, color: tc.muted),
              items: departments.map((d) {
                return DropdownMenuItem(
                  value: d,
                  child: Text(_sanitize(d, maxLen: 60),
                      style: TextStyle(
                          fontSize: 13,
                          color: tc.text,
                          fontWeight: FontWeight.w500)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedDepartment = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> employees) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;

          if (employees.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.people_outline_rounded,
                        size: 48, color: tc.muted),
                    const SizedBox(height: 12),
                    Text('No employees match your filters.',
                        style: TextStyle(color: tc.muted, fontSize: 14)),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: w),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(tc.surface),
                dataRowMinHeight: 68,
                dataRowMaxHeight: 78,
                columnSpacing: 24,
                columns: [
                  _col('EMPLOYEE'),
                  _col('BASIC'),
                  _col('HOURS'),
                  _col('ABSENCES'),
                  _col('GOVT (9%)'),
                  _col('NET PAY'),
                  _col('STATUS'),
                  _col('ACTION'),
                ],
                rows: employees.map((emp) {
                  final b = _computeForEmp(emp);
                  final hrs = _getHoursFor(emp);
                  final name = _sanitize(
                    emp['name'] ??
                        '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}',
                    maxLen: 80,
                  );
                  final initials = _getInitials(name);
                  final rawId =
                  (emp['id'] ?? emp['employeeId'] ?? 'N/A').toString();
                  final displayId = rawId.length > 10
                      ? '${rawId.substring(0, 8)}...'
                      : rawId;
                  final status = (emp['payrollStatus'] ?? 'PROCESSED')
                      .toString()
                      .toUpperCase();
                  final govt =
                      b.sss + b.philhealth + b.pagibig + b.taxWithheld;

                  return DataRow(cells: [
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                          tc.orange.withValues(alpha: 0.15),
                          child: Text(initials,
                              style: TextStyle(
                                  color: tc.orangeText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints:
                          const BoxConstraints(maxWidth: 180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: tc.text),
                                  overflow: TextOverflow.ellipsis),
                              Text('ID: $displayId',
                                  style: TextStyle(
                                      fontSize: 11, color: tc.muted)),
                            ],
                          ),
                        ),
                      ],
                    )),
                    DataCell(Text(
                        b.basicSalary > 0
                            ? PayrollCalculator.peso(b.basicSalary)
                            : 'Not set',
                        style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: b.basicSalary > 0 ? tc.text : tc.muted))),
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(hrs.netDisplay,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tc.text)),
                        Text(
                          hrs.totalLunchDeductedMinutes > 0
                              ? '-${hrs.lunchDisplay} lunch'
                              : 'no lunch',
                          style: TextStyle(
                              fontSize: 10,
                              color: tc.muted,
                              fontStyle: FontStyle.italic),
                        ),
                        if (hrs.totalOvertimeMinutes > 0)
                          Text(
                            '+${hrs.overtimeDisplay} OT',
                            style: TextStyle(
                                fontSize: 10,
                                color: tc.green,
                                fontWeight: FontWeight.w700),
                          ),
                      ],
                    )),
                    DataCell(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            b.absentDays > 0
                                ? '${b.absentDays} day/s'
                                : 'Perfect',
                            style: TextStyle(
                                color: b.absentDays > 0 ? tc.red : tc.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        Text('-${PayrollCalculator.peso(b.absentAmount)}',
                            style: TextStyle(
                                fontSize: 11, color: tc.muted)),
                      ],
                    )),
                    DataCell(Text('-${PayrollCalculator.peso(govt)}',
                        style: TextStyle(
                            color: tc.red,
                            fontWeight: FontWeight.w500,
                            fontSize: 13))),
                    DataCell(Text(PayrollCalculator.peso(b.netPay),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: tc.orangeText))),
                    DataCell(_statusBadge(status)),
                    DataCell(IconButton(
                      icon: Icon(Icons.remove_red_eye_outlined,
                          size: 16, color: tc.muted),
                      onPressed: () => widget.onSelectEmployee(emp),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          );
        }),
      ),
    );
  }

  DataColumn _col(String label) => DataColumn(
    label: Text(label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tc.muted)),
  );

  Widget _statusBadge(String status) {
    Color bg, tx;
    if (status.contains('PROCESS')) {
      bg = tc.pillGreenBg;
      tx = tc.pillGreenTx;
    } else if (status.contains('PEND')) {
      bg = tc.pillWarnBg;
      tx = tc.pillWarnTx;
    } else {
      bg = tc.pillBlueBg;
      tx = tc.pillBlueTx;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration:
              BoxDecoration(color: tx, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(_sanitize(status, maxLen: 20),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tx,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final clean = _sanitize(name, maxLen: 80);
    final parts = clean.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'HR';
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🆕 RATE LIMITER
// ═══════════════════════════════════════════════════════════════════
class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 2);

  bool tryAcquire(String key) {
    final now = DateTime.now();
    final last = _lastCall[key];
    if (last != null && now.difference(last) < _minInterval) {
      return false;
    }
    _lastCall[key] = now;
    return true;
  }
}