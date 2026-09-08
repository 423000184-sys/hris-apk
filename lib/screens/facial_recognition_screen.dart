// lib/screens/facial_recognition_screen.dart
//
<<<<<<< HEAD
// "Auth & Clock In" — Facial Recognition step.
// Visual design ported 1:1 from the orange HTML mocks (dimmed
// "Auth & Clock In" background + dark scrim + floating orange gradient
// modal card — same shell as fingerprint_screen.dart), with these
// per-state contents:
//   idle:     "Facial Recognition" / face-scan icon (orange)
//   scanning: "Scanning Face..." / live camera feed inside the icon box
//   success:  "Details Verified" / shield-check icon w/ green (#51FF00) ring
//   error:    "Try Again" / face-scan icon (red) + shake
//
// Camera behavior is LIVE, like GCash's face-verification flow:
//   • Front camera streams frames in real time (no static photo capture).
//   • Google ML Kit Face Detection runs on-device, every frame.
//   • The user must hold a clear, unobstructed, forward-facing face for
//     `_holdDuration` before it's accepted.
//   • Rejects: blurry frames, face masks, occluded landmarks, closed eyes,
//     and extreme head tilt — each surfaces as the subtitle text under the
//     icon box (kept off the box itself so the box stays visually identical
//     to the mock's 112x112 icon frame).
//   • The camera preview is horizontally mirrored (selfie view) — only the
//     on-screen preview is mirrored, the raw frame sent to ML Kit is not.
//
// ── Required pubspec.yaml dependencies ──────────────────────────────────
//   camera: ^0.10.5+9
//   google_mlkit_face_detection: ^0.11.0
//   cloud_firestore: ^5.6.2      (optional — used to log the verification)
//   permission_handler: ^11.3.1  (runtime camera permission)
//
// This file expects three sibling types to already exist in your app:
//   Employee                (model with id, fullName, email)
//   MainScreen(employee)    (destination after clock-in)
//   ClockInSuccessScreen(employee, onContinue)  (success interstitial)
=======
// Step 3: Facial Recognition screen.
// Uses Google ML Kit Face Detection for LIVE on-device face detection.
// Features: blur detection, face mask detection, occlusion detection.
// The scan only succeeds when a clear, unobstructed real face is confirmed.
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
<<<<<<< HEAD
import 'package:permission_handler/permission_handler.dart';
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import '../models/employee.dart';
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  const FacialRecognitionScreen({super.key, required this.employee});

  @override
  State<FacialRecognitionScreen> createState() => _FacialRecognitionScreenState();
}

class _FacialRecognitionScreenState extends State<FacialRecognitionScreen>
    with TickerProviderStateMixin {
<<<<<<< HEAD
  _FaceState _faceState = _FaceState.idle;
  String? _errorMessage;
  _FaceWarning _faceWarning = _FaceWarning.none;

  // ── Camera ────────────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _camReady = false;
  bool _cancelPressed = false;
  bool _isProcessing = false;
  bool _isScanning = false;

  // ── ML Kit ────────────────────────────────────────────────────────────
=======

  _FaceState _faceState    = _FaceState.idle;
  String?    _errorMessage;
  // Granular warning shown inside the camera preview
  _FaceWarning _faceWarning = _FaceWarning.none;

  // ── Camera ─────────────────────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _camReady       = false;
  bool _cancelPressed  = false;
  bool _isProcessing   = false;
  bool _isScanning     = false;

  // ── ML Kit ────────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  late final FaceDetector _faceDetector;

  static const _holdDuration = Duration(seconds: 2);
  DateTime? _faceFirstSeen;
  int _detectedFaceCount = 0;

<<<<<<< HEAD
  final List<double> _sharpnessBuffer = [];
  static const _sharpnessWindow = 6;
  static const _sharpnessThreshold = 0.18;
  static const _minEyeOpenProb = 0.5;
  static const _maxHeadTiltDeg = 30.0;
  static const _minFaceCoverage = 0.20;

  // ── Animations ────────────────────────────────────────────────────────
=======
  // Rolling sharpness buffer (last N frames)
  final List<double> _sharpnessBuffer = [];
  static const _sharpnessWindow = 6;          // frames to average
  static const _sharpnessThreshold = 0.18;    // normalised; tune per device
  static const _minEyeOpenProb = 0.5;         // below this = eyes closed / obscured
  static const _maxHeadTiltDeg = 30.0;        // reject extreme head poses
  static const _minFaceCoverage = 0.20;       // face bbox must be ≥20 % of frame

  // ── Animations ────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;
<<<<<<< HEAD
=======
  late AnimationController _scanLineCtrl;
  late AnimationController _warningCtrl;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;
  late Animation<double> _successAnim;
<<<<<<< HEAD

  // ── Design tokens — converted from the HTML mocks (idle / scanning / success) ──
  static const _bgTop        = Color(0xFFFFFFFF);
  static const _bgMid        = Color(0xFFFFF0E5);
  static const _bgBottom     = Color(0xFFFFE3D1);

  static const _headerStart  = Color(0xFFFF5500);
  static const _headerEnd    = Color(0xFFFF6B00);

  static const _cardBorder   = Color(0xFFFDBA74);
  static const _textDark     = Color(0xFF1F2937);

  static const _modalGradTop = Color(0xFFFF8A00);
  static const _modalGradMid = Color(0xFFFA6A00);
  static const _modalGradEnd = Color(0xFFF54900);

  // All three facial-recognition mock states use the SAME border color
  // (unlike the fingerprint screen, which switches border on success).
  static const _modalBorder  = Color(0xFF27272A);

  // Bright green ring drawn around the white icon box on success
  // (matches the mock's <path stroke="#51FF00">).
  static const _successRing  = Color(0xFF51FF00);

  static const _scrim        = Color.fromRGBO(9, 9, 11, 0.44);

  static const _white   = Color(0xFFFFFFFF);
  static const _white70 = Color(0xFFDFDFDF);
  static const _orange  = Color(0xFFF97316);
  static const _success = Color(0xFF22C55E);
  static const _error   = Color(0xFFDC2626);
  static const _warning = Color(0xFFFFCC00);
  static const _faceGreen = Color(0xFF22C55E);

  // Cancel button — mock uses the SAME color (#ffa500) for both text and
  // border, unlike the fingerprint screen's two-tone version.
  static const _cancelColor = Color(0xFFFFA500);
=======
  late Animation<double> _scanLineAnim;
  late Animation<double> _warningAnim;

  // ── Colors ─────────────────────────────────────────────────────────────────
  static const _bg        = Color(0xFF0A0A0A);
  static const _white     = Color(0xFFFFFFFF);
  static const _white70   = Color(0xB3FFFFFF);
  static const _white50   = Color(0x80FFFFFF);
  static const _white40   = Color(0x66FFFFFF);
  static const _white15   = Color(0x26FFFFFF);
  static const _white08   = Color(0x14FFFFFF);
  static const _orange    = Color(0xFFFF6600);
  static const _success   = Color(0xFFCCFF00);
  static const _error     = Color(0xFFFF3D00);
  static const _faceGreen = Color(0xFF00E676);
  static const _warning   = Color(0xFFFFCC00);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();

<<<<<<< HEAD
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
=======
    // ── ML Kit face detector — enable landmarks + contours for occlusion ──
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,   // eye-open probability
        enableLandmarks: true,        // nose, mouth, eye positions
        enableContours: true,         // face contour points
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        minFaceSize: _minFaceCoverage,
      ),
    );

