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
        // No biometrics on device — stay idle, do NOT navigate anywhere
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
        return;
      }

      final enrolled = await _localAuth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
        // No fingerprints enrolled — stay idle, do NOT navigate anywhere
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
        return;
      }

      // Trigger the REAL device fingerprint prompt
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
        // User dismissed the system dialog — go back to idle
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      }
    } catch (e) {
      final msg = e.toString();

      if (msg.contains('NotAvailable') ||
          msg.contains('NotEnrolled') ||
          msg.contains('no_fragment_activity')) {
        // No biometrics — stay idle, do NOT navigate
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      } else if (msg.contains('LockedOut') || msg.contains('PermanentlyLockedOut')) {
        _onFailure('Too many attempts. Use PIN or Keyfob instead.');
      } else if (msg.contains('UserCancel') ||
          msg.contains('passcode') ||
          msg.contains('canceled')) {
        // User cancelled — stay idle
        if (mounted) setState(() { _fpState = _FpState.idle; _errorMessage = null; });
      } else {
        // Any other error — show error, stay on screen
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

  /// Back button — go back to previous screen (PIN/NFC screen)
  void _goBack() => Navigator.of(context).pop();

  /// Cancel Authentication — only way to reach dashboard without fingerprint
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
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
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

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_stateTitle,
              key: ValueKey(_fpState),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _white, fontSize: 26,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2)),
        ),
        const SizedBox(height: 10),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey(_errorMessage ?? 'sub_$_fpState'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _white.withOpacity(0.75),
                  fontSize: 13, height: 1.5)),
        ),
        const SizedBox(height: 28),

        if (_fpState == _FpState.idle || _fpState == _FpState.error)
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
      ]),
    );
  }

  Widget _buildIcon() {
    Color borderColor;
    switch (_fpState) {
      case _FpState.success: borderColor = _success; break;
      case _FpState.error:   borderColor = _error;   break;
      default:               borderColor = _orange;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _ringAnim, _successAnim, _shakeAnim]),
      builder: (_, __) {
        final shakeX = _fpState == _FpState.error
            ? _shakeAnim.value * (_shakeCtrl.value * 10 % 2 == 0 ? 1 : -1)
            : 0.0;

        return Transform.translate(
          offset: Offset(shakeX, 0),
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
        );
      },
    );
  }

  // ── Cancel button — only this navigates to dashboard ─────────────────────
  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: _onCancelTapped,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
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
        ),
      ),
    );
  }

  String get _stateTitle {
    switch (_fpState) {
      case _FpState.idle:     return 'Fingerprint\nRequired';
      case _FpState.scanning: return 'Scanning\nFingerprint...';
      case _FpState.success:  return 'Details\nAnalyzed';
      case _FpState.error:    return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_fpState) {
      case _FpState.idle:     return 'Tap the scanner icon to verify\nyour fingerprint';
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
}