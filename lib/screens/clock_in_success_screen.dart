// lib/screens/clock_in_success_screen.dart
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

  // ═══════════════════════════════════════════════════════════════
  // Design tokens — mula sa HTML mockup (exact coordinates)
  // ═══════════════════════════════════════════════════════════════
  static const double _designCardW = 338.14;
  static const double _designCardH = 343.03;
  static const double _designIconSize = 112.0;
  static const double _designIconTop = 33.15;
  static const double _designTitleTop = 177.13;
  static const double _designSubtitleTop = 255.14;
  static const double _designBorderWidth = 1.15;
  static const double _designRadius = 16.0;

  // Horizontal margins mula sa HTML (left/right ng bawat element)
  static const double _designTitleHMargin = 33.15;
  static const double _designSubtitleHMargin = 60.75;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
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
    return 'TXN-$ts-$randHex';
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
      };
      _receiptHash =
          sha256.convert(utf8.encode(jsonEncode(payload))).toString();

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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleContinue();
      },
      child: Scaffold(
        // Transparent — ang dark overlay ay galing sa
        // PageRouteBuilder.barrierColor ng nag-navigate na screen
        backgroundColor: Colors.transparent,
        body: Center(
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
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SUCCESS CARD — Positioned layout para tumugma sa HTML design
  // ═══════════════════════════════════════════════════════════════
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
            offset: const Offset(0, 12.5),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ─── ICON — center horizontally, top: 33.15 ───
          Positioned(
            top: _designIconTop,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: _designIconSize,
                height: _designIconSize,
                child: CustomPaint(
                  painter: _CheckIconPainter(color: accent),
                ),
              ),
            ),
          ),

          // ─── TITLE — center horizontally, top: 177.13 ───
          Positioned(
            top: _designTitleTop,
            left: _designTitleHMargin,
            right: _designTitleHMargin,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w500,
                height: 1.1,
              ),
            ),
          ),

          // ─── SUBTITLE — center horizontally, top: 255.14 ───
          Positioned(
            top: _designSubtitleTop,
            left: _designSubtitleHMargin,
            right: _designSubtitleHMargin,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _subtitleColor,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),

          // ─── VERIFIED badge — top-right ───
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded,
                      color: Colors.white.withOpacity(0.7), size: 9),
                  const SizedBox(width: 3),
                  Text(
                    'VERIFIED',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── OFFLINE badge — bottom-center, kapag offline lang ───
          if (!_isOnline)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.35),
                      width: 1,
                    ),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CHECK ICON PAINTER — eksaktong tugma sa SVG sa HTML
// ═══════════════════════════════════════════════════════════════════
class _CheckIconPainter extends CustomPainter {
  final Color color;
  const _CheckIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Ang SVG viewBox ay 112x112. Ang paths ay may bounds
    // mula (1.5, 1.5) hanggang (110.496, 110.496). Kaya ang
    // scale ay base sa 112 (ang viewBox).
    const svgSize = 112.0;
    final scale = size.width / svgSize;

    // ─── Rounded rectangle (background + border) ───
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = 3.0 * scale
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        1.5 * scale,
        1.5 * scale,
        110.496 * scale,
        110.496 * scale,
      ),
      Radius.circular(14.5 * scale),
    );
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, borderPaint);

    // ─── Circle + checkmark ───
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 3.99965 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(
      Offset(55.989 * scale, 55.989 * scale),
      19.998 * scale,
      strokePaint,
    );

    final checkPath = Path()
      ..moveTo(49.9897 * scale, 55.9889 * scale)
      ..lineTo(53.9894 * scale, 59.9886 * scale)
      ..lineTo(61.9887 * scale, 51.9893 * scale);
    canvas.drawPath(checkPath, strokePaint);
  }

  @override
  bool shouldRepaint(_CheckIconPainter old) => old.color != color;
}