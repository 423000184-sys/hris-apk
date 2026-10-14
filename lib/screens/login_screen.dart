// lib/screens/login_screen.dart
// v2.2: Added "Forgot PIN / Request Password Change" button + dialog
// v2.3: FCM token + notification listener auto-start on login
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/client_meeting_assignment.dart';
import '../services/client_location_service.dart';
import '../services/client_meeting_assignment_service.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import '../services/security_hardening_service.dart';
import '../services/fcm_service.dart';
import '../services/employee_notification_listener.dart';
import '../models/employee.dart';
import 'biometric_method_screen.dart';
import 'fingerprint_screen.dart';
import 'landing_screen.dart';
import 'admin_login_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

String _sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();

enum _LoginStep { selectMethod, pinEntry, nfcWait, clientMeeting }
enum _NetworkState { online, offline, checking }

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

class _ClientMeetingValidationResult {
  final bool dateOk;
  final bool timeOk;
  final bool locationOk;

  final DateTime now;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final Duration grace;

  final double? distanceMeters;
  final double clientRadius;

  bool get allOk => dateOk && timeOk && locationOk;

  const _ClientMeetingValidationResult({
    required this.dateOk,
    required this.timeOk,
    required this.locationOk,
    required this.now,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.grace,
    required this.distanceMeters,
    required this.clientRadius,
  });
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String _pinInput = '';
  bool _isLoading = false;
  bool _nfcAvailable = false;
  String? _errorMessage;
  _LoginStep _step = _LoginStep.selectMethod;

  bool _clientMeetingMode = false;
  static const bool _clientMeetingEnabled = true;

  bool _hasActiveMeeting = false;
  bool _checkingActiveMeeting = false;

  late final DateTime _arrivalTime;

  CameraController? _cameraController;
  bool _isCapturing = false;
  bool _captureSuccess = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _successCloseTimer;
  Timer? _meetingRefreshTimer;
  bool _useFrontCamera = true;

  double? _currentLatitude;
  double? _currentLongitude;
  String _currentPlaceName = 'Getting location…';
  bool _loadingLocation = false;
  DateTime? _locationTimestamp;
  StreamSubscription<Position>? _positionSub;

  double? _currentAccuracy;
  bool _isMockedGps = false;
  ClientLocationMatch? _clientMatch;
  bool _validatingClient = false;

  ClientMeetingAssignment? _activeAssignment;
  Employee? _activeEmployee;

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  StreamSubscription<bool>? _networkSub;

  Timer? _adminHoldTimer;
  bool _adminNavigating = false;

  static const String _kLastEmployeeIdKey = 'last_logged_in_employee_id';

  static const int _maxPinAttempts = 5;
  static const int _pinRateLimitMs = 1500;

  int _pinFailedAttempts = 0;
  DateTime? _pinLockoutUntil;
  Timer? _pinLockoutTimer;
  DateTime? _lastPinAttemptAt;
  String? _deviceFingerprint;
  late final String _sessionNonce;

  bool _loggingIn = false;
  bool _obscureContent = false;

  bool _deviceCompromised = false;
  bool _integrityChecked = false;
  Duration? _activeBackoff;

  static DateTime? _memLockoutUntil;

  static const Set<String> _weakPins = {
    '0000', '1111', '2222', '3333', '4444',
    '5555', '6666', '7777', '8888', '9999',
    '1234', '4321', '0123', '9876', '1010',
    '1212', '1122', '0001', '1000', '2000',
  };

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _modalController;
  late Animation<double> _modalScaleAnim;
  late Animation<double> _modalOpacityAnim;
  late AnimationController _nfcPulseController;
  late Animation<double> _nfcPulseAnim;

  static const Color _headerStart = Color(0xFFFF8A00);
  static const Color _headerMid = Color(0xFFFF6B00);
  static const Color _headerEnd = Color(0xFFF54900);
  static const Color _headerBorder = Color(0xFF382A20);
  static const Color _orange = Color(0xFFF97316);
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _error = Color(0xFFDC2626);
  static const Color _errorBg = Color(0xFFFEE2E2);
  static const Color _modalGradTop = Color(0xFFFF8A00);
  static const Color _modalGradMid = Color(0xFFFA6A00);
  static const Color _modalGradEnd = Color(0xFFF54900);
  static const Color _scrim = Color.fromRGBO(9, 9, 21, 0.68);
  static const Color _cmPreviewBg = Color(0xFF20212A);
  static const Color _cmShutterOuter = Color(0xFFFFA500);
  static const Color _cmShutterInner = Color(0xFFFEE0AA);
  static const Color _cmShutterGlow = Color(0xFFFF8C00);
  static const Color _shieldBg = Color(0xFF0C0C0E);

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

  static const List<String> _notFoundCodes = [
    'user-not-found',
    'invalid-credential',
    'invalid-login-credentials',
    'INVALID_LOGIN_CREDENTIALS',
  ];

  bool get _isOnline => _networkState == _NetworkState.online;

  String? get _employeeId {
    final emp = _activeEmployee;
    if (emp == null) return null;
    if (emp.employeeId.isNotEmpty) return emp.employeeId;
    if (emp.id.isNotEmpty) return emp.id;
    return null;
  }

  String get _employeeName => _activeEmployee?.fullName ?? 'Unknown';
  String get _employeeEmail => _activeEmployee?.email ?? '';

