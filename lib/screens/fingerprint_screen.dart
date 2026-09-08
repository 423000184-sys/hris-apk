// lib/screens/fingerprint_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import 'main_screen.dart';
import 'facial_recognition_screen.dart';

class FingerprintScreen extends StatefulWidget {
  final Employee employee;
  const FingerprintScreen({super.key, required this.employee});

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen>
    with TickerProviderStateMixin {

  final LocalAuthentication _localAuth = LocalAuthentication();

  _FpState _fpState       = _FpState.idle;
  String?  _errorMessage;
  bool     _cancelPressed = false;

  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _shakeCtrl;
  late AnimationController _successCtrl;

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

  // Modal-card gradient — matches the mock's orange popup
  static const _modalGradTop = Color(0xFFFF8A00);
  static const _modalGradMid = Color(0xFFFA6A00);
  static const _modalGradEnd = Color(0xFFF54900);

  // Border color CHANGES per state in the mocks:
  //   idle + scanning -> #564334 (brown/tan)
  //   success         -> #27272a (dark)
  static const _modalBorderDefault = Color(0xFF564334);
  static const _modalBorderSuccess = Color(0xFF27272A);

  // Bright green ring drawn around the white icon box ONLY on success
  // (matches the mock's <path stroke="#51FF00"> outer square outline)
  static const _successRing = Color(0xFF51FF00);

  static const _scrim        = Color.fromRGBO(9, 9, 11, 0.44);

  static const _white   = Color(0xFFFFFFFF);
  static const _white70 = Color(0xFFDFDFDF); // matches mock's subtitle color
  static const _orange  = Color(0xFFF97316);
  static const _success = Color(0xFF22C55E);
  static const _error   = Color(0xFFDC2626);
  static const _cancelText = Color(0xFFFF8A00);
  static const _cancelBorder = Color(0xFFFFA500);
=======
  static const _bg      = Color(0xFF0A0A0A);
  static const _white   = Color(0xFFFFFFFF);
  static const _white70 = Color(0xB3FFFFFF);
  static const _white50 = Color(0x80FFFFFF);
  static const _white40 = Color(0x66FFFFFF);
  static const _white15 = Color(0x26FFFFFF);
  static const _white08 = Color(0x14FFFFFF);
  static const _orange  = Color(0xFFFF5500);
  static const _success = Color(0xFFCCFF00);
  static const _error   = Color(0xFFFF3D00);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();

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

    _pulseCtrl.repeat(reverse: true);
    _ringCtrl.repeat();
    _fadeCtrl.forward();

    // Auto-trigger real fingerprint on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), _authenticate);
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ── Authentication ────────────────────────────────────────────────────────
  Future<void> _authenticate() async {
    if (!mounted) return;

    if (kIsWeb) { await _onSuccess(); return; }

    setState(() { _fpState = _FpState.scanning; _errorMessage = null; });

    try {
      final canCheck    = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canCheck || !isSupported) {
<<<<<<< HEAD
=======
        // No biometrics on device — stay idle, do NOT navigate anywhere
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
        return;
      }

      final enrolled = await _localAuth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
<<<<<<< HEAD
=======
        // No fingerprints enrolled — stay idle, do NOT navigate anywhere
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
        return;
      }

<<<<<<< HEAD
=======
      // Trigger the REAL device fingerprint prompt
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Place your finger on the scanner to clock in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (authenticated) {
        await _onSuccess();
      } else {
<<<<<<< HEAD
=======
        // User dismissed the system dialog — go back to idle
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      }
    } catch (e) {
      final msg = e.toString();

      if (msg.contains('NotAvailable') ||
          msg.contains('NotEnrolled') ||
          msg.contains('no_fragment_activity')) {
<<<<<<< HEAD
=======
        // No biometrics — stay idle, do NOT navigate
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      } else if (msg.contains('LockedOut') || msg.contains('PermanentlyLockedOut')) {
        _onFailure('Too many attempts. Use PIN or Keyfob instead.');
      } else if (msg.contains('UserCancel') ||
          msg.contains('passcode') ||
          msg.contains('canceled')) {
<<<<<<< HEAD
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      } else {
=======
        // User cancelled — stay idle
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      } else {
        // Any other error — show error, stay on screen
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        _onFailure('Biometric error. Please try again.');
      }
    }
  }

  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() { _fpState = _FpState.success; _errorMessage = null; });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type'         : 'fingerprint_verified',
        'employeeId'   : widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email'        : widget.employee.email,
        'timestamp'    : FieldValue.serverTimestamp(),
        'device'       : kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1400));
    _navigateToFacialRecognition();
  }

