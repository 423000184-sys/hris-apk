// lib/screens/fingerprint_screen.dart
// v2.6: 🌐 All UI strings converted to English
//       🔒 Demo mode requires internet connection
//       ✅ Online → native prompt + auto-succeed
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../models/employee.dart';
import '../widgets/bootstrap_grid.dart';
import '../widgets/skeleton_screens.dart';
import '../data/local/dao/connectivity_service.dart';
import '../services/security_hardening_service.dart';
import '../services/clock_status_service.dart';
import '../services/geofence_service.dart';
import '../services/admin_notification_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/device_info_service.dart';
import '../services/presence_challenge_service.dart';
import '../services/demo_mode_service.dart';
import 'facial_recognition_screen.dart';
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

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
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFDBA74);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1F2937);
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

enum _NetworkState { online, offline, checking }

enum _CredentialStatus {
  ok,
  missing,
  employeeMismatch,
  deviceMismatch,
  enrollmentChanged,
  tampered,
}

enum _RegPhase { idle, capturingStep, completed }

class FingerprintScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;
  final bool standaloneMode;

  const FingerprintScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
    this.standaloneMode = false,
  });

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // 🎭 DEMO MODE
  bool get _isDemo => DemoModeService.instance.isEnabled;

  _FpState _fpState = _FpState.idle;
  String? _errorMessage;
  bool _cancelPressed = false;

  bool _isNavigating = false;
  bool _noBiometricHardware = false;
  bool _hardwareChecked = false;

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  bool _isInitialLoading = true;
  bool _obscureContent = false;

  Timer? _navTimer;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<int>? _pendingSub;

  static const String _logoAsset = 'assets/images/logo.png';

  GeofenceResult? _lastGeoResult;
  double? _lastDistanceMeters;
  double? _lastAccuracyMeters;
  double? _lastRadiusUsed;
  double? _lastLatitude;
  double? _lastLongitude;
  String? _lastLocationName;
  String? _lastZoneStatus;
  bool _lastUsedTolerance = false;
  bool _lastMockLocationDetected = false;
  bool _geofenceVerifiedOffline = false;

  bool _fingerprintRegistered = false;
  bool _checkingRegistration = true;

  String? _resolvedDocId;
  bool _registrationCheckComplete = false;
  bool _justRegistered = false;
  DateTime? _fingerprintRegisteredAt;

  _CredentialStatus _lastCredentialStatus = _CredentialStatus.ok;

  int _pendingCount = 0;

  static const int _totalRegSteps = 2;

  static const List<String> _regStepNames = ['CENTER', 'CONFIRM'];

  static const List<String> _regStepInstructions = [
    'Place the CENTER of your registered finger\non the sensor',
    'Lift your finger and place it again\n(same finger, same spot)',
  ];

  static const List<IconData> _regStepIcons = [
    Icons.fingerprint_rounded,
    Icons.check_circle_outline_rounded,
  ];

  _RegPhase _regPhase = _RegPhase.idle;
  int _currentRegStep = 0;
  final List<String> _regStepHashes = [];

  static const int _maxAuthAttempts = 3;
  static const int _authRateLimitMs = 2000;
  static const String _kAuthAttemptsKey = 'fp_failed_attempts';
  static const String _kAuthLockoutKey = 'fp_lockout_until';
  static const String _kPreAuthEmpKey = 'fp_preauth_employee_id';
  static const String _kPreAuthTimeKey = 'fp_preauth_time';
  static const Duration _preAuthValidDuration = Duration(minutes: 10);

  static const Duration _biometricTimeout = Duration(seconds: 45);
  static const int _minValidBiometricMs = 350;

  static const int _maxSessionFails = 3;
  static const int _consecutiveFailsToShowCleanup = 2;

  static String _credKey(String employeeId) => 'fp_cred_$employeeId';

  int _authFailedAttempts = 0;
  DateTime? _authLockoutUntil;
  Timer? _authLockoutTimer;
  DateTime? _lastAuthAttemptAt;
  String? _deviceFingerprint;
  String? _deviceBinding;
  late final String _sessionNonce;
  bool _preAuthVerified = false;
  bool _deviceCompromised = false;
  Duration? _activeBackoff;

  int _sessionFailCount = 0;
  int _consecutiveFailsForCleanup = 0;
  bool _showCleanupHint = false;
  bool _osLockedOut = false;
  DateTime? _osLockoutUntil;
  String? _lastErrorCode;

  bool _isCheckingGeofence = false;
  bool _isInsideZone = false;
  bool _isWfh = false;
  bool _isDriver = false;
  bool _geofenceExempted = false;
  String _deviceModel = 'Unknown Device';

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;

  Animation<double>? _pulseAnim;
  Animation<double>? _ringAnim;
  Animation<double>? _fadeAnim;
  Animation<double>? _shakeAnim;
  Animation<double>? _successAnim;

  static const _headerStart = Color(0xFFFF5500);
  static const _headerEnd = Color(0xFFFF6B00);
  static const _modalGradTop = Color(0xFFFF8A00);
  static const _modalGradMid = Color(0xFFFA6A00);
  static const _modalGradEnd = Color(0xFFF54900);
  static const _modalBorderDefault = Color(0xFF564334);
  static const _modalBorderSuccess = Color(0xFF27272A);
  static const _successRing = Color(0xFF51FF00);
  static const _scrim = Color.fromRGBO(9, 9, 11, 0.44);
  static const _white = Color(0xFFFFFFFF);
  static const _white70 = Color(0xFFDFDFDF);
  static const _orange = Color(0xFFF97316);
  static const _success = Color(0xFF22C55E);
  static const _error = Color(0xFFDC2626);
  static const _cancelText = Color(0xFFFF8A00);
  static const _cancelBorder = Color(0xFFFFA500);

  // 🎨 DEMO — ORANGE (matches app theme)
  static const _demoAccent = Color(0xFFFF8A00);
  static const _demoAccentDark = Color(0xFFF54900);

  bool get _isAuthLockedOut =>
      (_authLockoutUntil != null &&
          _authLockoutUntil!.isAfter(DateTime.now())) ||
          (_activeBackoff != null && _activeBackoff! > Duration.zero);

  bool get _isRegistering =>
      !_fingerprintRegistered && _regPhase != _RegPhase.completed;

  bool get _isOffline => _networkState == _NetworkState.offline;

  bool get _canAuthenticateOffline => true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();
    _secureLog('🔒 session nonce: $_sessionNonce');
    _secureLog('🎯 standaloneMode=${widget.standaloneMode}');

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _shakeAnim = Tween<double>(begin: 0, end: 12)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();

    // 🎭 DEMO MODE — skip all security + listeners
    if (_isDemo) {
      _secureLog('═══════════════════════════════════════════');
      _secureLog('🎭 [DemoMode] FingerprintScreen');
      _secureLog('   • Skipping security bootstrap');
      _secureLog('   • Forcing native biometric prompt');
      _secureLog('   • 🔒 Requires internet connection');
      _secureLog('═══════════════════════════════════════════');

      _preAuthVerified = true;
      _fingerprintRegistered = true;
      _checkingRegistration = false;
      _registrationCheckComplete = true;
      _regPhase = _RegPhase.completed;
      _deviceModel = 'Demo Device';
      _deviceBinding = 'demo-binding';
      _deviceFingerprint = 'demo-fingerprint';
      _networkState = _NetworkState.online;

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
        _secureLog('⚠️ connectivity listen error: $e');
      }

      // Sync initial connectivity state
      try {
        final online = ConnectivityService.instance.isOnline;
        _networkState =
        online ? _NetworkState.online : _NetworkState.offline;
      } catch (_) {}

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) setState(() => _isInitialLoading = false);
      });
      return;
    }

    // NORMAL MODE
    _bootstrapSecurity();
    _loadSecurityState();
    _loadDeviceFingerprint().then((_) async {
      if (mounted) {
        await _checkFingerprintRegistration();
        if (mounted) {
          setState(() => _registrationCheckComplete = true);
        }
      }
    });
    _verifyPreAuth();
    _loadDeviceModel();
    _determineRole();
    _subscribePendingCount();

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;

            if (!online) {
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\n\n'
                    'You can still clock in — records will be saved locally '
                    'and synced automatically when you\'re back online.';
                _showOfflineOverlay = false;
              });
            } else if (_networkState == _NetworkState.offline) {
              _retryNetworkCheck();
            }
          });
    } catch (e) {
      _secureLog('⚠️ connectivity listen error: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNetworkAndProceed();
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔌 OFFLINE SNACK HELPER
  // ═══════════════════════════════════════════════════════════════
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
                  custom ??
                      'Internet connection is required to verify.',
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

  bool _isOnlineSafely() {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  void _subscribePendingCount() {
    if (_isDemo) return;

    try {
      _pendingSub = OfflineAttendanceService.instance.pendingStream.listen((c) {
        if (mounted) setState(() => _pendingCount = c);
      });
      OfflineAttendanceService.instance.getPendingCount().then((c) {
        if (mounted) setState(() => _pendingCount = c);
      });
    } catch (e) {
      _secureLog('⚠️ pending stream error: $e');
    }
  }

  void _determineRole() {
    if (_isDemo) return;

    final emp = widget.employee;
    final role = emp.position.toLowerCase();
    final dept = emp.department.toLowerCase();
    _isDriver = role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider');
    _isWfh = emp.wfhAccess;
  }

  Future<void> _loadDeviceModel() async {
    if (_isDemo) {
      if (mounted) setState(() => _deviceModel = 'Demo Device');
      return;
    }

    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (mounted) setState(() => _deviceModel = model);
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navTimer?.cancel();
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    _authLockoutTimer?.cancel();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();

    SecurityHardeningService.instance.disableSecureScreen();

    super.dispose();
  }

  Future<void> _bootstrapSecurity() async {
    if (_isDemo) {
      _preAuthVerified = true;
      return;
    }

    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (_) {}

    try {
      final ok =
      await SecurityHardeningService.instance.checkDeviceIntegrity();
      if (!ok) {
        await _logSecurityEvent(
          type: 'fp_compromised_device',
          severity: 'critical',
          details:
          SecurityHardeningService.instance.integrityIssues.join(','),
        );
      }
      if (mounted) setState(() => _deviceCompromised = !ok);
    } catch (_) {}

    try {
      final bo = await SecurityHardeningService.instance.getActiveBackoff();
      if (bo != null && mounted) {
        setState(() {
          _activeBackoff = bo;
          _authLockoutUntil = DateTime.now().add(bo);
        });
        _startAuthLockoutCountdown();
      }
    } catch (_) {}

    try {
      final binding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
      if (mounted) setState(() => _deviceBinding = binding);
    } catch (_) {}
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _loadDeviceFingerprint() async {
    if (_isDemo) {
      if (mounted) setState(() => _deviceFingerprint = 'demo');
      return;
    }

    try {
      final fp =
      await SecurityHardeningService.instance.getDeviceFingerprint();
      if (mounted) setState(() => _deviceFingerprint = fp);
    } catch (_) {
      if (mounted) setState(() => _deviceFingerprint = 'unknown');
    }
  }

  Future<String?> _resolveEmployeeDocId() async {
    if (_isDemo) return DemoModeService.demoEmployee.id;

    if (_resolvedDocId != null && _resolvedDocId!.isNotEmpty) {
      return _resolvedDocId;
    }

    final id = widget.employee.id;
    if (id.isNotEmpty) {
      _resolvedDocId = id;
      return id;
    }

    final empId = widget.employee.employeeId;
    if (empId.isNotEmpty) {
      _resolvedDocId = empId;
      return empId;
    }

    if (_networkState == _NetworkState.offline) {
      _secureLog('⚠️ [DocId] Offline — skipping email query');
      return null;
    }

    try {
      final email = widget.employee.email;
      if (email.isNotEmpty) {
        final q = await FirebaseFirestore.instance
            .collection('employees')
            .where('email', isEqualTo: email.toLowerCase())
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 6));
        if (q.docs.isNotEmpty) {
          final found = q.docs.first.id;
          _resolvedDocId = found;
          return found;
        }
      }
    } catch (e) {
      _secureLog('⚠️ [DocId] Email query failed: $e');
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 BIOMETRIC CREDENTIAL HELPERS
  // ═══════════════════════════════════════════════════════════════
  Future<List<String>> _captureEnrollmentSnapshot() async {
    if (_isDemo) return const ['demo'];

    try {
      if (kIsWeb) return const [];
      final list = await _localAuth.getAvailableBiometrics();
      final names = list.map((b) {
        switch (b) {
          case BiometricType.face:
            return 'face';
          case BiometricType.fingerprint:
            return 'fingerprint';
          case BiometricType.iris:
            return 'iris';
          case BiometricType.strong:
            return 'strong';
          case BiometricType.weak:
            return 'weak';
        }
      }).toList()
        ..sort();
      return names;
    } catch (_) {
      return const [];
    }
  }

  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  String _buildStepHash(int step, String enrollmentSnapshot) {
    final rand = math.Random.secure();
    final nonceBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final nonce =
    nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _sha256Hex(
        'step=$step|nonce=$nonce|emp=${widget.employee.id}|snap=$enrollmentSnapshot');
  }

  Future<
      ({
      String json,
      String hash,
      List<String> snapshot,
      List<String> stepHashes
      })> _buildAndStoreCredential() async {
    if (_isDemo) {
      return (
      json: '{}',
      hash: 'demo-hash',
      snapshot: const ['demo'],
      stepHashes: const <String>[],
      );
    }

    final rand = math.Random.secure();
    final nonceBytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final nonce =
    nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final snapshot = await _captureEnrollmentSnapshot();

    final credMap = <String, dynamic>{
      'employee_id': widget.employee.id,
      'device_binding': _deviceBinding,
      'device_fingerprint': _deviceFingerprint,
      'nonce': nonce,
      'enrollment_snapshot': snapshot,
      'registration_steps': _totalRegSteps,
      'step_hashes': _regStepHashes,
      'registered_at': DateTime.now().toUtc().toIso8601String(),
      'v': 2,
    };

    final jsonStr = jsonEncode(credMap);
    final hash = _sha256Hex(jsonStr);

    try {
      await _secureStorage.write(
        key: _credKey(widget.employee.id),
        value: jsonStr,
      );
    } catch (_) {}

    return (
    json: jsonStr,
    hash: hash,
    snapshot: snapshot,
    stepHashes: _regStepHashes,
    );
  }

  Future<Map<String, dynamic>?> _readCredential() async {
    if (_isDemo) return null;

    try {
      final raw = await _secureStorage.read(key: _credKey(widget.employee.id));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (e) {
      _secureLog('❌ readCredential: $e');
      return null;
    }
  }

  Future<_CredentialStatus> _verifyCredential({
    required String? storedHashFromFirestore,
  }) async {
    if (_isDemo) return _CredentialStatus.ok;

    final cred = await _readCredential();
    if (cred == null) return _CredentialStatus.missing;

    if (cred['employee_id'] != widget.employee.id) {
      return _CredentialStatus.employeeMismatch;
    }

    if (cred['device_binding'] != _deviceBinding) {
      return _CredentialStatus.deviceMismatch;
    }

    final savedSnapshot =
        (cred['enrollment_snapshot'] as List?)?.cast<String>() ?? const [];
    final currentSnapshot = await _captureEnrollmentSnapshot();
    if (savedSnapshot.length != currentSnapshot.length ||
        !_listEq(savedSnapshot, currentSnapshot)) {
      return _CredentialStatus.enrollmentChanged;
    }

    if (storedHashFromFirestore != null &&
        storedHashFromFirestore.isNotEmpty) {
      final recomputed = _sha256Hex(jsonEncode(cred));
      if (recomputed != storedHashFromFirestore) {
        return _CredentialStatus.tampered;
      }
    }

    return _CredentialStatus.ok;
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _refreshCredentialInBackground() async {
    if (_isDemo) return;
    if (_networkState != _NetworkState.online) return;

    try {
      final cred = await _buildAndStoreCredential();
      final docId = await _resolveEmployeeDocId();
      if (docId == null) return;

      await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .set({
        'fingerprintCredentialHash': cred.hash,
        'fingerprintEnrollmentSnapshot': cred.snapshot,
        'fingerprintCredentialRefreshedAt': FieldValue.serverTimestamp(),
        'fingerprintInvalidReason': FieldValue.delete(),
        'fingerprintInvalidatedAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      _secureLog('⚠️ Self-heal failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 CHECK REGISTRATION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkFingerprintRegistration() async {
    if (_isDemo) {
      if (mounted) {
        setState(() {
          _fingerprintRegistered = true;
          _checkingRegistration = false;
          _registrationCheckComplete = true;
          _regPhase = _RegPhase.completed;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _checkingRegistration = true);

    if (_networkState == _NetworkState.offline) {
      await _checkRegistrationOffline();
      return;
    }

    try {
      final docId = await _resolveEmployeeDocId();
      if (docId == null || docId.isEmpty) {
        if (mounted) {
          setState(() {
            _fingerprintRegistered = false;
            _checkingRegistration = false;
          });
        }
        return;
      }

      DocumentSnapshot<Map<String, dynamic>>? doc;
      try {
        doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(docId)
            .get()
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        _secureLog('⚠️ [FP] Primary doc read failed: $e');
      }

      Map<String, dynamic>? data = doc?.data();

      if (data == null) {
        final empId = _employeeIdForAttendance;
        if (empId.isNotEmpty) {
          try {
            final q = await FirebaseFirestore.instance
                .collection('employees')
                .where('employeeId', isEqualTo: empId)
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 6));
            if (q.docs.isNotEmpty) {
              data = q.docs.first.data();
            }
          } catch (_) {}
        }
      }

      if (data == null) {
        if (mounted) {
          setState(() {
            _fingerprintRegistered = false;
            _checkingRegistration = false;
          });
        }
        return;
      }

      final enrolledFlag = data['fingerprintEnrolled'] == true;
      final savedBinding = data['fingerprintDeviceBinding']?.toString();
      final currentBinding = _deviceBinding;
      final storedHash = data['fingerprintCredentialHash']?.toString();

      bool bindingMatches = true;
      if (savedBinding != null &&
          savedBinding.isNotEmpty &&
          currentBinding != null &&
          currentBinding.isNotEmpty) {
        bindingMatches = savedBinding == currentBinding;
      }

      final enrolled = enrolledFlag && bindingMatches;

      DateTime? enrolledAt;
      final rawEnrolledAt = data['fingerprintEnrolledAt'];
      if (rawEnrolledAt is Timestamp) {
        enrolledAt = rawEnrolledAt.toDate();
      }

      _CredentialStatus credStatus = _CredentialStatus.ok;
      if (enrolled) {
        credStatus = await _verifyCredential(
          storedHashFromFirestore: storedHash,
        );
        if (credStatus != _CredentialStatus.ok) {
          unawaited(_refreshCredentialInBackground());
        }
      }

      await _cacheEnrollmentStatus(enrolled, enrolledAt);

      if (mounted) {
        setState(() {
          _fingerprintRegistered = enrolled;
          _fingerprintRegisteredAt = enrolledAt;
          _checkingRegistration = false;
          _lastCredentialStatus = credStatus;
          _regPhase = enrolled ? _RegPhase.completed : _RegPhase.idle;
        });
      }
    } catch (e) {
      _secureLog('❌ [FP] Check registration error: $e');
      await _checkRegistrationOffline();
    }
  }

  Future<void> _checkRegistrationOffline() async {
    if (_isDemo) return;

    try {
      final cred = await _readCredential();
      final enrolled =
          cred != null && cred['employee_id'] == widget.employee.id;

      if (mounted) {
        setState(() {
          _fingerprintRegistered = enrolled;
          _checkingRegistration = false;
          _regPhase = enrolled ? _RegPhase.completed : _RegPhase.idle;
        });
      }
    } catch (e) {
      _secureLog('❌ [FP-offline] $e');
      if (mounted) {
        setState(() {
          _fingerprintRegistered = false;
          _checkingRegistration = false;
        });
      }
    }
  }

  Future<void> _cacheEnrollmentStatus(bool enrolled, DateTime? at) async {
    if (_isDemo) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('fp_cached_enrolled', enrolled);
      if (at != null) {
        await prefs.setInt('fp_cached_enrolled_at', at.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  Future<void> _verifyPreAuth() async {
    if (_isDemo) {
      _preAuthVerified = true;
      return;
    }

    try {
      try {
        final secEmpId =
        await SecurityHardeningService.instance.getCurrentEmployeeId();
        if (secEmpId == null || secEmpId != widget.employee.id) {
          await _logSecurityEvent(
            type: 'fp_no_session',
            severity: 'critical',
            details: 'Session mismatch',
          );
          if (mounted) {
            setState(() {
              _errorMessage = '🚨 Session expired. Please log in again.';
              _fpState = _FpState.error;
            });
            _shakeCtrl.forward(from: 0);
          }
          return;
        }
      } catch (_) {
        return;
      }

      if (!widget.standaloneMode) {
        final prefs = await SharedPreferences.getInstance();
        final preAuthEmpId = prefs.getString(_kPreAuthEmpKey);
        final preAuthTimeMs = prefs.getInt(_kPreAuthTimeKey);

        if (preAuthEmpId == null || preAuthTimeMs == null) {
          if (mounted) {
            setState(() {
              _errorMessage =
              '🚨 Security check failed. Please log in again.';
              _fpState = _FpState.error;
            });
          }
          return;
        }
        if (preAuthEmpId != widget.employee.id) {
          if (mounted) {
            setState(() {
              _errorMessage =
              '🚨 Security check failed. Please log in again.';
              _fpState = _FpState.error;
            });
          }
          return;
        }
        final preAuthTime =
        DateTime.fromMillisecondsSinceEpoch(preAuthTimeMs);
        final elapsed = DateTime.now().difference(preAuthTime);
        if (elapsed > _preAuthValidDuration) {
          if (mounted) {
            setState(() {
              _errorMessage = '🚨 Session expired. Please log in again.';
              _fpState = _FpState.error;
            });
          }
          return;
        }
      }

      if (mounted) setState(() => _preAuthVerified = true);
    } catch (e) {
      _secureLog('❌ Pre-auth error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '🚨 Security check failed. Please log in again.';
          _fpState = _FpState.error;
        });
      }
    }
  }

  Future<void> _loadSecurityState() async {
    if (_isDemo) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final attempts = prefs.getInt(_kAuthAttemptsKey) ?? 0;
      final lockoutMs = prefs.getInt(_kAuthLockoutKey) ?? 0;

      if (!mounted) return;

      setState(() {
        _authFailedAttempts = attempts;
        if (lockoutMs > 0) {
          final lockout = DateTime.fromMillisecondsSinceEpoch(lockoutMs);
          if (lockout.isAfter(DateTime.now())) {
            _authLockoutUntil = lockout;
            _startAuthLockoutCountdown();
          } else {
            _authFailedAttempts = 0;
            _authLockoutUntil = null;
            prefs.remove(_kAuthLockoutKey);
            prefs.remove(_kAuthAttemptsKey);
          }
        }
      });
    } catch (_) {}
  }

  void _startAuthLockoutCountdown() {
    if (_isDemo) return;

    _authLockoutTimer?.cancel();
    _authLockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_authLockoutUntil == null ||
          _authLockoutUntil!.isBefore(DateTime.now())) {
        timer.cancel();
        setState(() {
          _authLockoutUntil = null;
          _authFailedAttempts = 0;
          _activeBackoff = null;
        });
        _clearAuthLockoutPrefs();
        SecurityHardeningService.instance.resetFailures();
        return;
      }
      setState(() {});
    });
  }

  Future<void> _clearAuthLockoutPrefs() async {
    if (_isDemo) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAuthAttemptsKey);
      await prefs.remove(_kAuthLockoutKey);
    } catch (_) {}
  }

  String _remainingLockoutText() {
    if (_authLockoutUntil == null) return '';
    final diff = _authLockoutUntil!.difference(DateTime.now());
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

  Future<void> _recordFailedAuthAttempt() async {
    if (_isDemo) return;

    _authFailedAttempts++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAuthAttemptsKey, _authFailedAttempts);

      final delay =
      await SecurityHardeningService.instance.registerFailure();
      final failCount =
      await SecurityHardeningService.instance.getFailureCount();

      if (delay > Duration.zero) {
        final until = DateTime.now().add(delay);
        await prefs.setInt(_kAuthLockoutKey, until.millisecondsSinceEpoch);
        if (mounted) {
          setState(() {
            _authLockoutUntil = until;
            _activeBackoff = delay;
          });
          _startAuthLockoutCountdown();
        }
      }
    } catch (_) {}
  }

  Future<void> _resetAuthAttempts() async {
    if (_isDemo) return;

    _authFailedAttempts = 0;
    _authLockoutUntil = null;
    _activeBackoff = null;
    _authLockoutTimer?.cancel();
    await _clearAuthLockoutPrefs();
    await SecurityHardeningService.instance.resetFailures();
  }

  bool _isRateLimited() {
    if (_lastAuthAttemptAt == null) return false;
    final elapsed =
        DateTime.now().difference(_lastAuthAttemptAt!).inMilliseconds;
    return elapsed < _authRateLimitMs;
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
    String? employeeId,
  }) async {
    if (_isDemo) {
      _secureLog('🎭 [DemoMode] Skipping security event: $type');
      return;
    }

    if (_networkState != _NetworkState.online) {
      try {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'security_events',
          data: {
            'type': type,
            'severity': severity,
            'details': details,
            'employeeId': employeeId ?? widget.employee.id,
            'employeeName': widget.employee.fullName,
            'sessionNonce': _sessionNonce,
            'deviceBinding': _deviceBinding,
            'deviceCompromised': _deviceCompromised,
            'stage': 'fingerprint',
            'platform': kIsWeb ? 'web' : 'mobile',
            'timestamp': DateTime.now(),
          },
        );
      } catch (_) {}
      return;
    }

    try {
      final hashDevice = _deviceFingerprint != null
          ? sha256.convert(utf8.encode(_deviceFingerprint!)).toString()
          : null;

      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': employeeId ?? widget.employee.id,
        'employeeName': widget.employee.fullName,
        'sessionNonce': _sessionNonce,
        'deviceHash': hashDevice,
        'deviceBinding': _deviceBinding,
        'deviceCompromised': _deviceCompromised,
        'mockLocation': _lastMockLocationDetected,
        'mode': widget.standaloneMode ? 'standalone' : 'login',
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'fingerprint',
        'lastErrorCode': _lastErrorCode,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  Future<bool> _hasNetwork() async {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkNetworkAndProceed() async {
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
        _networkErrorMessage =
        'No internet connection.\n\n'
            'You can still clock in — records will be saved locally '
            'and synced automatically when you\'re back online.';
        _showOfflineOverlay = false;
      });
      await _checkHardwareAndProceed();
      return;
    }

    setState(() => _networkState = _NetworkState.online);
    await _checkHardwareAndProceed();
  }

  Future<void> _retryNetworkCheck() async {
    if (_isDemo) return;

    if (!mounted) return;
    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
      _errorMessage = null;
    });
    await _checkNetworkAndProceed();
  }

  Future<void> _checkHardwareAndProceed() async {
    if (_isDemo) return;

    if (!mounted) return;
    final hasHardware = await _hasBiometricHardware();
    if (!mounted) return;
    _hardwareChecked = true;
    _noBiometricHardware = !hasHardware;

    if (!hasHardware) {
      if (widget.standaloneMode) {
        if (mounted) {
          setState(() {
            _errorMessage =
            'No fingerprint sensor on this device.\n'
                'Please go back and select Facial Recognition.';
          });
        }
        return;
      }
      _navigateToFacialRecognition();
    }
  }

  Future<bool> _hasBiometricHardware() async {
    if (_isDemo) return true;
    if (kIsWeb) return false;

    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported && canCheck;
    } catch (_) {
      return true;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 AUTHENTICATE — DEMO requires internet
  //    • Offline → snackbar + block
  //    • Online  → force native prompt, always succeed
  // ═══════════════════════════════════════════════════════════════
  Future<void> _authenticate() async {
    if (!mounted) return;

    // ═══════════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — REQUIRES INTERNET
    // ═══════════════════════════════════════════════════════════════
    if (_isDemo) {
      _secureLog('═══════════════════════════════════════════');
      _secureLog('🎭 [DemoMode] _authenticate() STARTED');
      _secureLog('═══════════════════════════════════════════');

      // 🔌 STEP 1: CHECK INTERNET FIRST
      final online = _isOnlineSafely();
      _secureLog('🎭 [DemoMode] online check = $online');

      if (!online) {
        _secureLog('🎭 [DemoMode] ⛔ BLOCKED — no internet connection');
        _showOfflineSnack(
            'Internet connection is required for Demo Mode.');
        return;
      }

      if (mounted) {
        setState(() {
          _fpState = _FpState.scanning;
          _errorMessage = null;
        });
      }

      bool attemptedPrompt = false;

      if (!kIsWeb) {
        try {
          // 1️⃣ Check if device has biometric hardware
          final isSupported = await _localAuth.isDeviceSupported();
          _secureLog('🎭 [DemoMode] isDeviceSupported = $isSupported');

          if (isSupported) {
            // 2️⃣ Log what's available (for debugging)
            try {
              final canCheck = await _localAuth.canCheckBiometrics;
              final enrolled = await _localAuth.getAvailableBiometrics();
              _secureLog('🎭 [DemoMode] canCheckBiometrics = $canCheck');
              _secureLog('🎭 [DemoMode] enrolled = $enrolled');
              _secureLog(
                  '🎭 [DemoMode] hasFingerprint = ${enrolled.contains(BiometricType.fingerprint)}');
            } catch (e) {
              _secureLog('🎭 [DemoMode] Diagnostics error: $e');
            }

            // 3️⃣ FORCE the prompt
            _secureLog('🎭 [DemoMode] 🚀 FORCING authenticate()...');
            attemptedPrompt = true;

            try {
              final result = await _localAuth
                  .authenticate(
                localizedReason:
                'Demo: Scan your fingerprint or enter PIN to continue',
                options: const AuthenticationOptions(
                  biometricOnly: false, // 👈 PIN fallback
                  stickyAuth: true,
                  useErrorDialogs: true,
                ),
              )
                  .timeout(_biometricTimeout);

              _secureLog(
                  '🎭 [DemoMode] ✅ Prompt returned: $result (demo: ignored)');
            } on PlatformException catch (pe) {
              _secureLog('🎭 [DemoMode] ⚠️ PlatformException:');
              _secureLog('   code    = ${pe.code}');
              _secureLog('   message = ${pe.message}');
            } on TimeoutException {
              _secureLog('🎭 [DemoMode] ⏱️ Prompt timed out (45s)');
            } catch (e) {
              _secureLog('🎭 [DemoMode] ⚠️ Generic error: $e');
            }
          } else {
            _secureLog(
                '🎭 [DemoMode] ❌ Device has NO biometric hardware — skip prompt');
          }
        } catch (e) {
          _secureLog('🎭 [DemoMode] ⚠️ Outer error: $e');
        }
      } else {
        _secureLog('🎭 [DemoMode] 🌐 Web — skip native prompt');
      }

      if (!attemptedPrompt) {
        _secureLog('🎭 [DemoMode] Simulating 1s delay (no prompt)');
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      if (!mounted) return;

      // 🔌 STEP 2: Re-check internet before proceeding
      if (!_isOnlineSafely()) {
        _secureLog(
            '🎭 [DemoMode] ⛔ Connection lost during prompt — blocking');
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
        _showOfflineSnack(
            'Internet connection lost. Please reconnect to continue.');
        return;
      }

      _secureLog('🎭 [DemoMode] ✅ Proceeding to SUCCESS (always)');

      // ✅ ALWAYS SUCCEED in demo
      setState(() {
        _fpState = _FpState.success;
        _justRegistered = false;
        _errorMessage = null;
      });

      _pulseCtrl.stop();
      _ringCtrl.stop();
      _successCtrl.forward();

      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;

      // 🚀 Direct to Clock-In Success (standalone) or Facial (login flow)
      if (widget.standaloneMode) {
        _goToClockInSuccess();
      } else {
        _navigateToFacialRecognition();
      }
      return;
    }

    // NORMAL MODE (unchanged)
    if (!_registrationCheckComplete) {
      _onFailure('Please wait — verifying registration status...');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!_registrationCheckComplete) {
          await _checkFingerprintRegistration();
          if (mounted) {
            setState(() => _registrationCheckComplete = true);
          }
        }
      });
      return;
    }

    if (!kIsWeb && _deviceCompromised) {
      _onFailure('This device is flagged as compromised. Access blocked.');
      return;
    }

    if (_isAuthLockedOut) {
      _onFailure('Locked. Try again in ${_remainingLockoutText()}.');
      return;
    }

    if (!_preAuthVerified) {
      _onFailure('Security check failed. Please log in again.');
      return;
    }

    if (_isRateLimited()) return;

    _lastAuthAttemptAt = DateTime.now();

    if (kIsWeb) {
      setState(() {
        _fpState = _FpState.scanning;
        _errorMessage = null;
      });
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      if (widget.standaloneMode) {
        await _onSuccess();
      } else {
        _navigateToFacialRecognition();
      }
      return;
    }

    if (!_hardwareChecked) {
      final hasHardware = await _hasBiometricHardware();
      _hardwareChecked = true;
      _noBiometricHardware = !hasHardware;
    }

    if (_noBiometricHardware) {
      if (widget.standaloneMode) {
        _onFailure('No fingerprint sensor on this device.');
        return;
      }
      _navigateToFacialRecognition();
      return;
    }

    setState(() {
      _fpState = _FpState.scanning;
      _errorMessage = null;
      _showCleanupHint = false;
      if (_isRegistering) {
        _regPhase = _RegPhase.capturingStep;
      }
    });

    await _authenticateNative();
  }

  Future<void> _authenticateNative() async {
    if (_isDemo) return;

    final attemptTime = DateTime.now();
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canCheck || !isSupported) {
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'This device does not support fingerprint sensors.\n'
                'Proceeding to facial recognition...');
        return;
      }

      final enrolled = await _localAuth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'No fingerprint enrolled in device settings.\n'
                'Proceeding to facial recognition...');
        return;
      }

      String reason;
      if (_fingerprintRegistered) {
        reason = 'Scan your registered fingerprint to verify';
      } else {
        final stepName = _regStepNames[_currentRegStep];
        reason = 'Step ${_currentRegStep + 1} of $_totalRegSteps: $stepName';
      }

      final authenticated = await _localAuth
          .authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      )
          .timeout(_biometricTimeout);

      final durationMs =
          DateTime.now().difference(attemptTime).inMilliseconds;

      if (!authenticated) {
        _sessionFailCount++;
        _consecutiveFailsForCleanup++;

        if (_consecutiveFailsForCleanup >= _consecutiveFailsToShowCleanup) {
          if (mounted) setState(() => _showCleanupHint = true);
        }

        await _recordFailedAuthAttempt();
        await _logSecurityEvent(
          type: 'fp_failed',
          severity: _authFailedAttempts >= 2 ? 'high' : 'medium',
          details: 'Failed attempt #$_authFailedAttempts '
              'sessionFail=$_sessionFailCount '
              '${_isRegistering ? "step=${_currentRegStep + 1}" : ""}',
        );

        if (_sessionFailCount >= _maxSessionFails) {
          if (!mounted) return;
          await _autoProceedToFaceScan(
              'Fingerprint verification failed.\n'
                  'Switching to facial recognition...');
          return;
        }

        final remaining = _maxAuthAttempts - _authFailedAttempts;
        if (_isAuthLockedOut) {
          _onFailure('Too many failed attempts. Locked for '
              '${_remainingLockoutText()}.');
        } else if (remaining <= 1 && remaining > 0) {
          _onFailure('⚠️ $remaining attempt left before lockout.');
        } else {
          if (!mounted) return;
          setState(() {
            _fpState = _FpState.idle;
            _errorMessage = null;
          });
        }
        return;
      }

      _consecutiveFailsForCleanup = 0;
      _showCleanupHint = false;
      _osLockedOut = false;
      _osLockoutUntil = null;

      if (durationMs < _minValidBiometricMs) {
        await _recordFailedAuthAttempt();
        _onFailure('Security check failed. Try again.');
        return;
      }

      if (_fingerprintRegistered && _networkState == _NetworkState.online) {
        String? storedHash;
        try {
          final docId = await _resolveEmployeeDocId();
          if (docId != null) {
            final doc = await FirebaseFirestore.instance
                .collection('employees')
                .doc(docId)
                .get()
                .timeout(const Duration(seconds: 6));
            storedHash = doc.data()?['fingerprintCredentialHash']?.toString();
          }
        } catch (_) {}

        final status = await _verifyCredential(
          storedHashFromFirestore: storedHash,
        );
        _lastCredentialStatus = status;

        if (status != _CredentialStatus.ok) {
          unawaited(_logSecurityEvent(
            type: 'fp_credential_soft_warning',
            severity: 'low',
            details: 'Status=$status durationMs=$durationMs (proceeding)',
          ));
          unawaited(_refreshCredentialInBackground());
        }
      } else if (_fingerprintRegistered) {
        final localStatus = await _verifyCredential(
          storedHashFromFirestore: null,
        );
        _lastCredentialStatus = localStatus;
      }

      await _resetAuthAttempts();
      _sessionFailCount = 0;

      if (_isRegistering) {
        final snapshot = await _captureEnrollmentSnapshot();
        final stepHash = _buildStepHash(_currentRegStep, snapshot.join(','));
        _regStepHashes.add(stepHash);

        await _logSecurityEvent(
          type: 'fp_reg_step_captured',
          severity: 'info',
          details: 'Step ${_currentRegStep + 1}/$_totalRegSteps '
              '(${_regStepNames[_currentRegStep]}) in ${durationMs}ms',
        );

        _currentRegStep++;

        if (_currentRegStep >= _totalRegSteps) {
          _regPhase = _RegPhase.completed;
          await _onSuccess();
        } else {
          if (!mounted) return;
          setState(() {
            _fpState = _FpState.idle;
            _errorMessage = null;
          });
          _pulseCtrl.repeat(reverse: true);
          _ringCtrl.repeat();
          await Future.delayed(const Duration(milliseconds: 400));
        }
        return;
      }

      await _logSecurityEvent(
        type: 'fp_success',
        severity: 'info',
        details: 'Fingerprint verified in ${durationMs}ms',
      );
      await _onSuccess();
    } on TimeoutException {
      _sessionFailCount++;
      await _recordFailedAuthAttempt();
      _onFailure('Fingerprint scan timed out. Please try again.');
    } on PlatformException catch (e) {
      await _handlePlatformException(e);
    } catch (e) {
      final msg = e.toString();

      if (msg.contains('no_fragment_activity') ||
          msg.contains('NotAvailable') ||
          msg.contains('NotEnrolled')) {
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'Fingerprint not available.\n'
                'Proceeding to facial recognition...');
      } else if (msg.contains('LockedOut') ||
          msg.contains('PermanentlyLockedOut')) {
        await _recordFailedAuthAttempt();
        _onFailure('Too many attempts.\nTry again later.');
      } else if (msg.contains('UserCancel') || msg.contains('canceled')) {
        if (!mounted) return;
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
      } else {
        await _recordFailedAuthAttempt();
        _onFailure('Biometric error: $msg');
      }
    }
  }

  Future<void> _handlePlatformException(PlatformException e) async {
    if (_isDemo) return;

    _lastErrorCode = e.code;
    final code = e.code.toLowerCase();

    if (code.contains('lockedout') && !code.contains('permanently')) {
      _osLockedOut = true;
      _osLockoutUntil = DateTime.now().add(const Duration(seconds: 30));
      _onFailure('OS biometric lockout.\n'
          'Please wait 30 seconds and try again.');
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _osLockedOut = false;
            _osLockoutUntil = null;
          });
        }
      });
      return;
    }

    if (code.contains('permanentlylockedout')) {
      _onFailure('OS biometrics locked.\n'
          'Please unlock your device with PIN/pattern first, then try again.');
      return;
    }

    if (code.contains('notenrolled')) {
      if (!mounted) return;
      await _autoProceedToFaceScan(
          'No fingerprint enrolled in device settings.\n'
              'Proceeding to facial recognition...');
      return;
    }

    if (code.contains('notavailable') || code.contains('hwnotavailable')) {
      if (!mounted) return;
      await _autoProceedToFaceScan(
          'Fingerprint sensor not available.\n'
              'Proceeding to facial recognition...');
      return;
    }

    if (code.contains('passcodenotset') ||
        code.contains('devicecredentialsnotset')) {
      _onFailure('Please set up a PIN or pattern on your device first.');
      return;
    }

    if (code.contains('usercancel') || code.contains('canceled')) {
      if (!mounted) return;
      setState(() {
        _fpState = _FpState.idle;
        _errorMessage = null;
      });
      return;
    }

    _sessionFailCount++;
    await _recordFailedAuthAttempt();
    _onFailure('Biometric error (${e.code}).\nPlease try again.');
  }

  Future<void> _autoProceedToFaceScan(String message) async {
    if (_isDemo) return;

    if (!mounted) return;

    if (widget.standaloneMode) {
      setState(() {
        _fpState = _FpState.error;
        _errorMessage = message;
      });
      _shakeCtrl.forward(from: 0);
      return;
    }

    setState(() {
      _fpState = _FpState.idle;
      _errorMessage = message;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _navigateToFacialRecognition();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 SAVE REGISTRATION — DEMO skip
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _saveFingerprintRegistration() async {
    if (_isDemo) {
      _secureLog('🎭 [DemoMode] Skipping fingerprint save');
      return true;
    }

    try {
      final docId = await _resolveEmployeeDocId();
      if (docId == null || docId.isEmpty) {
        _secureLog('❌ [FP-Save] Cannot resolve doc ID — ABORT');
        return false;
      }

      final employeeId = _employeeIdForAttendance;
      if (employeeId.isEmpty) {
        _secureLog('❌ [FP-Save] employeeId empty — ABORT');
        return false;
      }

      final cred = await _buildAndStoreCredential();
      final now = FieldValue.serverTimestamp();

      final payload = <String, dynamic>{
        'fingerprintEnrolled': true,
        'fingerprintEnrolledAt': now,
        'fingerprintDeviceModel': _deviceModel,
        'fingerprintDeviceBinding': _deviceBinding,
        'fingerprintDeviceFingerprint': _deviceFingerprint,
        'fingerprintCredentialHash': cred.hash,
        'fingerprintEnrollmentSnapshot': cred.snapshot,
        'fingerprintRegistrationSteps': _totalRegSteps,
        'fingerprintStepHashes': _regStepHashes,
        'fingerprintRegistrationMethod': 'double_confirm_local_auth',
        'fingerprintRegisteredBy': widget.employee.id,
        'fingerprintMethod': 'local_auth_v2',
        'employeeId': employeeId,
        'updatedAt': now,
      };

      if (_networkState != _NetworkState.online) {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'employees',
          docId: docId,
          data: payload,
        );
        _secureLog('📥 [FP-Save] Offline — queued to sync later');
      } else {
        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(docId)
              .set(payload, SetOptions(merge: true))
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          await OfflineAttendanceService.instance.enqueue(
            collection: 'employees',
            docId: docId,
            data: payload,
          );
        }
      }

      final activityPayload = <String, dynamic>{
        'type': 'fingerprint_registered',
        'action': 'Fingerprint Registered (Double Confirm)',
        'employeeId': docId,
        'employee_id': employeeId,
        'employee_name': widget.employee.fullName,
        'email': widget.employee.email,
        'verification_method': 'fingerprint',
        'registration_steps': _totalRegSteps,
        'device': _deviceModel,
        'device_binding': _deviceBinding,
        'session_nonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': now,
      };

      if (_networkState != _NetworkState.online) {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'activity_logs',
          data: activityPayload,
        );
      } else {
        try {
          await FirebaseFirestore.instance
              .collection('activity_logs')
              .add(activityPayload);
        } catch (_) {
          await OfflineAttendanceService.instance.enqueue(
            collection: 'activity_logs',
            data: activityPayload,
          );
        }
      }

      await _cacheEnrollmentStatus(true, DateTime.now());
      await _logSecurityEvent(
        type: 'fp_registered',
        severity: 'info',
        details: 'Double-confirm fingerprint registration for '
            '${widget.employee.fullName} on $_deviceModel',
      );

      return true;
    } catch (e, st) {
      _secureLog('❌ [FP-Save] EXCEPTION: $e\n$st');
      return false;
    }
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() {
      _fpState = _FpState.success;
      _errorMessage = null;
    });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    _sessionFailCount = 0;
    _consecutiveFailsForCleanup = 0;
    _showCleanupHint = false;

    if (_isDemo) {
      _justRegistered = false;
    } else if (!_fingerprintRegistered) {
      final ok = await _saveFingerprintRegistration();
      if (!mounted) return;

      if (ok) {
        _justRegistered = true;
        setState(() {
          _fingerprintRegistered = true;
          _fingerprintRegisteredAt = DateTime.now();
          _regPhase = _RegPhase.completed;
        });
        _resolvedDocId = null;
      } else {
        setState(() {
          _fpState = _FpState.error;
          _errorMessage = 'Failed to save registration.\n'
              'Please check your internet and try again.';
          _currentRegStep = 0;
          _regStepHashes.clear();
          _regPhase = _RegPhase.idle;
        });
        _shakeCtrl.forward(from: 0);
        _successCtrl.reset();
        _pulseCtrl.repeat(reverse: true);
        _ringCtrl.repeat();

        await Future.delayed(const Duration(seconds: 3));
        if (mounted && _fpState == _FpState.error) {
          setState(() {
            _fpState = _FpState.idle;
            _errorMessage = null;
          });
        }
        return;
      }
    } else {
      _justRegistered = false;
    }

    if (!_isDemo) {
      final logPayload = <String, dynamic>{
        'type': _justRegistered
            ? 'fingerprint_registered'
            : 'fingerprint_verified',
        'employeeId': widget.employee.id,
        'employee_id': widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email': widget.employee.email,
        'session_nonce': _sessionNonce,
        'device_binding': _deviceBinding,
        'mode': widget.standaloneMode ? 'standalone' : 'login',
        'stage': 'fingerprint',
        'is_first_registration': _justRegistered,
        'registration_steps': _justRegistered ? _totalRegSteps : null,
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : _deviceModel,
      };

      if (_networkState != _NetworkState.online) {
        try {
          await OfflineAttendanceService.instance.enqueue(
            collection: 'activity_logs',
            data: logPayload,
          );
        } catch (_) {}
      } else {
        try {
          await FirebaseFirestore.instance
              .collection('activity_logs')
              .add(logPayload)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          try {
            await OfflineAttendanceService.instance.enqueue(
              collection: 'activity_logs',
              data: logPayload,
            );
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;

    _navTimer?.cancel();
    _navTimer = Timer(const Duration(milliseconds: 1400), () async {
      if (!mounted) return;

      // 🔌 Demo mode — re-check internet before proceeding
      if (_isDemo && !_isOnlineSafely()) {
        _secureLog('🎭 [DemoMode] Lost internet before navigation');
        _showOfflineSnack(
            'Internet connection lost. Please reconnect to continue.');
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
        _successCtrl.reset();
        _pulseCtrl.repeat(reverse: true);
        _ringCtrl.repeat();
        return;
      }

      if (widget.standaloneMode) {
        await _handleClockIn();
        return;
      }

      _navigateToFacialRecognition();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔥 CLOCK-IN
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleClockIn() async {
    if (_isDemo) {
      _secureLog('🎭 [DemoMode] Skipping clock-in — going to success screen');
      _goToClockInSuccess();
      return;
    }

    setState(() => _isCheckingGeofence = true);
    GeofenceService.instance.invalidateCache();

    final canProceed = await _checkGeofence();
    if (!canProceed) {
      if (mounted) setState(() => _isCheckingGeofence = false);
      return;
    }

    await _writeAttendanceLog();

    if (!mounted) return;
    setState(() => _isCheckingGeofence = false);

    _goToClockInSuccess();
  }

  Future<bool> _checkGeofence() async {
    if (_isDemo) return true;

    try {
      GeofenceResult? geoResult;

      try {
        geoResult = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: widget.employee.id)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        _secureLog('❌ Geofence error: $e');
      }

      if (geoResult != null) {
        _lastGeoResult = geoResult;
        _lastDistanceMeters = geoResult.distanceMeters;
        _lastAccuracyMeters = geoResult.accuracyMeters;
        _lastRadiusUsed = geoResult.radiusUsed;
        _lastLocationName = geoResult.matchedLocationName;
        _lastZoneStatus = geoResult.status?.toString();
        _lastUsedTolerance = geoResult.usedTolerance;
        _geofenceVerifiedOffline = false;

        try {
          final pos = geoResult.position;
          if (pos != null) {
            _lastLatitude = pos.latitude;
            _lastLongitude = pos.longitude;
          }
        } catch (_) {}

        try {
          final dynamic r = geoResult;
          final dynamic mock = (r as dynamic).isMockLocation;
          if (mock is bool) _lastMockLocationDetected = mock;
        } catch (_) {}
      }

      final isAllowed = geoResult?.isAllowed ?? false;
      final isExempted = geoResult?.isExempted ?? false;

      if (isAllowed || isExempted) {
        _secureLog('✅ [FP] Geofence allowed');
        return true;
      }

      if (_networkState == _NetworkState.offline && geoResult == null) {
        _secureLog(
            '📴 [FP] Offline — allowing clock-in with pending geofence');
        _geofenceVerifiedOffline = true;
        _lastLocationName = 'Pending verification';
        _lastZoneStatus = 'offline_pending';
        return true;
      }

      if (geoResult == null) {
        await _logSecurityEvent(
          type: 'geofence_service_error',
          severity: 'high',
          details: 'Geofence returned null — blocking clock-in',
        );
        if (mounted) {
          setState(() {
            _fpState = _FpState.error;
            _errorMessage = 'Unable to verify location.\nPlease try again.';
          });
          _shakeCtrl.forward(from: 0);
        }
        return false;
      }

      final dist = geoResult.distanceMeters;
      final radius = geoResult.radiusUsed;
      final nearest = geoResult.matchedLocationName ?? 'Unknown';

      if (mounted) {
        setState(() {
          _fpState = _FpState.error;
          _errorMessage = '📍 Outside work zone\n'
              'Nearest: $nearest\n'
              'Distance: ${dist?.toStringAsFixed(0) ?? "?"}m '
              '(allowed: ${radius?.toStringAsFixed(0) ?? "?"}m)';
        });
        _shakeCtrl.forward(from: 0);
      }
      return false;
    } catch (e) {
      _secureLog('🚨 Geofence exception: $e');
      if (_networkState == _NetworkState.offline) {
        _geofenceVerifiedOffline = true;
        _lastLocationName = 'Pending verification';
        _lastZoneStatus = 'offline_pending';
        return true;
      }
      return false;
    }
  }

  String get _employeeIdForAttendance {
    if (_isDemo) return DemoModeService.demoEmployee.employeeId;

    final empId = widget.employee.employeeId;
    if (empId.isNotEmpty) return empId;
    return widget.employee.id;
  }

  String _computeZoneType() {
    if (_isDemo) return 'inside';

    final role = widget.employee.position.toLowerCase();
    final dept = widget.employee.department.toLowerCase();
    if (role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider')) {
      return 'driver';
    }
    if (widget.employee.wfhAccess) return 'wfh';
    return 'inside';
  }

  Future<void> _writeAttendanceLog() async {
    if (_isDemo) {
      _secureLog('🎭 [DemoMode] Skipping attendance log write');
      return;
    }

    try {
      final employeeId = _employeeIdForAttendance;
      if (employeeId.isEmpty) return;

      final alreadyClockedIn =
      await ClockStatusService.instance.isCurrentlyClockedIn(employeeId);
      final attendanceType = alreadyClockedIn ? 'OUT' : 'IN';
      final isClockIn = attendanceType == 'IN';

      final now = DateTime.now();
      final todayStr = now.toIso8601String().substring(0, 10);
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';

      final employeeName = widget.employee.fullName;
      final employeeEmail = widget.employee.email;
      final zoneType = _computeZoneType();

      final remarks = _geofenceVerifiedOffline
          ? 'fingerprint_match|pending_geofence_verification'
          : 'fingerprint_match';

      AttendanceResult? offlineResult;
      try {
        offlineResult =
        await OfflineAttendanceService.instance.logAttendance(
          employeeId: employeeId,
          employeeName: employeeName,
          employeeEmail: employeeEmail,
          type: attendanceType,
          timestamp: now,
          latitude: _lastLatitude,
          longitude: _lastLongitude,
          distance: _lastDistanceMeters,
          insideZone: !_geofenceVerifiedOffline,
          device: _deviceModel,
          remarks: remarks,
          zoneType: zoneType,
        );
        _secureLog(
            '💾 [FP] Local save: queued=${offlineResult.queued} id=${offlineResult.localId}');
      } catch (e) {
        _secureLog('❌ [FP] OfflineAttendanceService.logAttendance failed: $e');
        await _logSecurityEvent(
          type: 'attendance_local_save_failed',
          severity: 'critical',
          details: 'Failed to save attendance locally: $e',
        );
      }

      final needsDirectWrite = offlineResult != null &&
          !offlineResult.queued &&
          _networkState == _NetworkState.online;

      if (!needsDirectWrite) {
        _secureLog('📥 [FP] Attendance queued — skipping direct Firestore');
        await _emitPendingCount();
        return;
      }

      final locationPayload = <String, dynamic>{
        if (_lastLatitude != null) 'latitude': _lastLatitude,
        if (_lastLongitude != null) 'longitude': _lastLongitude,
        if (_lastLatitude != null && _lastLongitude != null)
          'coordinates': GeoPoint(_lastLatitude!, _lastLongitude!),
        if (_lastDistanceMeters != null)
          'distance_meters': _lastDistanceMeters,
        if (_lastDistanceMeters != null)
          'distance_from_office_m': _lastDistanceMeters,
        if (_lastAccuracyMeters != null)
          'gps_accuracy_meters': _lastAccuracyMeters,
        if (_lastRadiusUsed != null) 'radius_used_meters': _lastRadiusUsed,
        if (_lastLocationName != null) 'location_name': _lastLocationName,
        if (_lastLocationName != null)
          'matched_location_name': _lastLocationName,
        if (_lastZoneStatus != null) 'geofence_status': _lastZoneStatus,
        'used_tolerance': _lastUsedTolerance,
        'mock_location': _lastMockLocationDetected,
        if (_geofenceVerifiedOffline) 'pending_geofence_verification': true,
      };

      final activityPayload = <String, dynamic>{
        'type': isClockIn ? 'clock_in' : 'clock_out',
        'action': isClockIn
            ? 'Clocked In (Fingerprint)'
            : 'Clocked Out (Fingerprint)',
        'employeeId': widget.employee.id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'email': employeeEmail,
        'verification_method': 'fingerprint',
        'zone_type': zoneType,
        'time': timeStr,
        'date': todayStr,
        'device': _deviceModel,
        'device_binding': _deviceBinding,
        'device_compromised': _deviceCompromised,
        'platform': kIsWeb ? 'web' : 'mobile',
        'session_nonce': _sessionNonce,
        'timestamp': FieldValue.serverTimestamp(),
        ...locationPayload,
      };

      if (_networkState != _NetworkState.online) {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'activity_logs',
          data: activityPayload,
        );
      } else {
        try {
          await FirebaseFirestore.instance
              .collection('activity_logs')
              .add(activityPayload);
        } catch (_) {
          await OfflineAttendanceService.instance.enqueue(
            collection: 'activity_logs',
            data: activityPayload,
          );
        }
      }

      if (isClockIn) {
        try {
          unawaited(PresenceChallengeService.instance.scheduleForToday(
            employeeId: employeeId,
            clockInAt: now,
          ));
        } catch (_) {}
      }

      try {
        final notifPayload = <String, dynamic>{
          'employeeId': employeeId,
          'employeeName': employeeName,
          'timeStr': timeStr,
          'type': isClockIn ? 'clock_in' : 'clock_out',
          'zoneType': zoneType,
          'attendanceType': attendanceType,
          'timestamp': FieldValue.serverTimestamp(),
        };
        if (_networkState != _NetworkState.online) {
          await OfflineAttendanceService.instance.enqueue(
            collection: 'admin_notifications',
            data: notifPayload,
          );
        } else {
          if (isClockIn) {
            AdminNotificationService.instance.notifyClockIn(
              employeeId: employeeId,
              employeeName: employeeName,
              timeStr: timeStr,
              faceMatchPercent: 100.0,
              wfh: widget.employee.wfhAccess,
              inRange: true,
              zoneType: zoneType,
              distanceMeters: _lastDistanceMeters,
            );
          } else {
            AdminNotificationService.instance.notifyClockOut(
              employeeId: employeeId,
              employeeName: employeeName,
              timeStr: timeStr,
              faceMatchPercent: 100.0,
              wfh: widget.employee.wfhAccess,
              inRange: true,
              zoneType: zoneType,
              distanceMeters: _lastDistanceMeters,
            );
          }
        }
      } catch (_) {}
    } catch (e) {
      _secureLog('❌ _writeAttendanceLog: $e');
    }
  }

  Future<void> _emitPendingCount() async {
    if (_isDemo) return;

    try {
      final c = await OfflineAttendanceService.instance.getPendingCount();
      if (mounted) setState(() => _pendingCount = c);
    } catch (_) {}
  }

  void _goToClockInSuccess() {
    if (!mounted) return;
    final navigator = Navigator.of(context);

    navigator.push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: const Color(0xFF09090B).withOpacity(0.44),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => ClockInSuccessScreen(
          employee: widget.employee,
          arrivalTime: widget.arrivalTime,
          faceMatchPercent: 100.0,
          verificationMethod: 'fingerprint',
          locationName: _isDemo ? 'Demo Location' : _lastLocationName,
          onContinue: () {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => MainScreen(employee: widget.employee),
              ),
                  (route) => false,
            );
          },
        ),
      ),
    );
  }

  Future<void> _navigateToFacialRecognition() async {
    if (widget.standaloneMode) return;

    if (!mounted || _isNavigating) return;
    _isNavigating = true;

    if (!kIsWeb && _deviceCompromised && !_isDemo) {
      _isNavigating = false;
      _onFailure('Device integrity check failed. Access blocked.');
      return;
    }

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FacialRecognitionScreen(
            employee: widget.employee,
            arrivalTime: widget.arrivalTime,
          ),
        ),
      );
    } finally {
      _isNavigating = false;
    }

    if (!mounted) return;
    if (_noBiometricHardware && !_isDemo) {
      _navigateToFacialRecognition();
    }
  }

  void _onFailure(String msg) {
    if (!mounted) return;
    setState(() {
      _fpState = _FpState.error;
      _errorMessage = msg;
    });
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  void _goBack() {
    _navTimer?.cancel();
    _navTimer = null;

    if (_fpState == _FpState.success) {
      setState(() {
        _fpState = _FpState.idle;
        _errorMessage = null;
      });
      _successCtrl.reset();
      _pulseCtrl.repeat(reverse: true);
      _ringCtrl.repeat();
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    if (_isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bgTop,
        body: SafeArea(
          child: Stack(
            children: [
              const DashboardSkeleton(),
              if (_obscureContent) _buildPrivacyShield(),
            ],
          ),
        ),
      );
    }

    final fadeAnim = _fadeAnim ?? const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      body: FadeTransition(
        opacity: fadeAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = _buildContent(tc);

            if (constraints.maxWidth < 768) {
              return Stack(
                children: [
                  content,
                  if (_pendingCount > 0 && !_isDemo) _buildPendingBadge(),
                  if (_obscureContent) _buildPrivacyShield(),
                ],
              );
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [tc.bgTop, tc.bgMid, tc.bgBottom],
                        stops: const [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(child: Container(color: _scrim)),
                ),
                Positioned.fill(
                  child: BsContainer(maxWidth: 480, child: content),
                ),
                if (_pendingCount > 0 && !_isDemo) _buildPendingBadge(),
                if (_obscureContent) _buildPrivacyShield(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPendingBadge() {
    return Positioned(
      top: 12,
      right: 12,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.shade700,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$_pendingCount pending',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 0.55, child: _buildDimmedBackground(tc)),
        IgnorePointer(child: Container(color: _scrim)),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildModalCard(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDimmedBackground(_ThemeColors tc) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tc.bgTop, tc.bgMid, tc.bgBottom],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -130,
          left: -150,
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
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _isDemo
                        ? [_demoAccent, _demoAccentDark]
                        : [_headerStart, _headerEnd],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _goBack,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.chevron_left_rounded,
                                  color: _white, size: 22),
                              SizedBox(width: 4),
                              Text('Back',
                                  style: TextStyle(
                                      color: _white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                            _isDemo
                                ? 'Demo Verify'
                                : (widget.standaloneMode
                                ? 'Verify Identity'
                                : 'Auth & Clock In'),
                            style: const TextStyle(
                                color: _white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 6),
                        Text(
                            _isDemo
                                ? 'Real biometric prompt — always pass'
                                : (widget.standaloneMode
                                ? 'Fingerprint verification'
                                : 'Select your initial verification method'),
                            style:
                            const TextStyle(color: _white, fontSize: 14)),
                        if (_isDemo) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                  Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.science_rounded,
                                        color: Colors.white, size: 12),
                                    SizedBox(width: 6),
                                    Text(
                                      'DEMO MODE',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                              if (_networkState == _NetworkState.offline) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _error.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.cloud_off_rounded,
                                          color: Colors.white, size: 12),
                                      SizedBox(width: 6),
                                      Text(
                                        'OFFLINE',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ] else if (_networkState ==
                            _NetworkState.offline) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_rounded,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 6),
                                Text(
                                  _pendingCount > 0
                                      ? 'Offline — $_pendingCount pending'
                                      : 'Offline mode',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Transform.translate(
                  offset: const Offset(0, -40),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: tc.cardBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(children: [
                      Text(
                          _isDemo
                              ? 'Demo Mode'
                              : (_checkingRegistration
                              ? 'Checking registration...'
                              : _fingerprintRegistered
                              ? (widget.standaloneMode
                              ? 'Fingerprint Verification'
                              : 'Step 1: Initial Login')
                              : 'Register Your Fingerprint'),
                          style: TextStyle(
                              color: _isDemo ? _demoAccent : tc.textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: _dimmedOptionPlaceholder(
                                tc, Icons.contactless_rounded, 'Key Fob')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _dimmedOptionPlaceholder(
                                tc, Icons.key_rounded, 'Use PIN')),
                      ]),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dimmedOptionPlaceholder(
      _ThemeColors tc, IconData icon, String label) {
    return AspectRatio(
      aspectRatio: 0.95,
      child: Container(
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDemo ? _demoAccent : tc.cardBorder,
            width: 1.5,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isDemo ? _demoAccent : tc.cardBorder,
                width: 1.5,
              ),
            ),
            child:
            Icon(icon, color: _isDemo ? _demoAccent : _orange, size: 24),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                  color: tc.textDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Color get _currentModalBorder =>
      _fpState == _FpState.success ? _modalBorderSuccess : _modalBorderDefault;

  Widget _buildModalCard() {
    final locked = _isAuthLockedOut && !_isDemo;
    final blocked = _deviceCompromised && !_isDemo;
    final checking = _isCheckingGeofence && !_isDemo;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 338),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _isDemo
              ? [_demoAccent, _demoAccentDark, const Color(0xFFE63A00)]
              : [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _currentModalBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_isRegistering && _registrationCheckComplete && !_isDemo)
          _buildRegProgressIndicator(),
        _buildIcon(locked: locked || blocked),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
              blocked
                  ? 'Device Blocked'
                  : locked
                  ? 'Locked Out'
                  : checking
                  ? 'Verifying\nLocation...'
                  : _checkingRegistration && !_isDemo
                  ? 'Checking...'
                  : _stateTitle,
              key: ValueKey('$locked-$blocked-$checking-'
                  '$_checkingRegistration-${_fpState}-'
                  '$_fingerprintRegistered-$_currentRegStep-$_isDemo'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500,
                  height: 1.1)),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
              blocked
                  ? 'This device failed the security integrity check.\n'
                  'Please contact your administrator.'
                  : locked
                  ? 'Too many failed attempts.\nTry again in '
                  '${_remainingLockoutText()}'
                  : checking
                  ? 'Checking your role and location...'
                  : _checkingRegistration && !_isDemo
                  ? 'Verifying if your fingerprint is already registered...'
                  : (_errorMessage ?? _stateSubtitle),
              key: ValueKey(
                  'sub_${_errorMessage ?? _fpState}_'
                      '$locked-$blocked-$checking-$_checkingRegistration-'
                      '$_fingerprintRegistered-$_currentRegStep-'
                      '$_showCleanupHint-$_osLockedOut-'
                      '$_pendingCount-${_networkState.name}-$_isDemo'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _white70, fontSize: 14, height: 1.4)),
        ),
        if (locked && !blocked) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_rounded,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text('Lockout: ${_remainingLockoutText()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
        if (blocked) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('INTEGRITY FAILED',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 28),
        if (!kIsWeb &&
            !_noBiometricHardware &&
            !locked &&
            !blocked &&
            !checking &&
            (!_checkingRegistration || _isDemo) &&
            (_fpState == _FpState.idle || _fpState == _FpState.error))
          _buildCancelButton(),
        if (_networkState == _NetworkState.offline &&
            _pendingCount > 0 &&
            !_isDemo) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_upload_outlined,
                    color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Text(
                  '$_pendingCount record${_pendingCount == 1 ? "" : "s"} '
                      'queued for sync',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildRegProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalRegSteps, (i) {
              final done = i < _currentRegStep;
              final active = i == _currentRegStep;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: active ? 40 : 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: done
                        ? _success
                        : active
                        ? _white
                        : _white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 12)
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Step ${_currentRegStep + 1} of $_totalRegSteps',
            style: const TextStyle(
              color: _white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon({required bool locked}) {
    Color iconColor;
    if (_isDemo) {
      iconColor = _demoAccent;
    } else if (locked) {
      iconColor = _error;
    } else {
      switch (_fpState) {
        case _FpState.success:
          iconColor = _success;
          break;
        case _FpState.error:
          iconColor = _error;
          break;
        default:
          iconColor = _modalGradTop;
      }
    }

    final pulseAnim = _pulseAnim ?? const AlwaysStoppedAnimation(1.0);
    final ringAnim = _ringAnim ?? const AlwaysStoppedAnimation(0.0);
    final successAnim = _successAnim ?? const AlwaysStoppedAnimation(0.0);
    final shakeAnim = _shakeAnim ?? const AlwaysStoppedAnimation(0.0);

    final canTap = _isDemo
        ? (_fpState == _FpState.idle || _fpState == _FpState.error)
        : (!locked &&
        !_deviceCompromised &&
        !_isCheckingGeofence &&
        !_checkingRegistration &&
        _registrationCheckComplete &&
        !_osLockedOut &&
        (_fpState == _FpState.idle || _fpState == _FpState.error));

    return AnimatedBuilder(
      animation:
      Listenable.merge([pulseAnim, ringAnim, successAnim, shakeAnim]),
      builder: (_, __) {
        final shakeX = _fpState == _FpState.error
            ? shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canTap ? _authenticate : null,
            child: Stack(alignment: Alignment.center, children: [
              if (_fpState == _FpState.scanning ||
                  _isCheckingGeofence ||
                  (_checkingRegistration && !_isDemo))
                Transform.rotate(
                  angle: ringAnim.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(132, 132),
                    painter: _DashRingPainter(
                        color: _white.withValues(alpha: 0.5), dashCount: 14),
                  ),
                ),
              if (_fpState != _FpState.success && !locked)
                Transform.scale(
                  scale: pulseAnim.value,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              Transform.scale(
                scale: _fpState == _FpState.success
                    ? (0.85 + 0.15 * successAnim.value)
                    : 1.0,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(16),
                    border: _fpState == _FpState.success
                        ? Border.all(
                        color:
                        _isDemo ? _demoAccent : _successRing,
                        width: 3)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: locked
                      ? const Icon(Icons.lock_rounded,
                      color: _error, size: 48)
                      : _fpState == _FpState.success
                      ? Icon(Icons.verified_user_rounded,
                      color: iconColor, size: 46)
                      : _buildCurrentIcon(iconColor),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildCurrentIcon(Color iconColor) {
    if (_checkingRegistration && !_isDemo) {
      return Icon(Icons.hourglass_top_rounded, color: iconColor, size: 48);
    }

    if (_isDemo) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.fingerprint_rounded,
              color: _demoAccent.withValues(alpha: 0.3), size: 48),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _demoAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.science_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      );
    }

    if (_isRegistering) {
      final icon =
      _regStepIcons[_currentRegStep.clamp(0, _regStepIcons.length - 1)];
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.fingerprint_rounded,
              color: iconColor.withValues(alpha: 0.3), size: 48),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _modalGradTop,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
          ),
        ],
      );
    }

    return Icon(
      _fingerprintRegistered
          ? Icons.fingerprint_rounded
          : Icons.app_registration_rounded,
      color: iconColor,
      size: 48,
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _onCancelTapped,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _cancelPressed ? const Color(0xFFF3F3F3) : _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isDemo ? _demoAccent : _cancelBorder,
            width: 1.15,
          ),
        ),
        child: Center(
          child: Text(
            _isDemo ? 'Exit Demo' : _buildCancelLabel(),
            style: TextStyle(
              color: _isDemo ? _demoAccent : _cancelText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _buildCancelLabel() {
    if (_isRegistering) {
      if (_currentRegStep > 0) {
        return 'Cancel Registration (${_currentRegStep}/$_totalRegSteps)';
      }
      return 'Cancel Registration';
    }
    if (widget.standaloneMode) {
      return _fingerprintRegistered
          ? 'Cancel Verification'
          : 'Cancel Registration';
    }
    return 'Cancel Authentication';
  }

  void _onCancelTapped() async {
    _navTimer?.cancel();
    _navTimer = null;

    setState(() => _cancelPressed = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _cancelPressed = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    if (widget.standaloneMode) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    _navigateToFacialRecognition();
  }

  String get _stateTitle {
    if (_isDemo) {
      switch (_fpState) {
        case _FpState.idle:
          return 'Demo\nFingerprint';
        case _FpState.scanning:
          return 'Scanning...';
        case _FpState.success:
          return 'Demo\nVerified!';
        case _FpState.error:
          return 'Try Again';
      }
    }

    if (_deviceCompromised) return 'Device Blocked';
    if (_checkingRegistration) return 'Checking...';
    switch (_fpState) {
      case _FpState.idle:
        if (_isRegistering) {
          if (_currentRegStep == 0) return 'Register\nFingerprint';
          return 'Step ${_currentRegStep + 1} of $_totalRegSteps';
        }
        return 'Fingerprint Required';
      case _FpState.scanning:
        if (_isRegistering) {
          return 'Scanning ${_regStepNames[_currentRegStep]}...';
        }
        return 'Scanning\nFingerprint...';
      case _FpState.success:
        return _justRegistered ? 'Registered!' : 'Verified!';
      case _FpState.error:
        return 'Try Again';
    }
  }

  String get _stateSubtitle {
    if (_isDemo) {
      // 🔌 Offline state
      if (_networkState == _NetworkState.offline) {
        switch (_fpState) {
          case _FpState.idle:
            return '📴 No internet connection.\n\n'
                'Internet is required to use\n'
                'Demo Mode. Please connect first.';
          case _FpState.scanning:
            return 'Checking connection...';
          case _FpState.success:
            return 'Demo verification complete.\nProceeding to Clock-In...';
          case _FpState.error:
            return 'No internet. Please connect your device.';
        }
      }

      // ✅ Online state
      switch (_fpState) {
        case _FpState.idle:
          return 'Tap the scanner to open fingerprint prompt.\n\n'
              'Demo mode: real biometric prompt,\n'
              'but continues even if cancelled.';
        case _FpState.scanning:
          return 'Waiting for biometric prompt...';
        case _FpState.success:
          return 'Demo verification complete.\nProceeding to Clock-In...';
        case _FpState.error:
          return 'Please try again.';
      }
    }

    if (_deviceCompromised) {
      return 'Device integrity check failed.\nAccess blocked.';
    }
    if (_checkingRegistration) {
      return 'Verifying if your fingerprint is already registered...';
    }

    if (_showCleanupHint) {
      return '⚠️ Fingerprint sensor might be dirty.\n'
          'Please wipe it with a clean, dry cloth\n'
          'and wipe your finger too.';
    }

    if (_osLockedOut) {
      return 'OS biometric lockout.\n'
          'Wait 30 seconds before retrying.';
    }

    if (_isRegistering) {
      switch (_fpState) {
        case _FpState.idle:
          if (_currentRegStep == 0) {
            return 'We will scan your finger $_totalRegSteps times.\n\n'
                'Use the finger you registered in\n'
                'your phone\'s Settings first.\n\n'
                'Tap to start Step 1.';
          }
          return _regStepInstructions[_currentRegStep];
        case _FpState.scanning:
          return 'Hold your finger steady on the sensor...';
        case _FpState.success:
          return _justRegistered
              ? 'Fingerprint registered successfully!'
              : 'Step ${_currentRegStep + 1} complete!';
        case _FpState.error:
          return 'Fingerprint not recognized.\nTap to try again.';
      }
    }

    switch (_fpState) {
      case _FpState.idle:
        if (_networkState == _NetworkState.offline) {
          return '📴 Offline mode\n\n'
              'Tap the scanner to verify.\n'
              'Your attendance will be saved locally\n'
              'and synced automatically when online.';
        }
        return 'Tap the scanner icon to proceed.\n\n'
            '⚠️ Use the SAME finger you registered\n'
            'in your device Settings.\n\n'
            'Wipe the sensor if it feels dirty.';
      case _FpState.scanning:
        return kIsWeb
            ? 'Preparing camera...'
            : 'Place your finger flat on the sensor\nand hold steady...';
      case _FpState.success:
        return 'Biometric match confirmed.';
      case _FpState.error:
        return 'Fingerprint not recognized.\nTap to try again.';
    }
  }
}

enum _FpState { idle, scanning, success, error }

class _DashRingPainter extends CustomPainter {
  final Color color;
  final int dashCount;
  const _DashRingPainter({required this.color, this.dashCount = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 2;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dashAngle = (2 * math.pi) / dashCount;
    const gapFraction = 0.35;

    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * dashAngle,
        dashAngle * (1 - gapFraction),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashRingPainter old) => old.color != color;
}