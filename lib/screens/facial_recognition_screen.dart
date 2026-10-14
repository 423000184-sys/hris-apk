// lib/screens/facial_recognition_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/face_matcher.dart';
import '../services/clock_status_service.dart';
import '../services/geofence_service.dart';
import '../services/admin_notification_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/device_info_service.dart';
import '../services/face_liveness.dart';
import '../services/security_hardening_service.dart';
import '../services/presence_challenge_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7);
  Color get bgTop => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get outerCardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFECEBE8);
  Color get stepLabelColor =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF8A8A85);
  Color get cancelBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFFFFF);
  Color get cancelPressed =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFF4EE);
  Color get cancelText => const Color(0xFFF05000);
}

enum _NetState { online, offline, checking }

enum _AuthMode { unknown, enroll, verify }

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;
  final PresenceChallenge? challenge;

  const FacialRecognitionScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
    this.challenge,
  });

  @override
  State<FacialRecognitionScreen> createState() =>
      _FacialRecognitionScreenState();
}

class _FacialRecognitionScreenState extends State<FacialRecognitionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool get _isChallenge => widget.challenge != null;

  _FaceState _faceState = _FaceState.idle;
  _AuthMode _authMode = _AuthMode.unknown;
  String? _errorMessage;
  _FaceWarning _faceWarning = _FaceWarning.none;

  CameraController? _camCtrl;
  bool _camReady = false;
  bool _camTried = false;
  bool _cancelPressed = false;
  bool _isProcessing = false;
  bool _isScanning = false;
  String? _camError;

  double _matchScore = 0.0;
  double _matchPercent = 0.0;
  bool _faceMatched = false;

  int _enrollCaptureCount = 0;
  static const int _requiredEnrollCaptures = 3;
  bool _isSavingEnroll = false;
  String _enrollHint = 'Tumingin nang diretso sa camera.';
  DateTime? _lastEnrollCaptureAt;
  static const Duration _enrollCaptureCooldown = Duration(milliseconds: 1200);

  bool _isCheckingGeofence = false;
  bool _isCheckingTemplate = false;
  bool _selfHealTriggered = false;

  String _deviceModel = 'Unknown Device';

  static const double _matchThreshold = 0.68;
  static const double _minSharpnessScore = 12.0;
  static const double _minFaceAreaRatio = 0.06;
  static const double _maxFaceAreaRatio = 0.65;
  static const double _maxHeadYawDeg = 22.0;
  static const double _maxHeadRollDeg = 22.0;
  static const double _maxHeadPitchDeg = 20.0;

  late final FaceDetector _faceDetector;

  _LivenessStep _livenessStep = _LivenessStep.waitingForFace;
  bool _blinkDone = false;
  bool _smileDone = false;

  bool _facePresent = false;
  bool _eyesWereClosed = false;
  int _closedFrames = 0;
  static const int _minClosedFrames = 1;
  static const double _blinkClosedThreshold = 0.45;
  static const double _blinkOpenThreshold = 0.50;
  static const double _smileThreshold = 0.45;
  static const int _maxClosedFramesBeforeStuck = 45;

  DateTime? _livenessStartTime;
  static const int _livenessTimeoutMs = 25000;

  static const double _cameraBoxSize = 300.0;

  final FaceLivenessService _webLiveness = FaceLivenessService();

  static const double _webEyeClosedThreshold = 0.30;
  static const double _webEyeOpenThreshold = 0.35;
  static const double _webSmileThreshold = 0.40;
  static const int _webDetectIntervalMs = 150;

  bool _preAuthValid = false;
  bool _deviceCompromised = false;
  bool _integrityChecked = false;
  bool _obscureContent = false;
  String? _deviceBinding;
  late final String _sessionNonce;

  /// 🆕 Guard para hindi mag-doble-doble ang cancellation notification
  bool _cancelRecorded = false;

  _NetState _networkState = _NetState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _connectivitySub;

  static const String _kPreAuthEmpKey = 'fp_preauth_employee_id';
  static const String _kPreAuthTimeKey = 'fp_preauth_time';
  static const Duration _preAuthValidDuration = Duration(minutes: 30);

  int _rotationCompensation = 0;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;
  late AnimationController _scanLineCtrl;
  late AnimationController _warningCtrl;
  late AnimationController _flashCtrl;
  late AnimationController _matchCountCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;
  late Animation<double> _successAnim;
  late Animation<double> _scanLineAnim;
  late Animation<double> _warningAnim;
  late Animation<double> _flashAnim;
  late Animation<double> _matchCountAnim;

  static const _white = Color(0xFFFFFFFF);
  static const _orange = Color(0xFFF05000);
  static const _success = Color(0xFFCCFF00);
  static const _error = Color(0xFFFF3D00);
  static const _faceGreen = Color(0xFF00E676);
  static const _warning = Color(0xFFFFCC00);
  static const _verifiedGreen = Color(0xFF51FF00);

  // ══════════════════════════════════════════════════════════
  // INIT
  // ══════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _sessionNonce = _generateSessionNonce();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        minFaceSize: 0.08,
      ),
    );

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scanLineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _warningCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _flashCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _matchCountCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

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
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));
    _warningAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _warningCtrl, curve: Curves.easeInOut));
    _flashAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));
    _matchCountAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _matchCountCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();

    _loadDeviceModel();
    _secureLog('📷 Facial recognition ready'
        '${_isChallenge ? " (CHALLENGE MODE)" : ""}');
    _secureLog('🎯 Match threshold: '
        '${(_matchThreshold * 100).toStringAsFixed(0)}%');

    _bootstrapSecurity();

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;

            if (!online) {
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
                _showOfflineOverlay = false;
              });
              _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
                if (mounted && _networkState == _NetState.offline) {
                  setState(() => _showOfflineOverlay = true);
                }
              });
            } else if (_networkState == _NetState.offline) {
              _overlayDelayTimer?.cancel();
              _showOfflineOverlay = false;
              _retryNetworkCheck();
            }
          });
    } catch (e) {
      _secureLog('⚠️ connectivity listen error: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkNetworkAndProceed();
      await _detectMode();
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
      _updateRotationCompensation();
    });
  }

  // ══════════════════════════════════════════════════════════
  // MODE DETECTION
  // ══════════════════════════════════════════════════════════
  Future<void> _detectMode() async {
    if (kIsWeb) {
      _authMode = _AuthMode.verify;
      return;
    }

    try {
      _secureLog('🔍 Detecting mode for ${widget.employee.id}...');
      final hasFace = await FaceMatcher.hasRegisteredFace(widget.employee.id);

      if (!mounted) return;

      if (_isChallenge && !hasFace) {
        _secureLog('❌ [Challenge] No registered face — abort');
        setState(() {
          _authMode = _AuthMode.verify;
          _faceState = _FaceState.error;
          _errorMessage = 'Wala pang registered face ang account mo.\n'
              'Ipa-enroll muna sa admin bago makapag-verify.';
        });
        _shakeCtrl.forward(from: 0);

        unawaited(_recordChallengeFailure('no_registered_face'));

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop(false);
        });
        return;
      }

      setState(() {
        _authMode = hasFace ? _AuthMode.verify : _AuthMode.enroll;
      });

      if (hasFace) {
        _secureLog('✅ Mode: VERIFY${_isChallenge ? " (challenge)" : ""}');
      } else {
        _secureLog('🆕 Mode: ENROLL');
        _enrollHint = 'Unang beses mo — kailangan i-register ang mukha mo.';
      }
    } catch (e) {
      _secureLog('⚠️ _detectMode error: $e');
      if (mounted) {
        setState(() => _authMode = _AuthMode.verify);
      }
    }
  }

  // ══════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════
  void _updateRotationCompensation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final orientation = MediaQuery.of(context).orientation;
        final size = MediaQuery.of(context).size;
        if (orientation == Orientation.portrait) {
          _rotationCompensation = 0;
        } else {
          _rotationCompensation = size.width > size.height ? 90 : 270;
        }
      } catch (_) {}
    });
  }

  Future<bool> _hasNetwork() async {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  Future<void> _checkNetworkAndProceed() async {
    if (!mounted) return;
    setState(() => _networkState = _NetState.checking);

    final hasNet = await _hasNetwork();
    if (!mounted) return;

    if (!hasNet) {
      _overlayDelayTimer?.cancel();
      setState(() {
        _networkState = _NetState.offline;
        _networkErrorMessage =
        'No internet connection.\nPlease check your network and try again.';
        _showOfflineOverlay = false;
      });
      _overlayDelayTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _networkState == _NetState.offline) {
          setState(() => _showOfflineOverlay = true);
        }
      });
      return;
    }

    setState(() => _networkState = _NetState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted) return;
    _overlayDelayTimer?.cancel();
    setState(() {
      _networkState = _NetState.checking;
      _showOfflineOverlay = false;
      _errorMessage = null;
    });
    await _checkNetworkAndProceed();
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _bootstrapSecurity() async {
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (e) {
      _secureLog('⚠️ [Security] FLAG_SECURE failed: $e');
    }

    try {
      final ok =
      await SecurityHardeningService.instance.checkDeviceIntegrity();
      if (!ok) {
        _secureLog('🚨 [Integrity] Compromised');
        await _logSecurityEvent(
          type: 'face_compromised_device',
          severity: 'critical',
          details: SecurityHardeningService.instance.integrityIssues.join(','),
        );
      }
      if (mounted) {
        setState(() {
          _deviceCompromised = !ok;
          _integrityChecked = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _integrityChecked = true);
    }

    await _verifyPreAuthAndSession();

    try {
      _deviceBinding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}
  }

  Future<void> _verifyPreAuthAndSession() async {
    try {
      String? secEmpId;
      try {
        secEmpId = await SecurityHardeningService.instance
            .getCurrentEmployeeId()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _secureLog('⚠️ [PreAuth] Session check failed: $e');
      }

      String? preAuthEmpId;
      int? preAuthTimeMs;
      try {
        final prefs = await SharedPreferences.getInstance();
        preAuthEmpId = prefs.getString(_kPreAuthEmpKey);
        preAuthTimeMs = prefs.getInt(_kPreAuthTimeKey);
      } catch (e) {
        _secureLog('⚠️ [PreAuth] Prefs read failed: $e');
      }

      final targetId = widget.employee.id;
      final sessionMatches =
          secEmpId != null && secEmpId.isNotEmpty && secEmpId == targetId;
      final prefsMatches = preAuthEmpId != null &&
          preAuthEmpId.isNotEmpty &&
          preAuthEmpId == targetId;
      final bothEmpty = (secEmpId == null || secEmpId.isEmpty) &&
          (preAuthEmpId == null || preAuthEmpId.isEmpty);

      if (!sessionMatches && !prefsMatches && !bothEmpty) {
        if (mounted) {
          setState(() {
            _preAuthValid = false;
            _errorMessage = '🚨 Security check failed. Please log in again.';
            _faceState = _FaceState.error;
          });
          _shakeCtrl.forward(from: 0);
        }
        return;
      }

      _preAuthValid = true;
      _secureLog('✅ [Security] Pre-auth OK');
    } catch (e) {
      _secureLog('🚨 [Security] Pre-auth FATAL: $e');
      _preAuthValid = true;
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    try {
      if (!NetworkGuard.instance.isOnline) return;

      final hashDevice = _deviceBinding != null
          ? sha256.convert(utf8.encode(_deviceBinding!)).toString()
          : null;

      await FirebaseFirestore.instance.collection('security_events').add({
        'type': type,
        'severity': severity,
        'details': details,
        'employeeId': widget.employee.id,
        'employeeName': widget.employee.fullName,
        'sessionNonce': _sessionNonce,
        'deviceHash': hashDevice,
        'deviceBinding': _deviceBinding,
        'deviceCompromised': _deviceCompromised,
        'stage': _isChallenge ? 'presence_challenge' : 'facial_recognition',
        if (_isChallenge) 'challengeId': widget.challenge!.id,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('⚠️ Security log error: $e');
    }
  }

  Future<void> _loadDeviceModel() async {
    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (!mounted) return;
      setState(() => _deviceModel = model);
    } catch (e) {
      _secureLog('⚠️ Device model load failed: $e');
    }
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
      if (_isScanning) {
        _stopAllCameraOperations();
      }
    } else if (state == AppLifecycleState.resumed) {
      _updateRotationCompensation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isScanning = false;
    _connectivitySub?.cancel();
    _overlayDelayTimer?.cancel();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    _scanLineCtrl.dispose();
    _warningCtrl.dispose();
    _flashCtrl.dispose();
    _matchCountCtrl.dispose();

    final ctrl = _camCtrl;
    if (ctrl != null) {
      try {
        if (ctrl.value.isStreamingImages) {
          ctrl.stopImageStream().catchError((_) {});
        }
      } catch (_) {}
      try {
        ctrl.dispose();
      } catch (_) {}
    }
    _camCtrl = null;

    _faceDetector.close();

    SecurityHardeningService.instance.disableSecureScreen();

    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // CHALLENGE CANCELLATION RECORDING
  // ══════════════════════════════════════════════════════════
  Future<void> _recordChallengeFailure(String reason) async {
    if (!_isChallenge || widget.challenge == null) return;
    if (_cancelRecorded) {
      _secureLog('ℹ️ [Challenge] Cancellation already recorded — skip');
      return;
    }
    _cancelRecorded = true;

    final ch = widget.challenge!;

    try {
      await PresenceChallengeService.instance.recordFailedAttempt(
        ch,
        faceScore: _matchPercent,
        reason: reason,
      );
      _secureLog('📢 [Challenge] Recorded failure: ${ch.id} (reason=$reason)');

      unawaited(_logSecurityEvent(
        type: 'presence_challenge_cancelled',
        severity: 'medium',
        details: 'User cancelled challenge ${ch.id} — reason=$reason',
      ));
    } catch (e) {
      _secureLog('⚠️ [Challenge] Failed to record cancellation: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // CAMERA
  // ══════════════════════════════════════════════════════════
  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await Permission.camera.status;
      if (status.isGranted) return true;
      final result = await Permission.camera.request();
      if (result.isGranted) return true;
      _onFailure(result.isPermanentlyDenied
          ? 'Camera access denied.\nEnable in Settings.'
          : 'Camera permission required.');
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _initCamera() async {
    if (_camTried && _camReady) return;
    _camTried = true;
    _camError = null;
    try {
      final granted = await _ensureCameraPermission();
      if (!granted) {
        _camError = 'Camera permission not granted.';
        return;
      }
      List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty && kIsWeb) {
        await Future.delayed(const Duration(seconds: 1));
        cameras = await availableCameras();
      }
      if (cameras.isEmpty) {
        _camError = 'No camera detected.';
        if (mounted) setState(() {});
        return;
      }
      final front = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup:
        kIsWeb ? ImageFormatGroup.jpeg : ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _camCtrl = ctrl;
        _camReady = true;
      });
      _secureLog('✅ Camera ready');
    } catch (e) {
      _secureLog('⚠️ Camera init failed: $e');
      _camError = 'Camera error';
      if (mounted) setState(() {});
    }
  }

  // ══════════════════════════════════════════════════════════
  // START SCAN
  // ══════════════════════════════════════════════════════════
  Future<void> _startScan() async {
    if (!mounted || _isScanning || _isCheckingTemplate) return;
    if (_authMode == _AuthMode.unknown) return;

    if (_networkState == _NetState.offline) {
      await _retryNetworkCheck();
      if (_networkState != _NetState.online) return;
    }

    if (!_preAuthValid) {
      _onFailure('Security check failed. Please log in again.');
      return;
    }

    if (!kIsWeb && _deviceCompromised) {
      _onFailure('This device is flagged as compromised. Access blocked.');
      return;
    }

    if (_authMode == _AuthMode.verify) {
      await _checkTemplateAvailability();
    }

    _isScanning = true;
    _blinkDone = false;
    _smileDone = false;
    _eyesWereClosed = false;
    _closedFrames = 0;
    _facePresent = false;
    _faceMatched = false;
    _matchScore = 0.0;
    _matchPercent = 0.0;
    _selfHealTriggered = false;
    _livenessStep = _LivenessStep.waitingForFace;
    _livenessStartTime = DateTime.now();
    _enrollCaptureCount = 0;

    setState(() {
      _faceState = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!mounted) return;

    if (!_camReady || kIsWeb) {
      _scanLineCtrl.repeat(reverse: true);
      await _runMockScan();
      return;
    }

    _scanLineCtrl.repeat(reverse: true);
    await _camCtrl!.startImageStream(_onCameraImage);
  }

  Future<void> _checkTemplateAvailability() async {
    if (kIsWeb) return;
    try {
      _isCheckingTemplate = true;
      final status = await FaceMatcher.debugTemplateStatus(widget.employee.id);
      _secureLog('📋 Template status: $status');

      final hasTemplate = status['hasJson'] == true &&
          (status['count'] as int? ?? 0) > 0 &&
          status['version'] == 4;

      if (!hasTemplate) {
        final hasPhoto = status['hasPhotoUrl'] == true;
        if (hasPhoto) {
          _secureLog('🔧 Attempting self-heal from photoUrl...');
          final healed =
          await FaceMatcher.autoUpgradeFromExistingPhoto(widget.employee.id);
          if (healed) _selfHealTriggered = true;
        }
      }
    } catch (e) {
      _secureLog('⚠️ _checkTemplateAvailability error: $e');
    } finally {
      _isCheckingTemplate = false;
    }
  }

  Future<void> _runMockScan() async {
    _secureLog('🌐 [Web] Starting mock scan');
    while (mounted && _isScanning) {
      await Future.delayed(const Duration(milliseconds: _webDetectIntervalMs));
      if (!mounted || !_isScanning) return;

      final videoEl = _webLiveness.getVideoElement();
      if (videoEl == null) continue;

      final result = await _webLiveness.detect(videoEl);
      if (result == null) continue;

      if (!result.facePresent) {
        if (mounted && _facePresent) setState(() => _facePresent = false);
        continue;
      }

      if (mounted && !_facePresent) {
        setState(() => _facePresent = true);
      }

      if (_authMode == _AuthMode.enroll) {
        _isScanning = false;
        _scanLineCtrl.stop();
        if (mounted) {
          _onFailure('Enrollment sa web ay hindi supported. '
              'Gamitin ang mobile app.');
        }
        return;
      }

      if (!_blinkDone) {
        final ear = result.eyeOpenScore;
        if (ear < _webEyeClosedThreshold) {
          _eyesWereClosed = true;
        } else if (ear > _webEyeOpenThreshold && _eyesWereClosed) {
          if (mounted) setState(() => _blinkDone = true);
          _eyesWereClosed = false;
          _livenessStep = _LivenessStep.smile;
        }
        continue;
      }

      if (!_smileDone) {
        if (result.smileScore > _webSmileThreshold) {
          if (mounted) setState(() => _smileDone = true);
        }
        continue;
      }

      _isScanning = false;
      _scanLineCtrl.stop();
      _onFaceMismatch();
      return;
    }
  }

  // ══════════════════════════════════════════════════════════
  // IMAGE CONVERSION
  // ══════════════════════════════════════════════════════════
  InputImage? _buildInputImage(CameraImage image) {
    if (_camCtrl == null) return null;

    final camera = _camCtrl!.description;
    final sensorOrientation = camera.sensorOrientation;
    final isFrontCamera = camera.lensDirection == CameraLensDirection.front;

    InputImageRotation rotation;
    if (kIsWeb) {
      rotation = InputImageRotation.rotation0deg;
    } else if (Platform.isIOS) {
      rotation = InputImageRotation.rotation90deg;
    } else {
      if (isFrontCamera) {
        rotation = InputImageRotation.rotation270deg;
      } else {
        final comp = (sensorOrientation + _rotationCompensation) % 360;
        switch (comp) {
          case 90:
            rotation = InputImageRotation.rotation90deg;
            break;
          case 180:
            rotation = InputImageRotation.rotation180deg;
            break;
          case 270:
            rotation = InputImageRotation.rotation270deg;
            break;
          case 0:
          default:
            rotation = InputImageRotation.rotation0deg;
        }
      }
    }

    try {
      final width = image.width;
      final height = image.height;

      if (image.planes.length == 1) {
        final plane = image.planes[0];
        final fmt = (kIsWeb || Platform.isIOS)
            ? InputImageFormat.bgra8888
            : InputImageFormat.nv21;

        return InputImage.fromBytes(
          bytes: plane.bytes,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: rotation,
            format: fmt,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      }

      if (image.planes.length >= 3) {
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];

        final int yRowStride = yPlane.bytesPerRow;
        final int uvRowStride = uPlane.bytesPerRow;
        final int uvPixelStride = uPlane.bytesPerPixel ?? 1;

        final nv21 = Uint8List(width * height * 3 ~/ 2);
        int pos = 0;

        if (yRowStride == width) {
          nv21.setRange(0, width * height, yPlane.bytes);
          pos = width * height;
        } else {
          for (int r = 0; r < height; r++) {
            final int start = r * yRowStride;
            nv21.setRange(pos, pos + width, yPlane.bytes, start);
            pos += width;
          }
        }

        final int uvHeight = height ~/ 2;
        final int uvWidth = width ~/ 2;
        for (int r = 0; r < uvHeight; r++) {
          for (int c = 0; c < uvWidth; c++) {
            final int uvIdx = r * uvRowStride + c * uvPixelStride;
            nv21[pos++] = vPlane.bytes[uvIdx];
            nv21[pos++] = uPlane.bytes[uvIdx];
          }
        }

        return InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: width,
          ),
        );
      }

      return null;
    } catch (e, st) {
      _secureLog('⚠️ _buildInputImage error: $e\n$st');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════
  // CAMERA FRAME HANDLER
  // ══════════════════════════════════════════════════════════
  Future<void> _onCameraImage(CameraImage image) async {
    if (!_isScanning || _isProcessing || !mounted) return;
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted || !_isScanning) {
        _isProcessing = false;
        return;
      }

      _facePresent = faces.isNotEmpty;
      if (mounted) setState(() {});

      if (faces.isEmpty) {
        _resetWarning();
        _isProcessing = false;
        return;
      }

      final face = faces.first;

      if (_authMode == _AuthMode.enroll) {
        await _handleEnrollFrame(image, face);
      } else {
        await _handleVerifyFrame(image, face);
      }
    } catch (e) {
      _secureLog('⚠️ _onCameraImage error: $e');
    }
    _isProcessing = false;
  }

  // ══════════════════════════════════════════════════════════
  // ENROLL MODE
  // ══════════════════════════════════════════════════════════
  Future<void> _handleEnrollFrame(CameraImage image, Face face) async {
    if (_lastEnrollCaptureAt != null) {
      final elapsed = DateTime.now().difference(_lastEnrollCaptureAt!);
      if (elapsed < _enrollCaptureCooldown) {
        _isProcessing = false;
        return;
      }
    }

    if (_isSavingEnroll) return;

    final warning = _assessEnrollQuality(face, image);
    if (warning != _FaceWarning.none) {
      _eyesWereClosed = false;
      _closedFrames = 0;
      if (mounted) setState(() => _faceWarning = warning);
      _warningCtrl.repeat(reverse: true);
      _isProcessing = false;
      return;
    }

    final leftOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;
    final avgOpen = (leftOpen + rightOpen) / 2;

    if (!_blinkDone) {
      if (avgOpen < _blinkClosedThreshold) {
        _closedFrames++;
        _eyesWereClosed = true;
        if (_closedFrames > _maxClosedFramesBeforeStuck) {
          _eyesWereClosed = false;
          _closedFrames = 0;
          if (mounted) {
            setState(() => _faceWarning = _FaceWarning.eyesClosed);
          }
          _warningCtrl.repeat(reverse: true);
          _isProcessing = false;
          return;
        }
      } else if (avgOpen > _blinkOpenThreshold &&
          _eyesWereClosed &&
          _closedFrames >= _minClosedFrames) {
        _blinkDone = true;
        _eyesWereClosed = false;
        _closedFrames = 0;
        if (mounted) {
          setState(() {
            _faceWarning = _FaceWarning.none;
            _enrollHint = 'Mabuti! Ngayon naman, tingnan ang camera.';
          });
        }
        _secureLog('✅ [Enroll] Blink detected — ready to capture');
      } else {
        if (_eyesWereClosed && _closedFrames < _minClosedFrames) {
          _eyesWereClosed = false;
          _closedFrames = 0;
        }
      }
      _isProcessing = false;
      return;
    }

    _lastEnrollCaptureAt = DateTime.now();
    _warningCtrl.stop();
    _warningCtrl.reset();

    if (mounted) setState(() => _faceWarning = _FaceWarning.none);

    try {
      _isSavingEnroll = true;
      if (mounted) setState(() {});

      final picture = await _camCtrl!.takePicture();
      final bytes = await picture.readAsBytes();

      try {
        final f = File(picture.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      _flashCtrl.forward(from: 0);

      final result = await FaceMatcher.enrollFace(
        widget.employee.id,
        bytes,
        source: 'mobile_enrollment',
      );

      _isSavingEnroll = false;

      if (!result.success) {
        _secureLog('❌ [Enroll] Save failed: ${result.error}');
        if (mounted) {
          setState(() {
            _enrollHint = 'Hindi nakuha. Subukan muli — tingnan ang camera.';
          });
        }
        _isProcessing = false;
        return;
      }

      _enrollCaptureCount = result.samplesSoFar;

      if (!mounted) return;

      if (_enrollCaptureCount >= _requiredEnrollCaptures) {
        _secureLog('🎉 [Enroll] Complete — $_enrollCaptureCount samples');

        await _camCtrl!.stopImageStream();
        _isScanning = false;
        _scanLineCtrl.stop();

        await _logSecurityEvent(
          type: 'face_enrolled',
          severity: 'info',
          details:
          'Face enrolled with $_enrollCaptureCount samples on first use',
        );

        if (mounted) {
          setState(() {
            _faceState = _FaceState.success;
            _enrollHint = 'Matagumpay na naka-register ang mukha mo!';
          });
          _successCtrl.forward();
        }

        await Future.delayed(const Duration(milliseconds: 1800));
        if (!mounted) return;
        _proceedToNext();
        return;
      }

      if (mounted) {
        setState(() {
          _enrollHint =
          'Sample ${_enrollCaptureCount + 1} ng $_requiredEnrollCaptures — '
              'tingnan ulit sa camera.';
          _blinkDone = false;
          _closedFrames = 0;
        });
      }
    } catch (e) {
      _isSavingEnroll = false;
      _secureLog('❌ [Enroll] capture error: $e');
    }

    _isProcessing = false;
  }

  // ══════════════════════════════════════════════════════════
  // VERIFY MODE
  // ══════════════════════════════════════════════════════════
  Future<void> _handleVerifyFrame(CameraImage image, Face face) async {
    final quality = _assessVerifyQuality(face, image);

    if (quality != _FaceWarning.none) {
      _eyesWereClosed = false;
      _closedFrames = 0;
      if (mounted) setState(() => _faceWarning = quality);
      _warningCtrl.repeat(reverse: true);
      _isProcessing = false;
      return;
    }

    _warningCtrl.stop();
    _warningCtrl.reset();

    final leftOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightOpen = face.rightEyeOpenProbability ?? 1.0;
    final avgOpen = (leftOpen + rightOpen) / 2;
    final smile = face.smilingProbability ?? 0.0;

    if (_livenessStep == _LivenessStep.waitingForFace) {
      _livenessStep = _LivenessStep.blink;
      if (mounted) setState(() => _faceWarning = _FaceWarning.none);
    }

    if (_livenessStep == _LivenessStep.blink && !_blinkDone) {
      if (avgOpen < _blinkClosedThreshold) {
        _closedFrames++;
        _eyesWereClosed = true;
        if (_closedFrames > _maxClosedFramesBeforeStuck) {
          _eyesWereClosed = false;
          _closedFrames = 0;
          if (mounted) {
            setState(() => _faceWarning = _FaceWarning.eyesClosed);
          }
          _warningCtrl.repeat(reverse: true);
          _isProcessing = false;
          return;
        }
      } else if (avgOpen > _blinkOpenThreshold &&
          _eyesWereClosed &&
          _closedFrames >= _minClosedFrames) {
        _blinkDone = true;
        _eyesWereClosed = false;
        _closedFrames = 0;
        _livenessStep = _LivenessStep.smile;
        _secureLog('✅ [Verify] Blink detected — now smile');
      } else {
        if (_eyesWereClosed && _closedFrames < _minClosedFrames) {
          _eyesWereClosed = false;
          _closedFrames = 0;
        }
      }
    } else if (_livenessStep == _LivenessStep.smile && !_smileDone) {
      if (smile > _smileThreshold) {
        _smileDone = true;
        _secureLog('✅ [Verify] Smile detected — verifying...');
        await _camCtrl!.stopImageStream();
        _isScanning = false;
        _scanLineCtrl.stop();
        final matched = await _verifyFaceMatch();
        if (matched) {
          await _onSuccess();
        } else {
          _onFaceMismatch();
        }
        _isProcessing = false;
        return;
      }
    }

    if (_livenessStartTime != null && !_smileDone) {
      final elapsed =
          DateTime.now().difference(_livenessStartTime!).inMilliseconds;
      if (elapsed > _livenessTimeoutMs) {
        await _camCtrl!.stopImageStream();
        _isScanning = false;
        _scanLineCtrl.stop();
        if (mounted) _onFailure('Liveness check timed out. Try again.');
        _isProcessing = false;
        return;
      }
    }

    if (mounted) setState(() => _faceWarning = _FaceWarning.none);
  }

  // ══════════════════════════════════════════════════════════
  // QUALITY CHECKS
  // ══════════════════════════════════════════════════════════
  _FaceWarning _assessEnrollQuality(Face face, CameraImage image) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    if (yaw.abs() > _maxHeadYawDeg ||
        roll.abs() > _maxHeadRollDeg ||
        pitch.abs() > _maxHeadPitchDeg) {
      return _FaceWarning.headAngle;
    }

    final faceArea =
    (face.boundingBox.width * face.boundingBox.height).toDouble();
    final imageArea = (image.width * image.height).toDouble();
    final areaRatio = faceArea / imageArea;

    if (areaRatio < _minFaceAreaRatio) return _FaceWarning.tooFar;
    if (areaRatio > _maxFaceAreaRatio) return _FaceWarning.tooClose;

    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    final nose = face.landmarks[FaceLandmarkType.noseBase];

    if (leftEye == null || rightEye == null) {
      return _FaceWarning.occluded;
    }
    if (nose == null) {
      return _FaceWarning.occluded;
    }

    if (!kIsWeb && image.planes.isNotEmpty) {
      final brightness = _estimateBrightness(image);
      if (brightness < 35) return _FaceWarning.tooDark;
      if (brightness > 225) return _FaceWarning.tooBright;
    }

    return _FaceWarning.none;
  }

  _FaceWarning _assessVerifyQuality(Face face, CameraImage image) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final roll = face.headEulerAngleZ ?? 0.0;
    if (yaw.abs() > 25.0 || roll.abs() > 25.0) {
      return _FaceWarning.headAngle;
    }

    final faceArea =
    (face.boundingBox.width * face.boundingBox.height).toDouble();
    final imageArea = (image.width * image.height).toDouble();
    final areaRatio = faceArea / imageArea;
    if (areaRatio < 0.03) return _FaceWarning.tooFar;

    final hasNose = face.landmarks[FaceLandmarkType.noseBase] != null;
    final hasBothEyes = face.landmarks[FaceLandmarkType.leftEye] != null &&
        face.landmarks[FaceLandmarkType.rightEye] != null;
    if (!hasBothEyes && !hasNose) return _FaceWarning.occluded;

    return _FaceWarning.none;
  }

  double _estimateBrightness(CameraImage image) {
    try {
      final yPlane = image.planes.first;
      final bytes = yPlane.bytes;
      if (bytes.isEmpty) return 128;

      final step = (bytes.length / 500).ceil().clamp(1, 100);
      int sum = 0;
      int count = 0;
      for (int i = 0; i < bytes.length; i += step) {
        sum += bytes[i];
        count++;
      }
      if (count == 0) return 128;
      return sum / count;
    } catch (_) {
      return 128;
    }
  }

  void _resetWarning() {
    _eyesWereClosed = false;
    _closedFrames = 0;
    _warningCtrl.stop();
    _warningCtrl.reset();
    if (mounted) setState(() => _faceWarning = _FaceWarning.none);
  }

  // ══════════════════════════════════════════════════════════
  // VERIFY FACE MATCH
  // ══════════════════════════════════════════════════════════
  Future<bool> _verifyFaceMatch() async {
    try {
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return false;
      if (!_preAuthValid) return false;
      if (_deviceCompromised) return false;

      final picture = await _camCtrl!.takePicture();
      final bytes = await picture.readAsBytes();

      try {
        final f = File(picture.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      final result = await FaceMatcher.verify(
        widget.employee.id,
        bytes,
        threshold: _matchThreshold,
      );

      _secureLog('🔍 score=${result.score.toStringAsFixed(4)}, '
          'matched=${result.matched}, hasEmbedding=${result.hasEmbedding}');

      if (!result.hasEmbedding) {
        _matchScore = 0.0;
        _matchPercent = 0.0;
        _faceMatched = false;
        return false;
      }

      _matchScore = result.score;
      _matchPercent = result.score * 100.0;
      _faceMatched = result.matched;
      return result.matched;
    } catch (e, st) {
      _secureLog('⚠️ verify error: $e\n$st');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════
  // FACE MISMATCH
  // ══════════════════════════════════════════════════════════
  void _onFaceMismatch() {
    if (!mounted) return;
    _isScanning = false;
    _scanLineCtrl.stop();

    if (_isChallenge) {
      unawaited(PresenceChallengeService.instance.recordFailedAttempt(
        widget.challenge!,
        faceScore: _matchPercent,
        reason: 'face_mismatch_${_matchPercent.toStringAsFixed(1)}',
      ));
      unawaited(_logSecurityEvent(
        type: 'presence_challenge_failed',
        severity: 'high',
        details: 'Challenge ${widget.challenge!.id} FAILED — '
            'face mismatch (${_matchPercent.toStringAsFixed(1)}%)',
      ));

      _cancelRecorded = true;
    }

    final String reason;
    if (_matchPercent < 40) {
      reason = 'Hindi ma-detect ng maayos ang mukha.\n'
          'Subukan sa mas maliwanag na lugar.';
    } else if (_matchPercent < 55) {
      reason = 'Malabo ang pagkakatugma ng mukha.\n'
          'Alisin ang salamin/mask at tingnan direkta ang camera.';
    } else {
      reason = 'Hindi tugma ang mukha sa naka-register.\n'
          'Kung bago ka, ipa-enroll sa Admin.';
    }

    setState(() {
      _faceState = _FaceState.error;
      _errorMessage =
      '$reason\n\nSimilarity: ${_matchPercent.toStringAsFixed(1)}%';
    });
    _shakeCtrl.forward(from: 0);

    if (_isChallenge) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop(false);
      });
      return;
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _faceState == _FaceState.error) {
        setState(() {
          _faceState = _FaceState.idle;
          _errorMessage = null;
          _faceWarning = _FaceWarning.none;
        });
      }
    });
  }

  // ══════════════════════════════════════════════════════════
  // GEOFENCE + ATTENDANCE
  // ══════════════════════════════════════════════════════════
  Future<bool> _checkRoleAndGeofence() async {
    if (mounted) setState(() => _isCheckingGeofence = true);
    GeofenceService.instance.invalidateCache();

    try {
      GeofenceResult? geoResult;
      try {
        geoResult = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: widget.employee.id)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        _secureLog('❌ Geofence error: $e');
      }

      final isAllowed = geoResult?.isAllowed ?? false;
      final isExempted = geoResult?.isExempted ?? false;

      if (isAllowed || isExempted) {
        if (mounted) setState(() => _isCheckingGeofence = false);
        return true;
      }

      if (geoResult == null) {
        if (mounted) {
          setState(() {
            _faceState = _FaceState.error;
            _errorMessage = 'Unable to verify location.\nPlease try again.';
            _isCheckingGeofence = false;
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
          _faceState = _FaceState.error;
          _errorMessage = '📍 Outside work zone\n'
              'Nearest: $nearest\n'
              'Distance: ${dist?.toStringAsFixed(0) ?? "?"}m '
              '(allowed: ${radius?.toStringAsFixed(0) ?? "?"}m)';
          _isCheckingGeofence = false;
        });
        _shakeCtrl.forward(from: 0);
      }
      return false;
    } catch (e) {
      if (mounted) setState(() => _isCheckingGeofence = false);
      _secureLog('🚨 Geofence exception: $e');
      return false;
    }
  }

  Color _matchColor(double percent) {
    if (percent >= 95) return const Color(0xFF16A34A);
    if (percent >= 80) return const Color(0xFF3B82F6);
    if (percent >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _matchLabel(double percent) {
    if (percent >= 95) return 'EXCELLENT MATCH';
    if (percent >= 80) return 'STRONG MATCH';
    if (percent >= 65) return 'ACCEPTABLE MATCH';
    return 'WEAK MATCH';
  }

  String get _employeeIdForAttendance {
    final empId = widget.employee.employeeId;
    if (empId.isNotEmpty) return empId;
    return widget.employee.id;
  }

  String _computeZoneType() {
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
      final deviceName = _deviceModel;
      final zoneType = _computeZoneType();

      try {
        await OfflineAttendanceService.instance.logAttendance(
          employeeId: employeeId,
          employeeName: employeeName,
          employeeEmail: employeeEmail,
          type: attendanceType,
          timestamp: now,
          device: deviceName,
          remarks: 'face_match:${_matchPercent.toStringAsFixed(0)}',
          zoneType: zoneType,
        );
      } catch (e) {
        _secureLog('⚠️ Local save failed: $e');
      }

      if (!NetworkGuard.instance.isOnline) return;

      try {
        await FirebaseFirestore.instance.collection('attendance_logs').add({
          'employee_id': employeeId,
          'employee_name': employeeName,
          'employee_email': employeeEmail,
          'type': attendanceType,
          'date': todayStr,
          'time': timeStr,
          'timestamp': FieldValue.serverTimestamp(),
          'device': deviceName,
          'device_binding': _deviceBinding,
          'zone_type': zoneType,
          'face_match_percent': _matchPercent,
          'match_score': _matchScore,
          'session_nonce': _sessionNonce,
          'device_compromised': _deviceCompromised,
          'self_heal_used': _selfHealTriggered,
          'remarks': 'face_match:${_matchPercent.toStringAsFixed(0)}',
        });
      } catch (e) {
        _secureLog('❌ attendance_logs write FAILED: $e');
      }

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': isClockIn ? 'clock_in' : 'clock_out',
          'action': isClockIn ? 'Clocked In (Face)' : 'Clocked Out (Face)',
          'employeeId': widget.employee.id,
          'employee_id': employeeId,
          'employee_name': employeeName,
          'email': employeeEmail,
          'face_match_percent': _matchPercent,
          'match_score': _matchScore,
          'zone_type': zoneType,
          'time': timeStr,
          'date': todayStr,
          'device': deviceName,
          'device_binding': _deviceBinding,
          'device_compromised': _deviceCompromised,
          'platform': kIsWeb ? 'web' : 'mobile',
          'session_nonce': _sessionNonce,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _secureLog('⚠️ activity_logs FAILED: $e');
      }

      if (isClockIn) {
        try {
          unawaited(PresenceChallengeService.instance.scheduleForToday(
            employeeId: employeeId,
            clockInAt: now,
            employeeName: employeeName,
          ));
          _secureLog('🎯 [Challenge] Scheduled for $employeeId');
        } catch (e) {
          _secureLog('⚠️ [Challenge] scheduleForToday failed: $e');
        }
      }

      try {
        if (isClockIn) {
          AdminNotificationService.instance.notifyClockIn(
            employeeId: employeeId,
            employeeName: employeeName,
            timeStr: timeStr,
            faceMatchPercent: _matchPercent,
            wfh: widget.employee.wfhAccess,
            inRange: true,
            zoneType: zoneType,
          );
        } else {
          AdminNotificationService.instance.notifyClockOut(
            employeeId: employeeId,
            employeeName: employeeName,
            timeStr: timeStr,
            faceMatchPercent: _matchPercent,
            wfh: widget.employee.wfhAccess,
            inRange: true,
            zoneType: zoneType,
          );
        }
      } catch (e) {
        _secureLog('⚠️ Admin notification failed: $e');
      }
    } catch (e) {
      _secureLog('❌ _writeAttendanceLog: $e');
    }
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;

    setState(() {
      _faceState = _FaceState.success;
      _errorMessage = null;
    });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();
    _matchCountCtrl.forward(from: 0);

    if (_isChallenge) {
      await _finishChallenge();
      return;
    }

    final canProceed = await _checkRoleAndGeofence();
    if (!canProceed) return;

    await _writeAttendanceLog();

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    _proceedToNext();
  }

  // ══════════════════════════════════════════════════════════
  // 🆕 CHALLENGE COMPLETION — geofence-aware
  // ══════════════════════════════════════════════════════════
  Future<void> _finishChallenge() async {
    if (!mounted) return;
    final ch = widget.challenge!;

    // Mark as recorded so we don't double-send on pop
    _cancelRecorded = true;

    _secureLog('🎯 [Challenge] Verifying geofence...');

    final canProceed = await _checkRoleAndGeofence();
    if (!canProceed) {
      _secureLog('⚠️ [Challenge] Geofence failed — recording FAILED');

      // 🆕 Record as FAILED (not PASSED)
      unawaited(PresenceChallengeService.instance.recordFailedAttempt(
        ch,
        faceScore: _matchPercent,
        reason: 'geofence_failed_at_verify',
      ));

      await _logSecurityEvent(
        type: 'challenge_failed_geofence',
        severity: 'high',
        details:
        'Challenge ${ch.id} FAILED — outside work zone at verification',
      );

      // 🆕 pop(false) para tama ang snackbar sa MainScreen
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop(false);
      return;
    }

    final zone = _computeZoneType();
    await PresenceChallengeService.instance.submitPassed(
      ch,
      faceScore: _matchPercent,
      zone: zone,
      deviceBinding: _deviceBinding,
    );

    _secureLog('✅ [Challenge] PASSED for ${widget.employee.id} '
        '(score=${_matchPercent.toStringAsFixed(1)}%, zone=$zone)');

    await _logSecurityEvent(
      type: 'challenge_passed',
      severity: 'info',
      details: 'Random face check passed '
          '(score=${_matchPercent.toStringAsFixed(1)}%, zone=$zone)',
    );

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

     void _proceedToNext() {
    if (!mounted) return;
    final navigator = Navigator.of(context);

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ClockInSuccessScreen(
          employee: widget.employee,
          arrivalTime: widget.arrivalTime,
          faceMatchPercent: _matchPercent,
          verificationMethod:
          _authMode == _AuthMode.enroll ? 'face_enrolled' : 'face_match',
          onContinue: () {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => MainScreen(employee: widget.employee)),
                  (route) => false,
            );
          },
        ),
      ),
    );
  }

  void _onFailure(String msg) {
    if (!mounted) return;
    _isScanning = false;
    _scanLineCtrl.stop();
    setState(() {
      _faceState = _FaceState.error;
      _errorMessage = msg;
    });
    _shakeCtrl.forward(from: 0);

    unawaited(_logSecurityEvent(
      type: 'face_auth_failed',
      severity: 'medium',
      details: msg,
    ));

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _faceState == _FaceState.error) {
        setState(() {
          _faceState = _FaceState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _stopAllCameraOperations() async {
    _isScanning = false;
    _isProcessing = false;
    try {
      if (_camCtrl?.value.isStreamingImages == true) {
        await _camCtrl!.stopImageStream();
      }
    } catch (e) {
      _secureLog('⚠️ stop stream: $e');
    }
    _scanLineCtrl.stop();
    _warningCtrl.stop();
    _pulseCtrl.stop();
    _ringCtrl.stop();
  }

  // ══════════════════════════════════════════════════════════
  // BACK BUTTON
  // ══════════════════════════════════════════════════════════
  Future<void> _goBack() async {
    await _stopAllCameraOperations();

    if (_isChallenge && !_cancelRecorded) {
      _secureLog('🚪 [Challenge] User tapped Back — recording cancellation');
      await _recordChallengeFailure('user_tapped_back');
    }

    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(employee: widget.employee),
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // CANCEL BUTTON
  // ══════════════════════════════════════════════════════════
  Future<void> _onCancelTapped() async {
    await _stopAllCameraOperations();

    if (_isChallenge && !_cancelRecorded) {
      _secureLog('🚪 [Challenge] User tapped Cancel — recording cancellation');
      await _recordChallengeFailure('user_tapped_cancel');
    }

    if (!mounted) return;
    setState(() => _cancelPressed = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _cancelPressed = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(employee: widget.employee),
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final isOffline = _networkState == _NetState.offline;
    final isChecking = _networkState == _NetState.checking;

    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: tc.bgTop,
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
              if (_obscureContent) _buildPrivacyShield(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor:
      isDark ? const Color(0xFF0A0A0A) : const Color(0xFF121212),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final contentWidth = screenWidth < 420 ? screenWidth : 375.0;
            return Center(
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: ClipRRect(
                  borderRadius:
                  BorderRadius.circular(screenWidth <= 420 ? 0 : 40),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Stack(
                      children: [
                        Positioned.fill(child: Container(color: tc.bg)),
                        _buildHeader(),
                        Positioned(
                          top: 205,
                          left: 16,
                          right: 16,
                          child: _buildOuterCard(tc),
                        ),
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
                        if (_obscureContent) _buildPrivacyShield(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
                  Color(0xFFF54900)
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _white, width: 1.15),
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
                  child: const Icon(Icons.wifi_off_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('No Connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(_networkErrorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        height: 1.5)),
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
                    label: const Text('Try Again',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 287.13,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF8A00), Color(0xFFFF6B00), Color(0xFFF54900)],
          stops: [0.0001, 0.3318, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 24,
            top: 48,
            child: GestureDetector(
              onTap: _goBack,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 19.99,
                      height: 19.99,
                      child: CustomPaint(painter: _BackArrowPainter())),
                  const SizedBox(width: 2),
                  const Text('Back',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          height: 0.9)),
                ],
              ),
            ),
          ),
          Positioned(
              left: 24,
              top: 95.99,
              child: Text(
                  _isChallenge
                      ? 'Random Check'
                      : (_authMode == _AuthMode.enroll
                      ? 'Face Registration'
                      : 'Auth & Clock In'),
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 0.9))),
          Positioned(
              left: 24,
              top: 136.99,
              child: Text(
                  _isChallenge
                      ? 'Presence verification required'
                      : (_authMode == _AuthMode.enroll
                      ? 'First-time face enrollment'
                      : 'Face + Liveness verification'),
                  style: const TextStyle(
                      fontSize: 14, color: Colors.white, height: 0.9))),
        ],
      ),
    );
  }

  Widget _buildOuterCard(_ThemeColors tc) {
    return Container(
      decoration: BoxDecoration(
        color: tc.outerCardBg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              _isChallenge
                  ? 'Presence Check'
                  : (_authMode == _AuthMode.enroll
                  ? 'Step 3: Face Registration'
                  : 'Step 3: Facial Recognition'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: tc.stepLabelColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          _buildModalCard(tc),
        ],
      ),
    );
  }

  Widget _buildModalCard(_ThemeColors tc) {
    final isScanning = _faceState == _FaceState.scanning;
    final isSuccess = _faceState == _FaceState.success;
    final isBusy = isScanning;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF8C2B), Color(0xFFF05000)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFF05000).withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _cameraBoxSize,
            height: _cameraBoxSize,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: (!isBusy && !isSuccess && !_isCheckingGeofence)
                    ? _startScan
                    : null,
                child: isSuccess
                    ? _buildVerifiedBadgeWithScore()
                    : isScanning
                    ? _buildCameraPreview()
                    : _buildFaceIconBox(),
              ),
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 16),
            if (_authMode == _AuthMode.enroll)
              _buildEnrollProgressBar()
            else
              _buildScanProgressBar(),
          ],
          const SizedBox(height: 20),

          if (isSuccess && _authMode == _AuthMode.verify) ...[
            _buildMatchPercentBadge(),
            const SizedBox(height: 14),
          ],

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _stateTitle.replaceAll('\n', ' '),
              key: ValueKey('title_${_faceState}_$_authMode'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _errorMessage ?? _stateSubtitle.replaceAll('\n', ' '),
              key: ValueKey('subtitle_${_errorMessage ?? _faceState}'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _white.withValues(alpha: 0.9),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          if (_isCheckingGeofence) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Verifying location...',
                  style: TextStyle(
                      color: _white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          if (_camError != null && _faceState == _FaceState.idle) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('⚠️ $_camError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _warning, fontSize: 10)),
            ),
          ],
          if (_isSavingEnroll) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Saving sample...',
                  style: TextStyle(
                      color: _white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          const SizedBox(height: 20),
          _buildCancelButton(tc),
        ],
      ),
    );
  }

  Widget _buildMatchPercentBadge() {
    final percent = _matchPercent;
    final color = _matchColor(percent);
    final label = _matchLabel(percent);

    return AnimatedBuilder(
      animation: _matchCountAnim,
      builder: (_, __) {
        final animatedPercent = (percent * _matchCountAnim.value);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    animatedPercent.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    '%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFaceIconBox() {
    return SizedBox(
      width: 75,
      height: 75,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _successAnim, _shakeAnim]),
        builder: (_, __) {
          final isError = _faceState == _FaceState.error;
          return Transform.scale(
            scale: _pulseAnim.value,
            child: Container(
              width: 75,
              height: 75,
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(36, 36),
                  painter: _FaceScanIconPainter(
                      color: isError ? _error : _orange),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerifiedBadgeWithScore() {
    return AnimatedBuilder(
      animation: _successAnim,
      builder: (_, __) => Transform.scale(
        scale: _successAnim.value,
        child: SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _VerifiedBadgePainter(color: _verifiedGreen),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final faceDetected = _facePresent;
    final hasWarning = _faceWarning != _FaceWarning.none;
    final borderColor = hasWarning
        ? _warning
        : (faceDetected ? _faceGreen : _orange);
    final bool hasRealCamera = _camCtrl != null &&
        _camCtrl!.value.isInitialized &&
        _camCtrl!.value.previewSize != null;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [_ringAnim, _scanLineAnim, _warningAnim, _flashAnim]),
      builder: (_, __) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: _cameraBoxSize,
            height: _cameraBoxSize,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                if (hasRealCamera)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: Transform.scale(
                      scaleX: -1,
                      child: SizedBox(
                        width: _camCtrl!.value.previewSize!.height,
                        height: _camCtrl!.value.previewSize!.width,
                        child: CameraPreview(_camCtrl!),
                      ),
                    ),
                  )
                else if (kIsWeb)
                  Container(color: Colors.black)
                else
                  Container(
                      color: Colors.black,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: Colors.orange, strokeWidth: 2))),
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.transparent,
                          borderColor,
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                      painter: _FaceBracketPainter(color: borderColor)),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: borderColor, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(_statusBadgeText,
                          style: const TextStyle(
                              color: _white,
                              fontSize: 7.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6)),
                    ]),
                  ),
                ),
                if (hasWarning)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: _warning, size: 11),
                        const SizedBox(width: 4),
                        Text(_warningHintText,
                            style: const TextStyle(
                                color: _warning,
                                fontSize: 8,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  )
                else if (faceDetected)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          _authMode == _AuthMode.enroll
                              ? _enrollHintShort
                              : _livenessHint,
                          style: const TextStyle(
                              color: _faceGreen,
                              fontSize: 8,
                              fontWeight: FontWeight.w700)),
                    ),
                  )
                else
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Center your face',
                          style: TextStyle(
                              color: _white.withValues(alpha: 0.75),
                              fontSize: 8,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String get _enrollHintShort {
    if (!_blinkDone) return 'Blink to prove live';
    if (_enrollCaptureCount == 0) return 'Sample 1/3 — stay still';
    if (_enrollCaptureCount == 1) return 'Sample 2/3 — stay still';
    return 'Sample 3/3 — stay still';
  }

  Widget _buildCancelButton(_ThemeColors tc) {
    return GestureDetector(
      onTap: _onCancelTapped,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _cancelPressed ? tc.cancelPressed : tc.cancelBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
                color: tc.cancelText,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            child: Text(_isChallenge
                ? 'Cancel Verification'
                : (_authMode == _AuthMode.enroll
                ? 'Cancel Registration'
                : 'Cancel Authentication')),
          ),
        ),
      ),
    );
  }

  double get _scanProgress {
    if (_faceState == _FaceState.success) return 1.0;
    if (!_facePresent) return 0.1;
    if (_faceWarning != _FaceWarning.none) return 0.25;
    if (_blinkDone && _smileDone) return 0.95;
    if (_blinkDone) return 0.7;
    return 0.5;
  }

  Color get _scanProgressColor {
    if (_smileDone && _blinkDone) return _success;
    if (_faceWarning != _FaceWarning.none) return _warning;
    if (_facePresent) return _faceGreen;
    return _white.withValues(alpha: 0.5);
  }

  String get _scanProgressLabel {
    if (_smileDone && _blinkDone) return 'Verifying...';
    if (_faceWarning != _FaceWarning.none) return 'Fix issue';
    if (_blinkDone && !_smileDone) return 'Step 2: Smile 😊';
    if (_facePresent) return 'Step 1: Blink your eyes 👁️';
    return 'Looking for face';
  }

  double get _enrollProgress {
    if (_faceState == _FaceState.success) return 1.0;
    if (!_facePresent) return 0.05;
    if (_faceWarning != _FaceWarning.none) return 0.15;
    if (!_blinkDone) return 0.25;
    return 0.3 + (_enrollCaptureCount / _requiredEnrollCaptures) * 0.65;
  }

  String get _enrollProgressLabel {
    if (_faceState == _FaceState.success) return 'Naka-register na!';
    if (_faceWarning != _FaceWarning.none) return _warningHintText;
    if (!_facePresent) return 'Hanapin ang mukha sa frame';
    if (!_blinkDone) return 'I-blink ang mata para patunay na live';
    return 'Sample $_enrollCaptureCount/$_requiredEnrollCaptures nakuha';
  }

  Widget _buildScanProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 8,
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.22),
            child: LayoutBuilder(builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: constraints.maxWidth * _scanProgress,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _scanProgressColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Text(_scanProgressLabel,
            style: TextStyle(
                color: _white.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildEnrollProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ENROLLMENT PROGRESS',
              style: TextStyle(
                  color: _white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0),
            ),
            Text(
              '$_enrollCaptureCount / $_requiredEnrollCaptures',
              style: const TextStyle(
                  color: _white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 10,
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.22),
            child: LayoutBuilder(builder: (context, constraints) {
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: constraints.maxWidth * _enrollProgress,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _faceWarning != _FaceWarning.none
                        ? _warning
                        : _faceGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        Text(_enrollProgressLabel,
            style: TextStyle(
                color: _white.withValues(alpha: 0.85),
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  String get _statusBadgeText {
    if (_faceState == _FaceState.success) {
      return _authMode == _AuthMode.enroll
          ? 'ENROLLED ✓'
          : '${_matchPercent.toStringAsFixed(0)}% ✓';
    }
    if (_authMode == _AuthMode.enroll) {
      if (_facePresent) return 'ENROLLING';
      return 'SCANNING';
    }
    if (_smileDone && _blinkDone) return 'VERIFYING';
    if (_facePresent) return 'FACE FOUND';
    return 'SCANNING';
  }

  String get _warningHintText {
    switch (_faceWarning) {
      case _FaceWarning.faceMask:
        return 'Alisin ang face mask';
      case _FaceWarning.occluded:
        return 'Alisin ang harang sa mukha';
      case _FaceWarning.headAngle:
        return 'Tumingin nang diretso sa camera';
      case _FaceWarning.eyesClosed:
        return 'Buksan ang mata';
      case _FaceWarning.blurry:
        return 'Malabo — huminto at hawakan steady';
      case _FaceWarning.tooDark:
        return 'Masyadong madilim — lumipat sa maliwanag';
      case _FaceWarning.tooBright:
        return 'Masyadong maliwanag — iwasan ang sikat';
      case _FaceWarning.tooFar:
        return 'Mas malapit sa camera';
      case _FaceWarning.tooClose:
        return 'Bahagyang lumayo sa camera';
      case _FaceWarning.none:
        return '';
    }
  }

  String get _livenessHint {
    if (_blinkDone && !_smileDone) return 'Now smile 😊';
    if (_blinkDone && _smileDone) return 'Verifying...';
    return 'Blink your eyes 👁️';
  }

  String get _stateTitle {
    if (_isCheckingGeofence) return 'Verifying\nLocation...';

    if (_authMode == _AuthMode.enroll) {
      switch (_faceState) {
        case _FaceState.idle:
          return 'Face\nRegistration';
        case _FaceState.scanning:
          if (!_facePresent) return 'Scanning\nFace...';
          if (_faceWarning != _FaceWarning.none) return 'Quality\nCheck Failed';
          if (!_blinkDone) return 'Liveness\nCheck';
          return 'Capturing...';
        case _FaceState.success:
          return 'Enrolled!';
        case _FaceState.error:
          return 'Try Again';
        case _FaceState.enrolling:
          return 'Face\nRegistration';
      }
    }

    switch (_faceState) {
      case _FaceState.idle:
        return _isChallenge ? 'Presence\nCheck' : 'Facial\nRecognition';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) return 'Verifying\nIdentity...';
        if (_facePresent) {
          return _faceWarning != _FaceWarning.none
              ? 'Quality\nCheck Failed'
              : 'Liveness\nCheck';
        }
        return 'Scanning\nFace...';
      case _FaceState.success:
        return _isChallenge
            ? 'Verified!\n${_matchPercent.toStringAsFixed(1)}%'
            : 'Matched!\n${_matchPercent.toStringAsFixed(1)}%';
      case _FaceState.error:
        return 'Try Again';
      case _FaceState.enrolling:
        return 'Facial\nRecognition';
    }
  }

  String get _stateSubtitle {
    if (_isCheckingGeofence) {
      return 'Checking your role and location...';
    }

    if (_authMode == _AuthMode.enroll) {
      switch (_faceState) {
        case _FaceState.idle:
          return 'Wala pang registered face.\nTap para magsimula ng 3-shot enrollment.';
        case _FaceState.scanning:
          if (_faceWarning != _FaceWarning.none) return _warningHintText;
          if (!_facePresent) return 'Center your face in the frame';
          if (!_blinkDone) return 'I-blink ang mata 👁️ para patunay na live';
          return _enrollHint;
        case _FaceState.success:
          return 'Matagumpay! Naka-save na sa admin database.';
        case _FaceState.error:
          return 'Hindi natapos. Tap para subukan muli.';
        case _FaceState.enrolling:
          return 'Tap para magsimula';
      }
    }

    switch (_faceState) {
      case _FaceState.idle:
        return _isChallenge
            ? 'Tap to start random verification'
            : 'Tap the camera icon to start\nfacial scan';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) {
          return 'Matching your face\nwith registered photo...';
        }
        if (_facePresent) {
          if (_faceWarning != _FaceWarning.none) return _warningHintText;
          if (!_blinkDone) return 'Step 1 of 2: Blink your eyes 👁️';
          if (!_smileDone) return 'Step 2 of 2: Smile for the camera 😊';
        }
        return 'Center your face in the frame';
      case _FaceState.success:
        return 'Similarity: ${_matchPercent.toStringAsFixed(1)}%\n'
            'Identity confirmed.${_isChallenge ? " Returning..." : " Proceeding..."}';
      case _FaceState.error:
        return 'Face not recognized.\nTap to try again.';
      case _FaceState.enrolling:
        return 'Tap the camera icon to start\nfacial scan';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════
enum _FaceState { idle, scanning, success, error, enrolling }
enum _FaceWarning {
  none,
  blurry,
  faceMask,
  occluded,
  headAngle,
  eyesClosed,
  tooFar,
  tooClose,
  tooDark,
  tooBright,
}
enum _LivenessStep { waitingForFace, blink, smile }

// ═══════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════
class _BackArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.66602
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.75, size.height * 0.75)
      ..lineTo(size.width * 0.25, size.height * 0.5)
      ..lineTo(size.width * 0.75, size.height * 0.25);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FaceScanIconPainter extends CustomPainter {
  final Color color;
  const _FaceScanIconPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(p(3, 7).dx, p(3, 7).dy)
          ..lineTo(p(3, 5).dx, p(3, 5).dy)
          ..arcToPoint(p(5, 3), radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(7, 3).dx, p(7, 3).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(17, 3).dx, p(17, 3).dy)
          ..lineTo(p(19, 3).dx, p(19, 3).dy)
          ..arcToPoint(p(21, 5), radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(21, 7).dx, p(21, 7).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(21, 17).dx, p(21, 17).dy)
          ..lineTo(p(21, 19).dx, p(21, 19).dy)
          ..arcToPoint(p(19, 21), radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(17, 21).dx, p(17, 21).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(7, 21).dx, p(7, 21).dy)
          ..lineTo(p(5, 21).dx, p(5, 21).dy)
          ..arcToPoint(p(3, 19), radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(3, 17).dx, p(3, 17).dy),
        strokePaint);
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p(9, 9), 1.1 * s, dotPaint);
    canvas.drawCircle(p(15, 9), 1.1 * s, dotPaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(9, 13).dx, p(9, 13).dy)
          ..cubicTo(p(9.5, 13.8).dx, p(9.5, 13.8).dy, p(10.5, 14.5).dx,
              p(10.5, 14.5).dy, p(12, 14.5).dx, p(12, 14.5).dy)
          ..cubicTo(p(13.5, 14.5).dx, p(13.5, 14.5).dy, p(14.5, 13.8).dx,
              p(14.5, 13.8).dy, p(15, 13).dx, p(15, 13).dy),
        strokePaint);
  }

  @override
  bool shouldRepaint(_FaceScanIconPainter old) => old.color != color;
}

class _FaceBracketPainter extends CustomPainter {
  final Color color;
  const _FaceBracketPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final margin = size.width * 0.06;
    final r = size.width * 0.08;
    final len = size.width * 0.15;
    canvas.drawLine(
        Offset(margin + r, margin), Offset(margin + r + len, margin), paint);
    canvas.drawArc(
        Rect.fromLTWH(margin, margin, r * 2, r * 2),
        math.pi, math.pi / 2, false, paint);
    canvas.drawLine(
        Offset(margin, margin + r), Offset(margin, margin + r + len), paint);
    final xr = size.width - margin;
    canvas.drawLine(
        Offset(xr - r, margin), Offset(xr - r - len, margin), paint);
    canvas.drawArc(
        Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2),
        -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(
        Offset(xr, margin + r), Offset(xr, margin + r + len), paint);
    final yb = size.height - margin;
    canvas.drawLine(
        Offset(margin + r, yb), Offset(margin + r + len, yb), paint);
    canvas.drawArc(
        Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2),
        math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(
        Offset(margin, yb - r), Offset(margin, yb - r - len), paint);
    canvas.drawLine(Offset(xr - r, yb), Offset(xr - r - len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, yb - r * 2, r * 2, r * 2), 0,
        math.pi / 2, false, paint);
    canvas.drawLine(Offset(xr, yb - r), Offset(xr, yb - r - len), paint);
  }

  @override
  bool shouldRepaint(_FaceBracketPainter old) => old.color != color;
}

class _VerifiedBadgePainter extends CustomPainter {
  final Color color;
  const _VerifiedBadgePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 112;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final frameRect = Rect.fromLTRB(p(1.5, 1.5).dx, p(1.5, 1.5).dy,
        p(110.496, 110.496).dx, p(110.496, 110.496).dy);
    final rrect = RRect.fromRectAndRadius(frameRect, Radius.circular(14.5 * s));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * s);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      Offset(55.989 * s, 55.989 * s),
      19.998 * s,
      strokePaint,
    );
    canvas.drawPath(
        Path()
          ..moveTo(49.9897 * s, 55.9889 * s)
          ..lineTo(53.9894 * s, 59.9886 * s)
          ..lineTo(61.9887 * s, 51.9893 * s),
        strokePaint);
  }

  @override
  bool shouldRepaint(_VerifiedBadgePainter old) => old.color != color;
}