<<<<<<< HEAD
  void _navigateToFacialRecognition() {
    if (!mounted) return;
=======
  void _navigateToDashboard() {
    if (!mounted) return;
    // Cancel → dashboard
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainScreen(employee: widget.employee)),
          (route) => false,
    );
  }

  void _navigateToFacialRecognition() {
    if (!mounted) return;
    // Fingerprint success → facial recognition
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FacialRecognitionScreen(employee: widget.employee),
      ),
    );
  }

  void _onFailure(String msg) {
    if (!mounted) return;
    setState(() { _fpState = _FpState.error; _errorMessage = msg; });
    _shakeCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
    });
  }

<<<<<<< HEAD
  void _goBack() => Navigator.of(context).pop();

=======
  /// Back button — go back to previous screen (PIN/NFC screen)
  void _goBack() => Navigator.of(context).pop();

  /// Cancel Authentication — only way to reach dashboard without fingerprint
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  void _onCancelTapped() async {
    setState(() { _cancelPressed = true; });
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    setState(() { _cancelPressed = false; });
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;
    _navigateToFacialRecognition();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< HEAD
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
  // Border color follows the mock: brown/tan by default, dark on success
  Color get _currentModalBorder =>
      _fpState == _FpState.success ? _modalBorderSuccess : _modalBorderDefault;

  Widget _buildModalCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
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
                style: TextStyle(color: _white.withOpacity(0.8),
                    fontSize: 14)),
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
        if (_fpState == _FpState.idle || _fpState == _FpState.error)
          _buildCancelButton(),
        const SizedBox(height: 12),
        Text('Account creation is restricted to Admin.',
            style: TextStyle(color: _white40, fontSize: 11)),
      ]),
    );
  }

  Widget _buildOuterCard() {
    final showStepLabel =
        _fpState == _FpState.scanning || _fpState == _FpState.success;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F1F1F), width: 1),
      ),
      child: Column(children: [
        if (showStepLabel)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 0),
            child: Text('Step 1: Initial Login',
                style: TextStyle(color: _white50, fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        Padding(
          padding: EdgeInsets.only(top: showStepLabel ? 12 : 0),
          child: _buildInnerCard(),
        ),
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
        border: Border.all(color: _currentModalBorder, width: 1.15),
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
        if (_fpState == _FpState.idle || _fpState == _FpState.error) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.22),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text('Step 2: Biometric Verification',
                style: TextStyle(color: _white, fontSize: 12,
                    fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          ),
          const SizedBox(height: 32),
        ],

        _buildIcon(),
        const SizedBox(height: 28),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_stateTitle,
              key: ValueKey(_fpState),
              textAlign: TextAlign.center,
<<<<<<< HEAD
              style: const TextStyle(color: _white, fontSize: 30,
                  fontWeight: FontWeight.w500, height: 1.1)),
        ),
        const SizedBox(height: 12),
=======
              style: const TextStyle(color: _white, fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
        ),
        const SizedBox(height: 10),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey(_errorMessage ?? 'sub_$_fpState'),
              textAlign: TextAlign.center,
<<<<<<< HEAD
              style: const TextStyle(color: _white70, fontSize: 14, height: 1.4)),
=======
              style: TextStyle(color: _white.withOpacity(0.75),
                  fontSize: 13, height: 1.5)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
        const SizedBox(height: 28),

        if (_fpState == _FpState.idle || _fpState == _FpState.error)
<<<<<<< HEAD
          _buildCancelButton(),