<<<<<<< HEAD
    _pulseCtrl   = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl    = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl   = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

    _pulseAnim   = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim    = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));
    _fadeAnim    = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _shakeAnim   = Tween<double>(begin: 0, end: 12)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
=======
    // ── Animation controllers ──────────────────────────────────────────────
    _pulseCtrl    = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl     = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scanLineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _warningCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _pulseAnim    = Tween<double>(begin: 0.93, end: 1.07)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _ringAnim     = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.linear));
    _fadeAnim     = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _shakeAnim    = Tween<double>(begin: 0, end: 12)
        .animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _successAnim  = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scanLineCtrl, curve: Curves.easeInOut));
    _warningAnim  = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _warningCtrl, curve: Curves.easeInOut));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();
<<<<<<< HEAD

    // Auto-start the live scan on open, same pattern as the fingerprint screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), _startScan);
    });
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  }

  @override
  void dispose() {
    _isScanning = false;
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
<<<<<<< HEAD
=======
    _scanLineCtrl.dispose();
    _warningCtrl.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _faceDetector.close();
    super.dispose();
  }

<<<<<<< HEAD
  // ── Camera permission (runtime, before touching the camera) ────────────
  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;

    final result = await Permission.camera.request();
    if (result.isGranted) return true;

    if (result.isPermanentlyDenied) {
      _onFailure('Camera access denied.\nEnable it in Settings to continue.');
    } else {
      _onFailure('Camera permission is required\nfor facial recognition.');
    }
    return false;
  }

  // ── Camera init ───────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (kIsWeb) return; // web has no camera stream path here — see _startScan
    try {
      final granted = await _ensureCameraPermission();
      if (!granted) return;

=======
  // ── Camera init ────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      if (!mounted) return;
<<<<<<< HEAD
      setState(() {
        _camCtrl = ctrl;
        _camReady = true;
      });
=======
      setState(() { _camCtrl = ctrl; _camReady = true; });
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    } catch (e) {
      if (mounted) _onFailure('Camera unavailable. Try again.');
    }
  }

<<<<<<< HEAD
  // ── Start live scan ───────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (!mounted || _isScanning) return;

    if (kIsWeb) {
      setState(() { _faceState = _FaceState.scanning; _errorMessage = null; });
      await Future.delayed(const Duration(milliseconds: 900));
      await _onSuccess();
      return;
    }

    _isScanning = true;
=======
  // ── Start live scan ────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    if (!mounted || _isScanning) return;
    _isScanning    = true;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _faceFirstSeen = null;
    _detectedFaceCount = 0;
    _sharpnessBuffer.clear();

    setState(() {
<<<<<<< HEAD
      _faceState = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!_camReady || !mounted) {
      _isScanning = false;
      return;
    }

    await _camCtrl!.startImageStream(_onCameraImage);
  }

