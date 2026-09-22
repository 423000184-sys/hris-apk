// lib/screens/fingerprint_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:local_auth/local_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import '../widgets/bootstrap_grid.dart';
import 'facial_recognition_screen.dart';

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
}

class FingerprintScreen extends StatefulWidget {
  final Employee employee;
  final DateTime? arrivalTime;

  const FingerprintScreen({
    super.key,
    required this.employee,
    this.arrivalTime,
  });

  @override
  State<FingerprintScreen> createState() => _FingerprintScreenState();
}

class _FingerprintScreenState extends State<FingerprintScreen>
    with TickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();

  _FpState _fpState = _FpState.idle;
  String? _errorMessage;
  bool _cancelPressed = false;

  Timer? _navTimer;

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

  @override
  void initState() {
    super.initState();

    if (widget.arrivalTime != null) {
      debugPrint(
          '⏱️ [FingerprintScreen] Arrival received: ${widget.arrivalTime}');
    } else {
      debugPrint('⚠️ [FingerprintScreen] No arrival time passed');
    }

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
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _fadeCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTHENTICATE
  //  • Web  → tap = proceed to facial recognition (walang biometrics)
  //  • Native → trigger real biometric, auto-proceed if not available
  // ═══════════════════════════════════════════════════════════════
  Future<void> _authenticate() async {
    if (!mounted) return;

    if (kIsWeb) {
      debugPrint('🌐 [Web] Tap → proceeding to facial recognition');
      setState(() {
        _fpState = _FpState.scanning;
        _errorMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _navigateToFacialRecognition();
      return;
    }

    debugPrint('👆 [Native] _authenticate called');

    setState(() {
      _fpState = _FpState.scanning;
      _errorMessage = null;
    });

    await _authenticateNative();
  }

  Future<void> _authenticateNative() async {
    debugPrint('📱 Native: Starting biometric authentication');

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      debugPrint('📱 canCheck=$canCheck, isSupported=$isSupported');

      if (!canCheck || !isSupported) {
        debugPrint('❌ Device not supported for biometrics');
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'This device does not support fingerprint sensors.\n'
                'Proceeding to facial recognition...');
        return;
      }

      final enrolled = await _localAuth.getAvailableBiometrics();
      debugPrint('📱 Enrolled biometrics: $enrolled');

      if (enrolled.isEmpty) {
        debugPrint('❌ No enrolled fingerprints');
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'No fingerprint enrolled in device settings.\n'
                'Proceeding to facial recognition...');
        return;
      }

      debugPrint('📱 Triggering native biometric prompt...');

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your fingerprint to clock in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      debugPrint('📱 Authenticated: $authenticated');

      if (authenticated) {
        await _onSuccess();
      } else {
        if (!mounted) return;
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
      }
    } catch (e) {
      final msg = e.toString();
      debugPrint('❌ Native biometric error: $msg');

      if (msg.contains('no_fragment_activity') ||
          msg.contains('NotAvailable') ||
          msg.contains('NotEnrolled')) {
        if (!mounted) return;
        await _autoProceedToFaceScan(
            'Fingerprint not available.\n'
                'Proceeding to facial recognition...');
      } else if (msg.contains('LockedOut') ||
          msg.contains('PermanentlyLockedOut')) {
        _onFailure(
          'Too many attempts.\n'
              'Try again later or use another method.',
        );
      } else if (msg.contains('UserCancel') || msg.contains('canceled')) {
        if (!mounted) return;
        setState(() {
          _fpState = _FpState.idle;
          _errorMessage = null;
        });
      } else {
        _onFailure('Biometric error: $msg');
      }
    }
  }

  Future<void> _autoProceedToFaceScan(String message) async {
    if (!mounted) return;
    setState(() {
      _fpState = _FpState.idle;
      _errorMessage = message;
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    _navigateToFacialRecognition();
  }

  // ═══════════════════════════════════════════════════════════════
  // SUCCESS — reset state BEFORE navigating
  // ═══════════════════════════════════════════════════════════════
  Future<void> _onSuccess() async {
    if (!mounted) return;
    setState(() {
      _fpState = _FpState.success;
      _errorMessage = null;
    });
    _pulseCtrl.stop();
    _ringCtrl.stop();
    _successCtrl.forward();

    try {
      await FirebaseFirestore.instance.collection('activity logs').add({
        'type': 'fingerprint_verified',
        'employeeId': widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email': widget.employee.email,
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (e) {
      debugPrint('⚠️ Log save failed: $e');
    }

    if (!mounted) return;

    _navTimer?.cancel();
    _navTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;

      setState(() {
        _fpState = _FpState.idle;
        _errorMessage = null;
      });
      _successCtrl.reset();
      _pulseCtrl.repeat(reverse: true);
      _ringCtrl.repeat();

      _navigateToFacialRecognition();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // NAVIGATION — push so user can go back
  // ═══════════════════════════════════════════════════════════════
  void _navigateToFacialRecognition() {
    if (!mounted) return;

    debugPrint('➡️ [FingerprintScreen] → FacialRecognitionScreen (push)');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FacialRecognitionScreen(
          employee: widget.employee,
          arrivalTime: widget.arrivalTime,
        ),
      ),
    );
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

  // ═══════════════════════════════════════════════════════════════
  // BACK
  // ═══════════════════════════════════════════════════════════════
  void _goBack() {
    _navTimer?.cancel();
    _navTimer = null;

    if (_fpState == _FpState.success) {
      debugPrint('🔄 [FingerprintScreen] Resetting success state on Back');
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
    } else {
      debugPrint('⚠️ [FingerprintScreen] Nothing to go back to');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final fadeAnim = _fadeAnim ?? const AlwaysStoppedAnimation(1.0);

    return Scaffold(
      body: FadeTransition(
        opacity: fadeAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = _buildContent(tc);

            if (constraints.maxWidth < 768) {
              return content;
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
                  child: BsContainer(
                    maxWidth: 480,
                    child: content,
                  ),
                ),
              ],
            );
          },
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tc.bgTop, tc.bgMid, tc.bgBottom],
          stops: const [0.0, 0.6, 1.0],
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
                    const Text('Auth & Clock In',
                        style: TextStyle(
                            color: _white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('Select your initial verification method',
                        style: TextStyle(color: _white, fontSize: 14)),
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
                  Text('Step 1: Initial Login',
                      style: TextStyle(
                          color: tc.textDark,
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
          border: Border.all(color: tc.cardBorder, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.cardBorder, width: 1.5),
            ),
            child: Icon(icon, color: _orange, size: 24),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 338),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_modalGradTop, _modalGradMid, _modalGradEnd],
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
        _buildIcon(),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(_stateTitle,
              key: ValueKey(_fpState),
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
          child: Text(_errorMessage ?? _stateSubtitle,
              key: ValueKey('sub_${_errorMessage ?? _fpState}'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _white70, fontSize: 14, height: 1.4)),
        ),
        const SizedBox(height: 28),

        // ✅ Cancel button — native lang (sa web, tap lang ang icon)
        if (!kIsWeb &&
            (_fpState == _FpState.idle || _fpState == _FpState.error))
          _buildCancelButton(),
      ]),
    );
  }

  Widget _buildIcon() {
    Color iconColor;
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

    final pulseAnim = _pulseAnim ?? const AlwaysStoppedAnimation(1.0);
    final ringAnim = _ringAnim ?? const AlwaysStoppedAnimation(0.0);
    final successAnim = _successAnim ?? const AlwaysStoppedAnimation(0.0);
    final shakeAnim = _shakeAnim ?? const AlwaysStoppedAnimation(0.0);

    final canTap =
    (_fpState == _FpState.idle || _fpState == _FpState.error);

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
              if (_fpState == _FpState.scanning)
                Transform.rotate(
                  angle: ringAnim.value * 2 * math.pi,
                  child: CustomPaint(
                    size: const Size(132, 132),
                    painter: _DashRingPainter(
                        color: _white.withValues(alpha: 0.5), dashCount: 14),
                  ),
                ),
              if (_fpState != _FpState.success)
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
                        ? Border.all(color: _successRing, width: 3)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _fpState == _FpState.success
                      ? Icon(Icons.verified_user_rounded,
                      color: iconColor, size: 46)
                      : Icon(Icons.fingerprint_rounded,
                      color: iconColor, size: 48),
                ),
              ),
            ]),
          ),
        );
      },
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
          border: Border.all(color: _cancelBorder, width: 1.15),
        ),
        child: Center(
          child: Text(
            'Cancel Authentication',
            style: const TextStyle(
              color: _cancelText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
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
    _navigateToFacialRecognition();
  }

  String get _stateTitle {
    switch (_fpState) {
      case _FpState.idle:
        return 'Fingerprint Required';
      case _FpState.scanning:
        return 'Scanning\nFingerprint...';
      case _FpState.success:
        return 'Details\nAnalyzed';
      case _FpState.error:
        return 'Try Again';
    }
  }

  String get _stateSubtitle {
    switch (_fpState) {
      case _FpState.idle:
        return 'Tap the scanner icon to proceed';
      case _FpState.scanning:
        return kIsWeb
            ? 'Preparing camera...'
            : 'Analyzing biometric data...';
      case _FpState.success:
        return 'Biometric match confirmed. Preparing\ncamera...';
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