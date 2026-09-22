// lib/screens/admin_payroll_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // ✅ NEW — para sa date formatting sa export
import 'admin_theme.dart';
import '../utils/file_download.dart'; // ✅ NEW — CSV export helper
import '../widgets/bootstrap_grid.dart';
import '../services/payroll_calculator.dart';
import '../services/attendance_hours_service.dart';

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

  String _selectedPayPeriod = 'Current Month';
  String _selectedDepartment = 'All Departments';
  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  Map<String, int> _presentDaysMap = {};
  Map<String, EmployeeHoursSummary> _hoursMap = {};
  bool _loadingAttendance = true;
  bool _exporting = false; // ✅ NEW

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
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loadingAttendance = true);

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Look up hours summary for employee
  EmployeeHoursSummary _getHoursFor(Map<String, dynamic> emp) {
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
  // ✅ _computeForEmp
  // ══════════════════════════════════════════════════════════════
  PayrollBreakdown _computeForEmp(Map<String, dynamic> emp) {
    // ─── Present days lookup ────────────────────────────────
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

    // ─── Hours summary lookup ───────────────────────────────
    final hrs = _getHoursFor(emp);

    // ─── Basic fields ───────────────────────────────────────
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

    // ─── 💰 Salary config from Firestore ────────────────────
    final configuredWD = PayrollCalculator.toInt(
      emp['workingDaysPerMonth'],
      22,
    );
    final workingDaysPerMonth = configuredWD > 0 ? configuredWD : 22;
    final salarySource = (emp['salarySource'] as String?) ?? 'manual';

    // Daily rate: prefer saved value, else compute
    final savedDaily = PayrollCalculator.toDbl(emp['dailyRate']);
    final dailyRate = savedDaily > 0
        ? savedDaily
        : (workingDaysPerMonth > 0 ? basic / workingDaysPerMonth : 0.0);

    // ─── Attendance ─────────────────────────────────────────
    final wd = workingDays > 0 ? workingDays : 22;
    final p = present ?? 0; // ✅ non-nullable int
    final absent = (wd - p).clamp(0, wd);
    final absenceDeduction = dailyRate * absent;

    // ─── Government ─────────────────────────────────────────
    final sss = basic * PayrollCalculator.sssRate;
    final ph = basic * PayrollCalculator.philhealthRate;
    final pi = basic * PayrollCalculator.pagibigRate;
    const tax = 0.0;

    final totalDed = absenceDeduction + sss + ph + pi + tax;
    final net = gross - totalDed;

    // ─── 🍱 Work hours from EmployeeHoursSummary ────────────
    final netMinutes = hrs.totalNetMinutes;
    final lunchMinutes = hrs.totalLunchDeductedMinutes;
    final otMinutes = hrs.totalOvertimeMinutes;
    final rawMinutes = netMinutes + lunchMinutes;

    return PayrollBreakdown(
      // Earnings
      basicSalary: basic,
      allowances: allowances,
      overtimePay: overtime,
      grossPay: gross,
      // Benefits
      thirteenthMonth: basic / 12,
      silCredits: dailyRate * 5,
      totalBenefits: (basic / 12) + (dailyRate * 5),
      // Attendance
      workingDays: wd,
      workingDaysPerMonth: workingDaysPerMonth,
      presentDays: p,
      absentDays: absent,
      dailyRate: dailyRate,
      absenceDeduction: absenceDeduction,
      // 🍱 Work Hours
      workRawMinutes: rawMinutes,
      workLunchMinutes: lunchMinutes,
      workNetMinutes: netMinutes,
      workOvertimeMinutes: otMinutes,
      daysWithLogs: p,
      daysWithLunchApplied: lunchMinutes > 0 ? p : 0,
      // Salary metadata
      salarySource: salarySource,
      // Government
      sss: sss,
      philhealth: ph,
      pagibig: pi,
      withholdingTax: tax,
      // Totals
      totalDeductions: totalDed,
      netPay: net,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 📤 CSV EXPORT — LAHAT NG PAYROLL DETAILS PER EMPLOYEE
  // ══════════════════════════════════════════════════════════════
  Future<void> _exportPayrollToCsv() async {
    if (_exporting) return;

    // Respects search + department filters
    final departments = <String>['All Departments'];
    for (var emp in widget.employees) {
      final dept = emp['department']?.toString();
      if (dept != null && dept.isNotEmpty && !departments.contains(dept)) {
        departments.add(dept);
      }
    }

    final filtered = widget.employees.where((emp) {
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
          dept == _selectedDepartment;

      return matchesSearch && matchesDept;
    }).toList();

    if (filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('No employees to export.'),
        backgroundColor: tc.red,
      ));
      return;
    }

    setState(() => _exporting = true);

    try {
      // ─── Column headers ───
      const headers = <String>[
        // Employee
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
        // Pay period
        'pay_period',
        'period_start',
        'period_end',
        // Earnings
        'basic_salary',
        'allowances',
        'overtime_pay',
        'gross_pay',
        // Benefits
        'thirteenth_month',
        'sil_credits',
        'total_benefits',
        // Attendance
        'working_days',
        'working_days_per_month',
        'present_days',
        'absent_days',
        'daily_rate',
        'absence_deduction',
        // Work hours
        'work_raw_hours',
        'work_lunch_hours',
        'work_net_hours',
        'work_overtime_hours',
        'days_with_logs',
        'days_with_lunch_applied',
        // Government
        'sss',
        'philhealth',
        'pagibig',
        'withholding_tax',
        // Totals
        'total_deductions',
        'net_pay',
      ];

      final buffer = StringBuffer();
      buffer.write('\uFEFF'); // UTF-8 BOM para tama sa Excel
      buffer.write(headers.map(_csvEscape).join(','));
      buffer.write('\r\n');

      for (final emp in filtered) {
        final b = _computeForEmp(emp);
        final hrs = _getHoursFor(emp);

        final fullName = (emp['name'] ??
            '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
            .toString()
            .trim();

        final row = <String>[
          // Employee
          (emp['employeeId'] ?? emp['employee_id'] ?? '').toString(),
          (emp['id'] ?? '').toString(),
          fullName,
          (emp['firstName'] ?? '').toString(),
          (emp['lastName'] ?? '').toString(),
          (emp['email'] ?? '').toString(),
          (emp['department'] ?? '').toString(),
          (emp['role'] ?? '').toString(),
          (emp['deviceName'] ?? '').toString(),
          (emp['bankName'] ?? '').toString(),
          (emp['accountNumber'] ?? '').toString(),
          (emp['payrollStatus'] ?? 'Processed').toString(),
          (emp['salarySource'] ?? 'manual').toString(),
          // Pay period
          _selectedPayPeriod,
          DateFormat('yyyy-MM-dd').format(_periodStart),
          DateFormat('yyyy-MM-dd').format(_periodEnd),
          // Earnings
          b.basicSalary.toStringAsFixed(2),
          b.allowances.toStringAsFixed(2),
          b.overtimePay.toStringAsFixed(2),
          b.grossPay.toStringAsFixed(2),
          // Benefits
          b.thirteenthMonth.toStringAsFixed(2),
          b.silCredits.toStringAsFixed(2),
          b.totalBenefits.toStringAsFixed(2),
          // Attendance
          b.workingDays.toString(),
          b.workingDaysPerMonth.toString(),
          b.presentDays.toString(),
          b.absentDays.toString(),
          b.dailyRate.toStringAsFixed(2),
          b.absenceDeduction.toStringAsFixed(2),
          // Work hours (converted to decimal hours)
          _minutesToHours(b.workRawMinutes),
          _minutesToHours(b.workLunchMinutes),
          _minutesToHours(b.workNetMinutes),
          _minutesToHours(b.workOvertimeMinutes),
          b.daysWithLogs.toString(),
          b.daysWithLunchApplied.toString(),
          // Government
          b.sss.toStringAsFixed(2),
          b.philhealth.toStringAsFixed(2),
          b.pagibig.toStringAsFixed(2),
          b.withholdingTax.toStringAsFixed(2),
          // Totals
          b.totalDeductions.toStringAsFixed(2),
          b.netPay.toStringAsFixed(2),
        ];

        buffer.write(row.map(_csvEscape).join(','));
        buffer.write('\r\n');
      }

      // ─── Filename ───
      final tsStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final periodTag = _selectedPayPeriod.replaceAll(' ', '_').toLowerCase();
      final fileName = 'payroll_${periodTag}_$tsStr.csv';

      // ─── Save via shared helper ───
      final savedPath = await downloadTextFile(
        filename: fileName,
        content: buffer.toString(),
      );

      if (!mounted) return;

      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Exported ${filtered.length} employee(s) → $fileName'),
          backgroundColor: tc.green,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Export failed or cancelled.'),
          backgroundColor: tc.red,
        ));
      }
    } catch (e) {
      debugPrint('❌ Payroll CSV export error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: tc.red,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ─── CSV helpers ──────────────────────────────────────────
  String _csvEscape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Convert minutes to decimal hours (e.g. 90 → "1.50")
  String _minutesToHours(int minutes) {
    if (minutes <= 0) return '0.00';
    return (minutes / 60.0).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final departments = <String>['All Departments'];
    for (var emp in widget.employees) {
      final dept = emp['department']?.toString();
      if (dept != null && dept.isNotEmpty && !departments.contains(dept)) {
        departments.add(dept);
      }
    }

    final filtered = widget.employees.where((emp) {
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
          dept == _selectedDepartment;

      return matchesSearch && matchesDept;
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
      totalAbsences += b.absenceDeduction;
      totalNetMinutes += hrs.totalNetMinutes;
      totalOTMinutes += hrs.totalOvertimeMinutes;

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
                'Showing ${filtered.length} of ${widget.employees.length} employees',
                style: TextStyle(fontSize: 12, color: tc.muted),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
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
        onPressed: _loadingAttendance ? null : _loadAll,
        icon: Icon(Icons.refresh, size: 16, color: tc.text),
        label: Text('Refresh',
            style: TextStyle(
                color: tc.text, fontWeight: FontWeight.w600, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          backgroundColor: tc.card,
          side: BorderSide(color: tc.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );

      // ✅ UPDATED — hooked up sa CSV export
      final export = ElevatedButton.icon(
        onPressed: (_exporting || _loadingAttendance)
            ? null
            : _exportPayrollToCsv,
        icon: _exporting
            ? const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.download, size: 16, color: Colors.white),
        label: Text(
          _exporting ? 'Exporting...' : 'Export to CSV',
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          disabledBackgroundColor: tc.orange.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(color: tc.text, fontSize: 14),
            cursorColor: tc.orange,
            decoration: InputDecoration(
              hintText: 'Search by name or employee ID...',
              hintStyle: TextStyle(color: tc.muted, fontSize: 14),
              border: InputBorder.none,
              isDense: true,
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
              icon: Icon(Icons.keyboard_arrow_down, size: 16, color: tc.muted),
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
              icon: Icon(Icons.keyboard_arrow_down, size: 16, color: tc.muted),
              items: departments.map((d) {
                return DropdownMenuItem(
                  value: d,
                  child: Text(d,
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
                  final name = emp['name'] ??
                      '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}';
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
                      b.sss + b.philhealth + b.pagibig + b.withholdingTax;

                  return DataRow(cells: [
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: tc.orange.withValues(alpha: 0.15),
                          child: Text(initials,
                              style: TextStyle(
                                  color: tc.orangeText,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
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
                        Text('-${PayrollCalculator.peso(b.absenceDeduction)}',
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
              decoration: BoxDecoration(color: tx, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status,
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
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'HR';
  }
}