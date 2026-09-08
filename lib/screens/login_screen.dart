// lib/screens/login_screen.dart
//
// Authenticates employees by:
//   • NFC tap  → matches tag.data identifier against Firestore `nfcTagId` field
//   • 4-digit PIN → matches against Firestore `pin` field
//
// On successful auth → goes to FingerprintScreen (Step 2) before MainScreen.
<<<<<<< HEAD
//
// UI NOTE: "Enter PIN" and "Tap Key Fob" are now shown as a dark-scrim
// MODAL OVERLAY on top of the Select Method screen (matches the updated
// HTML mock), instead of replacing the whole screen content.
//
// HEADER UPDATE: gradient is now 3-stop (#FF8A00 → #FF6B00 @33% → #F54900),
// bottom corners now 16px radius (was 28px), and a thin bottom border
// (#382A20, 1.15px) was added — matches the latest "Auth & Clock In" HTML mock.
//
// NEW: added a "Client Meeting LogIn" option below the Key Fob / PIN row,
// converted from the latest dark-mode HTML mock but re-themed to match this
// screen's existing light mode (white card, orange outline/text — same
// treatment as the Cancel button on the modals).
//
// CLIENT MEETING MODAL: tapping "Client Meeting LogIn" opens a
// camera-capture modal, now using the orange gradient background to match
// PIN and NFC modals. A switch button is placed next to the shutter button
// to toggle between front and back cameras. The camera switch now properly
// disposes the old controller before initializing a new one, preventing
// "buildPreview() called on a disposed CameraController" errors.
//
// LOCATION: The hardcoded site name has been replaced with the actual
// GPS-derived location (reverse geocoded) of the employee. The place name
// is fetched when the client meeting modal opens and displayed as a
// watermark in the camera preview.
//
// ─────────────────────────────────────────────────────────────────────────
// SETUP REQUIRED for the new camera step to work:
//   1. Add to pubspec.yaml (already present):
//        camera: ^0.10.5+9
//        geolocator: ^13.0.2
//        geocoding: ^3.0.0   // <-- added this
//      then run `flutter pub get`.
//   2. Android — add to android/app/src/main/AndroidManifest.xml:
//        <uses-permission android:name="android.permission.CAMERA" />
//        <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
//        <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
//      and make sure minSdkVersion is at least 21.
//   3. iOS — add to ios/Runner/Info.plist:
//        <key>NSCameraUsageDescription</key>
//        <string>This app needs camera access for client meeting check-in.</string>
//        <key>NSLocationWhenInUseUsageDescription</key>
//        <string>We need your location to record where you check in.</string>
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';   // for Geolocator, Position, permissions
import 'package:geocoding/geocoding.dart';    // ✅ correct import for placemarkFromCoordinates, Placemark
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'fingerprint_screen.dart';
import 'landing_screen.dart';

// Login step enum
enum _LoginStep { selectMethod, pinEntry, nfcWait, clientMeeting }
=======

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'fingerprint_screen.dart'; // ← Step 2 screen
import 'landing_screen.dart';

// Login step enum
enum _LoginStep { selectMethod, pinEntry, nfcWait }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {

  String       _pinInput     = '';
  bool         _isLoading    = false;
  bool         _nfcAvailable = false;
  String?      _errorMessage;
  _LoginStep   _step         = _LoginStep.selectMethod;

<<<<<<< HEAD
  // ── Client Meeting (camera capture) state ──────────────────────────────
  CameraController? _cameraController;
  bool              _isCapturing    = false;
  bool              _captureSuccess = false;
  DateTime          _now         = DateTime.now();
  Timer?            _clockTimer;
  Timer?            _successCloseTimer;
  bool              _useFrontCamera = true;

  // Location state (replaces hardcoded site name)
  String _currentPlaceName = '';

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  late AnimationController _shakeController;
  late Animation<double>   _shakeAnim;
  late AnimationController _fadeController;
  late Animation<double>   _fadeAnim;
<<<<<<< HEAD
  late AnimationController _modalController;
  late Animation<double>   _modalScaleAnim;
  late Animation<double>   _modalOpacityAnim;
=======
  late AnimationController _slideController;
  late Animation<Offset>   _slideAnim;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  late AnimationController _nfcPulseController;
  late Animation<double>   _nfcPulseAnim;

