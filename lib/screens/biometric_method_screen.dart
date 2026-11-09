// lib/screens/biometric_method_screen.dart
// ═══════════════════════════════════════════════════════════════════
// BIOMETRIC METHOD SCREEN  v1.7
//   - 🎭 Demo mode: navigates to the ACTUAL biometric screen (no auto clock-in)
//   - 🔒 Requires internet connection even in Demo Mode
//   - 🌐 All UI text in English
//   - 🐛 FIX: Back button goes to the RECENT screen (LoginScreen),
//          HINDI diretso sa Dashboard.
//   - 🐛 FIX v1.7: Back arrow ↔ "Back" text alignment — pantay na sila
//          (tinanggal ang -5 offset sa _BackArrowPainter, at
//           explicit na center alignment sa Row).
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:camera/camera.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../services/geofence_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/demo_mode_service.dart';
import 'fingerprint_screen.dart';
import 'facial_recognition_screen.dart';
import 'login_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint('[BiometricMethod] $message');
}

enum BiometricFlowMode { login, clockAction }

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bgTop => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get bgMid => isDark ? const Color(0xFF0F0D0B) : const Color(0xFFFFF0E5);
  Color get bgBottom =>
      isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFE3D1);
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);
  Color get optionBorder =>
      isDark ? const Color(0xFF7C2D12) : const Color(0xFFFDBA74);
  Color get hoverBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFF7ED);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1F2937);
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  Color get infoBg => isDark ? const Color(0xFF1F1F23) : Colors.white;
  Color get infoBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);
  Color get infoText =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  Color get methodIconBg => isDark ? const Color(0xFF27272A) : Colors.white;
}

class BiometricMethodScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;
  final BiometricFlowMode mode;

  const BiometricMethodScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
    this.mode = BiometricFlowMode.login,
  });

  @override
  State<BiometricMethodScreen> createState() => _BiometricMethodScreenState();
}

