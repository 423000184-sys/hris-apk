// lib/screens/admin_attendance_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'admin_theme.dart';
import 'admin_database.dart';
import 'admin_dashboard.dart';
import '../widgets/bootstrap_grid.dart';

class AdminAttendancePage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> logs;
  final Color accent;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
  final List<Map<String, dynamic>> locations;

  // Employees list — fallback kung empty, mag-stream ng sarili
  final List<Map<String, dynamic>> employees;

  const AdminAttendancePage({
    super.key,
    required this.title,
    required this.logs,
    required this.accent,
    required this.searchQuery,
    required this.onRefreshNeeded,
    required this.locations,
    this.employees = const [],
  });

  @override
  State<AdminAttendancePage> createState() => _AdminAttendancePageState();
}

class _AdminAttendancePageState extends State<AdminAttendancePage> {
  AdminColors get tc => AdminTheme.getColors(context);

  // Filter states
  String _selectedEventType = 'All Events';
  String _selectedDepartment = 'All Departments';
  String _selectedYear = 'All Years';
  DateTimeRange? _selectedDateRange;
  int _currentPage = 1;
  final int _rowsPerPage = 5;

  final List<String> _eventTypes = ['All Events', 'IN', 'OUT'];

  // Employee lookup — self-sufficient, may sariling stream
  Map<String, Map<String, dynamic>> _employeeLookup = {};
  List<Map<String, dynamic>> _localEmployees = [];
  StreamSubscription? _empSub;

  @override
  void initState() {
    super.initState();
    _localEmployees = widget.employees;
    _buildEmployeeLookup();
    _listenToEmployees();
  }