  // ── Design tokens ──────────────────────────────────────────────────────────
<<<<<<< HEAD
  static const Color _bgTop        = Color(0xFFFFFFFF);
  static const Color _bgMid        = Color(0xFFFFF0E5);
  static const Color _bgBottom     = Color(0xFFFFE3D1);

  static const Color _headerStart  = Color(0xFFFF8A00);
  static const Color _headerMid    = Color(0xFFFF6B00);
  static const Color _headerEnd    = Color(0xFFF54900);
  static const Color _headerBorder = Color(0xFF382A20);

  static const Color _cardBg       = Color(0xFFFFFFFF);
  static const Color _cardBorder   = Color(0xFFFFEDD5);

  static const Color _optionBorder = Color(0xFFFDBA74);
  static const Color _hoverBg      = Color(0xFFFFF7ED);
  static const Color _orange       = Color(0xFFF97316);

  static const Color _textDark     = Color(0xFF1F2937);
  static const Color _textMuted    = Color(0xFF6B7280);

  static const Color _white        = Color(0xFFFFFFFF);
  static const Color _error        = Color(0xFFDC2626);
  static const Color _errorBg      = Color(0xFFFEE2E2);

  static const Color _modalGradTop = Color(0xFFFF8A00);
  static const Color _modalGradMid = Color(0xFFFA6A00);
  static const Color _modalGradEnd = Color(0xFFF54900);
  static const Color _scrim        = Color.fromRGBO(9, 9, 21, 0.44);

  static const Color _cmPreviewBg  = Color(0xFF20212A);
  static const Color _cmShutterOuter = Color(0xFFFFA500);
  static const Color _cmShutterInner = Color(0xFFFEE0AA);
  static const Color _cmShutterGlow  = Color(0xFFFF8C00);
=======
  static const Color _bg         = Color(0xFF0A0A0A);
  static const Color _card       = Color(0xFF1A1A1A);
  static const Color _cardBorder = Color(0xFF2A2A2A);
  static const Color _orange     = Color(0xFFFF8C00);
  static const Color _orangeLight= Color(0xFFFFAA33);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _white70    = Color(0xB3FFFFFF);
  static const Color _white40    = Color(0x66FFFFFF);
  static const Color _white15    = Color(0x26FFFFFF);
  static const Color _white08    = Color(0x14FFFFFF);
  static const Color _success    = Color(0xFF00E5A0);
  static const Color _error      = Color(0xFFFF4D6D);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  static const List<String> _notFoundCodes = [
    'user-not-found',
    'invalid-credential',
    'invalid-login-credentials',
    'INVALID_LOGIN_CREDENTIALS',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
<<<<<<< HEAD
    _modalController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
=======
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _nfcPulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));

    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
<<<<<<< HEAD
    _modalScaleAnim = Tween<double>(begin: 0.9, end: 1.0)
        .animate(CurvedAnimation(parent: _modalController, curve: Curves.easeOutBack));
    _modalOpacityAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _modalController, curve: Curves.easeOut));
=======
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _nfcPulseAnim = Tween<double>(begin: 0.9, end: 1.1)
        .animate(CurvedAnimation(parent: _nfcPulseController, curve: Curves.easeInOut));

    _nfcPulseController.repeat(reverse: true);
    _fadeController.forward();
<<<<<<< HEAD
=======
    _slideController.forward();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

    _checkCapabilities();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fadeController.dispose();
<<<<<<< HEAD
    _modalController.dispose();
    _nfcPulseController.dispose();
    _clockTimer?.cancel();
    _successCloseTimer?.cancel();
    _releaseCamera();
