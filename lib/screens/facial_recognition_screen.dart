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
import 'main_screen.dart';
import 'clock_in_success_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF7F7F7);
  Color get outerCardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFECEBE8);
  Color get stepLabelColor =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF8A8A85);
  Color get iconBoxBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFFFFFFF);
  Color get cancelBg => isDark ? const Color(0xFF27272A) : const Color(0xFFFFFFFF);
  Color get cancelPressed => isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFF4EE);
  Color get cancelText => const Color(0xFFF05000);
}

class FacialRecognitionScreen extends StatefulWidget {
  final Employee employee;
  const FacialRecognitionScreen({super.key, required this.employee});

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

  late final FaceDetector _faceDetector;

  bool _facePresent = false;

  bool _blinkDetected = false;
  bool _eyesWereClosed = false;
  int _closedFrames = 0;
  static const int _minClosedFrames = 2;
  static const double _blinkClosedThreshold = 0.3;
  static const double _blinkOpenThreshold = 0.6;
  static const int _maxClosedFramesBeforeStuck = 45;

  final List<double> _sharpnessBuffer = [];
  static const _sharpnessWindow = 6;
  static const _sharpnessThreshold = 0.18;
  static const _maxHeadTiltDeg = 30.0;
  static const _minFaceCoverage = 0.20;

  static const double _cameraBoxSize = 300.0;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;
  late AnimationController _scanLineCtrl;
  late AnimationController _warningCtrl;

  late Animation<double> _pulseAnim;
  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _shakeAnim;
  late Animation<double> _successAnim;
  late Animation<double> _scanLineAnim;
  late Animation<double> _warningAnim;

  static const _white = Color(0xFFFFFFFF);
  static const _orange = Color(0xFFF05000);
  static const _success = Color(0xFFCCFF00);
  static const _error = Color(0xFFFF3D00);
  static const _faceGreen = Color(0xFF00E676);
  static const _warning = Color(0xFFFFCC00);
  static const _verifiedGreen = Color(0xFF51FF00);