  @override
  void didUpdateWidget(covariant AdminAttendancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employees != widget.employees ||
        oldWidget.employees.length != widget.employees.length) {
      if (widget.employees.isNotEmpty) {
        _localEmployees = widget.employees;
        _buildEmployeeLookup();
      }
    }
  }

  @override
  void dispose() {
    _empSub?.cancel();
    super.dispose();
  }

  // ⭐ DIRECT STREAM — ito ang sagot sa 0 employees problem
  void _listenToEmployees() {
    _empSub = AdminDatabase.streamEmployees().listen(
          (emps) {
        if (!mounted) return;
        debugPrint('📡 [Attendance] Stream fired: ${emps.length} employees');
        setState(() {
          _localEmployees = emps.isNotEmpty ? emps : widget.employees;
          _buildEmployeeLookup();
        });
      },
      onError: (e) {
        debugPrint('❌ [Attendance] Employee stream error: $e');
      },
    );
  }

  void _buildEmployeeLookup() {
    final source =
    _localEmployees.isNotEmpty ? _localEmployees : widget.employees;

    final map = <String, Map<String, dynamic>>{};

    for (final emp in source) {
      final id = (emp['id'] ?? '').toString().trim();
      final empId =
      (emp['employeeId'] ?? emp['employee_id'] ?? '').toString().trim();
      final email = (emp['email'] ?? '').toString().trim().toLowerCase();
      final name = (emp['name'] ??
          emp['fullName'] ??
          '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}')
          .toString()
          .trim()
          .toLowerCase();

      if (id.isNotEmpty) map[id] = emp;
      if (empId.isNotEmpty) map[empId] = emp;
      if (email.isNotEmpty) map['email:$email'] = emp;
      if (name.isNotEmpty) map['name:$name'] = emp;
    }

    _employeeLookup = map;
    debugPrint(
        '📋 [Attendance] Lookup built: ${map.length} keys from ${source.length} employees');
  }

  Map<String, dynamic>? _findEmployee(Map<String, dynamic> log) {
    final id = (log['employee_id'] ??
        log['employeeId'] ??
        log['employeeID'] ??
        '')
        .toString()
        .trim();
    if (id.isNotEmpty && _employeeLookup.containsKey(id)) {
      return _employeeLookup[id];
    }

    final email = (log['email'] ?? '').toString().trim().toLowerCase();
    if (email.isNotEmpty && _employeeLookup.containsKey('email:$email')) {
      return _employeeLookup['email:$email'];
    }

    final name = (log['employee_name'] ??
        log['employeeName'] ??
        log['name'] ??
        '')
        .toString()
        .trim()
        .toLowerCase();
    if (name.isNotEmpty && _employeeLookup.containsKey('name:$name')) {
      return _employeeLookup['name:$name'];
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // RESOLVERS
  // ═══════════════════════════════════════════════════════════════
  String _resolveDepartment(Map<String, dynamic> log) {
    final fromLog =
    (log['department'] ?? log['dept'] ?? log['section'] ?? '')
        .toString()
        .trim();
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) {
      final dept =
      (emp['department'] ?? emp['dept'] ?? '').toString().trim();
      if (dept.isNotEmpty) return dept;

      final role = (emp['role'] ?? emp['position'] ?? '').toString().trim();
      if (role.isNotEmpty) return role;
    }
    return 'No Department';
  }

  String _resolveName(Map<String, dynamic> log) {
    final fromLog = (log['employee_name'] ??
        log['employeeName'] ??
        log['name'] ??
        '')
        .toString()
        .trim();
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) {
      final full =
      (emp['name'] ?? emp['fullName'] ?? '').toString().trim();
      if (full.isNotEmpty) return full;

      final first =
      (emp['firstName'] ?? emp['first_name'] ?? '').toString().trim();
      final last =
      (emp['lastName'] ?? emp['last_name'] ?? '').toString().trim();
      final combo = '$first $last'.trim();
      if (combo.isNotEmpty) return combo;
    }
    return 'Unknown Employee';
  }

  String _resolveEmail(Map<String, dynamic> log) {
    final fromLog = (log['email'] ?? '').toString().trim();
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) return (emp['email'] ?? '').toString().trim();
    return '';
  }

  String? _resolvePhotoUrl(Map<String, dynamic> log) {
    const photoKeys = ['photoUrl', 'photo', 'imageUrl', 'image', 'avatar'];

    for (final key in photoKeys) {
      final v = (log[key] ?? '').toString().trim();
      if (v.isNotEmpty && v != '—' && v != 'null') return v;
    }

    final emp = _findEmployee(log);
    if (emp != null) {
      for (final key in photoKeys) {
        final v = (emp[key] ?? '').toString().trim();
        if (v.isNotEmpty && v != '—' && v != 'null') return v;
      }
    }
    return null;
  }

  String? _resolveRegisteredDevice(Map<String, dynamic> log) {
    final fromLog = (log['registeredDevice'] ??
        log['deviceName'] ??
        log['device'] ??
        '')
        .toString()
        .trim();
    if (fromLog.isNotEmpty && fromLog != '—' && fromLog != 'null') {
      return fromLog;
    }

    final emp = _findEmployee(log);
    if (emp != null) {
      final dev = (emp['deviceName'] ??
          emp['registeredDevice'] ??
          emp['device'] ??
          '')
          .toString()
          .trim();
      if (dev.isNotEmpty && dev != '—' && dev != 'null') return dev;
    }
    return null;
  }

  List<String> get _departments {
    final depts = <String>{};
    for (final log in widget.logs) {
      final dept = _resolveDepartment(log);
      if (dept.isNotEmpty && dept != 'No Department') depts.add(dept);
    }
    return ['All Departments', ...depts.toList()..sort()];
  }

  // 🆕 Available years — descending order (newest first)
  List<String> get _years {
    final years = <int>{};
    for (final log in widget.logs) {
      final ts = log['timestamp'];
      DateTime? dt;
      if (ts is Timestamp) {
        dt = ts.toDate();
      } else if (ts is DateTime) {
        dt = ts;
      }
      if (dt != null) years.add(dt.year);
    }
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return ['All Years', ...sorted.map((y) => y.toString())];
  }

  List<Map<String, dynamic>> get _filteredLogs {
    var filtered = widget.logs.where((log) {
      final name = _resolveName(log).toLowerCase();
      final id =
      (log['employee_id'] ?? log['employeeId'] ?? '').toString().toLowerCase();
      final email = _resolveEmail(log).toLowerCase();
      final query = widget.searchQuery.toLowerCase();
      return name.contains(query) ||
          id.contains(query) ||
          email.contains(query);
    }).toList();

    if (_selectedEventType != 'All Events') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? 'IN').toString().toUpperCase();
        return type == _selectedEventType;
      }).toList();
    }

    if (_selectedDepartment != 'All Departments') {
      filtered = filtered
          .where((log) => _resolveDepartment(log) == _selectedDepartment)
          .toList();
    }

    // 🆕 YEAR filter
    if (_selectedYear != 'All Years') {
      final year = int.tryParse(_selectedYear);
      if (year != null) {
        filtered = filtered.where((log) {
          final ts = log['timestamp'];
          if (ts == null) return false;
          DateTime? dt;
          if (ts is Timestamp) {
            dt = ts.toDate();
          } else if (ts is DateTime) {
            dt = ts;
          }
          if (dt == null) return false;
          return dt.year == year;
        }).toList();
      }
    }

    if (_selectedDateRange != null) {
      filtered = filtered.where((log) {
        final ts = log['timestamp'];
        if (ts == null) return false;
        DateTime dt;
        if (ts is Timestamp) {
          dt = ts.toDate();
        } else if (ts is DateTime) {
          dt = ts;
        } else {
          return false;
        }
        return dt.isAfter(
            _selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            dt.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    filtered.sort((a, b) {
      final tsA = a['timestamp'];
      final tsB = b['timestamp'];
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;

      DateTime? dtA;
      DateTime? dtB;
      if (tsA is Timestamp) {
        dtA = tsA.toDate();
      } else if (tsA is DateTime) {
        dtA = tsA;
      }
      if (tsB is Timestamp) {
        dtB = tsB.toDate();
      } else if (tsB is DateTime) {
        dtB = tsB;
      }
      if (dtA == null || dtB == null) return 0;
      return dtB.compareTo(dtA);
    });

    return filtered;
  }

  List<Map<String, dynamic>> get _paginatedLogs {
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = start + _rowsPerPage;
    if (start >= _filteredLogs.length) return [];
    return _filteredLogs.sublist(start, end.clamp(0, _filteredLogs.length));
  }

  int get _totalPages => (_filteredLogs.length / _rowsPerPage).ceil();

  String _fmtTime(dynamic ts) {
    if (ts == null) return '--:--';
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    }
    if (dt == null) return '--:--';
    return DateFormat('hh:mm a').format(dt);
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    }
    if (dt == null) return '—';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  // ══════════════════════════════════════════════════════════════
  // 🆕 DATE RANGE PICKER — Syncfusion (custom dialog, NOT fullscreen)
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
                          setState(() {
                            _selectedDateRange = null;
                            _currentPage = 1;
                          });
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
      setState(() {
        _selectedDateRange = tempRange;
        _currentPage = 1;
      });
    }
  }

  // ⭐ ENRICHED VERIFICATION
  void _openVerification(Map<String, dynamic> log) {
    final enrichedLog = Map<String, dynamic>.from(log);

    final device = _resolveRegisteredDevice(log);
    if (device != null && device.isNotEmpty) {
      enrichedLog['registeredDevice'] = device;
    }

    enrichedLog['resolvedEmployeeName'] = _resolveName(log);
    enrichedLog['resolvedEmail'] = _resolveEmail(log);
    enrichedLog['resolvedDepartment'] = _resolveDepartment(log);

    final photo = _resolvePhotoUrl(log);
    if (photo != null && photo.isNotEmpty) {
      enrichedLog['resolvedPhotoUrl'] = photo;
    }

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔍 [Attendance] Opening verification');
    debugPrint('   logId:     ${log['id']}');
    debugPrint('   empName:   ${enrichedLog['resolvedEmployeeName']}');
    debugPrint('   device:    ${enrichedLog['registeredDevice'] ?? 'N/A'}');
    debugPrint('   dept:      ${enrichedLog['resolvedDepartment']}');
    debugPrint('═══════════════════════════════════════════');

    final dashboard = context.findAncestorStateOfType<AdminDashboardState>();
    if (dashboard != null) {
      dashboard.openAttendanceVerification(
        log['id'] ?? '',
        enrichedLog,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPageHeader(),
              const SizedBox(height: 24),
              _buildFilterBar(),
              const SizedBox(height: 24),
              _buildTable(),
              const SizedBox(height: 24),
              _buildBottomCards(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────
  Widget _buildPageHeader() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: r.responsive<double>(xs: 22, sm: 26, md: 28, lg: 32),
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Monitor real-time employee check-ins and check-outs across all departments.',
            style: TextStyle(
                fontSize: r.responsive<double>(xs: 13, md: 16),
                color: tc.textMuted),
          ),
        ],
      );

      final refreshBtn = _buildActionButton(
        icon: Icons.refresh_rounded,
        label: 'Refresh',
        onPressed: widget.onRefreshNeeded,
        bgColor: tc.card,
        textColor: tc.text,
        borderColor: tc.border,
      );

      final exportBtn = _buildActionButton(
        icon: Icons.download_rounded,
        label: 'Export Logs',
        onPressed: () {},
        bgColor: tc.orange,
        textColor: tc.isDark ? tc.onOrange : Colors.white,
        borderColor: tc.orange,
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: refreshBtn),
              const SizedBox(width: 12),
              Expanded(child: exportBtn),
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
            refreshBtn,
            const SizedBox(width: 12),
            exportBtn,
          ]),
        ],
      );
    });
  }

  // ─── FILTER BAR ────────────────────────────────────────────
  Widget _buildFilterBar() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.lg);

      // ─── 1. DATE RANGE ───
      final dateField = _buildFilterField(
        label: 'DATE RANGE',
        child: InkWell(
          onTap: _pickDateRange,
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: tc.card,
              border: Border.all(color: tc.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedDateRange == null
                        ? 'mm / dd / yyyy'
                        : '${DateFormat('MM/dd/yyyy').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd/yyyy').format(_selectedDateRange!.end)}',
                    style: TextStyle(color: tc.text, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.calendar_today, size: 16, color: tc.muted),
              ],
            ),
          ),
        ),
      );

      // ─── 2. YEAR ───
      final yearField = _buildFilterField(
        label: 'YEAR',
        child: _buildDropdown<String>(
          value: _selectedYear,
          items: _years,
          onChanged: (val) => setState(() {
            _selectedYear = val ?? 'All Years';
            _currentPage = 1;
          }),
        ),
      );

      // ─── 3. EVENT TYPE ───
      final eventField = _buildFilterField(
        label: 'EVENT TYPE',
        child: _buildDropdown<String>(
          value: _selectedEventType,
          items: _eventTypes,
          onChanged: (val) => setState(() {
            _selectedEventType = val ?? 'All Events';
            _currentPage = 1;
          }),
        ),
      );

      // ─── 4. DEPARTMENT ───
      final deptField = _buildFilterField(
        label: 'DEPARTMENT',
        child: _buildDropdown<String>(
          value: _selectedDepartment,
          items: _departments,
          onChanged: (val) => setState(() {
            _selectedDepartment = val ?? 'All Departments';
            _currentPage = 1;
          }),
        ),
      );

      // ─── 5. APPLY BUTTON ───
      final applyBtn = SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: () => setState(() => _currentPage = 1),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.surface,
            foregroundColor: tc.textMuted,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child:
          const Text('Apply Filters', style: TextStyle(fontSize: 14)),
        ),
      );

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tc.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.border),
        ),
        child: narrow
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            dateField,
            const SizedBox(height: 12),
            yearField,
            const SizedBox(height: 12),
            eventField,
            const SizedBox(height: 12),
            deptField,
            const SizedBox(height: 16),
            applyBtn,
          ],
        )
            : Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 2, child: dateField),
            const SizedBox(width: 12),
            Expanded(child: yearField),
            const SizedBox(width: 12),
            Expanded(child: eventField),
            const SizedBox(width: 12),
            Expanded(child: deptField),
            const SizedBox(width: 12),
            applyBtn,
          ],
        ),
      );
    });
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      dropdownColor: tc.card,
      iconEnabledColor: tc.text,
      style: TextStyle(
          color: tc.text, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        filled: true,
        fillColor: tc.card,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem<T>(
        value: e,
        child: Text('$e', style: TextStyle(color: tc.text)),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }

  // ─── TABLE ─────────────────────────────────────────────────
  Widget _buildTable() {
    return LayoutBuilder(builder: (_, c) {
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
            if (_paginatedLogs.isEmpty)
              _buildEmptyState()
            else if (isMobile)
              ..._paginatedLogs.map((log) => _buildMobileCard(log))
            else
              ..._paginatedLogs.map((log) => _buildRow(log)),
            if (_paginatedLogs.isNotEmpty) _buildPagination(),
          ],
        ),
      );
    });
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _th('EMPLOYEE', flex: 3),
          _th('CONTACT', flex: 3),
          _th('DATE', flex: 1),
          _th('TIME', flex: 1),
          _th('EVENT', flex: 1),
          _th('ACTIONS', flex: 1, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.hourglass_empty, size: 64, color: tc.muted),
          const SizedBox(height: 16),
          Text('No attendance records found',
              style: TextStyle(fontSize: 16, color: tc.muted)),
        ],
      ),
    );
  }

  Widget _th(String label,
      {required int flex, TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: tc.textMuted),
      ),
    );
  }

  // ─── AVATAR ────────────────────────────────────────────────
  Widget _buildAvatarWidget({
    required String? photoUrl,
    required String initials,
    required double size,
    required double fontSize,
  }) {
    if (photoUrl == null || photoUrl.isEmpty || photoUrl == '—') {
      return _initialsAvatar(
          initials: initials, size: size, fontSize: fontSize);
    }

    if (photoUrl.startsWith('data:image')) {
      try {
        final b64 = photoUrl.split(',').last;
        final bytes = base64Decode(b64);
        return Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: tc.orange.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsAvatar(
                initials: initials, size: size, fontSize: fontSize),
          ),
        );
      } catch (e) {
        debugPrint('⚠️ [Attendance] Base64 decode failed: $e');
        return _initialsAvatar(
            initials: initials, size: size, fontSize: fontSize);
      }
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
        Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsAvatar(
            initials: initials, size: size, fontSize: fontSize),
      ),
    );
  }

  Widget _initialsAvatar({
    required String initials,
    required double size,
    required double fontSize,
  }) {
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
        child: Text(
          initials,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: tc.orangeText,
          ),
        ),
      ),
    );
  }

  String _initialsFor(String name) {
    if (name.isEmpty || name == 'Unknown Employee') return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  // ─── DESKTOP ROW ───────────────────────────────────────────
  Widget _buildRow(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';

    final name = _resolveName(log);
    final email = _resolveEmail(log);
    final dept = _resolveDepartment(log);
    final photoUrl = _resolvePhotoUrl(log);
    final employeeId =
    (log['employee_id'] ?? log['employeeId'] ?? '').toString();

    final initials = _initialsFor(name);
    final displayEmail = email.isNotEmpty
        ? email
        : (employeeId.isNotEmpty ? '$employeeId@company.com' : '—');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _buildAvatarWidget(
                  photoUrl: photoUrl,
                  initials: initials,
                  size: 40,
                  fontSize: 15,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dept,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: dept == 'No Department'
                              ? tc.muted
                              : tc.orangeText,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              displayEmail,
              style: TextStyle(fontSize: 13, color: tc.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(_fmtDate(log['timestamp']),
                style: TextStyle(fontSize: 13, color: tc.text)),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _fmtTime(log['timestamp']),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: tc.text),
            ),
          ),
          Expanded(flex: 1, child: _buildEventPill(isLogin)),
          Expanded(flex: 1, child: _buildActions(log)),
        ],
      ),
    );
  }

  // ─── MOBILE CARD ───────────────────────────────────────────
  Widget _buildMobileCard(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';

    final name = _resolveName(log);
    final email = _resolveEmail(log);
    final dept = _resolveDepartment(log);
    final photoUrl = _resolvePhotoUrl(log);
    final employeeId =
    (log['employee_id'] ?? log['employeeId'] ?? '').toString();

    final initials = _initialsFor(name);
    final displayEmail = email.isNotEmpty
        ? email
        : (employeeId.isNotEmpty ? '$employeeId@company.com' : '—');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarWidget(
                photoUrl: photoUrl,
                initials: initials,
                size: 48,
                fontSize: 16,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: tc.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dept,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: dept == 'No Department'
                            ? tc.muted
                            : tc.orangeText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(displayEmail,
                        style:
                        TextStyle(fontSize: 12, color: tc.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              _buildActions(log),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 13, color: tc.textMuted),
              const SizedBox(width: 6),
              Text(_fmtDate(log['timestamp']),
                  style: TextStyle(fontSize: 12, color: tc.textMuted)),
              const SizedBox(width: 12),
              Icon(Icons.access_time_rounded,
                  size: 13, color: tc.textMuted),
              const SizedBox(width: 6),
              Text(
                _fmtTime(log['timestamp']),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tc.text),
              ),
              const Spacer(),
              _buildEventPill(isLogin, compact: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventPill(bool isLogin, {bool compact = false}) {
    return Container(
      padding:
      EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 4),
      decoration: BoxDecoration(
        color: isLogin ? tc.pillGreenBg : tc.pillBlueBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isLogin ? 'IN' : 'OUT',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isLogin ? tc.pillGreenTx : tc.pillBlueTx,
        ),
      ),
    );
  }

  Widget _buildActions(Map<String, dynamic> log) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: 20, color: tc.textMuted),
          color: tc.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: tc.border),
          ),
          tooltip: 'Actions',
          onSelected: (value) {
            switch (value) {
              case 'verify':
                _openVerification(log);
                break;
              case 'approve':
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Approved: ${_resolveName(log)}'),
                  backgroundColor: tc.green,
                ));
                break;
              case 'flag':
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Flagged: ${_resolveName(log)}'),
                  backgroundColor: tc.red,
                ));
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'verify',
              child: Row(children: [
                Icon(Icons.fact_check_outlined,
                    size: 16, color: tc.orange),
                const SizedBox(width: 10),
                Text('View Verification',
                    style: TextStyle(color: tc.text, fontSize: 13)),
              ]),
            ),
            PopupMenuItem<String>(
              value: 'approve',
              child: Row(children: [
                Icon(Icons.check_circle_outline,
                    size: 16, color: tc.green),
                const SizedBox(width: 10),
                Text('Approve',
                    style: TextStyle(color: tc.text, fontSize: 13)),
              ]),
            ),
            PopupMenuItem<String>(
              value: 'flag',
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 16, color: tc.red),
                const SizedBox(width: 10),
                Text('Flag for Review',
                    style: TextStyle(color: tc.text, fontSize: 13)),
              ]),
            ),
          ],
        ),
        IconButton(
          icon: Icon(Icons.arrow_forward_rounded,
              size: 18, color: tc.textMuted),
          tooltip: 'Open verification',
          onPressed: () => _openVerification(log),
        ),
      ],
    );
  }

  // ─── PAGINATION ────────────────────────────────────────────
  Widget _buildPagination() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final info = Text(
        'Showing ${_filteredLogs.isEmpty ? 0 : (_currentPage - 1) * _rowsPerPage + 1} to ${_currentPage * _rowsPerPage > _filteredLogs.length ? _filteredLogs.length : _currentPage * _rowsPerPage} of ${_filteredLogs.length} entries',
        style: TextStyle(fontSize: 13, color: tc.textMuted),
        overflow: TextOverflow.ellipsis,
      );

      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () => setState(() => _currentPage--)
                : null,
            icon: Icon(Icons.chevron_left,
                size: 20,
                color: _currentPage > 1 ? tc.text : tc.muted),
          ),
          ...List.generate(_totalPages, (index) {
            final i = index + 1;
            final isActive = i == _currentPage;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? tc.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border:
                isActive ? null : Border.all(color: tc.border),
              ),
              child: InkWell(
                onTap: () => setState(() => _currentPage = i),
                child: Text(
                  '$i',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.normal,
                    color: isActive
                        ? (tc.isDark ? tc.onOrange : Colors.white)
                        : tc.text,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: Icon(Icons.chevron_right,
                size: 20,
                color:
                _currentPage < _totalPages ? tc.text : tc.muted),
          ),
        ],
      );

      return Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: narrow
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            info,
            const SizedBox(height: 12),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: controls),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [info, controls],
        ),
      );
    });
  }

  // ─── BOTTOM CARDS ──────────────────────────────────────────
  Widget _buildBottomCards() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final stack = !r.up(BsSize.lg);

      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBiometricCard(),
            const SizedBox(height: 20),
            _buildAuditCard(),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildBiometricCard()),
          const SizedBox(width: 24),
          Expanded(child: _buildAuditCard()),
        ],
      );
    });
  }

  Widget _buildBiometricCard() {
    return Container(
      height: 300,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/logo1.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: tc.isDark
                        ? [
                      const Color(0xFF1F2937),
                      const Color(0xFF111827),
                      const Color(0xFF0F172A),
                    ]
                        : [
                      const Color(0xFF3B4A5F),
                      const Color(0xFF1F2937),
                      const Color(0xFF111827),
                    ],
                  ),
                ),
              );
            },
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text(
                  'Real-time Biometric Integration',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2),
                ),
                SizedBox(height: 8),
                Text(
                  'Every login and logout is synchronized instantly with central biometric hardware.',
                  style: TextStyle(
                      fontSize: 14, color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditCard() {
    final Color onOrange =
    tc.isDark ? tc.onOrange : const Color(0xFF623200);

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.orange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.security_rounded, size: 30, color: onOrange),
          Text(
            'Secure Audit Trail',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: onOrange,
                height: 1.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Detailed logs track timestamps, device IDs, and location data for administrative transparency.',
            style: TextStyle(
                fontSize: 14,
                color: onOrange.withValues(alpha: 0.9),
                height: 1.5),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: onOrange,
                foregroundColor: tc.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('View Compliance Report',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ───────────────────────────────────────────────
  Widget _buildFilterField(
      {required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tc.textMuted,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? bgColor,
    Color? textColor,
    Color? borderColor,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: textColor ?? tc.textMuted),
      label: Text(
        label,
        style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor ?? tc.textMuted),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: bgColor ?? tc.card,
        side: BorderSide(color: borderColor ?? tc.border, width: 1),
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}