=======
    _slideController.dispose();
    _nfcPulseController.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    if (!kIsWeb) {
      try { NfcManager.instance.stopSession(); } catch (_) {}
    }
    super.dispose();
  }

  // ── NFC ────────────────────────────────────────────────────────────────────
  Future<void> _checkCapabilities() async {
    if (kIsWeb) return;
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (e) {
      debugPrint('NFC check error: $e');
    }
  }

  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      await NfcManager.instance.stopSession();
      NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_isLoading) return;
          final serial = _extractTagId(tag);
          if (serial == null) { _setError('Could not read keyfob ID.'); return; }

          if (mounted) setState(() { _isLoading = true; _errorMessage = null; });

          try {
            final employee = await _findEmployeeByNfc(serial);
            if (employee != null) {
              await NfcManager.instance.stopSession();
              await _openSession(employee);
            } else {
              await NfcManager.instance.stopSession();
              _setError('Keyfob not registered. Contact your Admin.');
            }
          } catch (e) {
            _setError('NFC login error: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
    }
  }

  Future<Employee?> _findEmployeeByNfc(String serial) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('nfcTagId', isEqualTo: serial)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return _docToEmployee(snap.docs.first);
    } catch (e) {
      debugPrint('_findEmployeeByNfc error: $e');
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
      final id = tryKey('nfca') ?? tryKey('nfcb') ?? tryKey('nfcf') ??
          tryKey('nfcv') ?? tryKey('isodep') ??
          tryKey('mifare-classic') ?? tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ── PIN login ──────────────────────────────────────────────────────────────
  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      Employee? employee;
      employee = await _findEmployeeByPin(_pinInput);

      if (employee == null && !kIsWeb) {
        final localEmployees = await DatabaseService.instance.getAllEmployees();
        for (final emp in localEmployees) {
          final valid = await SecurityService.instance.verifyPin(emp.id, _pinInput);
          if (valid) { employee = emp; break; }
        }
      }

      if (employee == null) throw 'Invalid PIN. Please try again.';
      await _openSession(employee);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('Invalid PIN')
              ? 'Invalid PIN. Please try again.'
              : 'Login error: ${e.toString()}';
          _isLoading = false;
          _pinInput  = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<Employee?> _findEmployeeByPin(String pin) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: pin)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final employee = _docToEmployee(snap.docs.first);
      if (!kIsWeb) {
        try { await DatabaseService.instance.insertEmployee(employee); } catch (_) {}
      }
      return employee;
    } catch (e) {
      debugPrint('_findEmployeeByPin error: $e');
      return null;
    }
  }

  Employee _docToEmployee(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data      = doc.data();
    final firstName = data['firstName'] ?? '';
    final lastName  = data['lastName']  ?? '';
    final fullName  = data['name']      ?? '$firstName $lastName'.trim();
    return Employee.fromMap({
      'id'               : doc.id,
      'employee_id'      : data['employeeId'] ?? doc.id,
      'first_name'       : firstName,
      'last_name'        : lastName,
      'full_name'        : fullName,
      'email'            : data['email']      ?? '',
      'department'       : data['role']       ?? data['department'] ?? '',
      'position'         : data['role']       ?? data['position']   ?? '',
      'phone'            : data['phone'],
      'photo_path'       : data['photoPath'],
      'face_embedding'   : data['faceEmbedding'],
      'fingerprint_hash' : data['fingerprintHash'],
      'pin_hash'         : null,
      'pin_salt'         : null,
      'nfc_tag_id'       : data['nfcTagId'],
      'is_active'        : data['status'] == 'active' ? 1 : 0,
      'created_at'       : (data['createdAt'] as Timestamp?)?.toDate().toIso8601String()
          ?? DateTime.now().toIso8601String(),
      'updated_at'       : (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String()
          ?? DateTime.now().toIso8601String(),
    });
  }

  Future<void> _signIntoFirebaseAuth(Employee employee) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees').doc(employee.id).get();
      final data     = snap.data();
      final email    = (data?['email']    as String? ?? '').trim();
      final password = (data?['password'] as String? ?? '').trim();
      if (email.isEmpty || password.isEmpty) {
        debugPrint('Firebase Auth skipped — no email/password for ${employee.fullName}.');
        return;
      }
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email, password: password);
        debugPrint('Firebase Auth ✓ signed in: $email');
      } catch (signInErr) {
        final code = signInErr is FirebaseAuthException ? signInErr.code : '';
        if (_notFoundCodes.contains(code)) {
          try {
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email, password: password);
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (uid.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('employees').doc(employee.id)
                  .update({'authUid': uid});
            }
          } catch (createErr) {
            debugPrint('Firebase Auth create error: $createErr');
          }
        }
      }
    } catch (e) {
      debugPrint('Firebase Auth outer error: $e');
    }
  }

<<<<<<< HEAD
  // ── Open session → navigate to FingerprintScreen ──────────────────────────
=======
  // ── Open session → navigate to FingerprintScreen (Step 2) ─────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Future<void> _openSession(Employee employee) async {
    try {
      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      await _signIntoFirebaseAuth(employee);

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type'          : 'login',
          'employeeId'    : employee.id,
          'employee_name' : employee.fullName,
          'email'         : employee.email,
          'role'          : employee.position,
          'timestamp'     : FieldValue.serverTimestamp(),
          'device'        : kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } catch (logErr) {
        debugPrint('Activity log error: $logErr');
      }

      if (!mounted) return;