  @override
  void initState() {
    super.initState();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        minFaceSize: _minFaceCoverage,
      ),
    );

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scanLineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _warningCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
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
    _warningAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _warningCtrl, curve: Curves.easeInOut));

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();

    // ✅ WALANG AUTO-START — hintayin ang user mag-tap sa camera icon
    debugPrint('📷 Facial recognition screen ready — waiting for user tap');
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
    _camCtrl?.stopImageStream();
    _camCtrl?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<bool> _ensureCameraPermission() async {
    // ✅ Sa web, ipapaubaya sa browser ang permission prompt
    if (kIsWeb) return true;

    try {
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
    } catch (e) {
      debugPrint('⚠️ Permission check failed: $e');
      return false;
    }
  }

  Future<void> _initCamera() async {
    if (_camTried && _camReady) return;
    _camTried = true;
    try {
      final granted = await _ensureCameraPermission();
      if (!granted) return;
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('⚠️ No cameras available');
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
        // ✅ Web gumagamit ng JPEG; native NV21
        imageFormatGroup: kIsWeb
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _camCtrl = ctrl;
        _camReady = true;
      });
      debugPrint('✅ Camera initialized');
    } catch (e) {
      debugPrint('⚠️ Camera init failed: $e');
      if (!kIsWeb && mounted) {
        _onFailure('Camera unavailable. Try again.');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // START SCAN — WEB MOCK + NATIVE REAL
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _startScan() async {
    if (!mounted || _isScanning) return;
    _isScanning = true;
    _blinkDetected = false;
    _eyesWereClosed = false;
    _closedFrames = 0;
    _sharpnessBuffer.clear();
    _facePresent = false;

    setState(() {
      _faceState = _FaceState.scanning;
      _errorMessage = null;
      _faceWarning = _FaceWarning.none;
    });

    // ✅ WEB: subukang buksan ang camera + mock scan flow
    if (kIsWeb) {
      debugPrint('🌐 Web detected — trying real camera + mock scan');
      if (!_camReady) await _initCamera();
      _scanLineCtrl.repeat(reverse: true);
      await _runMockWebScan();
      return;
    }

    // ✅ NATIVE: Real camera + ML Kit
    if (!_camReady) await _initCamera();
    if (!_camReady || !mounted) {
      _isScanning = false;
      return;
    }

    _scanLineCtrl.repeat(reverse: true);
    await _camCtrl!.startImageStream(_onCameraImage);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // WEB MOCK SCAN FLOW
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _runMockWebScan() async {
    // Stage 1: Looking for face
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted || !_isScanning) return;
    setState(() => _facePresent = false);

    // Stage 2: Face detected
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted || !_isScanning) return;
    setState(() {
      _facePresent = true;
      _faceWarning = _FaceWarning.none;
    });

    // Stage 3: Simulate eyes starting to close
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted || !_isScanning) return;
    setState(() {
      _eyesWereClosed = true;
      _closedFrames = _minClosedFrames;
    });

    // Stage 4: Blink complete
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || !_isScanning) return;
    setState(() {
      _blinkDetected = true;
      _eyesWereClosed = false;
    });

    // Stage 5: Success
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _isScanning = false;
    _scanLineCtrl.stop();
    debugPrint('✅ Mock face scan complete');
    await _onSuccess();
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
              _blinkDetected = false;
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

        if (avgOpen < _blinkClosedThreshold) {
          _closedFrames++;
          _eyesWereClosed = true;

          if (_closedFrames > _maxClosedFramesBeforeStuck) {
            _eyesWereClosed = false;
            _closedFrames = 0;
            if (mounted) {
              setState(() {
                _faceWarning = _FaceWarning.eyesClosed;
                _blinkDetected = false;
              });
            }
            _warningCtrl.repeat(reverse: true);
            _isProcessing = false;
            return;
          }
        } else if (avgOpen > _blinkOpenThreshold &&
            _eyesWereClosed &&
            _closedFrames >= _minClosedFrames) {
          _blinkDetected = true;
          _eyesWereClosed = false;
          _closedFrames = 0;
          await _camCtrl!.stopImageStream();
          _isScanning = false;
          _scanLineCtrl.stop();
          await _onSuccess();
          _isProcessing = false;
          return;
        } else {
          if (_eyesWereClosed && _closedFrames < _minClosedFrames) {
            _eyesWereClosed = false;
            _closedFrames = 0;
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
            _blinkDetected = false;
          });
        }
      }
    } catch (_) {}

    _isProcessing = false;
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

    if (!hasNose && (!hasMouthL || !hasMouthR)) {
      return _FaceWarning.faceMask;
    }
    if (!hasBothEyes && (!hasNose || (!hasMouthL && !hasMouthR))) {
      return _FaceWarning.occluded;
    }

    final sharpness = _estimateSharpness(image);
    _sharpnessBuffer.add(sharpness);
    if (_sharpnessBuffer.length > _sharpnessWindow) {
      _sharpnessBuffer.removeAt(0);
    }
    if (_sharpnessBuffer.length == _sharpnessWindow) {
      final avgSharpness =
          _sharpnessBuffer.reduce((a, b) => a + b) / _sharpnessBuffer.length;
      if (avgSharpness < _sharpnessThreshold) {
        return _FaceWarning.blurry;
      }
    }

    return _FaceWarning.none;
  }

  double _estimateSharpness(CameraImage image) {
    try {
      final bytes = image.planes.first.bytes;
      final w = image.width;
      final h = image.height;

      const step = 8;
      const count = 32;
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

  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() {
      _faceState = _FaceState.success;
      _errorMessage = null;
    });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    try {
      await FirebaseFirestore.instance.collection('activity logs').add({
        'type': 'facial_recognition_verified_with_blink',
        'employeeId': widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email': widget.employee.email,
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (e) {
      debugPrint('⚠️ Log save failed: $e');
    }

    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClockInSuccessScreen(
          employee: widget.employee,
          onContinue: () {
            Navigator.of(context).pushAndRemoveUntil(
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

  void _goBack() => Navigator.of(context).pop();

  void _onCancelTapped() async {
    setState(() => _cancelPressed = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() => _cancelPressed = false);
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    Navigator.of(context).pop();
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
                  borderRadius: BorderRadius.circular(
                    screenWidth <= 420 ? 0 : 40,
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(color: tc.bg),
                        ),
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
          colors: [
            Color(0xFFFF8A00),
            Color(0xFFFF6B00),
            Color(0xFFF54900),
          ],
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
                    child: CustomPaint(
                      painter: _BackArrowPainter(),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    'Back',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 0.9,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: 24,
            top: 95.99,
            child: Text(
              'Auth & Clock In',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 0.9,
              ),
            ),
          ),
          const Positioned(
            left: 24,
            top: 136.99,
            child: Text(
              'Select your initial verification method',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
                color: Colors.white,
                height: 0.9,
              ),
            ),
          ),
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
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step 1: Initial Login',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: tc.stepLabelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _buildModalCard(tc),
        ],
      ),
    );
  }

  Widget _buildModalCard(_ThemeColors tc) {
    final isScanning =
        _faceState == _FaceState.scanning && (kIsWeb || _camReady);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF8C2B),
            Color(0xFFF05000),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF05000).withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
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
                onTap: (!isScanning && _faceState != _FaceState.success)
                    ? _startScan
                    : null,
                child: isScanning
                    ? _buildCameraPreview()
                    : (_faceState == _FaceState.success
                    ? _buildVerifiedBadge()
                    : _buildFaceIconBox(tc)),
              ),
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 16),
            _buildScanProgressBar(),
          ],
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _stateTitle.replaceAll('\n', ' '),
              key: ValueKey('title_$_faceState'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _errorMessage ?? _stateSubtitle.replaceAll('\n', ' '),
              key: ValueKey(
                'subtitle_${_errorMessage ?? _faceState.toString()}',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _white.withValues(alpha: 0.9),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildCancelButton(tc),
        ],
      ),
    );
  }

  Widget _buildFaceIconBox(_ThemeColors tc) {
    return SizedBox(
      width: 75,
      height: 75,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pulseAnim,
          _successAnim,
          _shakeAnim,
        ]),
        builder: (_, __) {
          final isSuccess = _faceState == _FaceState.success;
          final isError = _faceState == _FaceState.error;

          final shakeX = isError
              ? _shakeAnim.value *
              (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
              : 0.0;

          return Transform.translate(
            offset: Offset(shakeX, 0),
            child: Transform.scale(
              scale: isSuccess ? 1.0 : _pulseAnim.value,
              child: Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  color: isSuccess ? Colors.transparent : _white,
                  borderRadius: BorderRadius.circular(18),
                  border: isSuccess
                      ? Border.all(color: _success, width: 2.5)
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: isSuccess
                      ? Transform.scale(
                    scale: _successAnim.value,
                    child: const Icon(
                      Icons.how_to_reg_rounded,
                      color: _success,
                      size: 36,
                    ),
                  )
                      : CustomPaint(
                    size: const Size(36, 36),
                    painter: _FaceScanIconPainter(
                      color: isError ? _error : _orange,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerifiedBadge() {
    return AnimatedBuilder(
      animation: _successAnim,
      builder: (_, __) {
        return Transform.scale(
          scale: _successAnim.value,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CustomPaint(
              size: const Size(140, 140),
              painter: _VerifiedBadgePainter(color: _verifiedGreen),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CAMERA PREVIEW — REAL CAMERA (web + native) with mock fallback
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildCameraPreview() {
    final faceDetected = _facePresent;
    final hasWarning = _faceWarning != _FaceWarning.none;
    final borderColor =
    hasWarning ? _warning : (faceDetected ? _faceGreen : _orange);

    double blinkProgress = 0.0;
    if (faceDetected && !hasWarning && _eyesWereClosed) {
      blinkProgress = (_closedFrames / _minClosedFrames).clamp(0.0, 1.0);
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        _ringAnim,
        _scanLineAnim,
        _warningAnim,
      ]),
      builder: (_, __) {
        final glowOpacity = faceDetected
            ? 0.6 +
            0.35 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi))
            : 0.3 + 0.30 * (0.5 + 0.5 * math.sin(_ringAnim.value * 2 * math.pi));

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: _cameraBoxSize,
            height: _cameraBoxSize,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                // Priority: real camera preview kung available
                if (_camCtrl != null &&
                    _camCtrl!.value.isInitialized &&
                    _camCtrl!.value.previewSize != null)
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
                  _buildMockPreviewBackground(faceDetected)
                else
                  Container(color: Colors.black),

                // Scan line
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(0, (_scanLineAnim.value * 2) - 1),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            borderColor.withValues(alpha: 0.95),
                            borderColor,
                            borderColor.withValues(alpha: 0.95),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Face brackets
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FaceBracketPainter(color: borderColor),
                  ),
                ),

                // Hold progress ring
                if (faceDetected &&
                    !hasWarning &&
                    _eyesWereClosed &&
                    _closedFrames > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _HoldProgressPainter(
                          progress: blinkProgress,
                          color: _faceGreen,
                        ),
                      ),
                    ),
                  ),

                // Border glow
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor.withValues(
                            alpha: hasWarning
                                ? _warningAnim.value
                                : glowOpacity,
                          ),
                          width: faceDetected ? 2.5 : 2,
                        ),
                      ),
                    ),
                  ),
                ),

                // Status badge
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: borderColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _statusBadgeText,
                          style: const TextStyle(
                            color: _white,
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom hint
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: _warning, size: 11),
                              const SizedBox(width: 4),
                              Text(
                                _warningHintText,
                                style: const TextStyle(
                                  color: _warning,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                        _blinkDetected
                            ? 'Blink detected! ✓'
                            : 'Blink to verify',
                        style: TextStyle(
                          color: _blinkDetected ? _success : _faceGreen,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                      child: Text(
                        'Center your face',
                        style: TextStyle(
                          color: _white.withValues(alpha: 0.75),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Mock preview kung walang camera (web fallback)
  Widget _buildMockPreviewBackground(bool faceDetected) {
    return AnimatedBuilder(
      animation: _ringAnim,
      builder: (_, __) {
        final t = _ringAnim.value;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 0.9 + 0.1 * math.sin(t * 2 * math.pi),
              colors: [
                faceDetected
                    ? const Color(0xFF1B4332)
                    : const Color(0xFF2B1A0F),
                const Color(0xFF0A0A0A),
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 140,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: faceDetected
                      ? _faceGreen.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: faceDetected
                        ? _faceGreen.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 64,
                  color: faceDetected
                      ? _faceGreen.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCancelButton(_ThemeColors tc) {
    return GestureDetector(
      onTap: _onCancelTapped,
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
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: tc.cancelText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            child: const Text('Cancel Authentication'),
          ),
        ),
      ),
    );
  }

  double get _scanProgress {
    if (_blinkDetected) return 1.0;
    if (!_facePresent) return 0.0;
    if (_faceWarning != _FaceWarning.none) return 0.15;
    if (_eyesWereClosed && _closedFrames > 0) {
      final blinkFrac = (_closedFrames / _minClosedFrames).clamp(0.0, 1.0);
      return 0.55 + (0.40 * blinkFrac);
    }
    return 0.55;
  }

  Color get _scanProgressColor {
    if (_blinkDetected) return _success;
    if (_faceWarning != _FaceWarning.none) return _warning;
    if (_facePresent) return _faceGreen;
    return _white.withValues(alpha: 0.5);
  }

  String get _scanProgressLabel {
    if (_blinkDetected) return 'Verified';
    if (_faceWarning != _FaceWarning.none) return 'Fix issue';
    if (_facePresent) return 'Blink to finish';
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
            child: LayoutBuilder(
              builder: (context, constraints) {
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
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _scanProgressLabel,
            key: ValueKey('progress_label_$_scanProgressLabel'),
            style: TextStyle(
              color: _white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  int get _detectedFaceCount => _facePresent ? 1 : 0;

  String get _statusBadgeText {
    if (_blinkDetected) return 'BLINK ✓';
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
        return _detectedFaceCount > 0 ? 'FACE FOUND' : 'SCANNING';
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

  String get _stateTitle {
    switch (_faceState) {
      case _FaceState.idle:
        return 'Facial\nRecognition';
      case _FaceState.scanning:
        if (_blinkDetected) return 'Blink\nVerified!';
        if (_detectedFaceCount > 0) {
          return _faceWarning != _FaceWarning.none
              ? 'Quality\nCheck Failed'
              : 'Face\nDetected';
        }
        return 'Scanning\nFace...';
      case _FaceState.success:
        return 'Details\nVerified';
      case _FaceState.error:
        return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_faceState) {
      case _FaceState.idle:
        return 'Tap the camera icon to start\nfacial scan';
      case _FaceState.scanning:
        if (_blinkDetected) return 'Blink confirmed!\nProceeding...';
        if (_detectedFaceCount > 0) {
          if (_faceWarning != _FaceWarning.none) {
            return _warningHintText;
          } else {
            return 'Blink your eyes to verify\nliveness';
          }
        }
        return 'Verifying facial structure & depth...';
      case _FaceState.success:
        return 'Identity confirmed: Employee.\nProceeding...';
      case _FaceState.error:
        return 'Face not recognized.\nTap to try again.';
    }
  }
}

enum _FaceState { idle, scanning, success, error }

enum _FaceWarning { none, blurry, faceMask, occluded, headAngle, eyesClosed }

// ═══════════════════════════════════════════════════════════════════════════
// Painters
// ═══════════════════════════════════════════════════════════════════════════
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
      strokePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(17, 3).dx, p(17, 3).dy)
        ..lineTo(p(19, 3).dx, p(19, 3).dy)
        ..arcToPoint(p(21, 5),
            radius: Radius.circular(2 * s), clockwise: true)
        ..lineTo(p(21, 7).dx, p(21, 7).dy),
      strokePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(21, 17).dx, p(21, 17).dy)
        ..lineTo(p(21, 19).dx, p(21, 19).dy)
        ..arcToPoint(p(19, 21),
            radius: Radius.circular(2 * s), clockwise: true)
        ..lineTo(p(17, 21).dx, p(17, 21).dy),
      strokePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(p(7, 21).dx, p(7, 21).dy)
        ..lineTo(p(5, 21).dx, p(5, 21).dy)
        ..arcToPoint(p(3, 19),
            radius: Radius.circular(2 * s), clockwise: true)
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

    canvas.drawLine(Offset(margin + r, margin),
        Offset(margin + r + len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(margin, margin, r * 2, r * 2), math.pi,
        math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, margin + r),
        Offset(margin, margin + r + len), paint);

    final xr = size.width - margin;
    canvas.drawLine(Offset(xr - r, margin), Offset(xr - r - len, margin), paint);
    canvas.drawArc(Rect.fromLTWH(xr - r * 2, margin, r * 2, r * 2),
        -math.pi / 2, math.pi / 2, false, paint);
    canvas.drawLine(
        Offset(xr, margin + r), Offset(xr, margin + r + len), paint);

    final yb = size.height - margin;
    canvas.drawLine(Offset(margin + r, yb), Offset(margin + r + len, yb), paint);
    canvas.drawArc(Rect.fromLTWH(margin, yb - r * 2, r * 2, r * 2), math.pi / 2,
        math.pi / 2, false, paint);
    canvas.drawLine(Offset(margin, yb - r), Offset(margin, yb - r - len), paint);

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

    final frameRect = Rect.fromLTRB(
      p(1.5, 1.5).dx,
      p(1.5, 1.5).dy,
      p(110.496, 110.496).dx,
      p(110.496, 110.496).dy,
    );
    final rrect = RRect.fromRectAndRadius(frameRect, Radius.circular(14.5 * s));
    canvas.drawRRect(
        rrect, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * s,
    );

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(p(63.9885, 73.9877).dx, p(63.9885, 73.9877).dy)
        ..lineTo(p(63.9885, 69.9881).dx, p(63.9885, 69.9881).dy)
        ..cubicTo(
          p(63.9885, 67.8665).dx, p(63.9885, 67.8665).dy,
          p(63.1457, 65.8319).dx, p(63.1457, 65.8319).dy,
          p(61.6456, 64.3317).dx, p(61.6456, 64.3317).dy,
        )
        ..cubicTo(
          p(60.1454, 62.8316).dx, p(60.1454, 62.8316).dy,
          p(58.1108, 61.9888).dx, p(58.1108, 61.9888).dy,
          p(55.9892, 61.9888).dx, p(55.9892, 61.9888).dy,
        )
        ..lineTo(p(43.9903, 61.9888).dx, p(43.9903, 61.9888).dy)
        ..cubicTo(
          p(41.8687, 61.9888).dx, p(41.8687, 61.9888).dy,
          p(39.8341, 62.8316).dx, p(39.8341, 62.8316).dy,
          p(38.3339, 64.3317).dx, p(38.3339, 64.3317).dy,
        )
        ..cubicTo(
          p(36.8337, 65.8319).dx, p(36.8337, 65.8319).dy,
          p(35.991, 67.8665).dx, p(35.991, 67.8665).dy,
          p(35.991, 69.9881).dx, p(35.991, 69.9881).dy,
        )
        ..lineTo(p(35.991, 73.9877).dx, p(35.991, 73.9877).dy),
      strokePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(p(49.9895, 53.9893).dx, p(49.9895, 53.9893).dy)
        ..cubicTo(
          p(54.4074, 53.9893).dx, p(54.4074, 53.9893).dy,
          p(57.9888, 50.4079).dx, p(57.9888, 50.4079).dy,
          p(57.9888, 45.99).dx, p(57.9888, 45.99).dy,
        )
        ..cubicTo(
          p(57.9888, 41.5721).dx, p(57.9888, 41.5721).dy,
          p(54.4074, 37.9907).dx, p(54.4074, 37.9907).dy,
          p(49.9895, 37.9907).dx, p(49.9895, 37.9907).dy,
        )
        ..cubicTo(
          p(45.5716, 37.9907).dx, p(45.5716, 37.9907).dy,
          p(41.9902, 41.5721).dx, p(41.9902, 41.5721).dy,
          p(41.9902, 45.99).dx, p(41.9902, 45.99).dy,
        )
        ..cubicTo(
          p(41.9902, 50.4079).dx, p(41.9902, 50.4079).dy,
          p(45.5716, 53.9893).dx, p(45.5716, 53.9893).dy,
          p(49.9895, 53.9893).dx, p(49.9895, 53.9893).dy,
        )
        ..close(),
      strokePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(p(63.9885, 53.9894).dx, p(63.9885, 53.9894).dy)
        ..lineTo(p(67.9882, 57.989).dx, p(67.9882, 57.989).dy)
        ..lineTo(p(75.9875, 49.9897).dx, p(75.9875, 49.9897).dy),
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(_VerifiedBadgePainter old) => old.color != color;
}

class _HoldProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _HoldProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const inset = 4.0;
    final rect = Rect.fromLTWH(
        inset, inset, size.width - inset * 2, size.height - inset * 2);
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(_HoldProgressPainter old) =>
      old.progress != progress || old.color != color;
}