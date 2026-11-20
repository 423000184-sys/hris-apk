// lib/screens/admin_employees_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'admin_database.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/admin_notification_service.dart';
import '../services/admin_employee_service.dart';

const int kAdminAnnualLeaveTotal = 18;
const int kAdminSickLeaveTotal = 18;
const int kWorkingDaysPerMonth = 22;

// ═════════════════════════════════════════════════════════════════════
// LIVENESS — boolean check + on-device encrypted template only
// ═════════════════════════════════════════════════════════════════════
const String kLivenessVerifiedField = 'livenessVerified';
const String kLivenessVerifiedAtField = 'livenessVerifiedAt';
const Duration kLivenessValidity = Duration(hours: 24);

const Map<String, Map<String, double>> kRoleSalaryMatrix = {
  'Employee': {'basicSalary': 18000.0, 'allowances': 2000.0},
  'Driver': {'basicSalary': 16000.0, 'allowances': 1500.0},
  'Admin': {'basicSalary': 25000.0, 'allowances': 3000.0},
  'Manager': {'basicSalary': 45000.0, 'allowances': 5000.0},
};

double _basicSalaryForRole(String r) =>
    kRoleSalaryMatrix[r]?['basicSalary'] ?? 0.0;
double _allowancesForRole(String r) =>
    kRoleSalaryMatrix[r]?['allowances'] ?? 0.0;
double _parseMoneyStr(String s) =>
    double.tryParse(s.replaceAll(',', '').replaceAll('₱', '').trim()) ?? 0.0;

class CustomAppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