<<<<<<< HEAD
=======
      // ── Always go to fingerprint screen after PIN or NFC ──────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FingerprintScreen(employee: employee),
        ),
            (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = 'Session error: $e'; _isLoading = false; });
      }
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
      }
    } else if (_pinInput.length < 4) {
      setState(() => _pinInput += key);
      if (_pinInput.length == 4) {
        Future.delayed(const Duration(milliseconds: 250), _loginWithPin);
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() { _errorMessage = msg; _isLoading = false; _pinInput = ''; });
      _shakeController.forward(from: 0);
    }
  }

  void _goToStep(_LoginStep step) {
<<<<<<< HEAD
    setState(() {
      _step           = step;
      _errorMessage   = null;
      _pinInput       = '';
      _captureSuccess = false;
    });
    _modalController.forward(from: 0);
    if (step == _LoginStep.nfcWait) _startNfcSession();
    if (step == _LoginStep.clientMeeting) {
      _useFrontCamera = true;
      _currentPlaceName = ''; // reset before fetching
      _startCameraSession();
      _startClockTimer();
      _fetchCurrentLocation(); // get GPS location
    }
=======
    _slideController.reset();
    setState(() {
      _step         = step;
      _errorMessage = null;
      _pinInput     = '';
    });
    _slideController.forward();
    if (step == _LoginStep.nfcWait) _startNfcSession();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  }

  void _goBack() {
    if (_step == _LoginStep.selectMethod) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LandingScreen()));
    } else {
      if (_step == _LoginStep.nfcWait && !kIsWeb) {
        try { NfcManager.instance.stopSession(); } catch (_) {}
      }
<<<<<<< HEAD
      if (_step == _LoginStep.clientMeeting) {
        _clockTimer?.cancel();
        _successCloseTimer?.cancel();
        _releaseCamera();
        _useFrontCamera = true;
        _currentPlaceName = '';
      }
      _modalController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _step           = _LoginStep.selectMethod;
            _errorMessage   = null;
            _pinInput       = '';
            _captureSuccess = false;
          });
        }
      });
    }
  }

  void _onClientMeetingLogin() {
    _goToStep(_LoginStep.clientMeeting);
  }

  // ── Location fetching ──────────────────────────────────────────────────
  Future<void> _fetchCurrentLocation() async {
    try {
      // Check permissions
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _currentPlaceName = 'Location services disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _currentPlaceName = 'Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _currentPlaceName = 'Location permanently denied');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation);

      // Reverse geocode
      String placeName = '';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude, position.longitude);

        if (placemarks.isNotEmpty) {
          Placemark pm = placemarks.first;
          // Build address parts safely — no nullable += operator
          List<String> parts = [];
          if (pm.subThoroughfare != null) parts.add(pm.subThoroughfare!);
          if (pm.thoroughfare != null) parts.add(pm.thoroughfare!);
          if (pm.locality != null) parts.add(pm.locality!);
          if (pm.administrativeArea != null) parts.add(pm.administrativeArea!);
          if (pm.country != null) parts.add(pm.country!);
          placeName = parts.join(', ');
        }
      } catch (geocodeError) {
        placeName = '';
      }

      if (placeName.isEmpty) {
        placeName = 'Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
      }

      if (mounted) {
        setState(() => _currentPlaceName = placeName);
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        setState(() => _currentPlaceName = 'Unable to get location');
      }
    }
  }

  // ── Client Meeting: camera session ─────────────────────────────────────
  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _startCameraSession() async {
    if (kIsWeb) {
      _setError('Camera check-in is not available on web.');
      return;
    }
    await _releaseCamera();

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setError('No camera found on this device.');
        return;
      }
      final selected = cameras.firstWhere(
            (c) => c.lensDirection ==
            (_useFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
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
      debugPrint('Camera init error: $e');
      _setError('Could not start camera. Check camera permission.');
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
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() { _isCapturing = true; _errorMessage = null; });
    try {
      final photo = await controller.takePicture();
      debugPrint('Client meeting photo captured: ${photo.path} at $_now, location: $_currentPlaceName');

      _clockTimer?.cancel();
      await _releaseCamera();

      if (!mounted) return;
      setState(() {
        _isCapturing    = false;
        _captureSuccess = true;
      });

      _successCloseTimer?.cancel();
      _successCloseTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _step == _LoginStep.clientMeeting && _captureSuccess) {
          _goBack();
        }
      });
    } catch (e) {
      debugPrint('Client meeting capture error: $e');
      if (mounted) setState(() => _isCapturing = false);
      _setError('Could not capture photo. Please try again.');
    }
  }

  String _formatTimestamp(DateTime dt) {
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final hh  = hour12.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$mm/$dd/$yyyy - $hh:$min $ampm';
  }

