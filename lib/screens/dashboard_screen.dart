// lib/screens/dashboard_screen.dart
// ✅ v3.5: Fixed time display sync issue. Removed strict 'date' Firestore query
//          which was failing when dates were saved as Timestamps or different formats.
//          Now filters in memory and listens to all ID variations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/employee.dart';
import '../services/database_service.dart';
import '../services/geofence_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/demo_mode_service.dart';
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

  static const Color demoPurple = Color(0xFFFF8A00);
  static const Color demoAccent = Color(0xFFF54900);

  static const double r18 = 18;
  static const double r20 = 20;
  static const double r24 = 24;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradient,
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient demoGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
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
  StreamSubscription<QuerySnapshot>? _attendanceSubCamel;
  StreamSubscription<QuerySnapshot>? _attendanceSubDocId; // 🆕 3rd stream
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _attendancePollTimer;

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
  static const Duration _sessionCheckTimeout = Duration(seconds: 15);
  static const Duration _attendancePollInterval = Duration(seconds: 30);

  static const Duration _demoSkeletonDuration = Duration(milliseconds: 900);

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

  int _consecutiveTimeouts = 0;
  static const int _maxTimeoutsBeforeLogout = 3;

  static const int _kMaxTabIndex = 3;
  static const int _kTabLogs = 1;
  static const int _kTabLeaves = 2;
  static const int _kTabProfile = 3;

  final Map<String, DateTime> _recentSecurityLogs = {};

  bool get _isDemo => DemoModeService.instance.isEnabled;

  bool get _canClock => _isDemo || _isInRange || _wfhAccess || _isDriver;
  bool get _isWfhMode => _wfhAccess && !_isInRange;
  bool get _isDriverMode => _isDriver && !_isInRange && !_wfhAccess;
  bool get _isOnline => _networkState == _NetworkState.online;

  final DateTime _payslipMonth =
  DateTime(DateTime.now().year, DateTime.now().month - 1);
  double? _payslipAmount;
  bool _payslipLoading = true;
  bool _payslipError = false;

  Map<String, dynamic>? _payslipData;
  bool _payslipDownloading = false;
  String? _payslipLocalPath;
  bool _payslipAlreadyDownloaded = false;
  DateTime? _payslipDownloadedAt;

  static const String _kPayslipCacheKey = 'payslip_cache_meta';

  bool get _isPayslipVisible {
    final now = DateTime.now();
    final firstDayAfterPayslipMonth =
    DateTime(_payslipMonth.year, _payslipMonth.month + 1, 1);
    return !now.isBefore(firstDayAfterPayslipMonth);
  }

  String? get _employeeId {
    if (_isDemo) return DemoModeService.demoEmployee.employeeId;
    final id = _employee?.employeeId ?? widget.initialEmployee?.employeeId;
    if (id != null && id.isNotEmpty) return id;
    final fallback = _employee?.id ?? widget.initialEmployee?.id;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String? get _employeeDocId {
    if (_isDemo) return DemoModeService.demoEmployee.id;
    final id = _employee?.id ?? widget.initialEmployee?.id;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  void _safeSwitchTab(int index) {
    if (index < 0 || index > _kMaxTabIndex) return;
    widget.onTabSwitch?.call(index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(_logoProvider, context).catchError((e) {});
      }
    });

    try {
      _employee = widget.initialEmployee;
      _photoUrl = _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;
      _role = _employee?.position ?? '';
      _department = _employee?.department ?? '';
      _wfhAccess = _readWfhFromEmployee();
      _isDriver = _isDriverRole(_role, _department);

      try {
        _connectivitySub =
            ConnectivityService.instance.onStatusChange.listen((online) {
              if (!mounted) return;
              if (!online) {
                _overlayDelayTimer?.cancel();
                setState(() {
                  _networkState = _NetworkState.offline;
                  _networkErrorMessage = 'No internet connection.\nPlease check your network.';
                  _isLoadingAttendance = _isDemo ? false : true;
                  _checkingLocation = _isDemo ? false : true;
                  _showOfflineOverlay = false;
                });
                _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
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
      } catch (e) {}

      if (_isDemo) {
        _sessionValidated = true;
        _isInRange = true;
        _networkState = _NetworkState.online;
        _isLoadingAttendance = true;
        _checkingLocation = true;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadPayslipAmount();
        });

        Future.delayed(_demoSkeletonDuration, () {
          if (!mounted) return;
          setState(() {
            _isLoadingAttendance = false;
            _checkingLocation = false;
          });
        });
        return;
      }

      _bootstrapSecurity();
    } catch (e) {
      _initError = e.toString();
      _isLoadingAttendance = false;
      _checkingLocation = false;
    }
  }

  Future<void> _bootstrapSecurity() async {
    if (_isDemo) return;
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (_) {}
    try {
      final ok = await SecurityHardeningService.instance.checkDeviceIntegrity();
      _deviceCompromised = !ok;
      _integrityChecked = true;
    } catch (_) {}
    try {
      _deviceBinding = await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}

    final valid = await _validateSession(forceRefresh: true);
    if (!mounted) return;
    if (!valid) {
      await _handleForcedLogout('Invalid session');
      return;
    }

    final dataTampered = await _verifyEmployeeDataIntegrity();
    if (!mounted) return;
    if (dataTampered) {
      await _handleForcedLogout('Employee data integrity failed');
      return;
    }

    if (_employee != null) {
      _employeeDataHash = _hashEmployeeData(_employee!);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('${_kEmployeeHashKey}_${_employee!.id}', _employeeDataHash!);
      } catch (_) {}
    }

    if (!mounted) return;
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
    if (_isDemo) return false;
    if (_employee == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString('${_kEmployeeHashKey}_${_employee!.id}');
      if (storedHash == null) return false;
      final currentHash = _hashEmployeeData(_employee!);
      if (storedHash != currentHash) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    if (_isDemo) return;
    try {
      if (!_isOnline) return;
      if (_employee?.id == null) return;
      final key = '$type|$details';
      final now = DateTime.now();
      final lastLog = _recentSecurityLogs[key];
      if (lastLog != null && now.difference(lastLog).inSeconds < 60) return;

      _recentSecurityLogs.removeWhere((_, v) => now.difference(v).inMinutes > 1);
      if (_recentSecurityLogs.length >= _maxSecurityLogsPerMinute) return;

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
    } catch (_) {}
  }

  void _recordUserActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (_isDemo) return true;

    if (!forceRefresh &&
        _cachedSessionValid != null &&
        _sessionCacheTime != null &&
        DateTime.now().difference(_sessionCacheTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }

    if (!kIsWeb && _deviceCompromised) {
      _cachedSessionValid = false;
      _sessionCacheTime = DateTime.now();
      return false;
    }

    try {
      String? sessionEmpId;
      bool hardeningTimeout = false;
      try {
        sessionEmpId = await SecurityHardeningService.instance
            .getCurrentEmployeeId()
            .timeout(_sessionCheckTimeout);
      } on TimeoutException {
        hardeningTimeout = true;
      } catch (_) {}

      bool legacyValid = false;
      String? legacyEmpId;
      bool legacyTimeout = false;
      try {
        legacyValid = await SecurityService.instance
            .isSessionValid()
            .timeout(_sessionCheckTimeout);
        legacyEmpId = await SecurityService.instance.getCurrentEmployeeId();
      } on TimeoutException {
        legacyTimeout = true;
      } catch (_) {}

      if (hardeningTimeout || legacyTimeout) {
        _consecutiveTimeouts++;
        if (_consecutiveTimeouts >= _maxTimeoutsBeforeLogout) {
          _cachedSessionValid = false;
          _sessionCacheTime = DateTime.now();
          return false;
        }
        _cachedSessionValid = true;
        _sessionCacheTime = DateTime.now();
        return true;
      }

      _consecutiveTimeouts = 0;

      if ((sessionEmpId == null || sessionEmpId.isEmpty) && !legacyValid) {
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      final currentEmpId = _employee?.id;
      final checkedEmpId = sessionEmpId ?? legacyEmpId;

      if (currentEmpId != null &&
          checkedEmpId != null &&
          checkedEmpId != currentEmpId) {
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      _cachedSessionValid = true;
      _sessionCacheTime = DateTime.now();
      return true;
    } catch (_) {
      _consecutiveTimeouts++;
      _cachedSessionValid = _consecutiveTimeouts < _maxTimeoutsBeforeLogout;
      _sessionCacheTime = DateTime.now();
      return _cachedSessionValid!;
    }
  }

  void _startSecurityMonitoring() {
    if (_isDemo) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            _kLastHeartbeatKey, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}

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
        await _handleForcedLogout('Inactivity timeout');
      }
    });
  }

  Future<void> _handleForcedLogout(String reason) async {
    if (_isDemo) return;
    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    _heartbeatTimer?.cancel();
    _sessionWatchdog?.cancel();
    _durationTimer?.cancel();
    _attendancePollTimer?.cancel();
    _attendanceSub?.cancel();
    _attendanceSubCamel?.cancel();
    _attendanceSubDocId?.cancel();
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

    if (_isDemo) return;

    if (state == AppLifecycleState.resumed) {
      _recordUserActivity();
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) {
          _handleForcedLogout('Session invalid on resume');
        } else if (mounted && !_loggedOut) {
          _loadTodayAttendance().catchError((e) {});
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
    if (_isDemo) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);

    final hasNet = await _hasNetwork();
    if (!mounted) return;

    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage = 'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }
    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted) return;
    setState(() {
      _networkState = _NetworkState.checking;
      _isLoadingAttendance = _isDemo ? false : true;
      _checkingLocation = _isDemo ? false : true;
      _showOfflineOverlay = false;
    });

    await _checkNetworkOnEntry();

    if (_networkState == _NetworkState.online && mounted && !_isDemo) {
      try {
        await _loadTodayAttendance();
        await _loadEmployeePhoto();
        await _refreshLocation();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (mounted) {
      setState(() {
        _isLoadingAttendance = false;
        _checkingLocation = false;
      });
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
    if (!mounted) return;

    try {
      await _loadTodayAttendance().timeout(
        const Duration(seconds: 15),
        onTimeout: () {},
      );
    } catch (_) {}
    if (!mounted) return;

    _startAttendanceStream();
    _startEmployeeListener();
    await _refreshLocation();
    if (!mounted) return;

    _attendancePollTimer?.cancel();
    _attendancePollTimer = Timer.periodic(_attendancePollInterval, (_) {
      if (!mounted || _loggedOut || _isDemo) return;
      if (_networkState != _NetworkState.online) return;
      _loadTodayAttendance().catchError((e) {});
    });

    try {
      await _loadPayslipAmount();
    } catch (_) {}
    if (!mounted) return;

    try {
      await _loadEmployeePhoto();
    } catch (_) {}
    if (!mounted) return;

    setState(() => _sessionValidated = true);

    _logSecurityEvent(
      type: 'dashboard_opened',
      severity: 'info',
      details: 'Dashboard opened',
    );

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inMilliseconds < 800) {
      await Future.delayed(Duration(milliseconds: 800 - elapsed.inMilliseconds));
    }

    if (!mounted) return;
    setState(() {
      _isLoadingAttendance = false;
      _checkingLocation = false;
    });
  }

  void _startEmployeeListener() {
    if (_isDemo) return;
    final docId = _employeeDocId;
    if (docId == null || docId.isEmpty) return;

    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;

        final rawWfh = data['wfhAccess'];
        final wfh = rawWfh is bool
            ? rawWfh
            : (rawWfh?.toString().toLowerCase() == 'true');

        final newRole = (data['role'] ?? data['position'] ?? _role).toString();
        final newDept = (data['department'] ?? _department).toString();
        final newIsDriver = _isDriverRole(newRole, newDept);

        final status = (data['status'] ?? '').toString().toLowerCase();
        const blocked = {'suspended', 'terminated', 'deleted', 'blocked'};
        if (blocked.contains(status)) {
          _handleForcedLogout('Account status: $status');
          return;
        }

        final changed = wfh != _wfhAccess ||
            newIsDriver != _isDriver ||
            newRole != _role;

        if (changed) {
          setState(() {
            _wfhAccess = wfh;
            _role = newRole;
            _department = newDept;
            _isDriver = newIsDriver;
          });
          _refreshLocation();
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _refreshLocation() async {
    if (_isDemo) {
      if (mounted) {
        setState(() {
          _isInRange = true;
          _checkingLocation = false;
          _mockLocationDetected = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _checkingLocation = true);
    GeofenceService.instance.invalidateCache();

    try {
      final docId = _employeeDocId;
      final empId = _employeeId;

      GeofenceResult? result;

      if (docId != null && docId.isNotEmpty) {
        try {
          result = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: docId)
              .timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      if (result == null && empId != null && empId.isNotEmpty && empId != docId) {
        try {
          result = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: empId)
              .timeout(const Duration(seconds: 15));
        } catch (_) {}
      }

      if (result == null) {
        try {
          result = await GeofenceService.instance
              .checkGeofence()
              .timeout(const Duration(seconds: 12));
        } catch (_) {}
      }

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _checkingLocation = false;
          _isInRange = false;
        });
        return;
      }

      final nonNullResult = result;
      bool mockDetected = false;
      try {
        final dynamic r = nonNullResult;
        final dynamic mock = (r as dynamic).isMockLocation;
        if (mock is bool) mockDetected = mock;
      } catch (_) {}

      setState(() {
        _isInRange = nonNullResult.isInside ||
            nonNullResult.status == GeofenceStatus.insideWithTolerance;
        _distanceMeters = nonNullResult.distanceMeters;
        _checkingLocation = false;
        _mockLocationDetected = mockDetected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingLocation = false);
    }
  }

  // 🆕 3-way Stream Listener
  void _startAttendanceStream() {
    if (_isDemo) return;

    final empId = _employeeId;
    final docId = _employeeDocId;
    if (empId == null) return;

    // Stream 1: snake_case employee_id
    _attendanceSub?.cancel();
    _attendanceSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: empId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _filterAndProcess(snapshot.docs, empId, docId);
    }, onError: (_) {});

    // Stream 2: camelCase employeeId
    _attendanceSubCamel?.cancel();
    _attendanceSubCamel = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employeeId', isEqualTo: empId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _filterAndProcess(snapshot.docs, empId, docId);
    }, onError: (_) {});

    // Stream 3: camelCase employeeId with docId
    if (docId != null && docId != empId) {
      _attendanceSubDocId?.cancel();
      _attendanceSubDocId = FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employeeId', isEqualTo: docId)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        _filterAndProcess(snapshot.docs, empId, docId);
      }, onError: (_) {});
    }
  }

  // 🆕 Filter logs in-memory by TODAY'S date to avoid strict Firestore query issues
  void _filterAndProcess(Iterable<QueryDocumentSnapshot> docs, String empId, String? docId) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final filtered = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final dateStr = data['date']?.toString() ?? '';
      if (dateStr.startsWith(todayStr)) return true;

      final ts = data['timestamp'];
      if (ts is Timestamp) {
        final dt = ts.toDate();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          return true;
        }
      }

      final timeStr = data['time']?.toString() ?? '';
      if (timeStr.contains(todayStr)) return true;

      // If no date info at all, assume it's recent and include it
      if (dateStr.isEmpty && ts == null) return true;

      return false;
    }).toList();

    _processAttendanceDocs(filtered);
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
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';
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

    final prevIn = _clockInTime;
    final prevOut = _clockOutTime;

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

    final newIn = latestInTime ?? '--:--';
    final newOut = latestOutTime ?? '--:--';

    if (prevIn == newIn && prevOut == newOut) return; // No change

    setState(() {
      _isClockedIn = clockedInState;
      _clockInTime = newIn;
      _clockOutTime = newOut;
      _rawClockInDateTime = parsedInDateTime;
      _isLoadingAttendance = false;
    });

    // Snackbar for admin updates
    if (prevIn != '--:--' || prevOut != '--:--') {
      if (prevOut == '--:--' && newOut != '--:--') {
        _showSnack('📝 Admin recorded your clock OUT at $newOut');
      } else if (prevOut != '--:--' && newOut != '--:--' && prevOut != newOut) {
        _showSnack('📝 Admin updated your clock OUT to $newOut');
      }
    }

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
    _attendanceSubCamel?.cancel();
    _attendanceSubDocId?.cancel();
    _employeeSub?.cancel();
    _connectivitySub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _sessionWatchdog?.cancel();
    _attendancePollTimer?.cancel();

    SecurityHardeningService.instance.disableSecureScreen();
    super.dispose();
  }

  Future<void> _loadEmployeePhoto() async {
    if (_isDemo) return;
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
        if (_photoUrl != url) setState(() => _photoUrl = url);
      }
    } catch (_) {}
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

  Future<void> loadTodayAttendance() async {
    if (_isDemo) return;
    await _loadTodayAttendance();
  }

  Future<void> loadPayslipAmount() async => _loadPayslipAmount();

  Future<void> refreshAll() async {
    _recordUserActivity();
    if (_isDemo) {
      setState(() {
        _isLoadingAttendance = true;
        _checkingLocation = true;
      });
      await Future.delayed(_demoSkeletonDuration);
      if (!mounted) return;
      setState(() {
        _isLoadingAttendance = false;
        _checkingLocation = false;
      });
      return;
    }
    await _checkNetworkOnEntry();
    await _loadTodayAttendance();
    await _loadEmployeePhoto();
    await _refreshLocation();
  }

  // 🆕 Updated multi-query logic (removed strict 'date' filter)
  Future<void> _loadTodayAttendance() async {
    if (_isDemo) return;
    if (!mounted) return;

    final empId = _employeeId;
    final docId = _employeeDocId;
    if (empId == null) return;

    for (int attempt = 0; attempt < _maxAttendanceRetries; attempt++) {
      try {
        final allDocs = <QueryDocumentSnapshot>[];
        final seenIds = <String>{};

        // Q1: snake_case employee_id
        try {
          final snap1 = await FirebaseFirestore.instance
              .collection('attendance_logs')
              .where('employee_id', isEqualTo: empId)
              .get()
              .timeout(const Duration(seconds: 10));
          for (final d in snap1.docs) {
            if (seenIds.add(d.id)) allDocs.add(d);
          }
        } catch (e) {
          _secureLog('⚠️ Q1 failed: $e');
        }

        // Q2: camelCase employeeId (badge ID)
        try {
          final snap2 = await FirebaseFirestore.instance
              .collection('attendance_logs')
              .where('employeeId', isEqualTo: empId)
              .get()
              .timeout(const Duration(seconds: 10));
          for (final d in snap2.docs) {
            if (seenIds.add(d.id)) allDocs.add(d);
          }
        } catch (e) {
          _secureLog('⚠️ Q2 failed: $e');
        }

        // Q3: camelCase employeeId (doc ID)
        if (docId != null && docId != empId) {
          try {
            final snap3 = await FirebaseFirestore.instance
                .collection('attendance_logs')
                .where('employeeId', isEqualTo: docId)
                .get()
                .timeout(const Duration(seconds: 10));
            for (final d in snap3.docs) {
              if (seenIds.add(d.id)) allDocs.add(d);
            }
          } catch (e) {
            _secureLog('⚠️ Q3 failed: $e');
          }
        }

        if (!mounted) return;
        _filterAndProcess(allDocs, empId, docId);
        return;
      } catch (_) {
        if (attempt < _maxAttendanceRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
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

    if (_isDemo) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _payslipAmount = DemoModeService.instance.demoPayslipAmount;
        _payslipData = null;
        _payslipLoading = false;
        _payslipError = false;
        _payslipAlreadyDownloaded = false;
      });
      return;
    }

    try {
      final employeeId = _employeeId;
      if (employeeId == null) {
        if (mounted) {
          setState(() {
            _payslipAmount = null;
            _payslipData = null;
            _payslipLoading = false;
          });
        }
        return;
      }

      final data = await _fetchPayslipFromBackend(employeeId, _payslipMonth);
      if (!mounted) return;

      setState(() {
        _payslipData = data;
        _payslipAmount = data == null ? null : _extractNetPay(data);
        _payslipLoading = false;
        _payslipError = false;
      });

      await _checkLocalPayslipCache(employeeId);

      if (_isPayslipVisible && _payslipData != null && !_payslipAlreadyDownloaded) {
        unawaited(_autoDownloadPayslip(employeeId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _payslipAmount = null;
        _payslipData = null;
        _payslipError = true;
        _payslipLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchPayslipFromBackend(String employeeId, DateTime month) async {
    if (_isDemo) return null;
    if (!_isOnline) return null;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('payslips')
          .where('employeeId', isEqualTo: employeeId)
          .where('period.year', isEqualTo: month.year)
          .where('period.month', isEqualTo: month.month)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));

      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    } catch (_) {
      return null;
    }
  }

  double? _extractNetPay(Map<String, dynamic> data) {
    final candidates = ['netPay', 'net_pay', 'netAmount', 'amount', 'totalPay'];
    for (final key in candidates) {
      final v = data[key];
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<void> _checkLocalPayslipCache(String employeeId) async {
    if (_isDemo) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = _payslipFileName(employeeId, _payslipMonth);
      final file = File('${dir.path}/payslips/$fileName');

      if (await file.exists()) {
        final stat = await file.stat();
        if (mounted) {
          setState(() {
            _payslipAlreadyDownloaded = true;
            _payslipLocalPath = file.path;
            _payslipDownloadedAt = stat.modified;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _payslipAlreadyDownloaded = false;
            _payslipLocalPath = null;
            _payslipDownloadedAt = null;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _autoDownloadPayslip(String employeeId) async {
    if (_isDemo) return;
    if (_payslipDownloading) return;
    await _downloadPayslip(showUI: false);
  }

  Future<void> _downloadPayslip({bool showUI = true}) async {
    if (_payslipDownloading) return;
    final employeeId = _employeeId;
    if (employeeId == null) {
      if (showUI) _showSnack('No employee ID', isError: true);
      return;
    }

    if (_isDemo) {
      if (showUI) setState(() => _payslipDownloading = true);
      try {
        final fakeData = Map<String, dynamic>.from(
          DemoModeService.instance.demoPayslipBreakdown,
        );
        final pdfBytes = await _generatePayslipPDF(fakeData);
        final dir = await getApplicationDocumentsDirectory();
        final payslipDir = Directory('${dir.path}/payslips');
        if (!await payslipDir.exists()) {
          await payslipDir.create(recursive: true);
        }
        final fileName = _payslipFileName(employeeId, _payslipMonth);
        final file = File('${payslipDir.path}/$fileName');
        await file.writeAsBytes(pdfBytes, flush: true);
        if (mounted) {
          setState(() {
            _payslipDownloading = false;
            _payslipAlreadyDownloaded = true;
            _payslipLocalPath = file.path;
            _payslipDownloadedAt = DateTime.now();
          });
        }
        if (showUI) {
          _showSnack('🎭 Demo payslip saved ✅');
          unawaited(_previewLocalPayslip());
        }
      } catch (e) {
        if (mounted) setState(() => _payslipDownloading = false);
        if (showUI) _showSnack('Demo download failed: $e', isError: true);
      }
      return;
    }

    if (_payslipData == null) {
      if (showUI) _showSnack('No payslip available', isError: true);
      return;
    }

    if (showUI) setState(() => _payslipDownloading = true);

    try {
      final pdfBytes = await _generatePayslipPDF(_payslipData!);
      final dir = await getApplicationDocumentsDirectory();
      final payslipDir = Directory('${dir.path}/payslips');
      if (!await payslipDir.exists()) {
        await payslipDir.create(recursive: true);
      }
      final fileName = _payslipFileName(employeeId, _payslipMonth);
      final file = File('${payslipDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes, flush: true);

      if (mounted) {
        setState(() {
          _payslipDownloading = false;
          _payslipAlreadyDownloaded = true;
          _payslipLocalPath = file.path;
          _payslipDownloadedAt = DateTime.now();
        });
      }

      unawaited(_logSecurityEvent(
        type: 'payslip_downloaded',
        severity: 'info',
        details: 'Payslip ${_payslipMonthLabel} downloaded (${pdfBytes.length} bytes)',
      ));

      if (showUI) {
        _showSnack('Payslip saved ✅');
        unawaited(_previewLocalPayslip());
      }
    } catch (e) {
      if (mounted) setState(() => _payslipDownloading = false);
      if (showUI) _showSnack('Download failed: $e', isError: true);
    }
  }

  Future<void> _previewLocalPayslip() async {
    try {
      if (_payslipLocalPath == null) {
        await _downloadPayslip();
        return;
      }
      final file = File(_payslipLocalPath!);
      if (!await file.exists()) {
        await _downloadPayslip();
        return;
      }
      await Printing.layoutPdf(
        onLayout: (_) => file.readAsBytes(),
        name: _payslipFileName(_employeeId ?? '', _payslipMonth),
      );
    } catch (e) {
      _showSnack('Cannot open payslip', isError: true);
    }
  }

  Future<void> _shareLocalPayslip() async {
    try {
      if (_payslipLocalPath == null) {
        _showSnack('Download muna', isError: true);
        return;
      }
      final file = File(_payslipLocalPath!);
      if (!await file.exists()) {
        _showSnack('File not found', isError: true);
        return;
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Payslip — $_payslipMonthLabel',
        text: 'Payslip for $_payslipMonthLabel',
      );
    } catch (e) {
      _showSnack('Cannot share payslip', isError: true);
    }
  }

  String _payslipFileName(String employeeId, DateTime month) {
    final mm = month.month.toString().padLeft(2, '0');
    return 'payslip_${employeeId}_${month.year}_$mm.pdf';
  }

  Future<Uint8List> _generatePayslipPDF(Map<String, dynamic> data) async {
    final pdf = pw.Document();
    final employeeName = _isDemo ? DemoModeService.demoEmployee.fullName : (_employee?.fullName ?? 'Employee');
    final employeeIdStr = _employeeId ?? '—';
    final period = _payslipMonthLabel;
    final netPay = _extractNetPay(data) ?? (_isDemo ? DemoModeService.instance.demoPayslipAmount : null);
    final grossPay = _numOr(data['grossPay'] ?? data['gross_pay'], 0);
    final deductions = _numOr(data['totalDeductions'] ?? data['total_deductions'] ?? data['deductions_total'], 0);
    final allowances = _numOr(data['totalAllowances'] ?? data['total_allowances'] ?? data['allowances_total'], 0);
    final generatedAt = data['generatedAt'] is Timestamp ? (data['generatedAt'] as Timestamp).toDate() : DateTime.now();

    final headerColor = PdfColors.orange;
    final headerSoft = PdfColors.orange50;
    final headerAccent = PdfColors.orange;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: headerColor, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('R.A.C.O.M.A.', style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(_isDemo ? 'DEMO Payslip (no data saved)' : 'Employee Payslip', style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                  ],
                ),
                pw.Text(period, style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          _pdfInfoTable([
            ['Employee Name', employeeName],
            ['Employee ID', employeeIdStr],
            ['Pay Period', period],
            ['Status', _isDemo ? 'DEMO (not saved)' : (data['status'] ?? 'released').toString().toUpperCase()],
            ['Generated', _formatTimestamp(generatedAt)],
          ]),
          pw.SizedBox(height: 20),
          pw.Text('Earnings Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _pdfInfoTable([
            ['Gross Pay', 'PHP ${_formatPesoNum(grossPay)}'],
            ['Allowances', '+ PHP ${_formatPesoNum(allowances)}'],
            ['Deductions', '- PHP ${_formatPesoNum(deductions)}'],
          ]),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(color: headerSoft, border: pw.Border.all(color: headerAccent, width: 2), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('NET PAY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(netPay != null ? 'PHP ${_formatPesoNum(netPay)}' : '—', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: headerAccent)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(_isDemo ? 'DEMO MODE — this payslip is NOT saved to the database.' : 'This is a system-generated payslip. No signature required.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text('Generated on ${_formatTimestamp(DateTime.now())}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
    return pdf.save();
  }

  double _numOr(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  pw.Widget _pdfInfoTable(List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const { 0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3) },
      children: rows.map((r) => pw.TableRow(
        children: [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r[0], style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800))),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(r[1], style: const pw.TextStyle(fontSize: 10))),
        ],
      )).toList(),
    );
  }

  String _formatPesoNum(double amount) {
    final wholeStr = amount.toStringAsFixed(2);
    final parts = wholeStr.split('.');
    final whole = parts[0];
    final cents = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    for (int i = 0; i < whole.length; i++) {
      final posFromEnd = whole.length - i;
      buf.write(whole[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '${buf.toString()}.$cents';
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError ? _T.red : null,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  String _formatTimestamp(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final hh = hour12.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$mm/$dd/$yyyy $hh:$min $ampm';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _payslipMonthLabel => '${_monthNames[_payslipMonth.month - 1]} ${_payslipMonth.year}';

  void _handleClockAction() {
    _recordUserActivity();
    if (_clockActionInProgress) return;

    if (_isDemo) {
      widget.onClockAction?.call();
      return;
    }

    final now = DateTime.now();
    if (_lastClockActionAt != null) {
      final elapsed = now.difference(_lastClockActionAt!).inMilliseconds;
      if (elapsed < _clockActionCooldown.inMilliseconds) return;
    }
    _lastClockActionAt = now;
    _totalClockActions++;

    if (_totalClockActions > _maxClockActionsPerSession) {
      _showSnack('Too many clock actions. Restart the app.', isError: true);
      return;
    }

    _clockActionInProgress = true;

    _validateSession(forceRefresh: true).then((valid) async {
      if (!mounted) {
        _clockActionInProgress = false;
        return;
      }
      if (!valid) {
        _clockActionInProgress = false;
        _handleForcedLogout('Session invalidated during clock action');
        return;
      }

      if (_deviceCompromised) {
        _clockActionInProgress = false;
        _showSnack('Device compromised. Action blocked.', isError: true);
        return;
      }

      if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
        _clockActionInProgress = false;
        _showSnack('Location verification failed.', isError: true);
        return;
      }

      widget.onClockAction?.call();
      _clockActionInProgress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final isOffline = _networkState == _NetworkState.offline && !_isDemo;
    final isChecking = _networkState == _NetworkState.checking && !_isDemo;
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

    if (_initError != null && !_isDemo) {
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
                const Text('Dashboard Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_initError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                          if (_isDemo) ...[
                            _buildDemoBadge(),
                            const SizedBox(height: 8),
                          ],
                          if ((_deviceCompromised || _mockLocationDetected) && !_isDemo) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_deviceCompromised)
                                  _buildBadge('UNSAFE DEVICE', Icons.warning_amber_rounded, _T.red),
                                if (_mockLocationDetected && !_deviceCompromised)
                                  _buildBadge('FAKE GPS', Icons.location_off_rounded, _T.red),
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
                          _buildSectionTitle('Location Status', tc: tc, trailing: _buildGpsTag(tc)),
                          const SizedBox(height: 12),
                          _buildLocationCard(tc),
                          const SizedBox(height: 24),
                          _buildSectionTitle('Shortcuts', tc: tc),
                          const SizedBox(height: 12),
                          _buildShortcutsGrid(tc),
                          if (_isPayslipVisible) ...[
                            const SizedBox(height: 24),
                            _buildSectionTitle('Recent Payslip', tc: tc, viewAll: true, onViewAllTap: () => _safeSwitchTab(_kTabLogs)),
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

  Widget _buildDemoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: _T.demoGradient,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: _T.demoPurple.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.science_rounded, color: Colors.white, size: 13),
          SizedBox(width: 6),
          Text(
            'DEMO MODE — No data is saved',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ],
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
                child: const Icon(Icons.lock_outline_rounded, color: Colors.black, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('R.A.C.O.M.A.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text('Session hidden for your privacy', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
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
                colors: [Color(0xFFFF8A00), Color(0xFFFA6A00), Color(0xFFF54900)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.15),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 12)),
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('No Connection', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(_networkErrorMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 13, height: 1.5)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try Again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
    final name = _employee?.firstName ?? widget.initialEmployee?.firstName ?? 'Employee';
    final lastName = _employee?.lastName ?? widget.initialEmployee?.lastName ?? '';
    final photo = _photoUrl ?? _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;

    void goToProfile() {
      _recordUserActivity();
      _safeSwitchTab(_kTabProfile);
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
                style: TextStyle(fontSize: 10, color: tc.textGray, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(_isDemo ? 'Demo Dashboard' : 'Employee Dashboard', style: TextStyle(fontSize: 14, color: tc.textBlack, fontWeight: FontWeight.w500)),
                  if (_isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _T.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.orange),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science_rounded, size: 10, color: _T.orange),
                          SizedBox(width: 4),
                          Text('DEMO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _T.orange, letterSpacing: 0.4)),
                        ],
                      ),
                    ),
                  ],
                  if (_wfhAccess && !_isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.green),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_work_rounded, size: 10, color: _T.greenDeep),
                          SizedBox(width: 4),
                          Text('WFH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _T.greenDeep, letterSpacing: 0.4)),
                        ],
                      ),
                    ),
                  ],
                  if (_isDriver && !_wfhAccess && !_isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF3B82F6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping_rounded, size: 10, color: Color(0xFF1E40AF)),
                          SizedBox(width: 4),
                          Text('DRIVER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF), letterSpacing: 0.4)),
                        ],
                      ),
                    ),
                  ],
                  if (_networkState == _NetworkState.offline && !_isDemo) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.red),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 10, color: Color(0xFF991B1B)),
                          SizedBox(width: 4),
                          Text('OFFLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF991B1B), letterSpacing: 0.4)),
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
    if (_isDemo) {
      return Container(
        color: _T.orange,
        alignment: Alignment.center,
        child: const Icon(Icons.science_rounded, color: Colors.white, size: 22),
      );
    }

    final hasPhoto = photo != null && photo.isNotEmpty && photo != '—';
    if (!hasPhoto) return _avatarFallback(name);

    if (photo!.startsWith('data:image')) {
      try {
        final b64 = photo.split(',').last;
        final bytes = base64Decode(b64);
        return Image.memory(bytes, width: 45, height: 45, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low, errorBuilder: (_, __, ___) => _avatarFallback(name));
      } catch (_) {
        return _avatarFallback(name);
      }
    }
    if (photo.startsWith('http')) {
      return Image.network(photo, width: 45, height: 45, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.low, errorBuilder: (_, __, ___) => _avatarFallback(name));
    }
    return _avatarFallback(name);
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _T.orange,
      alignment: Alignment.center,
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
    );
  }

  Widget _buildStatusBanner() {
    final String statusText;
    final String subtitle;
    final Color accentColor;

    if (_isDemo) {
      statusText = 'in demo mode.';
      subtitle = 'All checks bypassed. No data will be saved.';
      accentColor = _T.orange;
    } else if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
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
      subtitle = 'Work-from-home access is active.';
      accentColor = _T.green;
    } else if (_isDriverMode) {
      statusText = 'on field duty.';
      subtitle = 'Driver/Rider mode — clock in from anywhere.';
      accentColor = const Color(0xFF3B82F6);
    } else if (_isInRange) {
      statusText = 'clocked out.';
      subtitle = 'You are inside the authorized zone.';
      accentColor = _T.orange;
    } else {
      statusText = 'out of range.';
      subtitle = 'Clock in from the authorized zone or ask admin for WFH access.';
      accentColor = _T.red;
    }

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFA500), width: 1.15),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), offset: const Offset(0, 25), blurRadius: 50, spreadRadius: -12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset('assets/images/imagewithfallback.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1A1A1A))),
            ),
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 32, 25, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  softWrap: true,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: Colors.white, height: 1.15),
                    children: [
                      const TextSpan(text: 'You are currently\n'),
                      TextSpan(text: statusText, style: TextStyle(color: accentColor, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Spacer(),
                Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFFA1A1AA), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(_ThemeColors tc) {
    final clocked = _isClockedIn;
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
                time: _clockInTime,
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
                time: _clockOutTime,
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
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? tc.textBlack : inactiveLabelColor)),
            const SizedBox(height: 2),
            Text(
              locked ? 'Locked' : time,
              style: TextStyle(
                fontSize: 11,
                color: locked ? _T.red : (active ? tc.textMuted : inactiveTimeColor),
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
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: tc.textBlack)),
        if (trailing != null) trailing,
        if (viewAll)
          GestureDetector(
            onTap: () {
              _recordUserActivity();
              onViewAllTap?.call();
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text('View All', style: TextStyle(fontSize: 12, color: _T.orange, fontWeight: FontWeight.w500)),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsTag(_ThemeColors tc) {
    if (_isDemo) {
      return Row(
        children: [
          const Icon(Icons.science_rounded, size: 12, color: _T.orange),
          const SizedBox(width: 4),
          Text('Demo Mode', style: TextStyle(fontSize: 12, color: _T.orange, fontWeight: FontWeight.w500)),
        ],
      );
    }

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
        : (_isDriverMode ? Icons.local_shipping_rounded : Icons.near_me_rounded)));
    final color = _networkState == _NetworkState.offline ? _T.red : tc.textBlack;

    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w400)),
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

    if (_isDemo) {
      dotColor = _T.orange;
      borderColor = _T.orange;
      gradientStart = _T.orange;
      gradientEnd = const Color(0xFFF54900);
      leadingIcon = Icons.science_rounded;
      title = 'Demo Mode';
      subtitle = 'Location checks bypassed';
      subtitleColor = _T.orange;
    } else if (_mockLocationDetected && !_wfhAccess && !_isDriver) {
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
      subtitle = _distanceMeters != null ? '${_distanceMeters!.toStringAsFixed(0)}m from office' : 'You are not in the work zone';
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
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [gradientStart, gradientEnd]),
                  shape: BoxShape.circle,
                ),
                child: _checkingLocation && _networkState != _NetworkState.offline && !_isDemo
                    ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : Icon(leadingIcon, color: Colors.white, size: 22),
              ),
              if ((!_checkingLocation || _networkState == _NetworkState.offline || _isDemo))
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
                Text(title, style: TextStyle(fontSize: 14, color: tc.textBlack, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: subtitleColor, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, maxLines: 2),
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
        _safeSwitchTab(_kTabLogs);
      }),
      (Icons.calendar_month_rounded, 'Leaves', _T.orangeBorder, () {
        _recordUserActivity();
        _safeSwitchTab(_kTabLeaves);
      }),
      (Icons.person_rounded, 'Profile', _T.orange, () {
        _recordUserActivity();
        _safeSwitchTab(_kTabProfile);
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
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
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
                    Text(item.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: item.$3)),
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
    final hasPayslip = _payslipAmount != null;
    final isDownloading = _payslipDownloading;
    final isDownloaded = _payslipAlreadyDownloaded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: _T.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _T.orange.withValues(alpha: 0.2), width: 1.15),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isDemo ? 'Demo Payslip' : _payslipMonthLabel, style: TextStyle(fontSize: 14, color: tc.textBlack, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    _buildPayslipAmountText(tc),
                    if (isDownloaded && _payslipDownloadedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Downloaded ${_formatTimestamp(_payslipDownloadedAt!)}',
                        style: TextStyle(fontSize: 10, color: tc.textMuted, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasPayslip && !isDownloading && !isDownloaded)
                GestureDetector(
                  onTap: () {
                    _recordUserActivity();
                    _downloadPayslip();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: _T.orange.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.download_rounded, color: _T.orange, size: 20),
                  ),
                )
              else if (isDownloading)
                const SizedBox(width: 32, height: 32, child: Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator(strokeWidth: 2.5, color: _T.orange)))
              else if (isDownloaded)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _recordUserActivity();
                          _shareLocalPayslip();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: _T.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.share_rounded, color: _T.orange, size: 18),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          _recordUserActivity();
                          _previewLocalPayslip();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: _T.orange, shape: BoxShape.circle),
                          child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  )
                else if (_payslipError)
                    GestureDetector(
                      onTap: () {
                        _recordUserActivity();
                        _loadPayslipAmount();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(Icons.refresh_rounded, color: _T.orange, size: 20),
                    ),
            ],
          ),
          if (!hasPayslip && !_payslipLoading && !_payslipError) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: tc.textMuted.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: tc.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No payslip yet for $_payslipMonthLabel. It will be available on the 1st day of next month.',
                      style: TextStyle(fontSize: 11, color: tc.textMuted, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayslipAmountText(_ThemeColors tc) {
    if (_payslipLoading) {
      return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _T.orange));
    }
    if (_payslipError) {
      return const Text('Unable to load payslip right now', style: TextStyle(fontSize: 12, color: Colors.redAccent));
    }
    if (_payslipAmount == null) {
      return Text('No payslip available yet', style: TextStyle(fontSize: 12, color: tc.textGray));
    }
    return Text(
      _isDemo ? 'Amount: ${_formatPeso(_payslipAmount!)} (DEMO)' : 'Amount: ${_formatPeso(_payslipAmount!)}',
      style: TextStyle(
        fontSize: 12,
        color: _isDemo ? _T.orange : tc.textGray,
        fontWeight: _isDemo ? FontWeight.w700 : FontWeight.w400,
      ),
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
              BoxShadow(color: const Color(0xFFFF8A00).withValues(alpha: 0.15), blurRadius: 40, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isDemo ? 'Clock Out (DEMO)' : 'Clock Out (Tap to proceed)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.timer_rounded, size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text('Duty Time: $_elapsedDuration', style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
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
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 1.1), 90, glowPaint);
  }

  @override
  bool shouldRepaint(_SilkPainter old) => false;
}