class PendingEditRestore {
  static String? docId;
  static String? newPin;
  static bool shouldRestore = false;
}

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
  final _svc = AdminEmployeeService.instance;
  final _scrollController = ScrollController();

  /// Collections na HINDI kailanman buburahin.
  static const Set<String> _protectedCollections = {
    'admins',
    'system_config',
  };

  /// Collections na buburahin ng "Clear All". Idagdag dito ang iba mo pang
  /// collection names (ang wala dito ay hindi mabubura).
  static const List<String> _wipeCollections = [
    '_time_ping',
    '_time_sync',
    'activity_logs',
    'admin_audit_log',
    'admin_login_logs',
    'attendance_receipts',
    'client_locations',
    'device_audit',
    'employee_presence',
    'field_proofs',
    'locations',
    'password_change_requests',
    'pdf_exports',
    'presence_challenges',
    'public_stats',
    'security_events',
    'sessions',
    'settings',
    'test_collection',
    'employees',
    'attendance_logs',
    'liveness_logs',
    'support_reports',
    'notifications',
    'leave_requests',
    'activity logs'
    'public_stats'
    'security_events'
    'sessions'
    'settings'
    'test_collection'
    'activity logs'
  ];
  AdminColors get tc => AdminTheme.getColors(context);

  String get _actorEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ??
          'unknown';
  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

  final _editFirstCtrl = TextEditingController();
  final _editLastCtrl = TextEditingController();
  final _editFullNameCtrl = TextEditingController();
  final _editRoleCtrl = TextEditingController();
  final _editDeptCtrl = TextEditingController();
  final _editEmailCtrl = TextEditingController();
  final _editPhoneCtrl = TextEditingController();
  final _editKeyfobCtrl = TextEditingController();
  final _editPinCtrl = TextEditingController();
  final _editBirthdayCtrl = TextEditingController();
  final _editDeviceNameCtrl = TextEditingController();
  final _editEmployeeIdCtrl = TextEditingController();
  final _editBasicSalaryCtrl = TextEditingController();
  final _editAllowancesCtrl = TextEditingController();
  final _editDailyRateCtrl = TextEditingController();
  final _editBankNameCtrl = TextEditingController();
  final _editAccountNumberCtrl = TextEditingController();

  // ✅ IDINAGDAG: Controllers para sa Leave Balances
  final _editAnnualLeaveCtrl = TextEditingController();
  final _editSickLeaveCtrl = TextEditingController();

  DateTime? _editBirthday;
  String? _editDepartmentDropdown;
  String? _editPositionDropdown;
  bool _editSaving = false;
  bool _isEditingEmployee = false;
  String _editOriginalEmployeeId = '';
  String _editGender = 'male';
  bool _editPinVisible = false;
  bool _editPinJustGenerated = false;
  bool _editPinSaving = false;

  XFile? _editPhotoXFile;
  Uint8List? _editPhotoBytes;
  bool _editPhotoUploading = false;
  String? _editPhotoUrl;

  Uint8List? _addPhotoBytes;

  static const List<String> _departmentOptions = [
    'HR/Admin',
    'Accounting',
    'Operation',
  ];
  static const Map<String, List<String>> _departmentPositionsMap = {
    'HR/Admin': ['Driver', 'Messenger'],
    'Accounting': ['Accountant'],
    'Operation': ['Manager', 'Broker'],
  };

  final _addFirstCtrl = TextEditingController();
  final _addLastCtrl = TextEditingController();
  final _addEmailCtrl = TextEditingController();
  final _addPhoneCtrl = TextEditingController();
  final _addRoleCtrl = TextEditingController();
  final _addDeptCtrl = TextEditingController();
  final _addPinCtrl = TextEditingController();
  final _addKeyfobCtrl = TextEditingController();
  final _addIdCtrl = TextEditingController();
  bool _addSaving = false;
  bool _isAddingEmployee = false;
  bool _addPinVisible = false;
  bool _addPinJustGenerated = false;
  String? _addDepartmentDropdown;
  String? _addPositionDropdown;
  String _addGender = 'male';
  static const List<String> _genderOptions = ['male', 'female'];

  final _filterCtrl = TextEditingController();
  String _filterText = '';
  String _department = 'All Departments';
  String _position = 'All Positions';
  String _sort = 'A-Z';
  String _livenessFilter = 'All';
  int _page = 0;
  static const int _pageSize = 6;

  Map<String, dynamic>? _selectedProfileEmp;
  final Set<String> _selectedEmpIds = {};
  final bool _bulkSelectMode = false;

  @override
  void initState() {
    super.initState();
    _filterCtrl.text = widget.searchQuery;
    _filterText = widget.searchQuery;
    _addPinCtrl.text = AdminEmployeeService.generatePin();

    if (PendingEditRestore.shouldRestore && PendingEditRestore.docId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restorePendingEdit();
      });
    }
  }

  void _restorePendingEdit() {
    if (!mounted) return;
    final docId = PendingEditRestore.docId;
    if (docId == null) return;

    Map<String, dynamic> emp = {};
    for (final e in widget.employees) {
      if (_s(e['id'], '') == docId) {
        emp = e;
        break;
      }
    }

    if (emp.isEmpty) {
      PendingEditRestore.shouldRestore = false;
      PendingEditRestore.docId = null;
      PendingEditRestore.newPin = null;
      return;
    }

    _initEditControllers(emp);
    setState(() {
      _selectedProfileEmp = emp;
      _isEditingEmployee = true;
      _editPhotoXFile = null;
      _editPhotoBytes = null;
      if (PendingEditRestore.newPin != null) {
        _editPinCtrl.text = PendingEditRestore.newPin!;
        _editPinJustGenerated = true;
        _editPinVisible = true;
        _editPinSaving = false;
      }
    });

    PendingEditRestore.shouldRestore = false;
    PendingEditRestore.docId = null;
    PendingEditRestore.newPin = null;
  }

  @override
  void didUpdateWidget(covariant AdminEmployeesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {
        _filterCtrl.text = widget.searchQuery;
        _filterText = widget.searchQuery;
        _page = 0;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in [
      _editFirstCtrl,
      _editLastCtrl,
      _editFullNameCtrl,
      _editRoleCtrl,
      _editDeptCtrl,
      _editEmailCtrl,
      _editPhoneCtrl,
      _editKeyfobCtrl,
      _editPinCtrl,
      _editBirthdayCtrl,
      _editDeviceNameCtrl,
      _editEmployeeIdCtrl,
      _editBasicSalaryCtrl,
      _editAllowancesCtrl,
      _editDailyRateCtrl,
      _editBankNameCtrl,
      _editAccountNumberCtrl,
      _editAnnualLeaveCtrl, // ✅ Idinagdag
      _editSickLeaveCtrl,   // ✅ Idinagdag
      _addFirstCtrl,
      _addLastCtrl,
      _addEmailCtrl,
      _addPhoneCtrl,
      _addRoleCtrl,
      _addDeptCtrl,
      _addPinCtrl,
      _addKeyfobCtrl,
      _addIdCtrl,
      _filterCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════
  // Small helpers
  // ═════════════════════════════════════════════════════════════════
  String _s(dynamic v, [String f = '—']) {
    if (v == null) return f;
    final str = v.toString().trim();
    return str.isEmpty ? f : str;
  }

  int _safeInt(dynamic v, [int f = 0]) {
    if (v == null) return f;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? f;
  }

  double _moneyOf(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDate(dynamic v, {String f = '—'}) {
    final dt = v is DateTime ? v : _toDateTime(v);
    if (dt == null) return f;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[dt.month - 1]} ${dt.day.toString().padLeft(2, '0')}, ${dt.year}';
  }

  String _fmtTime(dynamic v, {String f = '—'}) {
    final dt = v is DateTime ? v : _toDateTime(v);
    if (dt == null) return f;
    final h24 = dt.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    return '${h12.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} '
        '${h24 >= 12 ? 'PM' : 'AM'}';
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

  bool _isActive(Map<String, dynamic> e) {
    if (e['terminated'] == true) return false;
    final online = e['isOnline'];
    if (online is bool) return online;
    final loggedIn = e['isLoggedIn'];
    if (loggedIn is bool) return loggedIn;
    final status = _s(e['status'], '').toLowerCase();
    if (status == 'online' || status == 'logged_in' || status == 'active') {
      return true;
    }
    final last = _toDateTime(e['lastLogin'] ?? e['lastActive']);
    if (last != null && DateTime.now().difference(last).inMinutes <= 15) {
      return true;
    }
    return false;
  }

  bool _hasProfilePhoto(Map<String, dynamic> e) {
    final u = _s(e['photoUrl'], '');
    return u.isNotEmpty && u != '—';
  }

  // ═════════════════════════════════════════════════════════════════
  // Liveness detection (boolean, NOT biometric)
  // ═════════════════════════════════════════════════════════════════
  bool _isLivenessVerified(Map<String, dynamic> e) {
    if (e[kLivenessVerifiedField] != true) return false;
    final ts = _toDateTime(e[kLivenessVerifiedAtField]);
    if (ts == null) return false;
    return DateTime.now().difference(ts) <= kLivenessValidity;
  }

  DateTime? _livenessVerifiedAt(Map<String, dynamic> e) =>
      _toDateTime(e[kLivenessVerifiedAtField]);

  String _livenessSourceOf(Map<String, dynamic> e) =>
      _s(e['livenessSource'], '—');

  int _livenessCheckCountOf(Map<String, dynamic> e) {
    final v = _safeInt(e['livenessCheckCount'], -1);
    if (v >= 0) return v;
    return _isLivenessVerified(e) ? 1 : 0;
  }

  int _annualLeaveTotalOf(Map<String, dynamic> e) {
    final v = _safeInt(e['annualLeaveTotal'], -1);
    return v >= 0 ? v : kAdminAnnualLeaveTotal;
  }

  int _sickLeaveTotalOf(Map<String, dynamic> e) {
    final v = _safeInt(e['sickLeaveTotal'], -1);
    return v >= 0 ? v : kAdminSickLeaveTotal;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
  }

  bool _match(String text) {
    final needle = _filterText.trim().toLowerCase();
    if (needle.isEmpty) return true;
    final lower = text.toLowerCase();
    if (needle.contains(' ')) return lower.contains(needle);
    final words = lower.split(RegExp(r'[\s\-_.,;:()\[\]{}@/\\|]+'));
    return words.any((w) => w.startsWith(needle));
  }

  List<String> _positionsForDept(String d) =>
      d.isEmpty ? const [] : (_departmentPositionsMap[d] ?? const []);

  List<String> get _allPositionOptions {
    final set = <String>{};
    for (final r in _departmentPositionsMap.values) {
      set.addAll(r);
    }
    return set.toList()..sort();
  }

  List<String> get _positions {
    if (_department == 'All Departments') {
      final all = <String>{};
      for (final r in _departmentPositionsMap.values) {
        all.addAll(r);
      }
      return ['All Positions', ...(all.toList()..sort())];
    }
    final d = _departmentPositionsMap[_department] ?? const [];
    return ['All Positions', ...([...d]..sort())];
  }

  void _recomputeDailyRate() {
    final b = _parseMoneyStr(_editBasicSalaryCtrl.text);
    _editDailyRateCtrl.text = (b / kWorkingDaysPerMonth).toStringAsFixed(2);
  }

  // ═════════════════════════════════════════════════════════════════
  // Build — directory
  // ═════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_isEditingEmployee && _selectedProfileEmp != null) {
      return _buildEditPage(_selectedProfileEmp!);
    }
    if (_isAddingEmployee) return _buildAddPage();
    if (_selectedProfileEmp != null) {
      return _buildProfilePage(_selectedProfileEmp!);
    }

    final departments = ['All Departments', ..._departmentOptions];
    final allEmployees = widget.employees;

    var filtered = allEmployees.where((e) {
      if (e['terminated'] == true) return false;
      final hay =
          '${_nameOf(e)} ${_s(e['role'])} ${_s(e['id'])} ${_s(e['department'])}';

      final verified = _isLivenessVerified(e);
      if (_livenessFilter == 'Liveness ✓' && !verified) return false;
      if (_livenessFilter == 'No Liveness' && verified) return false;

      return _match(hay) &&
          (_department == 'All Departments' ||
              _s(e['department']) == _department) &&
          (_position == 'All Positions' || _s(e['role']) == _position);
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
          thickness: 8,
          radius: const Radius.circular(8),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1600),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(allEmployees),
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

  Widget _header(List<Map<String, dynamic>> currentEmployees) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final livenessCount = currentEmployees
          .where((e) => e['terminated'] != true && _isLivenessVerified(e))
          .length;

      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employee Directory',
            style: TextStyle(
              fontSize: r.responsive<double>(xs: 24, sm: 26, md: 28, lg: 32),
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Manage and monitor ${currentEmployees.where((e) => e['terminated'] != true).length} active workforce members.',
                style: TextStyle(color: tc.muted, fontSize: 15),
              ),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF16A34A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        size: 12, color: Color(0xFF166534)),
                    const SizedBox(width: 4),
                    Text(
                      '$livenessCount with Liveness',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF166534),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );

      final addBtn = ElevatedButton.icon(
        onPressed: () {
          if (widget.onAddEmployee != null) {
            widget.onAddEmployee!();
          } else {
            setState(() {
              _isAddingEmployee = true;
              _addPhotoBytes = null;
              _addPinCtrl.text = AdminEmployeeService.generatePin();
              _addPinJustGenerated = true;
              _addPinVisible = false;
              _addGender = 'male';
              _addDepartmentDropdown = null;
              _addPositionDropdown = null;
            });
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: const Text(
          'Add New Employee',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      );

      final wipeBtn = OutlinedButton.icon(
        onPressed: _confirmWipeAllLogs,
        style: OutlinedButton.styleFrom(
          foregroundColor: tc.red,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          side: BorderSide(color: tc.red.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
        label: const Text(
          'Clear All Logs',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 14),
            wipeBtn,
            const SizedBox(height: 10),
            addBtn,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: title),
          wipeBtn,
          const SizedBox(width: 8),
          addBtn,
        ],
      );
    });
  }

  Widget _filterBar(List<String> departments) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.lg);

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
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
      );

      final deptDD = _pillDropdown(
        value: _department,
        items: departments,
        onChanged: (v) => setState(() {
          _department = v ?? 'All Departments';
          _position = 'All Positions';
          _page = 0;
        }),
      );
      final posDD = _pillDropdown(
        value: _position,
        items: _positions,
        onChanged: (v) => setState(() {
          _position = v ?? 'All Positions';
          _page = 0;
        }),
      );
      final sortDD = _pillDropdown(
        value: _sort,
        items: const ['A-Z', 'Z-A'],
        prefix: 'Sort: ',
        onChanged: (v) => setState(() => _sort = v ?? 'A-Z'),
      );
      final livenessDD = _pillDropdown(
        value: _livenessFilter,
        items: const ['All', 'Liveness ✓', 'No Liveness'],
        prefix: 'Liveness: ',
        onChanged: (v) => setState(() {
          _livenessFilter = v ?? 'All';
          _page = 0;
        }),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: deptDD),
              const SizedBox(width: 10),
              Expanded(child: posDD),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: livenessDD),
              const SizedBox(width: 10),
              Expanded(child: sortDD),
            ]),
          ],
        );
      }
      return Row(children: [
        Expanded(flex: 3, child: search),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: deptDD),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: posDD),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: livenessDD),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: sortDD),
      ]);
    });
  }

  Widget _pillDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String prefix = '',
  }) {
    final safe =
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
          value: safe,
          isExpanded: true,
          dropdownColor: tc.card,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: tc.muted, size: 20),
          style: TextStyle(
              color: tc.text, fontSize: 14, fontWeight: FontWeight.w500),
          items: items
              .map((d) => DropdownMenuItem<String>(
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
          ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _directoryGrid(List<Map<String, dynamic>> items) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final cols =
      r.responsive<int>(xs: 1, sm: 1, md: 2, lg: 3, xl: 3, xxl: 3);
      const gap = 20.0;
      final colW = (c.maxWidth - (cols - 1) * gap) / cols;

      final cardHeight = cols == 1 ? 520.0 : 440.0;

      final widgets = <Widget>[];

      if (items.isNotEmpty) {
        final featuredW =
        cols >= 3 ? colW * 2 + gap : (cols == 2 ? colW * 2 + gap : colW);
        widgets.add(SizedBox(
          width: featuredW,
          height: cols == 1 ? 580.0 : 440.0,
          child: _featuredCard(items[0]),
        ));
        for (var i = 1; i < items.length; i++) {
          widgets.add(SizedBox(
            width: colW,
            height: cardHeight,
            child: _regularCard(items[i]),
          ));
        }
      }
      widgets.add(SizedBox(
        width: colW,
        height: cardHeight,
        child: _quickInviteCard(),
      ));

      return Wrap(spacing: gap, runSpacing: gap, children: widgets);
    });
  }

  Widget _featuredCard(Map<String, dynamic> emp) {
    final name = _nameOf(emp);
    final initials = _initialsOf(name);
    final role = _s(emp['role'], 'Staff Member');
    final dept = _s(emp['department'], 'General');
    final id = _s(emp['employeeId'], _s(emp['id'], 'N/A'));
    final isActive = _isActive(emp);
    final verified = _isLivenessVerified(emp);
    final docId = _s(emp['id'], '');
    final isSelected = _selectedEmpIds.contains(docId);

    return LayoutBuilder(builder: (_, c) {
      final isNarrow = c.maxWidth < 500;

      final avatar = Stack(
        children: [
          Container(
            width: isNarrow ? 88 : 128,
            height: isNarrow ? 88 : 128,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: tc.orange, width: 2),
            ),
            child: _avatarContent(
              emp,
              initials,
              isNarrow ? 88 : 128,
              isNarrow ? 28 : 40,
              tc.orangeText,
            ),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF006E05)
                    : const Color(0xFF857365),
                shape: BoxShape.circle,
                border: Border.all(color: tc.card, width: 3.5),
              ),
            ),
          ),
        ],
      );

      final info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: isNarrow ? 18 : 22,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            _statusPill(isActive),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 4, children: [
            _livenessPill(verified, compact: true),
          ]),
          const SizedBox(height: 4),
          Text(
            role,
            style: TextStyle(color: tc.muted, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _statBlock('DEPARTMENT', dept)),
            const SizedBox(width: 12),
            Expanded(child: _statBlock('EMPLOYEE ID', id)),
          ]),
        ],
      );

      final actionsWide = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _featAction(
            Icons.mail_outline_rounded,
                () => _snack('Email: ${_s(emp['email'])}'),
            'Email',
          ),
          const SizedBox(height: 8),
          _featAction(
            Icons.phone_outlined,
                () => _snack('Phone: ${_s(emp['phone'], _s(emp['mobile']))}'),
            'Call',
          ),
          const SizedBox(height: 8),
          _menuButton(emp, name),
        ],
      );

      final actionsNarrow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _featAction(
            Icons.mail_outline_rounded,
                () => _snack('Email: ${_s(emp['email'])}'),
            'Email',
          ),
          const SizedBox(width: 8),
          _featAction(
            Icons.phone_outlined,
                () => _snack('Phone: ${_s(emp['phone'], _s(emp['mobile']))}'),
            'Call',
          ),
          const SizedBox(width: 8),
          _menuButton(emp, name),
        ],
      );

      return GestureDetector(
        onTap: _bulkSelectMode ? () => _toggleSelection(docId) : null,
        child: Container(
          padding: EdgeInsets.all(isNarrow ? 16 : 24),
          decoration: BoxDecoration(
            color: isSelected ? tc.orange.withValues(alpha: 0.06) : tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? tc.orange : tc.border,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: isNarrow
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  Expanded(child: info),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: actionsNarrow,
              ),
            ],
          )
              : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(child: info),
              const SizedBox(width: 12),
              actionsWide,
            ],
          ),
        ),
      );
    });
  }

  Widget _regularCard(Map<String, dynamic> emp) {
    final name = _nameOf(emp);
    final initials = _initialsOf(name);
    final role = _s(emp['role'], 'Staff Member');
    final dept = _s(emp['department'], 'General');
    final email = _s(emp['email'], '—');
    final isActive = _isActive(emp);
    final verified = _isLivenessVerified(emp);
    final docId = _s(emp['id'], '');
    final isSelected = _selectedEmpIds.contains(docId);

    return GestureDetector(
      onTap: _bulkSelectMode ? () => _toggleSelection(docId) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? tc.orange.withValues(alpha: 0.06) : tc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? tc.orange : tc.border,
            width: isSelected ? 2 : 1,
          ),
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
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tc.border),
                ),
                child: _avatarContent(emp, initials, 64, 22, tc.orangeText),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _statusPill(isActive),
                  const SizedBox(height: 4),
                  _livenessPill(verified, compact: true),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Text(
              role,
              style: TextStyle(color: tc.muted, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: tc.border),
            const SizedBox(height: 12),
            _infoRow(Icons.business_outlined, dept),
            const SizedBox(height: 8),
            _infoRow(Icons.email_outlined, email),
            const SizedBox(height: 12),
            const Spacer(),
            Row(children: [
              Expanded(
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
                    child: Text(
                      'View Profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tc.text,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _menuButton(emp, name),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _menuButton(Map<String, dynamic> emp, String name) {
    return PopupMenuButton<String>(
      color: tc.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tc.border),
        ),
        child: Icon(Icons.more_vert_rounded, color: tc.text, size: 18),
      ),
      onSelected: (v) {
        if (v == 'profile') {
          setState(() => _selectedProfileEmp = emp);
        } else if (v == 'edit') {
          _openEdit(emp);
        } else if (v == 'reset_liveness') {
          _confirmResetLiveness(emp);
        } else if (v == 'delete') {
          _confirmTerminate(_s(emp['id']), name);
        }
      },
      itemBuilder: (_) => [
        _popupItem(
            'profile', Icons.person_outline_rounded, 'View Profile', tc.text),
        _popupItem('edit', Icons.edit_outlined, 'Edit Details', tc.orange),
        _popupItem('reset_liveness', Icons.face_retouching_off_rounded,
            'Reset Face / Liveness', const Color(0xFFF59E0B)),
        _popupItem(
            'delete', Icons.delete_outline_rounded, 'Terminate', tc.red),
      ],
    );
  }

  PopupMenuItem<String> _popupItem(
      String v, IconData icon, String label, Color c) {
    return PopupMenuItem(
      value: v,
      child: Row(children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: c, fontSize: 13)),
      ]),
    );
  }

  Widget _statusPill(bool active) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: active ? const Color(0xFFDCFCE7) : const Color(0xFFE0E3E6),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: active ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
      ),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color:
          active ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: active ? const Color(0xFF166534) : const Color(0xFF564334),
        ),
      ),
    ]),
  );

  Widget _livenessPill(bool verified, {bool compact = false}) {
    final bg = verified ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    final fg = verified ? const Color(0xFF166534) : const Color(0xFF6B7280);
    final border =
    verified ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          verified ? Icons.verified_user_rounded : Icons.person_off_rounded,
          size: compact ? 10 : 11,
          color: fg,
        ),
        SizedBox(width: compact ? 3 : 4),
        Text(
          verified ? 'Liveness' : 'No Liveness',
          style: TextStyle(
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w800,
            color: fg,
            letterSpacing: 0.3,
          ),
        ),
      ]),
    );
  }

  Widget _statBlock(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tc.muted,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tc.text,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    ]);
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: tc.muted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(color: tc.text, fontSize: 13),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ]);
  }

  Widget _featAction(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
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

  Widget _avatarContent(Map<String, dynamic> emp, String initial, double size,
      double fontSize, Color textColor) {
    final url = _s(emp['photoUrl'], '').isNotEmpty
        ? _s(emp['photoUrl'], '')
        : _s(emp['photo'], '');
    if (url.isNotEmpty && url != '—') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: _buildPhoto(url, size, size, BoxFit.cover,
            _avatarFallback(initial, fontSize, textColor)),
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
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _buildPhoto(
      String url, double? w, double? h, BoxFit fit, Widget errorWidget) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || cleanUrl == '—') return errorWidget;

    if (cleanUrl.startsWith('data:image')) {
      try {
        final commaIndex = cleanUrl.indexOf(',');
        if (commaIndex == -1) {
          return errorWidget;
        }
        final b64 =
        cleanUrl.substring(commaIndex + 1).replaceAll(RegExp(r'\s'), '');
        if (b64.isEmpty) {
          return errorWidget;
        }
        final bytes = base64Decode(b64);
        if (bytes.isEmpty) {
          return errorWidget;
        }
        return Image.memory(
          bytes,
          fit: fit,
          width: w,
          height: h,
          gaplessPlayback: true,
          errorBuilder: (_, error, __) {
            return errorWidget;
          },
        );
      } catch (e) {
        return errorWidget;
      }
    }

    return Image.network(
      cleanUrl,
      fit: fit,
      width: w,
      height: h,
      gaplessPlayback: true,
      errorBuilder: (_, error, __) {
        return errorWidget;
      },
    );
  }

  Widget _quickInviteCard() => Container(
    decoration: BoxDecoration(
      color: tc.card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: CustomPaint(
      painter: _DashedBorderPainter(color: tc.border, radius: 12),
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
              Text(
                'Quick Invite',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Send joining link to new staff\nmembers via email.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: tc.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pagination(int s, int e, int total, int totalPages) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);
      final info = Text(
        'Showing ${s + 1} to $e of $total employees',
        style: TextStyle(color: tc.muted, fontSize: 13),
      );
      final controls = Row(mainAxisSize: MainAxisSize.min, children: [
        _pageArrow(Icons.chevron_left_rounded, _page > 0,
                () => setState(() => _page--)),
        const SizedBox(width: 6),
        ...List.generate(
          totalPages,
              (i) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _pageNum(i),
          ),
        ),
        _pageArrow(Icons.chevron_right_rounded, _page < totalPages - 1,
                () => setState(() => _page++)),
      ]);
      return Container(
        padding: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tc.border)),
        ),
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

  Widget _pageArrow(IconData i, bool en, VoidCallback onTap) => InkWell(
    onTap: en ? onTap : null,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tc.border),
      ),
      child: Icon(i, size: 16, color: en ? tc.text : tc.muted),
    ),
  );

  Widget _pageNum(int i) {
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
          border: Border.all(color: sel ? tc.orange : tc.border),
        ),
        child: Text(
          '${i + 1}',
          style: TextStyle(
            color: sel ? Colors.white : tc.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 56, color: tc.muted),
          const SizedBox(height: 12),
          Text(
            'No employees found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try adjusting your filters or search query.',
            style: TextStyle(fontSize: 13, color: tc.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String docId) {
    if (docId.isEmpty) return;
    setState(() {
      if (_selectedEmpIds.contains(docId)) {
        _selectedEmpIds.remove(docId);
      } else {
        _selectedEmpIds.add(docId);
      }
    });
  }

  // ═════════════════════════════════════════════════════════════════
  // Add page
  // ═════════════════════════════════════════════════════════════════
  Widget _buildAddPage() {
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
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _isAddingEmployee = false),
                  icon: Icon(Icons.arrow_back_rounded, color: tc.muted),
                  label: Text(
                    'Back to Directory',
                    style: TextStyle(
                      color: tc.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Add New Employee',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: tc.text,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, c) {
                  final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
                  final photo = _addPhotoCard();
                  final form = Column(children: [
                    _addPersonalCard(),
                    const SizedBox(height: 24),
                    _addSecurityCard(),
                    const SizedBox(height: 24),
                    _addActions(),
                  ]);
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photo,
                        const SizedBox(height: 24),
                        form,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: photo),
                      const SizedBox(width: 24),
                      Expanded(child: form),
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

  Widget _addPhotoCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: tc.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: tc.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1024,
              maxHeight: 1024,
              imageQuality: 85,
            );
            if (picked != null) {
              final bytes = await picked.readAsBytes();
              setState(() {
                _addPhotoBytes = bytes;
              });
            }
          },
          child: Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tc.surface,
              border: Border.all(color: tc.border),
              image: _addPhotoBytes != null
                  ? DecorationImage(
                  image: MemoryImage(_addPhotoBytes!),
                  fit: BoxFit.cover)
                  : null,
            ),
            child: _addPhotoBytes == null
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 64, color: tc.muted),
                  const SizedBox(height: 12),
                  Text(
                    'Upload Photo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tc.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'JPG, PNG - max 2MB',
                    style: TextStyle(fontSize: 11, color: tc.muted),
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Profile Identity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: tc.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This photo will be used as a reference for the employee\'s profile.',
          style: TextStyle(fontSize: 13, color: tc.muted, height: 1.5),
        ),
      ],
    ),
  );

  Widget _addPersonalCard() {
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
            Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 500;
            final fields = [
              _input('First Name', _addFirstCtrl, maxLen: 50),
              _input('Last Name', _addLastCtrl, maxLen: 50),
              _input('Email Address', _addEmailCtrl, maxLen: 120),
              _input('Phone No.', _addPhoneCtrl, maxLen: 20),
            ];
            if (narrow) {
              return Column(children: [
                ...fields.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: f,
                )),
                _addDeptField(),
                const SizedBox(height: 16),
                _addPosField(),
                const SizedBox(height: 16),
                _input('Employee ID (e.g. emp-01-2026)', _addIdCtrl,
                    maxLen: 30),
                const SizedBox(height: 16),
                _addGenderField(),
              ]);
            }
            return Column(children: [
              Row(children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 16),
                Expanded(child: fields[1]),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: fields[2]),
                const SizedBox(width: 16),
                Expanded(child: fields[3]),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _addDeptField()),
                const SizedBox(width: 16),
                Expanded(child: _addPosField()),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _input('Employee ID (e.g. emp-01-2026)', _addIdCtrl,
                      maxLen: 30),
                ),
                const SizedBox(width: 16),
                Expanded(child: _addGenderField()),
              ]),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _addSecurityCard() {
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
            Icon(Icons.security, color: tc.orange, size: 20),
            const SizedBox(width: 8),
            Text(
              'Security Credentials',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 500;
            final kf = _input('Keyfob Serial (NFC)', _addKeyfobCtrl, maxLen: 40);
            final pin = _lockedPinField(
              '4-Digit PIN (Auto-Generated)',
              _addPinCtrl,
              _addPinVisible,
              _addPinJustGenerated,
              false,
                  () => setState(() => _addPinVisible = !_addPinVisible),
              _onGenerateAddPin,
            );
            if (narrow) {
              return Column(children: [
                kf,
                const SizedBox(height: 16),
                pin,
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: kf),
                const SizedBox(width: 16),
                Expanded(child: pin),
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
            child: Row(children: [
              Icon(Icons.lock_rounded, size: 16, color: tc.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The 4-digit PIN is auto-generated and stored as a salted hash. Tap "Regenerate" for a new one. It will be saved automatically on submit.',
                  style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // FIX #1: green notice now accurately describes on-device template.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF16A34A)),
            ),
            child: Row(children: [
              const Icon(Icons.verified_user_rounded,
                  size: 16, color: Color(0xFF166534)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Blink + Smile liveness check is performed in the mobile app. '
                      'A face template is stored encrypted on the employee\'s '
                      'device only. No face template or biometric data is '
                      'transmitted to or stored on our servers.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF166534),
                      height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _addActions() {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 500;
      final cancel = OutlinedButton(
        onPressed: () => setState(() => _isAddingEmployee = false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: tc.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text('Cancel', style: TextStyle(color: tc.text)),
      );
      final done = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _addSaving ? null : _submitAdd,
        child: _addSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child:
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : const Text(
          'Done',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
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
        children: [cancel, const SizedBox(width: 16), done],
      );
    });
  }

  Future<void> _submitAdd() async {
    final firstName =
    AdminEmployeeService.sanitize(_addFirstCtrl.text, maxLen: 50);
    final lastName =
    AdminEmployeeService.sanitize(_addLastCtrl.text, maxLen: 50);
    final email =
    AdminEmployeeService.sanitize(_addEmailCtrl.text, maxLen: 120);
    final empId = _addIdCtrl.text.trim();
    final phone = AdminEmployeeService.sanitize(_addPhoneCtrl.text, maxLen: 20);

    if (firstName.isEmpty || lastName.isEmpty) {
      _snack('First & last name are required.', error: true);
      return;
    }
    final emailErr = AdminEmployeeService.validateEmail(email);
    if (emailErr != null) {
      _snack('Error: $emailErr', error: true);
      return;
    }
    final idErr = AdminEmployeeService.validateEmployeeId(empId);
    if (idErr != null) {
      _snack('Error: $idErr', error: true);
      return;
    }
    if (_addDepartmentDropdown == null || _addDeptCtrl.text.isEmpty) {
      _snack('Please select a Department.', error: true);
      return;
    }
    if (_addRoleCtrl.text.trim().isEmpty) {
      _snack('Please select a Role / Position.', error: true);
      return;
    }

    final plainPin = _addPinCtrl.text.trim();
    if (plainPin.length != 4 || int.tryParse(plainPin) == null) {
      _snack('Invalid PIN. Please regenerate.', error: true);
      return;
    }

    setState(() => _addSaving = true);

    try {
      final err = await _svc.createEmployee(
        employeeId: empId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        role: _addRoleCtrl.text.trim(),
        department: _addDeptCtrl.text.trim(),
        nfcTagId: _addKeyfobCtrl.text.trim(),
        plainPin: plainPin,
        phone: phone.isEmpty ? null : phone,
        gender: _addGender,
      );

      if (!mounted) return;

      if (err != null) {
        _snack('Error: $err', error: true);
        return;
      }

      String? targetDocId;
      try {
        var query = await FirebaseFirestore.instance
            .collection('employees')
            .where('employeeId', isEqualTo: empId)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          targetDocId = query.docs.first.id;
        } else {
          query = await FirebaseFirestore.instance
              .collection('employees')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            targetDocId = query.docs.first.id;
          }
        }
      } catch (e) {
        debugPrint('Failed to fetch real doc ID: $e');
      }

      String? base64Photo;
      if (_addPhotoBytes != null) {
        try {
          final compressed = _compressForFirestore(_addPhotoBytes!);
          if (compressed != null) {
            final b64 = base64Encode(compressed).replaceAll(RegExp(r'\s'), '');
            if (b64.length <= 900 * 1024) {
              base64Photo = 'data:image/jpeg;base64,$b64';
            }
          }
        } catch (e) {
          debugPrint('Image compression failed: $e');
        }
      }

      if (base64Photo != null && targetDocId != null) {
        try {
          await AdminDatabase.fs
              .collection('employees')
              .doc(targetDocId)
              .update({
            'photoUrl': base64Photo,
          });
        } catch (e) {
          debugPrint('Failed to update photoUrl: $e');
        }
      }

      _snack('Employee added. PIN copied to clipboard.');
      await Clipboard.setData(ClipboardData(text: plainPin));

      for (final c in [
        _addFirstCtrl,
        _addLastCtrl,
        _addEmailCtrl,
        _addPhoneCtrl,
        _addRoleCtrl,
        _addDeptCtrl,
        _addPinCtrl,
        _addKeyfobCtrl,
        _addIdCtrl,
      ]) {
        c.clear();
      }
      setState(() {
        _isAddingEmployee = false;
        _addPinVisible = false;
        _addPinJustGenerated = false;
        _addGender = 'male';
        _addDepartmentDropdown = null;
        _addPositionDropdown = null;
        _addPhotoBytes = null;
      });
      widget.onRefreshNeeded();
    } finally {
      if (mounted) setState(() => _addSaving = false);
    }
  }

  void _onGenerateAddPin() {
    if (_addSaving) return;
    final pin = AdminEmployeeService.generatePin(current: _addPinCtrl.text);
    setState(() {
      _addPinCtrl.text = pin;
      _addPinJustGenerated = true;
      _addPinVisible = true;
    });
    _snack('New PIN generated. Tap the eye icon to reveal, then copy.');
  }

  Widget _input(
      String label,
      TextEditingController ctrl, {
        bool readOnly = false,
        int maxLen = 100,
      }) {
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      maxLength: maxLen,
      style: TextStyle(
        fontSize: 14,
        color: tc.text,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
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

  Widget _lockedPinField(
      String label,
      TextEditingController controller,
      bool visible,
      bool justGenerated,
      bool saving,
      VoidCallback onToggle,
      VoidCallback onRegen,
      ) {
    final hasPin = controller.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Row(children: [
            Icon(Icons.lock_rounded, size: 12, color: tc.orange),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                  letterSpacing: 0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: saving ? null : onRegen,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tc.orange.withValues(alpha: saving ? 0.05 : 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tc.orange.withValues(alpha: saving ? 0.15 : 0.4),
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded, size: 12, color: tc.orange),
                const SizedBox(width: 4),
                Text(
                  'Regenerate',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tc.orange,
                    letterSpacing: 0.3,
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: justGenerated ? tc.orange : tc.border,
            width: justGenerated ? 1.5 : 1,
          ),
        ),
        child: TextField(
          controller: controller,
          readOnly: true,
          enableInteractiveSelection: false,
          showCursor: false,
          obscureText: !visible,
          obscuringCharacter: '●',
          style: TextStyle(
            fontSize: 16,
            color: tc.text,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: '----',
            hintStyle: TextStyle(
              fontSize: 16,
              color: tc.muted,
              letterSpacing: 4,
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: hasPin ? onToggle : null,
                  tooltip: hasPin
                      ? (visible ? 'Hide PIN' : 'Show PIN')
                      : 'No PIN saved - tap Regenerate',
                  icon: Icon(
                    visible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                    color: hasPin ? tc.orange : tc.muted,
                  ),
                  splashRadius: 18,
                ),
                IconButton(
                  onPressed: hasPin
                      ? () {
                    final p = controller.text.trim();
                    if (p.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: p));
                    _snack('PIN copied to clipboard.');
                  }
                      : null,
                  tooltip: hasPin ? 'Copy PIN' : 'No PIN to copy',
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: hasPin ? tc.orange : tc.muted,
                  ),
                  splashRadius: 18,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Icon(
          hasPin ? Icons.auto_awesome_rounded : Icons.info_outline_rounded,
          size: 10,
          color: hasPin ? tc.orange : tc.muted,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            hasPin
                ? (justGenerated
                ? 'New PIN - tap the eye icon to view'
                : 'Saved PIN - tap the eye icon to view')
                : 'No saved PIN - tap Regenerate',
            style: TextStyle(
              fontSize: 10,
              color: hasPin ? tc.orange : tc.muted,
              fontStyle: FontStyle.italic,
              height: 1.3,
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _addGenderField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'GENDER',
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
          border: Border.all(color: tc.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _addGender,
            isExpanded: true,
            dropdownColor: tc.card,
            icon: Icon(Icons.keyboard_arrow_down_rounded,
                color: tc.text, size: 22),
            style: TextStyle(
              fontSize: 15,
              color: tc.text,
              fontWeight: FontWeight.w500,
            ),
            items: _genderOptions
                .map((g) => DropdownMenuItem<String>(
              value: g,
              child: Text(g == 'male' ? 'Male' : 'Female'),
            ))
                .toList(),
            onChanged: (v) => setState(() => _addGender = v ?? 'male'),
          ),
        ),
      ),
    ]);
  }

  Widget _addDeptField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          border: Border.all(color: tc.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _addDepartmentDropdown,
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
            items: _departmentOptions
                .map((d) => DropdownMenuItem<String>(
              value: d,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() {
              _addDepartmentDropdown = v;
              _addDeptCtrl.text = v ?? '';
              _addPositionDropdown = null;
              _addRoleCtrl.text = '';
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _addPosField() {
    final dept = _addDepartmentDropdown ?? '';
    final deptPos = _positionsForDept(dept);
    final options = deptPos.isNotEmpty ? deptPos : _allPositionOptions;
    String? value;
    final current = _addPositionDropdown ?? _addRoleCtrl.text.trim();
    if (current.isNotEmpty && options.contains(current)) value = current;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'ROLE / POSITION',
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
          border: Border.all(color: tc.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(
              dept.isEmpty ? 'Select department first' : 'Select position',
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
            items: options
                .map((r) => DropdownMenuItem<String>(
              value: r,
              child: Text(r, overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() {
              _addPositionDropdown = v;
              _addRoleCtrl.text = v ?? '';
            }),
          ),
        ),
      ),
    ]);
  }

  // ═════════════════════════════════════════════════════════════════
  // Edit page
  // ═════════════════════════════════════════════════════════════════
  void _openEdit(Map<String, dynamic> emp) {
    _initEditControllers(emp);
    setState(() {
      _selectedProfileEmp = emp;
      _isEditingEmployee = true;
      _editPhotoXFile = null;
      _editPhotoBytes = null;
    });
  }

  void _initEditControllers(Map<String, dynamic> emp) {
    final photoUrl = _s(emp['photoUrl'], '').isNotEmpty
        ? _s(emp['photoUrl'], '')
        : _s(emp['photo'], '');
    final empId = _s(emp['employeeId'], _s(emp['id'], ''));
    _editPhotoUrl = photoUrl.isNotEmpty && photoUrl != '—' ? photoUrl : null;

    final fullName =
    '${_s(emp['firstName'], '')} ${_s(emp['lastName'], '')}'.trim();
    _editFullNameCtrl.text = fullName.isEmpty ? _nameOf(emp) : fullName;
    _editEmailCtrl.text = _s(emp['email'], '');
    _editPhoneCtrl.text = _s(emp['phone'], _s(emp['mobile'], ''));
    _editRoleCtrl.text = _s(emp['role'], '');
    _editDeptCtrl.text = _s(emp['department'], '');
    _editKeyfobCtrl.text = _s(emp['nfcTagId'], _s(emp['nfcId'], ''));

    // SECURITY: Do not read plaintext PIN from Firestore.
    _editPinCtrl.text = '';
    _editPinJustGenerated = false;
    _editPinVisible = false;
    _editPinSaving = false;

    _editDeviceNameCtrl.text = _s(emp['deviceName'], '');
    _editEmployeeIdCtrl.text = empId;
    _editOriginalEmployeeId = empId;

    // ✅ IDINAGDAG: I-load ang Leave Balances
    _editAnnualLeaveCtrl.text = _annualLeaveTotalOf(emp).toString();
    _editSickLeaveCtrl.text = _sickLeaveTotalOf(emp).toString();

    final g = _s(emp['gender'], 'male').toLowerCase();
    _editGender =
    (g == 'female' || g == 'f' || g == 'babae') ? 'female' : 'male';

    final basic = _moneyOf(emp['basicSalary']);
    final allow = _moneyOf(emp['basicAllowance'] ?? emp['allowances']);
    final role = _s(emp['role'], 'Employee');
    _editBasicSalaryCtrl.text =
        (basic > 0 ? basic : _basicSalaryForRole(role)).toStringAsFixed(2);
    _editAllowancesCtrl.text =
        (allow > 0 ? allow : _allowancesForRole(role)).toStringAsFixed(2);
    _editDailyRateCtrl.text =
        (_parseMoneyStr(_editBasicSalaryCtrl.text) / kWorkingDaysPerMonth)
            .toStringAsFixed(2);
    _editBankNameCtrl.text = _s(emp['bankName'], '');
    _editAccountNumberCtrl.text = _s(emp['accountNumber'], '');

    final bd = _toDateTime(emp['birthday'] ?? emp['birthDate']);
    _editBirthday = bd;
    _editBirthdayCtrl.text = bd == null ? '' : _fmtDate(bd, f: '');

    _editDepartmentDropdown = _departmentOptions.contains(_editDeptCtrl.text)
        ? _editDeptCtrl.text
        : null;

    final curRole = _editRoleCtrl.text.trim();
    final deptPos = _positionsForDept(_editDepartmentDropdown ?? '');
    _editPositionDropdown = (curRole.isNotEmpty &&
        (deptPos.contains(curRole) ||
            _allPositionOptions.contains(curRole)))
        ? curRole
        : null;
  }

  Widget _buildEditPage(Map<String, dynamic> emp) {
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
              children: [
                GestureDetector(
                  onTap: () => setState(() {
                    _isEditingEmployee = false;
                    _editPhotoXFile = null;
                    _editPhotoBytes = null;
                  }),
                  child: const Text(
                    'Back to Profile',
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
                LayoutBuilder(builder: (context, c) {
                  final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
                  final photo = _editPhotoCard();
                  final form = Column(children: [
                    _editPersonalCard(),
                    const SizedBox(height: 16),
                    _editSalaryCard(),
                    const SizedBox(height: 16),
                    _editLeaveCard(), // ✅ IDINAGDAG: Leave Balances Card
                    const SizedBox(height: 16),
                    _editSecurityCard(),
                    const SizedBox(height: 16),
                    _editActions(emp),
                  ]);
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photo,
                        const SizedBox(height: 16),
                        form,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 312, child: photo),
                      const SizedBox(width: 16),
                      Expanded(child: form),
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

  Widget _editPhotoCard() {
    final hasNew = _editPhotoXFile != null;
    final displayUrl = _editPhotoUrl;
    final hasUrl = displayUrl != null && displayUrl != '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE)),
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
              border: Border.all(color: const Color(0xFFDDC1AE)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _editPhotoUploading
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFFF8C00)),
                    SizedBox(height: 12),
                    Text(
                      'Processing photo...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFF8C00),
                      ),
                    ),
                  ],
                ),
              )
                  : hasNew && kIsWeb && _editPhotoBytes != null
                  ? Image.memory(
                _editPhotoBytes!,
                fit: BoxFit.cover,
                width: double.infinity,
              )
                  : hasNew && !kIsWeb
                  ? Image.file(
                File(_editPhotoXFile!.path),
                fit: BoxFit.cover,
                width: double.infinity,
              )
                  : hasUrl
                  ? _buildPhoto(
                displayUrl,
                null,
                null,
                BoxFit.cover,
                Icon(Icons.person, size: 80, color: tc.muted),
              )
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 64, color: tc.muted),
                  const SizedBox(height: 8),
                  Text(
                    'No Photo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tc.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Profile Photo',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Profile photo - used as a reference for the employee\'s profile.',
            style: TextStyle(fontSize: 14, color: tc.muted, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _editPhotoUploading ? null : _pickEditPhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF8C00),
                  side: const BorderSide(color: Color(0xFFFF8C00)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.photo_library_rounded, size: 16),
                label: Text(
                  hasNew ? 'Change Photo' : 'Edit Photo',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
            if (hasNew) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _editPhotoUploading
                    ? null
                    : () => setState(() {
                  _editPhotoXFile = null;
                  _editPhotoBytes = null;
                }),
                icon: const Icon(Icons.close_rounded,
                    color: Color(0xFFEF4444), size: 20),
                style: IconButton.styleFrom(
                  backgroundColor:
                  const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _editPersonalCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE)),
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
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final fields = [
              _editField('FULL NAME', _editFullNameCtrl, maxLen: 100),
              _editField('EMAIL ADDRESS', _editEmailCtrl, maxLen: 120),
              _editBirthdayField(),
              _editField('PHONE NO.', _editPhoneCtrl, maxLen: 20),
              _editDeptField(),
              _editRoleField(),
              _editField('EMPLOYEE ID', _editEmployeeIdCtrl, maxLen: 30),
              _editGenderField(),
            ];
            if (narrow) {
              return Column(
                  children: fields
                      .map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: f,
                  ))
                      .toList());
            }
            return Column(children: [
              Row(children: [
                Expanded(child: fields[0]),
                const SizedBox(width: 16),
                Expanded(child: fields[1]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: fields[2]),
                const SizedBox(width: 16),
                Expanded(child: fields[3]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: fields[4]),
                const SizedBox(width: 16),
                Expanded(child: fields[5]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: fields[6]),
                const SizedBox(width: 16),
                Expanded(child: fields[7]),
              ]),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _editSalaryCard() {
    final basic = _parseMoneyStr(_editBasicSalaryCtrl.text);
    final allow = _parseMoneyStr(_editAllowancesCtrl.text);
    final daily = basic / kWorkingDaysPerMonth;
    final total = basic + allow;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.payments_outlined,
                color: Color(0xFFFF8C00), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Compensation & Payroll',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.4)),
              ),
              child: const Text(
                'EDITABLE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF8C00),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Basic & Allowances are bounded to 5,000-500,000 basic, 0-100,000 allowance.',
            style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF8C00).withValues(alpha: 0.12),
                  const Color(0xFFFF8C00).withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT ROLE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tc.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _s(_editRoleCtrl.text, 'Employee'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF904D00),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'MONTHLY TOTAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tc.muted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PHP ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF8C00),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final f1 = _editMoneyInput(
              'BASIC SALARY (/month)',
              _editBasicSalaryCtrl,
              onChanged: () => setState(_recomputeDailyRate),
            );
            final f2 = _editMoneyInput(
              'ALLOWANCES (/month)',
              _editAllowancesCtrl,
              onChanged: () => setState(() {}),
            );
            if (narrow) {
              return Column(children: [
                f1,
                const SizedBox(height: 14),
                f2,
                const SizedBox(height: 14),
                _editDailyRateField(daily),
                const SizedBox(height: 14),
                _editField('BANK NAME', _editBankNameCtrl, maxLen: 80),
                const SizedBox(height: 14),
                _editField('ACCOUNT NUMBER', _editAccountNumberCtrl,
                    maxLen: 30),
              ]);
            }
            return Column(children: [
              Row(children: [
                Expanded(child: f1),
                const SizedBox(width: 16),
                Expanded(child: f2),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _editDailyRateField(daily)),
                const SizedBox(width: 16),
                Expanded(child: _editWorkingDaysField()),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child:
                    _editField('BANK NAME', _editBankNameCtrl, maxLen: 80)),
                const SizedBox(width: 16),
                Expanded(
                  child: _editField('ACCOUNT NUMBER', _editAccountNumberCtrl,
                      maxLen: 30),
                ),
              ]),
            ]);
          }),
        ],
      ),
    );
  }

  // ✅ IDINAGDAG: Leave Card
  Widget _editLeaveCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_available_rounded,
                color: Color(0xFFFF8C00), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Leave Balances',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.4)),
              ),
              child: const Text(
                'EDITABLE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF8C00),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Set the total allowed leaves for this employee per year. Used remaining leaves are calculated automatically.',
            style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final f1 = _editField('ANNUAL LEAVE TOTAL (Days)', _editAnnualLeaveCtrl,
                maxLen: 3);
            final f2 = _editField('SICK LEAVE TOTAL (Days)', _editSickLeaveCtrl,
                maxLen: 3);
            if (narrow) {
              return Column(children: [
                f1,
                const SizedBox(height: 14),
                f2,
              ]);
            }
            return Row(children: [
              Expanded(child: f1),
              const SizedBox(width: 16),
              Expanded(child: f2),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _editWorkingDaysField() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'WORKING DAYS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tc.text,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: tc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDC1AE)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$kWorkingDaysPerMonth days',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
              Icon(Icons.lock_outline, size: 14, color: tc.muted),
            ],
          ),
        ),
      ]);

  Widget _editMoneyInput(
      String label,
      TextEditingController ctrl, {
        required VoidCallback onChanged,
      }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          color: tc.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDC1AE)),
        ),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'PHP ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tc.orange,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => onChanged(),
              style: TextStyle(
                fontSize: 15,
                color: tc.text,
                fontWeight: FontWeight.w700,
              ),
              cursorColor: tc.orange,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                border: InputBorder.none,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.edit_outlined, size: 14, color: tc.orange),
          ),
        ]),
      ),
    ]);
  }

  Widget _editDailyRateField(double rate) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            'DAILY RATE (/day)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'AUTO',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: tc.orange,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF8C00).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            Text(
              'PHP ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: tc.orange,
              ),
            ),
            Expanded(
              child: Text(
                rate.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tc.orange,
                ),
              ),
            ),
            Icon(Icons.calculate_outlined, size: 14, color: tc.orange),
          ]),
        ),
      ]);

  Widget _editField(
      String label,
      TextEditingController ctrl, {
        bool readOnly = false,
        int maxLen = 100,
      }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          border: Border.all(color: const Color(0xFFDDC1AE)),
        ),
        child: TextField(
          controller: ctrl,
          readOnly: readOnly,
          maxLength: maxLen,
          style: TextStyle(
            fontSize: 15,
            color: tc.text,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: tc.orange,
          decoration: const InputDecoration(
            isDense: true,
            counterText: '',
            contentPadding:
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: InputBorder.none,
          ),
        ),
      ),
    ]);
  }

  Widget _editGenderField() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'GENDER',
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
            border: Border.all(color: const Color(0xFFDDC1AE)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _editGender,
              isExpanded: true,
              dropdownColor: tc.card,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: tc.text, size: 22),
              style: TextStyle(
                fontSize: 15,
                color: tc.text,
                fontWeight: FontWeight.w500,
              ),
              items: _genderOptions
                  .map((g) => DropdownMenuItem<String>(
                value: g,
                child: Text(g == 'male' ? 'Male' : 'Female'),
              ))
                  .toList(),
              onChanged: (v) => setState(() => _editGender = v ?? 'male'),
            ),
          ),
        ),
      ]);

  Widget _editRoleField() {
    final dept = _editDepartmentDropdown ?? _editDeptCtrl.text.trim();
    final deptPos = _positionsForDept(dept);
    final options = <String>[
      ...(deptPos.isNotEmpty ? deptPos : _allPositionOptions),
    ];
    // Isama ang kasalukuyang role (hal. "Employee", "Admin") kahit wala sa listahan
    final savedRole = _editRoleCtrl.text.trim();
    if (savedRole.isNotEmpty && !options.contains(savedRole)) {
      options.add(savedRole);
    }
    String? value;
    final current = _editPositionDropdown ?? _editRoleCtrl.text.trim();
    if (current.isNotEmpty && options.contains(current)) value = current;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'ROLE / POSITION',
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
          border: Border.all(color: const Color(0xFFDDC1AE)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text(
              dept.isEmpty ? 'Select department first' : 'Select position',
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
            items: options
                .map((r) => DropdownMenuItem<String>(
              value: r,
              child: Text(r, overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() {
              _editPositionDropdown = v;
              _editRoleCtrl.text = v ?? '';
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _editBirthdayField() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                _editBirthdayCtrl.text = _fmtDate(pick, f: '');
              });
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDC1AE)),
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
      ]);

  Widget _editDeptField() {
    final current = _editDeptCtrl.text.trim();
    final options = <String>{..._departmentOptions};
    if (current.isNotEmpty && !options.contains(current)) options.add(current);
    final list = options.toList();
    final value =
    _editDepartmentDropdown != null && list.contains(_editDepartmentDropdown)
        ? _editDepartmentDropdown
        : (list.contains(current) ? current : null);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          border: Border.all(color: const Color(0xFFDDC1AE)),
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
            items: list
                .map((d) => DropdownMenuItem<String>(
              value: d,
              child: Text(d, overflow: TextOverflow.ellipsis),
            ))
                .toList(),
            onChanged: (v) => setState(() {
              _editDepartmentDropdown = v;
              _editDeptCtrl.text = v ?? '';
              _editPositionDropdown = null;
              _editRoleCtrl.text = '';
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _editSecurityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDC1AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.security_rounded,
                color: Color(0xFFFF8C00), size: 22),
            const SizedBox(width: 8),
            Text(
              'Security Credentials',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 560;
            final kf = _keyfobField();
            final pin = _lockedPinField(
              '4-DIGIT PIN',
              _editPinCtrl,
              _editPinVisible,
              _editPinJustGenerated,
              _editPinSaving,
                  () => setState(() => _editPinVisible = !_editPinVisible),
              _onGenerateEditPin,
            );
            if (narrow) {
              return Column(children: [
                kf,
                const SizedBox(height: 14),
                pin,
                const SizedBox(height: 14),
                _editField('REGISTERED DEVICE', _editDeviceNameCtrl,
                    maxLen: 60),
              ]);
            }
            return Column(children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: kf),
                  const SizedBox(width: 16),
                  Expanded(child: pin),
                ],
              ),
              const SizedBox(height: 14),
              _editField('REGISTERED DEVICE', _editDeviceNameCtrl,
                  maxLen: 60),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _keyfobField() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            border: Border.all(color: const Color(0xFFDDC1AE)),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _editKeyfobCtrl,
                maxLength: 40,
                style: TextStyle(
                  fontSize: 15,
                  color: tc.text,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: tc.orange,
                decoration: const InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: 'SN: 0000-XXX-00',
                  hintStyle: TextStyle(fontSize: 15, color: Color(0xFFB0B0B0)),
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.wifi_tethering_rounded,
                  size: 18, color: tc.muted),
            ),
          ]),
        ),
      ]);

  Widget _editActions(Map<String, dynamic> emp) {
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 500;
      final cancel = OutlinedButton(
        onPressed: () => setState(() {
          _isEditingEmployee = false;
          _editPhotoXFile = null;
          _editPhotoBytes = null;
        }),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: Color(0xFF897362)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          foregroundColor: const Color(0xFF564334),
        ),
        child: const Text(
          'Cancel',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );
      final done = ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF8C00),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _editSaving ? null : () => _submitEdit(emp),
        child: _editSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child:
          CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
            : const Text(
          'Done',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      );
      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [done, const SizedBox(height: 12), cancel],
        );
      }
      return Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFDDC1AE))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [cancel, const SizedBox(width: 12), done],
        ),
      );
    });
  }

  Future<void> _submitEdit(Map<String, dynamic> emp) async {
    final docId = _s(emp['id'], '');
    if (docId.isEmpty) {
      _snack('Missing employee doc ID.', error: true);
      return;
    }

    final fullName =
    AdminEmployeeService.sanitize(_editFullNameCtrl.text, maxLen: 100);
    final parts = fullName.split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final email =
    AdminEmployeeService.sanitize(_editEmailCtrl.text, maxLen: 120);
    final newId = _editEmployeeIdCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      _snack('Full name is required.', error: true);
      return;
    }
    final emailErr = AdminEmployeeService.validateEmail(email);
    if (emailErr != null) {
      _snack('Error: $emailErr', error: true);
      return;
    }
    final idErr = AdminEmployeeService.validateEmployeeId(newId);
    if (idErr != null) {
      _snack('Error: $idErr', error: true);
      return;
    }

    final basic = _parseMoneyStr(_editBasicSalaryCtrl.text);
    final allow = _parseMoneyStr(_editAllowancesCtrl.text);
    final salaryErr = AdminEmployeeService.validateSalary(basic, allow);
    if (salaryErr != null) {
      _snack('Warning: $salaryErr', error: true);
      return;
    }

    // ✅ IDINAGDAG: Kunin ang bagong leave totals
    final annualLeaveTotal =
        int.tryParse(_editAnnualLeaveCtrl.text) ?? kAdminAnnualLeaveTotal;
    final sickLeaveTotal =
        int.tryParse(_editSickLeaveCtrl.text) ?? kAdminSickLeaveTotal;

    setState(() => _editSaving = true);

    try {
      String? uploadedPhoto;
      if (_editPhotoXFile != null) {
        uploadedPhoto = await _uploadEditPhoto(docId);
        if (uploadedPhoto == null) {
          _snack('Photo upload failed.', error: true);
          return;
        }
      }

      final daily = basic / kWorkingDaysPerMonth;
      final total = basic + allow;
      final newRole = _editRoleCtrl.text.trim();

      final patch = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName',
        'employeeId': newId,
        'email': email,
        'emailLower': email.toLowerCase(),
        'phone': AdminEmployeeService.sanitize(_editPhoneCtrl.text, maxLen: 20),
        'role': newRole,
        'department': _editDeptCtrl.text.trim(),
        'gender': _editGender,
        'nfcTagId': _editKeyfobCtrl.text.trim().toUpperCase(),
        'deviceName': AdminEmployeeService.sanitize(
            _editDeviceNameCtrl.text,
            maxLen: 60),
        'basicSalary': basic,
        'allowances': allow,
        'basicAllowance': allow,
        'dailyRate': daily,
        'monthlyTotal': total,
        'workingDaysPerMonth': kWorkingDaysPerMonth,
        'bankName':
        AdminEmployeeService.sanitize(_editBankNameCtrl.text, maxLen: 80),
        'accountNumber': AdminEmployeeService.sanitize(
            _editAccountNumberCtrl.text,
            maxLen: 30),
        'salaryConfigured': true,

        // ✅ IDINAGDAG: Isama ang leave totals sa update
        'annualLeaveTotal': annualLeaveTotal,
        'sickLeaveTotal': sickLeaveTotal,
      };

      final err = await _svc.updateEmployee(docId: docId, patch: patch);

      if (err != null) {
        _snack('Error: $err', error: true);
        return;
      }

      if (uploadedPhoto != null) {
        try {
          await AdminDatabase.fs.collection('employees').doc(docId).update({
            'photoUrl': uploadedPhoto,
          });
        } catch (e) {
          debugPrint('Failed to update photoUrl directly: $e');
          if (mounted) {
            _snack('Profile saved, but photo failed: $e', error: true);
          }
        }
      }

      if (_editBirthday != null) {
        try {
          await AdminDatabase.fs.collection('employees').doc(docId).update({
            'birthday': Timestamp.fromDate(_editBirthday!),
          });
        } catch (e) {
          debugPrint('Failed to update birthday directly: $e');
        }
      }

      if (!mounted) return;

      _snack('Employee profile updated.');
      setState(() {
        _isEditingEmployee = false;
        _selectedProfileEmp = {
          ...emp,
          ...patch,
          if (uploadedPhoto != null) 'photoUrl': uploadedPhoto,
        };
        _editPhotoXFile = null;
        _editPhotoBytes = null;
        _editPinJustGenerated = false;
        _editPinVisible = false;
      });
      widget.onRefreshNeeded();
    } finally {
      if (mounted) setState(() => _editSaving = false);
    }
  }

  Future<void> _pickEditPhoto() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: tc.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tc.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFFFF8C00)),
              title:
              Text('Choose from Gallery', style: TextStyle(color: tc.text)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFFFF8C00)),
              title: Text('Take a Photo', style: TextStyle(color: tc.text)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (source == null) return;

      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      Uint8List? bytes;
      if (kIsWeb) bytes = await picked.readAsBytes();

      setState(() {
        _editPhotoXFile = picked;
        _editPhotoBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to pick image: $e', error: true);
    }
  }

  Future<String?> _uploadEditPhoto(String docId) async {
    if (_editPhotoXFile == null) return _editPhotoUrl;
    setState(() => _editPhotoUploading = true);
    try {
      final raw = _editPhotoBytes ?? await _editPhotoXFile!.readAsBytes();
      final compressed = _compressForFirestore(raw);
      if (compressed == null) {
        _snack('Failed to compress image.', error: true);
        return null;
      }
      final b64 = base64Encode(compressed).replaceAll(RegExp(r'\s'), '');
      if (b64.length > 900 * 1024) {
        _snack('Photo too large even after compression.', error: true);
        return null;
      }
      return 'data:image/jpeg;base64,$b64';
    } catch (e) {
      if (mounted) _snack('Photo failed: $e', error: true);
      return null;
    } finally {
      if (mounted) setState(() => _editPhotoUploading = false);
    }
  }

  Uint8List? _compressForFirestore(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;
      const maxDim = 600;
      img.Image resized = decoded;
      if (decoded.width > maxDim || decoded.height > maxDim) {
        resized = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDim : null,
          height: decoded.height > decoded.width ? maxDim : null,
          interpolation: img.Interpolation.average,
        );
      }
      var out = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      if (out.length < 400 * 1024) return out;
      out = Uint8List.fromList(img.encodeJpg(resized, quality: 50));
      if (out.length < 400 * 1024) return out;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 35));
    } catch (e) {
      return bytes;
    }
  }

  Future<void> _onGenerateEditPin() async {
    if (_editPinSaving) return;

    final emp = _selectedProfileEmp;
    final docId = emp != null ? _s(emp['id'], '') : '';
    if (docId.isEmpty) {
      _snack('Employee doc ID not found.', error: true);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Regenerate PIN?', style: TextStyle(color: tc.text)),
        content: Text(
          'The old PIN will no longer work. The new PIN will be shown only once.',
          style: TextStyle(color: tc.text, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    setState(() => _editPinSaving = true);

    try {
      final docRef = AdminDatabase.fs.collection('employees').doc(docId);
      final snap = await docRef.get();

      if (!mounted) return;

      if (!snap.exists) {
        _snack('Employee document not found (id: $docId).', error: true);
        setState(() => _editPinSaving = false);
        return;
      }

      String? newPin;
      Object? serviceError;
      try {
        newPin = await _svc.regeneratePin(docId);
      } catch (e, st) {
        serviceError = e;
        debugPrint('regeneratePin threw: $e\n$st');
      }

      if (newPin == null) {
        debugPrint(
            'Service returned null (error: $serviceError). Generating locally...');
        newPin = AdminEmployeeService.generatePin(
          current: _editPinCtrl.text,
        );
      }

      final salt = _randomSalt();
      final hash = _saltedHash(newPin, salt);

      PendingEditRestore.shouldRestore = true;
      PendingEditRestore.docId = docId;
      PendingEditRestore.newPin = newPin;

      await docRef.update({
        // SECURITY: Do not save plaintext PIN to Firestore
        'pinHash': hash,
        'pinSalt': salt,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
        'pinUpdatedBy': _actorEmail,
        'requiresPinChange': true,
      });

      debugPrint('PIN regenerated for $docId');

      if (!mounted) return;

      setState(() {
        _editPinCtrl.text = newPin!;
        _editPinJustGenerated = true;
        _editPinVisible = true;
        _editPinSaving = false;
        _isEditingEmployee = true;
        if (_selectedProfileEmp != null) {
          _selectedProfileEmp = {
            ..._selectedProfileEmp!,
            'pinUpdatedAt': DateTime.now(),
            'requiresPinChange': true,
          };
        }
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('New PIN: $newPin\nTap the copy icon to copy.'),
          backgroundColor: tc.green,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, st) {
      debugPrint('Regenerate PIN failed: $e\n$st');
      if (!mounted) return;

      setState(() => _editPinSaving = false);

      messenger.showSnackBar(
        SnackBar(
          content: Text('Failed to regenerate PIN: $e'),
          backgroundColor: tc.red,
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  String _randomSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _saltedHash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ═════════════════════════════════════════════════════════════════
  // Confirmations
  // ═════════════════════════════════════════════════════════════════
  // FIX #2: writes faceAdminResetAt so the device can wipe its template.
  Future<void> _confirmResetLiveness(Map<String, dynamic> emp) async {
    final docId = _s(emp['id'], '');
    final name = _nameOf(emp);
    if (docId.isEmpty) {
      _snack('Missing employee doc ID.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Reset liveness?', style: TextStyle(color: tc.text)),
        content: Text(
          'The employee will need to re-enroll (blink + smile) on their device. '
              'Their encrypted face template will be deleted from the device on the next sync.',
          style: TextStyle(color: tc.text, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    try {
      await AdminDatabase.fs.collection('employees').doc(docId).update({
        // Clear boolean liveness state
        kLivenessVerifiedField: false,
        kLivenessVerifiedAtField: FieldValue.delete(),
        'livenessSource': FieldValue.delete(),
        'livenessCheckCount': 0,

        // REQUIRED: lets the mobile client detect the admin reset, wipe its
        // locally-encrypted template, and re-enable enrollment.
        'faceAdminResetAt': FieldValue.serverTimestamp(),
        'faceAdminResetBy': _actorEmail,

        // Payagan ulit ang enrollment pagkatapos ng reset
        'faceEnrolled': false,
        'faceEnrolledAt': FieldValue.delete(),
        'faceEnrollAllowed': true,
      });

      _snack(
          'Liveness reset for $name. Device will wipe its template on next sync.');
      widget.onRefreshNeeded();
    } catch (e) {
      _snack('Failed to reset liveness: $e', error: true);
    }
  }

  Future<void> _confirmTerminate(String docId, String name) async {
    if (docId.isEmpty) {
      _snack('Missing employee doc ID.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Terminate employee?', style: TextStyle(color: tc.text)),
        content: Text(
          'This will mark $name as terminated. They will no longer be able to log in.',
          style: TextStyle(color: tc.text, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    try {
      await AdminDatabase.fs.collection('employees').doc(docId).update({
        'terminated': true,
        'terminatedAt': FieldValue.serverTimestamp(),
        'terminatedBy': _actorEmail,
        'isOnline': false,
        'isLoggedIn': false,
      });
      _snack('$name terminated.');
      widget.onRefreshNeeded();
    } catch (e) {
      _snack('Failed to terminate: $e', error: true);
    }
  }

  /// Binubura ang lahat ng docs sa isang collection (batched, 400 per batch).
  /// Ini-skip ang protected collections.
  Future<int> _deleteCollection(String col) async {
    if (_protectedCollections.contains(col)) return 0;
    var total = 0;
    while (true) {
      final snap = await AdminDatabase.fs.collection(col).limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = AdminDatabase.fs.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      total += snap.docs.length;
    }
    return total;
  }

  Future<void> _confirmWipeAllLogs() async {
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: tc.card,
          title: Text('Clear ALL data?', style: TextStyle(color: tc.red)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes ALL employees, logs, reports and '
                'other data from the database. Only "admins" and '
                '"system_config" are kept. This cannot be undone.',
                style: TextStyle(color: tc.text, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text('Type DELETE to confirm:',
                  style: TextStyle(color: tc.muted, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autofillHints: const <String>[],
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setD(() {}),
                style: TextStyle(color: tc.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: tc.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text('Cancel', style: TextStyle(color: tc.muted)),
            ),
            ElevatedButton(
              onPressed: confirmCtrl.text.trim() == 'DELETE'
                  ? () => Navigator.of(dialogCtx).pop(true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: tc.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear Everything'),
            ),
          ],
        ),
      ),
    );
    confirmCtrl.dispose();
    if (ok != true) return;
    if (!mounted) return;

    _snack('Clearing data... please wait.');

    var count = 0;
    final failed = <String>[];
    for (final col in _wipeCollections) {
      try {
        count += await _deleteCollection(col);
      } catch (e) {
        debugPrint('Failed to clear $col: $e');
        failed.add(col);
      }
    }

    if (!mounted) return;
    if (failed.isEmpty) {
      _snack('Cleared $count documents. Admins & system_config kept.');
    } else {
      _snack(
        'Cleared $count docs. Failed: ${failed.join(', ')} '
        '(check Firestore rules).',
        error: true,
      );
    }
    widget.onRefreshNeeded();
  }

  // ═════════════════════════════════════════════════════════════════
  // Profile page
  // ═════════════════════════════════════════════════════════════════
  Widget _buildProfilePage(Map<String, dynamic> emp) {
    final docId = _s(emp['id'], '');
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final empCode = _s(emp['employeeId'], docId);
    final genderLabel =
    _s(emp['gender'], 'male').toLowerCase() == 'female' ? 'Female' : 'Male';
    final joining = _fmtDate(
      emp['joiningDate'] ?? emp['createdAt'] ?? emp['created_at'],
      f: 'Not Specified',
    );
    final isActive = _isActive(emp);
    final nfc = _s(emp['nfcTagId'], 'NOT ASSIGNED');

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
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _selectedProfileEmp = null),
                  icon: Icon(Icons.arrow_back_rounded, color: tc.muted),
                  label: Text(
                    'Back to Directory',
                    style: TextStyle(
                      color: tc.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Employee Profile',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: tc.text,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 24),
                _profileTop(emp, name, role, dept, email, phone, empCode,
                    joining, isActive, nfc, genderLabel),
                const SizedBox(height: 24),
                _attendanceAndLeaveSection(docId, emp),
                const SizedBox(height: 24),
                _devicesSection(docId, emp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileTop(
      Map<String, dynamic> emp,
      String name,
      String role,
      String dept,
      String email,
      String phone,
      String id,
      String joining,
      bool isActive,
      String nfc,
      String genderLabel,
      ) {
    return LayoutBuilder(builder: (context, c) {
      final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
      final left = _mainProfileCard(
          emp, name, role, dept, email, phone, id, joining, isActive,
          genderLabel);
      final right = _securityCard(emp, nfc);
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 20), right],
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

  Widget _mainProfileCard(
      Map<String, dynamic> emp,
      String name,
      String role,
      String dept,
      String email,
      String phone,
      String id,
      String joining,
      bool isActive,
      String genderLabel,
      ) {
    final initials = _initialsOf(name);
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
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              Container(
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: tc.orange, width: 2.5),
                ),
                child: _avatarContent(emp, initials, 96, 32, tc.orangeText),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF006E05)
                        : const Color(0xFF857365),
                    shape: BoxShape.circle,
                    border: Border.all(color: tc.card, width: 3.5),
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFFFDCC3)
                            : const Color(0xFFE0E3E6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isActive ? 'ACTIVE' : 'INACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? const Color(0xFF6E3900)
                              : const Color(0xFF44474A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    _livenessPill(_isLivenessVerified(emp)),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                      letterSpacing: -0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF904D00),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('ID: $id',
                      style: TextStyle(fontSize: 13, color: tc.muted)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 32),
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 500;
            final items = [
              _profileDetail(Icons.apartment_rounded, 'Department', dept),
              _profileDetail(Icons.mail_outline_rounded, 'Work Email', email),
              _profileDetail(Icons.phone_outlined, 'Phone', phone),
              _profileDetail(
                  Icons.calendar_today_outlined, 'Joining Date', joining),
              _profileDetail(Icons.wc_rounded, 'Gender', genderLabel),
            ];
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    items[i],
                    if (i < items.length - 1) const SizedBox(height: 20),
                  ],
                ],
              );
            }
            return Column(children: [
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
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.only(right: 24), child: items[4]),
              ),
            ]);
          }),
          const SizedBox(height: 24),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ElevatedButton.icon(
              onPressed: () => _openEdit(emp),
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
              label: const Text(
                'Edit Details',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            OutlinedButton(
              onPressed: () => _downloadPdf(emp),
              style: OutlinedButton.styleFrom(
                foregroundColor: tc.text,
                backgroundColor: tc.card,
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                side: BorderSide(color: tc.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                'Download Profile',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _profileDetail(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: tc.text,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _securityCard(Map<String, dynamic> emp, String nfc) {
    final nfcOk = nfc.isNotEmpty && nfc != 'NOT ASSIGNED';
    final hasPhoto = _hasProfilePhoto(emp);
    final verified = _isLivenessVerified(emp);
    final count = _livenessCheckCountOf(emp);

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
              child: Text(
                'Security Credentials',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _credBox('NFC / KEYFOB ID', nfc, nfcOk,
              nfcOk ? 'Assigned' : 'Not assigned'),
          const SizedBox(height: 12),
          _credBox(
              'ACCESS PIN', '•••••  (salted hash)', true, 'PIN configured'),
          if (_s(emp['deviceName'], '').isNotEmpty &&
              _s(emp['deviceName'], '') != '—') ...[
            const SizedBox(height: 12),
            _credBox('REGISTERED DEVICE', _s(emp['deviceName'], 'NOT SET'),
                true, 'Device bound'),
          ],
          const SizedBox(height: 12),
          _livenessStatusCard(emp),
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
                Text(
                  'AUTH STATUS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tc.muted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: _statusItem(Icons.photo_camera_rounded, 'Photo',
                        hasPhoto, 'Uploaded', 'No Photo'),
                  ),
                  Expanded(
                    child: _statusItem(Icons.verified_user_rounded, 'Liveness',
                        verified, 'Passed', 'Not Passed'),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  verified
                      ? 'Liveness: passed  •  Checks: $count'
                      : 'Liveness check not passed yet.',
                  style: TextStyle(
                    fontSize: 11,
                    color: verified ? const Color(0xFF166534) : tc.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credBox(String label, String value, bool ok, String subtitle) {
    final fg = ok ? const Color(0xFF166534) : tc.muted;
    final bg = ok ? const Color(0xFFDCFCE7) : tc.surface;
    final border = ok ? const Color(0xFF16A34A) : tc.border;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tc.text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11, color: fg)),
        ],
      ),
    );
  }

  Widget _livenessStatusCard(Map<String, dynamic> emp) {
    final verified = _isLivenessVerified(emp);
    final at = _livenessVerifiedAt(emp);
    final src = _livenessSourceOf(emp);
    final count = _livenessCheckCountOf(emp);
    final fg = verified ? const Color(0xFF166534) : const Color(0xFF6B7280);
    final bg = verified ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    final border =
    verified ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              verified
                  ? Icons.verified_user_rounded
                  : Icons.person_off_rounded,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: 8),
            Text(
              'LIVENESS CHECK',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.5,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            verified ? 'Passed' : 'Not Passed',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (verified && at != null) ...[
            const SizedBox(height: 4),
            Text(
              'Verified ${_fmtDate(at)} ${_fmtTime(at)}',
              style: TextStyle(fontSize: 11, color: fg),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Source: $src  •  Checks: $count',
            style: TextStyle(fontSize: 11, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _statusItem(
      IconData icon, String label, bool ok, String okText, String failText) {
    final fg = ok ? const Color(0xFF166534) : tc.muted;
    return Row(
      children: [
        Icon(icon, size: 18, color: ok ? const Color(0xFF16A34A) : tc.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tc.muted,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ok ? okText : failText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attendanceAndLeaveSection(String docId, Map<String, dynamic> emp) {
    final annualTotal = _annualLeaveTotalOf(emp);
    final sickTotal = _sickLeaveTotalOf(emp);
    final annualUsed = _safeInt(emp['annualLeaveUsed'], 0);
    final sickUsed = _safeInt(emp['sickLeaveUsed'], 0);
    final annualLeft = (annualTotal - annualUsed).clamp(0, annualTotal);
    final sickLeft = (sickTotal - sickUsed).clamp(0, sickTotal);

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
            Icon(Icons.event_note_rounded, size: 22, color: tc.orange),
            const SizedBox(width: 8),
            Text(
              'Attendance & Leave',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 560;
            final annual = _leaveTile('ANNUAL LEAVE', annualLeft, annualTotal,
                const Color(0xFF904D00));
            final sick = _leaveTile('SICK LEAVE', sickLeft, sickTotal,
                const Color(0xFF1D4ED8));
            final days = _leaveTile('WORKING DAYS / MONTH',
                kWorkingDaysPerMonth, kWorkingDaysPerMonth,
                const Color(0xFF166534));
            if (narrow) {
              return Column(children: [
                annual,
                const SizedBox(height: 12),
                sick,
                const SizedBox(height: 12),
                days,
              ]);
            }
            return Row(children: [
              Expanded(child: annual),
              const SizedBox(width: 12),
              Expanded(child: sick),
              const SizedBox(width: 12),
              Expanded(child: days),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _leaveTile(String label, int remaining, int total, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tc.muted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$remaining',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                ' / $total',
                style: TextStyle(fontSize: 13, color: tc.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : remaining / total,
              minHeight: 4,
              backgroundColor: tc.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _devicesSection(String docId, Map<String, dynamic> emp) {
    final deviceName = _s(emp['deviceName'], '');
    final nfc = _s(emp['nfcTagId'], '');
    final lastLogin = _toDateTime(emp['lastLogin'] ?? emp['lastActive']);
    final hasDevice = deviceName.isNotEmpty && deviceName != '—';
    final hasNfc = nfc.isNotEmpty && nfc != '—';
    final hasLast = lastLogin != null;

    Widget row(IconData icon, String label, String value, bool ok) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.border),
        ),
        child: Row(children: [
          Icon(icon,
              size: 18, color: ok ? const Color(0xFF166534) : tc.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tc.muted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tc.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ]),
      );
    }

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
            Icon(Icons.devices_rounded, size: 22, color: tc.orange),
            const SizedBox(width: 8),
            Text(
              'Devices & Access',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: tc.text,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          row(Icons.phone_iphone_rounded, 'REGISTERED DEVICE',
              hasDevice ? deviceName : 'Not registered', hasDevice),
          row(Icons.wifi_tethering_rounded, 'NFC / KEYFOB SERIAL',
              hasNfc ? nfc : 'Not assigned', hasNfc),
          row(
              Icons.access_time_rounded,
              'LAST ACTIVITY',
              hasLast
                  ? '${_fmtDate(lastLogin)} ${_fmtTime(lastLogin)}'
                  : 'No activity yet',
              hasLast),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // PDF download
  // ═════════════════════════════════════════════════════════════════
  Future<void> _downloadPdf(Map<String, dynamic> emp) async {
    try {
      final name = _nameOf(emp);
      final role = _s(emp['role'], '—');
      final dept = _s(emp['department'], '—');
      final email = _s(emp['email'], '—');
      final phone = _s(emp['phone'], _s(emp['mobile'], '—'));
      final id = _s(emp['employeeId'], _s(emp['id'], '—'));
      final joining = _fmtDate(
        emp['joiningDate'] ?? emp['createdAt'] ?? emp['created_at'],
        f: 'Not Specified',
      );
      final gender = _s(emp['gender'], '—');

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => [
            pw.Header(level: 0, text: 'Employee Profile'),
            pw.SizedBox(height: 12),
            pw.Text(
              name,
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('$role  •  $dept'),
            pw.Divider(),
            pw.SizedBox(height: 12),
            _pdfRow('Employee ID', id),
            _pdfRow('Email', email),
            _pdfRow('Phone', phone),
            _pdfRow('Gender', gender),
            _pdfRow('Joining Date', joining),
          ],
        ),
      );

      final bytes = await doc.save();
      final safeId = id.isEmpty ? 'profile' : id;
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'employee_$safeId.pdf',
      );
    } catch (e) {
      _snack('Failed to generate PDF: $e', error: true);
    }
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Dashed border used by the "Quick Invite" card
// ═════════════════════════════════════════════════════════════════════
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;

  _DashedBorderPainter({
    required this.color,
    this.radius = 12,
  })  : dash = 6,
        gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = (d + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
          old.radius != radius ||
          old.dash != dash ||
          old.gap != gap;
}