=======
      _goToStep(_LoginStep.selectMethod);
    }
  }

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _goBack(); },
      child: Scaffold(
<<<<<<< HEAD
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_bgTop, _bgMid, _bgBottom],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(children: [
                  _buildOrangeHeader(),
                  Expanded(child: _buildSelectMethodStep()),
                ]),
              ),
            ),
            if (_step != _LoginStep.selectMethod) _buildModalOverlay(),
          ],
=======
        backgroundColor: _bg,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            _buildOrangeHeader(),
            Expanded(
              child: SlideTransition(
                position: _slideAnim,
                child: _buildStepContent(),
              ),
            ),
          ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ),
    );
  }

<<<<<<< HEAD
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
            child: ScaleTransition(
              scale: _modalScaleAnim,
              child: card,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER (unchanged)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildOrangeHeader() {
    const double radius       = 16;
    const double borderWidth  = 1.15;
    const double innerRadius  = radius - borderWidth;

    return Container(
      decoration: const BoxDecoration(
        color: _headerBorder,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(radius),
          bottomRight: Radius.circular(radius),
        ),
      ),
      padding: const EdgeInsets.only(bottom: borderWidth),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
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
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: _goBack,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.chevron_left_rounded, color: _white, size: 20),
                  const SizedBox(width: 2),
                  const Text('Back', style: TextStyle(
                      color: _white,
                      fontSize: 16, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 24),
              const Text('Auth & Clock In', style: TextStyle(
                  color: _white, fontSize: 30,
                  fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 8),
              const Text('Select your initial verification method',
                  style: TextStyle(
                      color: _white,
                      fontSize: 14, fontWeight: FontWeight.w400)),
            ]),
          ),
=======
  Widget _buildOrangeHeader() {
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _goBack,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left_rounded, color: _white, size: 22),
                const SizedBox(width: 4),
                Text('Back', style: TextStyle(
                    color: _white.withOpacity(0.9),
                    fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Auth & Clock In', style: TextStyle(
                color: _white, fontSize: 32,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('Select your initial verification method',
                style: TextStyle(
                    color: _white.withOpacity(0.85),
                    fontSize: 15, fontWeight: FontWeight.w400)),
          ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
      ),
    );
  }

<<<<<<< HEAD
  Widget _buildSelectMethodStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(children: [
        _buildOverlapCard(
          stepLabel: 'Step 1: Initial Login',
          child: Column(children: [
            Row(children: [
              Expanded(child: _MethodButton(
                icon: Icons.contactless_rounded,
                label: 'Key Fob',
                enabled: !kIsWeb && _nfcAvailable,
                onTap: () => _goToStep(_LoginStep.nfcWait),
              )),
              const SizedBox(width: 12),
              Expanded(child: _MethodButton(
                icon: Icons.key_rounded,
                label: 'Use PIN',
                onTap: () => _goToStep(_LoginStep.pinEntry),
              )),
            ]),
            const SizedBox(height: 16),
            _buildClientMeetingButton(),
=======
  Widget _buildStepContent() {
    switch (_step) {
      case _LoginStep.selectMethod: return _buildSelectMethodStep();
      case _LoginStep.pinEntry:     return _buildPinEntryStep();
      case _LoginStep.nfcWait:      return _buildNfcWaitStep();
    }
  }

  Widget _buildSelectMethodStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Initial Login',
          child: Row(children: [
            Expanded(child: _MethodButton(
              icon: Icons.contactless_rounded,
              label: 'Key Fob',
              enabled: !kIsWeb && _nfcAvailable,
              onTap: () => _goToStep(_LoginStep.nfcWait),
            )),
            const SizedBox(width: 14),
            Expanded(child: _MethodButton(
              icon: Icons.key_rounded,
              label: 'Use PIN',
              onTap: () => _goToStep(_LoginStep.pinEntry),
            )),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ]),
        ),
        if (kIsWeb || !_nfcAvailable) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
<<<<<<< HEAD
              color: _white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorder, width: 1.5),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: _textMuted, size: 16),
=======
              color: _white08,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _white15),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: _white40, size: 16),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              const SizedBox(width: 10),
              Expanded(child: Text(
                kIsWeb
                    ? 'NFC is not available on web. Use PIN to sign in.'
                    : 'NFC not available on this device. Use PIN to sign in.',
<<<<<<< HEAD
                style: const TextStyle(color: _textMuted, fontSize: 12),
=======
                style: TextStyle(color: _white40, fontSize: 12),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              )),
            ]),
          ),
        ],
      ]),
    );
  }

