// lib/screens/admin_employees_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

// ─── LEAVE CREDIT POLICY (TUGMA SA APP) ────────────────────────
const int kAdminAnnualLeaveTotal = 18;
const int kAdminSickLeaveTotal = 18;

// ══════════════════════════════════════════════════════════════
// CUSTOM SCROLL BEHAVIOR
// ══════════════════════════════════════════════════════════════
class CustomAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

// ══════════════════════════════════════════════════════════════
// MAIN PAGE
// ══════════════════════════════════════════════════════════════
class AdminEmployeesPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final String searchQuery;
  final VoidCallback onRefreshNeeded;
  final VoidCallback? onAddEmployee;

  const AdminEmployeesPage({
    super.key,
    required this.employees,
    required this.searchQuery,
    required this.onRefreshNeeded,
    this.onAddEmployee,
  });

  @override
  State<AdminEmployeesPage> createState() => _AdminEmployeesPageState();
}

class _AdminEmployeesPageState extends State<AdminEmployeesPage> {
  final ScrollController _scrollController = ScrollController();
  AdminColors get tc => AdminTheme.getColors(context);

  // ─── EDIT CONTROLLERS ─────────────────────────────────────────
  final _editFirstCtrl = TextEditingController();
  final _editLastCtrl = TextEditingController();
  final _editFullNameCtrl = TextEditingController();
  final _editRoleCtrl = TextEditingController();
  final _editDeptCtrl = TextEditingController();
  final _editEmailCtrl = TextEditingController();
  final _editPhoneCtrl = TextEditingController();
  final _editPassCtrl = TextEditingController();
  final _editKeyfobCtrl = TextEditingController();
  final _editPinCtrl = TextEditingController();
  final _editBirthdayCtrl = TextEditingController();
  DateTime? _editBirthday;
  String? _editDepartmentDropdown;
  bool _editSaving = false;
  bool _editPassVis = false;
  bool _isEditingEmployee = false;

  static const List<String> _departmentOptions = [
    'Information Tech Department',
    'Human Resources',
    'Finance',
    'Operations',
    'Sales & Marketing',
    'Customer Support',
    'Logistics',
    'Admin',
  ];

  // ─── ADD EMPLOYEE CONTROLLERS ─────────────────────────────────
  final _addFirstCtrl = TextEditingController();
  final _addLastCtrl = TextEditingController();
  final _addEmailCtrl = TextEditingController();
  final _addPhoneCtrl = TextEditingController();
  final _addRoleCtrl = TextEditingController();
  final _addDeptCtrl = TextEditingController();
  final _addPassCtrl = TextEditingController();
  final _addPinCtrl = TextEditingController();
  final _addKeyfobCtrl = TextEditingController();
  bool _addSaving = false;
  bool _addPassVis = false;
  bool _isAddingEmployee = false;

  // ─── FILTERS ──────────────────────────────────────────────────
  final _filterCtrl = TextEditingController();
  String _filterText = '';
  String _department = 'All Departments';
  String _sort = 'A-Z';
  int _page = 0;
  static const int _pageSize = 6;

  Map<String, dynamic>? _selectedProfileEmp;

