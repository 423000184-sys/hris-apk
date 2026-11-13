// lib/screens/admin_payroll_page.dart
// v2.1: 🆕 "Payroll Rates" button (onOpenSettings) opens the HR payroll settings.
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
import '../services/demo_mode_service.dart';

class AdminPayrollPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final Map<String, List<Map<String, dynamic>>> userLogs;
  final Function(Map<String, dynamic>) onSelectEmployee;

  /// 🆕 Opens the Payroll Rates (settings) screen. Null hides the button.
  final VoidCallback? onOpenSettings;

  const AdminPayrollPage({
    super.key,
    required this.employees,
    required this.userLogs,
    required this.onSelectEmployee,
    this.onOpenSettings,
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

  Map<String, PayrollBreakdown> _breakdownsMap = {};
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
      _breakdownsMap = {};
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
      final settings = await PayrollCalculator.fetchSettings();
      final Map<String, PayrollBreakdown> newBreakdowns = {};

      final presentDaysMap = await PayrollCalculator.fetchPresentDaysMap(
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );

      for (final emp in widget.employees) {
        final key = emp['id']?.toString() ?? emp['employeeId']?.toString() ?? '';
        if (key.isEmpty) continue;

        int? present;
        for (final k in ['id', 'employeeId', 'employee_id', 'nfcTagId', 'authUid']) {
          final pKey = emp[k]?.toString().trim();
          if (pKey != null && pKey.isNotEmpty && presentDaysMap.containsKey(pKey)) {
            present = presentDaysMap[pKey];
            break;
          }
        }

        final breakdown = await PayrollCalculator.compute(
          employee: emp,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
          presentDaysOverride: present,
          fetchAttendance: false, // Already fetched in bulk above
          fetchWorkHoursData: true, // Fetch logs to compute OT & ND
          settings: settings,
        );
        newBreakdowns[key] = breakdown;
      }

      if (!mounted) return;
      setState(() {
        _breakdownsMap = newBreakdowns;
        _loadingAttendance = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ payroll loadAll: $e');
      if (!mounted) return;
      setState(() => _loadingAttendance = false);
      _toast(_safeError(e), error: true);
    }
  }

  PayrollBreakdown _getBreakdownFor(Map<String, dynamic> emp) {
    if (_isDemo) return PayrollBreakdown.empty;
    final key = emp['id']?.toString() ?? emp['employeeId']?.toString() ?? '';
    return _breakdownsMap[key] ?? PayrollBreakdown.empty;
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
    int totalOTMinutes = 0;
    int pendingCount = 0;

    for (final emp in filtered) {
      final b = _getBreakdownFor(emp);
      totalNet += b.netPay;
      totalDeductions += b.totalDeductions;
      totalAbsences += b.absentAmount;
      totalNetMinutes += b.workNetMinutes;
      totalOTMinutes += b.workOvertimeMinutes;
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
              _buildStatsRow(totalNet, pendingCount, totalDeductions, totalAbsences, totalNetMinutes, totalOTMinutes),
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
        // 🆕 Payroll Rates (HR-editable settings)
        if (widget.onOpenSettings != null) ...[
          OutlinedButton.icon(
            onPressed: widget.onOpenSettings,
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Payroll Rates'),
          ),
          const SizedBox(width: 10),
        ],
        OutlinedButton.icon(onPressed: (_loadingAttendance || _isDemo) ? null : _loadAll, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: (_exporting || _loadingAttendance || _isDemo) ? null : _exportPayrollToCsv,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Export to CSV'),
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

  Widget _buildStatsRow(double totalNet, int pending, double totalDed, double totalAbs, int totalNetMinutes, int totalOTMinutes) {
    final totalHoursStr = '${(totalNetMinutes / 60).toStringAsFixed(0)}h';
    final totalOTStr = '${(totalOTMinutes / 60).toStringAsFixed(0)}h';

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

  Widget _buildTable(List<Map<String, dynamic>> employees) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: tc.border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(tc.surface),
                  columns: [
                    _col('EMPLOYEE'),
                    _col('BASIC'),
                    _col('HOURS'),
                    _col('ABSENCES'),
                    _col('GOVT'),
                    _col('NET PAY'),
                    _col('STATUS'),
                    _col('ACTION')
                  ],
                  rows: employees.map((emp) {
                    final b = _getBreakdownFor(emp);
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
                      DataCell(Text(PayrollCalculator.peso(b.earnedBasic), style: TextStyle(color: tc.text))),
                      DataCell(Text('${(b.workNetMinutes / 60).toStringAsFixed(0)}h', style: TextStyle(color: tc.text))),
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