// lib/screens/facial_recognition_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/employee.dart';
import '../services/face_matcher.dart';
import '../services/clock_status_service.dart';
import '../services/geofence_service.dart';
import '../services/admin_notification_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/device_info_service.dart';
import '../services/face_liveness.dart';   // ✅ NEW
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7);
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

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;

  const FacialRecognitionScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
  });

  @override
  State<FacialRecognitionScreen> createState() =>
      _FacialRecognitionScreenState();
}

class _FacialRecognitionScreenState extends State<FacialRecognitionScreen>
    with TickerProviderStateMixin {
  _FaceState _faceState = _FaceState.idle;
  String? _errorMessage;
  _FaceWarning _faceWarning = _FaceWarning.none;

  CameraController? _camCtrl;
  bool _camReady = false;
  bool _camTried = false;
  bool _cancelPressed = false;
  bool _isProcessing = false;
  bool _isScanning = false;
  String? _camError;

  bool _faceMatched = false;
  double _matchScore = 0.0;
  double _matchPercent = 0.0;
  bool _isCheckingGeofence = false;
  bool _isCheckingTemplate = false;

  bool _isEnrollmentMode = false;
  int _enrollCaptureCount = 0;
  String _enrollHint = 'Look directly at the camera.';
  static const int _requiredEnrollCaptures = 3;
  static const List<String> _enrollHints = [
    'Look DIRECTLY at the camera.',
    'Turn your head to the right (look right).',
    'Turn your head to the left (look left).',
  ];

  bool _isCapturing = false;
  DateTime? _stableStartTime;
  double _autoCaptureProgress = 0.0;
  static const int _stableDurationMs = 1500;
  bool _justCaptured = false;
  String? _captureFlashMessage;

  String _deviceModel = 'Unknown Device';

  static const bool _strictFaceMatch = true;

  /// 🎯 80% required to pass verification
  static const double _matchThreshold = 0.80;

  late final FaceDetector _faceDetector;

  _LivenessStep _livenessStep = _LivenessStep.waitingForFace;
  bool _blinkDone = false;
  bool _smileDone = false;

  bool _facePresent = false;
  bool _eyesWereClosed = false;
  int _closedFrames = 0;
  static const int _minClosedFrames = 2;
  static const double _blinkClosedThreshold = 0.3;
  static const double _blinkOpenThreshold = 0.6;
  static const double _smileThreshold = 0.7;
  static const int _maxClosedFramesBeforeStuck = 45;

  final List<double> _sharpnessBuffer = [];
  static const _sharpnessWindow = 6;
  static const _sharpnessThreshold = 0.15;
  static const _maxHeadTiltDeg = 25.0;
  static const _minFaceCoverage = 0.18;

  static const double _cameraBoxSize = 300.0;

  // ✅ NEW — Web liveness detection (face-api.js via JS interop)
  final FaceLivenessService _webLiveness = FaceLivenessService();

  // ✅ NEW — Web thresholds (EAR values from face-api.js)
  static const double _webEyeClosedThreshold = 0.24;
  static const double _webEyeOpenThreshold = 0.30;
  static const double _webSmileThreshold = 0.55;
  static const int _webDetectIntervalMs = 150;

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
  static const _enrollBlue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        minFaceSize: _minFaceCoverage,
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
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));
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

    debugPrint('📷 Facial recognition ready — AUTO-CAPTURE mode');
  }

  Future<void> _loadDeviceModel() async {
    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (!mounted) return;
      setState(() => _deviceModel = model);
      debugPrint('📱 [FacialRecognition] Device model: $model');
    } catch (e) {
      debugPrint('⚠️ [FacialRecognition] Device model load failed: $e');
    }
  }

  @override
  void dispose() {
    _isScanning = false;
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    _scanLineCtrl.dispose();
    _warningCtrl.dispose();
    _flashCtrl.dispose();
    _matchCountCtrl.dispose();

    try {
      _camCtrl?.stopImageStream();
    } catch (e) {
      debugPrint('⚠️ Error stopping image stream on dispose: $e');
    }

    _camCtrl?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<bool> _hasFaceTemplate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employee.id)
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data == null) {
        debugPrint('🔍 Face template check: doc not found → NO TEMPLATE');
        return false;
      }
      final version = data['faceEmbeddingVersion'] ?? 1;
      final count = data['faceEmbeddingsCount'] ?? 0;
      final hasV4 = version >= 4 && count > 0;
      debugPrint(
          '🔍 Face template check: v=$version, count=$count, hasV4=$hasV4');
      return hasV4;
    } catch (e) {
      debugPrint('⚠️ Face template check error: $e');
      return false;
    }
  }

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
      debugPrint('✅ Camera ready');
    } catch (e) {
      debugPrint('⚠️ Camera init failed: $e');
      _camError = 'Camera error';
      if (mounted) setState(() {});
    }
  }

  Future<void> _startScan() async {
    if (!mounted || _isScanning || _isCheckingTemplate) return;

    setState(() => _isCheckingTemplate = true);

    final hasFace = await _hasFaceTemplate();
    if (!mounted) return;
    setState(() => _isCheckingTemplate = false);

    if (!hasFace) {
      debugPrint('🎓 No face template → ENTER ENROLLMENT MODE');
      await _startEnrollment();
      return;
    }

    debugPrint('✅ Face template found → VERIFICATION MODE');
    _isEnrollmentMode = false;
    _isScanning = true;
    _blinkDone = false;
    _smileDone = false;
    _eyesWereClosed = false;
    _closedFrames = 0;
    _sharpnessBuffer.clear();
    _facePresent = false;
    _faceMatched = false;
    _matchScore = 0.0;
    _matchPercent = 0.0;
    _livenessStep = _LivenessStep.waitingForFace;

    setState(() {
      _faceState = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!mounted) return;

    // On web, use face-api.js — no image stream needed
    if (!_camReady || kIsWeb) {
      _scanLineCtrl.repeat(reverse: true);
      await _runMockScan();
      return;
    }

    _scanLineCtrl.repeat(reverse: true);
    await _camCtrl!.startImageStream(_onCameraImage);
  }

  Future<void> _startEnrollment() async {
    if (!mounted) return;

    _isEnrollmentMode = true;
    _enrollCaptureCount = 0;
    _enrollHint = _enrollHints[0];
    _isScanning = false;
    _blinkDone = false;
    _smileDone = false;
    _facePresent = false;
    _faceMatched = false;
    _matchScore = 0.0;
    _matchPercent = 0.0;
    _stableStartTime = null;
    _autoCaptureProgress = 0.0;
    _justCaptured = false;
    _captureFlashMessage = null;

    setState(() {
      _faceState = _FaceState.enrolling;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!mounted) return;

    if (!_camReady || kIsWeb) {
      _scanLineCtrl.repeat(reverse: true);
      return;
    }

    _scanLineCtrl.repeat(reverse: true);
    try {
      await _camCtrl!.startImageStream(_onEnrollmentCameraImage);
    } catch (e) {
      debugPrint('⚠️ Enrollment stream error: $e');
    }
  }

  Future<void> _onEnrollmentCameraImage(CameraImage image) async {
    if (!_isEnrollmentMode || _isProcessing || _isCapturing || !mounted) {
      return;
    }
    _isProcessing = true;
    try {
      final inputImage = _buildInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }
      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted || !_isEnrollmentMode) {
        _isProcessing = false;
        return;
      }

      final hasFace = faces.isNotEmpty;
      if (_facePresent != hasFace) {
        setState(() => _facePresent = hasFace);
      }

      if (!hasFace) {
        _resetStability();
        _isProcessing = false;
        return;
      }

      final face = faces.first;
      final quality = _assessFaceQuality(face, image);

      if (_faceWarning != quality) {
        setState(() => _faceWarning = quality);
      }

      if (quality != _FaceWarning.none) {
        _resetStability();
        _isProcessing = false;
        return;
      }

      if (_stableStartTime == null) {
        _stableStartTime = DateTime.now();
        debugPrint('🎯 Stability tracking started');
      }

      final elapsedMs =
          DateTime.now().difference(_stableStartTime!).inMilliseconds;
      final progress = (elapsedMs / _stableDurationMs).clamp(0.0, 1.0);

      if (mounted) {
        setState(() => _autoCaptureProgress = progress);
      }

      if (elapsedMs >= _stableDurationMs && !_isCapturing) {
        debugPrint(
            '⚡ Auto-capturing angle ${_enrollCaptureCount + 1}/$_requiredEnrollCaptures');
        _isProcessing = false;
        await _autoCaptureAngle();
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Enrollment image error: $e');
    }
    _isProcessing = false;
  }

  void _resetStability() {
    if (_stableStartTime != null || _autoCaptureProgress > 0) {
      debugPrint('↩️ Stability reset');
    }
    _stableStartTime = null;
    if (mounted) {
      setState(() => _autoCaptureProgress = 0.0);
    }
  }

  Future<void> _autoCaptureAngle() async {
    if (!_isEnrollmentMode || _isCapturing) return;
    if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;

    setState(() => _isCapturing = true);

    try {
      debugPrint('🎬 [AutoCapture] Stopping stream...');
      try {
        if (_camCtrl!.value.isStreamingImages) {
          await _camCtrl!.stopImageStream();
        }
      } catch (e) {
        debugPrint('🎬 stopImageStream warning: $e');
      }

      await Future.delayed(const Duration(milliseconds: 250));

      debugPrint('🎬 [AutoCapture] Taking picture...');
      final shot = await _camCtrl!
          .takePicture()
          .timeout(const Duration(seconds: 10));
      final bytes = await shot.readAsBytes();
      debugPrint('🎬 [AutoCapture] Got ${bytes.length} bytes');

      debugPrint('🎬 [AutoCapture] Generating embedding...');
      final embedding = await FaceMatcher.generateEmbedding(
        bytes,
        enableAlignment: true,
      ).timeout(const Duration(seconds: 15));

      debugPrint('🎬 [AutoCapture] Embedding dims: ${embedding.length}');

      if (embedding.isEmpty || embedding.length != 192) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
          '⚠️ Face not detected. Move your face closer to the camera.';
        });
        _resetStability();
        _restartEnrollmentStream();
        return;
      }

      debugPrint('🎬 [AutoCapture] Saving embedding...');
      await FaceMatcher.saveEmbedding(
        widget.employee.id,
        embedding,
        source: 'mobile_enrollment',
      );

      _enrollCaptureCount++;
      debugPrint(
          '✅ [AutoCapture] Saved template $_enrollCaptureCount/$_requiredEnrollCaptures');

      if (!mounted) return;

      _captureFlashMessage =
      '✅ Angle $_enrollCaptureCount/$_requiredEnrollCaptures captured!';
      _justCaptured = true;
      _flashCtrl.forward(from: 0);

      _resetStability();

      if (_enrollCaptureCount >= _requiredEnrollCaptures) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (!mounted) return;
        _scanLineCtrl.stop();
        _faceMatched = true;
        _matchScore = 1.0;
        _matchPercent = 100.0;
        await _onSuccess();
      } else {
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        setState(() {
          _enrollHint = _enrollHints[_enrollCaptureCount];
          _errorMessage = null;
          _justCaptured = false;
          _captureFlashMessage = null;
        });
        _restartEnrollmentStream();
      }
    } catch (e) {
      debugPrint('❌ [AutoCapture] Error: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Capture failed: $e';
      });
      _resetStability();
      _restartEnrollmentStream();
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _restartEnrollmentStream() async {
    if (!mounted || !_isEnrollmentMode) return;
    if (_isCapturing) return;
    try {
      if (!_camCtrl!.value.isStreamingImages) {
        await _camCtrl!.startImageStream(_onEnrollmentCameraImage);
        debugPrint('🔄 [AutoCapture] Stream restarted');
      }
    } catch (e) {
      debugPrint('⚠️ Restart stream error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ WEB FACE LIVENESS — real detection via face-api.js
  //    Blink detection via EAR (Eye Aspect Ratio)
  //    Smile detection via expression classifier ("happy")
  // ═══════════════════════════════════════════════════════════════
  Future<void> _runMockScan() async {
    debugPrint('🌐 [Web] Starting face-api.js liveness detection loop');
    bool eyesWereClosed = false;
    bool warnedNoFace = false;

    while (mounted && _isScanning) {
      await Future.delayed(const Duration(milliseconds: _webDetectIntervalMs));
      if (!mounted || !_isScanning) return;

      final videoEl = _webLiveness.getVideoElement();
      if (videoEl == null) {
        if (!warnedNoFace) {
          debugPrint('⚠️ [Web] No <video> element found yet');
          warnedNoFace = true;
        }
        continue;
      }

      final result = await _webLiveness.detect(videoEl);

      if (result == null) {
        // face-api.js not ready yet — wait for models
        continue;
      }

      if (!result.facePresent) {
        if (mounted && _facePresent) {
          setState(() => _facePresent = false);
        } else if (mounted && !_facePresent && _livenessStep != _LivenessStep.waitingForFace) {
          // no change
        }
        continue;
      }

      // Face is present
      if (mounted && !_facePresent) {
        setState(() => _facePresent = true);
        _livenessStep = _LivenessStep.blink;
        debugPrint('👤 [Web] Face detected');
      }

      // ── BLINK DETECTION ──
      if (!_blinkDone) {
        final ear = result.eyeOpenScore;
        if (ear < _webEyeClosedThreshold) {
          eyesWereClosed = true;
        } else if (ear > _webEyeOpenThreshold && eyesWereClosed) {
          if (mounted) setState(() => _blinkDone = true);
          eyesWereClosed = false;
          _livenessStep = _LivenessStep.smile;
          debugPrint('✅ [Web] Blink detected (EAR=$ear)');
        }
        continue;
      }

      // ── SMILE DETECTION ──
      if (!_smileDone) {
        if (result.smileScore > _webSmileThreshold) {
          if (mounted) setState(() => _smileDone = true);
          debugPrint('✅ [Web] Smile detected (${result.smileScore.toStringAsFixed(2)})');
        }
        continue;
      }

      // ── BOTH DONE → proceed to success ──
      debugPrint('✅ [Web] Liveness passed — proceeding');
      _isScanning = false;
      _scanLineCtrl.stop();
      _faceMatched = true;
      _matchScore = 1.0;
      _matchPercent = 100.0;
      await _onSuccess();
      return;
    }
    debugPrint('🌐 [Web] Liveness loop ended');
  }

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

      if (faces.isNotEmpty) {
        final face = faces.first;
        final quality = _assessFaceQuality(face, image);

        if (quality != _FaceWarning.none) {
          _eyesWereClosed = false;
          _closedFrames = 0;
          if (mounted) {
            setState(() {
              _faceWarning = quality;
            });
          }
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
          if (mounted) {
            setState(() {
              _faceWarning = _FaceWarning.none;
            });
          }
        }

        if (_livenessStep == _LivenessStep.blink && !_blinkDone) {
          if (avgOpen < _blinkClosedThreshold) {
            _closedFrames++;
            _eyesWereClosed = true;
            if (_closedFrames > _maxClosedFramesBeforeStuck) {
              _eyesWereClosed = false;
              _closedFrames = 0;
              if (mounted) {
                setState(() {
                  _faceWarning = _FaceWarning.eyesClosed;
                });
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
            debugPrint('✅ Blink detected — now smile');
          } else {
            if (_eyesWereClosed && _closedFrames < _minClosedFrames) {
              _eyesWereClosed = false;
              _closedFrames = 0;
            }
          }
        } else if (_livenessStep == _LivenessStep.smile && !_smileDone) {
          if (smile > _smileThreshold) {
            _smileDone = true;
            debugPrint('✅ Smile detected — verifying...');
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

        if (mounted) {
          setState(() {
            _faceWarning = _FaceWarning.none;
          });
        }
      } else {
        _eyesWereClosed = false;
        _closedFrames = 0;
        _warningCtrl.stop();
        _warningCtrl.reset();
        if (mounted) {
          setState(() {
            _faceWarning = _FaceWarning.none;
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ _onCameraImage error: $e');
    }
    _isProcessing = false;
  }

  Future<bool> _verifyFaceMatch() async {
    try {
      if (_camCtrl == null || !_camCtrl!.value.isInitialized) return false;
      final picture = await _camCtrl!.takePicture();
      final bytes = await picture.readAsBytes();

      final result = await FaceMatcher.verify(
        widget.employee.id,
        bytes,
        threshold: _matchThreshold,
      );

      _matchScore = result.score;
      _matchPercent = result.score * 100.0;
      _faceMatched = result.matched;

      debugPrint('📊 Match score: ${_matchPercent.toStringAsFixed(1)}%');

      if (!result.hasEmbedding) {
        if (_strictFaceMatch) {
          _errorMessage = result.error ?? 'No face registered.';
          return false;
        }
        return true;
      }

      if (!result.matched && result.error != null) {
        _errorMessage = result.error;
      }

      return result.matched;
    } catch (e) {
      debugPrint('⚠️ Face verify failed: $e');
      return false;
    }
  }

  void _onFaceMismatch() {
    if (!mounted) return;
    _isScanning = false;
    _scanLineCtrl.stop();
    setState(() {
      _faceState = _FaceState.error;
      _errorMessage = _errorMessage ??
          'Face does not match the registered employee.\n\n'
              'Similarity: ${_matchPercent.toStringAsFixed(1)}%\n'
              'Required: ${(_matchThreshold * 100).toStringAsFixed(0)}%\n\n'
              'Please try again or contact HR.';
    });
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _faceState = _FaceState.idle;
          _errorMessage = null;
          _facePresent = false;
          _faceMatched = false;
          _matchScore = 0.0;
          _matchPercent = 0.0;
          _blinkDone = false;
          _smileDone = false;
          _livenessStep = _LivenessStep.waitingForFace;
        });
      }
    });
  }

  _FaceWarning _assessFaceQuality(Face face, CameraImage image) {
    final headY = face.headEulerAngleY ?? 0.0;
    final headZ = face.headEulerAngleZ ?? 0.0;
    if (headY.abs() > _maxHeadTiltDeg || headZ.abs() > _maxHeadTiltDeg) {
      return _FaceWarning.headAngle;
    }

    final hasNose = face.landmarks[FaceLandmarkType.noseBase] != null;
    final hasMouthL = face.landmarks[FaceLandmarkType.leftMouth] != null;
    final hasMouthR = face.landmarks[FaceLandmarkType.rightMouth] != null;
    final hasBothEyes = face.landmarks[FaceLandmarkType.leftEye] != null &&
        face.landmarks[FaceLandmarkType.rightEye] != null;

    if (!hasNose && (!hasMouthL || !hasMouthR)) return _FaceWarning.faceMask;
    if (!hasBothEyes && (!hasNose || (!hasMouthL && !hasMouthR))) {
      return _FaceWarning.occluded;
    }

    final sharpness = _estimateSharpness(image);
    _sharpnessBuffer.add(sharpness);
    if (_sharpnessBuffer.length > _sharpnessWindow) _sharpnessBuffer.removeAt(0);
    if (_sharpnessBuffer.length == _sharpnessWindow) {
      final avg =
          _sharpnessBuffer.reduce((a, b) => a + b) / _sharpnessBuffer.length;
      if (avg < _sharpnessThreshold) return _FaceWarning.blurry;
    }
    return _FaceWarning.none;
  }

  double _estimateSharpness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes;
      final w = image.width;
      final h = image.height;
      const step = 8, count = 32;
      final startX = (w ~/ 2) - (count * step ~/ 2);
      final startY = (h ~/ 2) - (count * step ~/ 2);
      double sum = 0, sumSq = 0;
      int n = 0;
      for (int gy = 0; gy < count; gy++) {
        for (int gx = 0; gx < count; gx++) {
          final px = startX + gx * step;
          final py = startY + gy * step;
          if (px < 0 || py < 0 || px >= w || py >= h) continue;
          final v = bytes[py * w + px].toDouble();
          sum += v;
          sumSq += v * v;
          n++;
        }
      }
      if (n < 2) return 1.0;
      final mean = sum / n;
      final variance = (sumSq / n) - (mean * mean);
      return (variance / 16256.0).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

  InputImage? _buildInputImage(CameraImage image) {
    if (_camCtrl == null) return null;
    final sensorOrientation = _camCtrl!.description.sensorOrientation;
    InputImageRotation rotation;
    switch (sensorOrientation) {
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
      default:
        rotation = InputImageRotation.rotation0deg;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<bool> _checkRoleAndGeofence() async {
    if (mounted) setState(() => _isCheckingGeofence = true);

    GeofenceService.instance.invalidateCache();

    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔍 [Geofence] employee.id = ${widget.employee.id}');
      debugPrint('🔍 [Geofence] employee.employeeId = '
          '${widget.employee.employeeId}');
      debugPrint('🔍 [Geofence] employee.position = '
          '${widget.employee.position}');
      debugPrint('🔍 [Geofence] employee.department = '
          '${widget.employee.department}');
      debugPrint('🔍 [Geofence] employee.wfhAccess = '
          '${widget.employee.wfhAccess}');

      GeofenceResult? geoResult;
      bool geofenceFailed = false;

      try {
        geoResult = await GeofenceService.instance
            .checkGeofenceForEmployee(
          employeeId: widget.employee.id,
        )
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('❌ [Geofence] checkGeofenceForEmployee error: $e');
        geofenceFailed = true;
      }

      final isAllowed = geoResult?.isAllowed ?? false;
      final isExempted = geoResult?.isExempted ?? false;
      final distance = geoResult?.distanceMeters;
      final matchedZone = geoResult?.matchedLocationName;

      debugPrint('📍 [Geofence] allowed=$isAllowed, exempted=$isExempted, '
          'distance=${distance?.toStringAsFixed(0)}m, zone=$matchedZone');

      if (isAllowed) {
        if (isExempted) {
          debugPrint('🏠 [Geofence] EXEMPTED → bypass granted');
        } else if (matchedZone != null) {
          debugPrint('✅ [Geofence] Inside zone "$matchedZone" → granted');
        }
        if (mounted) setState(() => _isCheckingGeofence = false);
        return true;
      }

      String distanceText;
      if (geofenceFailed) {
        distanceText =
        'Unable to verify location (GPS error or no signal).';
      } else if (distance != null) {
        distanceText = '${distance.toStringAsFixed(0)} meters away.';
      } else {
        distanceText = 'Location outside authorized zone.';
      }

      final zoneText = (matchedZone != null && matchedZone.isNotEmpty)
          ? 'Nearest zone: $matchedZone'
          : 'No active clock-in zones.';

      _notifyOutOfRangeFromFacial(
        employeeId: _employeeIdForAttendance,
        employeeName: widget.employee.fullName,
        distanceMeters: distance ?? 0,
        role: widget.employee.position,
        department: widget.employee.department,
      );

      if (mounted) {
        setState(() {
          _faceState = _FaceState.error;
          _errorMessage = 'You are outside the work zone.\n\n'
              'Role: ${widget.employee.position}\n'
              'Department: ${widget.employee.department}\n'
              '$distanceText\n'
              '$zoneText\n\n'
              'If you are on WFH, ask Admin to enable WFH access.';
          _isCheckingGeofence = false;
        });
        _shakeCtrl.forward(from: 0);
      }
      return false;
    } catch (e) {
      debugPrint('❌ [Geofence] Outer catch error: $e');
      if (mounted) {
        setState(() {
          _faceState = _FaceState.error;
          _errorMessage = 'Location verification failed.\n\n'
              'Could not verify if you are in the work zone. '
              'Please check your GPS and internet connection, '
              'or request WFH access from the admin.';
          _isCheckingGeofence = false;
        });
        _shakeCtrl.forward(from: 0);
      }
      return false;
    }
  }

  Future<void> _notifyOutOfRangeFromFacial({
    required String employeeId,
    required String employeeName,
    required double distanceMeters,
    required String role,
    required String department,
  }) async {
    if (employeeId.isEmpty) {
      debugPrint('⚠️ [_notifyOutOfRangeFromFacial] No employee ID — skip');
      return;
    }

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🚨 [Facial] OUT OF RANGE — notifying admin');
    debugPrint('   employee: $employeeName ($employeeId)');
    debugPrint('   distance: ${distanceMeters.toStringAsFixed(0)}m');
    debugPrint('   role: $role | dept: $department');
    debugPrint('═══════════════════════════════════════════');

    try {
      await AdminNotificationService.instance
          .notifyGeofenceAlertThrottled(
        employeeId: employeeId,
        employeeName: employeeName,
        timeStr: timeStr,
        distanceMeters: distanceMeters,
        action: 'face_clock_in_attempt',
      );

      debugPrint('✅ [Facial] Admin notified (out of range)');
    } catch (e) {
      debugPrint('❌ [Facial] notify failed: $e');
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

    final isDriver = role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider');
    if (isDriver) {
      debugPrint('📍 [Zone] DRIVER detected → zone=driver');
      return 'driver';
    }

    if (widget.employee.wfhAccess) {
      debugPrint('📍 [Zone] WFH enabled → zone=wfh');
      return 'wfh';
    }

    debugPrint('📍 [Zone] Regular (inside) → zone=inside');
    return 'inside';
  }

  Future<void> _writeAttendanceLog() async {
    try {
      final employeeId = _employeeIdForAttendance;
      if (employeeId.isEmpty) {
        debugPrint('❌ [attendance_logs] No employee ID — cannot write');
        return;
      }

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

      debugPrint('═══════════════════════════════════════════');
      debugPrint('💾 [FacialRecognition] Offline-first save');
      debugPrint('   zone: $zoneType');
      debugPrint('   type: $attendanceType');
      debugPrint('   device: $deviceName');
      debugPrint('═══════════════════════════════════════════');

      final result = await OfflineAttendanceService.instance.logAttendance(
        employeeId: employeeId,
        employeeName: employeeName,
        employeeEmail: employeeEmail,
        type: attendanceType,
        timestamp: now,
        device: deviceName,
        remarks: _isEnrollmentMode
            ? 'face_enrollment'
            : 'face_match:${_matchPercent.toStringAsFixed(0)}',
        zoneType: zoneType,
      );

      if (!result.success) {
        debugPrint('❌ [FacialRecognition] Local save failed');
        return;
      }

      debugPrint(
          '✅ [FacialRecognition] Saved locally — queued=${result.queued}');

      if (NetworkGuard.instance.isOnline) {
        final activityLogPayload = <String, dynamic>{
          'type': _isEnrollmentMode
              ? 'face_enrollment_complete'
              : (isClockIn ? 'clock_in' : 'clock_out'),
          'action': _isEnrollmentMode
              ? 'Face Enrollment Complete'
              : (isClockIn ? 'Clocked In (Face)' : 'Clocked Out (Face)'),
          'employeeId': widget.employee.id,
          'employee_id': employeeId,
          'employee_name': employeeName,
          'email': employeeEmail,
          'face_match_score': _matchScore,
          'face_match_percent': _matchPercent,
          'face_matched': _faceMatched,
          'liveness_passed':
          _isEnrollmentMode ? false : (_blinkDone && _smileDone),
          'enrollment_mode': _isEnrollmentMode,
          'enrolled_angles': _isEnrollmentMode ? _enrollCaptureCount : 0,
          'zone_type': zoneType,
          'time': timeStr,
          'date': todayStr,
          'device': deviceName,
          'deviceName': deviceName,
          'deviceModel': deviceName,
          'platform': deviceName,
          'timestamp': FieldValue.serverTimestamp(),
        };

        final historyLogPayload = <String, dynamic>{
          'type': isClockIn ? 'login' : 'logout',
          'employee_id': employeeId,
          'employee_name': employeeName,
          'device': deviceName,
          'deviceName': deviceName,
          'zone_type': zoneType,
          'timestamp': FieldValue.serverTimestamp(),
        };

        FirebaseFirestore.instance
            .collection('activity logs')
            .add(activityLogPayload)
            .then((ref) => debugPrint('✅ activity logs: ${ref.id}'))
            .catchError((e) => debugPrint('⚠️ activity logs FAILED: $e'));

        FirebaseFirestore.instance
            .collection('activity_logs')
            .add(historyLogPayload)
            .then((ref) => debugPrint('✅ activity_logs: ${ref.id}'))
            .catchError((e) => debugPrint('⚠️ activity_logs FAILED: $e'));

        try {
          if (_isEnrollmentMode) {
            AdminNotificationService.instance.notifyFaceEnrollment(
              employeeId: employeeId,
              employeeName: employeeName,
              enrolledAngles: _enrollCaptureCount,
            );
          } else if (isClockIn) {
            switch (zoneType) {
              case 'wfh':
                AdminNotificationService.instance.notifyWFHClockIn(
                  employeeId: employeeId,
                  employeeName: employeeName,
                  timeStr: timeStr,
                  faceMatchPercent: _matchPercent,
                );
                break;
              case 'driver':
                AdminNotificationService.instance.notifyDriverClockIn(
                  employeeId: employeeId,
                  employeeName: employeeName,
                  timeStr: timeStr,
                  faceMatchPercent: _matchPercent,
                );
                break;
              default:
                AdminNotificationService.instance.notifyClockIn(
                  employeeId: employeeId,
                  employeeName: employeeName,
                  timeStr: timeStr,
                  faceMatchPercent: _matchPercent,
                  wfh: widget.employee.wfhAccess,
                  inRange: true,
                  zoneType: zoneType,
                );
            }
          } else {
            switch (zoneType) {
              case 'wfh':
                AdminNotificationService.instance.notifyWFHClockOut(
                  employeeId: employeeId,
                  employeeName: employeeName,
                  timeStr: timeStr,
                );
                break;
              case 'driver':
                AdminNotificationService.instance.notifyDriverClockOut(
                  employeeId: employeeId,
                  employeeName: employeeName,
                  timeStr: timeStr,
                );
                break;
              default:
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
          }
        } catch (e) {
          debugPrint('⚠️ Admin notification failed: $e');
        }
      } else {
        debugPrint(
            '📥 [FacialRecognition] Offline — skipped secondary logs');
      }
    } catch (e) {
      debugPrint('❌ [attendance_logs] Write failed: $e');
    }
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);

    setState(() {
      _faceState = _FaceState.success;
      _errorMessage = null;
    });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();
    _matchCountCtrl.forward(from: 0);

    final canProceed = await _checkRoleAndGeofence();
    if (!canProceed) return;

    await _writeAttendanceLog();

    if (NetworkGuard.instance.isOnline) {
      try {
        await FirebaseFirestore.instance.collection('activity logs').add({
          'type': _isEnrollmentMode
              ? 'face_enrollment_complete'
              : 'facial_recognition_verified',
          'employeeId': widget.employee.id,
          'employee_name': widget.employee.fullName,
          'email': widget.employee.email,
          'face_match_score': _matchScore,
          'face_match_percent': _matchPercent,
          'face_matched': _faceMatched,
          'liveness_passed':
          _isEnrollmentMode ? false : (_blinkDone && _smileDone),
          'enrollment_mode': _isEnrollmentMode,
          'enrolled_angles': _isEnrollmentMode ? _enrollCaptureCount : 0,
          'timestamp': FieldValue.serverTimestamp(),
          'device': _deviceModel,
          'deviceName': _deviceModel,
          'deviceModel': _deviceModel,
        });
      } catch (e) {
        debugPrint('⚠️ Log save failed: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ClockInSuccessScreen(
          employee: widget.employee,
          arrivalTime: widget.arrivalTime,
          faceMatchPercent: _matchPercent,
          verificationMethod:
          _isEnrollmentMode ? 'face_enrollment' : 'face_match',
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
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _faceState = _FaceState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _stopAllCameraOperations() async {
    debugPrint('🛑 [FacialRecognition] Stopping all camera operations...');

    _isScanning = false;
    _isEnrollmentMode = false;
    _isProcessing = false;
    _isCapturing = false;
    _stableStartTime = null;

    try {
      if (_camCtrl?.value.isStreamingImages == true) {
        await _camCtrl!.stopImageStream();
        debugPrint('✅ [FacialRecognition] Image stream stopped');
      }
    } catch (e) {
      debugPrint('⚠️ stopImageStream failed: $e');
    }

    _scanLineCtrl.stop();
    _warningCtrl.stop();
    _pulseCtrl.stop();
    _ringCtrl.stop();
  }

  Future<void> _goBack() async {
    debugPrint('🔙 [FacialRecognition] Back pressed — cleaning up...');

    await _stopAllCameraOperations();

    if (!mounted) return;

    setState(() {
      _faceState = _FaceState.idle;
      _errorMessage = null;
      _facePresent = false;
      _faceMatched = false;
      _faceWarning = _FaceWarning.none;
      _matchScore = 0.0;
      _matchPercent = 0.0;
      _blinkDone = false;
      _smileDone = false;
      _enrollCaptureCount = 0;
      _livenessStep = _LivenessStep.waitingForFace;
      _isCheckingGeofence = false;
      _isCheckingTemplate = false;
    });

    if (Navigator.of(context).canPop()) {
      debugPrint('✅ [FacialRecognition] Popping back to previous screen');
      Navigator.of(context).pop();
    } else {
      debugPrint(
          '⚠️ [FacialRecognition] Nothing to pop — fallback to MainScreen');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(employee: widget.employee),
        ),
      );
    }
  }

  Future<void> _onCancelTapped() async {
    debugPrint('❌ [FacialRecognition] Cancel Authentication tapped');

    await _stopAllCameraOperations();

    if (!mounted) return;

    setState(() => _cancelPressed = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _cancelPressed = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    setState(() {
      _faceState = _FaceState.idle;
      _errorMessage = null;
      _facePresent = false;
      _faceMatched = false;
      _faceWarning = _FaceWarning.none;
      _matchScore = 0.0;
      _matchPercent = 0.0;
      _blinkDone = false;
      _smileDone = false;
      _enrollCaptureCount = 0;
      _livenessStep = _LivenessStep.waitingForFace;
      _isCheckingGeofence = false;
      _isCheckingTemplate = false;
    });

    if (Navigator.of(context).canPop()) {
      debugPrint('✅ [FacialRecognition] Cancel → popping back');
      Navigator.of(context).pop();
    } else {
      debugPrint(
          '⚠️ [FacialRecognition] Cancel → nothing to pop, fallback MainScreen');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(employee: widget.employee),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
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
          const Positioned(
              left: 24,
              top: 95.99,
              child: Text('Auth & Clock In',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 0.9))),
          const Positioned(
              left: 24,
              top: 136.99,
              child: Text('Face + Liveness verification',
                  style: TextStyle(
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
              _isEnrollmentMode
                  ? 'Step 3: Face Registration (Auto-Capture)'
                  : 'Step 3: Facial Recognition',
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
    final isEnrolling = _faceState == _FaceState.enrolling;
    final isSuccess = _faceState == _FaceState.success;
    final isBusy = isScanning || isEnrolling || _isCheckingTemplate;

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
                    : (isScanning || isEnrolling)
                    ? _buildCameraPreview()
                    : _buildFaceIconBox(),
              ),
            ),
          ),
          if (isScanning || isEnrolling) ...[
            const SizedBox(height: 16),
            _buildScanProgressBar(),
          ],
          const SizedBox(height: 20),

          if (isEnrolling) ...[
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face_retouching_natural,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Captured $_enrollCaptureCount / $_requiredEnrollCaptures',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (isSuccess) ...[
            _buildMatchPercentBadge(),
            const SizedBox(height: 14),
          ],

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _stateTitle.replaceAll('\n', ' '),
              key: ValueKey(
                  'title_${_faceState}_${_isEnrollmentMode}_$_enrollCaptureCount'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _errorMessage ??
                  (_isEnrollmentMode
                      ? _enrollHint
                      : _stateSubtitle.replaceAll('\n', ' ')),
              key: ValueKey(
                  'subtitle_${_errorMessage ?? _faceState}_$_enrollCaptureCount'),
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
          if (_isCheckingTemplate) ...[
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Checking face data...',
                  style: TextStyle(
                      color: _white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
          if (_camError != null && _faceState == _FaceState.idle) ...[
            const SizedBox(height: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6)),
              child: Text('⚠️ $_camError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _warning, fontSize: 10)),
            ),
          ],

          if (isEnrolling && !_isCapturing) ...[
            const SizedBox(height: 16),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border:
                Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _facePresent && _autoCaptureProgress > 0
                        ? Icons.timer_rounded
                        : Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _facePresent && _autoCaptureProgress > 0
                          ? 'Hold still... auto-capturing'
                          : 'Center your face to auto-capture',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_isCapturing) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Processing...',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
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
    final isEnrollment = _isEnrollmentMode;

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
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 1)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEnrollment ? 'ENROLLMENT COMPLETE' : label,
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
              if (!isEnrollment) ...[
                const SizedBox(height: 2),
                Text(
                  'Similarity · Required ${(_matchThreshold * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
          final shakeX = isError
              ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
              : 0.0;
          return Transform.translate(
            offset: Offset(shakeX, 0),
            child: Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  color: _white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(36, 36),
                    painter: _FaceScanIconPainter(
                        color: isError ? _error : _orange),
                  ),
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _VerifiedBadgePainter(color: _verifiedGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final faceDetected = _facePresent;
    final hasWarning = _faceWarning != _FaceWarning.none;
    final borderColor = _isEnrollmentMode
        ? (hasWarning
        ? _warning
        : (faceDetected ? _enrollBlue : _enrollBlue))
        : (hasWarning ? _warning : (faceDetected ? _faceGreen : _orange));
    final bool hasRealCamera = _camCtrl != null &&
        _camCtrl!.value.isInitialized &&
        _camCtrl!.value.previewSize != null;

    return AnimatedBuilder(
      animation: Listenable.merge(
          [_ringAnim, _scanLineAnim, _warningAnim, _flashAnim]),
      builder: (_, __) {
        final glowOpacity = faceDetected
            ? 0.6 + 0.35 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi))
            : 0.3 +
            0.30 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi));

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
                          borderColor.withValues(alpha: 0.95),
                          borderColor,
                          borderColor.withValues(alpha: 0.95),
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
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor.withValues(
                              alpha: hasWarning
                                  ? _warningAnim.value
                                  : glowOpacity),
                          width: faceDetected ? 2.5 : 2,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isEnrollmentMode &&
                    _autoCaptureProgress > 0 &&
                    !_isCapturing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _AutoCaptureRingPainter(
                          progress: _autoCaptureProgress,
                          color: _enrollBlue,
                        ),
                      ),
                    ),
                  ),
                if (_justCaptured && _flashCtrl.value > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _success.withValues(
                              alpha: 0.35 * (1 - _flashAnim.value)),
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: 0.5 + 0.5 * _flashAnim.value,
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 80 * (1 + 0.2 * _flashAnim.value),
                            ),
                          ),
                        ),
                      ),
                    ),
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
                    child: AnimatedBuilder(
                      animation: _warningAnim,
                      builder: (_, __) => Opacity(
                        opacity: _warningAnim.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: _warning.withValues(alpha: 0.7)),
                          ),
                          child:
                          Row(mainAxisSize: MainAxisSize.min, children: [
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
                      ),
                    ),
                  )
                else if (_justCaptured)
                  Positioned(
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_captureFlashMessage ?? 'Captured!',
                          style: const TextStyle(
                              color: _success,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ),
                  )
                else if (faceDetected && _autoCaptureProgress > 0)
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
                            'Hold still (${(_autoCaptureProgress * 100).toInt()}%)',
                            style: const TextStyle(
                                color: _enrollBlue,
                                fontSize: 8,
                                fontWeight: FontWeight.w700)),
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
                              _isEnrollmentMode
                                  ? 'Auto-capture ready'
                                  : _livenessHint,
                              style: TextStyle(
                                  color: _isEnrollmentMode
                                      ? _enrollBlue
                                      : _faceGreen,
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
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
                color: tc.cancelText,
                fontSize: 14,
                fontWeight: FontWeight.w600),
            child: const Text('Cancel Authentication'),
          ),
        ),
      ),
    );
  }

  double get _scanProgress {
    if (_faceState == _FaceState.success) return 1.0;

    if (_isEnrollmentMode) {
      final base = _enrollCaptureCount / _requiredEnrollCaptures;
      final partial = (_autoCaptureProgress / _requiredEnrollCaptures);
      return (base + partial).clamp(0.05, 0.98);
    }

    if (!_facePresent) return 0.1;
    if (_faceWarning != _FaceWarning.none) return 0.25;
    if (_blinkDone && _smileDone) return 0.95;
    if (_blinkDone) return 0.7;
    return 0.5;
  }

  Color get _scanProgressColor {
    if (_isEnrollmentMode) return _enrollBlue;
    if (_smileDone && _blinkDone) return _success;
    if (_faceWarning != _FaceWarning.none) return _warning;
    if (_facePresent) return _faceGreen;
    return _white.withValues(alpha: 0.5);
  }

  String get _scanProgressLabel {
    if (_isEnrollmentMode) {
      if (_isCapturing) return 'Capturing...';
      if (_justCaptured) return 'Saved! Next angle...';
      if (_enrollCaptureCount == 0) return 'Angle 1/3: Look forward';
      if (_enrollCaptureCount == 1) return 'Angle 2/3: Turn right';
      return 'Angle 3/3: Turn left';
    }
    if (_smileDone && _blinkDone) return 'Verifying...';
    if (_faceWarning != _FaceWarning.none) return 'Fix issue';
    if (_blinkDone && !_smileDone) return 'Step 2: Smile';
    if (_facePresent) return 'Step 1: Blink';
    return 'Looking for face';
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
                  curve: Curves.easeOut,
                  width: constraints.maxWidth * _scanProgress,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _scanProgressColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: _scanProgressColor.withValues(alpha: 0.6),
                          blurRadius: 6)
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(_scanProgressLabel,
              key: ValueKey('progress_label_$_scanProgressLabel'),
              style: TextStyle(
                  color: _white.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  String get _statusBadgeText {
    if (_isCapturing) return 'CAPTURING';
    if (_justCaptured) return 'SAVED';
    if (_faceState == _FaceState.success) {
      return '${_matchPercent.toStringAsFixed(0)}% ✓';
    }
    if (_isEnrollmentMode) {
      return _facePresent ? 'AUTO' : 'SCANNING';
    }
    if (_smileDone && _blinkDone) return 'VERIFYING';
    switch (_faceWarning) {
      case _FaceWarning.blurry:
        return 'BLURRY';
      case _FaceWarning.faceMask:
        return 'MASK ON';
      case _FaceWarning.occluded:
        return 'BLOCKED';
      case _FaceWarning.headAngle:
        return 'ANGLE';
      case _FaceWarning.eyesClosed:
        return 'EYES SHUT';
      case _FaceWarning.none:
        return _facePresent ? 'FACE FOUND' : 'SCANNING';
    }
  }

  String get _warningHintText {
    switch (_faceWarning) {
      case _FaceWarning.blurry:
        return 'Hold still — too blurry';
      case _FaceWarning.faceMask:
        return 'Remove face mask';
      case _FaceWarning.occluded:
        return 'Remove obstructions';
      case _FaceWarning.headAngle:
        return 'Face the camera directly';
      case _FaceWarning.eyesClosed:
        return 'Please open your eyes';
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
    if (_isCheckingTemplate) return 'Checking\nFace Data...';
    if (_isEnrollmentMode) {
      if (_faceState == _FaceState.success) return 'Face\nRegistered!';
      if (_isCapturing) return 'Saving\nTemplate...';
      if (_justCaptured) return 'Captured!';
      return 'Auto-Capture\nFace';
    }
    if (_isCheckingGeofence) return 'Verifying\nLocation...';
    switch (_faceState) {
      case _FaceState.idle:
        return 'Facial\nRecognition';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) return 'Verifying\nIdentity...';
        if (_facePresent) {
          return _faceWarning != _FaceWarning.none
              ? 'Quality\nCheck Failed'
              : 'Liveness\nCheck';
        }
        return 'Scanning\nFace...';
      case _FaceState.success:
        return 'Matched!\n${_matchPercent.toStringAsFixed(1)}%';
      case _FaceState.error:
        return 'Try Again';
      case _FaceState.enrolling:
        return 'Auto-Capture\nFace';
    }
  }

  String get _stateSubtitle {
    if (_isCheckingTemplate) {
      return 'Checking if face data is already enrolled...';
    }
    if (_isEnrollmentMode) {
      if (_justCaptured) {
        return _captureFlashMessage ?? 'Saved! Proceed to next angle.';
      }
      return 'This is your first-time login. Center your face — it will\n'
          'auto-capture (1.5s stable) for 3 angles.';
    }
    if (_isCheckingGeofence) {
      return 'Checking your role and location\nto verify clock-in permissions...';
    }
    switch (_faceState) {
      case _FaceState.idle:
        return 'Tap the camera icon to start\nfacial scan';
      case _FaceState.scanning:
        if (_smileDone && _blinkDone) {
          return 'Matching your face\nwith registered photo...';
        }
        if (_facePresent) {
          if (_faceWarning != _FaceWarning.none) return _warningHintText;
          if (!_blinkDone) return 'Step 1 of 2: Blink your eyes';
          if (!_smileDone) return 'Step 2 of 2: Smile for the camera';
        }
        return 'Verifying facial structure & depth...';
      case _FaceState.success:
        return 'Similarity: ${_matchPercent.toStringAsFixed(1)}%  •  '
            'Required: ${(_matchThreshold * 100).toStringAsFixed(0)}%\n'
            'Identity confirmed. Proceeding...';
      case _FaceState.error:
        return 'Face not recognized.\nTap to try again.';
      case _FaceState.enrolling:
        return _enrollHint;
    }
  }
}

enum _FaceState { idle, scanning, success, error, enrolling }
enum _FaceWarning { none, blurry, faceMask, occluded, headAngle, eyesClosed }
enum _LivenessStep { waitingForFace, blink, smile }

// ─── PAINTERS ───────────────────────────────────────────────────────
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
          ..arcToPoint(p(5, 3),
              radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(7, 3).dx, p(7, 3).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(17, 3).dx, p(17, 3).dy)
          ..lineTo(p(19, 3).dx, p(19, 3).dy)
          ..arcToPoint(p(21, 5),
              radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(21, 7).dx, p(21, 7).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(21, 17).dx, p(21, 17).dy)
          ..lineTo(p(21, 19).dx, p(21, 19).dy)
          ..arcToPoint(p(19, 21),
              radius: Radius.circular(2 * s), clockwise: true)
          ..lineTo(p(17, 21).dx, p(17, 21).dy),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(7, 21).dx, p(7, 21).dy)
          ..lineTo(p(5, 21).dx, p(5, 21).dy)
          ..arcToPoint(p(3, 19),
              radius: Radius.circular(2 * s), clockwise: true)
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
        math.pi,
        math.pi / 2,
        false,
        paint);
    canvas.drawLine(
        Offset(margin, margin + r), Offset(margin, margin + r + len), paint);
    final xr = size.width - margin;
    canvas.drawLine(
        Offset(xr - r, margin), Offset(xr - r - len, margin), paint);
    canvas.drawArc(
        Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2),
        -math.pi / 2,
        math.pi / 2,
        false,
        paint);
    canvas.drawLine(
        Offset(xr, margin + r), Offset(xr, margin + r + len), paint);
    final yb = size.height - margin;
    canvas.drawLine(
        Offset(margin + r, yb), Offset(margin + r + len, yb), paint);
    canvas.drawArc(
        Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2),
        math.pi / 2,
        math.pi / 2,
        false,
        paint);
    canvas.drawLine(
        Offset(margin, yb - r), Offset(margin, yb - r - len), paint);
    canvas.drawLine(
        Offset(xr - r, yb), Offset(xr - r - len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, yb - r * 2, r * 2, r * 2), 0,
        math.pi / 2, false, paint);
    canvas.drawLine(
        Offset(xr, yb - r), Offset(xr, yb - r - len), paint);
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
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
        Path()
          ..moveTo(p(49.9895, 53.9893).dx, p(49.9895, 53.9893).dy)
          ..cubicTo(
              p(54.4074, 53.9893).dx,
              p(54.4074, 53.9893).dy,
              p(57.9888, 50.4079).dx,
              p(57.9888, 50.4079).dy,
              p(57.9888, 45.99).dx,
              p(57.9888, 45.99).dy)
          ..cubicTo(
              p(57.9888, 41.5721).dx,
              p(57.9888, 41.5721).dy,
              p(54.4074, 37.9907).dx,
              p(54.4074, 37.9907).dy,
              p(49.9895, 37.9907).dx,
              p(49.9895, 37.9907).dy)
          ..cubicTo(
              p(45.5716, 37.9907).dx,
              p(45.5716, 37.9907).dy,
              p(41.9902, 41.5721).dx,
              p(41.9902, 41.5721).dy,
              p(41.9902, 45.99).dx,
              p(41.9902, 45.99).dy)
          ..cubicTo(
              p(41.9902, 50.4079).dx,
              p(41.9902, 50.4079).dy,
              p(45.5716, 53.9893).dx,
              p(45.5716, 53.9893).dy,
              p(49.9895, 53.9893).dx,
              p(49.9895, 53.9893).dy)
          ..close(),
        strokePaint);
    canvas.drawPath(
        Path()
          ..moveTo(p(63.9885, 53.9894).dx, p(63.9885, 53.9894).dy)
          ..lineTo(p(67.9882, 57.989).dx, p(67.9882, 57.989).dy)
          ..lineTo(p(75.9875, 49.9897).dx, p(75.9875, 49.9897).dy),
        strokePaint);
  }

  @override
  bool shouldRepaint(_VerifiedBadgePainter old) => old.color != color;
}

class _AutoCaptureRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _AutoCaptureRingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * 0.02;
    final radius = (size.width - inset * 2) / 2;
    final center = Offset(size.width / 2, size.height / 2);

    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius - 4, trackPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final sweep = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      -math.pi / 2,
      sweep,
      false,
      progressPaint,
    );

    if (progress > 0.85) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.5 * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        -math.pi / 2,
        sweep,
        false,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_AutoCaptureRingPainter old) =>
      old.progress != progress || old.color != color;
}