  @override
  void initState() {
    super.initState();
    final q = widget.searchQuery;
    _filterCtrl.text = q;
    _filterText = q;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _editFirstCtrl.dispose();
    _editLastCtrl.dispose();
    _editFullNameCtrl.dispose();
    _editRoleCtrl.dispose();
    _editDeptCtrl.dispose();
    _editEmailCtrl.dispose();
    _editPhoneCtrl.dispose();
    _editPassCtrl.dispose();
    _editKeyfobCtrl.dispose();
    _editPinCtrl.dispose();
    _editBirthdayCtrl.dispose();
    _addFirstCtrl.dispose();
    _addLastCtrl.dispose();
    _addEmailCtrl.dispose();
    _addPhoneCtrl.dispose();
    _addRoleCtrl.dispose();
    _addDeptCtrl.dispose();
    _addPassCtrl.dispose();
    _addPinCtrl.dispose();
    _addKeyfobCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
  String _s(dynamic v, [String fallback = '—']) {
    if (v == null) return fallback;
    final str = v.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  int _safeInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  bool _match(String text) {
    final needle = _filterText.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return _s(text).toLowerCase().contains(needle);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _nameOf(Map<String, dynamic> e) {
    final name = _s(e['name'], '');
    if (name.isNotEmpty && name != '—') return name;
    final full = '${_s(e['firstName'], '')} ${_s(e['lastName'], '')}'.trim();
    return full.isNotEmpty ? full : 'Unnamed Employee';
  }

  String _initialsOf(String name) {
    if (name.trim().isEmpty) return '?';
    return name
        .trim()
        .split(RegExp(r'\s+'))
        .map((p) => p[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  bool _isPro(Map<String, dynamic> e) {
    final v = e['pro'] ?? e['isPro'];
    if (v is bool) return v;
    return _s(v).toLowerCase() == 'true';
  }

  bool _isActive(Map<String, dynamic> e) {
    final v = _s(e['status'], _s(e['workStatus'], 'Active')).toLowerCase();
    return v == 'active' || v == 'online' || v == 'true';
  }

  // ─── DATE / TIME HELPERS ─────────────────────────────────────
  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(dynamic v, {String fallback = '—'}) {
    final dt = v is DateTime ? v : _toDateTime(v);
    if (dt == null) return fallback;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  String _fmtTime(dynamic v, {String fallback = '—'}) {
    final dt = v is DateTime ? v : _toDateTime(v);
    if (dt == null) return fallback;
    final h24 = dt.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final ap = h24 >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ap';
  }

  String _durationBetween(dynamic inTs, dynamic outTs) {
    final a = _toDateTime(inTs);
    final b = _toDateTime(outTs);
    if (a == null || b == null || b.isBefore(a)) return '—';
    final d = b.difference(a);
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  // ══════════════════════════════════════════════════════════════
  // REAL FIRESTORE STREAMS
  // ══════════════════════════════════════════════════════════════
  Stream<List<Map<String, dynamic>>> _attendanceStream(String empId) {
    return AdminDatabase.fs
        .collection('attendance_logs')
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .where((log) {
        final eid = (log['employee_id'] ??
            log['employeeId'] ??
            log['employeeID'] ??
            '')
            .toString();
        return eid == empId;
      }).toList();

      list.sort((a, b) {
        final da = _logTimestamp(a);
        final db = _logTimestamp(b);
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return 0;
      });
      return list;
    }).handleError((e) {
      debugPrint('attendanceStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  Stream<List<Map<String, dynamic>>> _leaveStream(String empId) {
    return AdminDatabase.fs
        .collection('leave_applications')
        .where('employeeId', isEqualTo: empId)
        .snapshots()
        .map((s) => s.docs
        .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
        .toList())
        .handleError((e) {
      debugPrint('leaveStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  Stream<List<Map<String, dynamic>>> _activityStream(String empId) {
    return AdminDatabase.fs
        .collection('activity logs')
        .where('employeeId', isEqualTo: empId)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList();
      list.sort((a, b) {
        final da = _toDateTime(a['timestamp']);
        final db = _toDateTime(b['timestamp']);
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return 0;
      });
      return list;
    }).handleError((e) {
      debugPrint('activityStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  // ══════════════════════════════════════════════════════════════
  // ATTENDANCE ROW HELPERS — combine IN/OUT per day
  // ══════════════════════════════════════════════════════════════
  DateTime? _logTimestamp(Map<String, dynamic> log) {
    final raw = log['timestamp'] ??
        log['createdAt'] ??
        log['clockIn'] ??
        log['timeIn'] ??
        log['date'];
    return _toDateTime(raw);
  }

  String _logType(Map<String, dynamic> log) {
    return _s(log['type'], _s(log['status'], '')).toUpperCase();
  }

  /// Builds attendance rows per day. Computes actual hours worked.
  List<Map<String, dynamic>> _buildAttendanceRows(
      List<Map<String, dynamic>> logs) {
    final Map<String, List<Map<String, dynamic>>> byDay = {};

    for (final log in logs) {
      final dt = _logTimestamp(log);
      if (dt == null) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(log);
    }

    final rows = <Map<String, dynamic>>[];

    byDay.forEach((key, dayLogs) {
      dayLogs.sort((a, b) {
        final ta = _logTimestamp(a);
        final tb = _logTimestamp(b);
        if (ta == null || tb == null) return 0;
        return ta.compareTo(tb);
      });

      Map<String, dynamic>? inLog;
      Map<String, dynamic>? outLog;
      DateTime? inTs;
      DateTime? outTs;

      // 1. Check if a single document contains both timeIn and timeOut
      for (final log in dayLogs) {
        final rawIn = log['timeIn'] ??
            log['clockIn'] ??
            log['in'] ??
            log['time_in'];
        final rawOut = log['timeOut'] ??
            log['clockOut'] ??
            log['out'] ??
            log['time_out'];
        final parsedIn = _toDateTime(rawIn);
        final parsedOut = _toDateTime(rawOut);
        if (parsedIn != null && parsedOut != null) {
          inTs = parsedIn;
          outTs = parsedOut;
          inLog = log;
          outLog = log;
          break;
        }
      }

      // 2. If not found, look for separate IN/OUT logs
      if (inTs == null || outTs == null) {
        for (final l in dayLogs) {
          final t = _logType(l);
          final ts = _logTimestamp(l);
          if ((t == 'IN' ||
              t == 'LOGIN' ||
              t == 'CLOCK IN' ||
              t == 'TIME IN' ||
              t == 'CLOCK_IN') &&
              inLog == null) {
            inLog = l;
            inTs = ts;
          }
          if ((t == 'OUT' ||
              t == 'LOGOUT' ||
              t == 'CLOCK OUT' ||
              t == 'TIME OUT' ||
              t == 'CLOCK_OUT') &&
              outLog == null) {
            outLog = l;
            outTs = ts;
          }
        }
      }

      // 3. Fallback if no type found
      if (inTs == null && dayLogs.isNotEmpty) {
        inLog = dayLogs.first;
        inTs = _logTimestamp(inLog);
      }
      if (outTs == null && dayLogs.length > 1) {
        outLog = dayLogs.last;
        outTs = _logTimestamp(outLog);
      }

      String total = '—';
      int totalMinutes = 0;

      // Compute actual hours worked
      if (inTs != null && outTs != null) {
        if (outTs.isAfter(inTs) || outTs.isAtSameMomentAs(inTs)) {
          final d = outTs.difference(inTs);
          total = '${d.inHours}h ${d.inMinutes.remainder(60)}m';
          totalMinutes = d.inMinutes;
        }
      }

      String status;
      bool isLate = false;
      if (inTs != null && outTs != null) {
        if (inTs.hour > 9 || (inTs.hour == 9 && inTs.minute > 15)) {
          isLate = true;
          status = 'Late';
        } else {
          status = 'On Time';
        }
      } else if (inTs != null) {
        status = 'Working';
      } else {
        status = 'Present';
      }

      rows.add({
        'date': inTs ?? outTs ?? DateTime.now(),
        'in': inTs,
        'out': outTs,
        'total': total,
        'totalMinutes': totalMinutes,
        'status': status,
        'isLate': isLate,
      });
    });

    rows.sort((a, b) {
      final da = a['date'] as DateTime;
      final db = b['date'] as DateTime;
      return db.compareTo(da);
    });

    return rows;
  }

  // ─── TOTAL MINUTES HELPERS ────────────────────────────────────
  int _computeTotalMinutes(
      List<Map<String, dynamic>> rows, {
        int? filterMonth,
        int? filterYear,
      }) {
    int total = 0;
    for (final row in rows) {
      final inTs = row['in'] as DateTime?;
      final outTs = row['out'] as DateTime?;
      if (inTs == null || outTs == null) continue;
      // Allow equal timestamps (0 duration) but skip invalid out < in
      if (outTs.isBefore(inTs)) continue;

      if (filterMonth != null && inTs.month != filterMonth) continue;
      if (filterYear != null && inTs.year != filterYear) continue;

      total += outTs.difference(inTs).inMinutes;
    }
    return total;
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0h 0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  // ══════════════════════════════════════════════════════════════
  // LEAVE CREDIT COMPUTATION
  // ══════════════════════════════════════════════════════════════
  Map<String, int> _computeLeaveStats(List<Map<String, dynamic>> leaves) {
    int usedAnnual = 0;
    int usedSick = 0;
    int pendingAnnual = 0;
    int pendingSick = 0;
    int usedOther = 0;

    for (final l in leaves) {
      final rawCode = _s(l['leaveType'], _s(l['type'], '')).toUpperCase();
      final days = _safeInt(l['days'], 1);
      final status = _s(l['status'], 'pending').toLowerCase();

      if (status == 'approved') {
        if (rawCode == 'VL') {
          usedAnnual += days;
        } else if (rawCode == 'SL') {
          usedSick += days;
        } else {
          usedOther += days;
        }
      } else if (status == 'pending') {
        if (rawCode == 'VL') {
          pendingAnnual += days;
        } else if (rawCode == 'SL') {
          pendingSick += days;
        }
      }
    }

    return {
      'usedAnnual': usedAnnual,
      'usedSick': usedSick,
      'pendingAnnual': pendingAnnual,
      'pendingSick': pendingSick,
      'usedOther': usedOther,
      'remainingAnnual':
      (kAdminAnnualLeaveTotal - usedAnnual).clamp(0, kAdminAnnualLeaveTotal),
      'remainingSick':
      (kAdminSickLeaveTotal - usedSick).clamp(0, kAdminSickLeaveTotal),
    };
  }

  // ══════════════════════════════════════════════════════════════
  // PDF GENERATION
  // ══════════════════════════════════════════════════════════════
  Future<void> _generateAndDownloadPdf(Map<String, dynamic> emp) async {
    final pdf = pw.Document();
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final id = _s(emp['employeeId'], _s(emp['id'], 'N/A'));
    final joiningDate = _fmtDate(
      emp['joiningDate'] ?? emp['createdAt'] ?? emp['created_at'],
      fallback: 'Not Specified',
    );
    final nfcId = _s(emp['nfcTagId'], _s(emp['nfcId'], 'NOT ASSIGNED'));
    final activeStatus = _s(emp['status'], 'ACTIVE').toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('EMPLOYEE PROFILE REPORT',
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Status: $activeStatus',
                          style: pw.TextStyle(
                              fontSize: 12, color: PdfColors.orange)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text('Basic Information',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [
                  pw.Text('Name: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(name)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Employee ID: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(id)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Role: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(role)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Department: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(dept)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Email: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(email)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Phone: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(phone)
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Joining Date: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(joiningDate)
                ]),
                pw.SizedBox(height: 20),
                pw.Text('Leave Credits',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [
                  pw.Text('Annual Leave: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('$kAdminAnnualLeaveTotal days'),
                ]),
                pw.SizedBox(height: 5),
                pw.Row(children: [
                  pw.Text('Sick Leave: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('$kAdminSickLeaveTotal days'),
                ]),
                pw.SizedBox(height: 20),
                pw.Text('Security Credentials',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(children: [
                  pw.Text('NFC/KEYFOB ID: ',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(nfcId)
                ]),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Profile_${name.replaceAll(' ', '_')}.pdf',
    );
  }

  // ══════════════════════════════════════════════════════════════
  // AVATAR
  // ══════════════════════════════════════════════════════════════
  Widget _avatarContent(Map<String, dynamic> emp, String initial,
      {required double size,
        required double fontSize,
        Color textColor = Colors.white}) {
    final photoUrl = _s(emp['photoUrl'], '').isNotEmpty
        ? _s(emp['photoUrl'], '')
        : _s(emp['photo'], '');

    if (photoUrl.isNotEmpty && photoUrl != '—') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.network(
          photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _avatarFallback(initial, fontSize, textColor),
        ),
      );
    }
    return _avatarFallback(initial, fontSize, textColor);
  }

  Widget _avatarFallback(String initial, double fontSize, Color textColor) =>
      Center(
        child: Text(
          initial,
          style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w700),
        ),
      );

  // ══════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isEditingEmployee && _selectedProfileEmp != null) {
      return _buildEditEmployeePage(_selectedProfileEmp!);
    }
    if (_isAddingEmployee) {
      return _buildAddEmployeePage();
    }
    if (_selectedProfileEmp != null) {
      return _buildEmployeeProfilePage(_selectedProfileEmp!);
    }

    final departments = <String>{
      'All Departments',
      ...widget.employees
          .map((e) => _s(e['department'], ''))
          .where((d) => d.isNotEmpty && d != '—'),
    }.toList();

    var filtered = widget.employees.where((e) {
      final hay =
          '${_nameOf(e)} ${_s(e['role'])} ${_s(e['id'])} ${_s(e['department'])}';
      final matchesText = _match(hay);
      final matchesDept = _department == 'All Departments' ||
          _s(e['department']) == _department;
      return matchesText && matchesDept;
    }).toList();

    filtered.sort((a, b) {
      final cmp = _nameOf(a).toLowerCase().compareTo(_nameOf(b).toLowerCase());
      return _sort == 'A-Z' ? cmp : -cmp;
    });

    final total = filtered.length;
    final totalPages = total == 0 ? 1 : (total / _pageSize).ceil();
    if (_page >= totalPages) _page = totalPages - 1;
    if (_page < 0) _page = 0;
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, total);
    final pageItems =
    total == 0 ? <Map<String, dynamic>>[] : filtered.sublist(start, end);

    return Container(
      color: tc.background,
      child: ScrollConfiguration(
        behavior: CustomAppScrollBehavior(),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(8),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _header(),
                      const SizedBox(height: 20),
                      _filterBar(departments),
                      const SizedBox(height: 20),
                      if (pageItems.isEmpty)
                        _emptyState()
                      else
                        _directoryGrid(pageItems),
                      const SizedBox(height: 16),
                      if (total > 0)
                        _pagination(start, end, total, totalPages),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _header() {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final narrow = !r.up(BsSize.sm);

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee Directory',
              style: TextStyle(
                  fontSize:
                  r.responsive<double>(xs: 24, sm: 26, md: 28, lg: 32),
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                  letterSpacing: -0.3),
            ),
            const SizedBox(height: 6),
            Text(
              'Manage and monitor ${widget.employees.length} active workforce members.',
              style: TextStyle(color: tc.muted, fontSize: 15),
            ),
          ],
        );

        final button = ElevatedButton.icon(
          onPressed: () {
            if (widget.onAddEmployee != null) {
              widget.onAddEmployee!();
            } else {
              setState(() => _isAddingEmployee = true);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Add New Employee',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        );

        final wipeButton = OutlinedButton.icon(
          onPressed: () => _confirmWipeAllLogs(),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: tc.red,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            side: BorderSide(color: tc.red.withValues(alpha: 0.3)),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
          label: const Text('Clear All Logs',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 14),
              wipeButton,
              const SizedBox(height: 10),
              button,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            wipeButton,
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FILTER BAR
  // ══════════════════════════════════════════════════════════════
  Widget _filterBar(List<String> departments) {
    return LayoutBuilder(
      builder: (_, c) {
        final r = BsResponsive(c.maxWidth);
        final narrow = !r.up(BsSize.md);

        final search = Container(
          height: 46,
          decoration: BoxDecoration(
            color: tc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 18, color: tc.muted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _filterCtrl,
                onChanged: (v) => setState(() {
                  _filterText = v;
                  _page = 0;
                }),
                style: TextStyle(color: tc.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Filter by name, role, or ID...',
                  hintStyle: TextStyle(color: tc.muted, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ]),
        );

        final deptDropdown = _pillDropdown(
          value: _department,
          items: departments,
          onChanged: (v) => setState(() {
            _department = v ?? 'All Departments';
            _page = 0;
          }),
        );

        final sortDropdown = _pillDropdown(
          value: _sort,
          items: const ['A-Z', 'Z-A'],
          prefix: 'Sort: ',
          onChanged: (v) => setState(() => _sort = v ?? 'A-Z'),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: deptDropdown),
                const SizedBox(width: 10),
                Expanded(child: sortDropdown),
              ]),
            ],
          );
        }
        return Row(children: [
          Expanded(flex: 2, child: search),
          const SizedBox(width: 12),
          Expanded(child: deptDropdown),
          const SizedBox(width: 12),
          Expanded(child: sortDropdown),
        ]);
      },
    );
  }

  Widget _pillDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String prefix = '',
  }) {
    final safeValue =
    items.contains(value) ? value : (items.isNotEmpty ? items.first : null);

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: tc.card,
          focusColor: Colors.transparent,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: tc.muted, size: 20),
          style: TextStyle(
              color: tc.text, fontSize: 14, fontWeight: FontWeight.w500),
          items: items.map((d) {
            return DropdownMenuItem<String>(
              value: d,
              child: Text(
                '$prefix$d',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tc.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DIRECTORY GRID
  // ══════════════════════════════════════════════════════════════
  Widget _directoryGrid(List<Map<String, dynamic>> items) {
    return LayoutBuilder(
      builder: (_, c) {
        final width = c.maxWidth;
        final r = BsResponsive(width);
        final cols = r.responsive<int>(
          xs: 1,
          sm: 1,
          md: 2,
          lg: 3,
          xl: 3,
          xxl: 3,
        );
        const gap = 20.0;
        final colWidth = (width - (cols - 1) * gap) / cols;

        final widgets = <Widget>[];

        if (items.isNotEmpty) {
          final featuredWidth = cols >= 3
              ? colWidth * 2 + gap
              : (cols == 2 ? colWidth * 2 + gap : colWidth);
          widgets.add(SizedBox(
            width: featuredWidth,
            height: 340,
            child: _featuredEmployeeCard(items[0]),
          ));

          for (int i = 1; i < items.length; i++) {
            widgets.add(SizedBox(
              width: colWidth,
              height: 340,
              child: _regularEmployeeCard(items[i]),
            ));
          }
        }

        widgets.add(SizedBox(
          width: colWidth,
          height: 340,
          child: _quickInviteCard(),
        ));

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: widgets,
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FEATURED EMPLOYEE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _featuredEmployeeCard(Map<String, dynamic> emp) {
    final name = _nameOf(emp);
    final initials = _initialsOf(name);
    final role = _s(emp['role'], 'Staff Member');
    final dept = _s(emp['department'], 'General');
    final id = _s(emp['employeeId'], _s(emp['id'], 'N/A'));
    final isPro = _isPro(emp);
    final isActive = _isActive(emp);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 128,
                height: 128,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: tc.orange, width: 2),
                ),
                child: _avatarContent(emp, initials,
                    size: 128, fontSize: 40, textColor: tc.orangeText),
              ),
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF006E05)
                        : const Color(0xFF857365),
                    shape: BoxShape.circle,
                    border: Border.all(color: tc.card, width: 4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: tc.orange.withValues(alpha: 0.20)),
                        ),
                        child: Text('PRO',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: tc.orange,
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: TextStyle(color: tc.muted, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('DEPARTMENT',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: tc.muted,
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 6),
                          Text(dept,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EMPLOYEE ID',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: tc.muted,
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 6),
                          Text(id,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _featuredActionButton(
                icon: Icons.mail_outline_rounded,
                onTap: () {
                  final email = _s(emp['email'], 'No email registered');
                  _snack('Email: $email');
                },
                tooltip: 'Send Email',
              ),
              const SizedBox(height: 8),
              _featuredActionButton(
                icon: Icons.phone_outlined,
                onTap: () {
                  final phone =
                  _s(emp['phone'], _s(emp['mobile'], 'No phone registered'));
                  _snack('Contact number: $phone');
                },
                tooltip: 'Call',
              ),
              const SizedBox(height: 8),
              PopupMenuButton<String>(
                color: tc.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                icon: Icon(Icons.more_vert_rounded, color: tc.text, size: 20),
                onSelected: (v) {
                  if (v == 'profile') {
                    setState(() => _selectedProfileEmp = emp);
                  } else if (v == 'edit') {
                    _openEditDialog(emp);
                  } else if (v == 'delete') {
                    _confirmDelete(_s(emp['id']), name);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [
                      Icon(Icons.person_outline_rounded,
                          size: 16, color: tc.text),
                      const SizedBox(width: 8),
                      Text('View Profile',
                          style: TextStyle(color: tc.text, fontSize: 13)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16, color: tc.orange),
                      const SizedBox(width: 8),
                      Text('Edit Details',
                          style: TextStyle(color: tc.text, fontSize: 13)),
                    ]),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 16, color: tc.red),
                      const SizedBox(width: 8),
                      Text('Terminate',
                          style: TextStyle(color: tc.red, fontSize: 13)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _featuredActionButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.border),
            ),
            child: Icon(icon, size: 18, color: tc.text),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // REGULAR EMPLOYEE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _regularEmployeeCard(Map<String, dynamic> emp) {
    final name = _nameOf(emp);
    final initials = _initialsOf(name);
    final role = _s(emp['role'], 'Staff Member');
    final dept = _s(emp['department'], 'General');
    final email = _s(emp['email'], '—');
    final isActive = _isActive(emp);

    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tc.border),
                ),
                child: _avatarContent(emp, initials,
                    size: 64, fontSize: 22, textColor: tc.orangeText),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF006E05)
                          : const Color(0xFF857365),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isActive ? 'Active' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive
                          ? const Color(0xFF006E05)
                          : const Color(0xFF564334),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(name,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tc.text),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          const SizedBox(height: 2),
          Text(role,
              style: TextStyle(color: tc.muted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
          const SizedBox(height: 14),
          Divider(height: 1, color: tc.border),
          const SizedBox(height: 12),
          _infoRow(icon: Icons.business_outlined, text: dept),
          const SizedBox(height: 8),
          _infoRow(icon: Icons.email_outlined, text: email),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: InkWell(
              onTap: () => setState(() => _selectedProfileEmp = emp),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: tc.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tc.border),
                ),
                child: Text('View Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tc.text)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: tc.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(color: tc.text, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // QUICK INVITE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _quickInviteCard() {
    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: tc.border,
          radius: 12,
          dashWidth: 6,
          dashSpace: 4,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: tc.orange, size: 28),
                ),
                const SizedBox(height: 16),
                Text('Quick Invite',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tc.text)),
                const SizedBox(height: 6),
                Text(
                  'Send joining link to new staff\nmembers via email.',
                  textAlign: TextAlign.center,
                  style:
                  TextStyle(fontSize: 13, color: tc.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGINATION
  // ══════════════════════════════════════════════════════════════
  Widget _pagination(int start, int end, int total, int totalPages) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final info = Text('Showing ${start + 1} to $end of $total employees',
          style: TextStyle(color: tc.muted, fontSize: 13));

      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pageArrow(Icons.chevron_left_rounded, _page > 0,
                  () => setState(() => _page--)),
          const SizedBox(width: 6),
          ...List.generate(totalPages, (i) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _pageNumber(i),
          )),
          _pageArrow(Icons.chevron_right_rounded, _page < totalPages - 1,
                  () => setState(() => _page++)),
        ],
      );

      return Container(
        padding: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tc.border))),
        child: narrow
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            info,
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: controls,
            ),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [info, controls],
        ),
      );
    });
  }

  Widget _pageArrow(IconData icon, bool enabled, VoidCallback onTap) =>
      InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tc.border)),
          child: Icon(icon, size: 16, color: enabled ? tc.text : tc.muted),
        ),
      );

  Widget _pageNumber(int i) {
    final sel = i == _page;
    return InkWell(
      onTap: () => setState(() => _page = i),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: sel ? tc.orange : tc.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: sel ? tc.orange : tc.border)),
        child: Text('${i + 1}',
            style: TextStyle(
                color: sel ? Colors.white : tc.text,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ADD EMPLOYEE PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildAddEmployeePage() {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _isAddingEmployee = false),
                  icon: Icon(Icons.arrow_back_rounded, color: tc.muted),
                  label: Text('Back to Directory',
                      style: TextStyle(
                          color: tc.muted, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                Text('Add New Employee',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: tc.text)),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, constraints) {
                  final stack =
                  !BsResponsive(constraints.maxWidth).up(BsSize.lg);
                  final photoCard = _photoUploadCard();
                  final formColumn = Column(
                    children: [
                      _buildAddPersonalInfoCard(),
                      const SizedBox(height: 24),
                      _buildAddBiometricCard(),
                      const SizedBox(height: 24),
                      _buildAddActions(),
                    ],
                  );
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photoCard,
                        const SizedBox(height: 24),
                        formColumn,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: photoCard),
                      const SizedBox(width: 24),
                      Expanded(child: formColumn),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoUploadCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tc.surface,
              border: Border.all(color: tc.border),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline_rounded, size: 64, color: tc.muted),
                  const SizedBox(height: 12),
                  Text('Upload Photo',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tc.muted)),
                  const SizedBox(height: 4),
                  Text('JPG, PNG — max 2MB',
                      style: TextStyle(fontSize: 11, color: tc.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Profile Identity',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: tc.text)),
          const SizedBox(height: 8),
          Text(
            'This photo will be used for digital identification across the portal.',
            style: TextStyle(fontSize: 13, color: tc.muted, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildAddPersonalInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.person_outline, color: tc.orange, size: 20),
            const SizedBox(width: 8),
            Text('Personal Information',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: tc.text)),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            if (narrow) {
              return Column(
                children: [
                  _buildInputField('First Name', _addFirstCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('Last Name', _addLastCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('Email Address', _addEmailCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('Phone No.', _addPhoneCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('Role / Designation', _addRoleCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('Department', _addDeptCtrl),
                  const SizedBox(height: 16),
                  _buildPasswordField('Account Password', _addPassCtrl,
                      _addPassVis, () {
                        setState(() => _addPassVis = !_addPassVis);
                      }),
                ],
              );
            }
            return Column(
              children: [
                Row(children: [
                  Expanded(child: _buildInputField('First Name', _addFirstCtrl)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildInputField('Last Name', _addLastCtrl)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _buildInputField('Email Address', _addEmailCtrl)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildInputField('Phone No.', _addPhoneCtrl)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: _buildInputField(
                          'Role / Designation', _addRoleCtrl)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildInputField('Department', _addDeptCtrl)),
                ]),
                const SizedBox(height: 16),
                _buildPasswordField('Account Password', _addPassCtrl,
                    _addPassVis, () {
                      setState(() => _addPassVis = !_addPassVis);
                    }),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAddBiometricCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.fingerprint, color: tc.orange, size: 20),
            const SizedBox(width: 8),
            Text('Biometric Credentials',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: tc.text)),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 500;
            if (narrow) {
              return Column(
                children: [
                  _buildInputField('Keyfob Serial (NFC)', _addKeyfobCtrl),
                  const SizedBox(height: 16),
                  _buildInputField('4-Digit PIN', _addPinCtrl),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                    child:
                    _buildInputField('Keyfob Serial (NFC)', _addKeyfobCtrl)),
                const SizedBox(width: 16),
                Expanded(
                    child: _buildInputField('4-Digit PIN', _addPinCtrl)),
              ],
            );
          }),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tc.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tc.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: tc.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kung iiwan na blangko, awtomatikong bubuo ng keyfob serial at default PIN na "1234".',
                    style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddActions() {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 500;
      final cancel = OutlinedButton(
        onPressed: () => setState(() => _isAddingEmployee = false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: tc.border),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text('Cancel', style: TextStyle(color: tc.text)),
      );
      final done = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _addSaving
            ? null
            : () async {
          final firstName = _addFirstCtrl.text.trim();
          final lastName = _addLastCtrl.text.trim();
          final email = _addEmailCtrl.text.trim();

          if (firstName.isEmpty || lastName.isEmpty || email.isEmpty) {
            _snack('First name, last name, and email are required.',
                error: true);
            return;
          }

          final pinText = _addPinCtrl.text.trim();
          if (pinText.isNotEmpty && pinText.length != 4) {
            _snack('PIN must be exactly 4 digits.', error: true);
            return;
          }

          final keyfob = _addKeyfobCtrl.text.trim().isNotEmpty
              ? _addKeyfobCtrl.text.trim().toUpperCase()
              : 'NFC-${DateTime.now().millisecondsSinceEpoch.toString().substring(5, 13)}';
          final pin = pinText.isNotEmpty ? pinText : '1234';

          setState(() => _addSaving = true);
          try {
            final err = await AdminDatabase.addEmployee(
              firstName: firstName,
              lastName: lastName,
              email: email,
              password: _addPassCtrl.text.trim(),
              role: _addRoleCtrl.text.trim(),
              department: _addDeptCtrl.text.trim(),
              nfcTagId: keyfob,
              pin: pin,
            );

            if (!mounted) return;
            if (err != null) {
              _snack('Failed to add employee: $err', error: true);
            } else {
              if (_addPhoneCtrl.text.trim().isNotEmpty) {
                try {
                  final snap = await AdminDatabase.employees
                      .where('email', isEqualTo: email)
                      .limit(1)
                      .get();
                  if (snap.docs.isNotEmpty) {
                    await snap.docs.first.reference.update({
                      'phone': _addPhoneCtrl.text.trim(),
                    });
                  }
                } catch (e) {
                  debugPrint('Phone save warning: $e');
                }
              }

              _snack('Employee successfully added!');
              _addFirstCtrl.clear();
              _addLastCtrl.clear();
              _addEmailCtrl.clear();
              _addPhoneCtrl.clear();
              _addRoleCtrl.clear();
              _addDeptCtrl.clear();
              _addPassCtrl.clear();
              _addPinCtrl.clear();
              _addKeyfobCtrl.clear();
              setState(() => _isAddingEmployee = false);
              widget.onRefreshNeeded();
            }
          } catch (e) {
            if (!mounted) return;
            _snack('Failed to add employee: $e', error: true);
          } finally {
            if (mounted) setState(() => _addSaving = false);
          }
        },
        child: _addSaving
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2))
            : const Text('Done',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            done,
            const SizedBox(height: 12),
            cancel,
          ],
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          cancel,
          const SizedBox(width: 16),
          done,
        ],
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // INPUT FIELD WIDGETS
  // ══════════════════════════════════════════════════════════════
  Widget _buildInputField(String label, TextEditingController controller,
      {bool readOnly = false}) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      style: TextStyle(
        fontSize: 14,
        color: tc.text,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: tc.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: readOnly ? tc.surface : tc.card,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller,
      bool obscure, VoidCallback onToggle) {
    return TextField(
      controller: controller,
      obscureText: !obscure,
      style: TextStyle(
        fontSize: 14,
        color: tc.text,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: tc.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: tc.card,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.5),
        ),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off,
              color: tc.muted),
          onPressed: onToggle,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EDIT EMPLOYEE PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildEditEmployeePage(Map<String, dynamic> emp) {
    final photoUrl = _s(emp['photoUrl'], '').isNotEmpty
        ? _s(emp['photoUrl'], '')
        : _s(emp['photo'], '');
    final empId = _s(emp['employeeId'], _s(emp['id'], 'EMP-2024-024'));

    final fullName =
    '${_s(emp['firstName'], '')} ${_s(emp['lastName'], '')}'.trim();
    _editFullNameCtrl.text = fullName.isEmpty ? _nameOf(emp) : fullName;
    _editEmailCtrl.text = _s(emp['email'], '');
    _editPhoneCtrl.text = _s(emp['phone'], _s(emp['mobile'], ''));
    _editRoleCtrl.text = _s(emp['role'], '');
    _editDeptCtrl.text = _s(emp['department'], '');
    _editKeyfobCtrl.text = _s(emp['nfcTagId'], _s(emp['nfcId'], ''));
    _editPinCtrl.text = _s(emp['pin'], '');

    final bd = _toDateTime(emp['birthday'] ?? emp['birthDate']);
    _editBirthday = bd;
    _editBirthdayCtrl.text = bd == null ? '' : _fmtDate(bd, fallback: '');

    _editDepartmentDropdown = _departmentOptions.contains(_editDeptCtrl.text)
        ? _editDeptCtrl.text
        : null;

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isEditingEmployee = false),
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    'Add New Employee',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF8C00),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Edit Employee',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: tc.text,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, constraints) {
                  final stack =
                  !BsResponsive(constraints.maxWidth).up(BsSize.lg);
                  final photoCard = _editPhotoCard(photoUrl);
                  final formColumn = Column(
                    children: [
                      _buildEditPersonalInfoCard(empId),
                      const SizedBox(height: 16),
                      _buildEditBiometricCard(),
                      const SizedBox(height: 16),
                      _buildEditActions(emp),
                    ],
                  );
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photoCard,
                        const SizedBox(height: 16),
                        formColumn,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 312, child: photoCard),
                      const SizedBox(width: 16),
                      Expanded(child: formColumn),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _editPhotoCard(String photoUrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFEFF4FF),
              border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: photoUrl.isNotEmpty && photoUrl != '—'
                  ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.person, size: 80, color: tc.muted),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 64, color: tc.muted),
                  const SizedBox(height: 8),
                  Text('Upload Photo',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: tc.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Profile Identity',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This photo will be used for digital identification across the portal.',
            style: TextStyle(
              fontSize: 14,
              color: tc.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline_rounded,
                      size: 18, color: Color(0xFFFF8C00)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Ensure the employee's name matches their government-issued ID for biometric verification compliance.",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6E3900),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditPersonalInfoCard(String empId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.person_outline_rounded,
                color: Color(0xFFFF8C00), size: 22),
            const SizedBox(width: 8),
            Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            if (narrow) {
              return Column(
                children: [
                  _editField('FULL NAME', _editFullNameCtrl),
                  const SizedBox(height: 14),
                  _editField('EMAIL ADDRESS', _editEmailCtrl),
                  const SizedBox(height: 14),
                  _editBirthdayField(),
                  const SizedBox(height: 14),
                  _editField('PHONE NO.', _editPhoneCtrl),
                  const SizedBox(height: 14),
                  _editDepartmentDropdownField(),
                  const SizedBox(height: 14),
                  _editField('ROLE / DESIGNATION', _editRoleCtrl),
                  const SizedBox(height: 14),
                  _editField('EMPLOYEE ID',
                      TextEditingController(text: empId),
                      readOnly: true,
                      muted: true),
                ],
              );
            }
            return Column(
              children: [
                Row(children: [
                  Expanded(
                      child: _editField('FULL NAME', _editFullNameCtrl)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _editField('EMAIL ADDRESS', _editEmailCtrl)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _editBirthdayField()),
                  const SizedBox(width: 16),
                  Expanded(child: _editField('PHONE NO.', _editPhoneCtrl)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _editDepartmentDropdownField()),
                  const SizedBox(width: 16),
                  Expanded(
                      child:
                      _editField('ROLE / DESIGNATION', _editRoleCtrl)),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _editField(
                      'EMPLOYEE ID',
                      TextEditingController(text: empId),
                      readOnly: true,
                      muted: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Container()),
                ]),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _editField(
      String label,
      TextEditingController controller, {
        bool readOnly = false,
        bool muted = false,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.text,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: readOnly ? tc.surface : tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            style: TextStyle(
              fontSize: 15,
              color: muted ? tc.muted : tc.text,
              fontWeight: FontWeight.w500,
            ),
            cursorColor: tc.orange,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
              EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _editBirthdayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BIRTHDAY',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.text,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final pick = await showDatePicker(
              context: context,
              initialDate: _editBirthday ?? DateTime(now.year - 25),
              firstDate: DateTime(1950),
              lastDate: now,
              builder: (ctx, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: tc.orange,
                    surface: tc.card,
                  ),
                ),
                child: child!,
              ),
            );
            if (pick != null) {
              setState(() {
                _editBirthday = pick;
                _editBirthdayCtrl.text = _fmtDate(pick, fallback: '');
              });
            }
          },
          child: Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
            ),
            child: Text(
              _editBirthdayCtrl.text.isEmpty
                  ? 'Select birthday'
                  : _editBirthdayCtrl.text,
              style: TextStyle(
                fontSize: 15,
                color: _editBirthdayCtrl.text.isEmpty ? tc.muted : tc.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _editDepartmentDropdownField() {
    final current = _editDeptCtrl.text.trim();
    final options = <String>{..._departmentOptions};
    if (current.isNotEmpty && !options.contains(current)) {
      options.add(current);
    }
    final itemsList = options.toList();
    final value = _editDepartmentDropdown != null &&
        itemsList.contains(_editDepartmentDropdown)
        ? _editDepartmentDropdown
        : (itemsList.contains(current) ? current : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEPARTMENT',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.text,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              hint: Text(
                'Select department',
                style: TextStyle(
                  fontSize: 15,
                  color: tc.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: tc.text, size: 22),
              dropdownColor: tc.card,
              style: TextStyle(
                fontSize: 15,
                color: tc.text,
                fontWeight: FontWeight.w500,
              ),
              items: itemsList
                  .map((d) => DropdownMenuItem<String>(
                value: d,
                child: Text(d, overflow: TextOverflow.ellipsis),
              ))
                  .toList(),
              onChanged: (v) => setState(() {
                _editDepartmentDropdown = v;
                _editDeptCtrl.text = v ?? '';
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditBiometricCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.fingerprint,
                color: Color(0xFFFF8C00), size: 22),
            const SizedBox(width: 8),
            Text(
              'Biometric Credentials',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            if (narrow) {
              return Column(
                children: [
                  _keyfobField(),
                  const SizedBox(height: 14),
                  _editField('4-DIGIT PIN', _editPinCtrl),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _keyfobField()),
                const SizedBox(width: 16),
                Expanded(child: _editField('4-DIGIT PIN', _editPinCtrl)),
              ],
            );
          }),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _biometricChip(
                icon: Icons.check_circle_rounded,
                label: 'NFC Ready',
              ),
              _biometricChip(
                icon: Icons.check_circle_rounded,
                label: 'Pin-pad Enabled',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyfobField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KEYFOB SERIAL',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.text,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDC1AE), width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _editKeyfobCtrl,
                  style: TextStyle(
                    fontSize: 15,
                    color: tc.text,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: tc.orange,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'SN: 0000-XXX-00',
                    hintStyle: TextStyle(
                        fontSize: 15,
                        color: Color(0xFFB0B0B0),
                        fontWeight: FontWeight.w400),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.wifi_tethering_rounded,
                    size: 18, color: tc.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _biometricChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFDCE9FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: const Color(0xFFDDC1AE).withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 14, color: Color(0xFFFF8C00)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF564334),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditActions(Map<String, dynamic> emp) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 500;
      final cancel = OutlinedButton(
        onPressed: () => setState(() => _isEditingEmployee = false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: Color(0xFF897362)),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: const Color(0xFF564334),
        ),
        child: const Text('Cancel',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );
      final done = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8C00),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _editSaving
            ? null
            : () async {
          setState(() => _editSaving = true);

          final fullName = _editFullNameCtrl.text.trim();
          final parts = fullName.split(RegExp(r'\s+'));
          final firstName = parts.isNotEmpty ? parts.first : '';
          final lastName =
          parts.length > 1 ? parts.sublist(1).join(' ') : '';

          final data = <String, dynamic>{
            'firstName': firstName,
            'lastName': lastName,
            'name': fullName,
            'email': _editEmailCtrl.text.trim(),
            'phone': _editPhoneCtrl.text.trim(),
            'role': _editRoleCtrl.text.trim(),
            'department': _editDeptCtrl.text.trim(),
            'nfcTagId': _editKeyfobCtrl.text.trim().toUpperCase(),
            'pin': _editPinCtrl.text.trim(),
            if (_editBirthday != null)
              'birthday': Timestamp.fromDate(_editBirthday!),
          };

          final err =
          await AdminDatabase.updateEmployee(_s(emp['id']), data);
          if (!mounted) return;
          setState(() => _editSaving = false);
          if (err != null) {
            _snack('Update failed: $err', error: true);
          } else {
            _snack('Employee profile updated!');
            setState(() {
              _isEditingEmployee = false;
              _selectedProfileEmp = {...emp, ...data};
            });
            widget.onRefreshNeeded();
          }
        },
        child: _editSaving
            ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2))
            : const Text('Done',
            style:
            TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            done,
            const SizedBox(height: 12),
            cancel,
          ],
        );
      }
      return Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFDDC1AE), width: 1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            cancel,
            const SizedBox(width: 12),
            done,
          ],
        ),
      );
    });
  }

  Widget _buildChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tc.muted)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE PROFILE PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildEmployeeProfilePage(Map<String, dynamic> emp) {
    final docId = _s(emp['id'], '');
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final empCode = _s(emp['employeeId'], docId);
    final joiningDate = _fmtDate(
      emp['joiningDate'] ?? emp['createdAt'] ?? emp['created_at'],
      fallback: 'Not Specified',
    );
    final statusRaw = _s(emp['status'], 'active').toLowerCase();
    final activeStatus = statusRaw.toUpperCase();
    final nfcId = _s(emp['nfcTagId'], _s(emp['nfcId'], 'NOT ASSIGNED'));
    final pin = _s(emp['pin'], '');
    final hasBiometric = emp['biometric'] == true ||
        _s(emp['faceId'], '').isNotEmpty ||
        _s(emp['thumbId'], '').isNotEmpty;

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _selectedProfileEmp = null),
                  icon: Icon(Icons.arrow_back_rounded, color: tc.muted),
                  label: Text('Back to Directory',
                      style: TextStyle(
                          color: tc.muted, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                Text('Employee Profile',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: tc.text,
                        letterSpacing: -0.5)),
                const SizedBox(height: 24),
                _profileTopSection(
                  name: name,
                  role: role,
                  dept: dept,
                  email: email,
                  phone: phone,
                  id: empCode,
                  joiningDate: joiningDate,
                  activeStatus: activeStatus,
                  isActive:
                  activeStatus == 'ACTIVE' || activeStatus == 'ONLINE',
                  nfcId: nfcId,
                  pin: pin,
                  hasBiometric: hasBiometric,
                  emp: emp,
                ),
                const SizedBox(height: 24),
                _attendanceAndLeaveSection(docId),
                const SizedBox(height: 24),
                _devicesAndLoginSection(docId, emp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileTopSection({
    required String name,
    required String role,
    required String dept,
    required String email,
    required String phone,
    required String id,
    required String joiningDate,
    required String activeStatus,
    required bool isActive,
    required String nfcId,
    required String pin,
    required bool hasBiometric,
    required Map<String, dynamic> emp,
  }) {
    return LayoutBuilder(builder: (context, constraints) {
      final stack = !BsResponsive(constraints.maxWidth).up(BsSize.lg);
      final left = _mainProfileCard(
        name: name,
        role: role,
        dept: dept,
        email: email,
        phone: phone,
        id: id,
        joiningDate: joiningDate,
        activeStatus: activeStatus,
        isActive: isActive,
        emp: emp,
      );
      final right = _securityCredentialsCard(
        nfcId: nfcId,
        pin: pin,
        hasBiometric: hasBiometric,
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: 20),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: left),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: right),
        ],
      );
    });
  }

  Widget _mainProfileCard({
    required String name,
    required String role,
    required String dept,
    required String email,
    required String phone,
    required String id,
    required String joiningDate,
    required String activeStatus,
    required bool isActive,
    required Map<String, dynamic> emp,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFFFDCC3)
                    : const Color(0xFFE0E3E6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                activeStatus,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? const Color(0xFF6E3900)
                      : const Color(0xFF44474A),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            Text('ID: $id',
                style: TextStyle(fontSize: 14, color: tc.muted)),
          ]),
          const SizedBox(height: 16),
          Text(name,
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(role,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF904D00))),
          const SizedBox(height: 32),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 500;
            final items = [
              _profileIconDetail(
                  icon: Icons.apartment_rounded,
                  label: 'Department',
                  value: dept),
              _profileIconDetail(
                  icon: Icons.mail_outline_rounded,
                  label: 'Work Email',
                  value: email),
              _profileIconDetail(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: phone),
              _profileIconDetail(
                  icon: Icons.calendar_today_outlined,
                  label: 'Joining Date',
                  value: joiningDate),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    items[i],
                    if (i < items.length - 1) const SizedBox(height: 20),
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: items[0]),
                  const SizedBox(width: 24),
                  Expanded(child: items[1]),
                ]),
                const SizedBox(height: 20),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: items[2]),
                  const SizedBox(width: 24),
                  Expanded(child: items[3]),
                ]),
              ],
            );
          }),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: () => _openEditDialog(emp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.orange,
                  foregroundColor: Colors.white,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Details',
                    style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              OutlinedButton(
                onPressed: () => _generateAndDownloadPdf(emp),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tc.text,
                  backgroundColor: tc.card,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  side: BorderSide(color: tc.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Download Profile',
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileIconDetail({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFDCE9FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF904D00)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: tc.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _securityCredentialsCard({
    required String nfcId,
    required String pin,
    required bool hasBiometric,
  }) {
    final nfcAssigned = nfcId.isNotEmpty && nfcId != 'NOT ASSIGNED';
    final pinMasked = pin.isEmpty
        ? 'NOT SET'
        : '${'•' * pin.length}  (${pin.length} digits)';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.security_rounded, size: 22, color: tc.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Security Credentials',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: tc.text)),
            ),
          ]),
          const SizedBox(height: 20),
          _credBox(
            label: 'NFC / KEYFOB ID',
            value: nfcId,
            verified: nfcAssigned,
            verifiedText: nfcAssigned ? 'Assigned' : 'Not assigned',
          ),
          const SizedBox(height: 12),
          _credBox(
            label: 'ACCESS PIN',
            value: pinMasked,
            verified: pin.isNotEmpty,
            verifiedText: pin.isNotEmpty ? 'PIN configured' : 'No PIN set',
            mono: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BIOMETRIC STATUS',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tc.muted,
                        letterSpacing: 0.5)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: _biometricItem(
                      icon: Icons.face,
                      label: 'Face',
                      enabled: hasBiometric,
                    ),
                  ),
                  Expanded(
                    child: _biometricItem(
                      icon: Icons.fingerprint,
                      label: 'Thumb',
                      enabled: hasBiometric,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credBox({
    required String label,
    required String value,
    required bool verified,
    required String verifiedText,
    bool mono = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tc.muted,
                      letterSpacing: 0.5)),
            ),
            Icon(Icons.info_outline, size: 14, color: tc.muted),
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: mono ? 18 : 22,
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: mono ? 0.5 : 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.error_outline,
              size: 14,
              color: verified ? tc.orange : tc.red,
            ),
            const SizedBox(width: 6),
            Text(
              verifiedText,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: verified ? tc.orangeText : tc.red),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _biometricItem({
    required IconData icon,
    required String label,
    required bool enabled,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          size: 26,
          color: enabled ? const Color(0xFF904D00) : tc.muted,
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: enabled ? tc.text : tc.muted)),
        const SizedBox(height: 2),
        Text(enabled ? 'Enrolled' : 'Not Enrolled',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: enabled ? tc.orangeText : tc.muted)),
      ],
    );
  }

  // ─── ATTENDANCE + LEAVE ───────────────────────────────────────
  Widget _attendanceAndLeaveSection(String empId) {
    return LayoutBuilder(builder: (context, constraints) {
      final stack = !BsResponsive(constraints.maxWidth).up(BsSize.lg);
      final left = _recentAttendanceCard(empId);
      final right = _leaveBalanceCard(empId);
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: 20),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: left),
          const SizedBox(width: 20),
          Expanded(flex: 4, child: right),
        ],
      );
    });
  }

  // ✅ RECENT ATTENDANCE — may TOTAL HOURS WORKED summary
  Widget _recentAttendanceCard(String empId) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Recent Attendance',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: tc.text)),
            ),
            Text('Live data',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tc.muted)),
          ]),
          const SizedBox(height: 16),

          // TOTAL HOURS WORKED SUMMARY
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _attendanceStream(empId),
            builder: (context, snapshot) {
              final logs = snapshot.data ?? const [];
              final rows = _buildAttendanceRows(logs);

              final totalMinutes = _computeTotalMinutes(rows);
              final thisMonthMinutes = _computeTotalMinutes(rows,
                  filterMonth: DateTime.now().month,
                  filterYear: DateTime.now().year);
              final daysWorked = rows.length;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tc.orange.withValues(alpha: 0.12),
                      tc.orange.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border:
                  Border.all(color: tc.orange.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Expanded(
                    child: _hourStat(
                      icon: Icons.access_time_rounded,
                      label: 'Total Hours Worked',
                      value: _formatMinutes(totalMinutes),
                      color: tc.orange,
                    ),
                  ),
                  Container(width: 1, height: 40, color: tc.border),
                  Expanded(
                    child: _hourStat(
                      icon: Icons.calendar_month_rounded,
                      label: 'This Month',
                      value: _formatMinutes(thisMonthMinutes),
                      color: tc.orange,
                    ),
                  ),
                  Container(width: 1, height: 40, color: tc.border),
                  Expanded(
                    child: _hourStat(
                      icon: Icons.check_circle_rounded,
                      label: 'Days Worked',
                      value: '$daysWorked',
                      color: tc.orange,
                    ),
                  ),
                ]),
              );
            },
          ),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tc.border)),
            ),
            child: Row(children: [
              _attHeader('DATE', flex: 4),
              _attHeader('TIME IN', flex: 3),
              _attHeader('TIME OUT', flex: 3),
              _attHeader('TOTAL HRS', flex: 3),
              _attHeader('STATUS', flex: 3),
            ]),
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _attendanceStream(empId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Error loading attendance: ${snapshot.error}',
                      style: TextStyle(color: tc.red, fontSize: 12),
                    ),
                  ),
                );
              }

              final logs = snapshot.data ?? const [];
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.event_busy_outlined,
                            size: 32, color: tc.muted),
                        const SizedBox(height: 8),
                        Text('No attendance records yet.',
                            style:
                            TextStyle(color: tc.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }

              final rows = _buildAttendanceRows(logs).take(5).toList();

              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No valid attendance data.',
                        style: TextStyle(color: tc.muted, fontSize: 13)),
                  ),
                );
              }

              return Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    _attendanceRowFromData(rows[i]),
                    if (i < rows.length - 1)
                      Divider(
                          height: 1,
                          color: tc.border.withValues(alpha: 0.3)),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _hourStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tc.muted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: tc.text,
                  letterSpacing: -0.3),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ],
      ),
    );
  }

  Widget _attHeader(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: tc.muted,
              letterSpacing: 0.5)),
    );
  }

  Widget _attendanceRowFromData(Map<String, dynamic> row) {
    final date = row['date'] as DateTime?;
    final inTs = row['in'] as DateTime?;
    final outTs = row['out'] as DateTime?;
    final total = row['total'] as String;
    final status = row['status'] as String;
    final isLate = row['isLate'] as bool;

    final statusBg =
    isLate ? const Color(0xFFFEF9C3) : const Color(0xFFDCFCE7);
    final statusText =
    isLate ? const Color(0xFF854D0E) : const Color(0xFF166534);

    final isWorking = status == 'Working';
    final actualStatusBg = isWorking ? const Color(0xFFDBEAFE) : statusBg;
    final actualStatusText =
    isWorking ? const Color(0xFF1E40AF) : statusText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Expanded(
            flex: 4,
            child: Text(_fmtDate(date),
                style: TextStyle(fontSize: 14, color: tc.text))),
        Expanded(
            flex: 3,
            child: Text(_fmtTime(inTs),
                style: TextStyle(
                    fontSize: 14,
                    color: inTs != null ? tc.text : tc.muted))),
        Expanded(
            flex: 3,
            child: Text(_fmtTime(outTs),
                style: TextStyle(
                    fontSize: 14,
                    color: outTs != null ? tc.text : tc.muted))),
        Expanded(
            flex: 3,
            child: Text(total,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tc.text))),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: actualStatusBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(status,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: actualStatusText)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _leaveBalanceCard(String empId) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _leaveStream(empId),
        builder: (context, snapshot) {
          final leaves = snapshot.data ?? const [];
          final stats = _computeLeaveStats(leaves);

          final usedAnnual = stats['usedAnnual'] ?? 0;
          final usedSick = stats['usedSick'] ?? 0;
          final pendingAnnual = stats['pendingAnnual'] ?? 0;
          final pendingSick = stats['pendingSick'] ?? 0;
          final remainingAnnual =
              stats['remainingAnnual'] ?? kAdminAnnualLeaveTotal;
          final remainingSick =
              stats['remainingSick'] ?? kAdminSickLeaveTotal;

          final pending = leaves
              .where((l) =>
          _s(l['status'], 'pending').toLowerCase() == 'pending')
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Leave Balance',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: tc.text)),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text('Live',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tc.muted)),
              ]),
              const SizedBox(height: 20),
              _leaveBalanceItem(
                label: 'ANNUAL LEAVE',
                used: usedAnnual,
                total: kAdminAnnualLeaveTotal,
                barColor: const Color(0xFF904D00),
                pillBg: const Color(0xFFFFDCC3),
                pillText: const Color(0xFF6E3900),
              ),
              if (pendingAnnual > 0) ...[
                const SizedBox(height: 6),
                Text('+ $pendingAnnual day(s) pending approval',
                    style: TextStyle(
                        fontSize: 11,
                        color: tc.muted,
                        fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),
              _leaveBalanceItem(
                label: 'SICK LEAVE',
                used: usedSick,
                total: kAdminSickLeaveTotal,
                barColor: const Color(0xFF5C5F61),
                pillBg: const Color(0xFFE0E3E6),
                pillText: const Color(0xFF44474A),
              ),
              if (pendingSick > 0) ...[
                const SizedBox(height: 6),
                Text('+ $pendingSick day(s) pending approval',
                    style: TextStyle(
                        fontSize: 11,
                        color: tc.muted,
                        fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tc.border),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Remaining Total',
                            style:
                            TextStyle(fontSize: 11, color: tc.muted)),
                        const SizedBox(height: 2),
                        Text('${remainingAnnual + remainingSick} days',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: tc.text)),
                      ],
                    ),
                  ),
                  Text(
                    '${remainingAnnual}A · ${remainingSick}S',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.orangeText),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Text('PENDING REQUESTS',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tc.muted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.border),
                  ),
                  child: Text('No pending leave requests.',
                      style: TextStyle(fontSize: 13, color: tc.muted)),
                )
              else
                for (final p in pending.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF4FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tc.border),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _leaveTypeLabelAdmin(_s(p['leaveType'],
                                    _s(p['type'], 'Leave'))),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: tc.text),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_fmtDate(p['startDate'])} – ${_fmtDate(p['endDate'])} • ${_safeInt(p['days'], 1)}d',
                                style: TextStyle(
                                    fontSize: 12, color: tc.muted),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: tc.muted),
                      ]),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  String _leaveTypeLabelAdmin(String code) {
    const map = {
      'SL': 'Sick Leave',
      'VL': 'Vacation Leave',
      'EL': 'Emergency Leave',
      'BL': 'Bereavement Leave',
      'ML': 'Maternity/Paternity Leave',
    };
    return map[code.toUpperCase()] ?? code;
  }

  Widget _leaveBalanceItem({
    required String label,
    required int used,
    required int total,
    required Color barColor,
    required Color pillBg,
    required Color pillText,
  }) {
    final progress = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final remaining = (total - used).clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: pillText,
                    letterSpacing: 0.3)),
          ),
          const Spacer(),
          Text('${used.toString().padLeft(2, '0')}/$total',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tc.text)),
          const SizedBox(width: 6),
          Text('Days', style: TextStyle(fontSize: 13, color: tc.muted)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Container(height: 8, color: const Color(0xFFDCE9FF)),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 8, color: barColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Used: $used',
                style: TextStyle(fontSize: 11, color: tc.muted)),
            const Spacer(),
            Text('Remaining: $remaining',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tc.orangeText)),
          ],
        ),
      ],
    );
  }

  // ─── DEVICES + LOGIN HISTORY ──────────────────────────────────
  Widget _devicesAndLoginSection(String empId, Map<String, dynamic> emp) {
    return LayoutBuilder(builder: (context, constraints) {
      final stack = !BsResponsive(constraints.maxWidth).up(BsSize.lg);
      final left = _authorizedDevicesCard(empId, emp);
      final right = _deviceLoginHistoryCard(empId);
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: 20),
            right,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: left),
          const SizedBox(width: 20),
          Expanded(flex: 7, child: right),
        ],
      );
    });
  }

  // ✅ AUTHORIZED DEVICES CARD — Kukuha na ng actual data mula sa logs
  Widget _authorizedDevicesCard(String empId, Map<String, dynamic> emp) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _activityStream(empId),
        builder: (context, snapshot) {
          List<Map<String, dynamic>> devices = [];

          // 1. Kunin ang actual devices mula sa activity logs
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            devices = _extractDevicesFromLogs(snapshot.data!);
          }

          // 2. Fallback: Kung walang logs, check sa employee document
          if (devices.isEmpty) {
            final raw = emp['devices'];
            if (raw is List) {
              for (final d in raw) {
                if (d is Map) {
                  devices.add({
                    'name': _s(d['name'], 'Unknown Device'),
                    'sub': _s(d['type'], _s(d['platform'], 'Registered')),
                    'icon': Icons.devices_rounded,
                    'active': d['active'] != false,
                    'lastActive': d['lastActive'] ?? d['updatedAt'],
                  });
                } else if (d is String) {
                  devices.add({
                    'name': d,
                    'sub': 'Registered Device',
                    'icon': Icons.devices_rounded,
                    'active': true,
                    'lastActive': null,
                  });
                }
              }
            }
          }

          // 3. Fallback: Firebase Auth Session
          if (devices.isEmpty && _s(emp['authUid'], '').isNotEmpty) {
            devices.add({
              'name': 'Firebase Auth Session',
              'sub': 'Authenticated Account',
              'icon': Icons.vpn_key_outlined,
              'active': true,
              'lastActive': null,
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.devices_rounded, size: 22, color: tc.orange),
                const SizedBox(width: 8),
                Text('Authorized Devices',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: tc.text)),
              ]),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting && devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (devices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tc.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.border),
                  ),
                  child: Text('No devices registered for this employee.',
                      style: TextStyle(fontSize: 13, color: tc.muted)),
                )
              else
                for (int i = 0; i < devices.length; i++) ...[
                  _deviceItem(
                    name: devices[i]['name'] as String,
                    sub: devices[i]['sub'] as String,
                    icon: devices[i]['icon'] as IconData,
                    active: devices[i]['active'] as bool,
                    lastActive: devices[i]['lastActive'],
                  ),
                  if (i < devices.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  // Helper: Kinukuha ang unique devices mula sa activity logs
  List<Map<String, dynamic>> _extractDevicesFromLogs(
      List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, dynamic>> uniqueDevices = {};

    for (final log in logs) {
      final deviceName = _s(log['device'], '');
      if (deviceName.isNotEmpty &&
          deviceName.toLowerCase() != 'unknown device' &&
          deviceName != '—') {
        if (!uniqueDevices.containsKey(deviceName)) {
          final lowerName = deviceName.toLowerCase();
          IconData icon = Icons.devices_rounded;

          if (lowerName.contains('web') || lowerName.contains('chrome')) {
            icon = Icons.web_rounded;
          } else if (lowerName.contains('ios') || lowerName.contains('iphone')) {
            icon = Icons.phone_iphone_rounded;
          } else if (lowerName.contains('android')) {
            icon = Icons.phone_android_rounded;
          } else if (lowerName.contains('mobile')) {
            icon = Icons.smartphone_rounded;
          }

          uniqueDevices[deviceName] = {
            'name': deviceName,
            'sub': _s(log['platform'], _s(log['os'], 'Mobile App')),
            'lastActive': log['timestamp'],
            'active': true,
            'icon': icon,
          };
        } else {
          // I-update ang lastActive kung mas bago ang log na ito
          final currentLast = _toDateTime(uniqueDevices[deviceName]!['lastActive']);
          final newLast = _toDateTime(log['timestamp']);
          if (currentLast != null && newLast != null && newLast.isAfter(currentLast)) {
            uniqueDevices[deviceName]!['lastActive'] = log['timestamp'];
          }
        }
      }
    }
    return uniqueDevices.values.toList();
  }

  Widget _deviceItem({
    required String name,
    required String sub,
    required IconData icon,
    required bool active,
    dynamic lastActive,
  }) {
    final lastActiveStr = lastActive != null
        ? 'Last active: ${_fmtDate(lastActive)} ${_fmtTime(lastActive)}'
        : 'Active now';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFFFDCC3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: const Color(0xFF904D00)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tc.text)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 13, color: tc.muted)),
              const SizedBox(height: 4),
              Text(lastActiveStr,
                  style: TextStyle(fontSize: 11, color: tc.muted)),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
            shape: BoxShape.circle,
          ),
        ),
      ]),
    );
  }

  Widget _deviceLoginHistoryCard(String empId) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity History',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: tc.text)),
          const SizedBox(height: 24),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _activityStream(empId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final logs = snapshot.data ?? const [];
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No activity records yet.',
                      style: TextStyle(fontSize: 13, color: tc.muted)),
                );
              }
              final rows = logs.take(6).toList();
              return Column(
                children: [
                  for (int i = 0; i < rows.length; i++) ...[
                    _loginHistoryItem(
                      title: _s(rows[i]['action'],
                          _s(rows[i]['type'], 'Activity Event')),
                      sub:
                      '${_fmtDate(rows[i]['timestamp'])} • ${_fmtTime(rows[i]['timestamp'])} • ${_s(rows[i]['device'], 'Unknown device')}',
                      icon: _iconForActivity(rows[i]['type']),
                      iconBg: const Color(0xFFE0E3E6),
                      iconColor: const Color(0xFF44474A),
                      errorText: rows[i]['error'] != null
                          ? _s(rows[i]['error'])
                          : null,
                      showLine: i < rows.length - 1,
                    ),
                    if (i < rows.length - 1) const SizedBox(height: 4),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _iconForActivity(dynamic type) {
    final t = _s(type, '').toLowerCase();
    if (t.contains('login') || t.contains('auth')) {
      return Icons.vpn_key_outlined;
    }
    if (t.contains('error') || t.contains('fail')) {
      return Icons.error_outline;
    }
    if (t.contains('registration')) return Icons.person_add_alt_1_rounded;
    return Icons.settings_outlined;
  }

  Widget _loginHistoryItem({
    required String title,
    required String sub,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    String? errorText,
    required bool showLine,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                if (showLine)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: tc.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showLine ? 20 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: tc.text)),
                  const SizedBox(height: 4),
                  Text(sub, style: TextStyle(fontSize: 13, color: tc.muted)),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                        const Color(0xFFFFDAD6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFBA1A1A)
                                .withValues(alpha: 0.1)),
                      ),
                      child: Text(errorText,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF93000A))),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DIALOGS
  // ══════════════════════════════════════════════════════════════
  void _openEditDialog(Map<String, dynamic> emp) {
    setState(() {
      _selectedProfileEmp = emp;
      _isEditingEmployee = true;
    });
  }

  void _confirmDelete(String docId, String name) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: tc.card,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Confirm Record Deletion',
          style: TextStyle(color: tc.text)),
      content: Text(
          'Are you sure you want to completely erase the database file for $name? This action cannot be undone.',
          style: TextStyle(color: tc.text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            Navigator.pop(context);
            final err = await AdminDatabase.deleteEmployee(docId);
            if (err != null) {
              _snack('Deletion failed: $err', error: true);
            } else {
              _snack('Profile record deleted.');
              setState(() => _selectedProfileEmp = null);
              widget.onRefreshNeeded();
            }
          },
          child: const Text('Delete Permanently'),
        ),
      ],
    ),
  );

  void _confirmWipeAllLogs() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: tc.card,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Wipe Everything?', style: TextStyle(color: tc.text)),
      content: Text(
        'This will permanently delete ALL activity, attendance, clock-in/out, leave, and location records. This cannot be undone.',
        style: TextStyle(color: tc.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            Navigator.pop(context);
            final err = await AdminDatabase.wipeEverything();
            if (err != null) {
              _snack('Wipe failed: $err', error: true);
            } else {
              _snack('All logs cleared.');
              widget.onRefreshNeeded();
            }
          },
          child: const Text('Delete Everything'),
        ),
      ],
    ),
  );

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(48),
    decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tc.border)),
    child: Column(
      children: [
        Icon(Icons.person_search_rounded, size: 40, color: tc.muted),
        const SizedBox(height: 12),
        Text('No records match search parameters.',
            style: TextStyle(color: tc.muted, fontSize: 14)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => widget.onRefreshNeeded(),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// DASHED BORDER PAINTER
// ══════════════════════════════════════════════════════════════
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;

  _DashedBorderPainter({
    required this.color,
    this.radius = 12,
    this.dashWidth = 6,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final dashPath = _dashPath(path, dashWidth, dashSpace);
    canvas.drawPath(dashPath, paint);
  }

  Path _dashPath(Path source, double dashWidth, double dashSpace) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        dest.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + dashSpace;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
          oldDelegate.radius != radius ||
          oldDelegate.dashWidth != dashWidth ||
          oldDelegate.dashSpace != dashSpace;
}