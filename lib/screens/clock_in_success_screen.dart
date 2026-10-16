// lib/screens/clock_in_success_screen.dart
// ═══════════════════════════════════════════════════════════════════
// CLOCK IN SUCCESS SCREEN  v1.3
//   - Demo mode: walang Firestore write, DEMO badge
//   - onContinue() navigation ang tumatawag (hindi auto-pop)
//   - ✅ v1.3: Adaptive Light/Dark mode support
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../data/local/dao/connectivity_service.dart';
import '../services/demo_mode_service.dart';

// ═══════════════════════════════════════════════════════════════════
// 🎨 ADAPTIVE THEME COLORS
// ═══════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  // Backgrounds
  Color get scaffoldBg => isDark ? const Color(0xFF0A0A0A) : Colors.white;
  Color get bgLayer => isDark ? const Color(0xFF0F0D0B) : Colors.white;
  Color get scrim =>
      isDark ? Colors.black.withOpacity(0.55) : const Color(0xFF09090B).withOpacity(0.44);

  // Cards
  Color get cardBg => isDark ? const Color(0xFF18181B) : Colors.white;
  Color get cardBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFFFFA500);
  Color get methodIconBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFF8FAFC);

  // Text
  Color get textDark => isDark ? Colors.white : const Color(0xFF0F172A);
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);

  // Watermark
  double get watermarkOpacity => isDark ? 0.15 : 0.80;
  double get topWatermarkOpacity => isDark ? 0.08 : 0.25;
}

class ClockInSuccessScreen extends StatefulWidget {
  final Employee? employee;
  final DateTime? arrivalTime;
  final double? faceMatchPercent;
  final String? verificationMethod;
  final String? subtitle;
  final String type;
  final VoidCallback? onContinue;
  final Duration autoRedirectDelay;
  final String? locationName;
  final String? attendanceLogId;
  final String? transactionId;

  const ClockInSuccessScreen({
    super.key,
    this.employee,
    this.arrivalTime,
    this.faceMatchPercent,
    this.verificationMethod,
    this.subtitle,
    this.type = 'IN',
    this.onContinue,
    this.autoRedirectDelay = const Duration(milliseconds: 2200),
    this.locationName,
    this.attendanceLogId,
    this.transactionId,
  });

  @override
  State<ClockInSuccessScreen> createState() => _ClockInSuccessScreenState();
}