=======
      _faceState   = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning  = _FaceWarning.none;
    });

    if (!_camReady) await _initCamera();
    if (!_camReady || !mounted) { _isScanning = false; return; }

    _scanLineCtrl.repeat(reverse: true);
    await _camCtrl!.startImageStream(_onCameraImage);
  }

  /// Called for every camera frame while scanning.
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Future<void> _onCameraImage(CameraImage image) async {
    if (!_isScanning || _isProcessing || !mounted) return;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(image);
<<<<<<< HEAD
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (!mounted || !_isScanning) {
        _isProcessing = false;
        return;
      }

      if (faces.isNotEmpty) {
        final face = faces.first;
        final quality = _assessFaceQuality(face, image);

        if (quality != _FaceWarning.none) {
          _faceFirstSeen = null;
          if (mounted) {
            setState(() {
              _detectedFaceCount = 0;
              _faceWarning = quality;
            });
          }
=======
      if (inputImage == null) { _isProcessing = false; return; }

      final faces = await _faceDetector.processImage(inputImage);

      if (!mounted || !_isScanning) { _isProcessing = false; return; }

      if (faces.isNotEmpty) {
        final face = faces.first; // analyse the most prominent face

        // ── Quality gate ──────────────────────────────────────────────
        final quality = _assessFaceQuality(face, image);

        if (quality != _FaceWarning.none) {
          // Face detected but quality is unacceptable — reset hold timer
          _faceFirstSeen = null;
          if (mounted) setState(() {
            _detectedFaceCount = 0;
            _faceWarning = quality;
          });
          _warningCtrl.repeat(reverse: true);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          _isProcessing = false;
          return;
        }

<<<<<<< HEAD
=======
        // Quality OK — stop warning animation
        _warningCtrl.stop();
        _warningCtrl.reset();

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        final now = DateTime.now();
        _faceFirstSeen ??= now;
        final held = now.difference(_faceFirstSeen!);

<<<<<<< HEAD
        if (mounted) {
          setState(() {
            _detectedFaceCount = faces.length;
            _faceWarning = _FaceWarning.none;
          });
        }
=======
        if (mounted) setState(() {
          _detectedFaceCount = faces.length;
          _faceWarning = _FaceWarning.none;
        });
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

        if (held >= _holdDuration) {
          await _camCtrl!.stopImageStream();
          _isScanning = false;
<<<<<<< HEAD
=======
          _scanLineCtrl.stop();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          await _onSuccess();
        }
      } else {
        _faceFirstSeen = null;
<<<<<<< HEAD
        if (mounted) {
          setState(() {
            _detectedFaceCount = 0;
            _faceWarning = _FaceWarning.none;
          });
        }
      }
    } catch (_) {
      // Swallow per-frame errors so the stream keeps running.
=======
        _warningCtrl.stop();
        _warningCtrl.reset();
        if (mounted) setState(() {
          _detectedFaceCount = 0;
          _faceWarning = _FaceWarning.none;
        });
      }
    } catch (_) {
      // Swallow per-frame errors
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    }

    _isProcessing = false;
  }

<<<<<<< HEAD
  _FaceWarning _assessFaceQuality(Face face, CameraImage image) {
=======
  // ── Face quality assessment (FULLY FIXED) ───────────────────────────────────────────
  /// Returns the worst quality issue found, or [_FaceWarning.none] if clear.
  _FaceWarning _assessFaceQuality(Face face, CameraImage image) {

    // 1. HEAD POSE — access via .headPose object
    // Note: ML Kit 0.11+ moved angles to .headPose and renamed them (pitch/yaw/roll)
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    final headY = face.headEulerAngleY ?? 0.0;
    final headZ = face.headEulerAngleZ ?? 0.0;
    if (headY.abs() > _maxHeadTiltDeg || headZ.abs() > _maxHeadTiltDeg) {
      return _FaceWarning.headAngle;
    }

<<<<<<< HEAD
=======
    // 2. EYE OPENNESS
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    final leftEyeProb = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeProb = face.rightEyeOpenProbability ?? 1.0;
    if (leftEyeProb < _minEyeOpenProb && rightEyeProb < _minEyeOpenProb) {
      return _FaceWarning.eyesClosed;
    }

<<<<<<< HEAD
    final hasNose = face.landmarks[FaceLandmarkType.noseBase] != null;
    final hasMouthL = face.landmarks[FaceLandmarkType.leftMouth] != null;
    final hasMouthR = face.landmarks[FaceLandmarkType.rightMouth] != null;
    final hasBothEyes = face.landmarks[FaceLandmarkType.leftEye] != null &&
        face.landmarks[FaceLandmarkType.rightEye] != null;

    if (!hasNose && (!hasMouthL || !hasMouthR)) {
      return _FaceWarning.faceMask;
    }
    if (!hasBothEyes && (!hasNose || (!hasMouthL && !hasMouthR))) {
      return _FaceWarning.occluded;
    }

=======
    // 3. LANDMARK PRESENCE — access via .landmarks MAP
    final hasNose  = face.landmarks[FaceLandmarkType.noseBase] != null;
    final hasMouthL = face.landmarks[FaceLandmarkType.leftMouth] != null;
    final hasMouthR = face.landmarks[FaceLandmarkType.rightMouth] != null;
    final hasBothEyes = face.landmarks[FaceLandmarkType.leftEye] != null
        && face.landmarks[FaceLandmarkType.rightEye] != null;

    if (!hasNose && (!hasMouthL || !hasMouthR)) {
      // Nose and mouth both missing → almost certainly a face mask
      return _FaceWarning.faceMask;
    }

    if (!hasBothEyes && (!hasNose || (!hasMouthL && !hasMouthR))) {
      // Multiple landmarks absent → partial occlusion / heavy blur
      return _FaceWarning.occluded;
    }

    // 4. SHARPNESS ESTIMATION
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    final sharpness = _estimateSharpness(image);
    _sharpnessBuffer.add(sharpness);
    if (_sharpnessBuffer.length > _sharpnessWindow) {
      _sharpnessBuffer.removeAt(0);
    }
<<<<<<< HEAD
    if (_sharpnessBuffer.length == _sharpnessWindow) {
      final avgSharpness = _sharpnessBuffer.reduce((a, b) => a + b) / _sharpnessBuffer.length;
=======

    if (_sharpnessBuffer.length == _sharpnessWindow) {
      final avgSharpness = _sharpnessBuffer.reduce((a, b) => a + b)
          / _sharpnessBuffer.length;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      if (avgSharpness < _sharpnessThreshold) {
        return _FaceWarning.blurry;
      }
    }

    return _FaceWarning.none;
  }

<<<<<<< HEAD
  double _estimateSharpness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes;
      final w = image.width;
      final h = image.height;

      const step = 8;
      const count = 32;
=======
  /// Estimates image sharpness using variance of a sampled grid of Y-plane pixels.
  /// Returns a value roughly in [0, 1]; higher = sharper.
  double _estimateSharpness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes; // Y plane for NV21/YUV
      final w = image.width;
      final h = image.height;

      // Sample every 8th pixel in a 32×32 grid centred on the frame
      const step   = 8;
      const count  = 32;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
          sum += v;
=======
          sum   += v;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          sumSq += v * v;
          n++;
        }
      }

