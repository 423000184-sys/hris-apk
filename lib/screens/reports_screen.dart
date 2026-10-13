// lib/screens/reports_screen.dart
// ═══════════════════════════════════════════════════════════════════
// REPORTS / PAYSLIP SCREEN  v2.0
// Updates:
//   - Deterministic PDF password (no more versioning/reset).
//   - "View My PDF Password" always shows the same password.
//   - All user-facing text in English.
// ═══════════════════════════════════════════════════════════════════
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

enum _NetworkState { online, offline, checking }

class _Mock {
  static const Color orange = Color(0xFFFF8A00);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
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
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint('🌐 [Reports] connectivity → online=$online');

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
        debugPrint('🚨 [Reports] Cross-employee attempt: '
            'session=$sessionEmpId docId=$docId empId=$empId');
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
      debugPrint('⚠️ [Reports] Session validation error: $e');
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
    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    debugPrint('🚨 [Reports] Force logout: $reason');

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
    final now = DateTime.now();

    if (_lastPdfGeneratedAt != null) {
      final elapsed = now.difference(_lastPdfGeneratedAt!).inMilliseconds;
      if (elapsed < _pdfCooldown.inMilliseconds) {
        debugPrint('🚦 [Reports] PDF rate-limited ($elapsed ms)');
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

      if (windowStart == null ||
          now.difference(windowStart).inHours >= 1) {
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

      await prefs.setString(_pdfCountPrefsKey,
          '${windowStart.toIso8601String()}|${count + 1}');
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
    final fs = FirebaseFirestore.instance;
    debugPrint('🔍 [_fetchByRawId] rawId masked: ${_maskString(rawId)}');

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

    try {
      final snap = await fs
          .collection('employees')
          .where('id', isEqualTo: rawId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (e) {
      debugPrint('⚠️ [raw-3] failed: $e');
    }

    return null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _recordActivity();

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

        _displayName = displayName.isNotEmpty ? displayName : '—';
        _displayEmpId = displayId.isNotEmpty ? displayId : '—';

        _loading = false;
      });

      _logSecurityEvent(
        type: 'reports_payslip_loaded',
        severity: 'info',
        details: 'Payslip loaded ($_salarySource)',
        sensitive: true,
      );
    } catch (e, stack) {
      debugPrint('❌ _loadData ERROR: $e');
      debugPrint('$stack');
      if (mounted) setState(() => _loading = false);

      await _logSecurityEvent(
        type: 'reports_load_error',
        severity: 'medium',
        details: 'Error loading payslip',
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 📥 DOWNLOAD FLOW
  // ══════════════════════════════════════════════════════════════
  Future<void> _onDownloadPressed() async {
    _recordActivity();

    if (_exporting || _downloading) {
      debugPrint('🚫 [Reports] Download already in progress — ignored.');
      return;
    }
    _downloading = true;

    try {
      if (!await _checkPdfRateLimit()) return;

      final valid = await _validateSession(forceRefresh: true);
      if (!valid) {
        _showSnack('🚨 Session expired. Please log in again.', error: true);
        _forceLogout('Session invalid on PDF export');
        return;
      }

      if (_networkState != _NetworkState.online) {
        _showSnack(
          '⚠️ No internet. Please check your connection.',
          error: true,
          action: SnackBarAction(
            label: 'Report',
            textColor: Colors.white,
            onPressed: () =>
                _showContactHrSheet(prefillCategory: 'pdf_download'),
          ),
        );
        return;
      }

      final emp = _employee ?? widget.initialEmployee;
      Employee effectiveEmp;
      if (emp != null) {
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
        _showSnack(
          'No salary configured. Please contact HR.',
          error: true,
          action: SnackBarAction(
            label: 'Contact HR',
            textColor: Colors.white,
            onPressed: () =>
                _showContactHrSheet(prefillCategory: 'salary_question'),
          ),
        );
        return;
      }

      // ✅ Deterministic password — no sessionNonce needed
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

    await _logSecurityEvent(
      type: 'reports_pdf_requested',
      severity: 'info',
      details: 'PDF generation requested',
      sensitive: true,
    );

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
          _showSnack(
            result.errorMessage ?? 'Export failed.',
            error: true,
            action: SnackBarAction(
              label: 'Report',
              textColor: Colors.white,
              onPressed: () =>
                  _showContactHrSheet(prefillCategory: 'pdf_download'),
            ),
          );
        }
        await _logSecurityEvent(
          type: 'reports_pdf_error',
          severity: 'medium',
          details: result.errorMessage ?? 'Unknown',
        );
        return;
      }

      try {
        await FirebaseFirestore.instance.collection('pdf_exports').add({
          'employee_id': effectiveEmp.employeeId,
          'employee_id_hash':
          _hashEmployeeId(effectiveEmp.employeeId, _sessionNonce),
          'report_type': 'Payslip PDF',
          'month': DateFormat('yyyy-MM').format(DateTime.now()),
          'net_pay': _breakdown.netPay,
          'salary_source': _salarySource,
          'exported_at': FieldValue.serverTimestamp(),
          'platform': kIsWeb ? 'Web' : 'Mobile',
          'session_nonce': _sessionNonce,
        });
      } catch (e) {
        debugPrint('⚠️ pdf_exports log warning: $e');
      }

      await _logSecurityEvent(
        type: 'reports_pdf_generated',
        severity: 'info',
        details: 'PDF successfully generated (#$_totalPdfGenerated)',
        sensitive: true,
      );

      if (mounted) {
        if (result.filePath != null && result.filePath!.isNotEmpty) {
          final fname =
              result.filePath!.split(Platform.pathSeparator).last;
          _showSnack('✓ Saved to: Download/RACOMA_Payslips/$fname');
        } else {
          _showSnack('PDF payslip generated ✓');
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack(
          'Export failed. Please try again.',
          error: true,
          action: SnackBarAction(
            label: 'Report',
            textColor: Colors.white,
            onPressed: () =>
                _showContactHrSheet(prefillCategory: 'pdf_download'),
          ),
        );
      }
      await _logSecurityEvent(
        type: 'reports_pdf_error',
        severity: 'medium',
        details: 'PDF generation failed',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showPreDownloadPasswordDialog(String password) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

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
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _Mock.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: _Mock.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Save Password',
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _Mock.orange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _Mock.orange.withValues(alpha: 0.35),
                        width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectionArea(
                          child: Text(
                            password,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: _Mock.orange,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: Icon(Icons.copy_rounded,
                            color: tc.textGrayDark, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: password));
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
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFFFF4D6D), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This password is the SAME for all your payslips — it never changes. Save it somewhere safe.',
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
                foregroundColor: _Mock.orange,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
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

  // ══════════════════════════════════════════════════════════════
  // 🔑 VIEW MY PDF PASSWORD
  // ══════════════════════════════════════════════════════════════
  Future<void> _showCurrentPdfPassword() async {
    _recordActivity();
    if (_loadingPassword) return;

    final emp = _employee ?? widget.initialEmployee;
    if (emp == null && _rawData == null) {
      _showSnack('Employee data not loaded.', error: true);
      return;
    }

    final empId = emp?.employeeId ??
        (_rawData?['employeeId'] ?? _displayEmpId).toString();

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

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tc.cardBorder),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _Mock.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.vpn_key_rounded,
                  color: _Mock.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your PDF Password',
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
                'Use this password to open ANY payslip PDF you download. '
                    'This is the SAME password forever — save it somewhere safe.',
                style: TextStyle(
                    color: tc.textGrayDark,
                    fontSize: 13,
                    height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _Mock.orange.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _Mock.orange.withValues(alpha: 0.35),
                      width: 1.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectionArea(
                        child: Text(
                          pwd,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            color: _Mock.orange,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      icon: Icon(Icons.copy_rounded,
                          color: tc.textGrayDark, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: pwd));
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
                  const Icon(Icons.lightbulb_outline_rounded,
                      color: Color(0xFFFF4D6D), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Copy this now and save it somewhere safe. '
                          'It won\'t change — even after future downloads.',
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
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: _Mock.orange,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
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

  // ══════════════════════════════════════════════════════════════
  // 🆘 CONTACT HR / REPORT ISSUE
  // ══════════════════════════════════════════════════════════════
  Future<void> _showContactHrSheet({String? prefillCategory}) async {
    if (!mounted) return;
    if (_sendingSupport) return;

    _recordActivity();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final emp = _employee ?? widget.initialEmployee;
    if (emp == null && _rawData == null) {
      _showSnack('Employee data not loaded. Please reload the screen.',
          error: true);
      return;
    }

    final Employee effectiveEmp;
    if (emp != null) {
      effectiveEmp = emp;
    } else {
      final now = DateTime.now();
      effectiveEmp = Employee(
        id: (_rawData!['id'] ?? _displayEmpId).toString(),
        employeeId:
        (_rawData!['employeeId'] ?? _displayEmpId).toString(),
        firstName: (_rawData!['firstName'] ?? '').toString(),
        lastName: (_rawData!['lastName'] ?? '').toString(),
        email: (_rawData!['email'] ?? '').toString(),
        department: _department,
        position: _designation,
        createdAt: now,
        updatedAt: now,
      );
    }

    String selectedCategory =
        prefillCategory ?? SupportRequestService.categories.first.value;
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
                          child: const Icon(Icons.support_agent_rounded,
                              color: _Mock.orange, size: 20),
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
                                style: TextStyle(
                                    color: tc.textGrayDark, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'What seems to be the problem?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tc.textGrayDark,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...SupportRequestService.categories.map((c) {
                      final selected = selectedCategory == c.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InkWell(
                          onTap: () {
                            setSheet(() => selectedCategory = c.value);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _Mock.orange.withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? _Mock.orange.withValues(alpha: 0.5)
                                    : tc.cardBorder,
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
                                      color: selected
                                          ? _Mock.orange
                                          : tc.textGrayDark,
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
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: tc.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        c.hint,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: tc.textGrayDark),
                                      ),
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
                    Text(
                      'Additional details (optional)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tc.textGrayDark,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      maxLength: 300,
                      style: TextStyle(color: tc.textPrimary, fontSize: 13),
                      cursorColor: _Mock.orange,
                      decoration: InputDecoration(
                        hintText:
                        'Describe what happened (e.g., "Download failed even after tapping OK")...',
                        hintStyle: TextStyle(
                            color: tc.textGrayDark, fontSize: 12),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF4F4F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tc.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: tc.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: _Mock.orange, width: 1.5),
                        ),
                        counterStyle: TextStyle(
                            color: tc.textGrayDark, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: tc.cardBorder),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                  color: tc.textGrayDark,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _sendingSupport
                                ? null
                                : () =>
                                Navigator.pop(ctx, true),
                            icon: const Icon(Icons.send_rounded,
                                color: Colors.white, size: 16),
                            label: const Text(
                              'Send to HR',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _Mock.orange,
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
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
        await _logSecurityEvent(
          type: 'reports_support_sent',
          severity: 'info',
          details: 'Support request sent: $selectedCategory',
          sensitive: true,
        );
        _showSnack('✓ Sent to HR. Please wait for their response.');
      } else {
        _showSnack(
            'Failed to send. Please check your internet and try again.',
            error: true);
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
      backgroundColor:
      error ? const Color(0xFFFF4D6D) : const Color(0xFF00E5A0),
      behavior: SnackBarBehavior.floating,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
      action: action,
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

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
                    curve: Curves.easeInOut,
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
                          _buildPayslipCard(tc, thisMonth),
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
                colors: [
                  Color(0xFFFF8A00),
                  Color(0xFFFA6A00),
                  Color(0xFFF54900),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 1.5),
                  ),
                  child: const Icon(Icons.wifi_off_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _networkErrorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 180,
                  child: ElevatedButton.icon(
                    onPressed: _retryNetworkCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _Mock.orange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Automatically retries when network returns.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc, String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF8A00),
            Color(0xFFFA6A00),
            Color(0xFFF54900),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  _recordActivity();
                  Navigator.maybePop(context);
                },
                behavior: HitTestBehavior.opaque,
                child: const Row(
                  children: [
                    Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 2),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (_sessionValidated)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded,
                          size: 10, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'SECURED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onTap: (_exporting || _downloading)
                    ? null
                    : _onDownloadPressed,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tc.printButtonBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tc.printButtonBorder),
                  ),
                  child: (_exporting || _downloading)
                      ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                        color: _Mock.orange, strokeWidth: 2),
                  )
                      : const Icon(Icons.print_rounded,
                      color: _Mock.orange, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'Payslip Details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Salary slip for $thisMonth',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(_ThemeColors tc, String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'R.A.C.O.M.A',
                  style: TextStyle(
                    color: _Mock.orange,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Smart HR Information System',
                  style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Jumbo HQ, Manila, Philippines',
                  style: TextStyle(
                    color: tc.textGrayDark,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _Mock.paidBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Mock.paidBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: _Mock.lime, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Paid',
                      style: TextStyle(
                        color: _Mock.lime,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Payslip for\n$thisMonth',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: tc.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    final disabled = _exporting || _downloading;
    return GestureDetector(
      onTap: disabled ? null : _onDownloadPressed,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF8A00),
              Color(0xFFFA6A00),
              Color(0xFFF54900),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: disabled
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5),
          )
              : const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded,
                  color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Download as PDF / Print',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewPasswordButton(_ThemeColors tc) {
    final disabled = _loadingPassword;
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
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: _Mock.orange, strokeWidth: 2),
          )
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vpn_key_rounded,
                  color: tc.textGrayDark, size: 16),
              const SizedBox(width: 8),
              Text(
                'View My PDF Password',
                style: TextStyle(
                  color: tc.textGrayDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactHrButton(_ThemeColors tc) {
    final disabled = _sendingSupport;
    return GestureDetector(
      onTap: disabled ? null : () => _showContactHrSheet(),
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _Mock.orange.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Center(
          child: disabled
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: _Mock.orange, strokeWidth: 2),
          )
              : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.support_agent_rounded,
                  color: _Mock.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                'Contact HR / Report Issue',
                style: TextStyle(
                  color: tc.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}