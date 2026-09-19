// lib/screens/admin_add_employee_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import '../services/face_matcher.dart';
import '../widgets/bootstrap_grid.dart';

// ══════════════════════════════════════════════════════════════
// 💰 ROLE-BASED SALARY MATRIX (DEFAULT PRESETS ONLY)
// ══════════════════════════════════════════════════════════════
const int kWorkingDaysPerMonth = 22;

const Map<String, Map<String, double>> kRoleSalaryMatrix = {
  'Employee': {'basicSalary': 18000.0, 'allowances': 2000.0},
  'Driver':   {'basicSalary': 16000.0, 'allowances': 1500.0},
  'Admin':    {'basicSalary': 25000.0, 'allowances': 3000.0},
  'Manager':  {'basicSalary': 45000.0, 'allowances': 5000.0},
};

double _basicSalaryForRole(String role) =>
    kRoleSalaryMatrix[role]?['basicSalary'] ?? 0.0;

double _allowancesForRole(String role) =>
    kRoleSalaryMatrix[role]?['allowances'] ?? 0.0;

double _dailyRateForRole(String role) =>
    _basicSalaryForRole(role) / kWorkingDaysPerMonth;

double _parseMoneyStr(String s) => double.tryParse(
  s.replaceAll(',', '').replaceAll('₱', '').trim(),
) ??
    0.0;

class AdminAddEmployeePage extends StatefulWidget {
  final VoidCallback onRefreshNeeded;
  const AdminAddEmployeePage({super.key, required this.onRefreshNeeded});

  @override
  State<AdminAddEmployeePage> createState() => _AdminAddEmployeePageState();
}

class _AdminAddEmployeePageState extends State<AdminAddEmployeePage> {
  final _fKey = GlobalKey<FormState>();
  bool _saving = false;

  String _selectedRole = 'Employee';
  final List<String> _roleOptions = ['Employee', 'Driver', 'Admin', 'Manager'];

  Uint8List? _profileImageBytes;

  // 🆕 Date range filter state
  DateTimeRange? _selectedDateRange;

