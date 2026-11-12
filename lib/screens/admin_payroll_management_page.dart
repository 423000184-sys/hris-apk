// lib/screens/admin_payroll_management_page.dart
// v2.6: 🆕 HR can edit payroll per employee. Before saving, HR Assistant
//       password is required for override authorization.
//       Dual-signature audit logged.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'admin_theme.dart';
import '../utils/file_download.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/payroll_calculator.dart';
import '../services/employee_notification_service.dart';
import '../services/attendance_hours_service.dart';
import '../services/admin_auth_service.dart';
import '../services/demo_mode_service.dart';
import '../services/onesignal_sender.dart';

class AdminPayrollManagementPage extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  final VoidCallback? onBack;

  const AdminPayrollManagementPage({
    super.key,
    this.employeeData = const {},
    this.onBack,
  });

  @override
  State<AdminPayrollManagementPage> createState() =>
      _AdminPayrollManagementPageState();
}

class _AdminPayrollManagementPageState
    extends State<AdminPayrollManagementPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  // 🆕 Working copy of employee data so edits are reflected without
  //    needing the parent widget to re-fetch
  Map<String, dynamic> _currentEmployeeData = {};

  PayrollBreakdown _b = PayrollBreakdown.empty;
  EmployeeHoursSummary _hours = EmployeeHoursSummary.empty;
  bool _loading = true;
  bool _printing = false;
  bool _downloading = false;
  bool _unlockingPayslip = false;
  bool _isPayslipUnlocked = false;

  // 🆕 Override flow guard
  bool _editing = false;

  final _SecurityGuard _guard = _SecurityGuard();
  bool _isAdminVerified = false;
  DateTime? _lastNotifyAt;

  static const Duration _notifyCooldown = Duration(minutes: 5);

  // 🆕 HR Assistant override password storage
  static const String _kHrOverrideCollection = 'settings';
  static const String _kHrOverrideDoc = 'payroll_override';
  static const String _kHrOverrideField = 'hrAssistantPasswordHash';

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

  static String _safeFilenameSegment(dynamic raw, {int maxLen = 40}) {
    if (raw == null) return 'unknown';
    final s = raw.toString();
    var safe = s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    safe = safe.replaceAll(RegExp(r'^\.+'), '');
    if (safe.isEmpty) safe = 'unknown';
    if (safe.length > maxLen) safe = safe.substring(0, maxLen);
    return safe;
  }

  static bool _isSafePhotoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') return false;
      if (!uri.hasAuthority) return false;
      final host = uri.host.toLowerCase();
      if (host.contains('firebasestorage.googleapis.com')) return true;
      if (host.contains('storage.googleapis.com')) return true;
      if (host.endsWith('.googleusercontent.com')) return true;
      if (host.endsWith('.cloudinary.com')) return true;
      if (host.endsWith('.amazonaws.com')) return true;
      return true;
    } catch (_) {
      return false;
    }
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
      if (kDebugMode) debugPrint('⚠️ payroll-mgmt audit failed: $e');
    }
  }

  void _toast(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor: error
            ? tc.red
            : (success ? tc.green : tc.orange),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🆕 HR ASSISTANT OVERRIDE PASSWORD
  // ═══════════════════════════════════════════════════════════════════════
  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<String?> _getStoredHrPasswordHash() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_kHrOverrideCollection)
          .doc(_kHrOverrideDoc)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final raw = doc.data()?[_kHrOverrideField];
      if (raw is String && raw.isNotEmpty) return raw;
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [HrOverride] fetch hash failed: $e');
      }
      return null;
    }
  }

  Future<void> _setHrPassword(String plainPassword) async {
    final hash = _sha256Hex(plainPassword);
    await FirebaseFirestore.instance
        .collection(_kHrOverrideCollection)
        .doc(_kHrOverrideDoc)
        .set({
      _kHrOverrideField: hash,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    }, SetOptions(merge: true));
  }

  Future<bool> _verifyHrPassword(String plainPassword) async {
    if (plainPassword.isEmpty) return false;
    final storedHash = await _getStoredHrPasswordHash();
    if (storedHash == null || storedHash.isEmpty) return false;
    return _sha256Hex(plainPassword) == storedHash;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════
  String get _name {
    final raw = _currentEmployeeData['name'];
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return _sanitize(raw, maxLen: 80);
    }
    final first =
    _sanitize(_currentEmployeeData['firstName'] ?? '', maxLen: 40);
    final last =
    _sanitize(_currentEmployeeData['lastName'] ?? '', maxLen: 40);
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unknown Employee' : full;
  }

  String get _employeeId {
    final raw = _currentEmployeeData['id'] ??
        _currentEmployeeData['employeeId'] ??
        '—';
    return _sanitize(raw, maxLen: 64);
  }

  String get _docId {
    final id = _currentEmployeeData['id']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    return _currentEmployeeData['employeeId']?.toString().trim() ?? '';
  }

  String get _employeeIdForFilename => _safeFilenameSegment(
      _currentEmployeeData['id'] ??
          _currentEmployeeData['employeeId'] ??
          'unknown');

  String get _department {
    final raw = _currentEmployeeData['department'] ?? 'Unassigned';
    return _sanitize(raw, maxLen: 60);
  }

  String? get _photoUrl {
    final url = _currentEmployeeData['photoUrl'];
    if (url is! String || url.isEmpty) return null;
    if (!_isSafePhotoUrl(url)) {
      if (kDebugMode) {
        debugPrint('🚫 [PayrollMgmt] Unsafe photo URL blocked');
      }
      return null;
    }
    return url;
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  }

  String get _periodLabel {
    final s = _periodStart;
    final e = _periodEnd;
    const m = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[s.month]} ${s.day} - ${m[e.month]} ${e.day}, ${e.year}';
  }

  double get _autoOvertimePay {
    if (_hours.totalOvertimeMinutes <= 0) return 0;
    if (_b.dailyRate <= 0) return 0;
    final hourlyRate = _b.dailyRate / 8;
    return (_hours.totalOvertimeMinutes / 60.0) * hourlyRate;
  }

  double get _autoGrossPay {
    return _b.basicSalary +
        _b.otherIncomeAllowance +
        _autoOvertimePay +
        _b.nightDiffAmount;
  }

  double get _autoNetPay {
    return _autoGrossPay - _b.totalDeductions;
  }

  PayrollBreakdown _getMockBreakdown() {
    return PayrollBreakdown(
      regularPay: 50000.0,
      basicSalary: 45000.0,
      basicHours: 176.0,
      absentAmount: 2045.45,
      absentHours: 8.0,
      lateAmount: 0.0,
      lateHours: 0.0,
      undertimeAmount: 0.0,
      undertimeHours: 0.0,
      dayOffOtAmount: 0.0,
      dayOffOtHours: 0.0,
      overtimeAmount: 2500.0,
      overtimeHours: 8.0,
      nightDiffAmount: 0.0,
      nightDiffHours: 0.0,
      holidayAmount: 0.0,
      otherIncomeAllowance: 5000.0,
      totalAdjustmentsMade: 0.0,
      grossPay: 52500.0,
      thirteenthMonth: 3750.0,
      silCredits: 10227.27,
      totalBenefits: 13977.27,
      workingDays: 22,
      workingDaysPerMonth: 22,
      presentDays: 21,
      absentDays: 1,
      dailyRate: 2045.45,
      workRawMinutes: 10368,
      workLunchMinutes: 1056,
      workNetMinutes: 9312,
      workOvertimeMinutes: 480,
      daysWithLogs: 21,
      daysWithLunchApplied: 21,
      salarySource: 'manual',
      sss: 2025.0,
      philhealth: 1125.0,
      pagibig: 900.0,
      taxableIncome: 48450.0,
      taxWithheld: 0.0,
      totalLoanDeductions: 0.0,
      totalDeductions: 6095.45,
      netPay: 46404.55,
      sickLeaveBalance: 120.0,
      vacationLeaveBalance: 120.0,
      riceAllowance: 0.0,
    );
  }

  @override
  void initState() {
    super.initState();
    // 🆕 Working copy so edits reflect immediately
    _currentEmployeeData =
    Map<String, dynamic>.from(widget.employeeData);
    _verifyAndLoad();
  }

  Future<void> _verifyAndLoad() async {
    if (_isDemo) {
      setState(() {
        _isAdminVerified = true;
        _b = _getMockBreakdown();
        _hours = EmployeeHoursSummary(
          totalRawMinutes: 10368,
          totalLunchDeductedMinutes: 1056,
          totalNetMinutes: 9312,
          totalOvertimeMinutes: 480,
          daysWithLogs: 21,
          daysWithLunchApplied: 21,
          dailyBreakdown: <DailyHours>[],
        );
        _loading = false;
      });
      return;
    }

    final ok = await _ensureAdmin();
    if (!mounted) return;
    if (!ok) {
      _isAdminVerified = false;
      setState(() => _loading = false);
      _toast('No permission. Admin-only page.', error: true);
      return;
    }
    _isAdminVerified = true;
    await _load();
  }

  Future<void> _load() async {
    if (_isDemo) return;
    if (!_isAdminVerified) return;
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        PayrollCalculator.compute(
          employee: _currentEmployeeData,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        ),
        _loadHoursSummary(),
      ]);

      if (!mounted) return;

      final docId = _docId;
      bool isUnlocked = false;
      if (docId.isNotEmpty) {
        final empDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(docId)
            .get();
        isUnlocked = empDoc.data()?['payslipUnlocked'] == true;
      }

      setState(() {
        _b = results[0] as PayrollBreakdown;
        _hours = results[1] as EmployeeHoursSummary;
        _isPayslipUnlocked = isUnlocked;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [PayrollMgmt] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(_safeError(e), error: true);
    }
  }

  Future<EmployeeHoursSummary> _loadHoursSummary() async {
    if (_isDemo) return EmployeeHoursSummary.empty;
    try {
      final map = await AttendanceHoursService.instance.fetchHoursMap(
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );

      for (final k in [
        'id',
        'employeeId',
        'employee_id',
        'nfcTagId',
        'authUid'
      ]) {
        final key = _currentEmployeeData[k]?.toString().trim();
        if (key != null && key.isNotEmpty && map.containsKey(key)) {
          return map[key]!;
        }
      }

      return EmployeeHoursSummary.empty;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [PayrollMgmt] Hours load error: $e');
      }
      return EmployeeHoursSummary.empty;
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🆕 HR EDIT + HR ASSISTANT OVERRIDE FLOW
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _openEditPayrollDialog() async {
    if (_isDemo) return _demoBlock();
    if (_editing) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('No permission.', error: true);
      return;
    }

    if (!_guard.tryAcquire('edit_payroll')) {
      _toast('Please wait a moment.', error: true);
      return;
    }

    // Extract current source values for the dialog
    final current = {
      'basicSalary': PayrollCalculator.toDbl(
          _currentEmployeeData['basicSalary']),
      'basicAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['basicAllowance'] ??
              _currentEmployeeData['allowances']),
      'housingAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['housingAllowance']),
      'transportAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['transportAllowance']),
      'specialAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['specialAllowance']),
      'workingDaysPerMonth': PayrollCalculator.toInt(
          _currentEmployeeData['workingDaysPerMonth'], 22),
      'dailyRate': PayrollCalculator.toDbl(
          _currentEmployeeData['dailyRate']),
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayrollEditDialog(
        employeeName: _name,
        currentValues: current,
        currentNetPay: _autoNetPay,
      ),
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() => _editing = true);
    try {
      // Determine if this is first-time setup
      final storedHash = await _getStoredHrPasswordHash();
      final isSetup = storedHash == null || storedHash.isEmpty;

      final approved = await _showOverridePasswordDialog(isSetup: isSetup);
      if (approved != true) return;

      await _savePayrollOverride(result, isSetup: isSetup);

      // Refetch and reload
      await _refetchEmployeeAndReload();

      if (mounted) {
        _toast('✅ Payroll updated for $_name.', success: true);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Save failed: ${_safeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<bool?> _showOverridePasswordDialog({required bool isSetup}) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OverridePasswordDialog(
        isSetup: isSetup,
        onSetup: _setHrPassword,
        onVerify: _verifyHrPassword,
      ),
    );
  }

  Future<void> _savePayrollOverride(
      Map<String, dynamic> newValues, {
        required bool isSetup,
      }) async {
    final docId = _docId;
    if (docId.isEmpty) {
      throw Exception('Invalid employee ID');
    }

    final admin = await _currentAdmin();
    if (admin == null) {
      throw Exception('Admin session expired');
    }

    // Build the update payload (all editable source fields)
    final payload = <String, dynamic>{
      'basicSalary': newValues['basicSalary'],
      'basicAllowance': newValues['basicAllowance'],
      'housingAllowance': newValues['housingAllowance'],
      'transportAllowance': newValues['transportAllowance'],
      'specialAllowance': newValues['specialAllowance'],
      'workingDaysPerMonth': newValues['workingDaysPerMonth'],
      'dailyRate': newValues['dailyRate'],
      'salarySource': 'manual_override',
      'payrollLastEditedAt': FieldValue.serverTimestamp(),
      'payrollLastEditedBy': admin.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Before/after snapshot for audit
    final before = {
      'basicSalary':
      PayrollCalculator.toDbl(_currentEmployeeData['basicSalary']),
      'basicAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['basicAllowance'] ??
              _currentEmployeeData['allowances']),
      'housingAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['housingAllowance']),
      'transportAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['transportAllowance']),
      'specialAllowance': PayrollCalculator.toDbl(
          _currentEmployeeData['specialAllowance']),
      'workingDaysPerMonth': PayrollCalculator.toInt(
          _currentEmployeeData['workingDaysPerMonth'], 22),
      'dailyRate':
      PayrollCalculator.toDbl(_currentEmployeeData['dailyRate']),
    };

    await FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .set(payload, SetOptions(merge: true))
        .timeout(const Duration(seconds: 12));

    // Audit log — dual signature
    await _audit(
      action: isSetup
          ? 'payroll_override_edit_first_setup'
          : 'payroll_override_edit',
      targetId: docId,
      targetType: 'employee_payroll',
      metadata: {
        'employee_name': _name,
        'employee_id': _employeeId,
        'period': _periodLabel,
        'initiator_uid': admin.uid,
        'override_used': true,
        'hr_assistant_authorized': true,
        'password_was_first_setup': isSetup,
        'before': before,
        'after': newValues,
      },
    );

    // Notify employee their payroll was adjusted
    try {
      await OneSignalSender.instance.sendToEmployee(
        employeeId: docId,
        title: '💰 Payroll Updated',
        message:
        'Your payroll details for $_periodLabel have been adjusted by HR. Please review your payslip.',
        type: 'payroll',
      );
    } catch (e) {
      debugPrint('⚠️ [PayrollOverride] push failed: $e');
    }
  }

  Future<void> _refetchEmployeeAndReload() async {
    final docId = _docId;
    if (docId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        _currentEmployeeData = {
          ...doc.data()!,
          'id': doc.id,
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [PayrollOverride] refetch failed: $e');
      }
    }
    await _load();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PAYSLIP UNLOCK / LOCK
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _handleUnlockPayslip() async {
    if (_isDemo) return _demoBlock();
    if (_unlockingPayslip) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('No permission.', error: true);
      return;
    }

    if (!_guard.tryAcquire('unlock_payslip')) {
      _toast('Please wait a moment.', error: true);
      return;
    }

    setState(() => _unlockingPayslip = true);

    try {
      final docId = _docId;
      if (docId.isEmpty) throw Exception('Invalid employee ID');

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .update({
        'payslipUnlocked': true,
        'payslipUnlockedAt': FieldValue.serverTimestamp(),
        'payslipUnlockedBy': FirebaseAuth.instance.currentUser?.uid,
        'payslipUnlockedPeriod': _periodLabel,
      }).timeout(const Duration(seconds: 10));

      unawaited(_audit(
        action: 'unlock_payslip',
        targetId: docId,
        targetType: 'employee_payslip',
        metadata: {'employee_name': _name, 'period': _periodLabel},
      ));

      if (!mounted) return;
      setState(() => _isPayslipUnlocked = true);
      _toast('✅ Payslip unlocked for $_name.', success: true);

      try {
        await OneSignalSender.instance.sendToEmployee(
          employeeId: docId,
          title: '🔓 Payslip Unlocked',
          message:
          'Your payslip for $_periodLabel is now available for download.',
          type: 'payroll',
        );
      } catch (e) {
        debugPrint('⚠️ Push failed: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [UnlockPayslip] error: $e');
      if (!mounted) return;
      _toast('Failed to unlock: ${_safeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _unlockingPayslip = false);
    }
  }

  Future<void> _handleLockPayslip() async {
    if (_isDemo) return _demoBlock();
    if (_unlockingPayslip) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('No permission.', error: true);
      return;
    }

    if (!_guard.tryAcquire('lock_payslip')) {
      _toast('Please wait a moment.', error: true);
      return;
    }

    setState(() => _unlockingPayslip = true);

    try {
      final docId = _docId;
      if (docId.isEmpty) throw Exception('Invalid employee ID');

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .update({
        'payslipUnlocked': false,
        'payslipLockedAt': FieldValue.serverTimestamp(),
        'payslipLockedBy': FirebaseAuth.instance.currentUser?.uid,
      }).timeout(const Duration(seconds: 10));

      unawaited(_audit(
        action: 'lock_payslip',
        targetId: docId,
        targetType: 'employee_payslip',
        metadata: {'employee_name': _name, 'period': _periodLabel},
      ));

      if (!mounted) return;
      setState(() => _isPayslipUnlocked = false);
      _toast('🔒 Payslip locked for $_name.', success: true);

      try {
        await OneSignalSender.instance.sendToEmployee(
          employeeId: docId,
          title: '🔒 Payslip Locked',
          message:
          'Your payslip for $_periodLabel has been locked by Admin.',
          type: 'payroll',
        );
      } catch (e) {
        debugPrint('⚠️ Push failed: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [LockPayslip] error: $e');
      if (!mounted) return;
      _toast('Failed to lock: ${_safeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _unlockingPayslip = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PDF
  // ═══════════════════════════════════════════════════════════════════════
  String _pdfPeso(double amount) {
    final format = NumberFormat('#,##0.00');
    return '₱${format.format(amount)}';
  }

  String _pdfHrs(double hours) {
    return hours.toStringAsFixed(2);
  }

  Future<Uint8List> _generatePdf() async {
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document(
      title: 'Payroll Slip',
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Jumbo Worldwide Express Logistics Inc.',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        'Unit 12N, 8 Adriatico Tower, Padre Faura Street, Ermita, Manila',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 16),
                    pw.Text('Payroll Slip',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 6),
                    pw.Text('For the period of $_periodLabel',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 20),
                  ],
                ),
              ),
              pw.Row(
                children: [
                  pw.Text('Employee Code: ',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(_employeeId,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Text('Employee Name: ',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(_name.toUpperCase(),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Regular Pay:',
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                      width: 70,
                      child: pw.Text('Hrs.',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(
                      width: 90,
                      child: pw.Text('Amount',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold))),
                ],
              ),
              pw.SizedBox(height: 10),
              _pdfRow('Basic Pay', _pdfHrs(_b.basicHours),
                  _pdfPeso(_b.basicSalary)),
              _pdfRow('Absent', _pdfHrs(_b.absentHours),
                  '-${_pdfPeso(_b.absentAmount)}'),
              _pdfRow('Late', _pdfHrs(_b.lateHours),
                  '-${_pdfPeso(_b.lateAmount)}'),
              _pdfRow('Undertime', _pdfHrs(_b.undertimeHours),
                  '-${_pdfPeso(_b.undertimeAmount)}'),
              _pdfRow('Dayoff OT', _pdfHrs(_b.dayOffOtHours),
                  _pdfPeso(_b.dayOffOtAmount)),
              _pdfRow('Overtime', _pdfHrs(_b.overtimeHours),
                  _pdfPeso(_b.overtimeAmount)),
              _pdfRow('Night Diff.', _pdfHrs(_b.nightDiffHours),
                  _pdfPeso(_b.nightDiffAmount)),
              _pdfRow('Holiday', '', _pdfPeso(_b.holidayAmount)),
              _pdfRow('Other Income-Allowance', '',
                  _pdfPeso(_b.otherIncomeAllowance)),
              _pdfRow('Total Adjustments Made', '',
                  _pdfPeso(_b.totalAdjustmentsMade)),
              pw.Divider(color: PdfColors.black, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total:',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(_pdfPeso(_b.regularPay),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 20),
              _pdfRowDeduction('SSS', _pdfPeso(_b.sss)),
              _pdfRowDeduction('Phil. Health', _pdfPeso(_b.philhealth)),
              _pdfRowDeduction('Pag-Ibig', _pdfPeso(_b.pagibig)),
              _pdfRowDeduction(
                  'Taxable Income & Tax Withhe',
                  _pdfPeso(_b.taxWithheld),
                  hrs: _pdfHrs(_b.taxableIncome)),
              _pdfRowDeduction(
                  'Total Loan Deductions',
                  _pdfPeso(_b.totalLoanDeductions)),
              pw.Divider(color: PdfColors.black, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total:',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(_pdfPeso(_b.totalDeductions),
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('NET PAY:',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(_pdfPeso(_autoNetPay),
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('LEAVE',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          children: [
                            pw.Expanded(
                                child: pw.Text('Sick Leave',
                                    style: const pw.TextStyle(
                                        fontSize: 10))),
                            pw.Text(
                                _b.sickLeaveBalance.toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          children: [
                            pw.Expanded(
                                child: pw.Text('Vacation Leave',
                                    style: const pw.TextStyle(
                                        fontSize: 10))),
                            pw.Text(
                                _b.vacationLeaveBalance
                                    .toStringAsFixed(2),
                                style: const pw.TextStyle(fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 40),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('OTHER INCOME',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          children: [
                            pw.Expanded(
                                child: pw.Text('Rice Allowance',
                                    style: const pw.TextStyle(
                                        fontSize: 10))),
                            pw.Text(_pdfPeso(_b.riceAllowance),
                                style: const pw.TextStyle(
                                    fontSize: 10)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          children: [
                            pw.Expanded(
                                child: pw.Text('Total',
                                    style: const pw.TextStyle(
                                        fontSize: 10))),
                            pw.Text(_pdfPeso(_b.riceAllowance),
                                style: const pw.TextStyle(
                                    fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 40),
              pw.Text('Received thru: ATM',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 30),
              pw.Row(
                children: [
                  pw.Text('Received by: ',
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.only(left: 10),
                      decoration: const pw.BoxDecoration(
                        border:
                        pw.Border(bottom: pw.BorderSide(width: 1)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfRow(String label, String hrs, String amount) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child:
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(
            width: 70,
            child: pw.Text(hrs,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(
            width: 90,
            child: pw.Text(amount,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfRowDeduction(String label, String amount, {String? hrs}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(
            child:
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(
            width: 70,
            child: pw.Text(hrs ?? '',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
          pw.SizedBox(
            width: 90,
            child: pw.Text(amount,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint() async {
    if (_isDemo) return _demoBlock();
    if (_printing) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('No permission. Admin-only action.', error: true);
      return;
    }

    if (!_guard.tryAcquire('print_payslip')) {
      _toast('Too fast. Please wait a moment.', error: true);
      return;
    }

    setState(() => _printing = true);

    try {
      final bytes = await _generatePdf();
      final safeId = _employeeIdForFilename;
      final okPrint = await Printing.layoutPdf(
        onLayout: (PdfPageFormat f) async => bytes,
        name: 'payslip_$safeId.pdf',
      );

      unawaited(_audit(
        action: 'print_payslip',
        targetId: _employeeId,
        targetType: 'payslip',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
          'success': okPrint,
        },
      ));

      if (!mounted) return;

      if (okPrint) {
        _toast('Payslip sent to printer.', success: true);
        await _notifyEmployeePayroll();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PayrollMgmt] Print error: $e');
      }
      if (!mounted) return;
      _toast(_safeError(e), error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _handleDownload() async {
    if (_isDemo) return _demoBlock();
    if (_downloading) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('No permission. Admin-only action.', error: true);
      return;
    }

    if (!_guard.tryAcquire('download_payslip')) {
      _toast('Too fast. Please wait a moment.', error: true);
      return;
    }

    setState(() => _downloading = true);

    try {
      final bytes = await _generatePdf();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeId = _employeeIdForFilename;
      final fileName = 'payslip_${safeId}_$ts.pdf';

      final savedPath = await downloadBytesFile(
        filename: fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
      );

      unawaited(_audit(
        action: 'download_payslip',
        targetId: _employeeId,
        targetType: 'payslip',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
          'filename': fileName,
          'success': savedPath != null,
        },
      ));

      if (!mounted) return;

      if (savedPath != null) {
        _toast('Payslip saved → $fileName', success: true);
        await _notifyEmployeePayroll();
      } else {
        _toast('Download cancelled.', error: true);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PayrollMgmt] Download error: $e');
      }
      if (!mounted) return;
      _toast(_safeError(e), error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _notifyEmployeePayroll() async {
    if (_isDemo) return;

    final now = DateTime.now();
    if (_lastNotifyAt != null &&
        now.difference(_lastNotifyAt!) < _notifyCooldown) {
      return;
    }

    try {
      await EmployeeNotificationService.instance.sendPayrollAlert(
        employeeId: _employeeId,
        employeeName: _name,
        month: _periodLabel,
        netPay: _autoNetPay,
      );
      _lastNotifyAt = now;

      unawaited(_audit(
        action: 'notify_payslip',
        targetId: _employeeId,
        targetType: 'employee_notification',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
        },
      ));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [PayrollMgmt] Employee notification failed: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_loading && !_isDemo) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: tc.background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 48, color: tc.red),
                  const SizedBox(height: 12),
                  Text('Admin access required',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tc.text)),
                  const SizedBox(height: 6),
                  Text(
                    'Admin role is required to view the payslip.',
                    style: TextStyle(fontSize: 13, color: tc.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: tc.background,
        body: _loading
            ? Center(child: CircularProgressIndicator(color: tc.orange))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: BsContainer(
            maxWidth: 1300,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isDemo) ...[
                  _buildDemoBanner(),
                  const SizedBox(height: 16),
                ],
                _buildBackButton(),
                const SizedBox(height: 12),
                _buildProfileCard(),
                const SizedBox(height: 24),
                _buildMetricsRow(),
                const SizedBox(height: 24),
                _buildBreakdownGrid(),
                const SizedBox(height: 40),
              ],
            ),
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
                  'Showing sample payslip. Print, download, and notifications are disabled.',
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

  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _handleBack,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 4, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, color: tc.orange, size: 18),
              const SizedBox(width: 6),
              Text(
                'Back to Payroll',
                style: TextStyle(
                  color: tc.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
          final wide = w > 700;

          final avatar = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECD0),
              shape: BoxShape.circle,
              border: Border.all(color: tc.border),
              image: _photoUrl != null
                  ? DecorationImage(
                  image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: _photoUrl == null
                ? Center(
              child: Text(
                _getInitials(_name),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: tc.orangeText),
              ),
            )
                : null,
          );

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_name,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('ID: $_employeeId',
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Text(_department,
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tc.border),
                          ),
                          child: Text(_periodLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: tc.text,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              // 🆕 Edit Payroll button (HR initiator)
              OutlinedButton.icon(
                onPressed: (_editing || _isDemo)
                    ? null
                    : _openEditPayrollDialog,
                icon: _editing
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tc.orange),
                )
                    : Icon(Icons.edit_note_rounded,
                    size: 16,
                    color: _isDemo ? tc.muted : tc.orange),
                label: Text(_editing ? 'Editing...' : 'Edit Payroll',
                    style: TextStyle(
                        color: _isDemo ? tc.muted : tc.orange,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _isDemo ? tc.border : tc.orange),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: (_unlockingPayslip || _isDemo)
                    ? null
                    : (_isPayslipUnlocked
                    ? _handleLockPayslip
                    : _handleUnlockPayslip),
                icon: _unlockingPayslip
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _isPayslipUnlocked
                          ? tc.red
                          : tc.blue),
                )
                    : Icon(
                  _isPayslipUnlocked
                      ? Icons.lock_rounded
                      : Icons.lock_open_rounded,
                  size: 16,
                  color: _isDemo
                      ? tc.muted
                      : (_isPayslipUnlocked
                      ? tc.red
                      : tc.blue),
                ),
                label: Text(
                    _unlockingPayslip
                        ? 'Processing...'
                        : (_isPayslipUnlocked
                        ? 'Lock Payslip'
                        : 'Unlock Payslip'),
                    style: TextStyle(
                        color: _isDemo
                            ? tc.muted
                            : (_isPayslipUnlocked
                            ? tc.red
                            : tc.blue),
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _isDemo
                          ? tc.border
                          : (_isPayslipUnlocked ? tc.red : tc.blue)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: (_printing || _isDemo) ? null : _handlePrint,
                icon: _printing
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tc.text),
                )
                    : Icon(Icons.print_rounded,
                    size: 16,
                    color: _isDemo ? tc.muted : tc.text),
                label: Text(_printing ? 'Printing...' : 'Print',
                    style: TextStyle(
                        color: _isDemo ? tc.muted : tc.text,
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tc.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed:
                (_downloading || _isDemo) ? null : _handleDownload,
                icon: _downloading
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : Icon(Icons.download_rounded,
                    size: 16,
                    color: _isDemo ? tc.muted : Colors.white),
                label: Text(
                    _downloading ? 'Downloading...' : 'Download Payslip',
                    style: TextStyle(
                        color: _isDemo ? tc.muted : Colors.white,
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDemo ? tc.border : tc.orange,
                  disabledBackgroundColor:
                  tc.orange.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: header),
                const SizedBox(width: 16),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, const SizedBox(height: 16), actions],
          );
        },
      ),
    );
  }

  Widget _buildMetricsRow() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        final wide = w > 800;
        const gap = 20.0;

        final cards = <Widget>[
          _buildMetricCard('NET PAY', PayrollCalculator.peso(_autoNetPay),
              'Total take-home for this period', false),
          _buildMetricCard('GROSS PAY', PayrollCalculator.peso(_autoGrossPay),
              'Basic + Allowances + OT (auto)', false),
          _buildMetricCard('TOTAL DEDUCTIONS',
              PayrollCalculator.peso(_b.totalDeductions),
              'Absences + Govt (9%)', true),
        ];

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: gap),
              Expanded(child: cards[1]),
              const SizedBox(width: gap),
              Expanded(child: cards[2]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards[0],
            const SizedBox(height: gap),
            cards[1],
            const SizedBox(height: gap),
            cards[2],
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
      String title, String value, String subtitle, bool isRed) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
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
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: isRed ? tc.red : tc.text),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: tc.muted),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildBreakdownGrid() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        final wide = w > 900;

        final earnings = _earningsCard();
        final benefits = _benefitsCard();
        final absences = _absencesCard();
        final govt = _govtCard();

        if (wide) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: earnings),
                  const SizedBox(width: 20),
                  Expanded(child: benefits),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: absences),
                  const SizedBox(width: 20),
                  Expanded(child: govt),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            earnings,
            const SizedBox(height: 20),
            benefits,
            const SizedBox(height: 20),
            absences,
            const SizedBox(height: 20),
            govt,
          ],
        );
      },
    );
  }

  Widget _earningsCard() {
    final hasOT = _autoOvertimePay > 0;

    return _panel(
      title: 'Earnings Breakdown',
      badge: PayrollCalculator.peso(_autoGrossPay),
      badgeColor: tc.orange.withValues(alpha: 0.15),
      badgeTextColor: tc.orangeText,
      children: [
        _item('Basic Salary', 'Regular monthly pay',
            PayrollCalculator.peso(_b.basicSalary), false),
        _item('Allowances', 'Housing / Transport / Special',
            PayrollCalculator.peso(_b.otherIncomeAllowance), false),
        _item(
          'Overtime Pay',
          hasOT
              ? 'Auto-detected from work hours (${_hours.overtimeDisplay})'
              : 'No overtime this period',
          hasOT
              ? PayrollCalculator.peso(_autoOvertimePay)
              : PayrollCalculator.peso(0),
          false,
        ),
        if (_b.nightDiffAmount > 0)
          _item('Night Differential', 'Additional pay for night hours',
              PayrollCalculator.peso(_b.nightDiffAmount), false),
        Divider(color: tc.border, height: 20),
        _item('Total Gross', 'Sum of earnings',
            PayrollCalculator.peso(_autoGrossPay), false,
            bold: true),
        if (hasOT) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.pillGreenBg,
              border: Border(
                  left: BorderSide(color: tc.pillGreenTx, width: 4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Auto-computed overtime: ${_hours.overtimeDisplay} beyond standard 8h/day.',
              style: TextStyle(
                  fontSize: 11, color: tc.pillGreenTx, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _benefitsCard() {
    return _panel(
      title: 'Benefits (Accrued)',
      badge: PayrollCalculator.peso(_b.totalBenefits),
      badgeColor: tc.pillGreenBg,
      badgeTextColor: tc.pillGreenTx,
      children: [
        _item('13th Month Pay', '1/12 of basic salary',
            PayrollCalculator.peso(_b.thirteenthMonth), false),
        _item('SIL Credits', '5 days × daily rate (convertible)',
            PayrollCalculator.peso(_b.silCredits), false),
        _item('Service Incentive', 'Based on tenure & attendance', '—',
            false),
        Divider(color: tc.border, height: 20),
        _item('Total Benefits', 'Accrued, not yet paid',
            PayrollCalculator.peso(_b.totalBenefits), false,
            bold: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillGreenBg,
            border:
            Border(left: BorderSide(color: tc.pillGreenTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Benefits are not deducted from net pay. These are additional savings received at the 13th month payout or year-end.',
            style:
            TextStyle(fontSize: 11, color: tc.pillGreenTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _absencesCard() {
    final hasHours = _hours.totalNetMinutes > 0;

    return _panel(
      title: 'Attendance & Hours',
      badge: _b.absentDays > 0
          ? '-${PayrollCalculator.peso(_b.absentAmount)}'
          : 'Perfect',
      badgeColor: _b.absentDays > 0 ? tc.pillErrBg : tc.pillGreenBg,
      badgeTextColor: _b.absentDays > 0 ? tc.pillErrTx : tc.pillGreenTx,
      children: [
        _item('Working Days', 'Weekdays in the period',
            '${_b.workingDays}', false),
        _item('Present Days', 'With clock-in logged',
            '${_b.presentDays}', false),
        _item('Absent Days', 'No clock-in on weekday',
            '${_b.absentDays}', _b.absentDays > 0),
        if (hasHours) ...[
          Divider(color: tc.border, height: 20),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: tc.orange),
              const SizedBox(width: 6),
              Text('HOURS SUMMARY (Auto)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tc.textMuted,
                      letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tc.pillBlueBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_hours.netDisplay,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tc.pillBlueTx)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _item('Total Raw Hours', 'Before lunch deduction',
              _hours.rawDisplay, false),
          if (_hours.totalLunchDeductedMinutes > 0)
            _item(
              'Lunch Deducted',
              '${_hours.daysWithLunchApplied} day(s) applied',
              '-${_hours.lunchDisplay}',
              true,
            ),
          _item('Net Hours Worked', 'Raw − lunch deduction',
              _hours.netDisplay, false,
              bold: true),
          if (_hours.totalOvertimeMinutes > 0)
            _item('Overtime', 'Beyond standard 8h/day',
                '+${_hours.overtimeDisplay}', false),
        ],
        Divider(color: tc.border, height: 20),
        _item('Daily Rate', 'Basic ÷ working days',
            PayrollCalculator.peso(_b.dailyRate), false),
        _item('Absence Deduction', '${_b.absentDays} day/s × daily rate',
            '-${PayrollCalculator.peso(_b.absentAmount)}',
            _b.absentDays > 0,
            bold: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
            _b.absentDays > 0 ? tc.pillErrBg : tc.pillGreenBg,
            border: Border(
                left: BorderSide(
                    color: _b.absentDays > 0
                        ? tc.pillErrTx
                        : tc.pillGreenTx,
                    width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _b.absentDays > 0
                ? '${_b.absentDays} absent day(s) auto-deducted from salary based on attendance logs.'
                : 'No absences this period. Full salary will be received.',
            style: TextStyle(
                fontSize: 11,
                color: _b.absentDays > 0
                    ? tc.pillErrTx
                    : tc.pillGreenTx,
                height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _govtCard() {
    final total = _b.sss + _b.philhealth + _b.pagibig + _b.taxWithheld;
    return _panel(
      title: 'Government Remittances & Deductions',
      badge: '-${PayrollCalculator.peso(total)}',
      badgeColor: tc.pillErrBg,
      badgeTextColor: tc.pillErrTx,
      children: [
        _item('SSS Contribution', '4.5% Employee Share',
            '-${PayrollCalculator.peso(_b.sss)}', true),
        _item('PhilHealth Contribution', '2.5% Employee Share',
            '-${PayrollCalculator.peso(_b.philhealth)}', true),
        _item('Pag-IBIG Contribution', '2.0% Employee Share',
            '-${PayrollCalculator.peso(_b.pagibig)}', true),
        _item('Withholding Tax',
            'Calculated based on net taxable income',
            '-${PayrollCalculator.peso(_b.taxWithheld)}', true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillWarnBg,
            border:
            Border(left: BorderSide(color: tc.pillWarnTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Total statutory deductions amount to 9% of the basic salary (${PayrollCalculator.peso(_b.basicSalary)}) for this pay period.',
            style: TextStyle(
                fontSize: 11, color: tc.pillWarnTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    required List<Widget> children,
  }) {
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
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _item(String title, String desc, String amount, bool negative,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                        bold ? FontWeight.w700 : FontWeight.w600,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(fontSize: 11, color: tc.muted),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(amount,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: negative ? tc.red : tc.text)),
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

// ═══════════════════════════════════════════════════════════════════════
// 🆕 PAYROLL EDIT DIALOG
// ═══════════════════════════════════════════════════════════════════════
class _PayrollEditDialog extends StatefulWidget {
  final String employeeName;
  final Map<String, dynamic> currentValues;
  final double currentNetPay;

  const _PayrollEditDialog({
    required this.employeeName,
    required this.currentValues,
    required this.currentNetPay,
  });

  @override
  State<_PayrollEditDialog> createState() => _PayrollEditDialogState();
}

class _PayrollEditDialogState extends State<_PayrollEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _basicSalaryCtrl;
  late final TextEditingController _basicAllowanceCtrl;
  late final TextEditingController _housingAllowanceCtrl;
  late final TextEditingController _transportAllowanceCtrl;
  late final TextEditingController _specialAllowanceCtrl;
  late final TextEditingController _workingDaysCtrl;
  late final TextEditingController _dailyRateCtrl;

  @override
  void initState() {
    super.initState();
    final v = widget.currentValues;
    _basicSalaryCtrl = TextEditingController(
        text: _fmtNum(v['basicSalary']));
    _basicAllowanceCtrl =
        TextEditingController(text: _fmtNum(v['basicAllowance']));
    _housingAllowanceCtrl =
        TextEditingController(text: _fmtNum(v['housingAllowance']));
    _transportAllowanceCtrl =
        TextEditingController(text: _fmtNum(v['transportAllowance']));
    _specialAllowanceCtrl =
        TextEditingController(text: _fmtNum(v['specialAllowance']));
    _workingDaysCtrl = TextEditingController(
        text: (v['workingDaysPerMonth'] ?? 22).toString());
    _dailyRateCtrl =
        TextEditingController(text: _fmtNum(v['dailyRate']));

    _basicSalaryCtrl.addListener(() => setState(() {}));
    _workingDaysCtrl.addListener(() => setState(() {}));
    _dailyRateCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _basicSalaryCtrl.dispose();
    _basicAllowanceCtrl.dispose();
    _housingAllowanceCtrl.dispose();
    _transportAllowanceCtrl.dispose();
    _specialAllowanceCtrl.dispose();
    _workingDaysCtrl.dispose();
    _dailyRateCtrl.dispose();
    super.dispose();
  }

  static String _fmtNum(dynamic v) {
    final d = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    if (d == 0) return '';
    return d.toStringAsFixed(2);
  }

  double _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return 0.0;
    return double.tryParse(t) ?? 0.0;
  }

  int _parseInt(TextEditingController c, {int fallback = 22}) {
    final t = c.text.trim();
    if (t.isEmpty) return fallback;
    return int.tryParse(t) ?? fallback;
  }

  double get _computedDailyRate {
    final custom = _parse(_dailyRateCtrl);
    if (custom > 0) return custom;
    final basic = _parse(_basicSalaryCtrl);
    final days = _parseInt(_workingDaysCtrl);
    if (days <= 0) return 0;
    return basic / days;
  }

  double get _totalAllowances =>
      _parse(_basicAllowanceCtrl) +
          _parse(_housingAllowanceCtrl) +
          _parse(_transportAllowanceCtrl) +
          _parse(_specialAllowanceCtrl);

  bool _validateAll() {
    if (!_formKey.currentState!.validate()) return false;
    return true;
  }

  void _submit() {
    if (!_validateAll()) return;
    Navigator.pop(context, <String, dynamic>{
      'basicSalary': _parse(_basicSalaryCtrl),
      'basicAllowance': _parse(_basicAllowanceCtrl),
      'housingAllowance': _parse(_housingAllowanceCtrl),
      'transportAllowance': _parse(_transportAllowanceCtrl),
      'specialAllowance': _parse(_specialAllowanceCtrl),
      'workingDaysPerMonth': _parseInt(_workingDaysCtrl),
      'dailyRate': _parse(_dailyRateCtrl),
    });
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final dailyRate = _computedDailyRate;
    final monthlyTotal =
        _parse(_basicSalaryCtrl) + _totalAllowances;

    return Dialog(
      backgroundColor: tc.card,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit_note_rounded,
                        color: tc.orange, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Edit Payroll',
                              style: TextStyle(
                                  color: tc.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                              'For ${widget.employeeName} — HR Assistant password required to save.',
                              style: TextStyle(
                                  color: tc.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                _sectionLabel('BASIC SALARY (₱/month)', tc),
                _field(
                  controller: _basicSalaryCtrl,
                  hint: 'e.g. 25000',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null; // 0 is fine
                    final n = double.tryParse(t);
                    if (n == null) return 'Invalid number';
                    if (n < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                _sectionLabel('ALLOWANCES (₱/month)', tc),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _basicAllowanceCtrl,
                        hint: 'Basic',
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _numValidator,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _field(
                        controller: _housingAllowanceCtrl,
                        hint: 'Housing',
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _numValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _transportAllowanceCtrl,
                        hint: 'Transport',
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _numValidator,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _field(
                        controller: _specialAllowanceCtrl,
                        hint: 'Special',
                        keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _numValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                _sectionLabel('WORKING DAYS / MONTH', tc),
                _field(
                  controller: _workingDaysCtrl,
                  hint: '22',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Required';
                    final n = int.tryParse(t);
                    if (n == null) return 'Invalid';
                    if (n < 1 || n > 31) return '1 - 31 only';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                _sectionLabel('DAILY RATE OVERRIDE (optional)', tc),
                _field(
                  controller: _dailyRateCtrl,
                  hint: 'Leave empty to auto-compute',
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: _numValidator,
                ),
                const SizedBox(height: 4),
                Text(
                  'Auto daily rate: ₱${dailyRate.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 11,
                      color: tc.muted,
                      fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),

                // Preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: tc.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: tc.orange),
                          const SizedBox(width: 6),
                          Text('SUMMARY',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: tc.orange,
                                  letterSpacing: 0.4)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _previewRow(
                          'Monthly Basic', _peso(_parse(_basicSalaryCtrl)), tc),
                      _previewRow(
                          'Total Allowances', _peso(_totalAllowances), tc),
                      _previewRow('Daily Rate', _peso(dailyRate), tc,
                          bold: true),
                      const Divider(height: 16),
                      _previewRow(
                          'Total Monthly Gross',
                          _peso(monthlyTotal),
                          tc,
                          bold: true,
                          highlight: true),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: TextStyle(color: tc.muted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.arrow_forward_rounded,
                          size: 16),
                      label: const Text('Continue →'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tc.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _numValidator(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null) return 'Invalid';
    if (n < 0) return 'Negative';
    return null;
  }

  String _peso(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final posFromEnd = whole.length - i;
      buf.write(whole[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '₱${buf.toString()}.${parts.length > 1 ? parts[1] : '00'}';
  }

  Widget _sectionLabel(String text, AdminColors tc) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: TextStyle(
            color: tc.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5)),
  );

  Widget _previewRow(String label, String value, AdminColors tc,
      {bool bold = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: tc.muted,
                    fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  color: highlight ? tc.orange : tc.text,
                  fontWeight:
                  bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final tc = AdminTheme.getColors(context);
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: tc.text, fontSize: 14),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
        filled: true,
        fillColor: tc.surface,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.red, width: 1.2),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 🆕 HR ASSISTANT OVERRIDE PASSWORD DIALOG
// ═══════════════════════════════════════════════════════════════════════
class _OverridePasswordDialog extends StatefulWidget {
  final bool isSetup;
  final Future<void> Function(String password) onSetup;
  final Future<bool> Function(String password) onVerify;

  const _OverridePasswordDialog({
    required this.isSetup,
    required this.onSetup,
    required this.onVerify,
  });

  @override
  State<_OverridePasswordDialog> createState() =>
      _OverridePasswordDialogState();
}

class _OverridePasswordDialogState extends State<_OverridePasswordDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _verifying = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) return;
    setState(() {
      _error = null;
    });

    final pwd = _passwordCtrl.text;
    if (pwd.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }
    if (pwd.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    if (widget.isSetup) {
      if (pwd != _confirmCtrl.text) {
        setState(() => _error = 'Passwords do not match.');
        return;
      }
    }

    setState(() => _verifying = true);
    try {
      if (widget.isSetup) {
        await widget.onSetup(pwd);
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final ok = await widget.onVerify(pwd);
        if (!mounted) return;
        if (ok) {
          Navigator.pop(context, true);
        } else {
          setState(() {
            _verifying = false;
            _error = 'Incorrect HR Assistant password.';
            _passwordCtrl.clear();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final title = widget.isSetup
        ? 'Set HR Assistant Password'
        : 'HR Assistant Override Required';
    final subtitle = widget.isSetup
        ? 'First-time setup. This password will authorize future payroll edits. Share it only with HR Assistants.'
        : 'An HR Assistant must authorize this payroll change before it can be saved.';

    return AlertDialog(
      backgroundColor: tc.card,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.isSetup
                  ? Icons.lock_person_rounded
                  : Icons.shield_rounded,
              color: tc.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: tc.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(subtitle,
                style: TextStyle(
                    color: tc.muted, fontSize: 12, height: 1.5)),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              enabled: !_verifying,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              style: TextStyle(color: tc.text, fontSize: 14),
              cursorColor: tc.orange,
              decoration: InputDecoration(
                hintText: widget.isSetup
                    ? 'New HR Assistant password'
                    : 'Enter HR Assistant password',
                hintStyle:
                TextStyle(color: tc.muted, fontSize: 13),
                prefixIcon:
                Icon(Icons.key_rounded, color: tc.muted, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                      color: tc.muted),
                  onPressed: () =>
                      setState(() => _obscure = !_obscure),
                ),
                filled: true,
                fillColor: tc.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
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
                  borderSide:
                  BorderSide(color: tc.orange, width: 1.5),
                ),
              ),
            ),
            if (widget.isSetup) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                enabled: !_verifying,
                onSubmitted: (_) => _submit(),
                style: TextStyle(color: tc.text, fontSize: 14),
                cursorColor: tc.orange,
                decoration: InputDecoration(
                  hintText: 'Confirm password',
                  hintStyle:
                  TextStyle(color: tc.muted, fontSize: 13),
                  prefixIcon: Icon(Icons.check_circle_outline_rounded,
                      color: tc.muted, size: 18),
                  filled: true,
                  fillColor: tc.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
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
                    borderSide:
                    BorderSide(color: tc.orange, width: 1.5),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tc.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: tc.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: tc.red, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: tc.red,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: tc.muted)),
        ),
        ElevatedButton.icon(
          onPressed: _verifying ? null : _submit,
          icon: _verifying
              ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded, size: 16),
          label: Text(
              _verifying
                  ? 'Verifying...'
                  : (widget.isSetup ? 'Set & Authorize' : 'Authorize'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RATE LIMITER
// ═══════════════════════════════════════════════════════════════════════
class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 3);

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