<<<<<<< HEAD
      if (n < 2) return 1.0;
      final mean = sum / n;
      final variance = (sumSq / n) - (mean * mean);
      return (variance / 16256.0).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0;
    }
  }

=======
      if (n < 2) return 1.0; // can't compute — assume sharp
      final mean = sum / n;
      final variance = (sumSq / n) - (mean * mean);
      // Normalise: full-contrast image has variance ≈ 255²/4 ≈ 16256
      return (variance / 16256.0).clamp(0.0, 1.0);
    } catch (_) {
      return 1.0; // on error assume sharp
    }
  }

  // ── Input image builder ────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  InputImage? _buildInputImage(CameraImage image) {
    if (_camCtrl == null) return null;
    final sensorOrientation = _camCtrl!.description.sensorOrientation;
    InputImageRotation rotation;
    switch (sensorOrientation) {
<<<<<<< HEAD
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
=======
      case 90:  rotation = InputImageRotation.rotation90deg;  break;
      case 180: rotation = InputImageRotation.rotation180deg; break;
      case 270: rotation = InputImageRotation.rotation270deg; break;
      default:  rotation = InputImageRotation.rotation0deg;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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

<<<<<<< HEAD
=======
  // ── Success / failure handlers ─────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() { _faceState = _FaceState.success; _errorMessage = null; });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type'         : 'facial_recognition_verified',
        'employeeId'   : widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email'        : widget.employee.email,
        'timestamp'    : FieldValue.serverTimestamp(),
        'device'       : kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (_) {}

<<<<<<< HEAD
    await Future.delayed(const Duration(milliseconds: 1400));
=======
    await Future.delayed(const Duration(milliseconds: 1600));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClockInSuccessScreen(
          employee: widget.employee,
          onContinue: () {
            Navigator.of(context).pushAndRemoveUntil(
<<<<<<< HEAD
              MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)),
=======
              MaterialPageRoute(
                builder: (_) => MainScreen(employee: widget.employee),
              ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
=======
    _scanLineCtrl.stop();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    setState(() { _faceState = _FaceState.error; _errorMessage = msg; });
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() { _faceState = _FaceState.idle; _errorMessage = null; });
    });
  }

  void _goBack() => Navigator.of(context).pop();

  void _onCancelTapped() async {
    setState(() { _cancelPressed = true; });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() { _cancelPressed = false; });
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

<<<<<<< HEAD
  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: 0.55,
              child: _buildDimmedBackground(),
            ),
            Container(color: _scrim),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildModalCard(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimmedBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_bgTop, _bgMid, _bgBottom],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_headerStart, _headerEnd],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(
                    onTap: _goBack,
                    child: Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.chevron_left_rounded, color: _white, size: 22),
                      SizedBox(width: 4),
                      Text('Back', style: TextStyle(
                          color: _white, fontSize: 16, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  const Text('Auth & Clock In', style: TextStyle(
                      color: _white, fontSize: 28,
                      fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  const Text('Select your initial verification method',
                      style: TextStyle(color: _white, fontSize: 14)),
                ]),
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
                  color: _white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(children: [
                  const Text('Step 1: Initial Login',
                      style: TextStyle(color: _textDark, fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: _dimmedOptionPlaceholder(Icons.contactless_rounded, 'Key Fob')),
                    const SizedBox(width: 12),
                    Expanded(child: _dimmedOptionPlaceholder(Icons.key_rounded, 'Use PIN')),
                  ]),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dimmedOptionPlaceholder(IconData icon, String label) {
    return AspectRatio(
      aspectRatio: 0.95,
      child: Container(
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder, width: 1.5),
            ),
            child: Icon(icon, color: _orange, size: 24),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(
              color: _textDark, fontSize: 13, fontWeight: FontWeight.w700)),
=======
  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ]),
      ),
    );
  }