=======
          GestureDetector(
            onTap: _authenticate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _white.withOpacity(0.22), width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.fingerprint_rounded, color: _white, size: 20),
                const SizedBox(width: 8),
                const Text('Tap to Scan',
                    style: TextStyle(color: _white, fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

        if (_fpState == _FpState.scanning)
          Text('Analyzing biometric data…',
              style: TextStyle(color: _white.withOpacity(0.6), fontSize: 13)),

        const SizedBox(height: 4),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ]),
    );
  }

  Widget _buildIcon() {
<<<<<<< HEAD
    Color iconColor;
    switch (_fpState) {
      case _FpState.success: iconColor = _success; break;
      case _FpState.error:   iconColor = _error;   break;
      default:               iconColor = _modalGradTop;
=======
    Color borderColor;
    switch (_fpState) {
      case _FpState.success: borderColor = _success; break;
      case _FpState.error:   borderColor = _error;   break;
      default:               borderColor = _orange;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _ringAnim, _successAnim, _shakeAnim]),
      builder: (_, __) {
        final shakeX = _fpState == _FpState.error
            ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
<<<<<<< HEAD
          child: GestureDetector(
            onTap: (_fpState == _FpState.idle || _fpState == _FpState.error)
                ? _authenticate
                : null,
            child: Stack(alignment: Alignment.center, children: [
              if (_fpState == _FpState.scanning)
                Transform.rotate(
                  angle: _ringAnim.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(132, 132),
                    painter: _DashRingPainter(
                        color: _white.withOpacity(0.5), dashCount: 14),
                  ),
                ),

              if (_fpState != _FpState.success)
                Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 112, height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.15),
                    ),
                  ),
                ),

              // White icon box — 112x112.
              // On success, the mock draws a bright-green (#51FF00) outline
              // around this box instead of a plain white card shadow.
              Transform.scale(
                scale: _fpState == _FpState.success
                    ? (0.85 + 0.15 * _successAnim.value)
                    : 1.0,
                child: Container(
                  width: 112, height: 112,
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(16),
                    border: _fpState == _FpState.success
                        ? Border.all(color: _successRing, width: 3)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12, offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _fpState == _FpState.success
                      ? Icon(Icons.verified_user_rounded, color: iconColor, size: 46)
                      : Icon(Icons.fingerprint_rounded, color: iconColor, size: 48),
                ),
              ),
            ]),
          ),
=======
          child: Stack(alignment: Alignment.center, children: [
            if (_fpState == _FpState.scanning)
              Transform.rotate(
                angle: _ringAnim.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size(136, 136),
                  painter: _DashRingPainter(
                      color: _white.withOpacity(0.35), dashCount: 14),
                ),
              ),

            if (_fpState == _FpState.success)
              Transform.scale(
                scale: _successAnim.value * 1.25,
                child: Container(
                  width: 126, height: 126,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _success.withOpacity(
                            (1 - _successAnim.value).clamp(0.0, 1.0)),
                        width: 2),
                  ),
                ),
              ),

            if (_fpState != _FpState.success)
              Transform.scale(
                scale: _pulseAnim.value,
                child: Container(
                  width: 116, height: 116,
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
                        _fpState == _FpState.success ? 0.9 : 0.35),
                    width: _fpState == _FpState.success ? 2 : 1.5),
                boxShadow: [
                  BoxShadow(color: borderColor.withOpacity(0.2),
                      blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: _fpState == _FpState.success
                  ? Transform.scale(
                  scale: _successAnim.value,
                  child: Icon(Icons.shield_rounded, color: _success, size: 46))
                  : Icon(Icons.fingerprint_rounded,
                  color: _fpState == _FpState.error ? _error : _orange,
                  size: 50),
            ),

            if (_fpState == _FpState.success)
              Transform.scale(
                scale: _successAnim.value,
                child: const Icon(Icons.check_rounded, color: _success, size: 24),
              ),
          ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        );
      },
    );
  }

<<<<<<< HEAD
=======
  // ── Cancel button — only this navigates to dashboard ─────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
          border: Border.all(color: _cancelBorder, width: 1.15),
        ),
        child: const Center(
          child: Text('Cancel Authentication',
              style: TextStyle(
                color: _cancelText,
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

  String get _stateTitle {
    switch (_fpState) {
<<<<<<< HEAD
      case _FpState.idle:     return 'Fingerprint Required';
=======
      case _FpState.idle:     return 'Fingerprint\nRequired';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      case _FpState.scanning: return 'Scanning\nFingerprint...';
      case _FpState.success:  return 'Details\nAnalyzed';
      case _FpState.error:    return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_fpState) {
<<<<<<< HEAD
      case _FpState.idle:     return 'Tap the scanner icon to verify your fingerprint';
=======
      case _FpState.idle:     return 'Tap the scanner icon to verify\nyour fingerprint';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      case _FpState.scanning: return 'Analyzing biometric data...';
      case _FpState.success:  return 'Biometric match confirmed. Preparing\ncamera...';
      case _FpState.error:    return 'Fingerprint not recognized.\nTap to try again.';
    }
  }
}

enum _FpState { idle, scanning, success, error }

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
<<<<<<< HEAD
}
=======
}
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
