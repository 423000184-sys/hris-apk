// lib/screens/clock_screen.dart
// v1.2: 🎭 DEMO MODE now shows the SAME skeleton loading screen as normal mode.
//       Skeleton appears briefly (900ms), then fades into demo UI.
// v1.1: 🎨 Demo mode now uses ORANGE (matches app theme)
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/geofence_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/presence_monitor_service.dart';
import '../services/device_info_service.dart';
import '../services/admin_notification_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/demo_mode_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';
import 'login_screen.dart';

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get navBg => isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get navBorder => const Color(0xFF27272A);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get textOnDark => Colors.white;
  Color get cardFill =>
      isDark ? const Color(0xFF1F1F23) : Colors.white.withValues(alpha: 0.5);
  Color get cardBorder => const Color(0xFFFFA500);
  Color get avatarBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get avatarBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

enum _NetworkState { online, offline, checking }

class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final VoidCallback? onRefresh;
  final VoidCallback? onClockIn;
  final VoidCallback? onClockOut;
  final VoidCallback? onShortcutHome;
  final VoidCallback? onShortcutProfile;
  final VoidCallback? onShortcutLeaves;
  final ValueChanged<int>? onNavTap;
  final bool initialInRange;
  final bool initialWfhAccess;

  const ClockScreen({
    super.key,
    this.initialEmployee,
    this.onBack,
    this.onContinue,
    this.onRefresh,
    this.onClockIn,
    this.onClockOut,
    this.onShortcutHome,
    this.onShortcutProfile,
    this.onShortcutLeaves,
    this.onNavTap,
    this.initialInRange = false,
    this.initialWfhAccess = false,
  });

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> with WidgetsBindingObserver {
  static const _orange = Color(0xFFFF8A00);
  static const _orangeMid = Color(0xFFFA6A00);
  static const _orangeDeep = Color(0xFFF54900);
  static const _orangeBorder = Color(0xFFFFA500);
  static const _green = Color(0xFFC4FF0A);
  static const _greenDeep = Color(0xFF166534);
  static const _red = Color(0xFFFF0000);

  // 🎨 DEMO — ORANGE (matches app theme)
  static const _demoAccent = Color(0xFFFF8A00);
  static const _demoAccentMid = Color(0xFFFA6A00);
  static const _demoAccentDark = Color(0xFFF54900);

  static const _orangeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_orange, _orangeMid, _orangeDeep],
    stops: [0.0, 0.5, 1.0],
  );

  static const String _logoAsset = 'assets/images/logo.png';

  // 🆕 Demo skeleton display duration
  static const Duration _demoSkeletonDuration = Duration(milliseconds: 900);
  // 🆕 Normal mode initial skeleton display duration
  static const Duration _normalSkeletonDuration = Duration(milliseconds: 600);

  late bool _isInRange;
  late bool _wfhAccess;
  bool _checkingGeofence = false;
  int _activeNavIndex = 0;

  DateTime? _clockInTime;
  DateTime? _clockOutTime;
  bool _saving = false;
  bool _clockActionInProgress = false;

  // 🆕 Initial loading flag for skeleton
  bool _isInitialLoading = true;

  Employee? _liveEmployee;

  String _deviceModel = 'Unknown Device';

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;

  StreamSubscription<QuerySnapshot>? _attendanceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  StreamSubscription<bool>? _connectivitySub;

  static const Duration _clockActionCooldown = Duration(seconds: 5);
  static const Duration _clockSessionWatchdog = Duration(minutes: 30);
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const Duration _maxInactivityTime = Duration(minutes: 30);
  static const int _maxSecurityLogsPerMinute = 20;
  static const int _maxAttendanceRetries = 3;
  static const int _maxClockActionsPerSession = 30;

  late final String _sessionNonce;
  String? _employeeDataHash;
  DateTime? _lastClockActionAt;
  DateTime? _lastUserActivityAt;
  int _totalClockActions = 0;
  Timer? _sessionWatchdog;
  Timer? _heartbeatTimer;
  bool _sessionValidated = false;
  bool _loggedOut = false;
  bool _mockLocationDetected = false;

  bool? _cachedSessionValid;
  DateTime? _sessionCacheTime;

  final Map<String, DateTime> _recentSecurityLogs = {};

  Duration _timeOffset = Duration.zero;
  DateTime? _lastTimeSyncAt;

  bool _presenceStarted = false;
  bool _sessionListenerStarted = false;

  bool get _isDemo => DemoModeService.instance.isEnabled;

  Employee? get _employee => _liveEmployee ?? widget.initialEmployee;

  String? get _employeeId {
    if (_isDemo) return DemoModeService.demoEmployee.employeeId;

    final id = _employee?.employeeId;
    if (id != null && id.isNotEmpty) return id;
    final fallback = _employee?.id;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String? get _employeeDocId {
    if (_isDemo) return DemoModeService.demoEmployee.id;

    final id = _employee?.id;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  bool get _canClock {
    if (_isDemo) return true;

    return (_isInRange || _wfhAccess) &&
        _networkState == _NetworkState.online;
  }

  bool get _isWfhMode => _wfhAccess && !_isInRange;
  bool get _isOnline => _networkState == _NetworkState.online;

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  DateTime get _adjustedNow => DateTime.now().add(_timeOffset);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — ipakita ang skeleton sa simula
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] ClockScreen in DEMO MODE');
      debugPrint('   • Skipping all DB listeners');
      debugPrint('   • Orange theme applied');
      debugPrint('   • Skeleton shown for ${_demoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════════════');

      _isInRange = true;
      _wfhAccess = true;
      _sessionValidated = true;
      _checkingGeofence = false;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(
          const AssetImage(_logoAsset),
          context,
          onError: (e, st) => debugPrint('⚠️ Logo precache failed: $e'),
        );
      });

      try {
        _connectivitySub =
            ConnectivityService.instance.onStatusChange.listen((online) {
              if (!mounted) return;
              setState(() {
                _networkState =
                online ? _NetworkState.online : _NetworkState.offline;
              });
            });
      } catch (e) {
        debugPrint('⚠️ connectivity listen failed: $e');
      }

      setState(() => _networkState = _NetworkState.online);

      // 🆕 Hide skeleton after short delay
      Future.delayed(_demoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    // ═══════════════════════════════════════════════════════════
    // NORMAL MODE
    // ═══════════════════════════════════════════════════════════
    _isInRange = widget.initialInRange;
    _wfhAccess = widget.initialWfhAccess || _readWfhFromEmployee();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(
        const AssetImage(_logoAsset),
        context,
        onError: (e, st) => debugPrint('⚠️ Logo precache failed: $e'),
      );
    });

    _startAttendanceStream();
    _startEmployeeListener();
    _startSessionRevocationListener();
    _loadDeviceModel();
    _startSecurityMonitoring();
    _syncServerTime();

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint('🌐 [ClockScreen] connectivity → online=$online');

            if (!online) {
              if (_networkState == _NetworkState.offline) return;
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
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
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] connectivity listen failed: $e');
    }

    _checkNetworkOnEntry();
    _startPresenceIfNeeded();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _refreshGeofence(silent: true);
      await Future.delayed(const Duration(seconds: 1));
      await OfflineAttendanceService.instance.dumpAll();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) debugGeofenceCheck();
      });
    });

    // 🆕 Hide initial skeleton after normal load window
    Future.delayed(_normalSkeletonDuration, () {
      if (!mounted) return;
      setState(() => _isInitialLoading = false);
    });
  }

  Future<void> debugGeofenceCheck() async {
    if (_isDemo) return;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔍 [ClockScreen][DEBUG] Manual geofence check');
    debugPrint('   employee.id          = ${_employee?.id ?? "null"}');
    debugPrint('   employee.employeeId  = ${_employee?.employeeId ?? "null"}');
    debugPrint('═══════════════════════════════════════════');

    try {
      debugPrint('Test 1: GeofenceService.checkGeofence()');
      final r1 = await GeofenceService.instance.checkGeofence();
      debugPrint('   → inside=${r1.isInside}');
      debugPrint('   → status=${r1.status}');
      debugPrint('   → distance=${r1.distanceMeters}m');
      debugPrint('   → radius=${r1.radiusUsed}m');
      debugPrint('   → matched=${r1.matchedLocationName}');

      final docId = _employeeDocId;
      if (docId != null && docId.isNotEmpty) {
        debugPrint('Test 2: checkGeofenceForEmployee(docId=$docId)');
        try {
          final r2 = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: docId);
          debugPrint('   → inside=${r2.isInside}');
          debugPrint('   → distance=${r2.distanceMeters}m');
        } catch (e) {
          debugPrint('   → ERROR: $e');
        }
      }

      final empId = _employeeId;
      if (empId != null && empId != docId && empId.isNotEmpty) {
        debugPrint('Test 3: checkGeofenceForEmployee(empId=$empId)');
        try {
          final r3 = await GeofenceService.instance
              .checkGeofenceForEmployee(employeeId: empId);
          debugPrint('   → inside=${r3.isInside}');
          debugPrint('   → distance=${r3.distanceMeters}m');
        } catch (e) {
          debugPrint('   → ERROR: $e');
        }
      }
    } catch (e, st) {
      debugPrint('❌ [DEBUG] Failed: $e');
      debugPrint('$st');
    }
    debugPrint('═══════════════════════════════════════════');
  }

  void _startPresenceIfNeeded() {
    if (_isDemo) return;

    if (_presenceStarted) return;
    final emp = _employee;
    if (emp == null) return;
    _presenceStarted = true;
    try {
      PresenceMonitorService.instance.start(employee: emp);
    } catch (e) {
      debugPrint('⚠️ PresenceMonitor start failed: $e');
    }
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _generateTransactionId(String type) {
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch;
    final rand = math.Random.secure();
    final randHex = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'CLK-${type.toUpperCase()}-$ts-$randHex';
  }

  String _hashEmployeeData(Employee emp) {
    final data = '${emp.id}|${emp.employeeId}|${emp.email}|'
        '${emp.position}|${emp.department}|${emp.wfhAccess}';
    return sha256.convert(utf8.encode(data)).toString();
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Skipping security log: $type');
      return;
    }

    try {
      if (!_isOnline) return;
      final empId = _employeeId;
      if (empId == null) return;

      final key = '$type|$details';
      final now = DateTime.now();
      final lastLog = _recentSecurityLogs[key];
      if (lastLog != null && now.difference(lastLog).inSeconds < 60) {
        return;
      }

      _recentSecurityLogs
          .removeWhere((_, v) => now.difference(v).inMinutes > 1);
      if (_recentSecurityLogs.length >= _maxSecurityLogsPerMinute) {
        debugPrint('🚦 [ClockScreen] Security log rate limit hit');
        return;
      }
      _recentSecurityLogs[key] = now;

      await FirebaseFirestore.instance
          .collection('security_events')
          .add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': empId,
        'employeeName': _employee?.fullName ?? 'Unknown',
        'sessionNonce': _sessionNonce,
        'device': _deviceModel,
        'mockLocation': _mockLocationDetected,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'clock_screen',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] security log error: $e');
    }
  }

  void _recordUserActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  Future<void> _syncServerTime() async {
    if (_isDemo) return;

    try {
      final ref = FirebaseFirestore.instance
          .collection('_time_sync')
          .doc('ping');
      final before = DateTime.now();
      await ref
          .set({'ping': FieldValue.serverTimestamp()}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
      final snap = await ref.get().timeout(const Duration(seconds: 8));
      final after = DateTime.now();

      final serverTs = snap.data()?['ping'] as Timestamp?;
      if (serverTs == null) return;

      final rtt = after.difference(before);
      final serverTime = serverTs.toDate().add(rtt ~/ 2);
      _timeOffset = serverTime.difference(after);
      _lastTimeSyncAt = DateTime.now();

      debugPrint('⏰ [ClockScreen] Time offset: ${_timeOffset.inSeconds}s');

      if (_timeOffset.abs() > const Duration(minutes: 5)) {
        _logSecurityEvent(
          type: 'time_manipulation_detected',
          severity: 'high',
          details: 'Device time offset: ${_timeOffset.inMinutes} minutes',
        );
      }
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] Time sync failed: $e');
    }
  }

  Future<void> _forceLogout(String reason) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Ignoring force logout: $reason');
      return;
    }

    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    debugPrint('🚨 [ClockScreen] Forced logout: $reason');

    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    _sessionSub?.cancel();
    _sessionWatchdog?.cancel();
    _heartbeatTimer?.cancel();
    _overlayDelayTimer?.cancel();

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fp_preauth_employee_id');
      await prefs.remove('fp_preauth_time');
      await prefs.remove('fp_preauth_nonce');
    } catch (_) {}

    await _logSecurityEvent(
      type: 'clock_forced_logout',
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

  Future<bool> _validateSession({bool forceRefresh = false}) async {
    if (_isDemo) return true;

    if (!forceRefresh &&
        _cachedSessionValid != null &&
        _sessionCacheTime != null &&
        DateTime.now().difference(_sessionCacheTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }

    try {
      final valid = await SecurityService.instance
          .isSessionValid()
          .timeout(const Duration(seconds: 5));
      if (!valid) {
        debugPrint('🚨 [ClockScreen] Session INVALID');
        await _logSecurityEvent(
          type: 'clock_session_invalid',
          severity: 'high',
          details: 'Session expired or invalid',
        );
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      final sessionEmpId =
      await SecurityService.instance.getCurrentEmployeeId();
      final currentDocId = _employee?.id;
      final currentEmpId = _employee?.employeeId;

      final sessionMatches = sessionEmpId == null ||
          sessionEmpId.isEmpty ||
          (currentDocId != null && sessionEmpId == currentDocId) ||
          (currentEmpId != null && sessionEmpId == currentEmpId);

      if (!sessionMatches) {
        debugPrint('🚨 [ClockScreen] Employee MISMATCH — '
            'session=$sessionEmpId, docId=$currentDocId, empId=$currentEmpId');
        await _logSecurityEvent(
          type: 'clock_session_mismatch',
          severity: 'critical',
          details:
          'Session ($sessionEmpId) != clock ($currentDocId/$currentEmpId)',
        );
        _cachedSessionValid = false;
        _sessionCacheTime = DateTime.now();
        return false;
      }

      _cachedSessionValid = true;
      _sessionCacheTime = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] Session validation error: $e');
      _cachedSessionValid = true;
      _sessionCacheTime = DateTime.now();
      return true;
    }
  }

  void _startSessionRevocationListener() {
    if (_isDemo) return;

    if (_sessionListenerStarted) return;
    final empId = _employeeDocId;
    if (empId == null || empId.isEmpty) return;

    _sessionListenerStarted = true;
    _sessionSub?.cancel();
    _sessionSub = FirebaseFirestore.instance
        .collection('sessions')
        .doc(empId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;

        final revoked = data['revoked'] == true;
        final serverNonce = data['sessionNonce']?.toString();
        final expiresAt = data['expiresAt'] as Timestamp?;

        if (revoked) {
          _forceLogout('Session revoked by admin');
          return;
        }

        if (serverNonce != null &&
            serverNonce.isNotEmpty &&
            serverNonce != _sessionNonce) {
          _forceLogout('Login detected on another device');
          return;
        }

        if (expiresAt != null &&
            expiresAt.toDate().isBefore(DateTime.now())) {
          _forceLogout('Session expired');
        }
      },
      onError: (e) => debugPrint('Session listener error: $e'),
    );
  }

  void _startSecurityMonitoring() {
    if (_isDemo) return;

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

    _sessionWatchdog?.cancel();
    _sessionWatchdog = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;

      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _maxInactivityTime) {
        await _forceLogout('Inactivity timeout (${idle.inMinutes}m)');
      }
    });

    Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted || _loggedOut) return;
      _syncServerTime();
    });

    _validateSession(forceRefresh: true).then((valid) {
      if (mounted && _sessionValidated != valid) {
        setState(() => _sessionValidated = valid);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDemo) return;

    if (state == AppLifecycleState.resumed) {
      _recordUserActivity();
      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) {
          _forceLogout('Session invalid on resume');
        }
      });
    }
  }

  Future<void> _checkNetworkOnEntry() async {
    if (!mounted) return;

    if (_isDemo) {
      setState(() => _networkState = _NetworkState.online);
      return;
    }

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
      _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _networkState == _NetworkState.offline) {
          setState(() => _showOfflineOverlay = true);
        }
      });
      return;
    }

    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted) return;

    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
    });

    await _checkNetworkOnEntry();

    if (_networkState == _NetworkState.online && mounted && !_isDemo) {
      try {
        await _reloadAttendanceOnce();
        await _reloadEmployeeOnce();
        await _refreshGeofence(silent: true);
      } catch (e) {
        debugPrint('⚠️ Refresh after reconnect failed: $e');
      }
    }
  }

  Future<void> _loadDeviceModel() async {
    if (_isDemo) {
      if (mounted) setState(() => _deviceModel = 'Demo Device');
      return;
    }

    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (!mounted) return;
      setState(() => _deviceModel = model);
      debugPrint('📱 [ClockScreen] Device model: $model');
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] Device model load failed: $e');
    }
  }

  bool _readWfhFromEmployee() {
    final emp = _employee;
    if (emp == null) return false;
    try {
      final dynamic v = (emp as dynamic).wfhAccess;
      if (v is bool) return v;
      if (v != null) return v.toString().toLowerCase() == 'true';
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    _sessionSub?.cancel();
    _connectivitySub?.cancel();
    _overlayDelayTimer?.cancel();
    _sessionWatchdog?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime t) {
    final h24 = t.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final m = t.minute.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:$m $period';
  }

  String get _clockInDisplay =>
      _clockInTime != null ? _formatTime(_clockInTime!) : '--:--';
  String get _clockOutDisplay =>
      _clockOutTime != null ? _formatTime(_clockOutTime!) : '--:--';

  String get _todayStr {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  String _deviceName() {
    if (_isDemo) return 'Demo Device';
    if (_deviceModel.isNotEmpty && _deviceModel != 'Unknown Device') {
      return _deviceModel;
    }
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android App';
      if (Platform.isIOS) return 'iOS App';
      if (Platform.isWindows) return 'Windows App';
      if (Platform.isMacOS) return 'macOS App';
      if (Platform.isLinux) return 'Linux App';
    } catch (_) {}
    return defaultTargetPlatform.name;
  }

  String _computeZoneType() {
    if (_isDemo) return 'inside';

    final role = (_employee?.position ?? '').toLowerCase();
    final dept = (_employee?.department ?? '').toLowerCase();

    final isDriver = role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider');
    if (isDriver) return 'driver';
    if (_isInRange) return 'inside';
    if (_wfhAccess) return 'wfh';
    return 'outside';
  }

  String _fallbackLocationLabel(String zoneType) {
    switch (zoneType) {
      case 'wfh':
        return 'Work From Home';
      case 'driver':
        return 'On the Road (Driver)';
      case 'inside':
        return 'Office Zone';
      case 'outside':
        return 'Outside Zone';
      default:
        return zoneType;
    }
  }

  Future<GeofenceResult?> _checkGeofenceWithFallback() async {
    if (_isDemo) return null;

    final docId = _employeeDocId;
    final empId = _employeeId;

    GeofenceResult? result;
    Exception? lastError;

    if (docId != null && docId.isNotEmpty) {
      try {
        result = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: docId)
            .timeout(const Duration(seconds: 15));
        debugPrint('✅ [ClockScreen][Geo] OK via docId=$docId');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [ClockScreen][Geo] Failed via docId: $e');
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
        debugPrint('✅ [ClockScreen][Geo] OK via empId=$empId');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [ClockScreen][Geo] Failed via empId: $e');
      }
    }

    if (result == null) {
      try {
        result = await GeofenceService.instance
            .checkGeofence()
            .timeout(const Duration(seconds: 12));
        debugPrint('✅ [ClockScreen][Geo] OK (basic check)');
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ [ClockScreen][Geo] Failed (basic): $e');
      }
    }

    if (result == null) {
      debugPrint('❌ [ClockScreen][Geo] ALL attempts failed: $lastError');
    }

    return result;
  }

  Future<void> _refreshGeofence({bool silent = false}) async {
    if (_isDemo) {
      if (mounted) {
        setState(() {
          _isInRange = true;
          _wfhAccess = true;
          _mockLocationDetected = false;
          _checkingGeofence = false;
        });
      }
      return;
    }

    if (_checkingGeofence) return;
    if (mounted) setState(() => _checkingGeofence = true);

    GeofenceService.instance.invalidateCache();

    try {
      debugPrint('📍 [ClockScreen][Geo] Refreshing — '
          'docId=${_employeeDocId ?? "null"} '
          'empId=${_employeeId ?? "null"}');

      final result = await _checkGeofenceWithFallback();

      if (!mounted) return;

      if (result == null) {
        setState(() => _checkingGeofence = false);
        if (!silent) {
          _showSnack(
            '⚠️ Unable to verify location. Please check GPS and internet.',
          );
        }
        return;
      }

      final inside = result.isInside ||
          result.status == GeofenceStatus.insideWithTolerance;
      final distance = result.distanceMeters;

      bool mockDetected = false;
      try {
        final dynamic r = result;
        final dynamic mock = (r as dynamic).isMockLocation;
        if (mock is bool) mockDetected = mock;
      } catch (_) {}

      if (mockDetected && !_mockLocationDetected) {
        _logSecurityEvent(
          type: 'mock_location_detected',
          severity: 'critical',
          details: 'Mock location enabled during geofence check',
        );
      }

      debugPrint('📍 [ClockScreen][Geo] Result:');
      debugPrint('   inside   = $inside');
      debugPrint('   distance = ${distance}m');
      debugPrint('   radius   = ${result.radiusUsed}m');
      debugPrint('   status   = ${result.status}');
      debugPrint('   matched  = ${result.matchedLocationName}');

      final changed = inside != _isInRange;
      final mockChanged = mockDetected != _mockLocationDetected;

      if (changed || mockChanged) {
        setState(() {
          _isInRange = inside;
          _mockLocationDetected = mockDetected;
        });
      }

      if (mounted) setState(() => _checkingGeofence = false);

      if (result.usedTolerance && mounted) {
        await _logSecurityEvent(
          type: 'clock_geofence_tolerance',
          severity: 'info',
          details: 'Distance=${distance?.toStringAsFixed(0)}m, '
              'radius=${result.radiusUsed?.toStringAsFixed(0)}m',
        );
      }

      if (changed && !silent) {
        _showSnack(
          inside
              ? '✅ You are now inside the authorized zone.'
              : '📍 You are outside the authorized zone. '
              'If you are remote, ask the admin to enable WFH.',
        );
      }
    } catch (e) {
      debugPrint('❌ Geofence error: $e');
      if (!mounted) return;
      setState(() => _checkingGeofence = false);
      if (!silent) {
        _showSnack(
          '⚠️ Unable to verify location. Please check GPS and internet.',
        );
      }
    }
  }

  Future<void> _handlePullRefresh() async {
    _recordUserActivity();

    if (_isDemo) {
      await _refreshGeofence(silent: true);
      _showSnack('🎭 Demo mode — data refreshed (no DB sync)');
      return;
    }

    await OfflineAttendanceService.instance.dumpAll();
    await Future.wait([
      _refreshGeofence(silent: true),
      _reloadAttendanceOnce(),
      _reloadEmployeeOnce(),
      OfflineAttendanceService.instance.syncPending(),
      PresenceMonitorService.instance.checkNow(),
    ]);
    await OfflineAttendanceService.instance.dumpAll();
  }

  Future<void> _reloadAttendanceOnce() async {
    if (_isDemo) return;

    final empId = _employeeId;
    if (empId == null || empId.isEmpty) return;

    for (int attempt = 0; attempt < _maxAttendanceRetries; attempt++) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: empId)
            .where('date', isEqualTo: _todayStr)
            .get()
            .timeout(const Duration(seconds: 10));
        if (!mounted) return;
        _processAttendance(snap.docs);
        return;
      } catch (e) {
        debugPrint('⚠️ Attendance load attempt ${attempt + 1}: $e');
        if (attempt < _maxAttendanceRetries - 1) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
        }
      }
    }
  }

  Future<void> _reloadEmployeeOnce() async {
    if (_isDemo) return;

    final docId = _employeeDocId;
    if (docId == null || docId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null || !mounted) return;
      final updated = Employee.fromFirestore(data, docId);

      if (_liveEmployee?.id != updated.id ||
          _liveEmployee?.fullName != updated.fullName ||
          _liveEmployee?.wfhAccess != updated.wfhAccess ||
          _liveEmployee?.photoUrl != updated.photoUrl) {
        setState(() => _liveEmployee = updated);
      }
    } catch (e) {
      debugPrint('⚠️ _reloadEmployeeOnce error: $e');
    }
  }

  void _startAttendanceStream() {
    if (_isDemo) return;

    final empId = _employeeId;
    if (empId == null) return;
    _attendanceSub?.cancel();
    _attendanceSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: empId)
        .where('date', isEqualTo: _todayStr)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        _processAttendance(snap.docs);
      },
      onError: (e) => debugPrint('❌ ClockScreen stream error: $e'),
    );
  }

  void _startEmployeeListener() {
    if (_isDemo) return;

    final empDocId = _employeeDocId;
    if (empDocId == null || empDocId.isEmpty) return;
    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(empDocId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;

        final status = (data['status'] ?? '').toString().toLowerCase();
        const blocked = {'suspended', 'terminated', 'deleted', 'blocked'};
        if (blocked.contains(status)) {
          _forceLogout('Account status: $status');
          return;
        }

        Employee? updated;
        try {
          updated = Employee.fromFirestore(data, empDocId);
        } catch (e) {
          debugPrint('⚠️ Employee parse error: $e');
        }
        if (updated != null) {
          final nameChanged = _liveEmployee?.fullName != updated.fullName;
          final photoChanged = _liveEmployee?.photoUrl != updated.photoUrl;
          final posChanged = _liveEmployee?.position != updated.position;

          if (nameChanged || photoChanged || posChanged) {
            setState(() => _liveEmployee = updated);
          } else {
            _liveEmployee = updated;
          }

          _startPresenceIfNeeded();

          final newHash = _hashEmployeeData(updated);
          if (_employeeDataHash == null) {
            _employeeDataHash = newHash;
          } else if (newHash != _employeeDataHash) {
            debugPrint('🚨 [ClockScreen] Employee critical data changed');
            _logSecurityEvent(
              type: 'clock_employee_data_changed',
              severity: 'high',
              details: 'Critical employee record changed during session',
            );
            _forceLogout('Employee data changed');
            return;
          }
        }

        final raw = data['wfhAccess'];
        final enabled = raw is bool
            ? raw
            : (raw?.toString().toLowerCase() == 'true');

        if (enabled != _wfhAccess) {
          setState(() => _wfhAccess = enabled);

          _logSecurityEvent(
            type: 'clock_wfh_changed',
            severity: 'medium',
            details: 'WFH: $_wfhAccess → $enabled',
          );

          _showSnack(
            enabled
                ? '🏠 WFH access ENABLED — you can now clock in/out from anywhere.'
                : '🏢 WFH access DISABLED — you must be inside the office zone.',
          );
        }
      },
      onError: (e) =>
          debugPrint('❌ [ClockScreen] Employee listener error: $e'),
    );
  }

  DateTime? _extractDateTime(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      final parsed = _parseTimeString(rawTime.trim());
      if (parsed != null) return parsed;
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

  void _processAttendance(List<QueryDocumentSnapshot> docs) {
    DateTime? inTime;
    DateTime? outTime;

    final sorted = [...docs]..sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aTime = _extractDateTime(aData) ?? DateTime(2000);
      final bTime = _extractDateTime(bData) ?? DateTime(2000);
      return aTime.compareTo(bTime);
    });

    for (final doc in sorted) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toUpperCase();
      final parsed = _extractDateTime(data);
      if (parsed == null) continue;

      if (type == 'IN' || type == 'CLOCK_IN') {
        inTime = parsed;
        outTime = null;
      } else if (type == 'OUT' || type == 'CLOCK_OUT') {
        if (inTime != null && parsed.isAfter(inTime)) {
          outTime = parsed;
        }
      }
    }

    if (!mounted) return;

    final changed = _clockInTime?.millisecondsSinceEpoch !=
        inTime?.millisecondsSinceEpoch ||
        _clockOutTime?.millisecondsSinceEpoch !=
            outTime?.millisecondsSinceEpoch;

    if (changed) {
      setState(() {
        _clockInTime = inTime;
        _clockOutTime = outTime;
      });
    }
  }

  DateTime? _parseTimeString(String t) {
    try {
      final parts = t.split(':');
      if (parts.length < 2) return null;
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _saveAttendance({
    required String type,
    required DateTime time,
  }) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Simulating $type at $time — NO DB WRITE');
      await Future.delayed(const Duration(milliseconds: 400));
      return true;
    }

    final empId = _employeeId;
    if (empId == null || empId.isEmpty) {
      _showSnack('Unable to get employee ID. Please check your login.');
      return false;
    }

    final txnId = _generateTransactionId(type);
    debugPrint('🔒 [ClockScreen] Transaction ID: $txnId');

    final timeStr = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    final employeeName = _employee?.fullName ?? 'Unknown';
    final employeeEmail = _employee?.email ?? '';
    final deviceName = _deviceName();
    final isClockIn = type == 'IN';
    final zoneType = _computeZoneType();

    double? distanceMeters;
    String? locationName;
    if (zoneType == 'outside' || zoneType == 'inside') {
      try {
        final geo = await _checkGeofenceWithFallback();
        if (geo != null) {
          distanceMeters = geo.distanceMeters;
          locationName = geo.matchedLocationName;
        }
      } catch (e) {
        debugPrint('⚠️ distance/location capture failed: $e');
      }
    }

    final result = await OfflineAttendanceService.instance.logAttendance(
      employeeId: empId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      type: type,
      timestamp: time,
      device: deviceName,
      remarks: zoneType,
      zoneType: zoneType,
    );

    if (!result.success) {
      _showSnack('Error saving attendance. Please try again.');
      return false;
    }

    if (result.queued) {
      _showSnack('💾 Saved offline. Will auto-sync once internet returns.');
    }

    await _logSecurityEvent(
      type: isClockIn ? 'clock_in_success' : 'clock_out_success',
      severity: 'info',
      details: 'TXN=$txnId | zone=$zoneType | '
          'distance=${distanceMeters?.toStringAsFixed(0) ?? "N/A"}m',
    );

    _writeSecondaryLogs(
      empId: empId,
      employeeName: employeeName,
      timeStr: timeStr,
      isClockIn: isClockIn,
      deviceName: deviceName,
      zoneType: zoneType,
      distanceMeters: distanceMeters,
      locationName: locationName,
      txnId: txnId,
    );

    PresenceMonitorService.instance.checkNow();

    return true;
  }

  void _writeSecondaryLogs({
    required String empId,
    required String employeeName,
    required String timeStr,
    required bool isClockIn,
    required String deviceName,
    required String zoneType,
    double? distanceMeters,
    String? locationName,
    required String txnId,
  }) {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Skipping secondary logs');
      return;
    }

    final effectiveLocation =
    (locationName != null && locationName.isNotEmpty)
        ? locationName
        : _fallbackLocationLabel(zoneType);

    final activityLogPayload = <String, dynamic>{
      'type': isClockIn ? 'clock_in' : 'clock_out',
      'action': isClockIn ? 'Clocked In' : 'Clocked Out',
      'employeeId': empId,
      'employee_id': empId,
      'employee_name': employeeName,
      'time': timeStr,
      'date': _todayStr,
      'wfh': _wfhAccess,
      'in_range': _isInRange,
      'zone_type': zoneType,
      'location_name': effectiveLocation,
      'location': effectiveLocation,
      'matched_location_name': effectiveLocation,
      'device': deviceName,
      'deviceName': deviceName,
      'deviceModel': deviceName,
      'platform': deviceName,
      'transaction_id': txnId,
      'session_nonce': _sessionNonce,
      'mock_location': _mockLocationDetected,
      'device_hash': sha256
          .convert(utf8.encode(deviceName + empId))
          .toString()
          .substring(0, 16),
      'timestamp': FieldValue.serverTimestamp(),
    };

    final historyLogPayload = <String, dynamic>{
      'type': isClockIn ? 'login' : 'logout',
      'employee_id': empId,
      'employee_name': employeeName,
      'device': deviceName,
      'deviceName': deviceName,
      'wfh': _wfhAccess,
      'in_range': _isInRange,
      'zone_type': zoneType,
      'location_name': effectiveLocation,
      'location': effectiveLocation,
      'transaction_id': txnId,
      'session_nonce': _sessionNonce,
      'timestamp': FieldValue.serverTimestamp(),
    };

    FirebaseFirestore.instance
        .collection('activity logs')
        .add(activityLogPayload)
        .catchError((e) => debugPrint('⚠️ activity logs FAILED: $e'));

    FirebaseFirestore.instance
        .collection('activity_logs')
        .add(historyLogPayload)
        .catchError((e) => debugPrint('⚠️ activity_logs FAILED: $e'));

    try {
      if (isClockIn) {
        switch (zoneType) {
          case 'wfh':
            AdminNotificationService.instance.notifyWFHClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'driver':
            AdminNotificationService.instance.notifyDriverClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'outside':
            AdminNotificationService.instance.notifyGeofenceAlert(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              distanceMeters: distanceMeters ?? 0,
              action: 'clock_in',
            );
            break;
          default:
            AdminNotificationService.instance.notifyClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              wfh: _wfhAccess,
              inRange: _isInRange,
              zoneType: zoneType,
              distanceMeters: distanceMeters,
            );
        }
      } else {
        switch (zoneType) {
          case 'wfh':
            AdminNotificationService.instance.notifyWFHClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'driver':
            AdminNotificationService.instance.notifyDriverClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          default:
            AdminNotificationService.instance.notifyClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              wfh: _wfhAccess,
              inRange: _isInRange,
              zoneType: zoneType,
              distanceMeters: distanceMeters,
            );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Admin notification failed: $e');
    }
  }

  Future<void> _notifyBlockedAttempt(String action) async {
    if (_isDemo) return;

    final empId = _employeeId;
    final empName = _employee?.fullName ?? 'Unknown';
    if (empId == null || empId.isEmpty) return;

    double distance = 0;
    try {
      final geo = await _checkGeofenceWithFallback();
      distance = geo?.distanceMeters ?? 0;
    } catch (e) {
      debugPrint('⚠️ BlockedAttempt geofence check failed: $e');
    }

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    try {
      await AdminNotificationService.instance.notifyGeofenceAlertThrottled(
        employeeId: empId,
        employeeName: empName,
        timeStr: timeStr,
        distanceMeters: distance,
        action: action,
      );

      await _logSecurityEvent(
        type: 'clock_blocked_attempt',
        severity: 'medium',
        details: 'Action=$action | distance=${distance.toStringAsFixed(0)}m',
      );
    } catch (e) {
      debugPrint('❌ BlockedAttempt notify failed: $e');
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _handleContinue() {
    _recordUserActivity();
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      _handleBack();
    }
  }

  void _handleProfileTap() {
    _recordUserActivity();
    if (widget.onShortcutProfile != null) {
      widget.onShortcutProfile!();
    } else {
      _showSnack('⚠️ Profile screen is not wired up yet.');
    }
  }

  bool _checkRateLimit() {
    final now = DateTime.now();
    if (_lastClockActionAt != null) {
      final elapsed = now.difference(_lastClockActionAt!).inMilliseconds;
      if (elapsed < _clockActionCooldown.inMilliseconds) {
        debugPrint('🚦 [ClockScreen] Clock action rate-limited '
            '($elapsed ms / ${_clockActionCooldown.inMilliseconds} ms)');
        _showSnack('⚠️ Please wait a few seconds before trying again.');
        return false;
      }
    }
    _lastClockActionAt = now;
    _totalClockActions++;

    if (_totalClockActions > _maxClockActionsPerSession) {
      debugPrint('🚨 [ClockScreen] Too many clock actions');
      _logSecurityEvent(
        type: 'clock_action_abuse',
        severity: 'high',
        details: 'Total actions: $_totalClockActions',
      );
      return false;
    }
    return true;
  }

  Future<bool> _preClockCheck(String action) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Bypassing pre-clock check for $action');
      return true;
    }

    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      _showSnack('🚨 Session expired. Please log in again.');
      _forceLogout('Session invalid during $action');
      return false;
    }

    if (!_isOnline) {
      _showSnack('⚠️ No internet. Please check your connection.');
      return false;
    }

    if (_mockLocationDetected && !_wfhAccess) {
      _logSecurityEvent(
        type: 'clock_action_mock_location',
        severity: 'critical',
        details: 'Mock location during $action',
      );
      _showSnack('🚫 Fake GPS detected. Please disable mock location apps.');
      return false;
    }

    if (!_isInRange && !_wfhAccess) {
      try {
        final fresh = await _checkGeofenceWithFallback();

        if (fresh == null) {
          _logSecurityEvent(
            type: 'clock_action_geofence_error',
            severity: 'high',
            details: 'Fresh geofence returned null for $action',
          );
          _showSnack('⚠️ Unable to verify location. Please try again.');
          return false;
        }

        final stillInside = fresh.isInside ||
            fresh.status == GeofenceStatus.insideWithTolerance;

        if (!stillInside && !fresh.isExempted) {
          setState(() {
            _isInRange = false;
          });
          _notifyBlockedAttempt(action);
          _showSnack(
            '📍 You are not at an authorized location. You cannot $action.',
          );
          return false;
        }
        setState(() => _isInRange = true);
      } catch (e) {
        debugPrint('🚨 Fresh geofence failed: $e');
        _logSecurityEvent(
          type: 'clock_action_geofence_error',
          severity: 'high',
          details: 'Fresh geofence failed: $e',
        );
        _showSnack('⚠️ Unable to verify location. Please try again.');
        return false;
      }
    }

    return true;
  }

  Future<void> _handleClockIn() async {
    if (_saving || _clockActionInProgress) return;
    _clockActionInProgress = true;
    _recordUserActivity();

    try {
      if (!_checkRateLimit()) return;
      if (!await _preClockCheck('clock in')) return;

      if (_clockInTime != null) {
        _showSnack('You already clocked in at ${_formatTime(_clockInTime!)}.');
        return;
      }

      if (!mounted) return;
      setState(() => _saving = true);
      final now = _adjustedNow;
      final ok = await _saveAttendance(type: 'IN', time: now);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (ok) _clockInTime = now;
      });
      if (!ok) return;

      _showSnack(
        _isDemo
            ? '🎭 DEMO: Clocked IN at ${_formatTime(now)}'
            : '✅ Clocked IN at ${_formatTime(now)}',
      );
      widget.onClockIn?.call();
    } finally {
      _clockActionInProgress = false;
    }
  }

  Future<void> _handleClockOut() async {
    if (_saving || _clockActionInProgress) return;
    _clockActionInProgress = true;
    _recordUserActivity();

    try {
      if (!_checkRateLimit()) return;
      if (!await _preClockCheck('clock out')) return;

      if (_clockInTime == null) {
        _showSnack('Please clock in first before clocking out.');
        return;
      }
      if (_clockOutTime != null) {
        _showSnack('You already clocked out at ${_formatTime(_clockOutTime!)}.');
        return;
      }

      if (!mounted) return;
      setState(() => _saving = true);
      final now = _adjustedNow;
      final ok = await _saveAttendance(type: 'OUT', time: now);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (ok) _clockOutTime = now;
      });
      if (!ok) return;

      _showSnack(
        _isDemo
            ? '🎭 DEMO: Clocked OUT at ${_formatTime(now)}'
            : '✅ Clocked OUT at ${_formatTime(now)}',
      );
      widget.onClockOut?.call();
    } finally {
      _clockActionInProgress = false;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isDemo ? _demoAccent : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final empName = _employee?.fullName ?? 'JOHN HOWARD';

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

    // ═══════════════════════════════════════════════════════════
    // 🆕 SKELETON LOADING STATE (works for demo + normal)
    // ═══════════════════════════════════════════════════════════
    if (_isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(
          child: Stack(
            children: [
              const DashboardSkeleton(),
              if (isOffline && !_isDemo)
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

    return Scaffold(
      backgroundColor: tc.bg,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            bottom: -130,
            left: -150,
            child: RepaintBoundary(
              child: IgnorePointer(
                child: Transform.rotate(
                  angle: _degToRad(425),
                  child: Opacity(
                    opacity: tc.watermarkOpacity,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color.fromRGBO(255, 138, 0, 0.10),
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        _logoAsset,
                        width: 500,
                        height: 500,
                        fit: BoxFit.contain,
                        cacheWidth: 500,
                        cacheHeight: 500,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) {
                          debugPrint('logo.png failed to load');
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: RefreshIndicator(
                    color: _orange,
                    backgroundColor: tc.bg,
                    onRefresh: _handlePullRefresh,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),

                          if (_isDemo) _buildDemoClockBadge(),

                          if (_mockLocationDetected && !_isDemo) ...[
                            Padding(
                              padding:
                              const EdgeInsets.fromLTRB(24, 0, 24, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _buildSecurityBadge(
                                    'FAKE GPS',
                                    Icons.gps_off_rounded,
                                    _red,
                                  ),
                                ],
                              ),
                            ),
                          ],

                          _buildHeader(tc, empName),
                          const SizedBox(height: 24),
                          _buildHeroCard(),
                          const SizedBox(height: 21),
                          _buildClockInOutSection(),
                          const SizedBox(height: 23),
                          _buildClockOutSection(tc),
                          const SizedBox(height: 21),
                          _buildShortcutsSection(tc),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomNav(tc),
            ],
          ),

          if ((isOffline || isChecking) && !_isDemo)
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
    );
  }

  // 🎭 DEMO MODE badge sa taas — ORANGE
  Widget _buildDemoClockBadge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_demoAccent, _demoAccentDark],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: _demoAccent.withValues(alpha: 0.3),
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
      ),
    );
  }

  Widget _buildSecurityBadge(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                      foregroundColor: _orange,
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

  Widget _buildHeader(_ThemeColors tc, String name) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _handleProfileTap,
            behavior: HitTestBehavior.opaque,
            child: _buildHeaderAvatar(tc, initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'HI, $name'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tc.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: _orange),
                    const SizedBox(width: 4),
                    _LiveClock(
                      textStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tc.textPrimary,
                        letterSpacing: 0.2,
                      ),
                      offset: _timeOffset,
                    ),
                    if (_wfhAccess && !_isDemo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.isDark
                              ? const Color(0xFF14371F)
                              : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(999),
                          border:
                          Border.all(color: const Color(0xFF22C55E)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.home_work_rounded,
                                size: 10,
                                color: tc.isDark
                                    ? const Color(0xFF86EFAC)
                                    : _greenDeep),
                            const SizedBox(width: 4),
                            Text(
                              'WFH',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: tc.isDark
                                    ? const Color(0xFF86EFAC)
                                    : _greenDeep,
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
          if (_checkingGeofence && !_isDemo)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: _orange,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatar(_ThemeColors tc, String initials) {
    final photoUrl = _employee?.photoUrl;
    final hasPhoto =
        photoUrl != null && photoUrl.isNotEmpty && photoUrl != '—';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isDemo ? _demoAccent : tc.avatarBg,
        border: Border.all(
          color: _isDemo ? _demoAccent : tc.avatarBorder,
          width: 1.15,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasPhoto && !_isDemo
          ? _buildPhotoContent(tc, photoUrl, initials)
          : Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPhotoContent(_ThemeColors tc, String url, String initials) {
    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          width: 40,
          height: 40,
          cacheWidth: 80,
          cacheHeight: 80,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _avatarFallbackText(tc, initials),
        );
      } catch (_) {
        return _avatarFallbackText(tc, initials);
      }
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        cacheWidth: 80,
        cacheHeight: 80,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _avatarFallbackText(tc, initials),
      );
    }
    return _avatarFallbackText(tc, initials);
  }

  Widget _avatarFallbackText(_ThemeColors tc, String initials) {
    return Container(
      color: _orange,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final Color accent;
    final String statusText;
    final String subtitle;

    if (_isDemo) {
      accent = _demoAccent;
      statusText = 'DEMO MODE.';
      subtitle = 'All checks bypassed. No data will be saved to the database.';
    } else if (_mockLocationDetected && !_wfhAccess) {
      accent = _red;
      statusText = 'Fake GPS.';
      subtitle = 'Please disable mock location apps to proceed.';
    } else if (_checkingGeofence && !_wfhAccess) {
      accent = const Color(0xFFA1A1AA);
      statusText = 'Checking...';
      subtitle = 'Verifying your location. Please wait.';
    } else if (_isWfhMode) {
      accent = const Color(0xFF4ADE80);
      statusText = 'WFH Mode.';
      subtitle =
      'Work-from-home access is active. You can clock in/out anywhere.';
    } else if (_isInRange) {
      accent = _orange;
      statusText = 'In Range.';
      subtitle = 'Our system verified your location. You are ready to go.';
    } else {
      accent = _orange;
      statusText = 'Out of Range.';
      subtitle =
      'You are outside the authorized zone. Clock in/out is disabled.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _handleContinue,
        child: RepaintBoundary(
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isDemo ? _demoAccent : _orangeBorder,
                width: 1.15,
              ),
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
                                color: accent,
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
          ),
        ),
      ),
    );
  }

  Widget _buildClockInOutSection() {
    final clockedIn = _clockInTime != null;
    final canClock = _canClock;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 72,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: _isDemo
              ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_demoAccent, _demoAccentDark],
          )
              : _orangeGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDemo ? _demoAccent : _orangeBorder,
            width: 1.15,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: (_saving || !canClock || _clockActionInProgress)
                    ? null
                    : _handleClockIn,
                behavior: HitTestBehavior.opaque,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canClock ? 1.0 : 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDemo ? _demoAccent : _orangeBorder,
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Clock In',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _saving && !clockedIn
                              ? 'Saving...'
                              : (canClock ? _clockInDisplay : 'Locked'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: !canClock
                                ? _red
                                : (clockedIn
                                ? (_isDemo ? _demoAccent : _orange)
                                : const Color(0xFFA1A1AA)),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: GestureDetector(
                onTap: (_saving || !canClock || _clockActionInProgress)
                    ? null
                    : _handleClockOut,
                behavior: HitTestBehavior.opaque,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canClock ? 1.0 : 0.5,
                  child: Container(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Clock Out',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          canClock ? _clockOutDisplay : 'Locked',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockOutSection(_ThemeColors tc) {
    final isInRangeOrWfh = _isDemo || _isInRange || _isWfhMode;

    final cardBg = _isDemo
        ? _demoAccent.withValues(alpha: tc.isDark ? 0.2 : 0.15)
        : (_isInRange
        ? (tc.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.2))
        : (_isWfhMode
        ? const Color(0xFF22C55E)
        .withValues(alpha: tc.isDark ? 0.2 : 0.15)
        : (tc.isDark
        ? const Color(0xFF1F1F23)
        : const Color(0xFF838383).withValues(alpha: 0.28))));

    final cardBorder = _isDemo
        ? _demoAccent
        : (_isInRange
        ? _orangeBorder
        : (_isWfhMode ? const Color(0xFF22C55E) : _red));

    final labelColor = isInRangeOrWfh ? tc.textPrimary : tc.textOnDark;
    final hasClockedOut = _clockOutTime != null;
    final canClock = _canClock;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Clock Out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tc.textPrimary,
                ),
              ),
              if (hasClockedOut)
                Text(
                  _clockOutDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isDemo ? _demoAccent : _orange,
                  ),
                )
              else if (!canClock)
                const Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: (_saving || !canClock || _clockActionInProgress)
                  ? null
                  : _handleClockOut,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: canClock ? 1.0 : 0.5,
                child: Container(
                  width: 105,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder, width: 1.15),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _isDemo
                              ? const LinearGradient(
                            colors: [_demoAccent, _demoAccentDark],
                          )
                              : _orangeGradient,
                          border: Border.all(
                            color: _isDemo ? _demoAccent : _orangeBorder,
                            width: 1.15,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          !canClock
                              ? Icons.lock_outline_rounded
                              : (hasClockedOut
                              ? Icons.check_rounded
                              : Icons.access_time_rounded),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        !canClock
                            ? 'Locked'
                            : (hasClockedOut ? 'Done' : 'Clock Out'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isWfhMode && !_isDemo) ...[
            const SizedBox(height: 12),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tc.isDark
                    ? const Color(0xFF14371F)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.home_work_rounded,
                    size: 16,
                    color: tc.isDark ? const Color(0xFF86EFAC) : _greenDeep,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WFH mode active — clock in/out is allowed even outside the office zone.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color:
                        tc.isDark ? const Color(0xFF86EFAC) : _greenDeep,
                        height: 1.35,
                      ),
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

  Widget _buildShortcutsSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Short Cuts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: tc.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    onTap: () {
                      _recordUserActivity();
                      (widget.onShortcutHome ?? _handleBack)();
                    },
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    onTap: widget.onShortcutProfile ?? _handleProfileTap,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.calendar_month_rounded,
                    label: 'Leaves',
                    onTap: () {
                      _recordUserActivity();
                      widget.onShortcutLeaves?.call();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(_ThemeColors tc) {
    const items = <_NavItem>[
      _NavItem(icon: Icons.grid_view_rounded, label: 'Home'),
      _NavItem(icon: Icons.access_time_rounded, label: 'Logs'),
      _NavItem(icon: Icons.calendar_today_rounded, label: 'Itinerary'),
      _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: tc.navBg,
        border: Border(top: BorderSide(color: tc.navBorder, width: 1.15)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(items.length, (i) {
            final item = items[i];
            final active = i == _activeNavIndex;
            final color = active
                ? (_isDemo ? _demoAccent : _orange)
                : tc.textSecondary;
            return GestureDetector(
              onTap: () {
                _recordUserActivity();
                setState(() => _activeNavIndex = i);
                widget.onNavTap?.call(i);
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                      active ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _LiveClock extends StatefulWidget {
  final TextStyle textStyle;
  final Duration offset;

  const _LiveClock({
    required this.textStyle,
    this.offset = Duration.zero,
  });

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Timer _timer;
  late String _display;

  @override
  void initState() {
    super.initState();
    _display = _format(DateTime.now().add(widget.offset));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = _format(DateTime.now().add(widget.offset));
      if (next != _display && mounted) {
        setState(() => _display = next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _LiveClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offset != widget.offset) {
      _display = _format(DateTime.now().add(widget.offset));
    }
  }

  String _format(DateTime t) {
    final h24 = t.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final m = t.minute.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:$m $period';
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_display, style: widget.textStyle);
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _ShortcutCard extends StatelessWidget {
  final _ThemeColors tc;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ShortcutCard({
    required this.tc,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: tc.cardFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _ClockScreenState._orangeBorder,
            width: 1.15,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _ClockScreenState._orangeGradient,
                border: Border.all(
                  color: _ClockScreenState._orangeBorder,
                  width: 1.15,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tc.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}