<<<<<<< HEAD
  Widget _buildModalCard() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 338),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
=======
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B00), Color(0xFFFF9500), Color(0xFFFFAA00)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _goBack,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left_rounded, color: _white, size: 22),
                const SizedBox(width: 2),
                Text('Back', style: TextStyle(
                    color: _white.withOpacity(0.9),
                    fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 14),
            const Text('Auth & Clock In',
                style: TextStyle(color: _white, fontSize: 30,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text('Select your initial verification method',
                style: TextStyle(color: _white.withOpacity(0.8), fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(children: [
        _buildOuterCard(),
        const SizedBox(height: 16),
        if (_faceState == _FaceState.idle || _faceState == _FaceState.error)
          _buildCancelButton(),
        const SizedBox(height: 12),
        Text('Account creation is restricted to Admin.',
            style: TextStyle(color: _white40, fontSize: 11)),
      ]),
    );
  }

  Widget _buildOuterCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F1F1F), width: 1),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
          child: Text('Step 1: Initial Login',
              style: TextStyle(color: _white50, fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 12),
        _buildInnerCard(),
      ]),
    );
  }

  Widget _buildInnerCard() {
    return Container(
      width: double.infinity,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
<<<<<<< HEAD
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _modalBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildIcon(),
        const SizedBox(height: 24),

=======
          colors: [Color(0xFFFF8C00), Color(0xFFCC3300)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 36),
      child: Column(children: [
        _faceState == _FaceState.scanning && _camReady
            ? _buildCameraPreview()
            : _buildFaceIcon(),
        const SizedBox(height: 28),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_stateTitle,
              key: ValueKey(_faceState),
              textAlign: TextAlign.center,
<<<<<<< HEAD
              style: const TextStyle(color: _white, fontSize: 30,
                  fontWeight: FontWeight.w500, height: 1.1)),
        ),
        const SizedBox(height: 12),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey(_errorMessage ?? 'sub_${_faceState}_$_faceWarning'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white70, fontSize: 14, height: 1.4)),
        ),
        const SizedBox(height: 28),

        if (_faceState == _FaceState.idle || _faceState == _FaceState.error)
          _buildCancelButton(),
=======
              style: const TextStyle(color: _white, fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey(_errorMessage ?? 'sub_$_faceState'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _white.withOpacity(0.75),
                  fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 28),
        if (_faceState == _FaceState.idle || _faceState == _FaceState.error)
          GestureDetector(
            onTap: _startScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _white.withOpacity(0.22), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.face_retouching_natural_rounded,
                    color: _white, size: 20),
                const SizedBox(width: 8),
                const Text('Tap to Scan',
                    style: TextStyle(color: _white, fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        const SizedBox(height: 4),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ]),
    );
  }

<<<<<<< HEAD
  Widget _buildIcon() {
    Color iconColor;
    switch (_faceState) {
      case _FaceState.success: iconColor = _success; break;
      case _FaceState.error:   iconColor = _error;   break;
      default:                 iconColor = _modalGradTop;
    }

    final showLiveCamera = _faceState == _FaceState.scanning && _camReady && !kIsWeb;

    // The mock's icon box is 112x112, but a real live camera preview needs
    // much more room to be usable — so only while actively scanning, the
    // box fills the full width of the card. Idle/success/error stay at the
    // original 112x112 to match the static mock exactly.
    const boxSize = 112.0;
    const liveCameraHeight = 320.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _ringAnim, _successAnim, _shakeAnim]),
      builder: (_, __) {
        final shakeX = _faceState == _FaceState.error
            ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        final iconBox = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: showLiveCamera ? double.infinity : boxSize,
          height: showLiveCamera ? liveCameraHeight : boxSize,
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(showLiveCamera ? 20 : 16),
            border: _faceState == _FaceState.success
                ? Border.all(color: _successRing, width: 3)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 12, offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: showLiveCamera
              ? _buildLiveCameraFill()
              : (_faceState == _FaceState.success
              ? Icon(Icons.verified_user_rounded, color: iconColor, size: 46)
              : Center(
            child: CustomPaint(
              size: const Size(48, 48),
              painter: _FaceScanIconPainter(color: iconColor),
            ),
          )),
        );

        // Full-width live camera: no circular pulse/ring around it (those
        // only make sense around the small square icon), just the box.
        if (showLiveCamera) {
          return SizedBox(width: double.infinity, child: iconBox);
        }

        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: GestureDetector(
            onTap: (_faceState == _FaceState.idle || _faceState == _FaceState.error)
                ? _startScan
                : null,
            child: Stack(alignment: Alignment.center, children: [
              if (_faceState == _FaceState.scanning)
                Transform.rotate(
                  angle: _ringAnim.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(132, 132),
                    painter: _DashRingPainter(
                        color: _white.withOpacity(0.5), dashCount: 14),
                  ),
                ),

              if (_faceState != _FaceState.success)
                Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: boxSize, height: boxSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.15),
                    ),
                  ),
                ),

              iconBox,
            ]),
          ),