<<<<<<< HEAD
  Widget _buildClientMeetingButton() {
    return GestureDetector(
      onTap: _onClientMeetingLogin,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _orange, width: 1),
        ),
        child: const Text(
          'Client Meeting LogIn',
          style: TextStyle(
              color: _orange, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildOverlapCard({required String stepLabel, required Widget child}) {
    return Transform.translate(
      offset: const Offset(0, -30),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: _headerEnd.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Text(stepLabel,
              style: const TextStyle(color: _textDark, fontSize: 15,
                  fontWeight: FontWeight.w700, letterSpacing: 0.2))),
          const SizedBox(height: 20),
          child,
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PIN MODAL CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildPinModalCard() {
    return Container(
      width: double.infinity,
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
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.key_rounded, color: _modalGradTop, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('Enter PIN', style: TextStyle(
              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'Please enter your 4-digit PIN to begin',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 14),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) => Transform.translate(
              offset: Offset(_shakeAnim.value *
                  ((_shakeController.value * 10).round().isEven ? 1 : -1), 0),
              child: child,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pinInput.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Colors.white : Colors.white.withOpacity(0.35),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),
          Column(
            children: [
              _pinPadRow(['1', '2', '3']),
              const SizedBox(height: 12),
              _pinPadRow(['4', '5', '6']),
              const SizedBox(height: 12),
              _pinPadRow(['7', '8', '9']),
              const SizedBox(height: 12),
              _pinPadRow(['', '0', 'del']),
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

  Widget _pinPadRow(List<String> keys) {
    return Row(
      children: List.generate(keys.length, (colIdx) {
        final key = keys[colIdx];
        if (key.isEmpty) return const Expanded(child: SizedBox());
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                left: colIdx > 0 ? 10 : 0,
                right: colIdx < keys.length - 1 ? 10 : 0),
            child: _PinKeyWhite(label: key, onTap: () => _onPinKey(key)),
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NFC MODAL CARD
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildNfcModalCard() {
    return Container(
      width: double.infinity,
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
            color: Colors.black.withOpacity(0.06),
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
                width: 112, height: 112,
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
          const Text('Tap Key Fob', style: TextStyle(
              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            _isLoading
                ? 'Reading keyfob…'
                : 'Please tap your key fob on the reader...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
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

  // ═══════════════════════════════════════════════════════════════════════
  // CLIENT MEETING MODAL CARD — dynamic location
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildClientMeetingModalCard() {
    if (_captureSuccess) return _buildClientMeetingSuccessCard();

    return Container(
      width: double.infinity,
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
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Client Meeting Check-In', style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Snap a photo to log your visit',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
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
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.switch_camera, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(
              _useFrontCamera ? 'Front' : 'Back',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
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
          border: Border.all(color: _optionBorder, width: 1.5),
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
                  Container(color: Colors.black.withOpacity(0.25)),
                Positioned(
                  left: 14, right: 14, bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dynamic location name – NO HARDCODED TEXT!
                      Text(
                        _currentPlaceName.isEmpty ? 'Fetching location...' : _currentPlaceName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(_now),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
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
        child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2.5),
      );
    }
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(controller);
    }
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
            width: 64, height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cmShutterOuter,
              boxShadow: [
                BoxShadow(
                    color: _cmShutterGlow.withOpacity(0.8), blurRadius: 15),
              ],
            ),
            alignment: Alignment.center,
            child: _isCapturing
                ? const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5),
            )
                : Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cmShutterInner,
                boxShadow: [
                  BoxShadow(
                      color: _cmShutterGlow.withOpacity(0.8),
                      blurRadius: 15),
                ],
              ),
            ),
          ),
        ),
=======
  Widget _buildPinEntryStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Enter Your PIN',
          child: Column(children: [
            const SizedBox(height: 8),
            _buildPinDots(),
            const SizedBox(height: 24),
            _buildPinPad(),
            const SizedBox(height: 16),
            _buildFeedback(),
          ]),
        ),
        const SizedBox(height: 16),
        _buildFooterNote(),
      ]),
    );
  }

  Widget _buildNfcWaitStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Tap Key Fob',
          child: Column(children: [
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _nfcPulseAnim,
              builder: (_, __) => Transform.scale(
                scale: _isLoading ? 1.0 : _nfcPulseAnim.value,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _orange.withOpacity(0.12),
                    border: Border.all(color: _orange.withOpacity(0.5), width: 2),
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(
                      color: _orange, strokeWidth: 2.5))
                      : const Icon(Icons.contactless_rounded,
                      color: _orange, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isLoading ? 'Reading keyfob…' : 'Hold your keyfob\nclose to the device',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white70, fontSize: 15,
                  height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) _buildFeedback(),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStepCard({required String stepLabel, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text(stepLabel,
            style: TextStyle(color: _white70, fontSize: 13,
                fontWeight: FontWeight.w500, letterSpacing: 0.3))),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_shakeAnim.value *
            ((_shakeController.value * 10).round().isEven ? 1 : -1), 0),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled   = i < _pinInput.length;
          final hasError = _errorMessage != null;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError
                  ? _error.withOpacity(filled ? 1 : 0)
                  : filled ? _orange : Colors.transparent,
              border: Border.all(
                color: hasError ? _error.withOpacity(0.7)
                    : filled ? _orange : _white40,
                width: 2,
              ),
            ),
          );
        }),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    );
  }