class _BiometricMethodScreenState extends State<BiometricMethodScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;
  bool _retryable = false;

  bool _fingerprintAvailable = false;
  bool _facialAvailable = true;
  bool _fingerprintChecked = false;
  bool _cameraChecked = false;

  bool _checkingLocation = true;
  bool _isInsideZone = false;
  bool _isWfh = false;
  bool _isDriver = false;
  bool _geofenceExempted = false;

  bool _preAuthValid = false;
  bool _deviceCompromised = false;
  bool _obscureContent = false;
  String? _deviceBinding;
  late final String _sessionNonce;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _heartbeatTimer;
  Timer? _inactivityWatchdog;
  DateTime? _lastUserActivityAt;
  bool _sessionValidated = false;
  bool _loggedOut = false;

  DateTime? _lastMethodTapAt;
  static const Duration _methodTapCooldown = Duration(seconds: 2);

  static const Duration _bootstrapTimeout = Duration(seconds: 20);
  static const Duration _maxInactivityTime = Duration(minutes: 10);
  static const Duration _geofenceFreshTimeout = Duration(seconds: 10);

  bool _isNavigating = false;

  // 🌐 Live connectivity state
  bool _isOnline = true;

  static const String _kPreAuthEmpKey = 'fp_preauth_employee_id';
  static const String _kPreAuthTimeKey = 'fp_preauth_time';
  static const String _kPreAuthNonceKey = 'fp_preauth_nonce';
  static const Duration _preAuthValidDuration = Duration(minutes: 10);

  final LocalAuthentication _localAuth = LocalAuthentication();

  static const double _kHeaderDesignFrameWidth = 386.13;
  static const double _kHeaderH = 287.13;
  static const double _kHeaderBorderBottom = 1.15;
  static const double _kHeaderRadius = 16.0;
  static const double _kBackLeft = 24.0;
  static const double _kBackTop = 48.0;
  static const double _kBackIconSize = 19.99;
  static const double _kTitleLeft = 24.0;
  static const double _kTitleTop = 95.99;
  static const double _kTitleFontSize = 30.0;
  static const double _kSubtitleLeft = 24.0;
  static const double _kSubtitleTop = 136.99;
  static const double _kSubtitleFontSize = 14.0;

  static const Color _headerStart = Color(0xFFFF8A00);
  static const Color _headerMid = Color(0xFFFF6B00);
  static const Color _headerEnd = Color(0xFFF54900);
  static const Color _headerBorder = Color(0xFF382A20);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _orange = Color(0xFFF97316);
  static const Color _error = Color(0xFFDC2626);

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  bool get _isDemo => DemoModeService.instance.isEnabled;
  bool get _canClockIn =>
      _isInsideZone || _isWfh || _isDriver || _geofenceExempted;
  bool get _isLoginMode => widget.mode == BiometricFlowMode.login;

  String get _stepLabel =>
      _isLoginMode ? 'Step 2: Verify Identity' : 'Verify Identity to Clock';

  String get _headerSubtitle => _isLoginMode
      ? 'Select your verification method'
      : 'Select biometric to clock in or out';

  String get _infoText {
    if (_isDemo && !_isOnline) {
      return '📴 No internet connection. Demo Mode requires an active '
          'network connection. Please connect and try again.';
    }
    if (_isDemo) {
      return '🎭 DEMO MODE — Choose Fingerprint or Facial to continue '
          'to the biometric screen.';
    }
    if (!_fingerprintAvailable && !_facialAvailable) {
      return 'No biometric method available. Contact your administrator.';
    }
    if (!_fingerprintAvailable) {
      return 'Fingerprint is not available on this device. Use Facial recognition.';
    }
    if (!_facialAvailable) {
      return 'Camera is not available. Use Fingerprint to continue.';
    }
    if (!_canClockIn && !_checkingLocation) {
      return 'You are outside the authorized zone. Clock-in may be blocked.';
    }
    return _isLoginMode
        ? 'Both methods use military-grade encryption. Your biometric data never leaves your device.'
        : 'Your location will be verified automatically before clock-in.';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _lastUserActivityAt = DateTime.now();

    // 🌐 Sync initial connectivity state
    try {
      _isOnline = ConnectivityService.instance.isOnline;
    } catch (_) {
      _isOnline = true;
    }

    // 🌐 Listen for connectivity changes (works even in demo)
    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            setState(() => _isOnline = online);
            _secureLog('🌐 Connectivity changed: online=$online');
          });
    } catch (e) {
      _secureLog('⚠️ connectivity listen error: $e');
    }

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    _bootstrap();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔌 OFFLINE HELPERS
  // ═══════════════════════════════════════════════════════════════
  bool _isOnlineSafely() {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  void _showOfflineSnack([String? custom]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  custom ?? 'Internet connection is required to continue.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _retryable = false;
      });
    }

    try {
      await Future<void>.delayed(Duration.zero).timeout(_bootstrapTimeout);

      // ═══════════════════════════════════════════════════════════
      // 🎭 DEMO MODE — full bypass (but still requires internet)
      // ═══════════════════════════════════════════════════════════
      if (_isDemo) {
        debugPrint('🎭 [DemoMode] Bootstrap — DEMO PATH');

        // 🔌 Check internet FIRST — even in demo
        if (!_isOnlineSafely()) {
          _secureLog('🎭 [DemoMode] BLOCKED — no internet at bootstrap');
          if (mounted) {
            setState(() {
              _isOnline = false;
              _isLoading = false;
              _errorMessage =
              'Internet connection is required for Demo Mode.\n\n'
                  'Please connect to the internet and try again.';
              _retryable = true;
            });
          }
          return;
        }

        _preAuthValid = true;
        _deviceCompromised = false;
        _determineRole();

        _fingerprintAvailable = true;
        _facialAvailable = true;
        _fingerprintChecked = true;
        _cameraChecked = true;
        _isInsideZone = true;
        _checkingLocation = false;

        if (mounted) {
          setState(() {
            _isLoading = false;
            _sessionValidated = true;
          });
        }
        return;
      }

      try {
        await SecurityHardeningService.instance.enableSecureScreen();
      } catch (_) {}
      try {
        final ok =
        await SecurityHardeningService.instance.checkDeviceIntegrity();
        _deviceCompromised = !ok;
      } catch (_) {}
      try {
        _deviceBinding = await SecurityHardeningService.instance
            .getDeviceBindingToken();
      } catch (_) {}

      final preAuthOk = await _verifyPreAuth();
      _determineRole();

      await Future.wait([
        _checkFingerprintHardware(),
        _checkCameraAvailability(),
        _checkLocation(),
      ]);

      if (!preAuthOk) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _startSessionRevocationListener();
      _startHeartbeat();
      _startInactivityWatchdog();

      if (mounted && preAuthOk) _maybeAutoSelect();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _sessionValidated = true;
        });
      }
    } catch (e) {
      _secureLog('❌ Bootstrap error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Initialization error. Please try again.';
          _retryable = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _verifyPreAuth() async {
    // 🎭 DEMO MODE — bypass security (internet already checked in bootstrap)
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Pre-auth BYPASSED');
      _preAuthValid = true;
      return true;
    }

    try {
      final secEmpId =
      await SecurityHardeningService.instance.getCurrentEmployeeId();
      if (secEmpId == null || secEmpId != widget.employee.id) {
        await _logSecurityEvent(
          type: 'method_no_session',
          severity: 'critical',
          details:
          'Session mismatch (session=$secEmpId, screen=${widget.employee.id})',
        );
        await _hardClearSession();
        _setError('🚨 Session expired. Please log in again.',
            retryable: false);
        return false;
      }

      try {
        final valid = await SecurityService.instance
            .isSessionValid()
            .timeout(const Duration(seconds: 5));
        if (!valid) {
          await _logSecurityEvent(
            type: 'method_session_invalid',
            severity: 'high',
            details: 'SecurityService.isSessionValid() = false',
          );
          await _hardClearSession();
          _setError('🚨 Session expired. Please log in again.',
              retryable: false);
          return false;
        }

        final sessionEmpId =
        await SecurityService.instance.getCurrentEmployeeId();
        final docId = widget.employee.id;
        final empId = widget.employee.employeeId;
        final matches = sessionEmpId == null ||
            sessionEmpId.isEmpty ||
            sessionEmpId == docId ||
            (empId.isNotEmpty && sessionEmpId == empId);
        if (!matches) {
          await _logSecurityEvent(
            type: 'method_session_mismatch',
            severity: 'critical',
            details: 'Session ($sessionEmpId) != screen ($docId/$empId)',
          );
          await _hardClearSession();
          _setError('🚨 Session mismatch. Please log in again.',
              retryable: false);
          return false;
        }
      } catch (e) {
        _secureLog('⚠️ SecurityService check error: $e');
      }

      if (_isLoginMode) {
        final prefs = await SharedPreferences.getInstance();
        final preAuthEmpId = prefs.getString(_kPreAuthEmpKey);
        final preAuthTimeMs = prefs.getInt(_kPreAuthTimeKey);
        final preAuthNonce = prefs.getString(_kPreAuthNonceKey);

        if (preAuthEmpId == null ||
            preAuthTimeMs == null ||
            preAuthNonce == null ||
            preAuthNonce.isEmpty) {
          _setError('🚨 Security check failed. Please log in again.',
              retryable: false);
          return false;
        }
        if (preAuthEmpId != widget.employee.id) {
          await _logSecurityEvent(
            type: 'method_preauth_mismatch',
            severity: 'critical',
            details: 'preAuth=$preAuthEmpId != screen=${widget.employee.id}',
          );
          _setError('🚨 Security check failed. Please log in again.',
              retryable: false);
          return false;
        }
        final preAuthTime = DateTime.fromMillisecondsSinceEpoch(preAuthTimeMs);
        final elapsed = DateTime.now().difference(preAuthTime);
        if (elapsed.isNegative) {
          _setError('🚨 Invalid session time. Please log in again.',
              retryable: false);
          return false;
        }
        if (elapsed > _preAuthValidDuration) {
          _setError('🚨 Session expired. Please log in again.',
              retryable: false);
          return false;
        }
        await prefs.remove(_kPreAuthEmpKey);
        await prefs.remove(_kPreAuthTimeKey);
        await prefs.remove(_kPreAuthNonceKey);
      }

      if (!kIsWeb && _deviceCompromised) {
        _setError('🚨 This device is flagged as compromised. Access blocked.',
            retryable: false);
        return false;
      }

      _preAuthValid = true;
      return true;
    } catch (e) {
      _secureLog('❌ _verifyPreAuth error: $e');
      _setError('🚨 Security check failed. Please log in again.',
          retryable: false);
      return false;
    }
  }

  void _setError(String message, {required bool retryable}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _retryable = retryable;
      _isLoading = false;
    });
  }

  void _determineRole() {
    final emp = widget.employee;
    final role = emp.position.toLowerCase();
    final dept = emp.department.toLowerCase();
    _isDriver = role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider');
    _isWfh = emp.wfhAccess;
  }

  void _startSessionRevocationListener() {
    if (_isDemo) return;
    final empDocId = widget.employee.id;
    if (empDocId.isEmpty) return;

    _sessionSub?.cancel();
    _sessionSub = FirebaseFirestore.instance
        .collection('sessions')
        .doc(empDocId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) return;
        final revoked = data['revoked'] == true;
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (revoked) {
          _forceLogout('Session revoked by admin');
          return;
        }
        if (expiresAt != null &&
            expiresAt.toDate().isBefore(DateTime.now())) {
          _forceLogout('Session expired');
        }
      },
      onError: (e) => _secureLog('Session listener error: $e'),
    );
  }

  void _startHeartbeat() {
    if (_isDemo) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        final valid = await SecurityService.instance
            .isSessionValid()
            .timeout(const Duration(seconds: 5));
        if (!valid && mounted && !_loggedOut) {
          await _forceLogout('Session invalidated');
        } else {
          try {
            await SecurityService.instance.markSessionActive();
          } catch (_) {}
        }
      } catch (e) {
        _secureLog('⚠️ Heartbeat failed: $e');
      }
    });
  }

  void _startInactivityWatchdog() {
    if (_isDemo) return;
    _inactivityWatchdog?.cancel();
    _inactivityWatchdog = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _maxInactivityTime) {
        await _forceLogout('Inactivity timeout (${idle.inMinutes}m)');
      }
    });
  }

  void _recordUserActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  Future<void> _forceLogout(String reason) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Force logout ignored: $reason');
      return;
    }
    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    _heartbeatTimer?.cancel();
    _inactivityWatchdog?.cancel();
    _sessionSub?.cancel();

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
    await _hardClearSession();
    await _logSecurityEvent(
      type: 'method_forced_logout',
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

  Future<void> _hardClearSession() async {
    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}
    try {
      await SecurityService.instance.clearSession();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPreAuthEmpKey);
      await prefs.remove(_kPreAuthTimeKey);
      await prefs.remove(_kPreAuthNonceKey);
    } catch (_) {}
  }

  Future<void> _checkFingerprintHardware() async {
    if (_isDemo) {
      _fingerprintAvailable = true;
      _fingerprintChecked = true;
      return;
    }
    if (kIsWeb) {
      _fingerprintAvailable = false;
      _fingerprintChecked = true;
      return;
    }
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        _fingerprintAvailable = false;
        _fingerprintChecked = true;
        return;
      }
      final enrolled = await _localAuth.getAvailableBiometrics();
      _fingerprintAvailable = enrolled.isNotEmpty;
    } catch (_) {
      _fingerprintAvailable = false;
    } finally {
      _fingerprintChecked = true;
    }
  }

  Future<void> _checkCameraAvailability() async {
    if (_isDemo) {
      _facialAvailable = true;
      _cameraChecked = true;
      return;
    }
    if (kIsWeb) {
      _facialAvailable = true;
      _cameraChecked = true;
      return;
    }
    try {
      final cameras = await availableCameras();
      _facialAvailable = cameras.isNotEmpty;
    } catch (_) {
      _facialAvailable = false;
    } finally {
      _cameraChecked = true;
    }
  }

  Future<void> _checkLocation() async {
    if (_isDemo) {
      _isInsideZone = true;
      _geofenceExempted = true;
      if (mounted) setState(() => _checkingLocation = false);
      return;
    }
    try {
      final empId = widget.employee.id;
      GeofenceResult? result;
      try {
        result = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: empId)
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
      if (!mounted) return;
      if (result != null) {
        _isInsideZone = result.isInside ||
            result.status == GeofenceStatus.insideWithTolerance;
        _geofenceExempted = result.isExempted;
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _checkingLocation = false);
    }
  }

  void _maybeAutoSelect() {
    if (_isDemo) return;
    if (_fingerprintChecked && _cameraChecked) {
      if (_fingerprintAvailable && !_facialAvailable) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && !_isNavigating && !_loggedOut) _selectFingerprint();
        });
      } else if (!_fingerprintAvailable && _facialAvailable) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && !_isNavigating && !_loggedOut) _selectFacial();
        });
      }
    }
  }

  bool _checkMethodRateLimit() {
    if (_isDemo) return true;
    final now = DateTime.now();
    if (_lastMethodTapAt != null) {
      final elapsed = now.difference(_lastMethodTapAt!).inMilliseconds;
      if (elapsed < _methodTapCooldown.inMilliseconds) {
        _secureLog('🚦 Method tap rate-limited ($elapsed ms)');
        return false;
      }
    }
    _lastMethodTapAt = now;
    return true;
  }

  Future<bool> _revalidateBeforeNavigation() async {
    if (_isDemo) return true;
    final valid = await SecurityService.instance
        .isSessionValid()
        .timeout(const Duration(seconds: 5))
        .catchError((_) => false);
    if (!valid) {
      await _forceLogout('Session invalid on selection');
      return false;
    }
    if (!_isWfh && !_isDriver && !_geofenceExempted) {
      try {
        final fresh = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: widget.employee.id)
            .timeout(_geofenceFreshTimeout);
        final inside = fresh.isInside ||
            fresh.status == GeofenceStatus.insideWithTolerance ||
            fresh.isExempted;
        if (!inside) {
          if (mounted) {
            setState(() {
              _isInsideZone = false;
              _geofenceExempted = fresh.isExempted;
            });
          }
          _secureLog('📍 Re-check: no longer inside zone');
          await _logSecurityEvent(
            type: 'method_geofence_stale',
            severity: 'medium',
            details: 'Geofence state changed during method selection',
          );
        } else {
          if (mounted) setState(() => _isInsideZone = true);
        }
      } catch (e) {
        _secureLog('⚠️ Fresh geofence failed: $e');
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 SELECT — FINGERPRINT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _selectFingerprint() async {
    _recordUserActivity();
    if (_isNavigating || !_preAuthValid || _loggedOut) return;
    if (!_fingerprintAvailable) return;

    if (!_isOnlineSafely()) {
      _secureLog('🔌 Fingerprint selection BLOCKED — no internet');
      _showOfflineSnack('Internet connection is required to continue.');
      return;
    }

    if (!_checkMethodRateLimit()) return;

    if (mounted) {
      setState(() => _isNavigating = true);
    } else {
      _isNavigating = true;
    }

    try {
      if (!_isOnlineSafely()) {
        _showOfflineSnack(
            'Internet connection lost. Please reconnect and try again.');
        return;
      }

      final ok = await _revalidateBeforeNavigation();
      if (!ok || !mounted) return;

      await _logSecurityEvent(
        type: 'method_selected',
        severity: 'info',
        details: 'User selected: Fingerprint (mode: ${widget.mode.name})',
      );

      if (!mounted) return;

      _secureLog('➡️ Navigating to FingerprintScreen '
          '(demo=$_isDemo, standalone=true)');

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FingerprintScreen(
            employee: widget.employee,
            arrivalTime: widget.arrivalTime,
            standaloneMode: true,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
          _lastMethodTapAt = null;
        });
      } else {
        _isNavigating = false;
        _lastMethodTapAt = null;
      }
      if (_isDemo) return;
      if (mounted && !_loggedOut) {
        try {
          final valid = await SecurityService.instance
              .isSessionValid()
              .timeout(const Duration(seconds: 5));
          if (!valid && mounted && !_loggedOut) {
            await _forceLogout('Session invalid after return');
          }
        } catch (_) {}
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 SELECT — FACIAL
  // ═══════════════════════════════════════════════════════════════
  Future<void> _selectFacial() async {
    _recordUserActivity();
    if (_isNavigating || !_preAuthValid || _loggedOut) return;
    if (!_facialAvailable) return;

    if (!_isOnlineSafely()) {
      _secureLog('🔌 Facial selection BLOCKED — no internet');
      _showOfflineSnack('Internet connection is required to continue.');
      return;
    }

    if (!_checkMethodRateLimit()) return;

    if (mounted) {
      setState(() => _isNavigating = true);
    } else {
      _isNavigating = true;
    }

    try {
      if (!_isOnlineSafely()) {
        _showOfflineSnack(
            'Internet connection lost. Please reconnect and try again.');
        return;
      }

      final ok = await _revalidateBeforeNavigation();
      if (!ok || !mounted) return;

      await _logSecurityEvent(
        type: 'method_selected',
        severity: 'info',
        details:
        'User selected: Facial Recognition (mode: ${widget.mode.name})',
      );

      if (!mounted) return;

      _secureLog('➡️ Navigating to FacialRecognitionScreen '
          '(demo=$_isDemo)');

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FacialRecognitionScreen(
            employee: widget.employee,
            arrivalTime: widget.arrivalTime,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isNavigating = false;
          _lastMethodTapAt = null;
        });
      } else {
        _isNavigating = false;
        _lastMethodTapAt = null;
      }
      if (_isDemo) return;
      if (mounted && !_loggedOut) {
        try {
          final valid = await SecurityService.instance
              .isSessionValid()
              .timeout(const Duration(seconds: 5));
          if (!valid && mounted && !_loggedOut) {
            await _forceLogout('Session invalid after return');
          }
        } catch (_) {}
      }
    }
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Security event (skipped): $type — $details');
      return;
    }
    try {
      if (!_isOnline) return;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': widget.employee.id,
        'employeeName': widget.employee.fullName,
        'sessionNonce': _sessionNonce,
        'deviceBinding': _deviceBinding,
        'deviceCompromised': _deviceCompromised,
        'mode': widget.mode.name,
        'stage': 'biometric_method',
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // 🐛 _goBack — v1.7
  // ═══════════════════════════════════════════════════════════════
  Future<void> _goBack() async {
    _recordUserActivity();

    // 🐛 Kung naka-stuck ang _isNavigating (halimbawa napindot ang back
    //    habang nag-o-open pa lang ang FingerprintScreen), i-force reset.
    if (_isNavigating) {
      _secureLog('⚠️ _goBack called while _isNavigating — forcing reset');
      _isNavigating = false;
      _lastMethodTapAt = null;
    }

    final nav = Navigator.of(context);

    // ✅ Kung may previous route — normal pop lang (bumalik sa recent screen)
    if (nav.canPop()) {
      _secureLog('⬅️ Popping previous route (recent screen)');
      nav.pop();
      return;
    }

    // 🐛 WALANG previous route (na-remove ng pushAndRemoveUntil sa LoginScreen).
    //    Fallback: pumunta sa LoginScreen (NOT LandingScreen!).
    _secureLog('⬅️ No previous route — fallback to LoginScreen '
        '(demo=$_isDemo)');

    // I-clear ang pre-auth keys para hindi mag-auto-restore ang session
    // sa susunod na pagpasok ng LoginScreen.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPreAuthEmpKey);
      await prefs.remove(_kPreAuthTimeKey);
      await prefs.remove(_kPreAuthNonceKey);
    } catch (_) {}

    if (!mounted) return;
    nav.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordUserActivity();
      if (mounted) {
        final needsReset = _isNavigating;
        setState(() {
          _obscureContent = false;
          if (needsReset) {
            _isNavigating = false;
            _lastMethodTapAt = null;
          }
        });
      }
      if (_isDemo) return;
      if (_preAuthValid && !_loggedOut) {
        SecurityService.instance
            .isSessionValid()
            .timeout(const Duration(seconds: 5))
            .then((valid) {
          if (!valid && mounted && !_loggedOut) {
            _forceLogout('Session invalid on resume');
          }
        }).catchError((_) {});
      }
    } else {
      final obscure = state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
      if (obscure != _obscureContent && mounted) {
        setState(() => _obscureContent = obscure);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _inactivityWatchdog?.cancel();
    _sessionSub?.cancel();
    _connectivitySub?.cancel();
    _fadeCtrl.dispose();
    if (!_isDemo) {
      SecurityHardeningService.instance.disableSecureScreen();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: tc.bgMid,
        body: Stack(
          children: [
            FadeTransition(
              opacity: _fadeAnim,
              child: _buildContent(tc),
            ),
            if (_obscureContent) _buildPrivacyShield(),
          ],
        ),
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
                  color: _orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.lock_outline_rounded,
                    color: Colors.black, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('R.A.C.O.M.A.',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text('Session hidden for your privacy',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_ThemeColors tc) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tc.bgTop, tc.bgMid, tc.bgBottom],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildOrangeHeader(),
          if (!_isOnline) _buildOfflineBanner(),
          Expanded(child: _buildSelectMethodStep(tc)),
        ]),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _error,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'No internet connection — biometric verification requires network',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrangeHeader() {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double scale = constraints.maxWidth.isFinite
              ? constraints.maxWidth / _kHeaderDesignFrameWidth
              : 1.0;
          if (scale <= 0) scale = 1.0;
          if (scale > 1.0) scale = 1.0;

          final outerRadius = _kHeaderRadius * scale;
          final borderW = _kHeaderBorderBottom * scale;
          final innerRadius = (outerRadius - borderW).clamp(0.0, outerRadius);

          return Container(
            width: double.infinity,
            height: _kHeaderH * scale,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _headerBorder,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(outerRadius),
                bottomRight: Radius.circular(outerRadius),
              ),
            ),
            padding: EdgeInsets.only(bottom: borderW),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_headerStart, _headerMid, _headerEnd],
                  stops: [0.0001, 0.3318, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(innerRadius),
                  bottomRight: Radius.circular(innerRadius),
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: _kBackLeft * scale,
                    top: _kBackTop * scale,
                    child: GestureDetector(
                      onTap: _goBack,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        // ✅ FIX v1.7: explicit vertical centering ng
                        //           arrow box at "Back" text
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _kBackIconSize * scale,
                            height: _kBackIconSize * scale,
                            child:
                            CustomPaint(painter: _BackArrowPainter()),
                          ),
                          SizedBox(width: 2 * scale),
                          Text(
                            'Back',
                            style: TextStyle(
                              color: _white,
                              fontSize: 16 * scale,
                              fontWeight: FontWeight.w500,
                              // ✅ FIX v1.7: height: 1.0 para walang extra
                              //           leading — pantay sa arrow box
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: _kTitleLeft * scale,
                    top: _kTitleTop * scale,
                    child: Text(
                      'Auth & Clock In',
                      style: TextStyle(
                        color: _white,
                        fontSize: _kTitleFontSize * scale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.0,
                      ),
                    ),
                  ),
                  Positioned(
                    left: _kSubtitleLeft * scale,
                    top: _kSubtitleTop * scale,
                    child: Text(
                      _headerSubtitle,
                      style: TextStyle(
                        color: _white,
                        fontSize: _kSubtitleFontSize * scale,
                        fontWeight: FontWeight.w400,
                        height: 1.0,
                      ),
                    ),
                  ),
                  if (_isDemo)
                    Positioned(
                      right: 16 * scale,
                      top: 48 * scale,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.science_rounded,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('DEMO',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.0)),
                              ],
                            ),
                          ),
                          if (!_isOnline) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: _error.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.cloud_off_rounded,
                                      color: Colors.white, size: 11),
                                  SizedBox(width: 4),
                                  Text('OFFLINE',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectMethodStep(_ThemeColors tc) {
    return LayoutBuilder(
      builder: (context, constraints) {
        double scale = constraints.maxWidth.isFinite
            ? constraints.maxWidth / _kHeaderDesignFrameWidth
            : 1.0;
        if (scale <= 0) scale = 1.0;
        if (scale > 1.0) scale = 1.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(children: [
            _buildOverlapCard(
              tc: tc,
              stepLabel: _stepLabel,
              overlap: 64 * scale,
              child: _isLoading
                  ? _buildLoading()
                  : _errorMessage != null
                  ? _buildError()
                  : _buildMethodButtons(tc),
            ),
            if (!_isLoading && _errorMessage == null) ...[
              const SizedBox(height: 16),
              _buildInfoCard(tc),
            ],
          ]),
        );
      },
    );
  }

  Widget _buildOverlapCard({
    required _ThemeColors tc,
    required String stepLabel,
    required Widget child,
    double overlap = 30,
  }) {
    return Transform.translate(
      offset: Offset(0, -overlap),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tc.cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _headerEnd.withValues(alpha: 0.08),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                stepLabel,
                style: TextStyle(
                  color: tc.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildMethodButtons(_ThemeColors tc) {
    final fpEnabled = _fingerprintAvailable && !_isNavigating && _isOnline;
    final faceEnabled = _facialAvailable && !_isNavigating && _isOnline;

    return Row(children: [
      Expanded(
        child: _MethodButton(
          icon: Icons.fingerprint_rounded,
          label: 'Fingerprint',
          enabled: fpEnabled,
          onTap: _selectFingerprint,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _MethodButton(
          icon: Icons.face_retouching_natural_rounded,
          label: 'Facial',
          enabled: faceEnabled,
          onTap: _selectFacial,
        ),
      ),
    ]);
  }

  Widget _buildInfoCard(_ThemeColors tc) {
    final isOffline = !_isOnline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOffline ? _error.withValues(alpha: 0.08) : tc.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isOffline
                ? _error.withValues(alpha: 0.6)
                : (_isDemo
                ? _orange.withValues(alpha: 0.6)
                : tc.infoBorder),
            width: 1.5),
      ),
      child: Row(children: [
        Icon(
          isOffline
              ? Icons.cloud_off_rounded
              : (_isDemo ? Icons.science_rounded : Icons.info_outline_rounded),
          color: isOffline ? _error : (_isDemo ? _orange : tc.infoText),
          size: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _infoText,
            style: TextStyle(
                color: isOffline
                    ? _error
                    : (_isDemo ? _orange : tc.infoText),
                fontSize: 12,
                height: 1.4,
                fontWeight: (isOffline || _isDemo)
                    ? FontWeight.w600
                    : FontWeight.normal),
          ),
        ),
      ]),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            color: _orange,
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final isSessionError = _errorMessage?.contains('log in again') ?? false;
    final isOfflineError = _errorMessage?.contains('Internet') ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.15),
            ),
            child: Icon(
              isOfflineError
                  ? Icons.cloud_off_rounded
                  : Icons.error_outline_rounded,
              color: Colors.red,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_retryable) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    _recordUserActivity();
                    _bootstrap();
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                onPressed: isSessionError
                    ? () => _forceLogout('User acknowledged session error')
                    : _goBack,
                icon: Icon(
                  isSessionError
                      ? Icons.login_rounded
                      : Icons.arrow_back_rounded,
                  size: 16,
                ),
                label: Text(isSessionError ? 'Log In' : 'Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  isSessionError ? Colors.red.shade600 : _orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _MethodButton
// ═══════════════════════════════════════════════════════════════
class _MethodButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _MethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  static const Color _orange = Color(0xFFF97316);
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final button = GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
        _pressCtrl.forward();
        setState(() => _pressed = true);
      }
          : null,
      onTapUp: widget.enabled
          ? (_) {
        _pressCtrl.reverse();
        setState(() => _pressed = false);
        widget.onTap();
      }
          : null,
      onTapCancel: widget.enabled
          ? () {
        _pressCtrl.reverse();
        setState(() => _pressed = false);
      }
          : null,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: AspectRatio(
            aspectRatio: 0.95,
            child: Container(
              decoration: BoxDecoration(
                color: _pressed ? tc.hoverBg : tc.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed ? _orange : tc.optionBorder,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: tc.methodIconBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.enabled
                            ? tc.optionBorder
                            : (isDark
                            ? const Color(0xFF3F3F46)
                            : const Color(0xFFE5E5E5)),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.enabled
                          ? _orange
                          : (isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFFBBBBBB)),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.enabled
                          ? tc.textDark
                          : (isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFFAAAAAA)),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!widget.enabled) {
      return Tooltip(
        message: 'Not available',
        child: button,
      );
    }
    return button;
  }
}

// ═══════════════════════════════════════════════════════════════
// _BackArrowPainter — v1.7
//   ✅ FIX: Tinanggal ang `-5` vertical offset. Dati kasi, naka-shift
//   pataas ang arrow (y = -0.002 → 9.994), kaya hindi siya pantay
//   sa "Back" text na vertically centered sa Row. Ngayon naka-center
//   na ang arrow sa 19.99×19.99 box, kaya level na silang dalawa.
// ═══════════════════════════════════════════════════════════════
class _BackArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 19.99;

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.66602 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ✅ FIX: Walang -5 offset — arrow ay centered sa box.
    Offset p(double x, double y) => Offset(x * s, y * s);

    final path = Path()
      ..moveTo(p(12.4951, 14.9941).dx, p(12.4951, 14.9941).dy)
      ..lineTo(p(7.49707, 9.9961).dx, p(7.49707, 9.9961).dy)
      ..lineTo(p(12.4951, 4.99805).dx, p(12.4951, 4.99805).dy);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}