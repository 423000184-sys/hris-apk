// lib/screens/login_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'fingerprint_screen.dart';
import 'landing_screen.dart';

enum _LoginStep { selectMethod, pinEntry, nfcWait, clientMeeting }

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors resolved per build
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  // Background gradient
  Color get bgTop    => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get bgMid    => isDark ? const Color(0xFF0F0D0B) : const Color(0xFFFFF0E5);
  Color get bgBottom => isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFE3D1);

  // Card
  Color get cardBg     => isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);

  // Option button
  Color get optionBorder => isDark ? const Color(0xFF7C2D12) : const Color(0xFFFDBA74);
  Color get hoverBg      => isDark ? const Color(0xFF27272A) : const Color(0xFFFFF7ED);

  // Text
  Color get textDark  => isDark ? Colors.white : const Color(0xFF1F2937);
  Color get textMuted => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);

  // Info bar
  Color get infoBg     => isDark ? const Color(0xFF1F1F23) : Colors.white;
  Color get infoBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFEDD5);
  Color get infoText   => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);

  // Method buttons inner icon bg
  Color get methodIconBg => isDark ? const Color(0xFF27272A) : Colors.white;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  String _pinInput = '';
  bool _isLoading = false;
  bool _nfcAvailable = false;
  String? _errorMessage;
  _LoginStep _step = _LoginStep.selectMethod;

  // Client Meeting (camera capture) state
  CameraController? _cameraController;
  bool _isCapturing = false;
  bool _captureSuccess = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  Timer? _successCloseTimer;
  bool _useFrontCamera = true;

  static const String _siteName = 'National Teachers College';

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _modalController;
  late Animation<double> _modalScaleAnim;
  late Animation<double> _modalOpacityAnim;
  late AnimationController _nfcPulseController;
  late Animation<double> _nfcPulseAnim;

  // ── Static brand colors (same in both themes) ─────────────────────────
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
  static const Color _scrim = Color.fromRGBO(9, 9, 21, 0.44);

  static const Color _cmPreviewBg = Color(0xFF20212A);
  static const Color _cmShutterOuter = Color(0xFFFFA500);
  static const Color _cmShutterInner = Color(0xFFFEE0AA);
  static const Color _cmShutterGlow = Color(0xFFFF8C00);

  static const List<String> _notFoundCodes = [
    'user-not-found',
    'invalid-credential',
    'invalid-login-credentials',
    'INVALID_LOGIN_CREDENTIALS',
  ];

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _modalController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _nfcPulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));

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

    _checkCapabilities();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fadeController.dispose();
    _modalController.dispose();
    _nfcPulseController.dispose();
    _clockTimer?.cancel();
    _successCloseTimer?.cancel();
    _releaseCamera();
    if (!kIsWeb) {
      try {
        NfcManager.instance.stopSession();
      } catch (_) {}
    }
    super.dispose();
  }

  // ── NFC ──────────────────────────────────────────────────────────────
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

  // ── PIN login ─────────────────────────────────────────────────────────
  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Employee? employee;
      employee = await _findEmployeeByPin(_pinInput);

      if (employee == null && !kIsWeb) {
        final localEmployees =
        await DatabaseService.instance.getAllEmployees();
        for (final emp in localEmployees) {
          final valid =
          await SecurityService.instance.verifyPin(emp.id, _pinInput);
          if (valid) {
            employee = emp;
            break;
          }
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
          _pinInput = '';
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
        try {
          await DatabaseService.instance.insertEmployee(employee);
        } catch (_) {}
      }
      return employee;
    } catch (e) {
      debugPrint('_findEmployeeByPin error: $e');
      return null;
    }
  }

  Employee _docToEmployee(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final firstName = data['firstName'] ?? '';
    final lastName = data['lastName'] ?? '';
    final fullName = data['name'] ?? '$firstName $lastName'.trim();
    return Employee.fromMap({
      'id': doc.id,
      'employee_id': data['employeeId'] ?? doc.id,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'email': data['email'] ?? '',
      'department': data['role'] ?? data['department'] ?? '',
      'position': data['role'] ?? data['position'] ?? '',
      'phone': data['phone'],
      'photo_path': data['photoPath'],
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
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employee.id)
          .get();
      final data = snap.data();
      final email = (data?['email'] as String? ?? '').trim();
      final password = (data?['password'] as String? ?? '').trim();
      if (email.isEmpty || password.isEmpty) {
        debugPrint(
            'Firebase Auth skipped — no email/password for ${employee.fullName}.');
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
                  .collection('employees')
                  .doc(employee.id)
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

  Future<void> _openSession(Employee employee) async {
    try {
      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      await _signIntoFirebaseAuth(employee);

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'login',
          'employeeId': employee.id,
          'employee_name': employee.fullName,
          'email': employee.email,
          'role': employee.position,
          'timestamp': FieldValue.serverTimestamp(),
          'device': kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } catch (logErr) {
        debugPrint('Activity log error: $logErr');
      }

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FingerprintScreen(employee: employee),
        ),
            (route) => false,
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
    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(() =>
        _pinInput = _pinInput.substring(0, _pinInput.length - 1));
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
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
        _pinInput = '';
      });
      _shakeController.forward(from: 0);
    }
  }

  void _goToStep(_LoginStep step) {
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
        _useFrontCamera = true;
      }
      _modalController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _step = _LoginStep.selectMethod;
            _errorMessage = null;
            _pinInput = '';
            _captureSuccess = false;
          });
        }
      });
    }
  }

  void _onClientMeetingLogin() {
    _goToStep(_LoginStep.clientMeeting);
  }

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
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });
    try {
      final photo = await controller.takePicture();
      debugPrint('Client meeting photo captured: ${photo.path} at $_now');

      _clockTimer?.cancel();
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
    final hh = hour12.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$mm/$dd/$yyyy - $hh:$min $ampm';
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
        body: Stack(
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
        ),
      ),
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
            child: ScaleTransition(
              scale: _modalScaleAnim,
              child: card,
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER (same gradient, brand color) ────────────────────────────────
  Widget _buildOrangeHeader() {
    const double radius = 16;
    const double borderWidth = 1.15;
    const double innerRadius = radius - borderWidth;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _goBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.chevron_left_rounded,
                          color: _white, size: 20),
                      SizedBox(width: 2),
                      Text('Back',
                          style: TextStyle(
                              color: _white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Auth & Clock In',
                    style: TextStyle(
                        color: _white,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
                const SizedBox(height: 8),
                const Text('Select your initial verification method',
                    style: TextStyle(
                        color: _white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectMethodStep(_ThemeColors tc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(children: [
        _buildOverlapCard(
          tc: tc,
          stepLabel: 'Step 1: Initial Login',
          child: Column(children: [
            Row(children: [
              Expanded(
                child: _MethodButton(
                  icon: Icons.contactless_rounded,
                  label: 'Key Fob',
                  enabled: !kIsWeb && _nfcAvailable,
                  onTap: () => _goToStep(_LoginStep.nfcWait),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MethodButton(
                  icon: Icons.key_rounded,
                  label: 'Use PIN',
                  onTap: () => _goToStep(_LoginStep.pinEntry),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _buildClientMeetingButton(),
          ]),
        ),
        if (kIsWeb || !_nfcAvailable) ...[
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
              Icon(Icons.info_outline_rounded, color: tc.infoText, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kIsWeb
                      ? 'NFC is not available on web. Use PIN to sign in.'
                      : 'NFC not available on this device. Use PIN to sign in.',
                  style: TextStyle(color: tc.infoText, fontSize: 12),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildClientMeetingButton() {
    return GestureDetector(
      onTap: _onClientMeetingLogin,
      child: Container(
        width: double.infinity,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
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

  Widget _buildOverlapCard({
    required _ThemeColors tc,
    required String stepLabel,
    required Widget child,
  }) {
    return Transform.translate(
      offset: const Offset(0, -30),
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

  // ── PIN MODAL ──────────────────────────────────────────────────────────
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
            child: const Icon(Icons.key_rounded,
                color: _modalGradTop, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('Enter PIN',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(
            'Please enter your 4-digit PIN to begin',
            textAlign: TextAlign.center,
            style:
            TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 14),
          ),
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
              right: colIdx < keys.length - 1 ? 10 : 0,
            ),
            child: _PinKeyWhite(label: key, onTap: () => _onPinKey(key)),
          ),
        );
      }),
    );
  }

  // ── NFC MODAL ──────────────────────────────────────────────────────────
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

  // ── CLIENT MEETING MODAL ───────────────────────────────────────────────
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
          border: Border.all(color: const Color(0xFFFDBA74), width: 1.5),
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
                  left: 14,
                  right: 14,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _siteName,
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
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
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
        child: CircularProgressIndicator(
            color: Colors.white54, strokeWidth: 2.5),
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
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────────
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

// ── METHOD BUTTON (theme-aware) ──────────────────────────────────────────
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

    return GestureDetector(
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
  }
}

// ── PIN KEY (white variant) ─────────────────────────────────────────────
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