class _ClockInSuccessScreenState extends State<ClockInSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  Timer? _redirectTimer;
  bool _didRedirect = false;
  bool _isHandlingContinue = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _networkSub;

  static const String _kReceiptSecretKey = 'receipt_signing_secret';
  static const String _logoAsset = 'assets/images/logo.png';
  late final String _sessionNonce;
  late final String _transactionId;
  String? _receiptHash;
  DateTime? _receiptGeneratedAt;

  static const _neonGreen = Color(0xFF51FF00);
  static const _cardBorder = Color(0xFF27272A);
  static const _subtitleColor = Color(0xFFDFDFDF);
  static const _gradTop = Color(0xFFFF8A00);
  static const _gradMid = Color(0xFFFA6A00);
  static const _gradEnd = Color(0xFFF54900);

  static const double _designCardW = 338.14;
  static const double _designCardH = 343.03;
  static const double _designIconSize = 112.0;
  static const double _designIconTop = 33.15;
  static const double _designTitleTop = 177.13;
  static const double _designSubtitleTop = 255.14;
  static const double _designBorderWidth = 1.15;
  static const double _designRadius = 16.0;
  static const double _designTitleHMargin = 33.15;
  static const double _designSubtitleHMargin = 60.75;

  static const double _authHeaderH = 287.13;
  static const double _authHeaderRadius = 16.0;
  static const double _authHeaderBorderW = 1.15;
  static const Color _authHeaderBorderColor = Color(0xFF382A20);
  static const Color _authOrangeBorder = Color(0xFFFFA500);
  static const double _stepCardTop = 191.14;
  static const double _stepCardHPad = 24.0;

  bool get _isDemo => DemoModeService.instance.isEnabled;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    _sessionNonce = _generateSessionNonce();
    _transactionId = widget.transactionId ??
        widget.attendanceLogId ??
        _generateTransactionId();

    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();

    if (_isDemo) {
      _isOnline = true;
      debugPrint('🎭 [DemoMode] ClockInSuccess — DEMO, txn=$_transactionId');
    } else {
      try {
        _isOnline = ConnectivityService.instance.isOnline;
        _networkSub =
            ConnectivityService.instance.onStatusChange.listen((online) {
              if (!mounted) return;
              setState(() => _isOnline = online);
            });
      } catch (e) {
        debugPrint('⚠️ connectivity listen failed: $e');
      }
    }

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _generateReceipt();
    if (!mounted) return;
    _scheduleRedirect();
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _generateTransactionId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = math.Random.secure();
    final randHex = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final prefix = _isDemo ? 'DEMO-TXN' : 'TXN';
    return '$prefix-$ts-$randHex';
  }

  Future<void> _generateReceipt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secret = prefs.getString(_kReceiptSecretKey) ?? _makeNewSecret();
      if (prefs.getString(_kReceiptSecretKey) == null) {
        await prefs.setString(_kReceiptSecretKey, secret);
      }
      _receiptGeneratedAt = DateTime.now();
      final payload = <String, dynamic>{
        'txnId': _transactionId,
        'nonce': _sessionNonce,
        'employeeId': widget.employee?.id ?? '',
        'type': widget.type,
        'method': widget.verificationMethod ?? '',
        'facePercent': widget.faceMatchPercent ?? 0,
        'location': widget.locationName ?? '',
        'arrivalMs': widget.arrivalTime?.millisecondsSinceEpoch ?? 0,
        'generatedMs': _receiptGeneratedAt!.millisecondsSinceEpoch,
        'demoMode': _isDemo,
      };
      _receiptHash =
          sha256.convert(utf8.encode(jsonEncode(payload))).toString();

      if (_isDemo || DemoModeService.instance.shouldSkipDbWrite) {
        debugPrint('🎭 [DemoMode] Receipt local only — $_transactionId');
        return;
      }

      if (_isOnline && widget.employee != null) {
        try {
          await FirebaseFirestore.instance
              .collection('attendance_receipts')
              .doc(_transactionId)
              .set({
            'transactionId': _transactionId,
            'sessionNonce': _sessionNonce,
            'receiptHash': _receiptHash,
            'employeeId': widget.employee!.id,
            'employeeName': widget.employee!.fullName,
            'employeeEmail': widget.employee!.email,
            'type': widget.type,
            'method': widget.verificationMethod,
            'facePercent': widget.faceMatchPercent,
            'locationName': widget.locationName,
            'arrivalTime': widget.arrivalTime,
            'generatedAt': FieldValue.serverTimestamp(),
            'platform': kIsWeb ? 'web' : 'mobile',
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('⚠️ Receipt save failed: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Receipt generation failed: $e');
    }
  }

  String _makeNewSecret() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _scheduleRedirect() {
    _redirectTimer?.cancel();
    _redirectTimer = Timer(widget.autoRedirectDelay, _handleContinue);
  }

  Future<void> _logConfirm() async {
    if (_isDemo || DemoModeService.instance.shouldSkipDbWrite) {
      debugPrint('🎭 [DemoMode] Confirm skipped: $_transactionId');
      return;
    }
    if (!_isOnline || widget.employee == null) return;
    try {
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'clock_in_confirmed',
        'severity': 'info',
        'details': 'User confirmed — ${widget.type} via '
            '${widget.verificationMethod ?? "unknown"}',
        'employeeId': widget.employee!.id,
        'employeeName': widget.employee!.fullName,
        'transactionId': _transactionId,
        'sessionNonce': _sessionNonce,
        'receiptHash': _receiptHash,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'clock_in_success',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ Log confirm error: $e');
    }
  }

  void _handleContinue() {
    if (_isHandlingContinue || _didRedirect) return;
    _isHandlingContinue = true;
    _didRedirect = true;
    if (!mounted) return;
    unawaited(_logConfirm());
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _networkSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleContinue();
      },
      child: Scaffold(
        backgroundColor: tc.scaffoldBg,
        body: Stack(
          children: [
            Positioned.fill(child: _buildAuthBackground(tc)),
            Positioned.fill(
              child: Container(color: tc.scrim),
            ),
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: GestureDetector(
                    onTap: _handleContinue,
                    child: _buildSuccessCard(),
                  ),
                ),
              ),
            ),
            if (_isDemo)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 0,
                child: Center(child: _buildDemoBadge()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF54900),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: Colors.white.withOpacity(0.55), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.science_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            'DEMO MODE — No DB Write',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthBackground(_ThemeColors tc) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ✅ Adaptive background
        Positioned.fill(child: Container(color: tc.scaffoldBg)),

        // Top watermark — subtle in both modes
        Positioned(
          top: -180,
          right: -200,
          child: Transform.rotate(
            angle: _degToRad(270),
            child: Opacity(
              opacity: tc.topWatermarkOpacity,
              child: Image.asset(_logoAsset,
                  width: 600, height: 600, fit: BoxFit.contain),
            ),
          ),
        ),

        // Bottom watermark — orange tinted
        Positioned(
          bottom: -130,
          left: -150,
          child: Transform.rotate(
            angle: _degToRad(425),
            child: Opacity(
              opacity: tc.watermarkOpacity,
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                    Color.fromRGBO(255, 138, 0, 0.10), BlendMode.srcIn),
                child: Image.asset(_logoAsset,
                    width: 500, height: 500, fit: BoxFit.contain),
              ),
            ),
          ),
        ),

        // Orange auth header — SAME in both modes
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _authHeaderH,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_gradTop, Color(0xFFFF6B00), _gradEnd],
                stops: [0.0001, 0.3318, 1.0],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(_authHeaderRadius),
                bottomRight: Radius.circular(_authHeaderRadius),
              ),
              border: Border(
                bottom: BorderSide(
                    color: _authHeaderBorderColor,
                    width: _authHeaderBorderW),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 24,
                  top: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 19.99,
                        height: 19.99,
                        child: CustomPaint(painter: _BackArrowPainter()),
                      ),
                      const SizedBox(width: 2),
                      const Text('Back',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 0.9)),
                    ],
                  ),
                ),
                const Positioned(
                  left: 24,
                  top: 95.99,
                  child: Text('Auth & Clock In',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          height: 0.9)),
                ),
                const Positioned(
                  left: 24,
                  top: 136.99,
                  child: Text('Select your initial verification method',
                      style: TextStyle(
                          color: Colors.white, fontSize: 14, height: 0.9)),
                ),
              ],
            ),
          ),
        ),

        // Step 1 card — adaptive
        Positioned(
          top: _stepCardTop,
          left: _stepCardHPad,
          right: _stepCardHPad,
          child: _buildStep1Card(tc),
        ),
      ],
    );
  }

  Widget _buildStep1Card(_ThemeColors tc) {
    return Container(
      height: 234.38,
      padding: const EdgeInsets.fromLTRB(25.1, 25.1, 25.1, 1.11),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _authOrangeBorder, width: 1.11),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(tc.isDark ? 0.25 : 0.05),
              blurRadius: 3,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 20.99,
            child: Center(
              child: Text('Step 1: Initial Login',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: tc.textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 23.99),
          SizedBox(
            height: 139.18,
            child: Row(
              children: [
                Expanded(
                  child: _buildMethodCard(
                      label: 'Key Fob',
                      icon: Icons.contactless_rounded,
                      tc: tc),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMethodCard(
                      label: 'Use PIN',
                      icon: Icons.key_rounded,
                      tc: tc),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required String label,
    required IconData icon,
    required _ThemeColors tc,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _authOrangeBorder, width: 1.11),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 55.99,
            height: 55.99,
            decoration: BoxDecoration(
              color: tc.methodIconBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _authOrangeBorder, width: 1),
            ),
            child: const Icon(Icons.key_rounded,
                color: Color(0xFFFB923C), size: 0),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(
                  color: tc.textDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    final isClockIn = widget.type.toUpperCase() == 'IN';
    final accent = isClockIn ? _neonGreen : const Color(0xFFC4FF0A);
    final title = isClockIn ? 'Verified &\nClocked In!' : 'Clocked Out!';
    final subtitle = widget.subtitle ??
        (isClockIn
            ? 'Starting your shift and redirecting...'
            : 'Ending your shift and redirecting...');

    final cardW =
    math.min(MediaQuery.of(context).size.width - 48, _designCardW);

    return Container(
      width: cardW,
      height: _designCardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_designRadius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_gradTop, _gradMid, _gradEnd],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(color: _cardBorder, width: _designBorderWidth),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 12.5)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: _designIconTop,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: _designIconSize,
                height: _designIconSize,
                child: CustomPaint(
                    painter: _CheckIconPainter(color: accent)),
              ),
            ),
          ),
          Positioned(
            top: _designTitleTop,
            left: _designTitleHMargin,
            right: _designTitleHMargin,
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    height: 1.1)),
          ),
          Positioned(
            top: _designSubtitleTop,
            left: _designSubtitleHMargin,
            right: _designSubtitleHMargin,
            child: Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _subtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.4)),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isDemo
                        ? Icons.science_rounded
                        : Icons.verified_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 9,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _isDemo ? 'DEMO' : 'VERIFIED',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(child: _buildBottomBadge()),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBadge() {
    if (_isDemo) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _neonGreen.withOpacity(0.7), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_rounded,
                color: _neonGreen, size: 11),
            const SizedBox(width: 5),
            Text(
              'Demo — no DB write',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 9,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    if (!_isOnline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(20),
          border:
          Border.all(color: Colors.white.withOpacity(0.35), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                color: Colors.white.withOpacity(0.9), size: 11),
            const SizedBox(width: 5),
            Text(
              'Saved offline — will sync later',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 9,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

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

class _CheckIconPainter extends CustomPainter {
  final Color color;
  const _CheckIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const svgSize = 112.0;
    final scale = size.width / svgSize;

    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 3.0 * scale
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
          1.5 * scale, 1.5 * scale, 110.496 * scale, 110.496 * scale),
      Radius.circular(14.5 * scale),
    );
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 3.99965 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(Offset(55.989 * scale, 55.989 * scale),
        19.998 * scale, strokePaint);

    final checkPath = Path()
      ..moveTo(49.9897 * scale, 55.9889 * scale)
      ..lineTo(53.9894 * scale, 59.9886 * scale)
      ..lineTo(61.9887 * scale, 51.9893 * scale);
    canvas.drawPath(checkPath, strokePaint);
  }

  @override
  bool shouldRepaint(_CheckIconPainter old) => old.color != color;
}