=======
  // ── Live camera preview with ML Kit overlays ───────────────────────────────
  Widget _buildCameraPreview() {
    final faceDetected = _detectedFaceCount > 0;
    final hasWarning   = _faceWarning != _FaceWarning.none;
    final borderColor  = hasWarning
        ? _warning
        : faceDetected
        ? _faceGreen
        : _orange;

    return AnimatedBuilder(
      animation: Listenable.merge([_ringAnim, _scanLineAnim, _warningAnim]),
      builder: (_, __) {
        final glowOpacity = faceDetected
            ? 0.6 + 0.35 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi))
            : 0.3 + 0.30 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi));

        double holdProgress = 0.0;
        if (faceDetected && !hasWarning && _faceFirstSeen != null) {
          holdProgress = (DateTime.now().difference(_faceFirstSeen!).inMilliseconds /
              _holdDuration.inMilliseconds).clamp(0.0, 1.0);
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // Camera feed
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: CameraPreview(_camCtrl!),
              ),
            ),

            // Scan line
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: Align(
                  alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        borderColor.withOpacity(0.95),
                        borderColor,
                        borderColor.withOpacity(0.95),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
            ),

            // Scan line glow trail
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: double.infinity,
                height: 320,
                child: Align(
                  alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          borderColor.withOpacity(0.08),
                          borderColor.withOpacity(0.14),
                          borderColor.withOpacity(0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Corner brackets
            SizedBox(
              width: double.infinity,
              height: 320,
              child: CustomPaint(
                painter: _FaceBracketPainter(color: borderColor),
              ),
            ),

            // Hold-progress arc
            if (faceDetected && !hasWarning && holdProgress > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _HoldProgressPainter(
                      progress: holdProgress,
                      color: _faceGreen,
                    ),
                  ),
                ),
              ),

            // Animated glowing border
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: borderColor.withOpacity(
                          hasWarning
                              ? _warningAnim.value   // pulse amber
                              : glowOpacity),
                      width: faceDetected ? 2.5 : 2,
                    ),
                  ),
                ),
              ),
            ),

            // Top-right status badge
            Positioned(
              top: 12,
              right: 12,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: borderColor.withOpacity(0.7), width: 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      color: borderColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: borderColor.withOpacity(0.8), blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusBadgeText,
                    style: const TextStyle(
                        color: _white, fontSize: 10,
                        fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                ]),
              ),
            ),

            // Quality warning banner
            if (hasWarning)
              Positioned(
                bottom: 14,
                child: AnimatedBuilder(
                  animation: _warningAnim,
                  builder: (_, __) => Opacity(
                    opacity: _warningAnim.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _warning.withOpacity(0.7), width: 1.2),
                        boxShadow: [
                          BoxShadow(color: _warning.withOpacity(0.2),
                              blurRadius: 10, spreadRadius: 1),
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: _warning, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          _warningHintText,
                          style: const TextStyle(
                              color: _warning, fontSize: 11,
                              fontWeight: FontWeight.w700, letterSpacing: 0.3),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),

            // "Hold still" hint when clear face detected
            if (faceDetected && !hasWarning)
              Positioned(
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _faceGreen.withOpacity(0.4), width: 1),
                  ),
                  child: Text(
                    'Hold still — verifying...',
                    style: TextStyle(
                        color: _faceGreen, fontSize: 11,
                        fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),

            // "No face found" hint
            if (!faceDetected && !hasWarning)
              Positioned(
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Center your face in the frame',
                    style: TextStyle(
                        color: _white.withOpacity(0.7), fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        );
      },
    );
  }

<<<<<<< HEAD
  /// Live, mirrored camera feed filling the 112x112 icon box while scanning,
  /// with a thin colored ring reflecting face-detection status (green =
  /// good, amber = quality warning, orange = searching). Kept inside the
  /// same box footprint as the static mock so the overall card layout
  /// doesn't shift between states.
  Widget _buildLiveCameraFill() {
    final hasWarning = _faceWarning != _FaceWarning.none;
    final faceDetected = _detectedFaceCount > 0;
    final ringColor = hasWarning ? _warning : (faceDetected ? _faceGreen : _orange);

    return Stack(
      fit: StackFit.expand,
      children: [
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(math.pi),
          child: CameraPreview(_camCtrl!),
        ),
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: ringColor, width: 3),
            ),
          ),
        ),
      ],
