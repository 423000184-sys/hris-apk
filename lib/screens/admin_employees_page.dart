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
import '../services/face_matcher.dart';
import '../services/admin_notification_service.dart';
import '../services/admin_employee_service.dart';

// ─── CONSTANTS ───
const int kAdminAnnualLeaveTotal = 18;
const int kAdminSickLeaveTotal = 18;
const int kCurrentFaceVersion = 4;
const int kWorkingDaysPerMonth = 22;

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

// ─── SCROLL BEHAVIOR ───
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
  AdminColors get tc => AdminTheme.getColors(context);

  String get _actorEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ??
          'unknown';
  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

  // ─── EDIT CONTROLLERS ───
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

  DateTime? _editBirthday;
  String? _editDepartmentDropdown;
  String? _editPositionDropdown;
  bool _editSaving = false;
  bool _isEditingEmployee = false;
  bool _editWfhAccess = false;
  String _editOriginalEmployeeId = '';
  String _editGender = 'male';
  bool _editPinVisible = false;
  bool _editPinJustGenerated = false;
  bool _editPinSaving = false;
  bool _editFaceResetting = false;

  XFile? _editPhotoXFile;
  Uint8List? _editPhotoBytes;
  bool _editPhotoUploading = false;
  String? _editPhotoUrl;

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

  // ─── ADD CONTROLLERS ───
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

  // ─── FILTERS ───
  final _filterCtrl = TextEditingController();
  String _filterText = '';
  String _department = 'All Departments';
  String _position = 'All Positions';
  String _sort = 'A-Z';
  String _fpFilter = 'All';
  String _faceFilter = 'All'; // 🆕
  int _page = 0;
  static const int _pageSize = 6;

  Map<String, dynamic>? _selectedProfileEmp;
  final Set<String> _selectedEmpIds = {};
  bool _bulkTerminating = false;
  bool _bulkSelectMode = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🟢 [AdminEmployeesPage] initState — State CREATED');
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
      _editWfhAccess = _isWfhEnabled(emp);
      _editPhotoXFile = null;
      _editPhotoBytes = null;
      if (PendingEditRestore.newPin != null) {
        _editPinCtrl.text = PendingEditRestore.newPin!;
        _editPinJustGenerated = true;
        _editPinVisible = true;
        _editPinSaving = false;
      }
    });
    debugPrint('🔧 Restored edit view for $docId '
        '(PIN: ${PendingEditRestore.newPin})');

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
    debugPrint('🔴 [AdminEmployeesPage] dispose — State DESTROYED');
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

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
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
    if (status == 'online' || status == 'logged_in') return true;
    final last = _toDateTime(e['lastLogin'] ?? e['lastActive']);
    if (last != null && DateTime.now().difference(last).inMinutes <= 15) {
      return true;
    }
    return false;
  }

  bool _isWfhEnabled(Map<String, dynamic> e) {
    final v = e['wfhAccess'];
    if (v is bool) return v;
    return _s(v).toLowerCase() == 'true';
  }

  bool _canUseWfh(Map<String, dynamic> e) {
    final r = _s(e['role'], '').toLowerCase();
    return !(r.contains('driver') || r.contains('drayber'));
  }

  bool _hasProfilePhoto(Map<String, dynamic> e) {
    final u = _s(e['photoUrl'], '');
    return u.isNotEmpty && u != '—';
  }

  int _faceVersionOf(Map<String, dynamic> e) =>
      _safeInt(e['faceEmbeddingVersion'], 1);
  int _faceCountOf(Map<String, dynamic> e) =>
      _safeInt(e['faceEmbeddingsCount'], 0);
  bool _hasCurrentFaceVersion(Map<String, dynamic> e) =>
      _faceVersionOf(e) == kCurrentFaceVersion && _faceCountOf(e) > 0;

  // 🆕 Face enrollment helpers
  bool _isFaceEnrolled(Map<String, dynamic> e) => _hasCurrentFaceVersion(e);

  DateTime? _faceEnrolledAt(Map<String, dynamic> e) =>
      _toDateTime(e['faceEmbeddingUpdatedAt']);

  String _faceSourceOf(Map<String, dynamic> e) =>
      _s(e['faceEmbeddingSource'], '—');

  // ═══════════════════════════════════════════════════════════════
  // 🔐 FINGERPRINT HELPERS
  // ═══════════════════════════════════════════════════════════════
  bool _isFingerprintEnrolled(Map<String, dynamic> e) {
    final v = e['fingerprintEnrolled'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  DateTime? _fingerprintEnrolledAt(Map<String, dynamic> e) =>
      _toDateTime(e['fingerprintEnrolledAt']);

  String _fingerprintDeviceOf(Map<String, dynamic> e) =>
      _s(e['fingerprintDeviceModel'],
          _s(e['fingerprintDeviceFingerprint'], '—'));

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
    for (final r in _departmentPositionsMap.values) set.addAll(r);
    return set.toList()..sort();
  }

  List<String> get _positions {
    if (_department == 'All Departments') {
      final all = <String>{};
      for (final r in _departmentPositionsMap.values) all.addAll(r);
      return ['All Positions', ...(all.toList()..sort())];
    }
    final d = _departmentPositionsMap[_department] ?? const [];
    return ['All Positions', ...([...d]..sort())];
  }

  void _recomputeDailyRate() {
    final b = _parseMoneyStr(_editBasicSalaryCtrl.text);
    _editDailyRateCtrl.text = (b / kWorkingDaysPerMonth).toStringAsFixed(2);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
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

    var filtered = widget.employees.where((e) {
      if (e['terminated'] == true) return false;
      final hay =
          '${_nameOf(e)} ${_s(e['role'])} ${_s(e['id'])} ${_s(e['department'])}';

      // 🔐 Fingerprint filter
      final fpEnrolled = _isFingerprintEnrolled(e);
      if (_fpFilter == 'Fingerprint ✓' && !fpEnrolled) return false;
      if (_fpFilter == 'No Fingerprint' && fpEnrolled) return false;

      // 🆕 Face filter
      final faceEnrolled = _isFaceEnrolled(e);
      if (_faceFilter == 'Face ✓' && !faceEnrolled) return false;
      if (_faceFilter == 'No Face' && faceEnrolled) return false;

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
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.md);

      final fpCount = widget.employees
          .where((e) => e['terminated'] != true && _isFingerprintEnrolled(e))
          .length;

      // 🆕 Face count
      final faceCount = widget.employees
          .where((e) => e['terminated'] != true && _isFaceEnrolled(e))
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
                'Manage and monitor ${widget.employees.where((e) => e['terminated'] != true).length} active workforce members.',
                style: TextStyle(color: tc.muted, fontSize: 15),
              ),
              // 🔐 Fingerprint badge
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF3B82F6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fingerprint_rounded,
                        size: 12, color: Color(0xFF1E40AF)),
                    const SizedBox(width: 4),
                    Text(
                      '$fpCount with FP',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E40AF),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              // 🆕 Face badge
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
                    const Icon(Icons.face_rounded,
                        size: 12, color: Color(0xFF166534)),
                    const SizedBox(width: 4),
                    Text(
                      '$faceCount with Face',
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

  // ══════════════════════════════════════════════════════════════
  // FILTER BAR
  // ══════════════════════════════════════════════════════════════
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
      final fpDD = _pillDropdown(
        value: _fpFilter,
        items: const [
          'All',
          'Fingerprint ✓',
          'No Fingerprint',
        ],
        prefix: 'FP: ',
        onChanged: (v) => setState(() {
          _fpFilter = v ?? 'All';
          _page = 0;
        }),
      );
      // 🆕 Face filter dropdown
      final faceDD = _pillDropdown(
        value: _faceFilter,
        items: const [
          'All',
          'Face ✓',
          'No Face',
        ],
        prefix: 'Face: ',
        onChanged: (v) => setState(() {
          _faceFilter = v ?? 'All';
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
              Expanded(child: fpDD),
              const SizedBox(width: 10),
              Expanded(child: faceDD),
            ]),
            const SizedBox(height: 10),
            sortDD,
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
        Expanded(flex: 2, child: fpDD),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: faceDD),
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

  // ══════════════════════════════════════════════════════════════
  // DIRECTORY GRID
  // ══════════════════════════════════════════════════════════════
  Widget _directoryGrid(List<Map<String, dynamic>> items) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final cols = r.responsive<int>(xs: 1, sm: 1, md: 2, lg: 3, xl: 3, xxl: 3);
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
    final wfh = _isWfhEnabled(emp);
    final canWfh = _canUseWfh(emp);
    final fpEnrolled = _isFingerprintEnrolled(emp);
    final faceEnrolled = _isFaceEnrolled(emp);
    final genderIcon =
    _s(emp['gender'], 'male').toLowerCase() == 'female' ? '👩' : '👨';
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
                '$genderIcon $name',
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
            _fingerprintPill(fpEnrolled),
            _facePill(faceEnrolled, compact: true),
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: canWfh
                ? _wfhToggle(wfh, (v) => _setWfh(emp, v))
                : _wfhNotApplicable(),
          ),
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
    final wfh = _isWfhEnabled(emp);
    final canWfh = _canUseWfh(emp);
    final fpEnrolled = _isFingerprintEnrolled(emp);
    final faceEnrolled = _isFaceEnrolled(emp);
    final genderIcon =
    _s(emp['gender'], 'male').toLowerCase() == 'female' ? '👩' : '👨';
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
                  _fingerprintPill(fpEnrolled, compact: true),
                  const SizedBox(height: 4),
                  _facePill(faceEnrolled, compact: true),
                ],
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              '$genderIcon $name',
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
            Align(
              alignment: Alignment.centerLeft,
              child: canWfh
                  ? _wfhToggle(wfh, (v) => _setWfh(emp, v), compact: true)
                  : _wfhNotApplicable(compact: true),
            ),
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
        } else if (v == 'reset_face') {
          _confirmResetFace(emp);
        } else if (v == 'delete') {
          _confirmTerminate(_s(emp['id']), name);
        }
      },
      itemBuilder: (_) => [
        _popupItem('profile', Icons.person_outline_rounded, 'View Profile',
            tc.text),
        _popupItem('edit', Icons.edit_outlined, 'Edit Details', tc.orange),
        if (_isFaceEnrolled(emp))
          _popupItem('reset_face', Icons.face_retouching_off_rounded,
              'Reset Face', const Color(0xFFF59E0B)),
        _popupItem('delete', Icons.delete_outline_rounded, 'Terminate', tc.red),
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
          color:
          active ? const Color(0xFF166534) : const Color(0xFF564334),
        ),
      ),
    ]),
  );

  // 🔐 Fingerprint badge
  Widget _fingerprintPill(bool enrolled, {bool compact = false}) {
    final bg = enrolled ? const Color(0xFFDBEAFE) : const Color(0xFFF3F4F6);
    final fg = enrolled ? const Color(0xFF1E40AF) : const Color(0xFF6B7280);
    final border =
    enrolled ? const Color(0xFF3B82F6) : const Color(0xFF9CA3AF);

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
          enrolled ? Icons.fingerprint_rounded : Icons.fingerprint,
          size: compact ? 10 : 11,
          color: fg,
        ),
        SizedBox(width: compact ? 3 : 4),
        Text(
          enrolled ? 'FP' : 'No FP',
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

  // 🆕 Face badge
  Widget _facePill(bool enrolled, {bool compact = false}) {
    final bg = enrolled ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6);
    final fg = enrolled ? const Color(0xFF166534) : const Color(0xFF6B7280);
    final border =
    enrolled ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);

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
          enrolled ? Icons.face_rounded : Icons.face_retouching_off_rounded,
          size: compact ? 10 : 11,
          color: fg,
        ),
        SizedBox(width: compact ? 3 : 4),
        Text(
          enrolled ? 'Face' : 'No Face',
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
    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: fit,
          width: w,
          height: h,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => errorWidget,
        );
      } catch (_) {
        return errorWidget;
      }
    }
    return Image.network(
      url,
      fit: fit,
      width: w,
      height: h,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => errorWidget,
    );
  }

  Widget _wfhToggle(bool enabled, ValueChanged<bool> onChanged,
      {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFDCFCE7) : tc.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: enabled ? const Color(0xFF22C55E) : tc.border,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          enabled ? Icons.home_work_rounded : Icons.home_outlined,
          size: compact ? 14 : 15,
          color: enabled ? const Color(0xFF166534) : tc.muted,
        ),
        const SizedBox(width: 6),
        Text(
          enabled ? 'WFH: ON' : 'WFH: OFF',
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w700,
            color: enabled ? const Color(0xFF166534) : tc.muted,
          ),
        ),
        const SizedBox(width: 4),
        Transform.scale(
          scale: compact ? 0.65 : 0.72,
          child: Switch(
            value: enabled,
            onChanged: onChanged,
            activeColor: const Color(0xFF22C55E),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
    );
  }

  Widget _wfhNotApplicable({bool compact = false}) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 6 : 8,
    ),
    decoration: BoxDecoration(
      color: tc.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tc.border),
    ),
    child: Icon(
      Icons.no_transfer_rounded,
      size: compact ? 14 : 16,
      color: tc.muted,
    ),
  );

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
        _pageArrow(
            Icons.chevron_left_rounded, _page > 0, () => setState(() => _page--)),
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

  // ══════════════════════════════════════════════════════════════
  // ADD EMPLOYEE
  // ══════════════════════════════════════════════════════════════
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
                    _addBiometricCard(),
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
                  'JPG, PNG — max 2MB',
                  style: TextStyle(fontSize: 11, color: tc.muted),
                ),
              ],
            ),
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
          'This is just a display photo. FACE ENROLLMENT will be done by the employee in the mobile app on their first login.',
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

  Widget _addBiometricCard() {
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
            Text(
              'Biometric Credentials',
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
                  'The 4-digit PIN is auto-generated & stored as a salted hash. Tap "Regenerate" for a new one. It will be saved automatically on submit.',
                  style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3B82F6)),
            ),
            child: Row(children: [
              const Icon(Icons.fingerprint_rounded,
                  size: 16, color: Color(0xFF1E40AF)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Fingerprint registration ay gagawin ng employee sa mobile app sa unang pag-login. Hindi kailangang i-set up dito.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                      height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF16A34A)),
            ),
            child: Row(children: [
              const Icon(Icons.face_rounded,
                  size: 16, color: Color(0xFF166534)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Face enrollment ay AWTOMATIKO rin sa mobile app sa unang login. 3 shots + liveness check.',
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
        onPressed: _addSaving ? null : _submitAdd,
        child: _addSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2),
        )
            : const Text(
          'Done',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
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
      _snack('❌ $emailErr', error: true);
      return;
    }
    final idErr = AdminEmployeeService.validateEmployeeId(empId);
    if (idErr != null) {
      _snack('❌ $idErr', error: true);
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
        _snack('❌ $err', error: true);
        return;
      }

      _snack('✅ Employee added. PIN copied to clipboard.');
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
    _snack('🎲 New PIN generated. Tap 👁 to reveal, then copy.');
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
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  onPressed: onToggle,
                  icon: Icon(
                    visible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                    color: tc.muted,
                  ),
                  splashRadius: 18,
                ),
                IconButton(
                  onPressed: () {
                    final p = controller.text.trim();
                    if (p.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: p));
                    _snack('📋 PIN copied to clipboard.');
                  },
                  icon: Icon(Icons.copy_rounded, size: 16, color: tc.muted),
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
        Icon(Icons.auto_awesome_rounded, size: 10, color: tc.orange),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            justGenerated
                ? 'Auto-generated • will save as hash on submit'
                : 'Auto-generated PIN — stored as salted hash',
            style: TextStyle(
              fontSize: 10,
              color: tc.orange,
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
              child: Text(g == 'male' ? '👨 Male' : '👩 Female'),
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

  // ══════════════════════════════════════════════════════════════
  // EDIT EMPLOYEE
  // ══════════════════════════════════════════════════════════════
  void _openEdit(Map<String, dynamic> emp) {
    _initEditControllers(emp);
    setState(() {
      _selectedProfileEmp = emp;
      _isEditingEmployee = true;
      _editWfhAccess = _isWfhEnabled(emp);
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
    _editPinCtrl.text = '';
    _editPinJustGenerated = false;
    _editPinVisible = false;
    _editPinSaving = false;
    _editFaceResetting = false;
    _editDeviceNameCtrl.text = _s(emp['deviceName'], '');
    _editEmployeeIdCtrl.text = empId;
    _editOriginalEmployeeId = empId;

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
    final canWfh = _canUseWfh(emp);
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
                    _editBiometricCard(canWfh),
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
                    CircularProgressIndicator(
                        color: Color(0xFFFF8C00)),
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
                displayUrl!,
                null,
                null,
                BoxFit.cover,
                Icon(Icons.person,
                    size: 80, color: tc.muted),
              )
                  : Column(
                mainAxisAlignment:
                MainAxisAlignment.center,
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
            'Display-only photo — not used for facial recognition.',
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
              return Column(children: fields
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
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            'Basic & Allowances are bounded to ₱5,000–500,000 basic, ₱0–100,000 allowance.',
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
                      '₱${total.toStringAsFixed(2)}',
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
              'BASIC SALARY (₱/month)',
              _editBasicSalaryCtrl,
              onChanged: () => setState(_recomputeDailyRate),
            );
            final f2 = _editMoneyInput(
              'ALLOWANCES (₱/month)',
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
              '₱ ',
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
            'DAILY RATE (₱/day)',
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
              '₱ ',
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
                child: Text(g == 'male' ? '👨 Male' : '👩 Female'),
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
    final options = deptPos.isNotEmpty ? deptPos : _allPositionOptions;
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

  Widget _editBiometricCard(bool canWfh) {
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
          if (canWfh) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _editWfhAccess ? const Color(0xFFDCFCE7) : tc.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color:
                  _editWfhAccess ? const Color(0xFF22C55E) : tc.border,
                ),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _editWfhAccess
                        ? const Color(0xFF22C55E)
                        : tc.muted.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _editWfhAccess
                        ? Icons.home_work_rounded
                        : Icons.home_outlined,
                    color: _editWfhAccess ? Colors.white : tc.muted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Work From Home Access',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: tc.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _editWfhAccess
                            ? 'ON — Employee can clock in outside office geofence.'
                            : 'OFF — Employee must be inside office geofence.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _editWfhAccess
                              ? const Color(0xFF166534)
                              : tc.muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _editWfhAccess,
                  onChanged: (v) => setState(() => _editWfhAccess = v),
                  activeColor: const Color(0xFF22C55E),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          _editFingerprintInfoCard(_selectedProfileEmp),
          const SizedBox(height: 12),
          _editFaceInfoCard(_selectedProfileEmp),
        ],
      ),
    );
  }

  // 🔐 Fingerprint info card sa Edit page
  Widget _editFingerprintInfoCard(Map<String, dynamic>? emp) {
    if (emp == null) return const SizedBox.shrink();
    final enrolled = _isFingerprintEnrolled(emp);
    final enrolledAt = _fingerprintEnrolledAt(emp);
    final deviceModel = _fingerprintDeviceOf(emp);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
        enrolled ? const Color(0xFFDBEAFE) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enrolled ? const Color(0xFF3B82F6) : const Color(0xFFF97316),
          width: 1.2,
        ),
      ),
      child: Row(children: [
        Icon(
          enrolled ? Icons.fingerprint_rounded : Icons.fingerprint,
          size: 24,
          color:
          enrolled ? const Color(0xFF1E40AF) : const Color(0xFF9A3412),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enrolled
                    ? 'Fingerprint Registered'
                    : 'Fingerprint NOT Registered',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: enrolled
                      ? const Color(0xFF1E40AF)
                      : const Color(0xFF9A3412),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                enrolled
                    ? '${enrolledAt != null ? _fmtDate(enrolledAt) : "—"} • $deviceModel'
                    : 'Employee must register sa mobile app.',
                style: TextStyle(
                  fontSize: 11,
                  color: enrolled
                      ? const Color(0xFF1E40AF)
                      : const Color(0xFF9A3412),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (enrolled)
          IconButton(
            tooltip: 'Reset fingerprint registration',
            onPressed: () => _confirmResetFingerprint(emp),
            icon: const Icon(Icons.restart_alt_rounded,
                size: 18, color: Color(0xFF1E40AF)),
            splashRadius: 18,
          ),
      ]),
    );
  }

  // 🆕 Face info card sa Edit page
  Widget _editFaceInfoCard(Map<String, dynamic>? emp) {
    if (emp == null) return const SizedBox.shrink();
    final enrolled = _isFaceEnrolled(emp);
    final enrolledAt = _faceEnrolledAt(emp);
    final version = _faceVersionOf(emp);
    final count = _faceCountOf(emp);
    final source = _faceSourceOf(emp);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
        enrolled ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enrolled ? const Color(0xFF16A34A) : const Color(0xFFF97316),
          width: 1.2,
        ),
      ),
      child: Row(children: [
        Icon(
          enrolled ? Icons.face_rounded : Icons.face_retouching_off_rounded,
          size: 24,
          color:
          enrolled ? const Color(0xFF166534) : const Color(0xFF9A3412),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                enrolled ? 'Face Registered' : 'Face NOT Registered',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: enrolled
                      ? const Color(0xFF166534)
                      : const Color(0xFF9A3412),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                enrolled
                    ? 'v$version • $count template${count == 1 ? "" : "s"} • ${enrolledAt != null ? _fmtDate(enrolledAt) : "—"}'
                    : 'Employee must register sa mobile app.',
                style: TextStyle(
                  fontSize: 11,
                  color: enrolled
                      ? const Color(0xFF166534)
                      : const Color(0xFF9A3412),
                  height: 1.3,
                ),
              ),
              if (enrolled && source != '—')
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Source: $source',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF166534),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (enrolled)
          IconButton(
            tooltip: 'Reset face registration',
            onPressed: _editFaceResetting
                ? null
                : () => _confirmResetFace(emp),
            icon: _editFaceResetting
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF16A34A)),
            )
                : const Icon(Icons.restart_alt_rounded,
                size: 18, color: Color(0xFF166534)),
            splashRadius: 18,
          ),
      ]),
    );
  }

  // 🔐 Reset fingerprint — force re-register
  Future<void> _confirmResetFingerprint(Map<String, dynamic> emp) async {
    final docId = _s(emp['id'], '');
    if (docId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.restart_alt_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Reset Fingerprint?',
                style: TextStyle(color: tc.text, fontSize: 18)),
          ),
        ]),
        content: Text(
          'Mawawala ang registration ng fingerprint ni ${_nameOf(emp)}. '
              'Kailangan niyang mag-register muli sa susunod na login.',
          style: TextStyle(color: tc.text, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await AdminDatabase.fs.collection('employees').doc(docId).set({
        'fingerprintEnrolled': false,
        'fingerprintEnrolledAt': null,
        'fingerprintDeviceModel': null,
        'fingerprintDeviceBinding': null,
        'fingerprintDeviceFingerprint': null,
        'fingerprintResetAt': FieldValue.serverTimestamp(),
        'fingerprintResetBy': _actorEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        await AdminDatabase.fs.collection('activity_logs').add({
          'type': 'fingerprint_reset',
          'action': 'Fingerprint Reset by Admin',
          'employeeId': docId,
          'employee_id': _s(emp['employeeId'], docId),
          'employee_name': _nameOf(emp),
          'resetBy': _actorEmail,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      if (!mounted) return;
      _snack('✅ Fingerprint reset. Employee must re-register.');
      widget.onRefreshNeeded();

      setState(() {
        emp['fingerprintEnrolled'] = false;
        emp['fingerprintEnrolledAt'] = null;
        emp['fingerprintDeviceModel'] = null;
        if (_selectedProfileEmp != null &&
            _s(_selectedProfileEmp!['id'], '') == docId) {
          _selectedProfileEmp!['fingerprintEnrolled'] = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _snack('❌ Failed to reset: $e', error: true);
    }
  }

  // 🆕 Reset face — force re-enroll on next mobile login
  Future<void> _confirmResetFace(Map<String, dynamic> emp) async {
    final docId = _s(emp['id'], '');
    if (docId.isEmpty) return;

    final version = _faceVersionOf(emp);
    final count = _faceCountOf(emp);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.face_retouching_off_rounded,
              color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Reset Face Data?',
                style: TextStyle(color: tc.text, fontSize: 18)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mawawala ang naka-register na mukha ni ${_nameOf(emp)} '
                  '(v$version, $count template${count == 1 ? "" : "s"}).',
              style: TextStyle(color: tc.text, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFACC15)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF854D0E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sa susunod na login ng employee, awtomatikong '
                          'sasailalim siya sa 3-shot face enrollment.',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF854D0E),
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reset Face'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _editFaceResetting = true);

    try {
      await AdminDatabase.fs.collection('employees').doc(docId).set({
        'faceEmbedding': FieldValue.delete(),
        'faceEmbeddings': FieldValue.delete(),
        'faceEmbeddingsJson': FieldValue.delete(),
        'faceEmbeddingsCount': FieldValue.delete(),
        'faceEmbeddingSize': FieldValue.delete(),
        'faceEmbeddingVersion': FieldValue.delete(),
        'faceEmbeddingUpdatedAt': FieldValue.delete(),
        'faceEmbeddingSource': FieldValue.delete(),
        'faceEmbeddingHash': FieldValue.delete(),
        'faceResetAt': FieldValue.serverTimestamp(),
        'faceResetBy': _actorEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      try {
        await AdminDatabase.fs.collection('activity_logs').add({
          'type': 'face_reset',
          'action': 'Face Data Reset by Admin',
          'employeeId': docId,
          'employee_id': _s(emp['employeeId'], docId),
          'employee_name': _nameOf(emp),
          'previousVersion': version,
          'previousCount': count,
          'resetBy': _actorEmail,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      if (!mounted) return;
      _snack('✅ Face data reset. Employee must re-enroll on next login.');
      widget.onRefreshNeeded();

      setState(() {
        emp['faceEmbeddingVersion'] = null;
        emp['faceEmbeddingsCount'] = null;
        emp['faceEmbeddingsJson'] = null;
        emp['faceEmbeddingSource'] = null;
        emp['faceEmbeddingUpdatedAt'] = null;
        if (_selectedProfileEmp != null &&
            _s(_selectedProfileEmp!['id'], '') == docId) {
          _selectedProfileEmp!['faceEmbeddingVersion'] = null;
          _selectedProfileEmp!['faceEmbeddingsCount'] = null;
          _selectedProfileEmp!['faceEmbeddingsJson'] = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _snack('❌ Failed to reset face: $e', error: true);
    } finally {
      if (mounted) setState(() => _editFaceResetting = false);
    }
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
                  hintStyle:
                  TextStyle(fontSize: 15, color: Color(0xFFB0B0B0)),
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

  Future<void> _onGenerateEditPin() async {
    if (_editPinSaving) return;

    final emp = _selectedProfileEmp;
    final docId = emp != null ? _s(emp['id'], '') : '';
    if (docId.isEmpty) {
      _snack('⚠️ Employee doc ID not found.', error: true);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Regenerate PIN?', style: TextStyle(color: tc.text)),
        content: Text(
          'Ang lumang PIN ay hindi na gagana. Ang bagong PIN ay '
              'ipapakita nang isang beses lamang.',
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
        _snack('❌ Employee document not found (id: $docId).', error: true);
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
        'pin': newPin,
        'pinHash': hash,
        'pinSalt': salt,
        'pinUpdatedAt': FieldValue.serverTimestamp(),
        'pinUpdatedBy': _actorEmail,
        'requiresPinChange': true,
      });

      debugPrint('✅ PIN regenerated for $docId — new PIN: $newPin');

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
            'pin': newPin,
            'pinUpdatedAt': DateTime.now(),
            'requiresPinChange': true,
          };
        }
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('🎲 New PIN: $newPin\nTap 📋 to copy.'),
          backgroundColor: tc.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e, st) {
      debugPrint('❌ regenerate PIN failed: $e\n$st');
      if (!mounted) return;

      setState(() => _editPinSaving = false);

      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Failed to regenerate PIN: $e'),
          backgroundColor: tc.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        onPressed: _editSaving ? null : () => _submitEdit(emp),
        child: _editSaving
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2),
        )
            : const Text(
          'Done',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
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
      _snack('❌ $emailErr', error: true);
      return;
    }
    final idErr = AdminEmployeeService.validateEmployeeId(newId);
    if (idErr != null) {
      _snack('❌ $idErr', error: true);
      return;
    }

    final basic = _parseMoneyStr(_editBasicSalaryCtrl.text);
    final allow = _parseMoneyStr(_editAllowancesCtrl.text);
    final salaryErr = AdminEmployeeService.validateSalary(basic, allow);
    if (salaryErr != null) {
      _snack('⚠️ $salaryErr', error: true);
      return;
    }

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
      final canWfh = _canUseWfh(emp);

      final patch = <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName',
        'employeeId': newId,
        'email': email,
        'emailLower': email.toLowerCase(),
        'phone': AdminEmployeeService.sanitize(_editPhoneCtrl.text,
            maxLen: 20),
        'role': newRole,
        'department': _editDeptCtrl.text.trim(),
        'gender': _editGender,
        'nfcTagId': _editKeyfobCtrl.text.trim().toUpperCase(),
        'deviceName':
        AdminEmployeeService.sanitize(_editDeviceNameCtrl.text, maxLen: 60),
        'wfhAccess': canWfh ? _editWfhAccess : false,
        if (_editBirthday != null)
          'birthday': Timestamp.fromDate(_editBirthday!),
        if (uploadedPhoto != null) 'photoUrl': uploadedPhoto,
        'basicSalary': basic,
        'allowances': allow,
        'basicAllowance': allow,
        'dailyRate': daily,
        'monthlyTotal': total,
        'workingDaysPerMonth': kWorkingDaysPerMonth,
        'bankName': AdminEmployeeService.sanitize(_editBankNameCtrl.text,
            maxLen: 80),
        'accountNumber': AdminEmployeeService.sanitize(
            _editAccountNumberCtrl.text,
            maxLen: 30),
        'salaryConfigured': true,
      };

      final err = await _svc.updateEmployee(docId: docId, patch: patch);
      if (!mounted) return;

      if (err != null) {
        _snack('❌ $err', error: true);
      } else {
        _snack('✅ Employee profile updated.');
        setState(() {
          _isEditingEmployee = false;
          _selectedProfileEmp = {...emp, ...patch};
          _editPhotoXFile = null;
          _editPhotoBytes = null;
          _editPinJustGenerated = false;
          _editPinVisible = false;
        });
        widget.onRefreshNeeded();
      }
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
              title: Text('Choose from Gallery',
                  style: TextStyle(color: tc.text)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: Color(0xFFFF8C00)),
              title: Text('Take a Photo',
                  style: TextStyle(color: tc.text)),
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
      final b64 = base64Encode(compressed);
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

  // ══════════════════════════════════════════════════════════════
  // PROFILE PAGE
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfilePage(Map<String, dynamic> emp) {
    final docId = _s(emp['id'], '');
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role Specified');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email Registered');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone Registered'));
    final empCode = _s(emp['employeeId'], docId);
    final genderIcon = _s(emp['gender'], 'male').toLowerCase() == 'female'
        ? '👩 Female'
        : '👨 Male';
    final joining = _fmtDate(
      emp['joiningDate'] ?? emp['createdAt'] ?? emp['created_at'],
      f: 'Not Specified',
    );
    final isActive = _isActive(emp);
    final nfc = _s(emp['nfcTagId'], 'NOT ASSIGNED');
    final hasBio = _hasCurrentFaceVersion(emp);

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
                  onPressed: () =>
                      setState(() => _selectedProfileEmp = null),
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
                    joining, isActive, nfc, hasBio, genderIcon),
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
      bool hasBio,
      String genderLabel,
      ) {
    return LayoutBuilder(builder: (context, c) {
      final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
      final left = _mainProfileCard(emp, name, role, dept, email, phone, id,
          joining, isActive, genderLabel);
      final right = _securityCard(emp, nfc, hasBio);
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
                    _fingerprintPill(_isFingerprintEnrolled(emp)),
                    _facePill(_isFaceEnrolled(emp)),
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
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
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

  Widget _securityCard(Map<String, dynamic> emp, String nfc, bool hasBio) {
    final nfcOk = nfc.isNotEmpty && nfc != 'NOT ASSIGNED';
    final wfh = _isWfhEnabled(emp);
    final canWfh = _canUseWfh(emp);
    final hasPhoto = _hasProfilePhoto(emp);
    final version = _faceVersionOf(emp);
    final count = _faceCountOf(emp);
    final faceCurrent = version == kCurrentFaceVersion && count > 0;

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
          _credBox('ACCESS PIN', '•••••  (salted hash)', true,
              'PIN configured'),
          if (_s(emp['deviceName'], '').isNotEmpty &&
              _s(emp['deviceName'], '') != '—') ...[
            const SizedBox(height: 12),
            _credBox('REGISTERED DEVICE', _s(emp['deviceName'], 'NOT SET'),
                true, 'Device bound'),
          ],
          const SizedBox(height: 12),
          _fingerprintStatusCard(emp),
          const SizedBox(height: 12),
          _faceStatusCard(emp),
          const SizedBox(height: 12),
          if (canWfh)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: wfh ? const Color(0xFFDCFCE7) : const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: wfh ? const Color(0xFF22C55E) : tc.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      wfh ? Icons.home_work_rounded : Icons.home_outlined,
                      size: 18,
                      color: wfh ? const Color(0xFF166534) : tc.muted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'WFH ACCESS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: wfh ? const Color(0xFF166534) : tc.muted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Switch(
                      value: wfh,
                      onChanged: (v) => _setWfh(emp, v),
                      activeColor: const Color(0xFF22C55E),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    wfh
                        ? 'Employee can clock in even outside the office geofence.'
                        : 'Employee must be inside the office geofence to clock in.',
                    style: TextStyle(
                      fontSize: 12,
                      color: wfh ? const Color(0xFF166534) : tc.muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
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
                Text(
                  'BIOMETRIC STATUS',
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
                    child: _bioItem(Icons.photo_camera_rounded, 'Photo',
                        hasPhoto, 'Uploaded', 'No Photo'),
                  ),
                  Expanded(
                    child: _bioItem(Icons.face, 'Face', faceCurrent, 'Enrolled',
                        count > 0 ? 'Outdated' : 'Not Enrolled'),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  count > 0
                      ? 'Face version: v$version  •  Templates: $count'
                      : 'Face biometric not enrolled yet.',
                  style: TextStyle(
                    fontSize: 11,
                    color: faceCurrent ? const Color(0xFF166534) : tc.muted,
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

  // 🔐 Fingerprint status card (Profile Page)
  Widget _fingerprintStatusCard(Map<String, dynamic> emp) {
    final enrolled = _isFingerprintEnrolled(emp);
    final enrolledAt = _fingerprintEnrolledAt(emp);
    final deviceModel = _fingerprintDeviceOf(emp);

    final bg = enrolled ? const Color(0xFFDBEAFE) : const Color(0xFFFFF7ED);
    final border =
    enrolled ? const Color(0xFF3B82F6) : const Color(0xFFF97316);
    final iconColor =
    enrolled ? const Color(0xFF1E40AF) : const Color(0xFF9A3412);
    final labelColor =
    enrolled ? const Color(0xFF1E40AF) : const Color(0xFF9A3412);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enrolled
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                    : const Color(0xFFF97316).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                enrolled ? Icons.fingerprint_rounded : Icons.fingerprint,
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FINGERPRINT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: labelColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enrolled ? 'Registered' : 'Not Registered',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: enrolled
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF9CA3AF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  enrolled
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  enrolled ? 'ACTIVE' : 'PENDING',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (enrolled) ...[
            _fpDetailRow(
              Icons.calendar_today_rounded,
              'Registered on',
              enrolledAt != null
                  ? '${_fmtDate(enrolledAt)} • ${_fmtTime(enrolledAt)}'
                  : 'Date not available',
            ),
            const SizedBox(height: 8),
            _fpDetailRow(
              Icons.phone_android_rounded,
              'Registered device',
              deviceModel.isNotEmpty && deviceModel != '—'
                  ? deviceModel
                  : 'Not recorded',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _confirmResetFingerprint(emp),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text(
                  'Reset Fingerprint',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            _fpDetailRow(
              Icons.info_outline_rounded,
              'Status',
              'Employee must register fingerprint sa mobile app '
                  'bago maka-clock in.',
            ),
          ],
        ],
      ),
    );
  }

  // 🆕 Face status card (Profile Page)
  Widget _faceStatusCard(Map<String, dynamic> emp) {
    final enrolled = _isFaceEnrolled(emp);
    final enrolledAt = _faceEnrolledAt(emp);
    final version = _faceVersionOf(emp);
    final count = _faceCountOf(emp);
    final source = _faceSourceOf(emp);

    final bg = enrolled ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED);
    final border =
    enrolled ? const Color(0xFF16A34A) : const Color(0xFFF97316);
    final iconColor =
    enrolled ? const Color(0xFF166534) : const Color(0xFF9A3412);
    final labelColor =
    enrolled ? const Color(0xFF166534) : const Color(0xFF9A3412);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enrolled
                    ? const Color(0xFF16A34A).withValues(alpha: 0.15)
                    : const Color(0xFFF97316).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                enrolled
                    ? Icons.face_rounded
                    : Icons.face_retouching_off_rounded,
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FACE RECOGNITION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: labelColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enrolled ? 'Registered' : 'Not Registered',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: enrolled
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF9CA3AF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  enrolled
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  enrolled ? 'ACTIVE' : 'PENDING',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (enrolled) ...[
            _fpDetailRow(
              Icons.calendar_today_rounded,
              'Registered on',
              enrolledAt != null
                  ? '${_fmtDate(enrolledAt)} • ${_fmtTime(enrolledAt)}'
                  : 'Date not available',
            ),
            const SizedBox(height: 8),
            _fpDetailRow(
              Icons.straighten_rounded,
              'Templates',
              '$count template${count == 1 ? "" : "s"} • v$version',
            ),
            if (source != '—') ...[
              const SizedBox(height: 8),
              _fpDetailRow(
                Icons.source_rounded,
                'Source',
                source,
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _confirmResetFace(emp),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text(
                  'Reset Face',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            _fpDetailRow(
              Icons.info_outline_rounded,
              'Status',
              'Employee must enroll face sa mobile app '
                  'bago maka-clock in.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _fpDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF6B7280)),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    );
  }

  Widget _credBox(
      String label, String value, bool verified, String verifiedText,
      {bool mono = false}) {
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
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tc.muted,
                  letterSpacing: 0.5,
                ),
              ),
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
                color: verified ? tc.orangeText : tc.red,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _bioItem(IconData icon, String label, bool enabled,
      String enabledText, String disabledText) {
    return Column(children: [
      Icon(icon,
          size: 26, color: enabled ? const Color(0xFF904D00) : tc.muted),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: enabled ? tc.text : tc.muted,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        enabled ? enabledText : disabledText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: enabled ? tc.orangeText : tc.muted,
        ),
      ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════
  // WFH TOGGLE
  // ══════════════════════════════════════════════════════════════
  Future<void> _setWfh(Map<String, dynamic> emp, bool enabled) async {
    final docId = _s(emp['id'], '');
    if (docId.isEmpty) {
      _snack('Employee ID missing.', error: true);
      return;
    }

    setState(() {
      emp['wfhAccess'] = enabled;
      if (_selectedProfileEmp != null &&
          _s(_selectedProfileEmp!['id'], '') == docId) {
        _selectedProfileEmp!['wfhAccess'] = enabled;
      }
    });

    final err = await _svc.setWfhAccess(docId, enabled);
    if (!mounted) return;

    if (err != null) {
      setState(() {
        emp['wfhAccess'] = !enabled;
        if (_selectedProfileEmp != null &&
            _s(_selectedProfileEmp!['id'], '') == docId) {
          _selectedProfileEmp!['wfhAccess'] = !enabled;
        }
      });
      _snack('❌ $err', error: true);
      return;
    }

    _snack(enabled ? '🏠 WFH ENABLED' : '🏢 WFH DISABLED');
    try {
      AdminNotificationService.instance.notifyWfhToggle(
        employeeId: docId,
        employeeName: _nameOf(emp),
        enabled: enabled,
      );
    } catch (_) {}
    widget.onRefreshNeeded();
  }

  // ══════════════════════════════════════════════════════════════
  // STREAMS
  // ══════════════════════════════════════════════════════════════
  Stream<List<Map<String, dynamic>>> _attendanceStream(String empId) {
    return AdminDatabase.fs
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: empId)
        .limit(200)
        .snapshots()
        .map((s) {
      final list = s.docs.map((d) {
        final m = d.data();
        return <String, dynamic>{...m, 'id': d.id};
      }).toList();

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
      debugPrint('attendanceStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  Stream<List<Map<String, dynamic>>> _leaveStream(String empId) {
    return AdminDatabase.fs
        .collection('leave_applications')
        .where('employeeId', isEqualTo: empId)
        .snapshots()
        .map((s) {
      final list = s.docs.map((d) {
        final m = d.data();
        return <String, dynamic>{...m, 'id': d.id};
      }).toList();

      list.sort((a, b) {
        final da = _toDateTime(a['createdAt'] ?? a['timestamp']);
        final db = _toDateTime(b['createdAt'] ?? b['timestamp']);
        if (da != null && db != null) return db.compareTo(da);
        return 0;
      });
      return list;
    }).handleError((e) {
      debugPrint('leaveStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  Stream<List<Map<String, dynamic>>> _activityStream(String empId) {
    return AdminDatabase.fs
        .collection('activity_logs')
        .where('employeeId', isEqualTo: empId)
        .limit(50)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList();
      list.sort((a, b) {
        final da = _toDateTime(a['timestamp']);
        final db = _toDateTime(b['timestamp']);
        if (da != null && db != null) return db.compareTo(da);
        return 0;
      });
      return list;
    }).handleError((e) {
      debugPrint('activityStream($empId): $e');
      return <Map<String, dynamic>>[];
    });
  }

  // ══════════════════════════════════════════════════════════════
  // ATTENDANCE UI
  // ══════════════════════════════════════════════════════════════
  Widget _attendanceAndLeaveSection(String empId, Map<String, dynamic> emp) {
    return LayoutBuilder(builder: (context, c) {
      final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
      final left = _recentAttendanceCard(empId);
      final right = _leaveBalanceCard(empId, emp);
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
              child: Text(
                'Recent Attendance',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
            ),
            Text(
              'Live data',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tc.muted,
              ),
            ),
          ]),
          const SizedBox(height: 16),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _attendanceStream(empId),
            builder: (context, snap) {
              final logs = snap.data ?? const [];
              final rows = _buildAttendanceRows(logs);
              final totalMin = _sumMinutes(rows);
              final monthMin = _sumMinutes(rows,
                  month: DateTime.now().month, year: DateTime.now().year);

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tc.orange.withValues(alpha: 0.12),
                      tc.orange.withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tc.orange.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Expanded(
                    child: _hourStat(
                      Icons.access_time_rounded,
                      'Total Hours',
                      _fmtMinutes(totalMin),
                    ),
                  ),
                  Container(width: 1, height: 40, color: tc.border),
                  Expanded(
                    child: _hourStat(
                      Icons.calendar_month_rounded,
                      'This Month',
                      _fmtMinutes(monthMin),
                    ),
                  ),
                  Container(width: 1, height: 40, color: tc.border),
                  Expanded(
                    child: _hourStat(
                      Icons.check_circle_rounded,
                      'Days Worked',
                      '${rows.length}',
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
              _attHdr('DATE', 4),
              _attHdr('TIME IN', 3),
              _attHdr('TIME OUT', 3),
              _attHdr('TOTAL HRS', 3),
              _attHdr('STATUS', 3),
            ]),
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _attendanceStream(empId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
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
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.error_outline, size: 32, color: tc.red),
                      const SizedBox(height: 8),
                      Text(
                        'Unable to load attendance.',
                        style: TextStyle(color: tc.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                );
              }
              final logs = snap.data ?? const [];
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.event_busy_outlined,
                          size: 32, color: tc.muted),
                      const SizedBox(height: 8),
                      Text(
                        'No attendance records yet.',
                        style: TextStyle(color: tc.muted, fontSize: 13),
                      ),
                    ]),
                  ),
                );
              }
              final rows = _buildAttendanceRows(logs).take(5).toList();
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No valid attendance data.',
                      style: TextStyle(color: tc.muted, fontSize: 13),
                    ),
                  ),
                );
              }
              return Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _attRow(rows[i]),
                  if (i < rows.length - 1)
                    Divider(
                        height: 1,
                        color: tc.border.withValues(alpha: 0.3)),
                ],
              ]);
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildAttendanceRows(
      List<Map<String, dynamic>> logs) {
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final log in logs) {
      final dt = _toDateTime(log['timestamp'] ?? log['createdAt']);
      if (dt == null) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(log);
    }

    final rows = <Map<String, dynamic>>[];
    byDay.forEach((key, dayLogs) {
      dayLogs.sort((a, b) {
        final ta = _toDateTime(a['timestamp']);
        final tb = _toDateTime(b['timestamp']);
        if (ta == null || tb == null) return 0;
        return ta.compareTo(tb);
      });

      Map<String, dynamic>? inLog;
      Map<String, dynamic>? outLog;
      DateTime? inTs;
      DateTime? outTs;

      for (final l in dayLogs) {
        final t = _s(l['type'], '').toUpperCase();
        final ts = _toDateTime(l['timestamp']);
        if ((t == 'IN' || t == 'LOGIN' || t == 'CLOCK IN') && inLog == null) {
          inLog = l;
          inTs = ts;
        } else if ((t == 'OUT' || t == 'LOGOUT' || t == 'CLOCK OUT') &&
            outLog == null) {
          outLog = l;
          outTs = ts;
        }
      }

      if (inTs == null && dayLogs.isNotEmpty) {
        inLog = dayLogs.first;
        inTs = _toDateTime(inLog['timestamp']);
      }
      if (outTs == null && dayLogs.length > 1) {
        outLog = dayLogs.last;
        outTs = _toDateTime(outLog['timestamp']);
      }

      String total = '—';
      if (inTs != null &&
          outTs != null &&
          (outTs.isAfter(inTs) || outTs.isAtSameMomentAs(inTs))) {
        final d = outTs.difference(inTs);
        total = '${d.inHours}h ${d.inMinutes.remainder(60)}m';
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
        'status': status,
        'isLate': isLate,
      });
    });

    rows.sort(
            (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return rows;
  }

  int _sumMinutes(List<Map<String, dynamic>> rows, {int? month, int? year}) {
    int total = 0;
    for (final r in rows) {
      final a = r['in'] as DateTime?;
      final b = r['out'] as DateTime?;
      if (a == null || b == null || b.isBefore(a)) continue;
      if (month != null && a.month != month) continue;
      if (year != null && a.year != year) continue;
      total += b.difference(a).inMinutes;
    }
    return total;
  }

  String _fmtMinutes(int m) {
    if (m <= 0) return '0h 0m';
    return '${m ~/ 60}h ${m % 60}m';
  }

  Widget _hourStat(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: tc.orange),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tc.muted,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tc.text,
              letterSpacing: -0.3,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _attHdr(String label, int flex) => Expanded(
    flex: flex,
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: tc.muted,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _attRow(Map<String, dynamic> row) {
    final date = row['date'] as DateTime?;
    final inTs = row['in'] as DateTime?;
    final outTs = row['out'] as DateTime?;
    final total = row['total'] as String;
    final status = row['status'] as String;
    final isLate = row['isLate'] as bool;
    final isWorking = status == 'Working';

    final bg = isWorking
        ? const Color(0xFFDBEAFE)
        : (isLate ? const Color(0xFFFEF9C3) : const Color(0xFFDCFCE7));
    final fg = isWorking
        ? const Color(0xFF1E40AF)
        : (isLate ? const Color(0xFF854D0E) : const Color(0xFF166534));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Text(_fmtDate(date),
              style: TextStyle(fontSize: 14, color: tc.text)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            _fmtTime(inTs),
            style: TextStyle(
              fontSize: 14,
              color: inTs != null ? tc.text : tc.muted,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            _fmtTime(outTs),
            style: TextStyle(
              fontSize: 14,
              color: outTs != null ? tc.text : tc.muted,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            total,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _leaveBalanceCard(String empId, Map<String, dynamic> emp) {
    final annualTotal = _annualLeaveTotalOf(emp);
    final sickTotal = _sickLeaveTotalOf(emp);

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
        builder: (context, snap) {
          final leaves = snap.data ?? const [];
          final stats = _computeLeaveStats(leaves,
              annualTotal: annualTotal, sickTotal: sickTotal);

          final pending = leaves
              .where((l) =>
          _s(l['status'], 'pending').toLowerCase() == 'pending')
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    'Leave Balance',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: tc.text,
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openLeaveCreditsDialog(emp),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: tc.orange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: tc.orange.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 12, color: tc.orange),
                          const SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tc.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _leaveItem(
                'ANNUAL LEAVE',
                stats['usedAnnual']!,
                annualTotal,
                const Color(0xFF904D00),
                const Color(0xFFFFDCC3),
                const Color(0xFF6E3900),
              ),
              if ((stats['pendingAnnual'] ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '+ ${stats['pendingAnnual']} day(s) pending approval',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _leaveItem(
                'SICK LEAVE',
                stats['usedSick']!,
                sickTotal,
                const Color(0xFF5C5F61),
                const Color(0xFFE0E3E6),
                const Color(0xFF44474A),
              ),
              if ((stats['pendingSick'] ?? 0) > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '+ ${stats['pendingSick']} day(s) pending approval',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
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
                        Text(
                          '${stats['remainingAnnual']! + stats['remainingSick']!} days',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: tc.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${stats['remainingAnnual']}A · ${stats['remainingSick']}S',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tc.orangeText,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Text(
                'PENDING REQUESTS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tc.muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.border),
                  ),
                  child: Text(
                    'No pending leave requests.',
                    style: TextStyle(fontSize: 13, color: tc.muted),
                  ),
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
                                _leaveLabel(_s(p['leaveType'],
                                    _s(p['type'], 'Leave'))),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text,
                                ),
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

  Map<String, int> _computeLeaveStats(
      List<Map<String, dynamic>> leaves, {
        required int annualTotal,
        required int sickTotal,
      }) {
    int usedA = 0, usedS = 0, pendA = 0, pendS = 0;
    for (final l in leaves) {
      final code = _s(l['leaveType'], _s(l['type'], '')).toUpperCase();
      final days = _safeInt(l['days'], 1);
      final status = _s(l['status'], 'pending').toLowerCase();
      if (status == 'approved') {
        if (code == 'VL') {
          usedA += days;
        } else if (code == 'SL') {
          usedS += days;
        }
      } else if (status == 'pending') {
        if (code == 'VL') pendA += days;
        if (code == 'SL') pendS += days;
      }
    }
    return {
      'usedAnnual': usedA,
      'usedSick': usedS,
      'pendingAnnual': pendA,
      'pendingSick': pendS,
      'remainingAnnual': (annualTotal - usedA).clamp(0, annualTotal),
      'remainingSick': (sickTotal - usedS).clamp(0, sickTotal),
    };
  }

  String _leaveLabel(String c) {
    const m = {
      'SL': 'Sick Leave',
      'VL': 'Vacation Leave',
      'EL': 'Emergency Leave',
      'BL': 'Bereavement Leave',
      'ML': 'Maternity Leave',
      'PL': 'Paternity Leave',
    };
    return m[c.toUpperCase()] ?? c;
  }

  Widget _leaveItem(String label, int used, int total, Color bar,
      Color pillBg, Color pillText) {
    final progress = total == 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    final remaining = (total - used).clamp(0, total);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: pillText,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '${used.toString().padLeft(2, '0')}/$total',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: tc.text,
          ),
        ),
        const SizedBox(width: 6),
        Text('Days', style: TextStyle(fontSize: 13, color: tc.muted)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(children: [
          Container(height: 8, color: const Color(0xFFDCE9FF)),
          FractionallySizedBox(
            widthFactor: progress,
            child: Container(height: 8, color: bar),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        Text('Used: $used',
            style: TextStyle(fontSize: 11, color: tc.muted)),
        const Spacer(),
        Text(
          'Remaining: $remaining',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tc.orangeText,
          ),
        ),
      ]),
    ]);
  }

  Future<void> _openLeaveCreditsDialog(Map<String, dynamic> emp) async {
    final docId = _s(emp['id'], '');
    if (docId.isEmpty) return;

    final annualCtrl =
    TextEditingController(text: '${_annualLeaveTotalOf(emp)}');
    final sickCtrl = TextEditingController(text: '${_sickLeaveTotalOf(emp)}');

    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          Icon(Icons.tune_rounded, color: tc.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Edit Leave Credits',
              style: TextStyle(
                color: tc.text,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set the total leave credits for ${_nameOf(emp)}. Approved leaves are auto-deducted.',
                style:
                TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              _leaveCreditInput(
                  'ANNUAL LEAVE (days)', annualCtrl, Icons.beach_access_rounded),
              const SizedBox(height: 12),
              _leaveCreditInput(
                  'SICK LEAVE (days)', sickCtrl, Icons.sick_rounded),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final a = int.tryParse(annualCtrl.text.trim());
              final s = int.tryParse(sickCtrl.text.trim());
              if (a == null ||
                  s == null ||
                  a < 0 ||
                  a > 60 ||
                  s < 0 ||
                  s > 60) {
                _snack('Enter numbers 0–60.', error: true);
                return;
              }
              Navigator.pop(context, {'annual': a, 'sick': s});
            },
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (result == null) return;

    final err = await _svc.setLeaveCredits(
      docId: docId,
      annualTotal: result['annual']!,
      sickTotal: result['sick']!,
    );

    if (!mounted) return;
    if (err != null) {
      _snack('❌ $err', error: true);
      return;
    }

    setState(() {
      emp['annualLeaveTotal'] = result['annual'];
      emp['sickLeaveTotal'] = result['sick'];
      if (_selectedProfileEmp != null &&
          _s(_selectedProfileEmp!['id'], '') == docId) {
        _selectedProfileEmp!['annualLeaveTotal'] = result['annual'];
        _selectedProfileEmp!['sickLeaveTotal'] = result['sick'];
      }
    });
    _snack('✅ Leave credits updated.');
    widget.onRefreshNeeded();
  }

  Widget _leaveCreditInput(
      String label, TextEditingController ctrl, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tc.text,
          letterSpacing: 0.4,
        ),
      ),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.border),
        ),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(icon, size: 16, color: tc.orange),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: TextStyle(
                fontSize: 15,
                color: tc.text,
                fontWeight: FontWeight.w700,
              ),
              cursorColor: tc.orange,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none,
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _devicesSection(String empId, Map<String, dynamic> emp) {
    return LayoutBuilder(builder: (context, c) {
      final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);
      final left = _devicesCard(empId, emp);
      final right = _activityCard(empId);
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 20), right],
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

  Widget _devicesCard(String empId, Map<String, dynamic> emp) {
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
        builder: (context, snap) {
          final logs = snap.data ?? const [];
          final devices = _extractDevices(logs);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.devices_rounded, size: 22, color: tc.orange),
                const SizedBox(width: 8),
                Text(
                  'Authorized Devices',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: tc.text,
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              if (devices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tc.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.border),
                  ),
                  child: Text(
                    'No devices registered for this employee.',
                    style: TextStyle(fontSize: 13, color: tc.muted),
                  ),
                )
              else
                for (var i = 0; i < devices.length; i++) ...[
                  _deviceItem(devices[i]),
                  if (i < devices.length - 1) const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _extractDevices(
      List<Map<String, dynamic>> logs) {
    final uniq = <String, Map<String, dynamic>>{};
    for (final log in logs) {
      final name = _s(log['device'], '');
      if (name.isEmpty ||
          name.toLowerCase() == 'unknown device' ||
          name == '—') {
        continue;
      }
      if (!uniq.containsKey(name)) {
        final lower = name.toLowerCase();
        IconData icon = Icons.devices_rounded;
        if (lower.contains('web') || lower.contains('chrome')) {
          icon = Icons.web_rounded;
        } else if (lower.contains('ios') || lower.contains('iphone')) {
          icon = Icons.phone_iphone_rounded;
        } else if (lower.contains('android')) {
          icon = Icons.phone_android_rounded;
        } else if (lower.contains('mobile')) {
          icon = Icons.smartphone_rounded;
        }

        uniq[name] = {
          'name': name,
          'sub': _s(log['platform'], _s(log['os'], 'Mobile App')),
          'lastActive': log['timestamp'],
          'icon': icon,
        };
      }
    }
    return uniq.values.toList();
  }

  Widget _deviceItem(Map<String, dynamic> d) {
    final last = d['lastActive'];
    final lastStr = last != null
        ? 'Last active: ${_fmtDate(last)} ${_fmtTime(last)}'
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
          child: Icon(d['icon'] as IconData,
              size: 22, color: const Color(0xFF904D00)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d['name'] as String,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tc.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(d['sub'] as String,
                  style: TextStyle(fontSize: 13, color: tc.muted)),
              const SizedBox(height: 4),
              Text(lastStr,
                  style: TextStyle(fontSize: 11, color: tc.muted)),
            ],
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
      ]),
    );
  }

  Widget _activityCard(String empId) {
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
          Text(
            'Activity History',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
          const SizedBox(height: 24),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _activityStream(empId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
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
              final logs = snap.data ?? const [];
              if (logs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No activity records yet.',
                    style: TextStyle(fontSize: 13, color: tc.muted),
                  ),
                );
              }
              final rows = logs.take(6).toList();
              return Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  _activityItem(rows[i], i < rows.length - 1),
                  if (i < rows.length - 1) const SizedBox(height: 4),
                ],
              ]);
            },
          ),
        ],
      ),
    );
  }

  Widget _activityItem(Map<String, dynamic> log, bool showLine) {
    final title = _s(log['action'], _s(log['type'], 'Activity Event'));
    final sub =
        '${_fmtDate(log['timestamp'])} • ${_fmtTime(log['timestamp'])} • ${_s(log['device'], 'Unknown device')}';

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E3E6),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconForActivity(log['type']),
                  size: 18, color: const Color(0xFF44474A)),
            ),
            if (showLine)
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: tc.border,
                ),
              ),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: showLine ? 20 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tc.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 13, color: tc.muted)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  IconData _iconForActivity(dynamic type) {
    final t = _s(type, '').toLowerCase();
    if (t.contains('login') || t.contains('auth')) {
      return Icons.vpn_key_outlined;
    }
    if (t.contains('wfh')) return Icons.home_work_rounded;
    if (t.contains('pin')) return Icons.password_rounded;
    if (t.contains('fingerprint')) return Icons.fingerprint_rounded;
    if (t.contains('face_reset') || t.contains('face_reset')) {
      return Icons.face_retouching_off_rounded;
    }
    if (t.contains('face')) return Icons.face_rounded;
    if (t.contains('error') || t.contains('fail')) {
      return Icons.error_outline;
    }
    if (t.contains('registration')) {
      return Icons.person_add_alt_1_rounded;
    }
    if (t.contains('leave')) return Icons.beach_access_rounded;
    if (t.contains('terminat')) return Icons.person_remove_rounded;
    return Icons.settings_outlined;
  }

  // ══════════════════════════════════════════════════════════════
  // TERMINATE
  // ══════════════════════════════════════════════════════════════
  void _confirmTerminate(String docId, String name) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Terminate Employee?',
            style: TextStyle(color: tc.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ang $name ay ite-terminate (soft delete). Hindi na siya makakapasok, '
                  'pero ang record ay mananatili para sa audit.',
              style: TextStyle(color: tc.text, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLength: 200,
              maxLines: 3,
              style: TextStyle(color: tc.text),
              decoration: InputDecoration(
                labelText: 'Reason (optional)',
                labelStyle: TextStyle(color: tc.muted),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
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
              final err = await _svc.terminateEmployee(
                docId,
                reason: reasonCtrl.text.trim(),
              );
              if (!mounted) return;
              if (err != null) {
                _snack('❌ $err', error: true);
              } else {
                _snack('✅ Employee terminated.');
                setState(() => _selectedProfileEmp = null);
                widget.onRefreshNeeded();
              }
            },
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String empId) {
    if (empId.isEmpty) return;
    setState(() {
      if (_selectedEmpIds.contains(empId)) {
        _selectedEmpIds.remove(empId);
      } else {
        _selectedEmpIds.add(empId);
      }
      if (_selectedEmpIds.isEmpty) _bulkSelectMode = false;
    });
  }

  // ══════════════════════════════════════════════════════════════
  // PDF
  // ══════════════════════════════════════════════════════════════
  Future<void> _downloadPdf(Map<String, dynamic> emp) async {
    final pdf = pw.Document();
    final name = _nameOf(emp);
    final role = _s(emp['role'], 'No Role');
    final dept = _s(emp['department'], 'Unassigned');
    final email = _s(emp['email'], 'No Email');
    final phone = _s(emp['phone'], _s(emp['mobile'], 'No Phone'));
    final id = _s(emp['employeeId'], _s(emp['id'], 'N/A'));
    final gender = _s(emp['gender'], 'male').toLowerCase() == 'female'
        ? 'Female'
        : 'Male';
    final joining = _fmtDate(
      emp['joiningDate'] ?? emp['createdAt'],
      f: 'Not Specified',
    );
    final nfc = _s(emp['nfcTagId'], 'NOT ASSIGNED');
    final status = _isActive(emp) ? 'ACTIVE' : 'INACTIVE';
    final wfh = _canUseWfh(emp)
        ? (_isWfhEnabled(emp) ? 'ENABLED' : 'DISABLED')
        : 'N/A';
    final face = _hasCurrentFaceVersion(emp)
        ? 'ENROLLED (v$kCurrentFaceVersion)'
        : 'NOT ENROLLED';
    final photo = _hasProfilePhoto(emp) ? 'UPLOADED' : 'NO PHOTO';
    final device = _s(emp['deviceName'], 'NOT SET');
    final annual = _annualLeaveTotalOf(emp);
    final sick = _sickLeaveTotalOf(emp);
    final fpEnrolled = _isFingerprintEnrolled(emp);
    final fpStatus = fpEnrolled ? 'REGISTERED' : 'NOT REGISTERED';

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'EMPLOYEE PROFILE REPORT',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Status: $status',
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.orange,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text('Basic Information',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            _pdfRow('Name', name),
            _pdfRow('Gender', gender),
            _pdfRow('Employee ID', id),
            _pdfRow('Role', role),
            _pdfRow('Department', dept),
            _pdfRow('Email', email),
            _pdfRow('Phone', phone),
            _pdfRow('Joining Date', joining),
            pw.SizedBox(height: 20),
            pw.Text('Leave Credits',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            _pdfRow('Annual Leave', '$annual days'),
            _pdfRow('Sick Leave', '$sick days'),
            pw.SizedBox(height: 20),
            pw.Text('Security',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            _pdfRow('Profile Photo', photo),
            _pdfRow('Face Biometric', face),
            _pdfRow('Fingerprint', fpStatus),
            _pdfRow('NFC/Keyfob', nfc),
            _pdfRow('Device', device),
            _pdfRow('WFH Access', wfh),
          ],
        ),
      ),
    ));

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'Profile_${name.replaceAll(' ', '_')}.pdf',
    );
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
    child: pw.Row(children: [
      pw.Text('$label: ',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text(value),
    ]),
  );

  // ══════════════════════════════════════════════════════════════
  // CLEAR ALL LOGS
  // ══════════════════════════════════════════════════════════════
  void _confirmWipeAllLogs() {
    final selections = <String, bool>{
      'All Activity Logs': true,
      'All Attendance Records': true,
      'All Location Tracking Data': true,
      'All Leave Applications': true,
      'All PDF Exports': true,
      'All Task Records': true,
      'All Fingerprint Registrations': false,
      'All Face Registrations': false,
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        final hasSel = selections.values.any((v) => v);
        return AlertDialog(
          backgroundColor: tc.card,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: tc.red, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'SELECT DATA TO DELETE',
                style: TextStyle(
                  color: tc.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose which data to permanently delete:',
                    style: TextStyle(
                      color: tc.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tc.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: tc.red.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      children: selections.keys.map((k) {
                        return CheckboxListTile(
                          value: selections[k],
                          onChanged: (v) => setDialogState(
                                  () => selections[k] = v ?? false),
                          title: Text(
                            k,
                            style: TextStyle(
                              color: tc.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          activeColor: tc.red,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tc.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: tc.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This action CANNOT be undone!',
                          style: TextStyle(
                            color: tc.red,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: tc.muted)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: hasSel ? tc.red : tc.muted,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
              onPressed: hasSel
                  ? () async {
                Navigator.pop(context);

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AlertDialog(
                    backgroundColor: tc.card,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    content: Padding(
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                      child: Row(children: [
                        CircularProgressIndicator(color: tc.orange),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            'Deleting...\nPlease wait.',
                            style: TextStyle(color: tc.text),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );

                final keys = selections.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toList();
                final err = await AdminDatabase.wipeSelected(keys);

                if (mounted) {
                  Navigator.pop(context);
                  if (err != null) {
                    _snack('Wipe failed: $err', error: true);
                  } else {
                    _snack('✅ Selected data cleared.');
                    widget.onRefreshNeeded();
                  }
                }
              }
                  : null,
              icon: const Icon(Icons.delete_forever_rounded, size: 18),
              label: const Text(
                'Delete Selected',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _emptyState() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(48),
    decoration: BoxDecoration(
      color: tc.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: tc.border),
    ),
    child: Column(children: [
      Icon(Icons.person_search_rounded, size: 40, color: tc.muted),
      const SizedBox(height: 12),
      Text(
        'No records match search parameters.',
        style: TextStyle(color: tc.muted, fontSize: 14),
      ),
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
    ]),
  );
}

// ══════════════════════════════════════════════════════════════
// DASHED BORDER
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
    final dash = _dashPath(path, dashWidth, dashSpace);
    canvas.drawPath(dash, paint);
  }

  Path _dashPath(Path source, double dw, double ds) {
    final dest = Path();
    for (final m in source.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final n = d + dw;
        dest.addPath(m.extractPath(d, n.clamp(0, m.length)), Offset.zero);
        d = n + ds;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
          old.radius != radius ||
          old.dashWidth != dashWidth ||
          old.dashSpace != dashSpace;
}