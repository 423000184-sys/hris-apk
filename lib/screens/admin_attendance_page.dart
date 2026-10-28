// lib/screens/admin_attendance_page.dart
// v2.1: 🎭 Demo Mode Support (Mock Logs & Action Blocking)
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

import 'admin_dashboard.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import '../services/admin_employee_service.dart';
import '../services/demo_mode_service.dart'; // 🎭 Added
import '../utils/file_download.dart';
import '../widgets/bootstrap_grid.dart';

// ─── Security constants ───
const int kMaxCsvExportRows = 5000;
const int kMaxVisiblePages = 7;
const int kMaxBase64PhotoBytes = 2 * 1024 * 1024; // 2MB

/// Fields never exported to CSV in plaintext.
const Set<String> _csvSensitiveFields = {
  'email',
  'photo_url',
  'photoUrl',
  'faceEmbedding',
  'faceEmbeddingsJson',
  'pin',
  'pinHash',
};

class AdminAttendancePage extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> logs;
  final Color accent;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
  final List<Map<String, dynamic>> locations;
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

  // 🎭 Demo Mode Getter
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  // ─── Filter state ───
  String _selectedEventType = 'All Events';
  String _selectedDepartment = 'All Departments';
  String _selectedPosition = 'All Positions';
  String _selectedYear = 'All Years';
  DateTimeRange? _selectedDateRange;
  int _currentPage = 1;
  static const int _rowsPerPage = 5;

  // ─── Export state ───
  bool _exporting = false;

  // ─── Rate limiting ───
  DateTime? _lastExportAt;
  static const Duration _exportCooldown = Duration(seconds: 5);

  // ─── Filter application (prevents rebuild spam) ───
  String? _appliedEventType;
  String? _appliedDepartment;
  String? _appliedPosition;
  String? _appliedYear;
  DateTimeRange? _appliedDateRange;

  final List<String> _eventTypes = ['All Events', 'IN', 'OUT'];

  // ─── Predefined departments ───
  static const Map<String, List<String>> _predefinedDeptRoles = {
    'HR/Admin': ['Driver', 'Messenger'],
    'Accounting': ['Accountant'],
    'Operation': ['Manager', 'Broker'],
  };

  // ─── Employee lookup ───
  Map<String, Map<String, dynamic>> _employeeLookup = {};
  List<Map<String, dynamic>> _localEmployees = [];
  StreamSubscription<List<Map<String, dynamic>>>? _empSub;

  // ─── Actor context ───
  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  String get _actorEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _localEmployees = widget.employees;
    _buildEmployeeLookup();

    // 🎭 Only listen to real employees if NOT in demo mode
    if (!_isDemo) {
      _listenToEmployees();
    }
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

  // 🎭 DEMO BLOCK HELPER
  void _demoBlock() {
    _showSnack('Action disabled in Demo Mode.', error: true);
  }

  // 🎭 MOCK LOGS GENERATION
  List<Map<String, dynamic>> _getMockLogs() {
    final now = DateTime.now();
    return [
      {
        'id': 'demo_log_1',
        'employee_id': 'DEMO-001',
        'employee_name': 'John Doe',
        'type': 'IN',
        'timestamp': now.subtract(const Duration(hours: 1, minutes: 15)),
        'department': 'Operation',
        'position': 'Manager',
        'registeredDevice': 'iPhone 14 Pro',
      },
      {
        'id': 'demo_log_2',
        'employee_id': 'DEMO-002',
        'employee_name': 'Jane Smith',
        'type': 'IN',
        'timestamp': now.subtract(const Duration(hours: 2, minutes: 30)),
        'department': 'Accounting',
        'position': 'Accountant',
        'registeredDevice': 'Samsung Galaxy S23',
      },
      {
        'id': 'demo_log_3',
        'employee_id': 'DEMO-001',
        'employee_name': 'John Doe',
        'type': 'OUT',
        'timestamp': now.subtract(const Duration(hours: 3)),
        'department': 'Operation',
        'position': 'Manager',
        'registeredDevice': 'iPhone 14 Pro',
      },
      {
        'id': 'demo_log_4',
        'employee_id': 'DEMO-003',
        'employee_name': 'Mike Johnson',
        'type': 'IN',
        'timestamp': now.subtract(const Duration(hours: 5, minutes: 45)),
        'department': 'HR/Admin',
        'position': 'Driver',
        'registeredDevice': 'Xiaomi Redmi Note 12',
      },
      {
        'id': 'demo_log_5',
        'employee_id': 'DEMO-004',
        'employee_name': 'Sarah Lee',
        'type': 'OUT',
        'timestamp': now.subtract(const Duration(hours: 6, minutes: 10)),
        'department': 'Operation',
        'position': 'Broker',
        'registeredDevice': 'MacBook Pro (Web)',
      },
    ];
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE STREAM (bounded)
  // ══════════════════════════════════════════════════════════════
  void _listenToEmployees() {
    _empSub = AdminDatabase.streamEmployees()
        .timeout(const Duration(seconds: 30))
        .listen(
          (emps) {
        if (!mounted) return;
        final bounded = emps.length > 5000 ? emps.sublist(0, 5000) : emps;
        setState(() {
          _localEmployees = bounded.isNotEmpty ? bounded : widget.employees;
          _buildEmployeeLookup();
        });
      },
      onError: (e) {
        debugPrint('[Attendance] Employee stream error: $e');
      },
    );
  }

  void _buildEmployeeLookup() {
    final source = _localEmployees.isNotEmpty ? _localEmployees : widget.employees;
    final map = <String, Map<String, dynamic>>{};

    for (final emp in source) {
      final id = _sanitizeKey(emp['id']);
      final empId = _sanitizeKey(emp['employeeId'] ?? emp['employee_id']);
      final email = _sanitizeKey(emp['email']).toLowerCase();
      final name = _sanitizeKey(
        emp['name'] ??
            emp['fullName'] ??
            '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}',
      ).toLowerCase();

      if (id.isNotEmpty) map[id] = emp;
      if (empId.isNotEmpty) map[empId] = emp;
      if (email.isNotEmpty) map['email:$email'] = emp;
      if (name.isNotEmpty) map['name:$name'] = emp;
    }

    _employeeLookup = map;
  }

  String _sanitizeKey(dynamic v) {
    if (v == null) return '';
    var s = v.toString().replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u2028\u2029]'),
      '',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 200) s = s.substring(0, 200);
    return s;
  }

  Map<String, dynamic>? _findEmployee(Map<String, dynamic> log) {
    final id = _sanitizeKey(
      log['employee_id'] ?? log['employeeId'] ?? log['employeeID'],
    );
    if (id.isNotEmpty && _employeeLookup.containsKey(id)) {
      return _employeeLookup[id];
    }

    final email = _sanitizeKey(log['email']).toLowerCase();
    if (email.isNotEmpty && _employeeLookup.containsKey('email:$email')) {
      return _employeeLookup['email:$email'];
    }

    final name = _sanitizeKey(
      log['employee_name'] ?? log['employeeName'] ?? log['name'],
    ).toLowerCase();
    if (name.isNotEmpty && _employeeLookup.containsKey('name:$name')) {
      return _employeeLookup['name:$name'];
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // RESOLVERS (all sanitized)
  // ══════════════════════════════════════════════════════════════
  String _resolveDepartment(Map<String, dynamic> log) {
    final fromLog =
    _sanitizeKey(log['department'] ?? log['dept'] ?? log['section']);
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) {
      final dept =
      _sanitizeKey(emp['department'] ?? emp['dept'] ?? emp['section']);
      if (dept.isNotEmpty) return dept;
    }
    return 'No Department';
  }

  String _resolvePosition(Map<String, dynamic> log) {
    final fromLog = _sanitizeKey(
      log['position'] ?? log['role'] ?? log['jobTitle'] ?? log['job_title'],
    );
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) {
      final pos = _sanitizeKey(
        emp['position'] ?? emp['role'] ?? emp['jobTitle'] ?? emp['job_title'],
      );
      if (pos.isNotEmpty) return pos;
    }
    return '';
  }

  String _resolveName(Map<String, dynamic> log) {
    final fromLog = _sanitizeKey(
      log['employee_name'] ?? log['employeeName'] ?? log['name'],
    );
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) {
      final full = _sanitizeKey(emp['name'] ?? emp['fullName']);
      if (full.isNotEmpty) return full;

      final first = _sanitizeKey(emp['firstName'] ?? emp['first_name']);
      final last = _sanitizeKey(emp['lastName'] ?? emp['last_name']);
      final combo = '$first $last'.trim();
      if (combo.isNotEmpty) return combo;
    }
    return 'Unknown Employee';
  }

  String _resolveEmail(Map<String, dynamic> log) {
    final fromLog = _sanitizeKey(log['email']);
    if (fromLog.isNotEmpty) return fromLog;

    final emp = _findEmployee(log);
    if (emp != null) return _sanitizeKey(emp['email']);
    return '';
  }

  String _maskEmail(String email) {
    if (email.isEmpty) return '';
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at);
    final domain = email.substring(at);
    if (local.length <= 2) {
      return '${local[0]}***$domain';
    }
    return '${local[0]}${'*' * (local.length - 2)}${local[local.length - 1]}$domain';
  }

  String? _resolvePhotoUrl(Map<String, dynamic> log) {
    const keys = ['photoUrl', 'photo', 'imageUrl', 'image', 'avatar'];

    for (final key in keys) {
      final v = _sanitizeKey(log[key]);
      if (v.isNotEmpty && v != '—' && v != 'null') {
        if (!_isSafeUrl(v)) return null;
        return v;
      }
    }

    final emp = _findEmployee(log);
    if (emp != null) {
      for (final key in keys) {
        final v = _sanitizeKey(emp[key]);
        if (v.isNotEmpty && v != '—' && v != 'null') {
          if (!_isSafeUrl(v)) return null;
          return v;
        }
      }
    }
    return null;
  }

  bool _isSafeUrl(String url) {
    if (url.startsWith('data:image/')) return true;
    if (url.startsWith('https://')) return true;
    if (url.startsWith('http://')) return true;
    return false;
  }

  String? _resolveRegisteredDevice(Map<String, dynamic> log) {
    final fromLog = _sanitizeKey(
      log['registeredDevice'] ?? log['deviceName'] ?? log['device'],
    );
    if (fromLog.isNotEmpty && fromLog != '—' && fromLog != 'null') {
      return fromLog;
    }

    final emp = _findEmployee(log);
    if (emp != null) {
      final dev = _sanitizeKey(
        emp['deviceName'] ?? emp['registeredDevice'] ?? emp['device'],
      );
      if (dev.isNotEmpty && dev != '—' && dev != 'null') return dev;
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // FILTER OPTIONS
  // ══════════════════════════════════════════════════════════════
  List<String> get _departments {
    final depts = <String>{..._predefinedDeptRoles.keys};

    for (final log in (_isDemo ? _getMockLogs() : widget.logs)) {
      final dept = _resolveDepartment(log);
      if (dept.isNotEmpty && dept != 'No Department') depts.add(dept);
    }

    final sorted = depts.toList()..sort();
    return ['All Departments', ...sorted];
  }

  List<String> get _positions {
    final positions = <String>{};

    if (_selectedDepartment == 'All Departments') {
      for (final roles in _predefinedDeptRoles.values) {
        positions.addAll(roles);
      }
      for (final log in (_isDemo ? _getMockLogs() : widget.logs)) {
        final pos = _resolvePosition(log);
        if (pos.isNotEmpty) positions.add(pos);
      }
    } else {
      final predefined = _predefinedDeptRoles[_selectedDepartment];
      if (predefined != null) positions.addAll(predefined);

      for (final log in (_isDemo ? _getMockLogs() : widget.logs)) {
        if (_resolveDepartment(log) == _selectedDepartment) {
          final pos = _resolvePosition(log);
          if (pos.isNotEmpty) positions.add(pos);
        }
      }
    }

    final sorted = positions.toList()..sort();
    return ['All Positions', ...sorted];
  }

  List<String> get _years {
    final years = <int>{};
    for (final log in (_isDemo ? _getMockLogs() : widget.logs)) {
      final dt = _toDateTime(log['timestamp']);
      if (dt != null) years.add(dt.year);
    }
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return ['All Years', ...sorted.map((y) => y.toString())];
  }

  // ══════════════════════════════════════════════════════════════
  // FILTERING
  // ══════════════════════════════════════════════════════════════
  List<Map<String, dynamic>> get _filteredLogs {
    final eventType = _appliedEventType ?? _selectedEventType;
    final department = _appliedDepartment ?? _selectedDepartment;
    final position = _appliedPosition ?? _selectedPosition;
    final year = _appliedYear ?? _selectedYear;
    final dateRange = _appliedDateRange ?? _selectedDateRange;

    // 🎭 Use mock data if in Demo Mode
    final sourceLogs = _isDemo ? _getMockLogs() : widget.logs;

    var filtered = sourceLogs.where((log) {
      final name = _resolveName(log).toLowerCase();
      final id = _sanitizeKey(log['employee_id'] ?? log['employeeId']).toLowerCase();
      final email = _resolveEmail(log).toLowerCase();
      final query = widget.searchQuery.toLowerCase();
      return name.contains(query) || id.contains(query) || email.contains(query);
    }).toList();

    if (eventType != 'All Events') {
      filtered = filtered.where((log) {
        final type = (log['type'] ?? 'IN').toString().toUpperCase();
        return type == eventType;
      }).toList();
    }

    if (department != 'All Departments') {
      filtered = filtered
          .where((log) => _resolveDepartment(log) == department)
          .toList();
    }

    if (position != 'All Positions') {
      filtered = filtered
          .where((log) => _resolvePosition(log) == position)
          .toList();
    }

    if (year != 'All Years') {
      final y = int.tryParse(year);
      if (y != null) {
        filtered = filtered.where((log) {
          final dt = _toDateTime(log['timestamp']);
          return dt != null && dt.year == y;
        }).toList();
      }
    }

    if (dateRange != null) {
      filtered = filtered.where((log) {
        final dt = _toDateTime(log['timestamp']);
        if (dt == null) return false;
        return dt.isAfter(dateRange.start.subtract(const Duration(days: 1))) &&
            dt.isBefore(dateRange.end.add(const Duration(days: 1)));
      }).toList();
    }

    filtered.sort((a, b) {
      final dtA = _toDateTime(a['timestamp']);
      final dtB = _toDateTime(b['timestamp']);
      if (dtA == null && dtB == null) return 0;
      if (dtA == null) return 1;
      if (dtB == null) return -1;
      return dtB.compareTo(dtA);
    });

    return filtered;
  }

  List<Map<String, dynamic>> get _paginatedLogs {
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = start + _rowsPerPage;
    final all = _filteredLogs;
    if (start >= all.length) return [];
    return all.sublist(start, end.clamp(0, all.length));
  }

  int get _totalPages => (_filteredLogs.length / _rowsPerPage).ceil();

  // ══════════════════════════════════════════════════════════════
  // DATE HELPERS
  // ══════════════════════════════════════════════════════════════
  String _fmtTime(dynamic ts) {
    final dt = _toDateTime(ts);
    if (dt == null) return '--:--';
    return DateFormat('hh:mm a').format(dt);
  }

  String _fmtDate(dynamic ts) {
    final dt = _toDateTime(ts);
    if (dt == null) return '—';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // CSV EXPORT
  // ══════════════════════════════════════════════════════════════
  Future<void> _exportLogsToCsv() async {
    if (_isDemo) return _demoBlock(); // 🎭 Block in Demo
    if (_exporting) return;

    if (_lastExportAt != null) {
      final elapsed = DateTime.now().difference(_lastExportAt!);
      if (elapsed < _exportCooldown) {
        final remaining = (_exportCooldown - elapsed).inSeconds;
        _showSnack('Please wait ${remaining}s before exporting again.', error: true);
        return;
      }
    }

    final logs = _filteredLogs;
    if (logs.isEmpty) {
      _showSnack('No attendance logs to export.', error: true);
      return;
    }

    if (logs.length > kMaxCsvExportRows) {
      _showSnack(
        'Too many rows to export (${logs.length}). Maximum is $kMaxCsvExportRows. Please narrow your filters.',
        error: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: tc.orange, size: 22),
          const SizedBox(width: 10),
          Text('Export Attendance Logs?', style: TextStyle(color: tc.text)),
        ]),
        content: Text(
          'You are about to export ${logs.length} attendance record(s) to CSV.\n\n'
              'Employee emails will be masked for privacy. This action will be logged for audit.',
          style: TextStyle(color: tc.text, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _exporting = true);
    _lastExportAt = DateTime.now();

    try {
      const headers = <String>[
        'log_id',
        'employee_id',
        'employee_name',
        'email_masked',
        'department',
        'position',
        'event_type',
        'date',
        'time',
        'registered_device',
      ];

      final buffer = StringBuffer();
      buffer.write('\uFEFF');
      buffer.write(headers.map(_csvEscape).join(','));
      buffer.write('\r\n');

      for (final log in logs) {
        final dt = _toDateTime(log['timestamp']);
        final email = _resolveEmail(log);

        final row = <String>[
          _sanitizeCsvCell((log['id'] ?? '').toString()),
          _sanitizeCsvCell(
            (log['employee_id'] ?? log['employeeId'] ?? log['employeeID'] ?? '')
                .toString(),
          ),
          _sanitizeCsvCell(_resolveName(log)),
          email.isEmpty ? '' : _maskEmail(email),
          _sanitizeCsvCell(_resolveDepartment(log)),
          _sanitizeCsvCell(_resolvePosition(log)),
          (log['type'] ?? 'IN').toString().toUpperCase(),
          dt != null ? DateFormat('yyyy-MM-dd').format(dt) : '',
          dt != null ? DateFormat('HH:mm:ss').format(dt) : '',
          _sanitizeCsvCell(_resolveRegisteredDevice(log) ?? ''),
        ];

        buffer.write(row.map(_csvEscape).join(','));
        buffer.write('\r\n');
      }

      final tsStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'attendance_logs_$tsStr.csv';

      final savedPath = await downloadTextFile(
        filename: fileName,
        content: buffer.toString(),
      );

      try {
        await FirebaseFirestore.instance.collection('admin_audit_log').add({
          'action': 'attendance_csv_exported',
          'targetType': 'bulk',
          'targetId': 'attendance_logs',
          'actorUid': _actorUid,
          'actorEmail': _actorEmail,
          'details': {
            'recordCount': logs.length,
            'fileName': fileName,
            'filters': {
              'eventType': _selectedEventType,
              'department': _selectedDepartment,
              'position': _selectedPosition,
              'year': _selectedYear,
            },
          },
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Audit log failed: $e');
      }

      if (!mounted) return;
      if (savedPath != null) {
        _showSnack('Exported ${logs.length} log(s) to $fileName');
      } else {
        _showSnack('Export failed or cancelled.', error: true);
      }
    } catch (e) {
      debugPrint('Attendance CSV export error: $e');
      if (!mounted) return;
      _showSnack('Export failed.', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _sanitizeCsvCell(String v) {
    var s = v.replaceAll(RegExp(r'[\u0000-\u001F\u007F\u2028\u2029]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 500) s = s.substring(0, 500);
    return s;
  }

  String _csvEscape(String value) {
    var v = value;
    if (v.isNotEmpty) {
      final first = v[0];
      if (first == '=' || first == '+' || first == '-' || first == '@') {
        v = "'$v";
      }
    }
    if (v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  // ══════════════════════════════════════════════════════════════
  // SNACKBAR HELPER
  // ══════════════════════════════════════════════════════════════
  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DATE RANGE PICKER
  // ══════════════════════════════════════════════════════════════
  Future<void> _pickDateRange() async {
    DateTimeRange? tempRange = _selectedDateRange;

    final applied = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: tc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 640,
            height: 620,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              children: [
                Row(children: [
                  Icon(Icons.date_range_rounded, color: tc.orange, size: 22),
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
                    icon: Icon(Icons.close_rounded, color: tc.muted, size: 20),
                    onPressed: () => Navigator.pop(dialogCtx, false),
                  ),
                ]),
                Divider(color: tc.border, height: 20),
                Expanded(
                  child: SfDateRangePicker(
                    view: DateRangePickerView.month,
                    selectionMode: DateRangePickerSelectionMode.range,
                    initialSelectedRange: _selectedDateRange != null
                        ? PickerDateRange(
                        _selectedDateRange!.start, _selectedDateRange!.end)
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
                      textStyle: TextStyle(color: tc.text, fontSize: 13),
                      todayTextStyle: TextStyle(
                          color: tc.orange, fontWeight: FontWeight.w700),
                      trailingDatesTextStyle:
                      TextStyle(color: tc.muted.withValues(alpha: 0.5)),
                      leadingDatesTextStyle:
                      TextStyle(color: tc.muted.withValues(alpha: 0.5)),
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
                    rangeSelectionColor: tc.orange.withValues(alpha: 0.25),
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
                Row(children: [
                  if (_selectedDateRange != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedDateRange = null;
                          _appliedDateRange = null;
                          _currentPage = 1;
                        });
                        Navigator.pop(dialogCtx, false);
                      },
                      icon: Icon(Icons.clear_rounded, size: 14, color: tc.muted),
                      label: Text('CLEAR',
                          style: TextStyle(
                              color: tc.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: Text('CANCEL',
                        style: TextStyle(
                            color: tc.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
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
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('APPLY',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 0.5)),
                  ),
                ]),
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

  // ══════════════════════════════════════════════════════════════
  // APPLY FILTERS
  // ══════════════════════════════════════════════════════════════
  void _applyFilters() {
    setState(() {
      _appliedEventType = _selectedEventType;
      _appliedDepartment = _selectedDepartment;
      _appliedPosition = _selectedPosition;
      _appliedYear = _selectedYear;
      _appliedDateRange = _selectedDateRange;
      _currentPage = 1;
    });
    _showSnack('Filters applied.');
  }

  // ══════════════════════════════════════════════════════════════
  // OPEN VERIFICATION
  // ══════════════════════════════════════════════════════════════
  void _openVerification(Map<String, dynamic> log) {
    final enrichedLog = Map<String, dynamic>.from(log);

    final device = _resolveRegisteredDevice(log);
    if (device != null && device.isNotEmpty) {
      enrichedLog['registeredDevice'] = device;
    }

    enrichedLog['resolvedEmployeeName'] = _resolveName(log);
    enrichedLog['resolvedEmail'] = _resolveEmail(log);
    enrichedLog['resolvedDepartment'] = _resolveDepartment(log);
    enrichedLog['resolvedPosition'] = _resolvePosition(log);

    final photo = _resolvePhotoUrl(log);
    if (photo != null && photo.isNotEmpty) {
      enrichedLog['resolvedPhotoUrl'] = photo;
    }

    final dashboard = context.findAncestorStateOfType<AdminDashboardState>();
    if (dashboard != null) {
      dashboard.openAttendanceVerification(
        (log['id'] ?? '').toString(),
        enrichedLog,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // APPROVE / FLAG — with audit logging
  // ══════════════════════════════════════════════════════════════
  Future<void> _approveLog(Map<String, dynamic> log) async {
    if (_isDemo) return _demoBlock(); // 🎭 Block in Demo

    final logId = (log['id'] ?? '').toString();
    if (logId.isEmpty) {
      _showSnack('Missing log ID.', error: true);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('attendance_logs')
          .doc(logId)
          .set({
        'reviewStatus': 'approved',
        'reviewedBy': _actorEmail,
        'reviewedByUid': _actorUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      try {
        await FirebaseFirestore.instance.collection('admin_audit_log').add({
          'action': 'attendance_approved',
          'targetType': 'attendance_log',
          'targetId': logId,
          'actorUid': _actorUid,
          'actorEmail': _actorEmail,
          'details': {
            'employeeName': _resolveName(log),
          },
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      _showSnack('Attendance approved.');
      widget.onRefreshNeeded();
    } catch (e) {
      debugPrint('Approve failed: $e');
      _showSnack('Failed to approve. Please try again.', error: true);
    }
  }

  Future<void> _flagLog(Map<String, dynamic> log) async {
    if (_isDemo) return _demoBlock(); // 🎭 Block in Demo

    final logId = (log['id'] ?? '').toString();
    if (logId.isEmpty) {
      _showSnack('Missing log ID.', error: true);
      return;
    }

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Flag for Review', style: TextStyle(color: tc.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Flag ${_resolveName(log)} for review. Provide a reason.',
              style: TextStyle(color: tc.text, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLength: 200,
              maxLines: 3,
              style: TextStyle(color: tc.text),
              decoration: InputDecoration(
                labelText: 'Reason',
                labelStyle: TextStyle(color: tc.muted),
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Flag'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = AdminEmployeeService.sanitize(
      reasonCtrl.text,
      maxLen: 200,
    );
    if (reason.isEmpty) {
      _showSnack('Reason is required to flag.', error: true);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('attendance_logs')
          .doc(logId)
          .set({
        'reviewStatus': 'flagged',
        'reviewReason': reason,
        'reviewedBy': _actorEmail,
        'reviewedByUid': _actorUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      try {
        await FirebaseFirestore.instance.collection('admin_audit_log').add({
          'action': 'attendance_flagged',
          'targetType': 'attendance_log',
          'targetId': logId,
          'actorUid': _actorUid,
          'actorEmail': _actorEmail,
          'details': {
            'employeeName': _resolveName(log),
            'reason': reason,
          },
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      _showSnack('Attendance flagged for review.');
      widget.onRefreshNeeded();
    } catch (e) {
      debugPrint('Flag failed: $e');
      _showSnack('Failed to flag. Please try again.', error: true);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
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
              // 🎭 DEMO BANNER
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 24),
              ],
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

  // ══════════════════════════════════════════════════════════════
  // 🎭 DEMO BANNER
  // ══════════════════════════════════════════════════════════════
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
                  'Showing sample data. Exporting, approving, and flagging are disabled.',
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

  // ─── HEADER ───
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
            'Monitor real-time employee check-ins and check-outs.',
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
        label: _exporting ? 'Exporting...' : 'Export Logs',
        onPressed: (_isDemo || _exporting) ? () {} : _exportLogsToCsv,
        bgColor: _isDemo ? tc.border : tc.orange,
        textColor: _isDemo ? tc.muted : (tc.isDark ? tc.onOrange : Colors.white),
        borderColor: _isDemo ? tc.border : tc.orange,
        showSpinner: _exporting,
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

  // ─── FILTER BAR ───
  Widget _buildFilterBar() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.xl);

      final dateField = _buildFilterField(
        label: 'DATE RANGE',
        child: InkWell(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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

      final yearField = _buildFilterField(
        label: 'YEAR',
        child: _buildDropdown<String>(
          value: _selectedYear,
          items: _years,
          onChanged: (val) => setState(() {
            _selectedYear = val ?? 'All Years';
          }),
        ),
      );

      final eventField = _buildFilterField(
        label: 'EVENT TYPE',
        child: _buildDropdown<String>(
          value: _selectedEventType,
          items: _eventTypes,
          onChanged: (val) => setState(() {
            _selectedEventType = val ?? 'All Events';
          }),
        ),
      );

      final deptField = _buildFilterField(
        label: 'DEPARTMENT',
        child: _buildDropdown<String>(
          value: _selectedDepartment,
          items: _departments,
          onChanged: (val) {
            setState(() {
              _selectedDepartment = val ?? 'All Departments';
              _selectedPosition = 'All Positions';
            });
          },
        ),
      );

      final positionField = _buildFilterField(
        label: 'POSITION',
        child: _buildDropdown<String>(
          value: _selectedPosition,
          items: _positions,
          onChanged: (val) => setState(() {
            _selectedPosition = val ?? 'All Positions';
          }),
        ),
      );

      final applyBtn = SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _applyFilters,
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: tc.isDark ? tc.onOrange : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text(
            'Apply Filters',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
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
            const SizedBox(height: 12),
            positionField,
            const SizedBox(height: 16),
            applyBtn,
          ],
        )
            : Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 2, child: dateField),
            const SizedBox(width: 10),
            Expanded(child: yearField),
            const SizedBox(width: 10),
            Expanded(child: eventField),
            const SizedBox(width: 10),
            Expanded(child: deptField),
            const SizedBox(width: 10),
            Expanded(child: positionField),
            const SizedBox(width: 10),
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
      initialValue: value,
      isExpanded: true,
      dropdownColor: tc.card,
      iconEnabledColor: tc.text,
      style: TextStyle(color: tc.text, fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        filled: true,
        fillColor: tc.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        child: Text('$e',
            style: TextStyle(color: tc.text),
            overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }

  // ─── TABLE ───
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
      child: Row(children: [
        _th('EMPLOYEE', flex: 3),
        _th('CONTACT', flex: 3),
        _th('DATE', flex: 1),
        _th('TIME', flex: 1),
        _th('EVENT', flex: 1),
        _th('ACTIONS', flex: 1, align: TextAlign.right),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Icon(Icons.hourglass_empty, size: 64, color: tc.muted),
        const SizedBox(height: 16),
        Text('No attendance records found',
            style: TextStyle(fontSize: 16, color: tc.muted)),
      ]),
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

  // ─── AVATAR ───
  Widget _buildAvatarWidget({
    required String? photoUrl,
    required String initials,
    required double size,
    required double fontSize,
  }) {
    if (photoUrl == null || photoUrl.isEmpty || photoUrl == '—') {
      return _initialsAvatar(initials: initials, size: size, fontSize: fontSize);
    }

    if (photoUrl.startsWith('data:image')) {
      try {
        final b64 = photoUrl.split(',').last;
        if (b64.length > kMaxBase64PhotoBytes * 2) {
          return _initialsAvatar(
              initials: initials, size: size, fontSize: fontSize);
        }
        final bytes = base64Decode(b64);
        if (bytes.length > kMaxBase64PhotoBytes) {
          return _initialsAvatar(
              initials: initials, size: size, fontSize: fontSize);
        }

        return Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1.5),
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
      } catch (_) {
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
        border: Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Image.network(
        photoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialsAvatar(
            initials: initials, size: size, fontSize: fontSize),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return _initialsAvatar(
              initials: initials, size: size, fontSize: fontSize);
        },
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
        border: Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1),
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

  // ─── DESKTOP ROW ───
  Widget _buildRow(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';

    final name = _resolveName(log);
    final email = _resolveEmail(log);
    final dept = _resolveDepartment(log);
    final position = _resolvePosition(log);
    final photoUrl = _resolvePhotoUrl(log);
    final employeeId =
    (log['employee_id'] ?? log['employeeId'] ?? '').toString();

    final initials = _initialsFor(name);
    final displayEmail = email.isNotEmpty
        ? _maskEmail(email)
        : (employeeId.isNotEmpty ? '$employeeId@company.com' : '—');

    final subtitle = <String>[];
    if (dept.isNotEmpty && dept != 'No Department') subtitle.add(dept);
    if (position.isNotEmpty) subtitle.add(position);
    final subtitleText =
    subtitle.isEmpty ? 'No Department' : subtitle.join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tc.border, width: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Row(children: [
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
                    subtitleText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: subtitle.isEmpty ? tc.muted : tc.orangeText,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ]),
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
                fontSize: 13, fontWeight: FontWeight.w500, color: tc.text),
          ),
        ),
        Expanded(flex: 1, child: _buildEventPill(isLogin)),
        Expanded(flex: 1, child: _buildActions(log)),
      ]),
    );
  }

  // ─── MOBILE CARD ───
  Widget _buildMobileCard(Map<String, dynamic> log) {
    final type = (log['type'] ?? 'IN').toString().toUpperCase();
    final isLogin = type == 'IN' || type == 'LOGIN';

    final name = _resolveName(log);
    final email = _resolveEmail(log);
    final dept = _resolveDepartment(log);
    final position = _resolvePosition(log);
    final photoUrl = _resolvePhotoUrl(log);
    final employeeId =
    (log['employee_id'] ?? log['employeeId'] ?? '').toString();

    final initials = _initialsFor(name);
    final displayEmail = email.isNotEmpty
        ? _maskEmail(email)
        : (employeeId.isNotEmpty ? '$employeeId@company.com' : '—');

    final subtitle = <String>[];
    if (dept.isNotEmpty && dept != 'No Department') subtitle.add(dept);
    if (position.isNotEmpty) subtitle.add(position);
    final subtitleText =
    subtitle.isEmpty ? 'No Department' : subtitle.join(' · ');

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
                      subtitleText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: subtitle.isEmpty ? tc.muted : tc.orangeText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(displayEmail,
                        style: TextStyle(fontSize: 12, color: tc.textMuted),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              _buildActions(log),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.calendar_today_rounded, size: 13, color: tc.textMuted),
            const SizedBox(width: 6),
            Text(_fmtDate(log['timestamp']),
                style: TextStyle(fontSize: 12, color: tc.textMuted)),
            const SizedBox(width: 12),
            Icon(Icons.access_time_rounded, size: 13, color: tc.textMuted),
            const SizedBox(width: 6),
            Text(
              _fmtTime(log['timestamp']),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: tc.text),
            ),
            const Spacer(),
            _buildEventPill(isLogin, compact: true),
          ]),
        ],
      ),
    );
  }

  Widget _buildEventPill(bool isLogin, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: 4),
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
                _approveLog(log);
                break;
              case 'flag':
                _flagLog(log);
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<String>(
              value: 'verify',
              child: Row(children: [
                Icon(Icons.fact_check_outlined, size: 16, color: tc.orange),
                const SizedBox(width: 10),
                Text('View Verification',
                    style: TextStyle(color: tc.text, fontSize: 13)),
              ]),
            ),
            PopupMenuItem<String>(
              value: 'approve',
              child: Row(children: [
                Icon(Icons.check_circle_outline, size: 16,
                    color: _isDemo ? tc.muted : tc.green),
                const SizedBox(width: 10),
                Text('Approve',
                    style: TextStyle(
                        color: _isDemo ? tc.muted : tc.text,
                        fontSize: 13)),
              ]),
            ),
            PopupMenuItem<String>(
              value: 'flag',
              child: Row(children: [
                Icon(Icons.flag_outlined, size: 16,
                    color: _isDemo ? tc.muted : tc.red),
                const SizedBox(width: 10),
                Text('Flag for Review',
                    style: TextStyle(
                        color: _isDemo ? tc.muted : tc.text,
                        fontSize: 13)),
              ]),
            ),
          ],
        ),
        IconButton(
          icon: Icon(Icons.arrow_forward_rounded, size: 18, color: tc.textMuted),
          tooltip: 'Open verification',
          onPressed: () => _openVerification(log),
        ),
      ],
    );
  }

  // ─── PAGINATION (bounded to prevent massive renders) ───
  Widget _buildPagination() {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final start = _filteredLogs.isEmpty
          ? 0
          : (_currentPage - 1) * _rowsPerPage + 1;
      final end = _currentPage * _rowsPerPage > _filteredLogs.length
          ? _filteredLogs.length
          : _currentPage * _rowsPerPage;

      final info = Text(
        'Showing $start to $end of ${_filteredLogs.length} entries',
        style: TextStyle(fontSize: 13, color: tc.textMuted),
        overflow: TextOverflow.ellipsis,
      );

      final totalPages = _totalPages;
      final visiblePages = _computeVisiblePages(totalPages);

      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () => setState(() => _currentPage--)
                : null,
            icon: Icon(Icons.chevron_left,
                size: 20, color: _currentPage > 1 ? tc.text : tc.muted),
          ),
          ...visiblePages.map((i) {
            final isActive = i == _currentPage;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? tc.orange : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: isActive ? null : Border.all(color: tc.border),
              ),
              child: InkWell(
                onTap: () => setState(() => _currentPage = i),
                child: Text(
                  '$i',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                    color: isActive
                        ? (tc.isDark ? tc.onOrange : Colors.white)
                        : tc.text,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: Icon(Icons.chevron_right,
                size: 20,
                color: _currentPage < totalPages ? tc.text : tc.muted),
          ),
        ],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

  List<int> _computeVisiblePages(int totalPages) {
    if (totalPages <= kMaxVisiblePages) {
      return List<int>.generate(totalPages, (i) => i + 1);
    }

    final pages = <int>{1, totalPages, _currentPage};
    for (var offset = 1; offset <= 2; offset++) {
      if (_currentPage - offset > 1) pages.add(_currentPage - offset);
      if (_currentPage + offset < totalPages) pages.add(_currentPage + offset);
    }

    final sorted = pages.toList()..sort();

    final out = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) out.add(-1);
      out.add(sorted[i]);
    }
    return out;
  }

  // ─── BOTTOM CARDS ───
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
              onPressed: _isDemo
                  ? _demoBlock
                  : () {
                _showSnack('Compliance report coming soon.');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: onOrange,
                foregroundColor: tc.orange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('View Compliance Report',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ───
  Widget _buildFilterField({required String label, required Widget child}) {
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
    bool showSpinner = false,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: showSpinner
          ? SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: textColor ?? tc.textMuted,
        ),
      )
          : Icon(icon, size: 14, color: textColor ?? tc.textMuted),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }
}