=======
  // ── Face icon (idle / success / error) ────────────────────────────────────
  Widget _buildFaceIcon() {
    Color borderColor;
    switch (_faceState) {
      case _FaceState.success: borderColor = _success; break;
      case _FaceState.error:   borderColor = _error;   break;
      default:                 borderColor = _orange;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _successAnim, _shakeAnim]),
      builder: (_, __) {
        final shakeX = _faceState == _FaceState.error
            ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
          child: Stack(alignment: Alignment.center, children: [
            if (_faceState == _FaceState.success)
              Transform.scale(
                scale: _successAnim.value * 1.25,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _success.withOpacity(
                            (1 - _successAnim.value).clamp(0.0, 1.0)),
                        width: 2),
                  ),
                ),
              ),
            if (_faceState != _FaceState.success)
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.15),
                    border: Border.all(color: _white.withOpacity(0.12), width: 1),
                  ),
                ),
              ),
            Container(
              width: 92, height: 92,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                    color: borderColor.withOpacity(
                        _faceState == _FaceState.success ? 0.9 : 0.4),
                    width: _faceState == _FaceState.success ? 2 : 1.5),
                boxShadow: [
                  BoxShadow(color: borderColor.withOpacity(0.25),
                      blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: _faceState == _FaceState.success
                  ? Transform.scale(
                  scale: _successAnim.value,
                  child: const Icon(Icons.person_rounded, color: _success, size: 48))
                  : Icon(Icons.face_retouching_natural_rounded,
                  color: _faceState == _FaceState.error ? _error : _orange,
                  size: 48),
            ),
            if (_faceState == _FaceState.success)
              Transform.scale(
                scale: _successAnim.value,
                child: Padding(
                  padding: const EdgeInsets.only(left: 52, top: 52),
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: _success,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Color(0xFF1A1A1A), size: 14),
                  ),
                ),
              ),
          ]),
        );
      },
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _onCancelTapped,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
<<<<<<< HEAD
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _cancelPressed ? const Color(0xFFF3F3F3) : _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cancelColor, width: 1.15),
        ),
        child: const Center(
          child: Text('Cancel Authentication',
              style: TextStyle(
                color: _cancelColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              )),
=======
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: _cancelPressed ? _white.withOpacity(0.20) : _white08,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _cancelPressed ? _white.withOpacity(0.55) : _white15,
            width: _cancelPressed ? 1.5 : 1,
          ),
          boxShadow: _cancelPressed
              ? [BoxShadow(color: _white.withOpacity(0.07),
              blurRadius: 12, spreadRadius: 2)]
              : [],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: _cancelPressed ? _white : _white70,
              fontSize: 15,
              fontWeight: _cancelPressed ? FontWeight.w800 : FontWeight.w600,
            ),
            child: const Text('Cancel Authentication'),
          ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ),
    );
  }

<<<<<<< HEAD
  String get _stateTitle {
    switch (_faceState) {
      case _FaceState.idle:     return 'Facial Recognition';
      case _FaceState.scanning: return 'Scanning\nFace...';
      case _FaceState.success:  return 'Details\nVerified';
      case _FaceState.error:    return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_faceState) {
      case _FaceState.idle:
        return 'Tap the camera icon to start facial scan';
      case _FaceState.scanning:
        return _faceWarning != _FaceWarning.none
            ? _warningHintText
            : 'Verifying facial structure & depth...';
      case _FaceState.success:
        return 'Identity confirmed: Employee. Proceeding...';
      case _FaceState.error:
        return 'Face not recognized.\nTap to try again.';
    }
  }

=======
  // ── Dynamic badge text ────────────────────────────────────────────────
  String get _statusBadgeText {
    switch (_faceWarning) {
      case _FaceWarning.blurry:    return 'BLURRY IMAGE';
      case _FaceWarning.faceMask:  return 'MASK DETECTED';
      case _FaceWarning.occluded:  return 'FACE BLOCKED';
      case _FaceWarning.headAngle: return 'ANGLE TOO STEEP';
      case _FaceWarning.eyesClosed: return 'EYES CLOSED';
      case _FaceWarning.none:
        return _detectedFaceCount > 0 ? 'FACE DETECTED' : 'SCANNING';
    }
  }

  // ── Warning hint texts ────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  String get _warningHintText {
    switch (_faceWarning) {
      case _FaceWarning.blurry:     return 'Hold still — image too blurry';
      case _FaceWarning.faceMask:   return 'Remove face mask to continue';
      case _FaceWarning.occluded:   return 'Remove obstructions from your face';
      case _FaceWarning.headAngle:  return 'Face the camera directly';
      case _FaceWarning.eyesClosed: return 'Please open your eyes';
      case _FaceWarning.none:       return '';
    }
  }
<<<<<<< HEAD
}

enum _FaceState { idle, scanning, success, error }

enum _FaceWarning { none, blurry, faceMask, occluded, headAngle, eyesClosed }