  AdminColors get tc => AdminTheme.getColors(context);

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
      ),
    );
  }

  String _getInitials(String firstName, String lastName) {
    String f = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    String l = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return '$f$l'.isEmpty ? 'E' : '$f$l';
  }

  // 🆕 Convert any timestamp-like value to DateTime
  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  // 🆕 Get the "date to filter by" from employee record
  DateTime? _employeeDate(Map<String, dynamic> emp) {
    return _toDateTime(
      emp['joiningDate'] ??
          emp['createdAt'] ??
          emp['created_at'] ??
          emp['timestamp'] ??
          emp['dateCreated'],
    );
  }

  // 🆕 Filter employees by date range
  List<Map<String, dynamic>> _filterByDate(List<Map<String, dynamic>> list) {
    if (_selectedDateRange == null) return list;
    return list.where((emp) {
      final dt = _employeeDate(emp);
      if (dt == null) return true; // keep those without date
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23, 59, 59,
      );
      return dt.isAfter(start.subtract(const Duration(seconds: 1))) &&
          dt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════
  // 🆕 ACTUAL DATE RANGE PICKER — Syncfusion (custom dialog)
  // ══════════════════════════════════════════════════════════════
  Future<void> _pickDateRange() async {
    DateTimeRange? tempRange = _selectedDateRange;

    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: tc.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 640,
            height: 620,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              children: [
                // ─── HEADER ───
                Row(
                  children: [
                    Icon(Icons.date_range_rounded,
                        color: tc.orange, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Select Date Range',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: tc.text,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: tc.muted, size: 20),
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                Divider(color: tc.border, height: 20),

                // ─── DATE PICKER ───
                Expanded(
                  child: SfDateRangePicker(
                    view: DateRangePickerView.month,
                    selectionMode: DateRangePickerSelectionMode.range,
                    initialSelectedRange: _selectedDateRange != null
                        ? PickerDateRange(
                      _selectedDateRange!.start,
                      _selectedDateRange!.end,
                    )
                        : null,
                    minDate: DateTime(2020),
                    maxDate: DateTime.now(),
                    showActionButtons: false,
                    enablePastDates: true,
                    onSelectionChanged:
                        (DateRangePickerSelectionChangedArgs args) {
                      if (args.value is PickerDateRange) {
                        final range = args.value as PickerDateRange;
                        if (range.startDate != null) {
                          tempRange = DateTimeRange(
                            start: range.startDate!,
                            end: range.endDate ?? range.startDate!,
                          );
                        }
                      }
                    },
                    backgroundColor: tc.card,
                    headerStyle: DateRangePickerHeaderStyle(
                      backgroundColor: tc.card,
                      textStyle: TextStyle(
                        color: tc.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    monthCellStyle: DateRangePickerMonthCellStyle(
                      textStyle: TextStyle(
                        color: tc.text,
                        fontSize: 13,
                      ),
                      todayTextStyle: TextStyle(
                        color: tc.orange,
                        fontWeight: FontWeight.w700,
                      ),
                      trailingDatesTextStyle: TextStyle(
                        color: tc.muted.withValues(alpha: 0.5),
                      ),
                      leadingDatesTextStyle: TextStyle(
                        color: tc.muted.withValues(alpha: 0.5),
                      ),
                    ),
                    monthViewSettings: DateRangePickerMonthViewSettings(
                      viewHeaderStyle: DateRangePickerViewHeaderStyle(
                        textStyle: TextStyle(
                          color: tc.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    rangeSelectionColor:
                    tc.orange.withValues(alpha: 0.25),
                    startRangeSelectionColor: tc.orange,
                    endRangeSelectionColor: tc.orange,
                    todayHighlightColor: tc.orange,
                    selectionColor: tc.orange,
                    selectionTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Divider(color: tc.border, height: 20),

                // ─── ACTIONS ───
                Row(
                  children: [
                    if (_selectedDateRange != null)
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _selectedDateRange = null);
                          Navigator.pop(dialogCtx, false);
                        },
                        icon: Icon(Icons.clear_rounded,
                            size: 14, color: tc.muted),
                        label: Text(
                          'CLEAR',
                          style: TextStyle(
                            color: tc.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      child: Text(
                        'CANCEL',
                        style: TextStyle(
                          color: tc.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(dialogCtx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tc.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'APPLY',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (applied == true && tempRange != null) {
      setState(() => _selectedDateRange = tempRange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Container(
            color: tc.background,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: BsContainer(
                      maxWidth: 1600,
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPageHeader(),
                          const SizedBox(height: 24),
                          _buildFilterCard(),
                          const SizedBox(height: 24),
                          _buildEmployeesTable(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    onPressed: () => _snack('Print report initiated...'),
                    backgroundColor: tc.orange,
                    foregroundColor: tc.onOrange,
                    elevation: 4,
                    child: const Icon(Icons.print_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeader() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final narrow = !r.up(BsSize.md);

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Employee',
              style: TextStyle(
                fontSize: r.responsive<double>(xs: 22, sm: 26, md: 28, lg: 32),
                fontWeight: FontWeight.w700,
                color: tc.text,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time verification of professional shifts and geofencing status.',
              style: TextStyle(
                fontSize: r.responsive<double>(xs: 13, md: 16),
                color: tc.textMuted,
              ),
            ),
          ],
        );

        final exportBtn = OutlinedButton.icon(
          onPressed: () => _snack('CSV Exported'),
          icon: Icon(Icons.download_rounded, size: 16, color: tc.text),
          label: Text('Export CSV',
              style: TextStyle(
                  color: tc.text, fontWeight: FontWeight.w700, fontSize: 14)),
          style: OutlinedButton.styleFrom(
            backgroundColor: tc.card,
            side: BorderSide(color: tc.border),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        final manualBtn = ElevatedButton.icon(
          onPressed: _openAddDialog,
          icon: Icon(Icons.add_rounded, size: 16, color: tc.onOrange),
          label: Text('Manual Entry',
              style: TextStyle(
                  color: tc.onOrange,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: exportBtn),
                const SizedBox(width: 12),
                Expanded(child: manualBtn),
              ]),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            Row(children: [
              exportBtn,
              const SizedBox(width: 12),
              manualBtn,
            ]),
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 🆕 FILTER CARD — ACTUAL DATE RANGE PICKER
  // ══════════════════════════════════════════════════════════════
  Widget _buildFilterCard() {
    final hasRange = _selectedDateRange != null;
    final rangeText = hasRange
        ? '${DateFormat('MMM d, yyyy').format(_selectedDateRange!.start)} - '
        '${DateFormat('MMM d, yyyy').format(_selectedDateRange!.end)}'
        : 'Select date range to filter employees';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('DATE RANGE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tc.textMuted,
                      letterSpacing: 0.5)),
              if (hasRange) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'FILTER ACTIVE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: tc.orange,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: tc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasRange ? tc.orange : tc.border,
                  width: hasRange ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      rangeText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: hasRange ? FontWeight.w600 : FontWeight.w500,
                        color: hasRange ? tc.text : tc.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasRange)
                    InkWell(
                      onTap: () {
                        setState(() => _selectedDateRange = null);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.clear_rounded,
                            size: 18, color: tc.muted),
                      ),
                    )
                  else
                    Icon(Icons.calendar_month_rounded,
                        size: 20, color: tc.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEES TABLE
  // ══════════════════════════════════════════════════════════════
  Widget _buildEmployeesTable() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final isMobile = !r.up(BsSize.md);

        return Container(
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
          ),
          child: Column(
            children: [
              if (!isMobile) _buildTableHeader(),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: AdminDatabase.streamEmployees(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                          child: CircularProgressIndicator(color: tc.orange)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Error loading employees: ${snapshot.error}',
                          style: TextStyle(color: tc.red)),
                    );
                  }

                  final allEmployees = snapshot.data ?? [];

                  // 🆕 Apply date range filter
                  final employees = _filterByDate(allEmployees);

                  if (employees.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              _selectedDateRange == null
                                  ? Icons.people_outline_rounded
                                  : Icons.filter_alt_off_rounded,
                              size: 48,
                              color: tc.muted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedDateRange == null
                                  ? 'No registered employees found in database.'
                                  : 'No employees match the selected date range.',
                              style: TextStyle(
                                  color: tc.muted, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            if (_selectedDateRange != null) ...[
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _selectedDateRange = null),
                                icon: Icon(Icons.clear_rounded,
                                    size: 16, color: tc.orange),
                                label: Text(
                                  'Clear filter',
                                  style: TextStyle(
                                    color: tc.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: employees.asMap().entries.map((entry) {
                      final index = entry.key;
                      final emp = entry.value;
                      final isLast = index == employees.length - 1;
                      return isMobile
                          ? _buildEmployeeMobileCard(emp, isLast: isLast)
                          : _buildEmployeeRow(emp, isLast: isLast);
                    }).toList(),
                  );
                },
              ),
              _buildTableFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: tc.borderWarm, width: 1)),
      ),
      child: Row(
        children: [
          _th('EMPLOYEE NAME', flex: 3),
          _th('ROLE / DEPT', flex: 2),
          SizedBox(
            width: 60,
            child: Text('ACTIONS',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tc.textMuted,
                    letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildTableFooter() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);
      final info = Text('System Records Active',
          style: TextStyle(fontSize: 13, color: tc.textMuted));
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pageBtn(Icons.chevron_left_rounded, false),
          const SizedBox(width: 6),
          _pageNumberBtn('1', true),
          const SizedBox(width: 6),
          _pageBtn(Icons.chevron_right_rounded, false),
        ],
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12)),
          border: Border(top: BorderSide(color: tc.borderWarm, width: 1)),
        ),
        child: narrow
            ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [info, const SizedBox(height: 12), controls])
            : Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [info, controls]),
      );
    });
  }

  Widget _th(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tc.textMuted,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildEmployeeRow(Map<String, dynamic> emp, {bool isLast = false}) {
    final firstName = emp['firstName'] ?? emp['first_name'] ?? '';
    final lastName = emp['lastName'] ?? emp['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? (emp['name'] ?? 'Unknown Staff')
        : '$firstName $lastName';

    final empId = emp['employeeId'] ?? emp['id'] ?? 'N/A';
    final displayId = empId.toString().length > 16
        ? '${empId.toString().substring(0, 16)}...'
        : empId.toString();
    final role = emp['role'] ?? 'Staff';
    final dept = emp['department'] ?? 'General';
    final initials = _getInitials(firstName, lastName);
    final hasFace = emp['faceEmbedding'] != null;
    final photoUrl = _s(emp['photoUrl'], '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: tc.border, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _buildAvatar(
                    photoUrl: photoUrl,
                    initials: initials,
                    size: 40,
                    fontSize: 13),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(fullName,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: tc.text),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (hasFace) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified_user_rounded,
                                size: 14, color: tc.green),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('ID: $displayId',
                          style:
                          TextStyle(fontSize: 12, color: tc.textMuted),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: Text('$role ($dept)',
                  style: TextStyle(
                      fontSize: 14,
                      color: tc.text,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
          SizedBox(
              width: 60,
              child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildActionsMenu(fullName))),
        ],
      ),
    );
  }

  Widget _buildEmployeeMobileCard(Map<String, dynamic> emp,
      {bool isLast = false}) {
    final firstName = emp['firstName'] ?? emp['first_name'] ?? '';
    final lastName = emp['lastName'] ?? emp['last_name'] ?? '';
    final fullName = '$firstName $lastName'.trim().isEmpty
        ? (emp['name'] ?? 'Unknown Staff')
        : '$firstName $lastName';
    final empId = emp['employeeId'] ?? emp['id'] ?? 'N/A';
    final displayId = empId.toString().length > 16
        ? '${empId.toString().substring(0, 16)}...'
        : empId.toString();
    final role = emp['role'] ?? 'Staff';
    final dept = emp['department'] ?? 'General';
    final initials = _getInitials(firstName, lastName);
    final hasFace = emp['faceEmbedding'] != null;
    final photoUrl = _s(emp['photoUrl'], '');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(bottom: BorderSide(color: tc.border, width: 0.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(
              photoUrl: photoUrl,
              initials: initials,
              size: 44,
              fontSize: 14),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(fullName,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: tc.text),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (hasFace) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_user_rounded,
                          size: 14, color: tc.green),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text('ID: $displayId',
                    style: TextStyle(fontSize: 12, color: tc.textMuted),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text('$role ($dept)',
                    style: TextStyle(
                        fontSize: 13,
                        color: tc.text,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _buildActionsMenu(fullName),
        ],
      ),
    );
  }

  Widget _buildAvatar({
    required String photoUrl,
    required String initials,
    required double size,
    required double fontSize,
  }) {
    if (photoUrl.isNotEmpty && photoUrl != '—') {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
          Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1.5),
          color: tc.orange.withValues(alpha: 0.15),
        ),
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tc.orange,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Text(initials,
                    style: TextStyle(
                        color: tc.orangeText,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700)),
              );
            },
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border:
        Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1),
      ),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                color: tc.orangeText,
                fontSize: fontSize,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  String _s(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final str = v.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  Widget _buildActionsMenu(String fullName) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: tc.textMuted, size: 20),
      color: tc.card,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: tc.border)),
      tooltip: 'Actions',
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16, color: tc.orange),
            const SizedBox(width: 10),
            Text('Edit', style: TextStyle(color: tc.text, fontSize: 13))
          ]),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded, size: 16, color: tc.red),
            const SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: tc.text, fontSize: 13))
          ]),
        ),
      ],
      onSelected: (value) => _snack('$value: $fullName'),
    );
  }

  Widget _pageBtn(IconData icon, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 32,
    height: 32,
    decoration: BoxDecoration(
        color: active ? tc.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(6)),
    child:
    Icon(icon, size: 18, color: active ? tc.onOrange : tc.textMuted),
  );

  Widget _pageNumberBtn(String text, bool active) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 2),
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color: active ? tc.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(6)),
    child: Text(text,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: active ? tc.onOrange : tc.text)),
  );

  // ══════════════════════════════════════════════════════════════
  // ADD DIALOG — EDITABLE SALARY
  // ══════════════════════════════════════════════════════════════
  void _openAddDialog() {
    _profileImageBytes = null;
    _saving = false;
    _selectedRole = 'Employee';

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final birthdayCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final deptCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final nfcCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final deviceNameCtrl = TextEditingController();

    // ─── SALARY — EDITABLE ─────────────────────────────────────
    final basicSalaryCtrl = TextEditingController();
    final allowancesCtrl = TextEditingController();
    final dailyRateCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final accountNumberCtrl = TextEditingController();

    // ✅ Recompute daily rate = basic / 22
    void _recomputeDaily() {
      final basic = _parseMoneyStr(basicSalaryCtrl.text);
      final daily = basic / kWorkingDaysPerMonth;
      dailyRateCtrl.text = daily.toStringAsFixed(2);
    }

    // ✅ Prefill from role (called on open + role change)
    void _refreshFromRole() {
      basicSalaryCtrl.text =
          _basicSalaryForRole(_selectedRole).toStringAsFixed(2);
      allowancesCtrl.text =
          _allowancesForRole(_selectedRole).toStringAsFixed(2);
      _recomputeDaily();
    }

    _refreshFromRole();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final dialogTc = AdminTheme.getColors(ctx);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.all(BsResponsive.of(ctx).isXs ? 8 : 16),
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: 960,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.95),
              padding: EdgeInsets.all(BsResponsive.of(ctx).isXs ? 16 : 28),
              decoration: BoxDecoration(
                color: dialogTc.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: dialogTc.border),
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _fKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Add New Employee',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: dialogTc.orange)),
                      const SizedBox(height: 4),
                      Text('Employee Registration',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dialogTc.text)),
                      const SizedBox(height: 4),
                      Text(
                          'Onboard a new team member and configure their biometric access credentials.',
                          style: TextStyle(
                              fontSize: 12, color: dialogTc.muted)),
                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stack = !BsResponsive(constraints.maxWidth)
                              .up(BsSize.md);
                          if (stack) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProfileCard(ctx, setS, dialogTc),
                                const SizedBox(height: 20),
                                _buildRightColumn(
                                  ctx,
                                  setS,
                                  dialogTc,
                                  nameCtrl,
                                  emailCtrl,
                                  birthdayCtrl,
                                  phoneCtrl,
                                  deptCtrl,
                                  idCtrl,
                                  nfcCtrl,
                                  pinCtrl,
                                  deviceNameCtrl,
                                  basicSalaryCtrl,
                                  allowancesCtrl,
                                  dailyRateCtrl,
                                  bankNameCtrl,
                                  accountNumberCtrl,
                                  _refreshFromRole,
                                  _recomputeDaily,
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                  width: 280,
                                  child:
                                  _buildProfileCard(ctx, setS, dialogTc)),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _buildRightColumn(
                                  ctx,
                                  setS,
                                  dialogTc,
                                  nameCtrl,
                                  emailCtrl,
                                  birthdayCtrl,
                                  phoneCtrl,
                                  deptCtrl,
                                  idCtrl,
                                  nfcCtrl,
                                  pinCtrl,
                                  deviceNameCtrl,
                                  basicSalaryCtrl,
                                  allowancesCtrl,
                                  dailyRateCtrl,
                                  bankNameCtrl,
                                  accountNumberCtrl,
                                  _refreshFromRole,
                                  _recomputeDaily,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stack = BsResponsive(constraints.maxWidth).isXs;

                          final cancelBtn = OutlinedButton(
                            onPressed:
                            _saving ? null : () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: dialogTc.text,
                              side: BorderSide(color: dialogTc.border),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Cancel',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          );

                          final submitBtn = ElevatedButton(
                            onPressed: _saving
                                ? null
                                : () async {
                              if (_fKey.currentState == null ||
                                  !_fKey.currentState!.validate()) {
                                return;
                              }

                              final typedEmployeeId = idCtrl.text.trim();
                              if (typedEmployeeId.isEmpty) {
                                _snack(
                                    'Please enter an Employee ID (e.g., emp-01-2026)',
                                    error: true);
                                return;
                              }

                              if (typedEmployeeId.contains('/') ||
                                  typedEmployeeId.contains('~') ||
                                  typedEmployeeId.contains('*') ||
                                  typedEmployeeId.contains('[') ||
                                  typedEmployeeId.contains(']') ||
                                  typedEmployeeId.contains('.')) {
                                _snack(
                                    'Employee ID cannot contain / ~ * [ ] or .',
                                    error: true);
                                return;
                              }

                              final basicSalary =
                              _parseMoneyStr(basicSalaryCtrl.text);
                              if (basicSalary <= 0) {
                                _snack(
                                    '⚠️ Basic Salary must be > 0.',
                                    error: true);
                                return;
                              }
                              final allowances =
                              _parseMoneyStr(allowancesCtrl.text);
                              final dailyRate = basicSalary /
                                  kWorkingDaysPerMonth;
                              final monthlyTotal =
                                  basicSalary + allowances;

                              if (!ctx.mounted) return;
                              setS(() => _saving = true);

                              try {
                                final fullName = nameCtrl.text.trim();
                                final parts = fullName.split(' ');
                                final firstName = parts.isNotEmpty
                                    ? parts.first
                                    : fullName;
                                final lastName = parts.length > 1
                                    ? parts.sublist(1).join(' ')
                                    : 'Doe';

                                final err =
                                await AdminDatabase.addEmployee(
                                  employeeId: typedEmployeeId,
                                  firstName: firstName,
                                  lastName: lastName,
                                  email: emailCtrl.text.trim(),
                                  password: 'password123',
                                  role: _selectedRole,
                                  department: deptCtrl.text.trim(),
                                  nfcTagId: nfcCtrl.text.trim(),
                                  pin: pinCtrl.text.trim(),
                                );

                                if (!ctx.mounted) return;

                                if (err != null) {
                                  _snack(err, error: true);
                                  setS(() => _saving = false);
                                  return;
                                }

                                final capturedEmail =
                                emailCtrl.text.trim();

                                try {
                                  final docRef = FirebaseFirestore
                                      .instance
                                      .collection('employees')
                                      .doc(typedEmployeeId);

                                  final extraData = <String, dynamic>{
                                    'employeeId': typedEmployeeId,
                                    'role': _selectedRole,
                                    if (deviceNameCtrl.text.trim().isNotEmpty)
                                      'deviceName':
                                      deviceNameCtrl.text.trim(),
                                    'basicSalary': basicSalary,
                                    'allowances': allowances,
                                    'basicAllowance': allowances,
                                    'housingAllowance': 0.0,
                                    'transportAllowance': 0.0,
                                    'specialAllowance': 0.0,
                                    'dailyRate': dailyRate,
                                    'monthlyTotal': monthlyTotal,
                                    'workingDaysPerMonth':
                                    kWorkingDaysPerMonth,
                                    'salarySource': 'manual',
                                    'bankName':
                                    bankNameCtrl.text.trim(),
                                    'accountNumber':
                                    accountNumberCtrl.text.trim(),
                                    'payrollStatus': 'Processed',
                                    'salaryConfigured': true,
                                    'salaryUpdatedAt':
                                    FieldValue.serverTimestamp(),
                                  };

                                  final phone = phoneCtrl.text.trim();
                                  final bday = birthdayCtrl.text.trim();
                                  if (phone.isNotEmpty) {
                                    extraData['phone'] = phone;
                                  }
                                  if (bday.isNotEmpty) {
                                    extraData['birthday'] = bday;
                                  }

                                  await docRef.update(extraData);
                                  debugPrint(
                                      '✅ Extra data saved to $typedEmployeeId: $extraData');
                                } catch (e) {
                                  debugPrint(
                                      '⚠️ Extra data save failed: $e');
                                }

                                final capturedBytes =
                                    _profileImageBytes;
                                Navigator.pop(ctx);
                                if (mounted) {
                                  _snack(capturedBytes != null
                                      ? 'Employee "$typedEmployeeId" saved! Processing photo in background...'
                                      : 'Employee "$typedEmployeeId" saved successfully.');
                                  widget.onRefreshNeeded();
                                }

                                if (capturedBytes != null) {
                                  _processFaceInBackground(
                                      capturedEmail, capturedBytes);
                                }
                              } catch (e) {
                                if (!ctx.mounted) return;
                                _snack('Failed to add employee: $e',
                                    error: true);
                                setS(() => _saving = false);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dialogTc.orange,
                              foregroundColor: dialogTc.onOrange,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            child: _saving
                                ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: dialogTc.onOrange,
                                    strokeWidth: 2))
                                : const Text('Complete Onboarding',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          );

                          if (stack) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                submitBtn,
                                const SizedBox(height: 12),
                                cancelBtn
                              ],
                            );
                          }
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              cancelBtn,
                              const SizedBox(width: 12),
                              submitBtn
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      birthdayCtrl.dispose();
      phoneCtrl.dispose();
      deptCtrl.dispose();
      idCtrl.dispose();
      nfcCtrl.dispose();
      pinCtrl.dispose();
      deviceNameCtrl.dispose();
      basicSalaryCtrl.dispose();
      allowancesCtrl.dispose();
      dailyRateCtrl.dispose();
      bankNameCtrl.dispose();
      accountNumberCtrl.dispose();
    });
  }

  Future<void> _processFaceInBackground(
      String email, Uint8List imageBytes) async {
    try {
      debugPrint('🔒 Starting background face setup for $email');

      final query = await FirebaseFirestore.instance
          .collection('employees')
          .where('email', isEqualTo: email)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (query.docs.isEmpty) {
        debugPrint('⚠️ Employee not found by email — face setup skipped');
        return;
      }

      final empDoc = query.docs.first;
      final empId = empDoc.id;

      try {
        debugPrint('📤 Uploading photo...');
        final photoUrl = await FaceMatcher.uploadEmployeePhoto(
          empId,
          imageBytes,
        ).timeout(const Duration(seconds: 60));

        if (photoUrl != null) {
          await empDoc.reference
              .update({'photoUrl': photoUrl})
              .timeout(const Duration(seconds: 10));
          debugPrint('✅ Photo uploaded and saved to Firestore: $photoUrl');
        }
      } catch (e) {
        debugPrint('⚠️ Photo upload failed: $e');
      }

      try {
        debugPrint('🧠 Generating face embedding...');
        final embedding = await FaceMatcher.generateEmbedding(imageBytes)
            .timeout(const Duration(seconds: 20));

        if (embedding.isNotEmpty) {
          await FaceMatcher.saveEmbedding(empId, embedding)
              .timeout(const Duration(seconds: 15));
          debugPrint('✅ Face embedding saved for $empId');
        }
      } catch (e) {
        debugPrint('⚠️ Embedding failed: $e');
      }

      debugPrint('✅ Background face setup complete');
    } catch (e) {
      debugPrint('❌ Background face setup error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PROFILE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard(
      BuildContext ctx, StateSetter setS, AdminColors dialogTc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dialogTc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dialogTc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () async {
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.image, allowMultiple: false);
              if (result != null && result.files.single.bytes != null) {
                if (ctx.mounted) {
                  setS(() {
                    _profileImageBytes = result.files.single.bytes;
                  });
                  _snack('Profile picture loaded.');
                }
              }
            },
            child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: dialogTc.surface,
                image: _profileImageBytes != null
                    ? DecorationImage(
                    image: MemoryImage(_profileImageBytes!),
                    fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                children: [
                  if (_profileImageBytes == null)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_outline_rounded,
                              size: 56, color: dialogTc.muted),
                          const SizedBox(height: 8),
                          Text('Upload Photo',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: dialogTc.muted)),
                          const SizedBox(height: 4),
                          Text('(used for face recognition)',
                              style: TextStyle(
                                  fontSize: 10, color: dialogTc.muted)),
                        ],
                      ),
                    ),
                  const Positioned(
                    bottom: 8,
                    right: 8,
                    child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 16,
                        child: Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 16)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Profile Identity',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: dialogTc.text)),
          const SizedBox(height: 4),
          Text('Click image to upload/change employee photo.',
              style: TextStyle(
                  fontSize: 11, color: dialogTc.muted, height: 1.3)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dialogTc.pillWarnBg,
              borderRadius: BorderRadius.circular(8),
              border:
              Border.all(color: dialogTc.pillWarnTx.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: dialogTc.pillWarnTx),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Ensure the employee's name matches their government-issued ID.",
                    style: TextStyle(
                        fontSize: 10,
                        color: dialogTc.pillWarnTx,
                        fontWeight: FontWeight.w500,
                        height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // RIGHT COLUMN — EDITABLE SALARY
  // ══════════════════════════════════════════════════════════════
  Widget _buildRightColumn(
      BuildContext ctx,
      StateSetter setS,
      AdminColors dialogTc,
      TextEditingController nameCtrl,
      TextEditingController emailCtrl,
      TextEditingController birthdayCtrl,
      TextEditingController phoneCtrl,
      TextEditingController deptCtrl,
      TextEditingController idCtrl,
      TextEditingController nfcCtrl,
      TextEditingController pinCtrl,
      TextEditingController deviceNameCtrl,
      TextEditingController basicSalaryCtrl,
      TextEditingController allowancesCtrl,
      TextEditingController dailyRateCtrl,
      TextEditingController bankNameCtrl,
      TextEditingController accountNumberCtrl,
      VoidCallback refreshFromRole,
      VoidCallback recomputeDaily,
      ) {
    return Column(
      children: [
        // ─── PERSONAL INFO ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dialogTc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dialogTc.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.badge_outlined, size: 16, color: dialogTc.orange),
                const SizedBox(width: 8),
                Text('Personal Information',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: dialogTc.text))
              ]),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 500;
                  if (narrow) {
                    return Column(
                      children: [
                        _buildInput(
                            'FULL NAME', nameCtrl, 'Full Name', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput('EMAIL ADDRESS', emailCtrl,
                            'Email Address', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'BIRTHDAY', birthdayCtrl, 'Birthday', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'PHONE NO.', phoneCtrl, 'Phone No.', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput(
                            'DEPARTMENT', deptCtrl, 'Department', dialogTc),
                        const SizedBox(height: 12),
                        _buildInput('EMPLOYEE ID', idCtrl,
                            'e.g., emp-01-2026', dialogTc),
                        const SizedBox(height: 12),
                        _buildRoleDropdown(
                          dialogTc,
                          setS,
                          onRoleChanged: () {
                            refreshFromRole();
                            recomputeDaily();
                          },
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: _buildInput(
                                'FULL NAME', nameCtrl, 'Full Name', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInput('EMAIL ADDRESS', emailCtrl,
                                'Email Address', dialogTc))
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildInput(
                                'BIRTHDAY', birthdayCtrl, 'Birthday', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInput(
                                'PHONE NO.', phoneCtrl, 'Phone No.', dialogTc))
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildInput('DEPARTMENT', deptCtrl,
                                'Department', dialogTc)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildRoleDropdown(
                            dialogTc,
                            setS,
                            onRoleChanged: () {
                              refreshFromRole();
                              recomputeDaily();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: _buildInput('EMPLOYEE ID', idCtrl,
                                'e.g., emp-01-2026', dialogTc)),
                        const SizedBox(width: 12),
                        const Expanded(child: SizedBox()),
                      ]),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ─── 💰 COMPENSATION & PAYROLL ─────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dialogTc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dialogTc.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.payments_outlined,
                    size: 16, color: dialogTc.orange),
                const SizedBox(width: 8),
                Text('Compensation & Payroll',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: dialogTc.text)),
              ]),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: dialogTc.pillWarnBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: dialogTc.pillWarnTx.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.edit_note,
                        size: 14, color: dialogTc.pillWarnTx),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pwede mong i-edit ang Basic Salary at Allowances. Ang DAILY RATE ay auto-computed (Basic ÷ 22 days).',
                        style: TextStyle(
                            fontSize: 10,
                            color: dialogTc.pillWarnTx,
                            fontWeight: FontWeight.w600,
                            height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, c) {
                final narrow = c.maxWidth < 500;
                if (narrow) {
                  return Column(children: [
                    _buildMoneyInput(
                      'BASIC SALARY (₱/month)',
                      basicSalaryCtrl,
                      dialogTc,
                      required: true,
                      onChanged: (_) => setS(() => recomputeDaily()),
                    ),
                    const SizedBox(height: 12),
                    _buildMoneyInput(
                      'ALLOWANCES (₱/month)',
                      allowancesCtrl,
                      dialogTc,
                      onChanged: (_) => setS(() {}),
                    ),
                    const SizedBox(height: 12),
                    _buildReadOnlyMoney(
                        'DAILY RATE (₱/day)', dailyRateCtrl, dialogTc,
                        highlight: true),
                    const SizedBox(height: 12),
                    _buildInput('BANK NAME', bankNameCtrl, 'e.g. BPI', dialogTc),
                    const SizedBox(height: 12),
                    _buildInput('ACCOUNT NUMBER', accountNumberCtrl,
                        'e.g. 1234567890', dialogTc,
                        keyboardType: TextInputType.number),
                  ]);
                }
                return Column(children: [
                  Row(children: [
                    Expanded(
                      child: _buildMoneyInput(
                        'BASIC SALARY (₱/month)',
                        basicSalaryCtrl,
                        dialogTc,
                        required: true,
                        onChanged: (_) => setS(() => recomputeDaily()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMoneyInput(
                        'ALLOWANCES (₱/month)',
                        allowancesCtrl,
                        dialogTc,
                        onChanged: (_) => setS(() {}),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _buildReadOnlyMoney(
                          'DAILY RATE (₱/day)', dailyRateCtrl, dialogTc,
                          highlight: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: dialogTc.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: dialogTc.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('WORKING DAYS',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: dialogTc.muted,
                                    letterSpacing: 0.5)),
                            Text('$kWorkingDaysPerMonth days',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: dialogTc.text)),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _buildInput(
                          'BANK NAME', bankNameCtrl, 'e.g. BPI', dialogTc),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInput('ACCOUNT NUMBER', accountNumberCtrl,
                          'e.g. 1234567890', dialogTc,
                          keyboardType: TextInputType.number),
                    ),
                  ]),
                ]);
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ─── BIOMETRIC ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: dialogTc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dialogTc.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.fingerprint, size: 16, color: dialogTc.orange),
                const SizedBox(width: 8),
                Text('Biometric Credentials',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: dialogTc.text))
              ]),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 500;
                  if (narrow) {
                    return Column(
                      children: [
                        _buildInput('KEYFOB SERIAL', nfcCtrl, 'Keyfob Serial',
                            dialogTc,
                            suffixIcon: Icons.wifi),
                        const SizedBox(height: 12),
                        _buildInput('4-DIGIT PIN', pinCtrl, '4-Digit PIN',
                            dialogTc,
                            obscure: true),
                        const SizedBox(height: 12),
                        _buildInput(
                            'REGISTERED DEVICE', deviceNameCtrl,
                            'e.g. Samsung A54, Redmi Note 12',
                            dialogTc,
                            suffixIcon: Icons.smartphone),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: _buildInput('KEYFOB SERIAL', nfcCtrl,
                                  'Keyfob Serial', dialogTc,
                                  suffixIcon: Icons.wifi)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _buildInput('4-DIGIT PIN', pinCtrl,
                                  '4-Digit PIN', dialogTc,
                                  obscure: true)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInput(
                          'REGISTERED DEVICE', deviceNameCtrl,
                          'e.g. Samsung A54, Redmi Note 12, iPhone 13',
                          dialogTc,
                          suffixIcon: Icons.smartphone),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildBadge('NFC Ready', dialogTc),
                  _buildBadge('Pin-pad Enabled', dialogTc),
                  if (deviceNameCtrl.text.trim().isNotEmpty)
                    _buildBadge('Device Bound', dialogTc),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown(
      AdminColors dialogTc,
      StateSetter setS, {
        VoidCallback? onRoleChanged,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ROLE',
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: dialogTc.muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: dialogTc.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: dialogTc.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRole,
              isExpanded: true,
              dropdownColor: dialogTc.card,
              style: TextStyle(
                  fontSize: 12,
                  color: dialogTc.text,
                  fontWeight: FontWeight.w500),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: dialogTc.muted),
              items: _roleOptions.map((role) {
                return DropdownMenuItem<String>(
                  value: role,
                  child: Text(role),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setS(() => _selectedRole = val);
                  if (onRoleChanged != null) onRoleChanged();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  // ─── Editable money input ─────────────────────────────────
  Widget _buildMoneyInput(
      String label,
      TextEditingController controller,
      AdminColors dialogTc, {
        ValueChanged<String>? onChanged,
        bool required = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: dialogTc.muted,
                  letterSpacing: 0.5)),
          if (required) ...[
            const SizedBox(width: 4),
            Text('*',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: dialogTc.orange)),
          ],
        ]),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: onChanged,
          style: TextStyle(
              fontSize: 12, color: dialogTc.text, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: TextStyle(color: dialogTc.muted),
            prefixText: '₱ ',
            prefixStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: dialogTc.orange),
            filled: true,
            fillColor: dialogTc.surface,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.orange, width: 1.5)),
          ),
        ),
      ],
    );
  }

  // ─── Read-only money display ──────────────────────────────
  Widget _buildReadOnlyMoney(
      String label,
      TextEditingController controller,
      AdminColors dialogTc, {
        bool highlight = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: dialogTc.muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: highlight
                ? dialogTc.orange.withValues(alpha: 0.08)
                : dialogTc.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: highlight
                    ? dialogTc.orange.withValues(alpha: 0.5)
                    : dialogTc.border),
          ),
          child: Row(
            children: [
              Text('₱ ',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: highlight ? dialogTc.orange : dialogTc.muted)),
              Expanded(
                child: Text(
                  controller.text.isEmpty ? '0.00' : controller.text,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: highlight ? dialogTc.orange : dialogTc.text),
                ),
              ),
              Icon(Icons.calculate_outlined,
                  size: 12,
                  color: highlight ? dialogTc.orange : dialogTc.muted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInput(
      String label,
      TextEditingController controller,
      String hint,
      AdminColors dialogTc, {
        bool obscure = false,
        IconData? suffixIcon,
        TextInputType? keyboardType,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: dialogTc.muted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: TextStyle(
              fontSize: 12, color: dialogTc.text, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: dialogTc.muted),
            filled: true,
            fillColor: dialogTc.surface,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: suffixIcon != null
                ? Icon(suffixIcon, size: 14, color: dialogTc.muted)
                : null,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: dialogTc.orange, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text, AdminColors dialogTc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: dialogTc.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dialogTc.border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 11, color: dialogTc.orange),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: dialogTc.text)),
        ],
      ),
    );
  }
}