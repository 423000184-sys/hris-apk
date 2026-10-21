// lib/screens/reports_screen.dart
// v2.6: 🔓 Admin can manually unlock payslips (bypasses end-of-month rule).
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/dao/connectivity_service.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/payroll_calculator.dart';
import '../services/payroll_pdf_service.dart';
import '../services/support_request_service.dart';
import '../services/demo_mode_service.dart';
import '../models/employee.dart';
import '../widgets/skeleton_screens.dart';
import 'login_screen.dart';

// ══════════════════════════════════════════════════════════════
// WATERMARK
// ══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';
double _degToRad(double deg) => deg * 3.1415926535 / 180;

Widget _buildHandWatermark({required double opacity}) {
  return Positioned(
    bottom: -130,
    left: -150,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: _degToRad(425),
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color.fromRGBO(255, 138, 0, 0.10),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              _kLogoAsset,
              width: 500,
              height: 500,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════
// SECURITY HELPERS
// ══════════════════════════════════════════════════════════════
String _generateSessionNonce() {
  final rand = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _hashEmployeeId(String empId, String nonce) {
  return sha256.convert(utf8.encode('$empId::$nonce')).toString();
}

Future<void> _logSecurityEventGlobal({
  required String type,
  required String severity,
  required String details,
  String? employeeId,
  String? sessionNonce,
  bool sensitive = false,
}) async {
  if (DemoModeService.instance.isEnabled) return;

  try {
    final doc = <String, dynamic>{
      'type': type,
      'severity': severity,
      'details': details,
      'employeeId': sensitive ? null : employeeId,
      'employeeIdHash': employeeId != null
          ? _hashEmployeeId(employeeId, sessionNonce ?? '')
          : null,
      'sessionNonce': sessionNonce,
      'platform': kIsWeb ? 'web' : 'mobile',
      'stage': 'reports_payslip',
      'timestamp': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('security_events')
        .add(doc)
        .timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('⚠️ [ReportsSecurity] log error: $e');
  }
}

String _maskString(String input, {int showStart = 2, int showEnd = 2}) {
  if (input.isEmpty) return '';
  if (input.length <= showStart + showEnd) return '*' * input.length;
  final start = input.substring(0, showStart);
  final end = input.substring(input.length - showEnd);
  return '$start${'*' * (input.length - showStart - showEnd)}$end';
}

const int kWorkingDaysPerMonth = 22;
const int _kDownloadWindowDays = 1;
const Duration _kDemoSkeletonDuration = Duration(milliseconds: 900);

enum _NetworkState { online, offline, checking }

class _Mock {
  static const Color orange = Color(0xFFFF8A00);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
  static const Color demoAccent = orange;
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg => isDark ? const Color(0xFF18181B) : Colors.white;
  Color get cardBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textGrayDark =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF52525B);
  Color get printButtonBg => isDark ? const Color(0xFF27272A) : Colors.white;
  Color get printButtonBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF3F3F46);
  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with WidgetsBindingObserver {
  Employee? _employee;
  Map<String, dynamic>? _rawData;
  PayrollBreakdown _breakdown = PayrollBreakdown.empty;
  bool _loading = true;
  bool _exporting = false;
  bool _downloading = false;
  bool _sendingSupport = false;
  bool _loadingPassword = false;

  // 🆕 Payslip Unlock State
  bool _isPayslipUnlocked = false;

  String _bankName = '—';
  String _accountNumber = '—';
  String _department = '—';
  String _designation = '—';

  double _basicSalary = 0;
  double _allowances = 0;
  double _dailyRate = 0;
  int _workingDaysPerMonth = kWorkingDaysPerMonth;
  String _salarySource = 'manual';
  String _role = '';

  String _displayName = '—';
  String _displayEmpId = '—';

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  StreamSubscription<bool>? _networkSub;

  bool _isInitialLoading = true;

  static const Duration _pdfCooldown = Duration(seconds: 10);
  static const Duration _inactivityLimit = Duration(minutes: 30);
  static const int _maxPdfPerHour = 20;
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const String _pdfCountPrefsKey = 'reports_pdf_count_window';

  late final String _sessionNonce;
  DateTime? _lastPdfGeneratedAt;
  DateTime? _lastUserActivityAt;
  int _totalPdfGenerated = 0;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  bool _sessionValidated = false;
  bool _loggedOut = false;
  bool? _cachedSessionValid;
  DateTime? _cachedSessionTime;

  bool get _isDemo => DemoModeService.instance.isEnabled;

  // ═══════════════════════════════════════════════════════════════
  // PAYSLIP PERIOD
  // ═══════════════════════════════════════════════════════════════
  DateTime get _periodStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1, 0, 0, 0);
  }

  DateTime get _periodEnd {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0, 23, 59, 59);
  }

  String get _periodRangeLabel {
    final start = DateFormat('MMM d').format(_periodStart);
    final end = DateFormat('MMM d, yyyy').format(_periodEnd);
    return '$start – $end';
  }

  // ═══════════════════════════════════════════════════════════════
  // DOWNLOAD WINDOW
  // ═══════════════════════════════════════════════════════════════
  int get _lastDayOfMonth {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0).day;
  }

  int get _firstAllowedDay {
    final last = _lastDayOfMonth;
    return (last - (_kDownloadWindowDays - 1)).clamp(1, last);
  }

  bool get _isDownloadWindowOpen {
    if (_isDemo || _isPayslipUnlocked) return true; // 🆕 Allow if unlocked

    final now = DateTime.now();
    return now.day >= _firstAllowedDay;
  }

  String get _downloadWindowLabel {
    final now = DateTime.now();
    final last = _lastDayOfMonth;
    final first = _firstAllowedDay;
    if (first == last) {
      final d = DateTime(now.year, now.month, last);
      return DateFormat('MMMM d, yyyy').format(d);
    }
    final d1 = DateTime(now.year, now.month, first);
    final d2 = DateTime(now.year, now.month, last);
    return '${DateFormat('MMMM d').format(d1)} – ${DateFormat('MMMM d, yyyy').format(d2)}';
  }

  String get _downloadBlockedReason {
    return 'Payslip becomes available on $_downloadWindowLabel.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    if (_isDemo) {
      debugPrint('🎭 [DemoMode] ReportsScreen in DEMO MODE');
      _sessionValidated = true;
      _networkState = _NetworkState.online;
      _isInitialLoading = true;
      _loadData();

      Future.delayed(_kDemoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
      });
      return;
    }

    // NORMAL MODE
    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;

            if (!online) {
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
                _showOfflineOverlay = false;
              });

              _overlayDelayTimer =
                  Timer(const Duration(milliseconds: 1200), () {
                    if (mounted && _networkState == _NetworkState.offline) {
                      setState(() => _showOfflineOverlay = true);
                    }
                  });
            } else if (_networkState == _NetworkState.offline) {
              _overlayDelayTimer?.cancel();
              _showOfflineOverlay = false;
              _retryNetworkCheck();
            }
          });
    } catch (e) {
      debugPrint('⚠️ [Reports] connectivity failed: $e');
    }

    _startSecurityMonitoring();

    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });

    _loadData();
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (_isDemo) return true;

    if (!forceRefresh &&
        _cachedSessionValid != null &&
        _cachedSessionTime != null &&
        DateTime.now().difference(_cachedSessionTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }

    try {
      final valid = await SecurityService.instance
          .isSessionValid()
          .timeout(const Duration(seconds: 5));

      if (!valid) {
        await _logSecurityEventGlobal(
          type: 'reports_session_invalid',
          severity: 'high',
          details: 'Session expired on Reports screen',
          employeeId: widget.initialEmployee?.id,
          sessionNonce: _sessionNonce,
        );
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }

      final sessionEmpId =
      await SecurityService.instance.getCurrentEmployeeId();
      final docId = widget.initialEmployee?.id;
      final empId = widget.initialEmployee?.employeeId;

      final matches = sessionEmpId == null ||
          sessionEmpId.isEmpty ||
          (docId != null && sessionEmpId == docId) ||
          (empId != null && empId.isNotEmpty && sessionEmpId == empId);

      if (!matches) {
        await _logSecurityEventGlobal(
          type: 'reports_cross_access',
          severity: 'critical',
          details: 'Session ($sessionEmpId) != viewing',
          employeeId: sessionEmpId,
          sessionNonce: _sessionNonce,
        );
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }

      _cachedSessionValid = true;
      _cachedSessionTime = DateTime.now();
      return true;
    } catch (e) {
      _cachedSessionValid = false;
      _cachedSessionTime = DateTime.now();
      return false;
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
    bool sensitive = false,
  }) async {
    if (_isDemo) return;

    await _logSecurityEventGlobal(
      type: type,
      severity: severity,
      details: details,
      employeeId: _employee?.id ?? widget.initialEmployee?.id,
      sessionNonce: _sessionNonce,
      sensitive: sensitive,
    );
  }

  void _recordActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  void _startSecurityMonitoring() {
    if (_isDemo) return;

    final empDocId = widget.initialEmployee?.id;
    if (empDocId != null && empDocId.isNotEmpty) {
      _sessionSub = FirebaseFirestore.instance
          .collection('sessions')
          .doc(empDocId)
          .snapshots()
          .listen(
            (snap) {
          if (!mounted || _loggedOut) return;
          final data = snap.data();
          if (data == null) return;

          if (data['revoked'] == true) {
            _forceLogout('Session revoked by admin');
            return;
          }
          final expiresAt = data['expiresAt'] as Timestamp?;
          if (expiresAt != null &&
              expiresAt.toDate().isBefore(DateTime.now())) {
            _forceLogout('Session expired');
          }
        },
        onError: (e) => debugPrint('Session listener error: $e'),
      );
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final valid = await _validateSession(forceRefresh: true);
        if (!valid && mounted && !_loggedOut) {
          await _forceLogout('Session invalidated');
        }
      } catch (e) {
        debugPrint('⚠️ Heartbeat failed: $e');
      }
    });

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _inactivityLimit) {
        await _forceLogout('Inactivity (${idle.inMinutes}m)');
      }
    });

    _validateSession(forceRefresh: true).then((valid) {
      if (mounted) {
        setState(() => _sessionValidated = valid);
        if (valid) {
          _logSecurityEvent(
            type: 'reports_opened',
            severity: 'info',
            details: 'Reports/Payslip screen opened',
          );
        } else {
          _forceLogout('Initial session invalid');
        }
      }
    });
  }

  Future<void> _forceLogout(String reason) async {
    if (_isDemo) return;
    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    _sessionSub?.cancel();

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}
    try {
      await SecurityService.instance.clearSession();
    } catch (_) {}

    await _logSecurityEventGlobal(
      type: 'reports_forced_logout',
      severity: 'high',
      details: 'Force logout: $reason',
      sessionNonce: _sessionNonce,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
        settings: const RouteSettings(name: '/login'),
      ),
          (route) => false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDemo) return;

    if (state == AppLifecycleState.resumed) {
      _recordActivity();
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) {
          _forceLogout('Session invalid on resume');
        }
      });
    }
  }

  Future<bool> _checkPdfRateLimit() async {
    if (_isDemo) {
      _totalPdfGenerated++;
      return true;
    }

    final now = DateTime.now();

    if (_lastPdfGeneratedAt != null) {
      final elapsed = now.difference(_lastPdfGeneratedAt!).inMilliseconds;
      if (elapsed < _pdfCooldown.inMilliseconds) {
        _showSnack('Export not allowed yet. Please wait a few seconds.',
            error: true);
        return false;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pdfCountPrefsKey);
      int count = 0;
      DateTime? windowStart;
      if (raw != null) {
        final parts = raw.split('|');
        if (parts.length == 2) {
          windowStart = DateTime.tryParse(parts[0]);
          count = int.tryParse(parts[1]) ?? 0;
        }
      }

      if (windowStart == null || now.difference(windowStart).inHours >= 1) {
        windowStart = now;
        count = 0;
      }

      if (count >= _maxPdfPerHour) {
        _showSnack('Max PDF exports reached. Try again later.', error: true);
        _logSecurityEvent(
          type: 'reports_pdf_excessive',
          severity: 'medium',
          details: 'Total PDFs in window: $count',
        );
        return false;
      }

      await prefs.setString(
          _pdfCountPrefsKey, '${windowStart.toIso8601String()}|${count + 1}');
    } catch (e) {
      debugPrint('⚠️ Rate limit prefs error: $e');
    }

    _totalPdfGenerated++;
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }

  Future<void> _checkNetworkOnEntry() async {
    if (_isDemo) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }

    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);

    bool hasNet = true;
    try {
      hasNet = ConnectivityService.instance.isOnline;
    } catch (_) {
      hasNet = true;
    }

    if (!mounted) return;

    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage =
        'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }

    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (_isDemo) return;

    if (!mounted) return;
    _recordActivity();

    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
    });

    await _checkNetworkOnEntry();

    if (_networkState == _NetworkState.online && mounted) {
      try {
        await _loadData();
      } catch (e) {
        debugPrint('⚠️ Retry refresh failed: $e');
      }
    }
  }

  double _num(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _int(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  Future<Map<String, dynamic>?> _fetchByRawId(String rawId) async {
    if (_isDemo) return null;

    final fs = FirebaseFirestore.instance;

    try {
      final doc = await fs
          .collection('employees')
          .doc(rawId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists) return doc.data();
    } catch (e) {
      debugPrint('⚠️ [raw-1] failed: $e');
    }

    try {
      final snap = await fs
          .collection('employees')
          .where('employeeId', isEqualTo: rawId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (e) {
      debugPrint('⚠️ [raw-2] failed: $e');
    }

    return null;
  }

  PayrollBreakdown _buildDemoBreakdown() {
    final demo = DemoModeService.instance.demoPayslipBreakdown;

    return PayrollBreakdown(
      regularPay: demo['regularPay'] ?? 22000.0,
      basicSalary: demo['basicSalary'] ?? 22000.0,
      basicHours: demo['basicHours'] ?? 176.0,
      absentAmount: demo['absentAmount'] ?? 0.0,
      absentHours: demo['absentHours'] ?? 0.0,
      lateAmount: demo['lateAmount'] ?? -150.0,
      lateHours: demo['lateHours'] ?? 1.5,
      undertimeAmount: demo['undertimeAmount'] ?? 0.0,
      undertimeHours: demo['undertimeHours'] ?? 0.0,
      dayOffOtAmount: demo['dayOffOtAmount'] ?? 0.0,
      dayOffOtHours: demo['dayOffOtHours'] ?? 0.0,
      overtimeAmount: demo['overtimeAmount'] ?? 2750.0,
      overtimeHours: demo['overtimeHours'] ?? 10.0,
      nightDiffAmount: demo['nightDiffAmount'] ?? 550.0,
      nightDiffHours: demo['nightDiffHours'] ?? 12.0,
      holidayAmount: demo['holidayAmount'] ?? 600.0,
      otherIncomeAllowance: demo['otherIncomeAllowance'] ?? 0.0,
      totalAdjustmentsMade: demo['totalAdjustmentsMade'] ?? 0.0,
      grossPay: demo['grossPay'] ?? 25750.0,
      thirteenthMonth: 0,
      silCredits: 0,
      totalBenefits: 0,
      workingDays: 22,
      workingDaysPerMonth: 22,
      presentDays: 22,
      absentDays: 0,
      dailyRate: 1000.0,
      workRawMinutes: 10560,
      workLunchMinutes: 1320,
      workNetMinutes: 9240,
      workOvertimeMinutes: 600,
      daysWithLogs: 22,
      daysWithLunchApplied: 22,
      salarySource: 'demo',
      sss: demo['sss'] ?? 990.0,
      philhealth: demo['philhealth'] ?? 550.0,
      pagibig: demo['pagibig'] ?? 100.0,
      taxableIncome: demo['taxableIncome'] ?? 24110.0,
      taxWithheld: demo['taxWithheld'] ?? 1410.0,
      totalLoanDeductions: demo['totalLoanDeductions'] ?? 0.0,
      totalDeductions: demo['totalDeductions'] ?? 3450.0,
      netPay: demo['netPay'] ?? 22300.0,
      sickLeaveBalance: demo['sickLeaveBalance'] ?? 120.0,
      vacationLeaveBalance: demo['vacationLeaveBalance'] ?? 120.0,
      riceAllowance: demo['riceAllowance'] ?? 0.0,
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _recordActivity();

    if (_isDemo) {
      setState(() => _loading = true);

      final fakeBreakdown = _buildDemoBreakdown();
      final demo = DemoModeService.instance.demoPayslipBreakdown;

      if (!mounted) return;
      setState(() {
        _employee = DemoModeService.demoEmployee;
        _rawData = null;
        _breakdown = fakeBreakdown;
        _bankName = 'DEMO Bank';
        _accountNumber = '•••• 1234';
        _department = DemoModeService.demoEmployee.department;
        _designation = DemoModeService.demoEmployee.position;

        _basicSalary = demo['basicSalary'] ?? 22000.0;
        _allowances = 0;
        _dailyRate = 1000.0;
        _workingDaysPerMonth = 22;
        _salarySource = 'demo';
        _role = 'Demo';
        _isPayslipUnlocked = true; // Always unlocked in demo

        _displayName = DemoModeService.demoEmployee.fullName;
        _displayEmpId = DemoModeService.demoEmployee.employeeId;

        _loading = false;
      });
      return;
    }

    // NORMAL MODE
    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      if (mounted) {
        setState(() {
          _loading = false;
          _networkErrorMessage = 'Session expired. Please log in again.';
        });
        _forceLogout('Session invalid on _loadData');
      }
      return;
    }

    setState(() => _loading = true);

    try {
      String? rawEmpId;
      if (!kIsWeb) {
        rawEmpId = await SecurityService.instance.getCurrentEmployeeId();
      }

      Employee? emp = widget.initialEmployee;
      if (emp == null && rawEmpId != null && rawEmpId.isNotEmpty) {
        try {
          emp = await DatabaseService.instance.getEmployeeById(rawEmpId);
        } catch (_) {}
      }

      Map<String, dynamic>? data;
      if (rawEmpId != null && rawEmpId.isNotEmpty) {
        data = await _fetchByRawId(rawEmpId);
      }
      if (data == null && emp != null) {
        for (final id in <String>{emp.employeeId, emp.id}) {
          if (id.isEmpty) continue;
          data = await _fetchByRawId(id);
          if (data != null) break;
        }
      }

      PayrollBreakdown b = PayrollBreakdown.empty;
      if (data != null) {
        final empData = {
          ...data,
          if (emp != null && emp.id.isNotEmpty) 'id': emp.id,
          if (rawEmpId != null) 'employeeId': rawEmpId,
        };
        b = await PayrollCalculator.compute(
          employee: empData,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        );
      }

      final basicFromData = _num(data?['basicSalary']);
      final basicAllow =
      _num(data?['basicAllowance'] ?? data?['allowances']);
      final housingAllow = _num(data?['housingAllowance']);
      final transportAllow = _num(data?['transportAllowance']);
      final specialAllow = _num(data?['specialAllowance']);
      final allowancesFromData =
          basicAllow + housingAllow + transportAllow + specialAllow;

      final dailyFromData = _num(data?['dailyRate']);
      final workingDays = _int(data?['workingDaysPerMonth'], 22);
      final salarySource = (data?['salarySource'] as String?) ?? 'manual';
      final roleFromData = (data?['role'] as String?) ?? '';

      // 🆕 READ UNLOCK STATUS
      final isUnlocked = data?['payslipUnlocked'] == true;

      final effectiveDaily = dailyFromData > 0
          ? dailyFromData
          : (basicFromData > 0 && workingDays > 0
          ? basicFromData / workingDays
          : 0.0);

      final displayName = emp?.fullName ??
          (data?['name'] as String?) ??
          '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();

      final displayId = emp?.employeeId ??
          rawEmpId ??
          (data?['employeeId'] as String?) ??
          '—';

      if (!mounted) return;
      setState(() {
        _employee = emp;
        _rawData = data;
        _breakdown = b;
        _bankName = (data?['bankName'] as String?) ?? '—';
        _accountNumber = (data?['accountNumber'] as String?) ?? '—';
        _department = (data?['department'] as String?) ?? '—';
        _designation = (data?['designation'] as String?) ??
            (data?['role'] as String?) ??
            emp?.position ??
            '—';

        _basicSalary = basicFromData > 0
            ? basicFromData
            : (b.basicSalary > 0 ? b.basicSalary : 0);
        _allowances = allowancesFromData > 0
            ? allowancesFromData
            : (b.otherIncomeAllowance > 0 ? b.otherIncomeAllowance : 0);
        _dailyRate = effectiveDaily > 0
            ? effectiveDaily
            : (b.dailyRate > 0 ? b.dailyRate : 0);
        _workingDaysPerMonth = workingDays > 0 ? workingDays : 22;
        _salarySource = salarySource;
        _role = roleFromData;
        _isPayslipUnlocked = isUnlocked; // 🆕 Set state

        _displayName = displayName.isNotEmpty ? displayName : '—';
        _displayEmpId = displayId.isNotEmpty ? displayId : '—';

        _loading = false;
      });

      _logSecurityEvent(
        type: 'reports_payslip_loaded',
        severity: 'info',
        details: 'Payslip loaded ($_salarySource) • period: $_periodRangeLabel',
        sensitive: true,
      );
    } catch (e, stack) {
      debugPrint('❌ _loadData ERROR: $e');
      if (mounted) setState(() => _loading = false);

      await _logSecurityEvent(
        type: 'reports_load_error',
        severity: 'medium',
        details: 'Error loading payslip',
      );
    }
  }

  Future<void> _onDownloadPressed() async {
    _recordActivity();

    if (_exporting || _downloading) return;

    if (!_isDownloadWindowOpen) {
      _showSnack('🗓️ $_downloadBlockedReason', error: true);
      await _logSecurityEvent(
        type: 'reports_download_blocked_too_early',
        severity: 'info',
        details: 'Attempted download before end-of-month window',
      );
      return;
    }

    _downloading = true;

    try {
      if (!await _checkPdfRateLimit()) return;

      if (!_isDemo) {
        final valid = await _validateSession(forceRefresh: true);
        if (!valid) {
          _showSnack('🚨 Session expired. Please log in again.', error: true);
          _forceLogout('Session invalid on PDF export');
          return;
        }
      }

      if (!_isDemo && _networkState != _NetworkState.online) {
        _showSnack('⚠️ No internet. Please check your connection.', error: true);
        return;
      }

      final emp = _employee ?? widget.initialEmployee;
      Employee effectiveEmp;

      if (_isDemo) {
        effectiveEmp = DemoModeService.demoEmployee;
      } else if (emp != null) {
        effectiveEmp = emp;
      } else if (_rawData != null) {
        final now = DateTime.now();
        effectiveEmp = Employee(
          id: (_rawData!['id'] ?? _displayEmpId).toString(),
          employeeId: (_rawData!['employeeId'] ?? _displayEmpId).toString(),
          firstName: (_rawData!['firstName'] ?? '').toString(),
          lastName: (_rawData!['lastName'] ?? '').toString(),
          email: (_rawData!['email'] ?? '').toString(),
          department: _department,
          position: _designation,
          createdAt: now,
          updatedAt: now,
        );
      } else {
        _showSnack('No employee data.', error: true);
        return;
      }

      if (_basicSalary <= 0 && _breakdown.basicSalary <= 0) {
        _showSnack('No salary configured. Please contact HR.', error: true);
        return;
      }

      final password =
      PayrollPdfService.deriveUserPassword(effectiveEmp.employeeId.trim());

      if (!mounted) return;
      await _showPreDownloadPasswordDialog(password);
      if (!mounted) return;

      await _doGeneratePdf(effectiveEmp);
    } finally {
      _downloading = false;
    }
  }

  Future<void> _doGeneratePdf(Employee effectiveEmp) async {
    if (!mounted) return;
    setState(() => _exporting = true);
    _lastPdfGeneratedAt = DateTime.now();

    try {
      final result = await PayrollPdfService.generate(
        context,
        employee: effectiveEmp,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        regularPay: _breakdown.regularPay,
        basicPay: _breakdown.basicSalary,
        basicHours: _breakdown.basicHours,
        absentAmount: _breakdown.absentAmount,
        absentHours: _breakdown.absentHours,
        lateAmount: _breakdown.lateAmount,
        lateHours: _breakdown.lateHours,
        undertimeAmount: _breakdown.undertimeAmount,
        undertimeHours: _breakdown.undertimeHours,
        dayOffOtAmount: _breakdown.dayOffOtAmount,
        dayOffOtHours: _breakdown.dayOffOtHours,
        overtimeAmount: _breakdown.overtimeAmount,
        overtimeHours: _breakdown.overtimeHours,
        nightDiffAmount: _breakdown.nightDiffAmount,
        nightDiffHours: _breakdown.nightDiffHours,
        holidayAmount: _breakdown.holidayAmount,
        otherIncomeAllowance: _breakdown.otherIncomeAllowance,
        totalAdjustmentsMade: _breakdown.totalAdjustmentsMade,
        sss: _breakdown.sss,
        philhealth: _breakdown.philhealth,
        pagibig: _breakdown.pagibig,
        taxableIncome: _breakdown.taxableIncome,
        taxWithheld: _breakdown.taxWithheld,
        totalLoanDeductions: _breakdown.totalLoanDeductions,
        sickLeaveBalance: _breakdown.sickLeaveBalance,
        vacationLeaveBalance: _breakdown.vacationLeaveBalance,
        riceAllowance: _breakdown.riceAllowance,
        receivedThru: 'ATM',
        sessionNonce: _sessionNonce,
      );

      if (!result.success) {
        if (mounted) {
          _showSnack(result.errorMessage ?? 'Export failed.', error: true);
        }
        return;
      }

      if (!_isDemo) {
        try {
          await FirebaseFirestore.instance.collection('pdf_exports').add({
            'employee_id': effectiveEmp.employeeId,
            'employee_id_hash':
            _hashEmployeeId(effectiveEmp.employeeId, _sessionNonce),
            'report_type': 'Payslip PDF',
            'month': DateFormat('yyyy-MM').format(DateTime.now()),
            'period_start': _periodStart.toIso8601String(),
            'period_end': _periodEnd.toIso8601String(),
            'period_label': _periodRangeLabel,
            'net_pay': _breakdown.netPay,
            'salary_source': _salarySource,
            'exported_at': FieldValue.serverTimestamp(),
            'platform': kIsWeb ? 'Web' : 'Mobile',
            'session_nonce': _sessionNonce,
          });
        } catch (e) {
          debugPrint('⚠️ pdf_exports log warning: $e');
        }
      }

      if (mounted) {
        _showSnack(
          _isDemo
              ? '🎭 DEMO PDF payslip generated ✓'
              : 'PDF payslip generated ✓',
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Export failed. Please try again.', error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showPreDownloadPasswordDialog(String password) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final accent = _Mock.orange;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: tc.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: tc.cardBorder),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isDemo ? Icons.science_rounded : Icons.lock_outline_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isDemo ? 'Demo — Save Password' : 'Save Password',
                  style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before downloading, copy or save this password first. You will need it to open the PDF.',
                  style: TextStyle(
                      color: tc.textGrayDark, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectionArea(
                          child: Text(
                            password,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: accent,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_rounded, color: tc.textGrayDark, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: password));
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Password copied ✓'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFFF4D6D), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isDemo
                            ? '🎭 DEMO MODE — this is a FAKE PDF. No data will be saved to the database.'
                            : 'This password is the SAME for all your payslips — it never changes. Save it somewhere safe.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF4D6D),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: accent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text(
                'OK — Download Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCurrentPdfPassword() async {
    _recordActivity();
    if (_loadingPassword) return;

    String empId;
    if (_isDemo) {
      empId = DemoModeService.demoEmployee.employeeId;
    } else {
      final emp = _employee ?? widget.initialEmployee;
      if (emp == null && _rawData == null) {
        _showSnack('Employee data not loaded.', error: true);
        return;
      }
      empId = emp?.employeeId ?? (_rawData?['employeeId'] ?? _displayEmpId).toString();
    }

    if (empId.isEmpty || empId == '—') {
      _showSnack('Employee ID not available.', error: true);
      return;
    }

    setState(() => _loadingPassword = true);
    final pwd = PayrollPdfService.deriveUserPassword(empId);
    if (!mounted) return;
    setState(() => _loadingPassword = false);

    if (pwd.isEmpty) {
      _showSnack('Could not compute password.', error: true);
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final accent = _Mock.orange;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tc.cardBorder),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isDemo ? Icons.science_rounded : Icons.vpn_key_rounded,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isDemo ? 'Demo PDF Password' : 'Your PDF Password',
                style: TextStyle(
                  color: tc.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isDemo
                    ? 'This is a FAKE password for demo mode. The PDF will still open with it.'
                    : 'Use this password to open ANY payslip PDF you download. '
                    'This is the SAME password forever — save it somewhere safe.',
                style: TextStyle(color: tc.textGrayDark, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectionArea(
                        child: Text(
                          pwd,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.copy_rounded, color: tc.textGrayDark, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: pwd));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Password copied ✓'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContactHrSheet({String? prefillCategory}) async {
    if (!mounted) return;
    if (_sendingSupport) return;
    _recordActivity();

    if (_isDemo) {
      _showSnack('🎭 Demo mode: support requests are not sent.', error: true);
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final emp = _employee ?? widget.initialEmployee;
    if (emp == null && _rawData == null) {
      _showSnack('Employee data not loaded. Please reload the screen.', error: true);
      return;
    }

    final Employee effectiveEmp;
    if (emp != null) {
      effectiveEmp = emp;
    } else {
      final now = DateTime.now();
      effectiveEmp = Employee(
        id: (_rawData!['id'] ?? _displayEmpId).toString(),
        employeeId: (_rawData!['employeeId'] ?? _displayEmpId).toString(),
        firstName: (_rawData!['firstName'] ?? '').toString(),
        lastName: (_rawData!['lastName'] ?? '').toString(),
        email: (_rawData!['email'] ?? '').toString(),
        department: _department,
        position: _designation,
        createdAt: now,
        updatedAt: now,
      );
    }

    String selectedCategory = prefillCategory ?? SupportRequestService.categories.first.value;
    final TextEditingController descCtrl = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: tc.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tc.cardBorder,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _Mock.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.support_agent_rounded, color: _Mock.orange, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Contact HR',
                                style: TextStyle(
                                  color: tc.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'We will forward your concern to the admin/HR.',
                                style: TextStyle(color: tc.textGrayDark, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ...SupportRequestService.categories.map((c) {
                      final selected = selectedCategory == c.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () => setSheet(() => selectedCategory = c.value),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? _Mock.orange.withValues(alpha: 0.10) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? _Mock.orange.withValues(alpha: 0.5) : tc.cardBorder,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected ? _Mock.orange : tc.textGrayDark,
                                      width: 2,
                                    ),
                                  ),
                                  child: selected
                                      ? Center(
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _Mock.orange,
                                      ),
                                    ),
                                  )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                                          color: tc.textPrimary,
                                        ),
                                      ),
                                      Text(c.hint, style: TextStyle(fontSize: 11, color: tc.textGrayDark)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      maxLength: 300,
                      style: TextStyle(color: tc.textPrimary, fontSize: 13),
                      cursorColor: _Mock.orange,
                      decoration: InputDecoration(
                        hintText: 'Describe what happened...',
                        hintStyle: TextStyle(color: tc.textGrayDark, fontSize: 12),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF4F4F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tc.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _Mock.orange, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: TextStyle(color: tc.textGrayDark)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _sendingSupport ? null : () => Navigator.pop(ctx, true),
                            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                            label: const Text('Send to HR', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _Mock.orange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
      },
    );

    if (submitted != true) {
      descCtrl.dispose();
      return;
    }

    setState(() => _sendingSupport = true);
    try {
      final ok = await SupportRequestService.instance.sendRequest(
        employee: effectiveEmp,
        category: selectedCategory,
        description: descCtrl.text,
      );

      if (!mounted) return;

      if (ok) {
        _showSnack('✓ Sent to HR. Please wait for their response.');
      } else {
        _showSnack('Failed to send. Please check your internet.', error: true);
      }
    } finally {
      if (mounted) setState(() => _sendingSupport = false);
      descCtrl.dispose();
    }
  }

  void _showSnack(String msg, {bool error = false, SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFFF4D6D) : const Color(0xFF00E5A0),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
      action: action,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());

    final isOffline = _networkState == _NetworkState.offline && !_isDemo;
    final isChecking = _networkState == _NetworkState.checking && !_isDemo;

    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(
          child: Stack(
            children: [
              const ListSkeleton(itemCount: 5),
              if (isOffline)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showOfflineOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    child: IgnorePointer(
                      ignoring: !_showOfflineOverlay,
                      child: _buildNetworkErrorOverlay(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildHandWatermark(opacity: tc.watermarkOpacity),
            Column(
              children: [
                _buildHeader(tc, thisMonth),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    color: _Mock.orange,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isDemo) ...[
                            _buildDemoBadge(),
                            const SizedBox(height: 14),
                          ],

                          _buildPayslipCard(tc, thisMonth),

                          // Show download window info ONLY if locked
                          if (!_isDownloadWindowOpen && !_isDemo) ...[
                            const SizedBox(height: 14),
                            _buildDownloadLockedBanner(tc),
                          ],

                          const SizedBox(height: 20),
                          _buildDownloadButton(),
                          const SizedBox(height: 12),
                          _buildViewPasswordButton(tc),
                          const SizedBox(height: 10),
                          _buildContactHrButton(tc),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_Mock.orange, Color(0xFFF54900)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: const [
          Icon(Icons.science_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'DEMO MODE — Fake payslip, no data is saved',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadLockedBanner(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Mock.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Mock.orange.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _Mock.orange.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.lock_clock_rounded, color: _Mock.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Download Available at End of Month',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _Mock.orange),
                ),
                const SizedBox(height: 4),
                Text(
                  'Payslip for $_periodRangeLabel will be downloadable on $_downloadWindowLabel.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: tc.textGrayDark, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkErrorOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 20),
                const Text('No Connection', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(_networkErrorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _retryNetworkCheck,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _Mock.orange),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc, String thisMonth) {
    final canDownload = _isDownloadWindowOpen;
    final busy = _exporting || _downloading;
    final printDisabled = busy || !canDownload;

    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
    );

    const accent = _Mock.orange;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () { _recordActivity(); Navigator.maybePop(context); },
                child: const Row(
                  children: [
                    Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 2),
                    Text('Back', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const Spacer(),
              if (_isDemo) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    children: [
                      Icon(Icons.science_rounded, color: Colors.white, size: 11),
                      SizedBox(width: 5),
                      Text('DEMO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: printDisabled ? null : _onDownloadPressed,
                child: Opacity(
                  opacity: printDisabled && !busy ? 0.55 : 1.0,
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: tc.printButtonBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tc.printButtonBorder),
                    ),
                    child: busy
                        ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(color: accent, strokeWidth: 2))
                        : Icon(canDownload ? Icons.print_rounded : Icons.lock_outline_rounded, color: accent, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(_isDemo ? 'Demo Payslip' : 'Payslip Details', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('Salary slip for $thisMonth', style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Period: $_periodRangeLabel', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(_ThemeColors tc, String thisMonth) {
    const accent = _Mock.orange;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder, width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('R.A.C.O.M.A', style: TextStyle(color: accent, fontSize: 20, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(_isDemo ? 'DEMO Payslip — no data saved' : 'Smart HR Information System', style: TextStyle(color: tc.textPrimary, fontSize: 12)),
                const SizedBox(height: 12),
                Text(_isDemo ? 'Demo Company HQ, Philippines' : 'Jumbo HQ, Manila, Philippines', style: TextStyle(color: tc.textGrayDark, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isDemo ? _Mock.orange.withValues(alpha: 0.12) : _Mock.paidBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _isDemo ? _Mock.orange.withValues(alpha: 0.45) : _Mock.paidBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_isDemo ? Icons.science_rounded : Icons.check_circle_rounded, color: accent, size: 14),
                    const SizedBox(width: 6),
                    Text(_isDemo ? 'DEMO' : 'Paid', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Payslip for\n$thisMonth', textAlign: TextAlign.right, style: TextStyle(color: tc.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    final canDownload = _isDownloadWindowOpen;
    final busy = _exporting || _downloading;
    final disabled = busy || !canDownload;

    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
    );

    return GestureDetector(
      onTap: disabled ? null : _onDownloadPressed,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: canDownload ? gradient : null,
          color: canDownload ? null : const Color(0xFF9CA3AF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(canDownload ? Icons.download_rounded : Icons.lock_clock_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                canDownload
                    ? (_isDemo ? 'Download DEMO PDF' : 'Download as PDF / Print')
                    : 'Available on $_downloadWindowLabel',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewPasswordButton(_ThemeColors tc) {
    final disabled = _loadingPassword;
    final accent = _isDemo ? _Mock.orange : tc.textGrayDark;

    return GestureDetector(
      onTap: disabled ? null : _showCurrentPdfPassword,
      child: Container(
        width: double.infinity,
        height: 42,
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tc.cardBorder, width: 1),
        ),
        child: Center(
          child: disabled
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: _Mock.orange, strokeWidth: 2))
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vpn_key_rounded, color: accent, size: 16),
              const SizedBox(width: 8),
              Text(
                _isDemo ? 'View Demo PDF Password' : 'View My PDF Password',
                style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactHrButton(_ThemeColors tc) {
    final disabled = _sendingSupport || _isDemo;

    return GestureDetector(
      onTap: disabled ? null : () => _showContactHrSheet(),
      child: Opacity(
        opacity: _isDemo ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: tc.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Mock.orange.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Center(
            child: disabled && !_isDemo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _Mock.orange, strokeWidth: 2))
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.support_agent_rounded, color: _Mock.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  _isDemo ? 'Contact HR (disabled in demo)' : 'Contact HR / Report Issue',
                  style: TextStyle(color: tc.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}