/// Recreates the mock's inline "face scan" icon (viewBox 0 0 24 24, scaled):
/// four rounded corner brackets, two eye dots, and a smile curve.
/// Used for BOTH the idle and (fallback, non-live) scanning icon, exactly
/// as it appears in the idle and scanning HTML mocks.
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
      strokePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(p(17, 3).dx, p(17, 3).dy)
        ..lineTo(p(19, 3).dx, p(19, 3).dy)
        ..arcToPoint(p(21, 5), radius: Radius.circular(2 * s), clockwise: true)
        ..lineTo(p(21, 7).dx, p(21, 7).dy),
      strokePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(p(21, 17).dx, p(21, 17).dy)
        ..lineTo(p(21, 19).dx, p(21, 19).dy)
        ..arcToPoint(p(19, 21), radius: Radius.circular(2 * s), clockwise: true)
        ..lineTo(p(17, 21).dx, p(17, 21).dy),
      strokePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(p(7, 21).dx, p(7, 21).dy)
        ..lineTo(p(5, 21).dx, p(5, 21).dy)
        ..arcToPoint(p(3, 19), radius: Radius.circular(2 * s), clockwise: true)
        ..lineTo(p(3, 17).dx, p(3, 17).dy),
      strokePaint,
    );

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(p(9, 9), 1.1 * s, dotPaint);
    canvas.drawCircle(p(15, 9), 1.1 * s, dotPaint);

    canvas.drawPath(
      Path()
        ..moveTo(p(9, 13).dx, p(9, 13).dy)
        ..cubicTo(
          p(9.5, 13.8).dx, p(9.5, 13.8).dy,
          p(10.5, 14.5).dx, p(10.5, 14.5).dy,
          p(12, 14.5).dx, p(12, 14.5).dy,
        )
        ..cubicTo(
          p(13.5, 14.5).dx, p(13.5, 14.5).dy,
          p(14.5, 13.8).dx, p(14.5, 13.8).dy,
          p(15, 13).dx, p(15, 13).dy,
        ),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(_FaceScanIconPainter old) => old.color != color;
}

class _DashRingPainter extends CustomPainter {
  final Color color;
  final int   dashCount;
  const _DashRingPainter({required this.color, this.dashCount = 16});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - 2;
    final center = Offset(size.width / 2, size.height / 2);
    final paint  = Paint()
      ..color      = color
      ..strokeWidth = 2
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    final dashAngle   = (2 * math.pi) / dashCount;
    const gapFraction = 0.35;

    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * dashAngle,
        dashAngle * (1 - gapFraction),
        false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashRingPainter old) => old.color != color;
=======

  // ── State helpers ──────────────────────────────────────────────────────────
  String get _stateTitle {
    switch (_faceState) {
      case _FaceState.idle:     return 'Facial\nRecognition';
      case _FaceState.scanning: return _detectedFaceCount > 0
          ? (_faceWarning != _FaceWarning.none ? 'Quality\nCheck Failed' : 'Face\nDetected!')
          : 'Scanning\nFace...';
      case _FaceState.success:  return 'Details\nVerified';
      case _FaceState.error:    return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_faceState) {
      case _FaceState.idle:     return 'Tap the camera icon to start\nfacial scan';
      case _FaceState.scanning: return _detectedFaceCount > 0
          ? (_faceWarning != _FaceWarning.none
          ? _warningHintText
          : 'Keep your face centered\nand hold still...')
          : 'Verifying facial structure & depth...';
      case _FaceState.success:  return 'Identity confirmed: Employee.\nProceeding...';
      case _FaceState.error:    return 'Face not recognized.\nTap to try again.';
    }
  }
}

// ── Enums ─────────────────────────────────────────────────────────────────────
enum _FaceState   { idle, scanning, success, error }

// individual quality failure reasons
enum _FaceWarning { none, blurry, faceMask, occluded, headAngle, eyesClosed }

// ── Corner bracket overlay painter ────────────────────────────────────────────
class _FaceBracketPainter extends CustomPainter {
  final Color color;
  const _FaceBracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color      = color
      ..strokeWidth = 3.5
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    const len    = 28.0;
    const margin = 10.0;
    const r      = 14.0;

    // top-left
    canvas.drawLine(Offset(margin + r, margin), Offset(margin + r + len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(margin, margin, r * 2, r * 2), math.pi, math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, margin + r), Offset(margin, margin + r + len), paint);

    // top-right
    final xr = size.width - margin;
    canvas.drawLine(Offset(xr - r, margin), Offset(xr - r - len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2), -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(xr, margin + r), Offset(xr, margin + r + len), paint);

    // bottom-left
    final yb = size.height - margin;
    canvas.drawLine(Offset(margin + r, yb), Offset(margin + r + len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2), math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, yb - r), Offset(margin, yb - r - len), paint);

    // bottom-right
    canvas.drawLine(Offset(xr - r, yb), Offset(xr - r - len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, yb - r * 2, r * 2, r * 2), 0, math.pi / 2, false, paint);
    canvas.drawLine(Offset(xr, yb - r), Offset(xr, yb - r - len), paint);
  }

  @override
  bool shouldRepaint(_FaceBracketPainter old) => old.color != color;
}

// ── Hold-progress arc painter ─────────────────────────────────────────────────
class _HoldProgressPainter extends CustomPainter {
  final double progress;
  final Color  color;
  const _HoldProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color      = color.withOpacity(0.85)
      ..strokeWidth = 4
      ..style      = PaintingStyle.stroke
      ..strokeCap  = StrokeCap.round;

    const inset = 4.0;
    final rect  = Rect.fromLTWH(inset, inset,
        size.width - inset * 2, size.height - inset * 2);
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(_HoldProgressPainter old) =>
      old.progress != progress || old.color != color;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}