<<<<<<< HEAD
  // ═══════════════════════════════════════════════════════════════════════
  // CLIENT MEETING SUCCESS CARD (orange gradient)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildClientMeetingSuccessCard() {
    return Container(
      width: double.infinity,
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
            color: Colors.black.withOpacity(0.06),
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
            child: const Icon(
              Icons.check_circle_rounded,
              color: _modalGradTop,
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Successfully Clock In',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Just wait for the HR Approvement...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Shared widgets ──────────────────────────────────────────────────────
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
        child: const Text('Cancel', style: TextStyle(
            color: Color(0xFFFFA500), fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildFeedback({bool onDark = false}) {
    if (_isLoading) {
      return SizedBox(
        height: 36,
        child: Center(child: CircularProgressIndicator(
            color: onDark ? Colors.white : _orange, strokeWidth: 2.5)),
      );
=======
  Widget _buildPinPad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['',  '0', 'del'],
    ];
    return Column(
      children: List.generate(4, (rowIdx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: List.generate(3, (colIdx) {
            final key = rows[rowIdx][colIdx];
            if (key.isEmpty) return const Expanded(child: SizedBox());
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: colIdx > 0 ? 10 : 0, right: colIdx < 2 ? 10 : 0),
                child: _PinKey(label: key, onTap: () => _onPinKey(key)),
              ),
            );
          }),
        ),
      )),
    );
  }

  Widget _buildFeedback() {
    if (_isLoading) {
      return const SizedBox(height: 36,
          child: Center(child: CircularProgressIndicator(
              color: _orange, strokeWidth: 2.5)));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    }
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
<<<<<<< HEAD
          color: onDark ? Colors.white.withOpacity(0.15) : _errorBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: onDark ? Colors.white.withOpacity(0.4) : _error.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded,
              color: onDark ? Colors.white : _error, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Text(_errorMessage!,
              style: TextStyle(
                  color: onDark ? Colors.white : _error,
                  fontSize: 13, fontWeight: FontWeight.w600))),
=======
          color: _error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _error.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: _error, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Text(_errorMessage!,
              style: TextStyle(color: _error, fontSize: 13,
                  fontWeight: FontWeight.w600))),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ]),
      );
    }
    return const SizedBox(height: 8);
  }
<<<<<<< HEAD
=======

  Widget _buildFooterNote() => Text(
    'Account creation is restricted to Admin.',
    textAlign: TextAlign.center,
    style: TextStyle(color: _white40, fontSize: 11),
  );
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}