  bool get _isPinLockedOut {
    if (_activeBackoff != null && _activeBackoff! > Duration.zero) return true;
    if (_memLockoutUntil != null &&
        _memLockoutUntil!.isAfter(DateTime.now())) {
      return true;
    }
    return _pinLockoutUntil != null && _pinLockoutUntil!.isAfter(DateTime.now());
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _arrivalTime = DateTime.now();
    _sessionNonce = _generateSessionNonce();

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _modalController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _nfcPulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));

    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
        CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _modalScaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _modalController, curve: Curves.easeOutBack));
    _modalOpacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _modalController, curve: Curves.easeOut));
    _nfcPulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
        CurvedAnimation(parent: _nfcPulseController, curve: Curves.easeInOut));

    _nfcPulseController.repeat(reverse: true);
    _fadeController.forward();

    _startClockTimer();
    _checkCapabilities();
    _preloadLastEmployee();
    _loadDeviceFingerprint();

    _bootstrapSecurity();

    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            _secureLog('🌐 [LoginScreen] connectivity → online=$online');

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
              _checkNetworkOnEntry();
            }
          });
    } catch (e) {
      _secureLog('⚠️ [LoginScreen] connectivity failed: $e');
    }

    _checkNetworkOnEntry();

    _meetingRefreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) {
          if (!mounted) return;
          if (_checkingActiveMeeting) return;
          if (_step == _LoginStep.selectMethod && _activeEmployee != null) {
            _checkActiveMeeting();
          }
        });
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 SECURITY BOOTSTRAP
  // ═══════════════════════════════════════════════════════════════
  Future<void> _bootstrapSecurity() async {
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (e) {
      _secureLog('⚠️ [Security] FLAG_SECURE failed: $e');
    }

    try {
      final ok = await SecurityHardeningService.instance
          .checkDeviceIntegrity();
      if (!ok) {
        _secureLog('🚨 [Integrity] Compromised: '
            '${SecurityHardeningService.instance.integrityIssues.join(",")}');
        await _logSecurityEvent(
          type: 'compromised_device',
          severity: 'critical',
          details:
          SecurityHardeningService.instance.integrityIssues.join(','),
        );
      }
      if (mounted) {
        setState(() {
          _deviceCompromised = !ok;
          _integrityChecked = true;
        });
      }
    } catch (e) {
      _secureLog('⚠️ [Security] Integrity failed: $e');
      if (mounted) setState(() => _integrityChecked = true);
    }

    try {
      final bo =
      await SecurityHardeningService.instance.getActiveBackoff();
      if (bo != null && mounted) {
        setState(() {
          _activeBackoff = bo;
          _pinLockoutUntil = DateTime.now().add(bo);
          _memLockoutUntil = _pinLockoutUntil;
        });
        _startPinLockoutCountdown();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final obscure = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;

    if (obscure != _obscureContent && mounted) {
      setState(() => _obscureContent = obscure);
    }

    if (obscure) {
      if (_step == _LoginStep.pinEntry) {
        _pinInput = '';
      }
      if (_step == _LoginStep.clientMeeting) {
        _releaseCamera();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_step == _LoginStep.clientMeeting) {
        _startCameraSession();
      }
    }
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 HIDDEN ADMIN ACCESS
  // ═══════════════════════════════════════════════════════════════
  void _handleAdminHoldStart() {
    _adminHoldTimer?.cancel();
    _adminHoldTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _openHiddenAdminLogin();
    });
  }

  void _handleAdminHoldEnd() {
    _adminHoldTimer?.cancel();
  }

  Future<void> _openHiddenAdminLogin() async {
    if (_adminNavigating) return;
    _adminNavigating = true;

    try {
      if (!kIsWeb) HapticFeedback.mediumImpact();

      await _logSecurityEvent(
        type: 'admin_hold_triggered',
        severity: 'info',
        details: 'Hidden admin gesture triggered from login screen',
      );

      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminLoginScreen(),
          settings: const RouteSettings(name: '/admin-login'),
        ),
      );
    } catch (e) {
      _secureLog('Admin nav error: $e');
    } finally {
      _adminNavigating = false;
    }
  }

  Widget _wrapWithHiddenAdmin({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleAdminHoldStart(),
      onTapUp: (_) => _handleAdminHoldEnd(),
      onTapCancel: _handleAdminHoldEnd,
      onLongPressStart: (_) => _handleAdminHoldStart(),
      onLongPressEnd: (_) => _handleAdminHoldEnd(),
      onLongPressCancel: _handleAdminHoldEnd,
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 DEVICE FINGERPRINT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadDeviceFingerprint() async {
    try {
      final binding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
      if (mounted) setState(() => _deviceFingerprint = binding);
    } catch (e) {
      _secureLog('⚠️ [Security] Fingerprint error: $e');
      if (mounted) setState(() => _deviceFingerprint = 'unknown');
    }
  }

  void _startPinLockoutCountdown() {
    _pinLockoutTimer?.cancel();
    _pinLockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_pinLockoutUntil == null ||
          _pinLockoutUntil!.isBefore(DateTime.now())) {
        timer.cancel();
        setState(() {
          _pinLockoutUntil = null;
          _memLockoutUntil = null;
          _pinFailedAttempts = 0;
          _activeBackoff = null;
        });
        SecurityHardeningService.instance.resetFailures();
        return;
      }
      setState(() {});
    });
  }

  String _remainingLockoutText() {
    if (_pinLockoutUntil == null) return '';
    final diff = _pinLockoutUntil!.difference(DateTime.now());
    if (diff.isNegative) return '0:00';
    if (diff.inHours > 0) {
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60);
      return '${h}h ${m}m';
    }
    final m = diff.inMinutes;
    final s = diff.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
    String? employeeId,
  }) async {
    try {
      if (!_isOnline) return;

      final hashDevice = _deviceFingerprint != null
          ? _sha256Hex(_deviceFingerprint!)
          : null;

      await FirebaseFirestore.instance
          .collection('security_events')
          .add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': employeeId,
        'sessionNonce': _sessionNonce,
        'deviceHash': hashDevice,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('⚠️ Security log error: $e');
    }
  }

  bool _isRateLimited() {
    if (_lastPinAttemptAt == null) return false;
    final elapsed =
        DateTime.now().difference(_lastPinAttemptAt!).inMilliseconds;
    return elapsed < _pinRateLimitMs;
  }

  bool _isWeakPin(String pin) => _weakPins.contains(pin);

  bool _isEmployeeLoginable(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toLowerCase().trim();
    final isActive = data['isActive'];

    const blocked = {
      'suspended',
      'terminated',
      'deleted',
      'blocked',
      'archived',
    };
    if (blocked.contains(status)) {
      _secureLog('🚫 [Login check] Blocked status: $status');
      return false;
    }

    if (isActive == true) return true;

    if (status.isEmpty ||
        status == 'active' ||
        status == 'online' ||
        status == 'offline' ||
        status == 'inactive') {
      return true;
    }

    return false;
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
    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
    });
    await _checkNetworkOnEntry();
  }

  Future<void> _preloadLastEmployee() async {
    final lastId = await _getLastEmployeeId();

    if (lastId == null || lastId.isEmpty) {
      if (mounted) setState(() => _hasActiveMeeting = false);
      return;
    }
    final emp = await _loadEmployeeById(lastId);
    if (emp != null && mounted) {
      setState(() => _activeEmployee = emp);
      await _checkActiveMeeting();
    } else {
      if (mounted) setState(() => _hasActiveMeeting = false);
    }
  }

  Future<void> _checkActiveMeeting() async {
    if (!_clientMeetingEnabled) {
      if (mounted) {
        setState(() {
          _hasActiveMeeting = false;
          _checkingActiveMeeting = false;
        });
      }
      return;
    }

    final emp = _activeEmployee;
    if (emp == null) {
      if (mounted) {
        setState(() {
          _hasActiveMeeting = false;
          _checkingActiveMeeting = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _checkingActiveMeeting = true);

    try {
      final assignment = await ClientMeetingAssignmentService.instance
          .getActiveAssignmentForEmployee(emp.id)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _hasActiveMeeting = assignment != null;
        _checkingActiveMeeting = false;
      });
    } catch (e) {
      _secureLog('❌ [MeetingCheck] ERROR: $e');
      if (mounted) {
        setState(() {
          _hasActiveMeeting = false;
          _checkingActiveMeeting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _pinInput = '';

    _shakeController.dispose();
    _fadeController.dispose();
    _modalController.dispose();
    _nfcPulseController.dispose();
    _clockTimer?.cancel();
    _successCloseTimer?.cancel();
    _meetingRefreshTimer?.cancel();
    _positionSub?.cancel();
    _networkSub?.cancel();
    _overlayDelayTimer?.cancel();
    _pinLockoutTimer?.cancel();
    _adminHoldTimer?.cancel();
    _releaseCamera();
    if (!kIsWeb) {
      try {
        NfcManager.instance.stopSession();
      } catch (_) {}
    }

    SecurityHardeningService.instance.disableSecureScreen();

    super.dispose();
  }

  Future<void> _saveLastEmployeeId(String empId) async {
    if (empId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEmployeeIdKey, empId);
    } catch (e) {
      _secureLog('⚠️ [Prefs] Save failed: $e');
    }
  }

  Future<String?> _getLastEmployeeId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLastEmployeeIdKey);
    } catch (e) {
      return null;
    }
  }

  Future<void> _checkCapabilities() async {
    if (kIsWeb) {
      if (mounted) setState(() => _nfcAvailable = false);
      return;
    }
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (e) {
      _secureLog('NFC check error: $e');
    }
  }

  Future<bool> _ensureLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  void _startLocationTracking() {
    _positionSub?.cancel();
    if (mounted) {
      setState(() {
        _loadingLocation = true;
        _currentPlaceName = 'Getting location…';
      });
    }
    _getCurrentPositionOnce();
    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).listen((Position pos) {
        _updatePosition(pos);
      }, onError: (e) {
        _secureLog('⚠️ Position stream error: $e');
      });
    } catch (e) {
      _secureLog('⚠️ Position stream init failed: $e');
    }
  }

  Future<void> _getCurrentPositionOnce() async {
    try {
      final ok = await _ensureLocationPermission();
      if (!ok) {
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _currentPlaceName = 'Location unavailable';
          });
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
      await _updatePosition(pos);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
          if (_currentPlaceName == 'Getting location…') {
            _currentPlaceName = 'Location unavailable';
          }
        });
      }
    }
  }

  Future<void> _updatePosition(Position pos) async {
    if (!mounted) return;
    if (pos.latitude == 0 && pos.longitude == 0) return;

    bool isMocked = false;
    if (!kIsWeb) {
      try {
        isMocked = (pos as dynamic).isMocked ?? false;
      } catch (_) {}
    }

    final accuracy = pos.accuracy;

    if (isMocked) {
      _secureLog('🚨 [ANTI-FRAUD] MOCK GPS DETECTED!');
      await _logSecurityEvent(
        type: 'mock_gps_detected',
        severity: 'critical',
        details: 'Mock GPS location detected during login',
      );
    }

    setState(() {
      _currentLatitude = pos.latitude;
      _currentLongitude = pos.longitude;
      _currentAccuracy = accuracy;
      _isMockedGps = isMocked;
      _locationTimestamp = DateTime.now();
      _loadingLocation = false;
    });

    await _reverseGeocode(pos.latitude, pos.longitude);
    _validateClientLocation(pos.latitude, pos.longitude);
  }

  Future<void> _validateClientLocation(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _validatingClient = true);

    try {
      final match = await ClientLocationService.instance
          .validateLocation(lat: lat, lng: lng)
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      setState(() {
        _clientMatch = match;
        _validatingClient = false;
      });
    } catch (e) {
      if (mounted) setState(() => _validatingClient = false);
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty || !mounted) return;
      final p = placemarks.first;
      final subLocality = (p.subLocality ?? '').trim();
      final locality = (p.locality ?? '').trim();
      final subAdmin = (p.subAdministrativeArea ?? '').trim();
      final admin = (p.administrativeArea ?? '').trim();
      final street = (p.street ?? '').trim();
      final name = (p.name ?? '').trim();
      String placeName = '';
      if (subLocality.isNotEmpty &&
          locality.isNotEmpty &&
          subLocality != locality) {
        placeName = '$subLocality, $locality';
      } else if (locality.isNotEmpty) {
        placeName = locality;
      } else if (subAdmin.isNotEmpty) {
        placeName = subAdmin;
      } else if (admin.isNotEmpty) {
        placeName = admin;
      } else if (subLocality.isNotEmpty) {
        placeName = subLocality;
      } else if (street.isNotEmpty) {
        placeName = street;
      } else if (name.isNotEmpty) {
        placeName = name;
      } else {
        placeName = 'Unknown location';
      }
      if (!mounted) return;
      setState(() => _currentPlaceName = placeName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _currentPlaceName = 'Location unavailable');
    }
  }

  String get _locationDisplay {
    if (_loadingLocation) return 'Getting location…';
    return _currentPlaceName;
  }

  void _stopLocationTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    if (mounted) {
      setState(() {
        _loadingLocation = false;
        _currentLatitude = null;
        _currentLongitude = null;
        _locationTimestamp = null;
        _currentPlaceName = 'Getting location…';
        _currentAccuracy = null;
        _isMockedGps = false;
        _clientMatch = null;
        _validatingClient = false;
      });
    }
  }

  Future<void> _ensureFreshLocation() async {
    final age = _locationTimestamp != null
        ? DateTime.now().difference(_locationTimestamp!).inSeconds
        : 999;

    if (age < 30 && _currentLatitude != null && _currentLongitude != null) {
      return;
    }

    try {
      final ok = await _ensureLocationPermission();
      if (!ok) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      await _updatePosition(pos);
    } catch (e) {
      _secureLog('⚠️ [Location] Refresh failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 NFC
  // ═══════════════════════════════════════════════════════════════
  Future<void> _startNfcSession() async {
    if (kIsWeb) {
      _setError(
          'NFC is not available on web browsers. Please use PIN instead.');
      return;
    }

    if (!_isOnline) {
      _setError('No internet. A connection is required for NFC login.');
      return;
    }

    if (_deviceCompromised) {
      _setError('This device is flagged as compromised. NFC login blocked.');
      return;
    }

    final backoff =
    await SecurityHardeningService.instance.getActiveBackoff();
    if (backoff != null) {
      _setError(
          'Too many attempts. Try again in ${_remainingLockoutText()}.');
      return;
    }

    try {
      await NfcManager.instance.stopSession();
      NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_isLoading) return;
          final serial = _extractTagId(tag);
          if (serial == null) {
            _setError('Could not read keyfob ID.');
            return;
          }
          if (mounted) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          }
          try {
            final employee = await _findEmployeeByNfc(serial);
            if (employee != null) {
              await NfcManager.instance.stopSession();
              await SecurityHardeningService.instance.resetFailures();
              await _openSession(employee);
            } else {
              await NfcManager.instance.stopSession();

              final delay = await SecurityHardeningService.instance
                  .registerFailure();
              await _logSecurityEvent(
                type: 'nfc_unknown_tag',
                severity: 'medium',
                details:
                'Unknown NFC tag hash=${_sha256Hex(serial).substring(0, 16)}…',
              );

              if (delay > Duration.zero) {
                if (mounted) {
                  setState(() {
                    _pinLockoutUntil = DateTime.now().add(delay);
                    _memLockoutUntil = _pinLockoutUntil;
                    _startPinLockoutCountdown();
                  });
                }
                _setError(
                    'Keyfob not registered. Locked for ${_remainingLockoutText()}.');
              } else {
                _setError('Keyfob not registered. Contact your Admin.');
              }
            }
          } catch (e) {
            _setError('NFC login error: $e');
          }
        },
      );
    } catch (e) {
      _secureLog('NFC session error: $e');
    }
  }

  Future<Employee?> _findEmployeeByNfc(String serial) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('nfcTagId', isEqualTo: serial)
          .limit(5)
          .get();

      if (snap.docs.isEmpty) return null;

      for (final doc in snap.docs) {
        if (_isEmployeeLoginable(doc.data())) {
          return _docToEmployee(doc);
        }
      }
      return null;
    } catch (e) {
      _secureLog('_findEmployeeByNfc error: $e');
      return null;
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String key) {
        final tech = tagMap[key] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        if (raw is List) return raw.cast<int>();
        return null;
      }
      final id = tryKey('nfca') ??
          tryKey('nfcb') ??
          tryKey('nfcf') ??
          tryKey('nfcv') ??
          tryKey('isodep') ??
          tryKey('mifare-classic') ??
          tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔑 PASSWORD CHANGE REQUEST
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showPasswordChangeRequestDialog() async {
    if (!_isOnline) {
      _setError('No internet. Please check your connection.');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final empIdCtrl = TextEditingController(
      text: _activeEmployee?.employeeId ?? _activeEmployee?.id ?? '',
    );
    final reasonCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_reset_rounded,
                    color: _orange, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Request Password Change',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                  'Submit a request to Admin/HR to reset your password or PIN.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? const Color(0xFFB0B0B0)
                        : const Color(0xFF71717A),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: empIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Employee ID / Email',
                    hintText: 'e.g. EMP-001 or juan@company.com',
                    prefixIcon:
                    const Icon(Icons.badge_outlined, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  enabled: !submitting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g. I forgot my PIN',
                    prefixIcon:
                    const Icon(Icons.notes_rounded, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    isDense: true,
                  ),
                  enabled: !submitting,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF71717A))),
            ),
            FilledButton.icon(
              onPressed: submitting
                  ? null
                  : () async {
                final empId = empIdCtrl.text.trim();
                if (empId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text('Please enter your Employee ID')),
                  );
                  return;
                }

                setDlg(() => submitting = true);

                final ok = await _submitPasswordChangeRequest(
                  employeeIdentifier: empId,
                  reason: reasonCtrl.text.trim(),
                );

                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (ok) {
                  _showRequestSuccessDialog(empId);
                }
              },
              icon: submitting
                  ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(submitting ? 'Sending…' : 'Send Request'),
              style: FilledButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    empIdCtrl.dispose();
    reasonCtrl.dispose();
  }

  Future<bool> _submitPasswordChangeRequest({
    required String employeeIdentifier,
    required String reason,
  }) async {
    try {
      final fs = FirebaseFirestore.instance;
      Map<String, dynamic>? empData;
      String? empDocId;

      var snap = await fs
          .collection('employees')
          .where('employeeId', isEqualTo: employeeIdentifier)
          .limit(1)
          .get();

      if (snap.docs.isEmpty && employeeIdentifier.contains('@')) {
        snap = await fs
            .collection('employees')
            .where('email',
            isEqualTo: employeeIdentifier.toLowerCase())
            .limit(1)
            .get();
      }

      if (snap.docs.isEmpty) {
        try {
          final doc = await fs
              .collection('employees')
              .doc(employeeIdentifier)
              .get();
          if (doc.exists) {
            empDocId = doc.id;
            empData = doc.data();
          }
        } catch (_) {}
      }

      if (empDocId == null && snap.docs.isNotEmpty) {
        empDocId = snap.docs.first.id;
        empData = snap.docs.first.data();
      }

      final empName = empData != null
          ? (empData['name'] ??
          '${empData['firstName'] ?? ''} ${empData['lastName'] ?? ''}')
          .toString()
          .trim()
          : employeeIdentifier;

      final empEmail = (empData?['email'] ?? '').toString();

      final reqRef = await fs.collection('password_change_requests').add({
        'employeeId': empDocId,
        'employeeIdentifier': employeeIdentifier,
        'employeeName': empName,
        'employeeEmail': empEmail,
        'reason': reason.isEmpty ? 'No reason provided' : reason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'sessionNonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'deviceHash': _deviceFingerprint != null
            ? _sha256Hex(_deviceFingerprint!)
            : null,
      });

      await fs.collection('admin_notifications').add({
        'type': 'password_change',
        'title': '🔐 Password Change Request',
        'message':
        '$empName ($employeeIdentifier) is requesting a password/PIN reset.'
            '${reason.isNotEmpty ? " Reason: $reason" : ""}',
        'employeeId': empDocId,
        'employeeName': empName,
        'employeeIdentifier': employeeIdentifier,
        'priority': 'high',
        'read': false,
        'requestId': reqRef.id,
        'metadata': {
          'requestId': reqRef.id,
          'reason': reason,
          'employeeIdentifier': employeeIdentifier,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _logSecurityEvent(
        type: 'password_change_requested',
        severity: 'medium',
        details:
        'Password change requested for "$employeeIdentifier" (reqId=${reqRef.id})',
        employeeId: empDocId,
      );

      if (!kIsWeb) HapticFeedback.mediumImpact();
      return true;
    } catch (e) {
      _secureLog('❌ [PasswordRequest] Failed: $e');
      _setError('Failed to send request. Please try again.');
      return false;
    }
  }

  void _showRequestSuccessDialog(String empId) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 32),
            ),
            const SizedBox(height: 16),
            const Text(
              'Request Sent!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your password change request has been sent to Admin/HR.\n\n'
                  'Please wait for their approval.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: Color(0xFF71717A)),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('OK',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 HARDENED PIN LOGIN
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    if (_loggingIn) return;

    if (!kIsWeb && _deviceCompromised) {
      _setError('This device is flagged as compromised. Login blocked.');
      await _logSecurityEvent(
        type: 'blocked_compromised_device',
        severity: 'critical',
        details:
        SecurityHardeningService.instance.integrityIssues.join(','),
      );
      return;
    }

    final backoff =
    await SecurityHardeningService.instance.getActiveBackoff();
    if (backoff != null) {
      _setError(
          'Too many attempts. Try again in ${_remainingLockoutText()}.');
      return;
    }

    if (_isRateLimited()) {
      _secureLog('🚦 [Security] Rate limited — too fast');
      return;
    }

    if (!_isOnline) {
      _setError('No internet. Please check your connection before logging in.');
      return;
    }

    _loggingIn = true;
    _lastPinAttemptAt = DateTime.now();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pin = _pinInput.trim();
      final weak = _isWeakPin(pin);

      Employee? employee = await _findEmployeeByPin(pin);

      if (employee == null && !kIsWeb) {
        final localEmployees =
        await DatabaseService.instance.getAllEmployees();
        for (final emp in localEmployees) {
          final valid =
          await SecurityService.instance.verifyPin(emp.id, pin);
          if (valid) {
            employee = emp;
            break;
          }
        }
      }

      if (employee == null) {
        _pinFailedAttempts++;

        final delay =
        await SecurityHardeningService.instance.registerFailure();
        final failCount =
        await SecurityHardeningService.instance.getFailureCount();

        await _logSecurityEvent(
          type: 'pin_failed',
          severity: failCount >= 3 ? 'high' : 'medium',
          details: 'Failed PIN attempt #$failCount'
              '${weak ? " (weak pattern)" : ""}',
        );

        if (delay > Duration.zero) {
          if (mounted) {
            setState(() {
              _pinLockoutUntil = DateTime.now().add(delay);
              _memLockoutUntil = _pinLockoutUntil;
              _startPinLockoutCountdown();
            });
          }
          throw 'Too many failed attempts. Account locked for '
              '${_remainingLockoutText()}.';
        }

        final remaining = _maxPinAttempts - _pinFailedAttempts;
        if (remaining <= 2 && remaining > 0) {
          throw 'Invalid PIN. ⚠️ $remaining attempt(s) left before lockout.';
        }
        throw 'Invalid PIN. Please try again.';
      }

      _pinFailedAttempts = 0;
      await SecurityHardeningService.instance.resetFailures();
      await _saveLastEmployeeId(employee.id);

      try {
        await SecurityHardeningService.instance
            .issueSessionToken(employee.id);
      } catch (e) {
        _secureLog('⚠️ [Security] Session token issue failed: $e');
      }

      await _logSecurityEvent(
        type: 'pin_success',
        severity: 'info',
        details: 'Successful PIN login${weak ? " (weak pattern)" : ""}',
        employeeId: employee.id,
      );

      if (_clientMeetingMode) {
        _activeEmployee = employee;
        try {
          await SecurityService.instance.createSession(employee.id);
        } catch (e) {
          _secureLog('⚠️ [ClientMeeting] createSession failed: $e');
        }
        if (!kIsWeb) {
          try {
            LocationTrackingService.instance.startTracking(employee.id);
          } catch (e) {
            _secureLog('⚠️ [ClientMeeting] startTracking failed: $e');
          }
        }
        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(employee.id)
              .update({
            'isOnline': true,
            'isLoggedIn': true,
            'isActive': true,
            'status': 'active',
            'lastLogin': FieldValue.serverTimestamp(),
            'lastActive': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          _secureLog('⚠️ [Presence] Failed: $e');
        }
        try {
          await FirebaseFirestore.instance.collection('activity_logs').add({
            'type': 'client_meeting_login',
            'employeeId': employee.id,
            'employee_id': employee.id,
            'employee_name': employee.fullName,
            'email': employee.email,
            'role': employee.position,
            'assignment_id': _activeAssignment?.id,
            'session_nonce': _sessionNonce,
            'timestamp': FieldValue.serverTimestamp(),
            'device': kIsWeb ? 'Web Browser' : 'Mobile App',
          });
        } catch (e) {
          _secureLog('⚠️ [ClientMeeting] login audit log failed: $e');
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
            _pinInput = '';
            _errorMessage = null;
            _clientMeetingMode = false;
          });
        }
        _goToStep(_LoginStep.clientMeeting);
        return;
      }

      await _openSession(employee);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
          _pinInput = '';
        });
        _shakeController.forward(from: 0);
      }
    } finally {
      _loggingIn = false;
    }
  }

  Future<Employee?> _findEmployeeByPin(String pin) async {
    try {
      final cleanPin = pin.trim();
      final lookup =
      SecurityHardeningService.instance.pinLookupHash(cleanPin);

      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('pinLookupHash', isEqualTo: lookup)
          .limit(5)
          .get();

      if (snap.docs.isNotEmpty) {
        for (final doc in snap.docs) {
          if (!_isEmployeeLoginable(doc.data())) continue;

          final data = doc.data();
          final salt = data['pinSalt'] as String?;
          final hash = data['pinHash'] as String?;

          if (salt != null && hash != null) {
            final ok = await SecurityHardeningService.instance
                .verifyPinAsync(cleanPin, salt, hash);
            if (!ok) continue;
          }

          final employee = _docToEmployee(doc);
          if (!kIsWeb) {
            try {
              await DatabaseService.instance.insertEmployee(employee);
            } catch (_) {}
          }
          return employee;
        }
      }

      _secureLog('⚠️ [PIN Query] Falling back to legacy plaintext lookup');
      final legacy = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: cleanPin)
          .limit(5)
          .get();

      for (final doc in legacy.docs) {
        if (_isEmployeeLoginable(doc.data())) {
          await _logSecurityEvent(
            type: 'legacy_pin_used',
            severity: 'high',
            details:
            'Employee ${doc.id} used a legacy plaintext PIN — MIGRATE NOW',
            employeeId: doc.id,
          );
          final employee = _docToEmployee(doc);
          if (!kIsWeb) {
            try {
              await DatabaseService.instance.insertEmployee(employee);
            } catch (_) {}
          }
          return employee;
        }
      }

      final pinInt = int.tryParse(cleanPin);
      if (pinInt != null) {
        _secureLog('⚠️ [PIN Query] Trying legacy numeric pin ($pinInt)');
        final legacyInt = await FirebaseFirestore.instance
            .collection('employees')
            .where('pin', isEqualTo: pinInt)
            .limit(5)
            .get();

        for (final doc in legacyInt.docs) {
          if (_isEmployeeLoginable(doc.data())) {
            await _logSecurityEvent(
              type: 'legacy_pin_used',
              severity: 'high',
              details:
              'Employee ${doc.id} used a legacy NUMERIC PIN — MIGRATE NOW',
              employeeId: doc.id,
            );
            final employee = _docToEmployee(doc);
            if (!kIsWeb) {
              try {
                await DatabaseService.instance.insertEmployee(employee);
              } catch (_) {}
            }
            return employee;
          }
        }
      }

      return null;
    } catch (e) {
      _secureLog('❌ _findEmployeeByPin error: $e');
      return null;
    }
  }

  Future<Employee?> _loadEmployeeById(String empId) async {
    if (empId.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empId)
          .get();
      if (!doc.exists) return null;
      return _docToEmployee(doc);
    } catch (e) {
      return null;
    }
  }

  Employee _docToEmployee(dynamic doc) {
    final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final String docId = doc.id as String;
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final fullName = data['name'] ?? '$firstName $lastName'.trim();

    return Employee.fromMap({
      'id': docId,
      'employee_id': data['employeeId'] ?? docId,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'email': data['email'] ?? '',
      'role': data['role'] ?? 'Employee',
      'department': data['role'] ?? data['department'] ?? '',
      'position': data['role'] ?? data['position'] ?? '',
      'phone': data['phone'],
      'photo_path': data['photoPath'],
      'photo_url': data['photoUrl'],
      'face_embedding': data['faceEmbedding'],
      'fingerprint_hash': data['fingerprintHash'],
      'pin_hash': null,
      'pin_salt': null,
      'nfc_tag_id': data['nfcTagId'],
      'is_active': data['status'] == 'active' ? 1 : 0,
      'created_at': (data['createdAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
      'updated_at': (data['updatedAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
    });
  }

  Future<void> _signIntoFirebaseAuth(Employee employee) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employee.id)
          .get();
      final data = snap.data();
      final email = (data?['email'] as String? ?? '').trim();
      final password = (data?['password'] as String? ?? '').trim();
      final existingAuthUid = (data?['authUid'] as String? ?? '').trim();

      if (email.isEmpty || password.isEmpty) {
        _secureLog('⚠️ [Auth] No email/password for ${employee.id}');
        return;
      }

      if (currentUser != null &&
          existingAuthUid.isNotEmpty &&
          currentUser.uid == existingAuthUid) {
        _secureLog('✅ [Auth] Already signed in as $existingAuthUid');
        return;
      }

      try {
        final cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        _secureLog('✅ [Auth] Signed in: ${cred.user?.uid}');

        if (cred.user != null && existingAuthUid != cred.user!.uid) {
          try {
            await FirebaseFirestore.instance
                .collection('employees')
                .doc(employee.id)
                .update({'authUid': cred.user!.uid});
          } catch (e) {
            _secureLog('⚠️ [Auth] Failed to save authUid: $e');
          }
        }
        return;
      } catch (signInErr) {
        final code = signInErr is FirebaseAuthException ? signInErr.code : '';
        _secureLog('⚠️ [Auth] Sign-in failed ($code), trying create...');

        if (_notFoundCodes.contains(code)) {
          try {
            final cred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(
                email: email, password: password);
            _secureLog('✅ [Auth] Created: ${cred.user?.uid}');
            final uid = cred.user?.uid ?? '';
            if (uid.isNotEmpty) {
              try {
                await FirebaseFirestore.instance
                    .collection('employees')
                    .doc(employee.id)
                    .update({'authUid': uid});
              } catch (e) {
                _secureLog('⚠️ [Auth] Failed to save authUid: $e');
              }
            }
            return;
          } catch (createErr) {
            _secureLog('❌ [Auth] Create failed: $createErr');
          }
        }
      }
    } catch (e) {
      _secureLog('❌ [Auth] Outer error: $e');
    }
  }

  Future<void> _savePreAuth(Employee employee) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fp_preauth_employee_id', employee.id);
      await prefs.setInt(
        'fp_preauth_time',
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setString('fp_preauth_nonce', _sessionNonce);
      _secureLog('✅ [PreAuth] Saved for ${employee.id}');
    } catch (e) {
      _secureLog('⚠️ [PreAuth] Save failed: $e');
    }
  }

  Future<void> _openSession(Employee employee) async {
    try {
      if (_sessionNonce.length < 16) {
        throw StateError('Session nonce invalid');
      }

      _activeEmployee = employee;
      await _saveLastEmployeeId(employee.id);

      // ═══════════════════════════════════════════════════════════
      // 🆕 START NOTIFICATION LISTENER (para sa auto PIN notification)
      // ═══════════════════════════════════════════════════════════
      try {
        await EmployeeNotificationListener.instance.start(employee.id);
        _secureLog('✅ [NotifListener] Started for ${employee.id}');
      } catch (e) {
        _secureLog('⚠️ [NotifListener] Start failed: $e');
      }

      // 🆕 FCM token association (para sa future push, kung may FCM na)
      try {
        await FcmService.instance.associateWithEmployee(employee.id);
        _secureLog('✅ [FCM] Token associated with ${employee.id}');
      } catch (e) {
        _secureLog('⚠️ [FCM] Associate failed: $e');
      }

      try {
        await SecurityHardeningService.instance
            .issueSessionToken(employee.id);
      } catch (e) {
        _secureLog('⚠️ [Security] Session token issue failed: $e');
      }

      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      await _signIntoFirebaseAuth(employee);

      final deviceBinding =
      await SecurityHardeningService.instance.getDeviceBindingToken();

      try {
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(employee.id)
            .update({
          'isOnline': true,
          'isLoggedIn': true,
          'isActive': true,
          'status': 'active',
          'lastLogin': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
          'lastDeviceBinding': deviceBinding,
        });
      } catch (presenceErr) {
        _secureLog('⚠️ [Presence] Failed: $presenceErr');
      }

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'login',
          'employeeId': employee.id,
          'employee_id': employee.id,
          'employee_name': employee.fullName,
          'email': employee.email,
          'role': employee.position,
          'arrival_time': Timestamp.fromDate(_arrivalTime),
          'session_nonce': _sessionNonce,
          'device_binding': deviceBinding,
          'timestamp': FieldValue.serverTimestamp(),
          'device': kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } catch (logErr) {
        _secureLog('Activity log error: $logErr');
      }

      await _savePreAuth(employee);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BiometricMethodScreen(
            employee: employee,
            arrivalTime: _arrivalTime,
            mode: BiometricFlowMode.login,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Session error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    if (_isPinLockedOut) {
      _setError('Locked. Try again in ${_remainingLockoutText()}.');
      return;
    }

    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(
                () => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
      }
    } else if (_pinInput.length < 4) {
      setState(() => _pinInput += key);
      if (_pinInput.length == 4) {
        final delay = 200 + math.Random.secure().nextInt(150);
        Future.delayed(Duration(milliseconds: delay), () {
          if (mounted) _loginWithPin();
        });
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
        _pinInput = '';
      });
      _shakeController.forward(from: 0);
    }
  }

  void _goToStep(_LoginStep step) {
    if (step == _LoginStep.nfcWait && kIsWeb) {
      _setError('NFC is not available on web. Please use PIN instead.');
      return;
    }
    if (step == _LoginStep.clientMeeting && !_clientMeetingEnabled) {
      _setError('Client Meeting login is coming soon.');
      return;
    }
    setState(() {
      _step = step;
      _errorMessage = null;
      _pinInput = '';
      _captureSuccess = false;
    });
    _modalController.forward(from: 0);
    if (step == _LoginStep.nfcWait) _startNfcSession();
    if (step == _LoginStep.clientMeeting) {
      _useFrontCamera = true;
      _startCameraSession();
      _startClockTimer();
      _startLocationTracking();
    }
  }

  void _goBack() {
    if (_step == _LoginStep.selectMethod) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LandingScreen()));
    } else {
      if (_step == _LoginStep.nfcWait && !kIsWeb) {
        try {
          NfcManager.instance.stopSession();
        } catch (_) {}
      }
      if (_step == _LoginStep.clientMeeting) {
        _clockTimer?.cancel();
        _successCloseTimer?.cancel();
        _releaseCamera();
        _stopLocationTracking();
        _useFrontCamera = true;
      }
      _modalController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _step = _LoginStep.selectMethod;
            _errorMessage = null;
            _pinInput = '';
            _captureSuccess = false;
            _clientMeetingMode = false;
            _activeAssignment = null;
          });
          _checkActiveMeeting();
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CLIENT MEETING LOGIN
  // ═══════════════════════════════════════════════════════════════
  Future<void> _onClientMeetingLogin() async {
    if (!_clientMeetingEnabled) {
      _setError('Client Meeting login is coming soon.');
      return;
    }

    if (_deviceCompromised) {
      _setError('This device is flagged as compromised. Login blocked.');
      return;
    }

    if (!_isOnline) {
      _showBlockedDialog(
        title: 'No Internet',
        icon: Icons.wifi_off_rounded,
        iconColor: Colors.red,
        message:
        'An internet connection is required to check your assignment.',
      );
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    Employee? resolved = _activeEmployee;

    if (resolved == null) {
      try {
        final secId = await SecurityService.instance.getCurrentEmployeeId();
        if (secId != null && secId.isNotEmpty) {
          resolved = await _loadEmployeeById(secId);
        }
      } catch (e) {
        _secureLog('⚠️ [ClientMeeting] SecurityService lookup failed: $e');
      }
    }

    if (resolved == null) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('authUid', isEqualTo: authUser.uid)
              .limit(1)
              .get();

          if (snap.docs.isNotEmpty) {
            resolved = _docToEmployee(snap.docs.first);
          } else if (authUser.email != null) {
            final emailSnap = await FirebaseFirestore.instance
                .collection('employees')
                .where('email',
                isEqualTo: authUser.email!.toLowerCase())
                .limit(1)
                .get();
            if (emailSnap.docs.isNotEmpty) {
              resolved = _docToEmployee(emailSnap.docs.first);
            }
          }
        } catch (e) {
          _secureLog('⚠️ [ClientMeeting] FirebaseAuth lookup failed: $e');
        }
      }
    }

    if (resolved == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showBlockedDialog(
        title: 'Not Logged In',
        icon: Icons.lock_rounded,
        iconColor: Colors.orange,
        message:
        'Please log in first using your PIN or Key Fob before accessing '
            'Client Meeting check-in.',
      );
      return;
    }

    try {
      await _signIntoFirebaseAuth(resolved);
    } catch (e) {
      _secureLog('⚠️ [ClientMeeting] Pre-auth sign-in failed: $e');
    }

    await _checkAssignmentAndProceed(resolved);
  }

  Future<void> _checkAssignmentAndProceed(Employee employee) async {
    try {
      final empId = employee.id;
      final assignment = await ClientMeetingAssignmentService.instance
          .getActiveAssignmentForEmployee(empId)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (assignment == null) {
        setState(() {
          _isLoading = false;
          _activeEmployee = employee;
          _hasActiveMeeting = false;
        });
        await _showBlockedDialog(
          title: 'No Client Meeting Scheduled',
          icon: Icons.lock_rounded,
          iconColor: Colors.orange,
          message: 'You don\'t have a scheduled client meeting right now.\n\n'
              'Admin or HR must assign you a client meeting before you can '
              'log one.\n\n'
              '📞 Please contact HR/Admin to request an assignment.',
        );
        return;
      }

      setState(() {
        _activeEmployee = employee;
        _hasActiveMeeting = true;
      });

      _showValidatingDialog();

      final validation =
      await _validateClientMeetingPreconditions(assignment);

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!validation.allOk) {
        await _showValidationFailedDialog(validation, assignment);
        return;
      }

      final confirmed = await _showAssignmentConfirmDialog(assignment);
      if (confirmed != true) {
        setState(() => _isLoading = false);
        return;
      }

      _activeAssignment = assignment;
      await _startClientMeetingFor(employee, assignment);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _activeEmployee = employee;
        _hasActiveMeeting = false;
      });
      _showBlockedDialog(
        title: 'Error',
        icon: Icons.error_outline_rounded,
        iconColor: Colors.red,
        message: 'Unable to check the assignment. Please try again.\n\n$e',
      );
    }
  }

  Future<_ClientMeetingValidationResult> _validateClientMeetingPreconditions(
      ClientMeetingAssignment a) async {
    final now = DateTime.now();

    final scheduledDate = DateTime(
      a.scheduledStart.year,
      a.scheduledStart.month,
      a.scheduledStart.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    final dateOk = scheduledDate == today;

    Duration grace = const Duration(minutes: 15);
    try {
      final g = (a as dynamic).gracePeriod;
      if (g is Duration) grace = g;
    } catch (_) {}

    final windowStart = a.scheduledStart.subtract(grace);
    final windowEnd = a.scheduledEnd.add(grace);

    final timeOk = now.isAfter(windowStart) && now.isBefore(windowEnd);

    double? distance;
    bool locationOk = false;

    final hasClientCoords =
        a.clientLat.abs() > 0.0001 || a.clientLng.abs() > 0.0001;

    if (!hasClientCoords) {
      locationOk = true;
    } else {
      await _ensureFreshLocation();

      if (_currentLatitude != null && _currentLongitude != null) {
        if (_isMockedGps) {
          locationOk = false;
        } else {
          distance = Geolocator.distanceBetween(
            _currentLatitude!,
            _currentLongitude!,
            a.clientLat,
            a.clientLng,
          );
          locationOk = distance <= a.clientRadius;
        }
      } else {
        locationOk = false;
      }
    }

    return _ClientMeetingValidationResult(
      dateOk: dateOk,
      timeOk: timeOk,
      locationOk: locationOk,
      now: now,
      scheduledStart: a.scheduledStart,
      scheduledEnd: a.scheduledEnd,
      grace: grace,
      distanceMeters: distance,
      clientRadius: a.clientRadius,
    );
  }

  void _showValidatingDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
          isDark ? const Color(0xFF18181B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: _orange,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Verifying...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Checking date, time, and location',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showValidationFailedDialog(
      _ClientMeetingValidationResult v, ClientMeetingAssignment a) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    late String failReason;
    IconData failIcon = Icons.error_outline_rounded;
    Color failColor = Colors.red;

    if (!v.dateOk) {
      failReason =
      'Wrong date. The meeting is scheduled on ${a.dateLabel}, '
          'but today is ${_formatFullDate(v.now)}.';
      failIcon = Icons.calendar_today_rounded;
    } else if (!v.timeOk) {
      if (v.now.isBefore(v.scheduledStart.subtract(v.grace))) {
        final mins = v.scheduledStart.difference(v.now).inMinutes;
        failReason =
        'You are too early. The meeting starts at '
            '${_formatTimeOfDay(v.scheduledStart)}.\n\n'
            'About $mins more minutes before it begins.';
      } else {
        final mins = v.now.difference(v.scheduledEnd).inMinutes;
        failReason =
        'You are late. The meeting ended at '
            '${_formatTimeOfDay(v.scheduledEnd)}.\n\n'
            'You are $mins minutes late.';
      }
      failIcon = Icons.access_time_rounded;
      failColor = Colors.orange;
    } else if (!v.locationOk) {
      if (_isMockedGps) {
        failReason =
        'Mock / fake GPS is not allowed.\n\n'
            'Please turn off mock location in your device settings.';
        failIcon = Icons.warning_amber_rounded;
      } else if (v.distanceMeters != null) {
        failReason =
        'You are not at the client location.\n\n'
            'Your distance: ${v.distanceMeters!.toStringAsFixed(0)} meters\n'
            'Allowed radius: ${v.clientRadius.toStringAsFixed(0)} meters\n\n'
            'Move closer to ${a.clientName} before checking in.';
        failIcon = Icons.location_off_rounded;
      } else {
        failReason =
        'Unable to get your GPS location.\n\n'
            'Please turn on location services and try again.';
        failIcon = Icons.location_disabled_rounded;
      }
    } else {
      failReason = 'Unable to verify the assignment. Please try again.';
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor:
        isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: failColor.withValues(alpha: 0.15),
              ),
              child: Icon(failIcon, color: failColor, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'Cannot Check-In',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              failReason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark
                    ? const Color(0xFFB0B0B0)
                    : const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Column(
                children: [
                  _validationRow(
                    label: 'Date',
                    ok: v.dateOk,
                    detail: a.dateLabel,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _validationRow(
                    label: 'Time',
                    ok: v.timeOk,
                    detail: '${_formatTimeOfDay(v.scheduledStart)} → '
                        '${_formatTimeOfDay(v.scheduledEnd)}',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _validationRow(
                    label: 'Location',
                    ok: v.locationOk,
                    detail: v.distanceMeters != null
                        ? '${v.distanceMeters!.toStringAsFixed(0)}m / '
                        '${v.clientRadius.toStringAsFixed(0)}m'
                        : 'No GPS',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _validationRow({
    required String label,
    required bool ok,
    required String detail,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 16,
          color: ok ? Colors.green : Colors.red,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? const Color(0xFFB0B0B0)
                  : const Color(0xFF6B7280),
            ),
          ),
        ),
        Expanded(
          child: Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF1F2937),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatTimeOfDay(DateTime dt) {
    int h = dt.hour % 12;
    if (h == 0) h = 12;
    final hh = h.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ampm';
  }

  String _formatFullDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _showBlockedDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? const Color(0xFF18181B)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: iconColor.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF71717A),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showAssignmentConfirmDialog(
      ClientMeetingAssignment a) async {
    if (!mounted) return false;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor:
        isDark ? const Color(0xFF18181B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green.withValues(alpha: 0.15),
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.green, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Confirm Client Meeting',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(
              icon: Icons.business_rounded,
              label: 'Client',
              value: a.clientName,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.location_on_rounded,
              label: 'Address',
              value: a.clientAddress.isEmpty ? '—' : a.clientAddress,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: a.dateLabel,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.access_time_rounded,
              label: 'Time window',
              value: a.timeWindowLabel,
            ),
            const SizedBox(height: 8),
            _infoRow(
              icon: Icons.assignment_rounded,
              label: 'Purpose',
              value: a.purpose,
            ),
            if (a.notes != null && a.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(
                icon: Icons.notes_rounded,
                label: 'Notes',
                value: a.notes!,
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: _orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Make sure you are at the client location before '
                          'taking the snapshot. Your GPS will be validated.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFFB0B0B0)
                            : const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Proceed to Check-In'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: _orange),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF71717A),
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Future<void> _startClientMeetingFor(
      Employee employee, ClientMeetingAssignment assignment) async {
    _activeEmployee = employee;
    _activeAssignment = assignment;

    try {
      await _signIntoFirebaseAuth(employee);
    } catch (e) {
      _secureLog('⚠️ [ClientMeeting] Firebase Auth sign-in failed: $e');
    }

    try {
      await SecurityService.instance.createSession(employee.id);
    } catch (e) {
      _secureLog('⚠️ [ClientMeeting] createSession failed: $e');
    }
    if (!kIsWeb) {
      try {
        LocationTrackingService.instance.startTracking(employee.id);
      } catch (e) {
        _secureLog('⚠️ [ClientMeeting] startTracking failed: $e');
      }
    }

    // 🆕 Start notification listener din para sa client meeting
    try {
      await EmployeeNotificationListener.instance.start(employee.id);
      _secureLog('✅ [NotifListener] Started (client meeting)');
    } catch (e) {
      _secureLog('⚠️ [NotifListener] Start failed: $e');
    }

    try {
      await FcmService.instance.associateWithEmployee(employee.id);
      _secureLog('✅ [FCM] Token associated');
    } catch (e) {
      _secureLog('⚠️ [FCM] Associate failed: $e');
    }

    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employee.id)
          .update({
        'isOnline': true,
        'isLoggedIn': true,
        'isActive': true,
        'status': 'active',
        'lastLogin': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('⚠️ [Presence] Failed: $e');
    }

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type': 'client_meeting_login',
        'employeeId': employee.id,
        'employee_id': employee.id,
        'employee_name': employee.fullName,
        'email': employee.email,
        'role': employee.position,
        'assignment_id': assignment.id,
        'client_name': assignment.clientName,
        'session_nonce': _sessionNonce,
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (e) {
      _secureLog('⚠️ [ClientMeeting] audit log failed: $e');
    }

    await _savePreAuth(employee);

    if (!mounted) return;
    setState(() => _isLoading = false);
    _goToStep(_LoginStep.clientMeeting);
  }

  /// Safe cleanup — walang setState. Ginagamit sa dispose() at lifecycle.
  Future<void> _releaseCameraQuiet() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  /// Normal release — may setState. Ginagamit kapag buhay pa ang widget.
  Future<void> _releaseCamera() async {
    await _releaseCameraQuiet();
    if (!mounted) return;
    // Double-check na active pa ang element (hindi pa defunct)
    try {
      if (context.mounted) {
        setState(() {});
      }
    } catch (_) {
      // Silent — nangyayari lang ito kapag defunct na ang element
    }
  }

  Future<void> _startCameraSession() async {
    await _releaseCamera();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError(kIsWeb
            ? 'No camera detected. Please allow camera access in your browser.'
            : 'No camera found on this device.');
        return;
      }
      final selected = cameras.firstWhere(
            (c) =>
        c.lensDirection ==
            (_useFrontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      _secureLog('Camera init error: $e');
      _setError(kIsWeb
          ? 'Could not start camera. Please allow camera access and try again.'
          : 'Could not start camera. Check camera permission.');
    }
  }

  Future<void> _switchCamera() async {
    if (_isCapturing) return;
    setState(() {
      _useFrontCamera = !_useFrontCamera;
    });
    await _startCameraSession();
  }

  void _startClockTimer() {
    _clockTimer?.cancel();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _capturePhoto() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    if (!_isOnline) {
      _setError('⚠️ No internet. Please check your connection.');
      return;
    }

    if (_activeEmployee == null || _employeeId == null) {
      if (mounted) {
        setState(() => _isCapturing = false);
        _setError(
            'No logged-in employee. Please log in using PIN or Key Fob first.');
      }
      return;
    }

    if (_activeAssignment == null) {
      if (mounted) {
        setState(() => _isCapturing = false);
        _setError('No active assignment. Cancel and try again.');
      }
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final validation = await _validateClientMeetingPreconditions(
          _activeAssignment!);

      if (!validation.allOk) {
        if (mounted) setState(() => _isCapturing = false);
        await _showValidationFailedDialog(validation, _activeAssignment!);
        return;
      }

      final ok = await _ensureLocationPermission();
      if (ok) {
        try {
          final freshPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
          await _updatePosition(freshPos);
        } catch (e) {
          _secureLog('⚠️ Fresh position failed: $e');
        }
      }

      final photo = await controller.takePicture();

      if (_currentLatitude != null && _currentLongitude != null) {
        await _validateClientLocation(_currentLatitude!, _currentLongitude!);
      }

      await _saveClientMeetingLog(photoPath: photo.path);

      _clockTimer?.cancel();
      _stopLocationTracking();
      await _releaseCamera();
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _captureSuccess = true;
      });
      _successCloseTimer?.cancel();
      _successCloseTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _step == _LoginStep.clientMeeting && _captureSuccess) {
          _goBack();
        }
      });
    } catch (e) {
      _secureLog('Client meeting capture error: $e');
      if (mounted) setState(() => _isCapturing = false);
      _setError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _saveClientMeetingLog({required String photoPath}) async {
    String empId = _employeeId ?? '';
    String empName = _employeeName;
    String empEmail = _employeeEmail;

    if (empId.isEmpty) {
      try {
        final secId = await SecurityService.instance.getCurrentEmployeeId();
        if (secId != null && secId.isNotEmpty) {
          empId = secId;
          final emp = await _loadEmployeeById(secId);
          if (emp != null) {
            empName = emp.fullName;
            empEmail = emp.email;
          }
        }
      } catch (e) {
        _secureLog('⚠️ SecurityService lookup failed: $e');
      }
    }

    if (empId.isEmpty) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('authUid', isEqualTo: authUser.uid)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final emp = _docToEmployee(snap.docs.first);
            empId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
            empName = emp.fullName;
            empEmail = emp.email;
          }
        } catch (_) {}
      }
    }

    if (empId.isEmpty) {
      throw 'No logged-in employee.';
    }

    if (empName == 'Unknown' || empEmail.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get();
        if (doc.exists) {
          final d = doc.data()!;
          final fn = (d['firstName'] ?? '').toString();
          final ln = (d['lastName'] ?? '').toString();
          empName = (d['name'] ?? '$fn $ln').toString().trim();
          empEmail = (d['email'] ?? '').toString();
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final dateStr = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final locAgeSec = _locationTimestamp != null
        ? now.difference(_locationTimestamp!).inSeconds
        : null;

    final antiFraudFlags = <String>[];
    if (_isMockedGps) antiFraudFlags.add('mock_gps');
    if (_currentAccuracy != null && _currentAccuracy! > 200) {
      antiFraudFlags.add('low_accuracy');
    }
    if (locAgeSec != null && locAgeSec > 60) {
      antiFraudFlags.add('stale_location');
    }
    if (_currentLatitude == null || _currentLongitude == null) {
      antiFraudFlags.add('no_location');
    }
    if (_clientMatch != null && _clientMatch!.hasAnyRegisteredClient) {
      if (!_clientMatch!.isWithinRadius) {
        antiFraudFlags.add('outside_client_radius');
      }
    }
    if (_deviceCompromised) {
      antiFraudFlags.add('compromised_device');
    }

    final severity = _isMockedGps || _deviceCompromised
        ? 'critical'
        : antiFraudFlags.isEmpty
        ? 'clean'
        : antiFraudFlags.length >= 2
        ? 'high'
        : 'medium';

    final assignment = _activeAssignment;
    final deviceBinding =
    await SecurityHardeningService.instance.getDeviceBindingToken();

    final payload = <String, dynamic>{
      'employee_id': empId,
      'employeeId': empId,
      'employee_name': empName,
      'employee_email': empEmail,
      'type': 'client_meeting',
      'action': 'Client Meeting Clock In',
      'details': 'Client meeting — $_currentPlaceName',
      'description': 'Client meeting at $_currentPlaceName',
      'remarks': 'client_meeting',
      'date': dateStr,
      'time': timeStr,
      'photo_path': photoPath,
      'location_name': _currentPlaceName,
      'latitude': _currentLatitude,
      'longitude': _currentLongitude,
      'location_captured_at': _locationTimestamp != null
          ? Timestamp.fromDate(_locationTimestamp!)
          : null,
      'has_location': _currentLatitude != null && _currentLongitude != null,
      'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      'platform': kIsWeb ? 'web' : 'mobile',
      'zone_type': 'client_meeting',
      'status': 'pending_hr_approval',
      'payrollStatus': 'Pending',
      'assignment_id': assignment?.id,
      'assigned_client_name': assignment?.clientName,
      'assigned_scheduled_start': assignment != null
          ? Timestamp.fromDate(assignment.scheduledStart)
          : null,
      'assigned_scheduled_end': assignment != null
          ? Timestamp.fromDate(assignment.scheduledEnd)
          : null,
      'assigned_purpose': assignment?.purpose,
      'assigned_by': assignment?.assignedByName,
      'gps_accuracy_meters': _currentAccuracy,
      'gps_is_mocked': _isMockedGps,
      'gps_age_seconds': locAgeSec,
      'gps_device_platform': kIsWeb ? 'web' : 'mobile',
      'matched_client_id': _clientMatch?.nearestClient?.id,
      'matched_client_name': _clientMatch?.nearestClient?.name,
      'distance_from_client_m': _clientMatch?.distanceMeters,
      'is_verified_at_client': _clientMatch?.isVerified ?? false,
      'client_verdict': _clientMatch?.verdict ?? 'unknown',
      'anti_fraud_flags': antiFraudFlags,
      'anti_fraud_severity': severity,
      'device_binding': deviceBinding,
      'device_compromised': _deviceCompromised,
      'session_nonce': _sessionNonce,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final fs = FirebaseFirestore.instance;

    final attendanceRef =
    await fs.collection('attendance_logs').add(payload);

    try {
      await fs.collection('activity_logs').add(payload);
    } catch (e) {
      _secureLog('⚠️ activity_logs write skipped: $e');
    }

    if (assignment != null) {
      await ClientMeetingAssignmentService.instance.markAsUsed(
        assignmentId: assignment.id,
        meetingLogId: attendanceRef.id,
      );
    }
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
    return '$mm/$dd/$yyyy - $hh:$min $ampm';
  }

  String _formatClockTime(DateTime dt) {
    int h = dt.hour % 12;
    if (h == 0) h = 12;
    final hh = h.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm:$ss $ampm';
  }

  String _formatClockDate(DateTime dt) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final isOffline = _networkState == _NetworkState.offline;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1024;
          if (!isWide) {
            return Scaffold(
              backgroundColor: tc.bgMid,
              body: Stack(
                children: [
                  _buildContent(tc),
                  if (isOffline)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: _showOfflineOverlay ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                        child: IgnorePointer(
                          ignoring: !_showOfflineOverlay,
                          child: _buildNetworkErrorOverlay(
                            onRetry: _retryNetworkCheck,
                          ),
                        ),
                      ),
                    ),
                  if (_obscureContent) _buildPrivacyShield(),
                ],
              ),
            );
          }
          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0F),
            body: Stack(
              children: [
                _buildWebLayout(tc),
                if (_step != _LoginStep.selectMethod) _buildDesktopModal(),
                if (isOffline)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _showOfflineOverlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: !_showOfflineOverlay,
                        child: _buildNetworkErrorOverlay(
                          onRetry: _retryNetworkCheck,
                        ),
                      ),
                    ),
                  ),
                if (_obscureContent) _buildPrivacyShield(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrivacyShield() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: _shieldBg,
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

  Widget _buildNetworkErrorOverlay({required VoidCallback onRetry}) {
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
                colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
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
                    onPressed: onRetry,
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

  Widget _buildWebLayout(_ThemeColors tc) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0A0F),
            Color(0xFF0D0B08),
            Color(0xFF1A0F05),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildWebTopNav(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWebSidebar(),
                  Expanded(child: _buildWebMainContent(tc)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebTopNav() {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          _wrapWithHiddenAdmin(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.access_time_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'R.A.C.O.M.A.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'v1.0.4',
              style: TextStyle(
                color: Color(0xFFFF8A00),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          if (_deviceCompromised) ...[
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border:
                Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 14),
                  SizedBox(width: 6),
                  Text('COMPROMISED',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _formatClockTime(_now),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatClockDate(_now),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebSidebar() {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUTHENTICATION FLOW',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 24),
          _buildStepItem(1, 'Initial Login', 'Key Fob or PIN', isActive: true),
          _buildStepConnector(),
          _buildStepItem(2, 'Confirm Identity', 'Secondary verification',
              isActive: false),
          _buildStepConnector(),
          _buildStepItem(3, 'Clock In', 'Attendance recorded', isActive: false),
        ],
      ),
    );
  }

  Widget _buildStepItem(int n, String title, String subtitle,
      {required bool isActive}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
              colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
            )
                : null,
            color: isActive ? null : Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
            border: isActive
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: isActive
                ? [
              BoxShadow(
                color:
                const Color(0xFFFF8A00).withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ]
                : null,
          ),
          child: Text(
            '$n',
            style: TextStyle(
              color: isActive
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector() {
    return Container(
      margin: const EdgeInsets.only(left: 15, top: 6, bottom: 6),
      width: 2,
      height: 24,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }

  Widget _buildWebMainContent(_ThemeColors tc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wrapWithHiddenAdmin(
            child: const Text(
              'Auth & Clock In',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.4,
                height: 1.05,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose your verification method to begin your shift.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            height: 320,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _WebOptionCard(
                    icon: Icons.contactless_rounded,
                    title: 'Key Fob',
                    desc:
                    'Tap your fob on the NFC reader to authenticate instantly.',
                    enabled: !kIsWeb &&
                        _nfcAvailable &&
                        _isOnline &&
                        !_deviceCompromised,
                    onTap: () => _goToStep(_LoginStep.nfcWait),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _WebOptionCard(
                    icon: Icons.key_rounded,
                    title: 'Use PIN',
                    desc:
                    'Enter your 4-digit security PIN to verify your identity.',
                    enabled: _isOnline && !_deviceCompromised,
                    onTap: () => _goToStep(_LoginStep.pinEntry),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Text(
                'Having trouble? ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
              GestureDetector(
                onTap: _showPasswordChangeRequestDialog,
                child: const Text(
                  'Request password change',
                  style: TextStyle(
                    color: Color(0xFFFF8A00),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFFFF8A00),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopModal() {
    Widget card;
    switch (_step) {
      case _LoginStep.pinEntry:
        card = _buildPinModalCard();
        break;
      case _LoginStep.nfcWait:
        card = _buildNfcModalCard();
        break;
      case _LoginStep.clientMeeting:
        card = _buildClientMeetingModalCard();
        break;
      case _LoginStep.selectMethod:
        return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: FadeTransition(
        opacity: _modalOpacityAnim,
        child: Container(
          color: _scrim,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: SingleChildScrollView(
              child: ScaleTransition(scale: _modalScaleAnim, child: card),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_ThemeColors tc) {
    return Stack(
      children: [
        Container(
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
              Expanded(child: _buildSelectMethodStep(tc)),
            ]),
          ),
        ),
        if (_step != _LoginStep.selectMethod) _buildModalOverlay(),
      ],
    );
  }

  Widget _buildModalOverlay() {
    Widget card;
    switch (_step) {
      case _LoginStep.pinEntry:
        card = _buildPinModalCard();
        break;
      case _LoginStep.nfcWait:
        card = _buildNfcModalCard();
        break;
      case _LoginStep.clientMeeting:
        card = _buildClientMeetingModalCard();
        break;
      case _LoginStep.selectMethod:
        card = const SizedBox.shrink();
        break;
    }
    return Positioned.fill(
      child: FadeTransition(
        opacity: _modalOpacityAnim,
        child: Container(
          color: _scrim,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: ScaleTransition(scale: _modalScaleAnim, child: card),
          ),
        ),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: _kTitleLeft * scale,
                    top: _kTitleTop * scale,
                    child: _wrapWithHiddenAdmin(
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
                  ),
                  Positioned(
                    left: _kSubtitleLeft * scale,
                    top: _kSubtitleTop * scale,
                    child: Text(
                      'Select your initial verification method',
                      style: TextStyle(
                        color: _white,
                        fontSize: _kSubtitleFontSize * scale,
                        fontWeight: FontWeight.w400,
                        height: 1.0,
                      ),
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
              stepLabel: 'Step 1: Initial Login',
              overlap: 64 * scale,
              child: Column(children: [
                if (_deviceCompromised) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Device integrity check failed. '
                              'Logins are blocked on this device.',
                          style: TextStyle(
                            color: isDark(context)
                                ? Colors.white
                                : Colors.red.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Expanded(
                    child: _MethodButton(
                      icon: Icons.contactless_rounded,
                      label: 'Key Fob',
                      enabled:
                      !kIsWeb && _nfcAvailable && !_deviceCompromised,
                      onTap: () => _goToStep(_LoginStep.nfcWait),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MethodButton(
                      icon: Icons.key_rounded,
                      label: 'Use PIN',
                      enabled: !_deviceCompromised,
                      onTap: () => _goToStep(_LoginStep.pinEntry),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildClientMeetingButton(),
                const SizedBox(height: 10),
                _buildPasswordRequestButton(),
              ]),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: tc.infoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.infoBorder, width: 1.5),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: tc.infoText, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NFC / Key Fob is not supported by web browsers. '
                          'Please use PIN or Client Meeting login, or download the APK.',
                      style: TextStyle(
                          color: tc.infoText, fontSize: 12, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ] else if (!_nfcAvailable) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: tc.infoBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.infoBorder, width: 1.5),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: tc.infoText, size: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'NFC not available on this device. Use PIN to sign in.',
                      style: TextStyle(color: tc.infoText, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }

  bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Widget _buildPasswordRequestButton() {
    final disabled = _isLoading || !_isOnline;
    return GestureDetector(
      onTap: disabled ? null : _showPasswordChangeRequestDialog,
      child: Container(
        width: double.infinity,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: disabled ? const Color(0xFF9CA3AF) : _orange,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_reset_rounded,
              size: 16,
              color: disabled ? const Color(0xFF9CA3AF) : _orange,
            ),
            const SizedBox(width: 6),
            Text(
              'Forgot PIN / Request Password Change',
              style: TextStyle(
                color: disabled ? const Color(0xFF9CA3AF) : _orange,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientMeetingButton() {
    if (!_clientMeetingEnabled) {
      return _buildGrayClientMeetingButton(
        message: 'Client Meeting login is coming soon',
        label: 'Client Meeting LogIn',
        showSpinner: false,
      );
    }

    if (_checkingActiveMeeting) {
      return _buildGrayClientMeetingButton(
        message: 'Checking for scheduled client meetings…',
        label: 'Checking…',
        showSpinner: true,
      );
    }

    final blockBecauseNoMeeting =
        _activeEmployee != null && !_hasActiveMeeting;

    if (blockBecauseNoMeeting) {
      return _buildGrayClientMeetingButton(
        message:
        'No client meeting scheduled.\nPlease ask your admin to assign one.',
        label: 'Client Meeting LogIn',
        showSpinner: false,
      );
    }

    final disabled = _isLoading || _deviceCompromised;

    return GestureDetector(
      onTap: disabled ? null : _onClientMeetingLogin,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: disabled ? const Color(0xFF9CA3AF) : _orange,
            width: 1,
          ),
        ),
        child: _isLoading
            ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              color: _orange, strokeWidth: 2),
        )
            : Text(
          'Client Meeting LogIn',
          style: TextStyle(
              color:
              disabled ? const Color(0xFF9CA3AF) : _orange,
              fontSize: 14,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildGrayClientMeetingButton({
    required String message,
    required String label,
    required bool showSpinner,
  }) {
    return Tooltip(
      message: message,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF9CA3AF),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showSpinner)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF6B7280),
                ),
              )
            else
              const Icon(
                Icons.lock_clock_rounded,
                size: 14,
                color: Color(0xFF6B7280),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildPinModalCard() {
    final locked = _isPinLockedOut;
    final remaining = _maxPinAttempts - _pinFailedAttempts;
    final showWarning = remaining <= 2 && remaining > 0 && !locked;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              locked ? Icons.lock_rounded : Icons.key_rounded,
              color: locked ? _error : _modalGradTop,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            locked ? 'Account Locked' : 'Enter PIN',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Text(
            locked
                ? 'Too many failed attempts.\nTry again in ${_remainingLockoutText()}'
                : 'Please enter your 4-digit PIN to begin',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92), fontSize: 14),
          ),
          if (locked) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Lockout: ${_remainingLockoutText()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ] else if (showWarning) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '⚠️ $remaining attempt(s) left',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                  _shakeAnim.value *
                      ((_shakeController.value * 10).round().isEven
                          ? 1
                          : -1),
                  0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pinInput.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),
          Column(
            children: [
              _pinPadRow(['1', '2', '3'], locked),
              const SizedBox(height: 12),
              _pinPadRow(['4', '5', '6'], locked),
              const SizedBox(height: 12),
              _pinPadRow(['7', '8', '9'], locked),
              const SizedBox(height: 12),
              _pinPadRow(['', '0', 'del'], locked),
            ],
          ),
          const SizedBox(height: 16),
          _buildFeedback(onDark: true),
          const SizedBox(height: 8),
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _pinPadRow(List<String> keys, bool locked) {
    return Row(
      children: List.generate(keys.length, (colIdx) {
        final key = keys[colIdx];
        if (key.isEmpty) return const Expanded(child: SizedBox());
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: colIdx > 0 ? 10 : 0,
              right: colIdx < keys.length - 1 ? 10 : 0,
            ),
            child: _PinKeyWhite(
              label: key,
              onTap: locked ? () {} : () => _onPinKey(key),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildNfcModalCard() {
    if (kIsWeb) {
      return _buildUnsupportedWebCard(
        icon: Icons.contactless_rounded,
        title: 'NFC Not Supported',
        message: 'NFC / Key Fob login is not available on web browsers.\n\n'
            'Please use PIN or Client Meeting login instead.',
      );
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _nfcPulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isLoading ? 1.0 : _nfcPulseAnim.value,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: _isLoading
                    ? const CircularProgressIndicator(
                    color: _modalGradTop, strokeWidth: 2.5)
                    : const Icon(Icons.contactless_rounded,
                    color: _modalGradTop, size: 48),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Tap Key Fob',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            _isLoading
                ? 'Reading keyfob…'
                : 'Please tap your key fob on the reader...',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_errorMessage != null) ...[
            _buildFeedback(onDark: true),
            const SizedBox(height: 12),
          ],
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildUnsupportedWebCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: _modalGradTop, size: 40),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.5)),
          const SizedBox(height: 24),
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildClientMeetingModalCard() {
    if (_captureSuccess) return _buildClientMeetingSuccessCard();
    final assignment = _activeAssignment;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Client Meeting Check-In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (assignment != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assignment_rounded,
                      color: Colors.white, size: 12),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${assignment.clientName} · ${assignment.timeWindowLabel}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text('Snap a photo to log your visit',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 16),
          _buildCameraPreviewBox(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShutterButton(),
              const SizedBox(width: 20),
              _buildCameraSwitchButton(),
            ],
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            _buildFeedback(onDark: true),
            const SizedBox(height: 8),
          ],
          _buildCancelButton(),
        ],
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    return GestureDetector(
      onTap: _switchCamera,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.switch_camera, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(_useFrontCamera ? 'Front' : 'Back',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreviewBox() {
    return AspectRatio(
      aspectRatio: 314 / 456,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isMockedGps ? Colors.red : const Color(0xFFFDBA74),
            width: _isMockedGps ? 2 : 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14.5),
          child: Container(
            color: _cmPreviewBg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraController != null &&
                    _cameraController!.value.isInitialized)
                  _buildCoveredCameraPreview()
                else
                  const Center(
                    child: CircularProgressIndicator(
                        color: Colors.white54, strokeWidth: 2.5),
                  ),
                if (_isCapturing)
                  Container(color: Colors.black.withValues(alpha: 0.25)),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isMockedGps)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('FAKE GPS',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      if (_currentAccuracy != null &&
                          _currentAccuracy! > 200)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'GPS ±${_currentAccuracy!.toStringAsFixed(0)}m',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      if (_clientMatch != null && _clientMatch!.isVerified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded,
                                  color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('VERIFIED',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Color(0xFFC4FF0A), size: 14),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _locationDisplay,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 6,
                                    ),
                                  ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(_now),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 6,
                              ),
                            ]),
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

  Widget _buildCoveredCameraPreview() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child:
        CircularProgressIndicator(color: Colors.white54, strokeWidth: 2.5),
      );
    }
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _capturePhoto,
      child: AnimatedBuilder(
        animation: _nfcPulseAnim,
        builder: (_, __) => Transform.scale(
          scale: _isCapturing ? 1.0 : _nfcPulseAnim.value,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cmShutterOuter,
              boxShadow: [
                BoxShadow(
                    color: _cmShutterGlow.withValues(alpha: 0.8),
                    blurRadius: 15),
              ],
            ),
            alignment: Alignment.center,
            child: _isCapturing
                ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            )
                : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cmShutterInner,
                boxShadow: [
                  BoxShadow(
                      color: _cmShutterGlow.withValues(alpha: 0.8),
                      blurRadius: 15),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClientMeetingSuccessCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded,
                color: _modalGradTop, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('Successfully Clocked In',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'Please wait for HR approval...',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92), fontSize: 14),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _goBack,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFA500), width: 1.15),
        ),
        child: const Text('Cancel',
            style: TextStyle(
                color: Color(0xFFFFA500),
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildFeedback({bool onDark = false}) {
    if (_isLoading) {
      return SizedBox(
        height: 36,
        child: Center(
          child: CircularProgressIndicator(
              color: onDark ? Colors.white : _orange, strokeWidth: 2.5),
        ),
      );
    }
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.15) : _errorBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : _error.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              color: onDark ? Colors.white : _error, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                  color: onDark ? Colors.white : _error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
    }
    return const SizedBox(height: 8);
  }
}

// ═══════════════════════════════════════════════════════════════
// WEB OPTION CARD
// ═══════════════════════════════════════════════════════════════
class _WebOptionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool enabled;
  final VoidCallback onTap;

  const _WebOptionCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_WebOptionCard> createState() => _WebOptionCardState();
}

class _WebOptionCardState extends State<_WebOptionCard> {
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _pressed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return MouseRegion(
      cursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.forbidden,
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: GestureDetector(
        onTapDown: enabled ? (_) => _pressed.value = true : null,
        onTapUp: enabled
            ? (_) {
          _pressed.value = false;
          widget.onTap();
        }
            : null,
        onTapCancel: enabled ? () => _pressed.value = false : null,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hovered,
          builder: (context, hovered, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _pressed,
              builder: (context, pressed, __) {
                final active = enabled && (hovered || pressed);
                final scale = pressed ? 0.98 : 1.0;

                return AnimatedScale(
                  duration: const Duration(milliseconds: 140),
                  scale: scale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFFFF8A00).withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? const Color(0xFFFF8A00)
                            .withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1.5,
                      ),
                      boxShadow: active
                          ? [
                        BoxShadow(
                          color: const Color(0xFFFF8A00)
                              .withValues(alpha: 0.18),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ]
                          : null,
                    ),
                    child: Opacity(
                      opacity: enabled ? 1.0 : 0.45,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF8A00)
                                      .withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Icon(widget.icon,
                                color: Colors.white, size: 26),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.desc,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Text(
                                'Select',
                                style: TextStyle(
                                  color: enabled
                                      ? const Color(0xFFFF8A00)
                                      : Colors.white.withValues(alpha: 0.3),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AnimatedPadding(
                                duration: const Duration(milliseconds: 180),
                                padding: EdgeInsets.only(
                                    left: hovered && enabled ? 4 : 0),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: enabled
                                      ? const Color(0xFFFF8A00)
                                      : Colors.white.withValues(alpha: 0.3),
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BackArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.66602 * (size.width / 19.99)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final s = size.width / 19.99;
    Offset p(double x, double y) => Offset(x * s, (y - 5) * s);
    final path = Path()
      ..moveTo(p(12.4951, 14.9941).dx, p(12.4951, 14.9941).dy)
      ..lineTo(p(7.49707, 9.9961).dx, p(7.49707, 9.9961).dy)
      ..lineTo(p(12.4951, 4.99805).dx, p(12.4951, 4.99805).dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
        message: 'Not available on this device',
        child: button,
      );
    }
    return button;
  }
}

class _PinKeyWhite extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _PinKeyWhite({required this.label, required this.onTap});
  @override
  State<_PinKeyWhite> createState() => _PinKeyWhiteState();
}

class _PinKeyWhiteState extends State<_PinKeyWhite>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
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
    final isDel = widget.label == 'del';
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF564334), width: 1.15),
          ),
          child: Center(
            child: isDel
                ? const Text('DEL',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF71717A)))
                : Text(widget.label,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.black)),
          ),
        ),
      ),
    );
  }
}