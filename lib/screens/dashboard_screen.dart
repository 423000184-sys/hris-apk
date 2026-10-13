// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/database_service.dart';
import '../services/geofence_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/skeleton_screens.dart';
import 'login_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint('[Dashboard] $message');
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get cardFill => isDark
      ? const Color(0xFF1F1F23)
      : const Color.fromRGBO(131, 131, 131, 0.07);
  Color get darkBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
  Color get toggleActiveBg =>
      isDark ? const Color(0xFF27272A) : Colors.white;

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

class _T {
  static const List<Color> gradient = [
    Color(0xFFFF8A00),
    Color(0xFFFA6A00),
    Color(0xFFF54900),
  ];
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color green = Color(0xFF22C55E);
  static const Color greenDeep = Color(0xFF166534);
  static const Color red = Color(0xFFEF4444);

  static const double r18 = 18;
  static const double r20 = 20;
  static const double r24 = 24;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradient,
    stops: [0.0, 0.5, 1.0],
  );
}

enum _NetworkState { online, offline, checking }

class _WatermarkLogo extends StatelessWidget {
  final bool isDark;
  final double rotationDegrees;

  static const AssetImage _provider = AssetImage('assets/images/logo.png');

  const _WatermarkLogo({
    required this.isDark,
    this.rotationDegrees = 425,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: Transform.rotate(
          angle: rotationDegrees * 3.1415926535 / 180,
          child: Opacity(
            opacity: isDark ? 0.15 : 0.80,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color.fromRGBO(255, 138, 0, 0.10),
                BlendMode.srcIn,
              ),
              child: Image(
                image: _provider,
                width: 500,
                height: 500,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final VoidCallback? onClockAction;
  final Employee? initialEmployee;

  const DashboardScreen({
    super.key,
    this.onTabSwitch,
    this.onClockAction,
    this.initialEmployee,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Employee? _employee;
  bool _isClockedIn = false;
  String _clockInTime = '--:--';
  String _clockOutTime = '--:--';
  bool _isLoadingAttendance = true;
  Timer? _durationTimer;
  String _elapsedDuration = '00:00:00';
  DateTime? _rawClockInDateTime;

  String? _photoUrl;

  StreamSubscription<QuerySnapshot>? _attendanceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;
  StreamSubscription<bool>? _connectivitySub;

  String? _initError;

  bool _isInRange = false;
  bool _wfhAccess = false;
  bool _isDriver = false;
  bool _checkingLocation = true;
  String _role = '';
  String _department = '';
  double? _distanceMeters;
  bool _mockLocationDetected = false;

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';

  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;

  static const String _kLastHeartbeatKey = 'dashboard_last_heartbeat';
  static const String _kEmployeeHashKey = 'dashboard_employee_hash';

  static const Duration _heartbeatInterval = Duration(minutes: 2);
  static const Duration _maxInactivityTime = Duration(minutes: 30);
  static const Duration _clockActionCooldown = Duration(seconds: 3);
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const int _maxClockActionsPerSession = 20;
  static const int _maxSecurityLogsPerMinute = 20;
  static const int _maxAttendanceRetries = 3;

  static const AssetImage _logoProvider =
  AssetImage('assets/images/logo.png');

  late final String _sessionNonce;
  String? _employeeDataHash;
  String? _deviceBinding;
  Timer? _heartbeatTimer;
  Timer? _sessionWatchdog;
  DateTime? _lastUserActivityAt;
  DateTime? _lastClockActionAt;
  int _totalClockActions = 0;
  bool _sessionValidated = false;
  bool _deviceCompromised = false;
  bool _integrityChecked = false;
  bool _obscureContent = false;
  bool _loggedOut = false;

  bool _clockActionInProgress = false;
  bool? _cachedSessionValid;
  DateTime? _sessionCacheTime;

  final Map<String, DateTime> _recentSecurityLogs = {};

  bool get _canClock => _isInRange || _wfhAccess || _isDriver;
  bool get _isWfhMode => _wfhAccess && !_isInRange;
  bool get _isDriverMode => _isDriver && !_isInRange && !_wfhAccess;
  bool get _isOnline => _networkState == _NetworkState.online;

  final DateTime _payslipMonth =
  DateTime(DateTime.now().year, DateTime.now().month - 1);
  double? _payslipAmount;
  bool _payslipLoading = true;
  bool _payslipError = false;

  bool get _isPayslipVisible {
    final now = DateTime.now();
    final firstDayAfterPayslipMonth =
    DateTime(_payslipMonth.year, _payslipMonth.month + 1, 1);
    return !now.isBefore(firstDayAfterPayslipMonth);
  }

  String? get _employeeId {
    final id = _employee?.employeeId ?? widget.initialEmployee?.employeeId;
    if (id != null && id.isNotEmpty) return id;
    final fallback = _employee?.id ?? widget.initialEmployee?.id;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String? get _employeeDocId {
    final id = _employee?.id ?? widget.initialEmployee?.id;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(_logoProvider, context).catchError((e) {
          _secureLog('⚠️ Logo precache failed: $e');
        });
      }
    });

    try {
      _employee = widget.initialEmployee;
      _photoUrl = _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;
      _role = _employee?.position ?? '';
      _department = _employee?.department ?? '';
      _wfhAccess = _readWfhFromEmployee();
      _isDriver = _isDriverRole(_role, _department);

      _secureLog('═══════════════════════════════════════════');
      _secureLog('👤 [Dashboard] Employee loaded:');
      _secureLog('   id          = ${_employee?.id ?? "null"}');
      _secureLog('   employeeId  = ${_employee?.employeeId ?? "null"}');
      _secureLog('   name        = ${_employee?.fullName ?? "null"}');
      _secureLog('   role        = ${_employee?.position ?? "null"}');
      _secureLog('   department  = ${_employee?.department ?? "null"}');
      _secureLog('   wfhAccess   = $_wfhAccess');
      _secureLog('   isDriver    = $_isDriver');
      _secureLog('═══════════════════════════════════════════');

      try {
        _connectivitySub =
            ConnectivityService.instance.onStatusChange.listen((online) {
              if (!mounted) return;
              _secureLog('🌐 connectivity → online=$online');

              if (!online) {
                _overlayDelayTimer?.cancel();
                setState(() {
                  _networkState = _NetworkState.offline;
                  _networkErrorMessage =
                  'No internet connection.\nPlease check your network.';
                  _isLoadingAttendance = true;
                  _checkingLocation = true;
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
        _secureLog('⚠️ connectivity listen failed: $e');
      }

      _bootstrapSecurity();

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) debugGeofenceCheck();
      });
    } catch (e, st) {
      _secureLog('❌ initState error: $e\n$st');
      _initError = e.toString();
      _isLoadingAttendance = false;
      _checkingLocation = false;
    }
  }

  Future<void> debugGeofenceCheck() async {
    _secureLog('═══════════════════════════════════════════');
    _secureLog('🔍 [DEBUG] Manual geofence check');
    _secureLog('═══════════════════════════════════════════');

    try {
      _secureLog('Test 1: GeofenceService.checkGeofence()');
      final r1 = await GeofenceService.instance.checkGeofence();
      _secureLog('   → inside=${r1.isInside}');
      _secureLog('   → status=${r1.status}');
      _secureLog('   → distance=${r1.distanceMeters}m');
      _secureLog('   → radius=${r1.radiusUsed}m');
      _secureLog('   → matched=${r1.matchedLocationName}');

      final docId = _employeeDocId;
      if (docId != null) {
        _secureLog('Test 2: checkGeofenceForEmployee(docId=$docId)');
        try {
          final r2 = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: docId);
          _secureLog('   → inside=${r2.isInside}');
          _secureLog('   → distance=${r2.distanceMeters}m');
        } catch (e) {
          _secureLog('   → ERROR: $e');
        }
      }

      final empId = _employeeId;
      if (empId != null && empId != docId) {
        _secureLog('Test 3: checkGeofenceForEmployee(empId=$empId)');
        try {
          final r3 = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: empId);
          _secureLog('   → inside=${r3.isInside}');
          _secureLog('   → distance=${r3.distanceMeters}m');
        } catch (e) {
          _secureLog('   → ERROR: $e');
        }
      }
    } catch (e, st) {
      _secureLog('❌ [DEBUG] Failed: $e');
      _secureLog('$st');
    }
    _secureLog('═══════════════════════════════════════════');
  }

  Future<void> _bootstrapSecurity() async {
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (e) {
      _secureLog('FLAG_SECURE failed: $e');
    }

    try {
      final ok =
      await SecurityHardeningService.instance.checkDeviceIntegrity();
      _deviceCompromised = !ok;
      _integrityChecked = true;
      if (!ok) {
        _secureLog('🚨 Device compromised: '
            '${SecurityHardeningService.instance.integrityIssues.join(",")}');
      }
    } catch (e) {
      _secureLog('Integrity check failed: $e');
    }

    try {
      _deviceBinding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}

    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      await _handleForcedLogout('Invalid session');
      return;
    }

    final dataTampered = await _verifyEmployeeDataIntegrity();
    if (dataTampered) {
      _secureLog('🚨 Employee data tampered — forcing logout');
      await _handleForcedLogout('Employee data integrity failed');
      return;
    }

    if (_employee != null) {
      _employeeDataHash = _hashEmployeeData(_employee!);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            '${_kEmployeeHashKey}_${_employee!.id}', _employeeDataHash!);
      } catch (_) {}
    }

    _startSecurityMonitoring();
    _safeInit();
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashEmployeeData(Employee emp) {
    final data = '${emp.id}|${emp.employeeId}|${emp.email}|'
        '${emp.position}|${emp.department}|${emp.wfhAccess}';
    return sha256.convert(utf8.encode(data)).toString();
  }

  Future<bool> _verifyEmployeeDataIntegrity() async {
    if (_employee == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash =
      prefs.getString('${_kEmployeeHashKey}_${_employee!.id}');
      if (storedHash == null) return false;

      final currentHash = _hashEmployeeData(_employee!);
      if (storedHash != currentHash) {
        _secureLog('🚨 Hash mismatch! Stored=$storedHash Current=$currentHash');
        await _logSecurityEvent(
          type: 'employee_data_tampered',
          severity: 'critical',
          details: 'Stored hash != current hash',
        );
        return true;
      }
      return false;
    } catch (e) {
      _secureLog('⚠️ Integrity verify error: $e');
      return false;
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    try {
      if (!_isOnline) return;
      if (_employee?.id == null) return;

      final key = '$type|$details';
      final now = DateTime.now();
      final lastLog = _recentSecurityLogs[key];
      if (lastLog != null &&
          now.difference(lastLog).inSeconds < 60) {
        _secureLog('⏭️ Skipping duplicate security log: $type');
        return;
      }

      _recentSecurityLogs.removeWhere(
              (_, v) => now.difference(v).inMinutes > 1);
      if (_recentSecurityLogs.length >= _maxSecurityLogsPerMinute) {
        _secureLog('🚦 Security log rate limit hit');
        return;
      }

      _recentSecurityLogs[key] = now;

      final hashDevice = _deviceBinding != null
          ? sha256.convert(utf8.encode(_deviceBinding!)).toString()
          : null;

      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': _employee!.id,
        'employeeName': _employee!.fullName,
        'sessionNonce': _sessionNonce,
        'deviceBinding': _deviceBinding,
        'deviceHash': hashDevice,
        'deviceCompromised': _deviceCompromised,
        'mockLocation': _mockLocationDetected,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'dashboard',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('⚠️ security log error: $e');
    }
  }

  void _recordUserActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedSessionValid != null &&
        _sessionCacheTime != null &&
        DateTime.now().difference(_sessionCacheTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }

    if (!kIsWeb && _deviceCompromised) {
      await _logSecurityEvent(
        type: 'dashboard_compromised_device',
        severity: 'critical',
        details:
        SecurityHardeningService.instance.integrityIssues.join(','),
      );
      _cachedSessionValid = false;
      _sessionCacheTime = DateTime.now();
      return false;
    }

    try {
      String? sessionEmpId;
      try {
        sessionEmpId = await SecurityHardeningService.instance
            .getCurrentEmployeeId()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _secureLog('Hardening session check failed: $e');
      }

      bool legacyValid = false;
      String? legacyEmpId;
      try {
        legacyValid = await SecurityService.instance
            .isSessionValid()
            .timeout(const Duration(seconds: 5));
        legacyEmpId =
        await SecurityService.instance.getCurrentEmployeeId();
      } catch (e) {
        _secureLog('Legacy session check failed: $e');
      }

      if ((sessionEmpId == null || sessionEmpId.isEmpty) && !legacyValid) {
        _secureLog('🚨 No valid session — FAIL');
        await _logSecurityEvent(
          type: 'dashboard_session_invalid',
          severity: 'high',
          details: 'No valid session token found',
        );
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      final currentEmpId = _employee?.id;
      final checkedEmpId = sessionEmpId ?? legacyEmpId;

      if (currentEmpId != null &&
          checkedEmpId != null &&
          checkedEmpId != currentEmpId) {
        _secureLog('🚨 Employee mismatch: '
            'session=$checkedEmpId, dashboard=$currentEmpId');
        await _logSecurityEvent(
          type: 'dashboard_session_mismatch',
          severity: 'critical',
          details: 'Session ($checkedEmpId) != dashboard ($currentEmpId)',
        );
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      _cachedSessionValid = true;
      _sessionCacheTime = DateTime.now();
      return true;
    } catch (e) {
      _secureLog('⚠️ Session validation error: $e');
      await _logSecurityEvent(
        type: 'dashboard_session_error',
        severity: 'high',
        details: 'Validation error: $e',
      );
      _cachedSessionValid = false;
      _sessionCacheTime = DateTime.now();
      return false;
    }
  }

  void _startSecurityMonitoring() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (!mounted || _loggedOut) return;

      try {
        await SecurityService.instance.markSessionActive();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _kLastHeartbeatKey, DateTime.now().millisecondsSinceEpoch);
        _secureLog('🔒 Heartbeat sent');
      } catch (e) {
        _secureLog('⚠️ Heartbeat failed: $e');
      }

      final valid = await _validateSession(forceRefresh: true);
      if (!valid && mounted && !_loggedOut) {
        await _handleForcedLogout('Session invalidated');
      }
    });

    _sessionWatchdog?.cancel();
    _sessionWatchdog = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;

      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _maxInactivityTime) {
        _secureLog('🚨 Inactivity timeout: ${idle.inMinutes}min');
        await _logSecurityEvent(
          type: 'dashboard_inactivity_logout',
          severity: 'info',
          details: 'Auto-logout after ${idle.inMinutes} min inactivity',
        );
        await _handleForcedLogout('Inactivity timeout');
      }
    });
  }

  Future<void> _handleForcedLogout(String reason) async {
    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    _secureLog('🚨 Forced logout: $reason');

    _heartbeatTimer?.cancel();
    _sessionWatchdog?.cancel();
    _durationTimer?.cancel();
    _attendanceSub?.cancel();
    _employeeSub?.cancel();

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}

    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}
    try {
      await SecurityService.instance.clearSession();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fp_preauth_employee_id');
      await prefs.remove('fp_preauth_time');
      await prefs.remove('fp_preauth_nonce');
      await prefs.remove(_kLastHeartbeatKey);
    } catch (_) {}

    await _logSecurityEvent(
      type: 'dashboard_forced_logout',
      severity: 'high',
      details: 'Forced logout: $reason',
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
    final obscure = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;

    if (obscure != _obscureContent && mounted) {
      setState(() => _obscureContent = obscure);
    }

    if (state == AppLifecycleState.resumed) {
      _recordUserActivity();
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) {
          _handleForcedLogout('Session invalid on resume');
        }
      });
    }
  }

  Future<bool> _hasNetwork() async {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkNetworkOnEntry() async {
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);

    final hasNet = await _hasNetwork();
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

    setState(() {
      _networkState = _NetworkState.checking;
      _isLoadingAttendance = true;
      _checkingLocation = true;
      _showOfflineOverlay = false;
    });

    await _checkNetworkOnEntry();

    if (_networkState == _NetworkState.online && mounted) {
      try {
        await _loadTodayAttendance();
        await _loadEmployeePhoto();
        await _refreshLocation();
      } catch (e) {
        _secureLog('⚠️ Refresh after reconnect failed: $e');
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (mounted) {
        setState(() {
          _isLoadingAttendance = false;
          _checkingLocation = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoadingAttendance = false;
          _checkingLocation = false;
        });
      }
    }
  }

  bool _readWfhFromEmployee() {
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) return false;
    try {
      final dynamic v = (emp as dynamic).wfhAccess;
      if (v is bool) return v;
      if (v != null) return v.toString().toLowerCase() == 'true';
    } catch (_) {}
    return false;
  }

  bool _isDriverRole(String role, String dept) {
    final r = role.toLowerCase().trim();
    final d = dept.toLowerCase().trim();
    return r.contains('driver') ||
        r.contains('rider') ||
        d.contains('driver') ||
        d.contains('rider');
  }

  Future<void> _safeInit() async {
    final startTime = DateTime.now();

    await _checkNetworkOnEntry();

    try {
      await _loadTodayAttendance().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _secureLog('⚠️ Attendance load timeout');
        },
      );
    } catch (e) {
      _secureLog('❌ _loadTodayAttendance: $e');
    }

    _startAttendanceStream();
    _startEmployeeListener();
    await _refreshLocation();

    try {
      await _loadPayslipAmount();
    } catch (e) {
      _secureLog('❌ _loadPayslipAmount: $e');
    }

    try {
      await _loadEmployeePhoto();
    } catch (e) {
      _secureLog('❌ _loadEmployeePhoto: $e');
    }

    setState(() => _sessionValidated = true);

    _logSecurityEvent(
      type: 'dashboard_opened',
      severity: 'info',
      details: 'Dashboard opened',
    );

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inMilliseconds < 800) {
      await Future.delayed(
          Duration(milliseconds: 800 - elapsed.inMilliseconds));
    }

    if (mounted) {
      setState(() {
        _isLoadingAttendance = false;
        _checkingLocation = false;
      });
    }
  }

  void _startEmployeeListener() {
    final docId = _employeeDocId;
    if (docId == null || docId.isEmpty) {
      _secureLog('⚠️ [EmpListener] Skipped — no docId');
      return;
    }

    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) {
          _secureLog('⚠️ [EmpListener] Doc does not exist: $docId');
          return;
        }

        final rawWfh = data['wfhAccess'];
        final wfh = rawWfh is bool
            ? rawWfh
            : (rawWfh?.toString().toLowerCase() == 'true');

        final newRole =
        (data['role'] ?? data['position'] ?? _role).toString();
        final newDept = (data['department'] ?? _department).toString();
        final newIsDriver = _isDriverRole(newRole, newDept);

        final status = (data['status'] ?? '').toString().toLowerCase();
        const blocked = {'suspended', 'terminated', 'deleted', 'blocked'};
        if (blocked.contains(status)) {
          _secureLog('🚫 [EmpListener] Account blocked: $status');
          _logSecurityEvent(
            type: 'dashboard_account_blocked',
            severity: 'critical',
            details: 'Status changed to: $status',
          );
          _handleForcedLogout('Account status: $status');
          return;
        }

        final changed = wfh != _wfhAccess ||
            newIsDriver != _isDriver ||
            newRole != _role;

        if (changed) {
          _secureLog('🔄 [EmpListener] Changes detected — updating state');
          setState(() {
            _wfhAccess = wfh;
            _role = newRole;
            _department = newDept;
            _isDriver = newIsDriver;
          });
          _refreshLocation();
        }
      },
      onError: (e) => _secureLog('❌ [EmpListener] Error: $e'),
    );
  }

  Future<void> _refreshLocation() async {
    if (mounted) setState(() => _checkingLocation = true);

    GeofenceService.instance.invalidateCache();

    try {
      final docId = _employeeDocId;
      final empId = _employeeId;

      _secureLog('📍 [Geo] Attempting geofence check:');
      _secureLog('   docId   = ${docId ?? "null"}');
      _secureLog('   empId   = ${empId ?? "null"}');
      _secureLog('   isDriver= $_isDriver, isWfh= $_wfhAccess');

      GeofenceResult? result;
      Exception? lastError;
      String usedId = 'none';

      if (docId != null && docId.isNotEmpty) {
        try {
          result = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: docId)
              .timeout(const Duration(seconds: 15));
          usedId = 'docId=$docId';
          _secureLog('✅ [Geo] OK with docId=$docId');
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          _secureLog('⚠️ [Geo] Failed with docId: $e');
        }
      }

      if (result == null &&
          empId != null &&
          empId.isNotEmpty &&
          empId != docId) {
        try {
          result = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: empId)
              .timeout(const Duration(seconds: 15));
          usedId = 'empId=$empId';
          _secureLog('✅ [Geo] OK with empId=$empId');
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          _secureLog('⚠️ [Geo] Failed with empId: $e');
        }
      }

      if (result == null) {
        try {
          result = await GeofenceService.instance
              .checkGeofence()
              .timeout(const Duration(seconds: 12));
          usedId = 'basic';
          _secureLog('✅ [Geo] OK (basic check)');
        } catch (e) {
          lastError = e is Exception ? e : Exception(e.toString());
          _secureLog('⚠️ [Geo] Failed (basic): $e');
        }
      }

      if (!mounted) return;

      if (result == null) {
        _secureLog('❌ [Geo] ALL attempts failed: $lastError');
        setState(() {
          _checkingLocation = false;
          _isInRange = false;
        });
        return;
      }

      final GeofenceResult nonNullResult = result;

      bool mockDetected = false;
      try {
        final dynamic r = nonNullResult;
        final dynamic mock = (r as dynamic).isMockLocation;
        if (mock is bool) mockDetected = mock;
      } catch (_) {}

      if (mockDetected && !_mockLocationDetected) {
        _secureLog('🚨 [Geo] Mock location detected!');
        _logSecurityEvent(
          type: 'mock_location_detected',
          severity: 'critical',
          details: 'User device has mock location enabled',
        );
      }

      _secureLog('📍 [Geo] Result via $usedId:');
      _secureLog('   isInside       = ${nonNullResult.isInside}');
      _secureLog('   status         = ${nonNullResult.status}');
      _secureLog('   distanceMeters = ${nonNullResult.distanceMeters}');
      _secureLog('   radiusUsed     = ${nonNullResult.radiusUsed}');
      _secureLog('   matchedName    = ${nonNullResult.matchedLocationName}');

      setState(() {
        _isInRange = nonNullResult.isInside ||
            nonNullResult.status == GeofenceStatus.insideWithTolerance;
        _distanceMeters = nonNullResult.distanceMeters;
        _checkingLocation = false;
        _mockLocationDetected = mockDetected;
      });

      if (nonNullResult.usedTolerance) {
        _logSecurityEvent(
          type: 'geofence_tolerance_used',
          severity: 'info',
          details:
          'Distance=${nonNullResult.distanceMeters?.toStringAsFixed(0)}m, '
              'radius=${nonNullResult.radiusUsed?.toStringAsFixed(0)}m',
        );
      }
    } catch (e, st) {
      _secureLog('❌ [Geo] Exception: $e');
      _secureLog('$st');
      if (!mounted) return;
      setState(() => _checkingLocation = false);
    }
  }

  void _startAttendanceStream() {
    final employeeId = _employeeId;
    if (employeeId == null) return;

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    _attendanceSub?.cancel();
    _attendanceSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: employeeId)
        .where('date', isEqualTo: todayStr)
        .snapshots()
        .listen(
          (snapshot) {
        if (!mounted) return;
        _processAttendanceDocs(snapshot.docs);
      },
      onError: (e) => _secureLog('📡 Stream error: $e'),
    );
  }

  String? _extractTimeString(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) return rawTime.trim();
    final rawTs = data['timestamp'];
    DateTime? dt;
    if (rawTs is Timestamp) {
      dt = rawTs.toDate().toLocal();
    } else if (rawTs is String && rawTs.trim().isNotEmpty) {
      dt = DateTime.tryParse(rawTs.trim())?.toLocal();
    } else if (rawTs is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTs);
    }
    if (dt != null) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return null;
  }

  DateTime? _extractDateTime(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      final parts = rawTime.trim().split(':');
      if (parts.length >= 2) {
        try {
          final now = DateTime.now();
          return DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
            parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
          );
        } catch (_) {}
      }
    }
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) return rawTs.toDate().toLocal();
    if (rawTs is String && rawTs.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawTs.trim());
      if (parsed != null) return parsed.toLocal();
    }
    if (rawTs is int) return DateTime.fromMillisecondsSinceEpoch(rawTs);
    return null;
  }

  void _processAttendanceDocs(List<QueryDocumentSnapshot> docs) {
    if (!mounted) return;

    String? latestInTime;
    String? latestOutTime;
    bool clockedInState = false;
    DateTime? parsedInDateTime;

    if (docs.isNotEmpty) {
      final sortedDocs = [...docs];
      sortedDocs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aTime = _extractDateTime(aData) ?? DateTime(2000);
        final bTime = _extractDateTime(bData) ?? DateTime(2000);
        return aTime.compareTo(bTime);
      });

      for (final doc in sortedDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type']?.toString().toUpperCase();
        final timeVal = _extractTimeString(data) ?? '--:--';

        if (type == 'IN' || type == 'CLOCK_IN') {
          latestInTime = _formatTimeTo12Hour(timeVal);
          latestOutTime = null;
          clockedInState = true;
          try {
            final parts = timeVal.split(':');
            if (parts.length >= 2) {
              final now = DateTime.now();
              parsedInDateTime = DateTime(
                now.year,
                now.month,
                now.day,
                int.parse(parts[0]),
                int.parse(parts[1]),
                parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
              );
            }
          } catch (_) {}
        } else if (type == 'OUT' || type == 'CLOCK_OUT') {
          latestOutTime = _formatTimeTo12Hour(timeVal);
          clockedInState = false;
          parsedInDateTime = null;
        }
      }
    }

    setState(() {
      _isClockedIn = clockedInState;
      _clockInTime = latestInTime ?? '--:--';
      _clockOutTime = latestOutTime ?? '--:--';
      _rawClockInDateTime = parsedInDateTime;
      _isLoadingAttendance = false;
    });

    if (_isClockedIn) {
      if (_durationTimer == null || !_durationTimer!.isActive) {
        _startElapsedTimer();
      }
    } else {
      _durationTimer?.cancel();
      _durationTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    _connectivitySub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sessionWatchdog?.cancel();

    SecurityHardeningService.instance.disableSecureScreen();

    super.dispose();
  }

  Future<void> _loadEmployeePhoto() async {
    try {
      final empId = _employee?.id ?? widget.initialEmployee?.id;
      if (empId == null || empId.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final url = data['photoUrl']?.toString();
      if (mounted && url != null && url.isNotEmpty && url != '—') {
        if (_photoUrl != url) {
          setState(() => _photoUrl = url);
        }
      }
    } catch (e) {
      _secureLog('❌ Error loading photo: $e');
    }
  }

  void _startElapsedTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rawClockInDateTime != null && _isClockedIn) {
        final now = DateTime.now();
        final difference = now.difference(_rawClockInDateTime!);
        final hours = difference.inHours.toString().padLeft(2, '0');
        final minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() => _elapsedDuration = '$hours:$minutes:$seconds');
        }
      }
    });
  }

  Future<void> loadTodayAttendance() async => _loadTodayAttendance();
  Future<void> loadPayslipAmount() async => _loadPayslipAmount();

  Future<void> refreshAll() async {
    _recordUserActivity();
    await _checkNetworkOnEntry();
    await _loadTodayAttendance();
    await _loadEmployeePhoto();
    await _refreshLocation();
  }

  Future<void> _loadTodayAttendance() async {
    if (!mounted) return;
    final employeeId = _employeeId;
    if (employeeId == null) return;

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    for (int attempt = 0; attempt < _maxAttendanceRetries; attempt++) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: employeeId)
            .where('date', isEqualTo: todayStr)
            .get()
            .timeout(const Duration(seconds: 10));

        _processAttendanceDocs(snapshot.docs);
        return;
      } catch (e) {
        _secureLog('⚠️ Attendance load attempt ${attempt + 1} failed: $e');
        if (attempt < _maxAttendanceRetries - 1) {
          final backoff = Duration(milliseconds: 500 * (attempt + 1));
          await Future.delayed(backoff);
        }
      }
    }

    _secureLog('❌ All attendance load attempts failed');
  }

  String _formatTimeTo12Hour(String t) {
    try {
      if (t.contains('AM') || t.contains('PM')) return t;
      final parts = t.split(':');
      if (parts.length < 2) return t;
      int h = int.parse(parts[0]);
      final m = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) h = 12;
      if (h > 12) h -= 12;
      return '${h.toString().padLeft(2, '0')}:$m $period';
    } catch (_) {
      return t;
    }
  }

  Future<void> _loadPayslipAmount() async {
    if (!mounted) return;
    try {
      final employeeId = _employeeId;
      if (employeeId == null) {
        if (mounted) {
          setState(() {
            _payslipAmount = null;
            _payslipLoading = false;
          });
        }
        return;
      }
      final double? amount =
      await _fetchPayslipFromBackend(employeeId, _payslipMonth);
      if (!mounted) return;
      setState(() {
        _payslipAmount = amount;
        _payslipLoading = false;
      });
    } catch (e) {
      _secureLog('Payslip fetch error: $e');
      if (!mounted) return;
      setState(() {
        _payslipAmount = null;
        _payslipError = true;
        _payslipLoading = false;
      });
    }
  }

  Future<double?> _fetchPayslipFromBackend(
      String employeeId, DateTime month) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return null;
  }

  String _formatPeso(double amount) {
    final wholeStr = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < wholeStr.length; i++) {
      final posFromEnd = wholeStr.length - i;
      buf.write(wholeStr[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '\u20b1${buf.toString()}';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _payslipMonthLabel =>
      '${_monthNames[_payslipMonth.month - 1]} ${_payslipMonth.year}';

  void _handleClockAction() {
    _recordUserActivity();

    if (_clockActionInProgress) {
      _secureLog('🚦 Clock action already in progress — ignored');
      return;
    }

    final now = DateTime.now();
    if (_lastClockActionAt != null) {
      final elapsed = now.difference(_lastClockActionAt!).inMilliseconds;
      if (elapsed < _clockActionCooldown.inMilliseconds) {
        _secureLog('🚦 Clock action rate-limited ($elapsed ms)');
        return;
      }
    }
    _lastClockActionAt = now;
    _totalClockActions++;

    if (_totalClockActions > _maxClockActionsPerSession) {
      _secureLog('🚨 Too many clock actions — BLOCKED');
      _logSecurityEvent(
        type: 'clock_action_abuse',
        severity: 'high',
        details: 'Total clock actions exceeded: $_totalClockActions',
      );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Too many clock actions. Please restart the app.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: _T.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    _clockActionInProgress = true;

    _validateSession(forceRefresh: true).then((valid) async {
      if (!valid) {
        _clockActionInProgress = false;
        _handleForcedLogout('Session invalidated during clock action');
        return;
      }

      if (_deviceCompromised) {
        _clockActionInProgress = false;
        _secureLog('🚨 Compromised device — clock action blocked');
        _logSecurityEvent(
          type: 'clock_action_blocked_compromised',
          severity: 'critical',
          details: 'Clock action on compromised device',
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'This device is flagged as compromised. Action blocked.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: _T.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
        _clockActionInProgress = false;
        _secureLog('🚨 Mock location — clock action blocked');
        _logSecurityEvent(
          type: 'clock_action_mock_location',
          severity: 'critical',
          details: 'Mock location detected during clock action',
        );
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Location verification failed. Please disable fake GPS.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: _T.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        return;
      }

      _logSecurityEvent(
        type: 'clock_action_triggered',
        severity: 'info',
        details: 'User triggered clock action '
            '(${_isClockedIn ? "clock_out" : "clock_in"})',
      );

      widget.onClockAction?.call();
      _clockActionInProgress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;
    final isInitialLoad = _isLoadingAttendance && _checkingLocation;

    if (isOffline || isChecking || isInitialLoad) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(
          child: Stack(
            children: [
              const DashboardSkeleton(),
              if (isOffline)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showOfflineOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_showOfflineOverlay,
                      child: _buildNetworkErrorOverlay(tc),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text('Dashboard Error',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _initError = null);
                    _safeInit();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
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
            Positioned(
              bottom: -130,
              left: -150,
              child: _WatermarkLogo(isDark: isDark),
            ),

            RefreshIndicator(
              color: _T.orange,
              onRefresh: refreshAll,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_sessionValidated ||
                              _deviceCompromised ||
                              _mockLocationDetected) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_deviceCompromised)
                                  _buildBadge(
                                    'UNSAFE DEVICE',
                                    Icons.warning_amber_rounded,
                                    _T.red,
                                  ),
                                if (_mockLocationDetected &&
                                    !_deviceCompromised)
                                  _buildBadge(
                                    'FAKE GPS',
                                    Icons.location_off_rounded,
                                    _T.red,
                                  ),
                                if (_sessionValidated &&
                                    !_deviceCompromised &&
                                    !_mockLocationDetected)
                                  _buildBadge(
                                    '',
                                    Icons.verified_user_rounded,
                                    _T.greenDeep,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          _buildHeader(tc),
                          const SizedBox(height: 20),
                          _buildStatusBanner(),
                          const SizedBox(height: 24),
                          _buildToggle(tc),
                          const SizedBox(height: 24),
                          _buildSectionTitle(
                            'Location Status',
                            tc: tc,
                            trailing: _buildGpsTag(tc),
                          ),
                          const SizedBox(height: 12),
                          _buildLocationCard(tc),
                          const SizedBox(height: 24),
                          _buildSectionTitle('Shortcuts', tc: tc),
                          const SizedBox(height: 12),
                          _buildShortcutsGrid(tc),
                          if (_isPayslipVisible) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle(
                              'Recent Payslip',
                              tc: tc,
                              viewAll: true,
                              onViewAllTap: () => widget.onTabSwitch?.call(4),
                            ),
                            const SizedBox(height: 12),
                            _buildPayslipCard(tc),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: _buildFloatingAction(),
                  ),
                ],
              ),
            ),

            if (_obscureContent) _buildPrivacyShield(),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyShield() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: const Color(0xFF0C0C0E),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _T.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.black,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'R.A.C.O.M.A.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Session hidden for your privacy',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkErrorOverlay(_ThemeColors tc) {
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
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
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
                      foregroundColor: _T.orange,
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

  Widget _buildHeader(_ThemeColors tc) {
    final name = _employee?.firstName ??
        widget.initialEmployee?.firstName ??
        'Employee';
    final lastName =
        _employee?.lastName ?? widget.initialEmployee?.lastName ?? '';
    final photo =
        _photoUrl ?? _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;

    void goToProfile() {
      _recordUserActivity();
      _secureLog('👤 Avatar tapped → Profile tab');
      widget.onTabSwitch?.call(3);
    }

    return Row(
      children: [
        GestureDetector(
          onTap: goToProfile,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tc.darkBorder, width: 1.15),
            ),
            child: ClipOval(child: _buildAvatarContent(photo, name)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HI, ${name.toUpperCase()} ${lastName.toUpperCase()}',
                style: TextStyle(
                  fontSize: 10,
                  color: tc.textGray,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Employee Dashboard',
                    style: TextStyle(
                      fontSize: 14,
                      color: tc.textBlack,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_wfhAccess) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.green),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_work_rounded,
                              size: 10, color: _T.greenDeep),
                          SizedBox(width: 4),
                          Text(
                            'WFH',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _T.greenDeep,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_isDriver && !_wfhAccess) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF3B82F6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping_rounded,
                              size: 10, color: Color(0xFF1E40AF)),
                          SizedBox(width: 4),
                          Text(
                            'DRIVER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E40AF),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_networkState == _NetworkState.offline) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.red),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 10, color: Color(0xFF991B1B)),
                          SizedBox(width: 4),
                          Text(
                            'OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF991B1B),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarContent(String? photo, String name) {
    final hasPhoto = photo != null && photo.isNotEmpty && photo != '—';
    if (!hasPhoto) return _avatarFallback(name);

    if (photo!.startsWith('data:image')) {
      try {
        final b64 = photo.split(',').last;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          width: 45,
          height: 45,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) => _avatarFallback(name),
        );
      } catch (_) {
        return _avatarFallback(name);
      }
    }

    if (photo.startsWith('http')) {
      return Image.network(
        photo,
        width: 45,
        height: 45,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => _avatarFallback(name),
      );
    }

    return _avatarFallback(name);
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _T.orange,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🖼️ STATUS BANNER — image + clean gradient overlay
  // gradient: from-[#09090b] via-[#09090b]/40 to-black/0
  // ═══════════════════════════════════════════════════════════════
  Widget _buildStatusBanner() {
    final String statusText;
    final String subtitle;
    final Color accentColor;

    if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
      statusText = 'fake GPS detected.';
      subtitle = 'Please disable mock location apps to proceed.';
      accentColor = _T.red;
    } else if (_networkState == _NetworkState.offline) {
      statusText = 'offline.';
      subtitle = 'Check your internet connection to continue.';
      accentColor = _T.red;
    } else if (_isClockedIn) {
      statusText = 'clocked in.';
      subtitle = 'Our system verified your location. You are ready to go.';
      accentColor = _T.orange;
    } else if (_checkingLocation) {
      statusText = 'verifying...';
      subtitle = 'Getting your location. Please wait.';
      accentColor = _T.orange;
    } else if (_isWfhMode) {
      statusText = 'on WFH mode.';
      subtitle = 'Work-from-home access is active. You can clock in anytime.';
      accentColor = _T.green;
    } else if (_isDriverMode) {
      statusText = 'on field duty.';
      subtitle = 'Driver/Rider mode — you can clock in from anywhere.';
      accentColor = const Color(0xFF3B82F6);
    } else if (_isInRange) {
      statusText = 'clocked out.';
      subtitle = 'You are inside the authorized zone. Ready to clock in.';
      accentColor = _T.orange;
    } else {
      statusText = 'out of range.';
      subtitle =
      'Clock in from the authorized zone or ask admin for WFH access.';
      accentColor = _T.red;
    }

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFA500), width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 25),
            blurRadius: 50,
            spreadRadius: -12,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ═══ 1. BACKGROUND IMAGE (60% opacity, cover) ═══
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset(
                'assets/images/imagewithfallback.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: const Color(0xFF1A1A1A));
                },
              ),
            ),
          ),

          // ═══ 2. GRADIENT OVERLAY — from-[#09090b] via-[#09090b]/40 to-black/0 ═══
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF09090B),
                    const Color(0xFF09090B).withValues(alpha: 0.40),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // ═══ 3. TEXT CONTENT ═══
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 32, 25, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  softWrap: true,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1.15,
                    ),
                    children: [
                      const TextSpan(text: 'You are currently\n'),
                      TextSpan(
                        text: statusText,
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                Text(
                  subtitle,
                  softWrap: true,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFFA1A1AA),
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

  Widget _buildToggle(_ThemeColors tc) {
    final clocked = _isClockedIn;
    final timeIn = _clockInTime;
    final timeOut = _clockOutTime;
    final canAction = _canClock && _isOnline && !_deviceCompromised;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_T.r18),
        gradient: _T.brandGradient,
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (clocked || !canAction) ? null : _handleClockAction,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock In',
                time: timeIn,
                active: true,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
                locked: !canAction,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: (!clocked || !canAction) ? null : _handleClockAction,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock Out',
                time: timeOut,
                active: false,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
                locked: !canAction,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab({
    required _ThemeColors tc,
    required String label,
    required String time,
    required bool active,
    required Color inactiveLabelColor,
    required Color inactiveTimeColor,
    bool locked = false,
  }) {
    return Opacity(
      opacity: locked ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? tc.toggleActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: _T.orangeBorder, width: 1) : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? tc.textBlack : inactiveLabelColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              locked ? 'Locked' : time,
              style: TextStyle(
                fontSize: 11,
                color: locked
                    ? _T.red
                    : (active ? tc.textMuted : inactiveTimeColor),
                fontWeight: locked ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
      String title, {
        required _ThemeColors tc,
        Widget? trailing,
        bool viewAll = false,
        VoidCallback? onViewAllTap,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: tc.textBlack,
          ),
        ),
        if (trailing != null) trailing,
        if (viewAll)
          GestureDetector(
            onTap: () {
              _recordUserActivity();
              onViewAllTap?.call();
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 12,
                  color: _T.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsTag(_ThemeColors tc) {
    final label = _networkState == _NetworkState.offline
        ? 'Offline'
        : (_checkingLocation
        ? 'Verifying'
        : (_isWfhMode
        ? 'Remote GPS'
        : (_isDriverMode ? 'Field GPS' : 'Live GPS')));
    final icon = _networkState == _NetworkState.offline
        ? Icons.cloud_off_rounded
        : (_checkingLocation
        ? Icons.gps_fixed_rounded
        : (_isWfhMode
        ? Icons.home_work_rounded
        : (_isDriverMode
        ? Icons.local_shipping_rounded
        : Icons.near_me_rounded)));
    final color =
    _networkState == _NetworkState.offline ? _T.red : tc.textBlack;

    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(_ThemeColors tc) {
    final Color dotColor;
    final Color borderColor;
    final Color gradientStart;
    final Color gradientEnd;
    final IconData leadingIcon;
    final String title;
    final String subtitle;
    final Color subtitleColor;

    if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
      dotColor = _T.red;
      borderColor = _T.red;
      gradientStart = _T.red;
      gradientEnd = const Color(0xFFB91C1C);
      leadingIcon = Icons.gps_off_rounded;
      title = 'Fake GPS Detected';
      subtitle = 'Disable mock location to continue';
      subtitleColor = _T.red;
    } else if (_networkState == _NetworkState.offline) {
      dotColor = _T.red;
      borderColor = _T.red;
      gradientStart = _T.red;
      gradientEnd = const Color(0xFFB91C1C);
      leadingIcon = Icons.cloud_off_rounded;
      title = 'Offline';
      subtitle = 'Location unavailable';
      subtitleColor = _T.red;
    } else if (_checkingLocation) {
      dotColor = tc.textMuted;
      borderColor = _T.orangeBorder;
      gradientStart = _T.orange;
      gradientEnd = _T.orange;
      leadingIcon = Icons.gps_fixed_rounded;
      title = 'Verifying location...';
      subtitle = 'Getting GPS position';
      subtitleColor = _T.orange;
    } else if (_isWfhMode) {
      dotColor = _T.green;
      borderColor = _T.green;
      gradientStart = _T.green;
      gradientEnd = const Color(0xFF16A34A);
      leadingIcon = Icons.home_work_rounded;
      title = 'Work From Home';
      subtitle = 'Allowed — clock in from anywhere';
      subtitleColor = _T.green;
    } else if (_isDriverMode) {
      dotColor = const Color(0xFF3B82F6);
      borderColor = const Color(0xFF3B82F6);
      gradientStart = const Color(0xFF3B82F6);
      gradientEnd = const Color(0xFF1E40AF);
      leadingIcon = Icons.local_shipping_rounded;
      title = 'Field Duty';
      subtitle = 'Driver/Rider — clock in allowed';
      subtitleColor = const Color(0xFF3B82F6);
    } else if (_isInRange) {
      dotColor = _T.lime;
      borderColor = _T.orangeBorder;
      gradientStart = _T.orange;
      gradientEnd = _T.orange;
      leadingIcon = Icons.location_on_rounded;
      title = 'HQ Main Office';
      subtitle = 'Inside Authorized Zone';
      subtitleColor = _T.orange;
    } else {
      dotColor = _T.red;
      borderColor = _T.red;
      gradientStart = _T.red;
      gradientEnd = const Color(0xFFB91C1C);
      leadingIcon = Icons.location_off_rounded;
      title = 'Outside Authorized Zone';
      subtitle = _distanceMeters != null
          ? '${_distanceMeters!.toStringAsFixed(0)}m from office'
          : 'You are not in the work zone';
      subtitleColor = _T.red;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: borderColor, width: 1.15),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [gradientStart, gradientEnd],
                  ),
                  shape: BoxShape.circle,
                ),
                child: _checkingLocation &&
                    _networkState != _NetworkState.offline
                    ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Icon(leadingIcon, color: Colors.white, size: 22),
              ),
              if (!_checkingLocation ||
                  _networkState == _NetworkState.offline)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: tc.textBlack,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: subtitleColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsGrid(_ThemeColors tc) {
    final items = [
      (Icons.history_rounded, 'Logs', _T.orange, () {
        _recordUserActivity();
        widget.onTabSwitch?.call(1);
      }),
      (Icons.calendar_month_rounded, 'Leaves', _T.orangeBorder, () {
        _recordUserActivity();
        widget.onTabSwitch?.call(2);
      }),
      (Icons.person_rounded, 'Profile', _T.orange, () {
        _recordUserActivity();
        widget.onTabSwitch?.call(3);
      }),
    ];

    return Row(
      children: items.map((item) {
        final isLast = item == items.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 12),
            child: GestureDetector(
              onTap: item.$4,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                decoration: BoxDecoration(
                  color: tc.cardFill,
                  borderRadius: BorderRadius.circular(_T.r20),
                  border: Border.all(color: _T.orangeBorder, width: 1.15),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: _T.brandGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: _T.orange, width: 1.15),
                      ),
                      child: Icon(item.$1, color: Colors.white, size: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: item.$3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayslipCard(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: _T.brandGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _T.orange.withValues(alpha: 0.2), width: 1.15),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _payslipMonthLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: tc.textBlack,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                _buildPayslipAmountText(tc),
              ],
            ),
          ),
          if (_payslipAmount != null && !_payslipLoading && !_payslipError)
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: _T.orange, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            )
          else if (_payslipError)
            GestureDetector(
              onTap: () {
                _recordUserActivity();
                _loadPayslipAmount();
              },
              behavior: HitTestBehavior.opaque,
              child: const Icon(Icons.refresh_rounded,
                  color: _T.orange, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildPayslipAmountText(_ThemeColors tc) {
    if (_payslipLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _T.orange),
      );
    }
    if (_payslipError) {
      return const Text(
        'Unable to load payslip right now',
        style: TextStyle(fontSize: 12, color: Colors.redAccent),
      );
    }
    if (_payslipAmount == null) {
      return Text(
        'No payslip available yet',
        style: TextStyle(fontSize: 12, color: tc.textGray),
      );
    }
    return Text(
      'Amount: ${_formatPeso(_payslipAmount!)}',
      style: TextStyle(fontSize: 12, color: tc.textGray),
    );
  }

  Widget _buildFloatingAction() {
    if (!_isClockedIn) return const SizedBox.shrink();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: _handleClockAction,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_T.r18),
            gradient: _T.brandGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clock Out (Tap to proceed)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.timer_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        'Duty Time: $_elapsedDuration',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SilkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = -5; i < 20; i++) {
      final path = Path();
      final startX = i * 22.0;
      path.moveTo(startX, 0);
      path.cubicTo(
        startX + 30, size.height * 0.3,
        startX - 10, size.height * 0.7,
        startX + 20, size.height,
      );
      canvas.drawPath(path, paint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFFF8A00).withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 1.1), 90, glowPaint);
  }

  @override
  bool shouldRepaint(_SilkPainter old) => false;
}