// ── METHOD BUTTON ──────────────────────────────────────────────────────────────
class _MethodButton extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final bool         enabled;

  const _MethodButton({
    required this.icon, required this.label,
    required this.onTap, this.enabled = true,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

<<<<<<< HEAD
  static const Color _orange       = Color(0xFFF97316);
  static const Color _optionBorder = Color(0xFFFDBA74);
  static const Color _hoverBg      = Color(0xFFFFF7ED);
  static const Color _textDark     = Color(0xFF1F2937);

  bool _pressed = false;
=======
  static const Color _orange  = Color(0xFFFF8C00);
  static const Color _white15 = Color(0x26FFFFFF);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
<<<<<<< HEAD
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
=======
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95)
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
<<<<<<< HEAD
      onTapDown: widget.enabled ? (_) { _pressCtrl.forward(); setState(() => _pressed = true); } : null,
      onTapUp: widget.enabled ? (_) {
        _pressCtrl.reverse();
        setState(() => _pressed = false);
        widget.onTap();
      } : null,
      onTapCancel: widget.enabled ? () { _pressCtrl.reverse(); setState(() => _pressed = false); } : null,
=======
      onTapDown:   widget.enabled ? (_) => _pressCtrl.forward() : null,
      onTapUp:     widget.enabled ? (_) { _pressCtrl.reverse(); widget.onTap(); } : null,
      onTapCancel: widget.enabled ? () => _pressCtrl.reverse() : null,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: AspectRatio(
<<<<<<< HEAD
            aspectRatio: 0.95,
            child: Container(
              decoration: BoxDecoration(
                color: _pressed ? _hoverBg : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed ? _orange : _optionBorder,
=======
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                gradient: widget.enabled
                    ? const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2A1800), Color(0xFF1A1200)],
                ) : null,
                color: widget.enabled ? null : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.enabled ? _orange.withOpacity(0.45) : _white15,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  width: 1.5,
                ),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
<<<<<<< HEAD
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.enabled ? _optionBorder : const Color(0xFFE5E5E5),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(widget.icon,
                      color: widget.enabled ? _orange : const Color(0xFFBBBBBB),
                      size: 26),
                ),
                const SizedBox(height: 12),
                Text(widget.label, style: TextStyle(
                    color: widget.enabled ? _textDark : const Color(0xFFAAAAAA),
                    fontSize: 13, fontWeight: FontWeight.w700)),
=======
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: widget.enabled ? _orange.withOpacity(0.15) : _white15,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon,
                      color: widget.enabled ? _orange : const Color(0x66FFFFFF),
                      size: 28),
                ),
                const SizedBox(height: 14),
                Text(widget.label, style: TextStyle(
                    color: widget.enabled
                        ? const Color(0xFFFFFFFF) : const Color(0x66FFFFFF),
                    fontSize: 15, fontWeight: FontWeight.w600)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

<<<<<<< HEAD
// ── PIN KEY (white variant) ──────────────────────────────────────────────────
class _PinKeyWhite extends StatefulWidget {
  final String       label;
  final VoidCallback onTap;
  const _PinKeyWhite({required this.label, required this.onTap});
  @override
  State<_PinKeyWhite> createState() => _PinKeyWhiteState();
}

class _PinKeyWhiteState extends State<_PinKeyWhite> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

=======
// ── PIN KEY BUTTON ─────────────────────────────────────────────────────────────
class _PinKey extends StatefulWidget {
  final String       label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});
  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

  static const Color _orange  = Color(0xFFFF8C00);
  static const Color _white   = Color(0xFFFFFFFF);
  static const Color _white15 = Color(0x26FFFFFF);
  static const Color _white08 = Color(0x14FFFFFF);

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDel = widget.label == 'del';
    return GestureDetector(
      onTapDown:   (_) => _pressCtrl.forward(),
      onTapUp:     (_) { _pressCtrl.reverse(); widget.onTap(); },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
<<<<<<< HEAD
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF564334), width: 1.15),
          ),
          child: Center(
            child: isDel
                ? const Text('DEL', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF71717A)))
                : Text(widget.label, style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w500, color: Colors.black)),
=======
          height: 62,
          decoration: BoxDecoration(
            color: isDel ? _white08 : _white15,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDel ? const Color(0x26FFFFFF) : _orange.withOpacity(0.2),
            ),
          ),
          child: Center(
            child: isDel
                ? const Icon(Icons.backspace_outlined,
                color: Color(0xB3FFFFFF), size: 22)
                : Text(widget.label, style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: _white)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ),
      ),
    );
  }
}