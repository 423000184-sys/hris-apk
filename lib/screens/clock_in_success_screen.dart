// lib/screens/clock_in_success_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/employee.dart';

// ══════════════════════════════════════════════════════════════
// THEME COLORS — mirrors DashboardScreen._ThemeColors
// ══════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get cardFill => isDark
      ? const Color(0xFF1F1F23)
      : const Color.fromRGBO(131, 131, 131, 0.07);
  Color get darkBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
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

  // ══════════════════════════════════════════════════════════════
  // COLORS — exact from HTML design (success modal stays same)
  // ══════════════════════════════════════════════════════════════
  static const _neonGreen = Color(0xFF51FF00);
  static const _cardBorder = Color(0xFF27272A);
  static const _subtitleColor = Color(0xFFDFDFDF);
  static const _backdropBase = Color(0xFF09090B);
  static const double _backdropAlpha = 0.44;

  // Gradient: #ff8a00 (0%), #fa6a00 (50%), #f54900 (100%)
  static const _gradTop = Color(0xFFFF8A00);
  static const _gradMid = Color(0xFFFA6A00);
  static const _gradEnd = Color(0xFFF54900);

  // Background header colors (behind dim overlay)
  static const _headerStart = Color(0xFFFF8A00);
  static const _headerMid = Color(0xFFFF6B00);
  static const _headerEnd = Color(0xFFF54900);
  static const _cardBorderLight = Color(0xFFFDBA74);
  static const _optionOrange = Color(0xFFF97316);

  // ══════════════════════════════════════════════════════════════
  // DESIGN FRAME MEASUREMENTS — from HTML mockup
  // ══════════════════════════════════════════════════════════════
  static const double _designCardW = 338.14;
  static const double _designCardH = 343.03;
  static const double _designIconSize = 112.0;
  static const double _designIconLeft = 113.06;
  static const double _designIconTop = 33.15;
  static const double _designTitleTop = 177.13;
  static const double _designTitleLeft = 33.15;
  static const double _designTitleW = 271.84;
  static const double _designTitleH = 66.0;
  static const double _designTitleFontSize = 30.0;
  static const double _designSubtitleTop = 255.14;
  static const double _designSubtitleLeft = 60.75;
  static const double _designSubtitleW = 216.63;
  static const double _designSubtitleFontSize = 14.0;
  static const double _designBorderWidth = 1.15;
  static const double _designRadius = 16.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();
    _redirectTimer = Timer(widget.autoRedirectDelay, _handleContinue);
  }

  void _handleContinue() {
    if (_didRedirect) return;
    _didRedirect = true;
    if (!mounted) return;
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: tc.bg,
        body: Stack(
          children: [
            // Dimmed background — recreates previous screen
            Positioned.fill(
              child: Opacity(
                opacity: 0.55,
                child: IgnorePointer(child: _buildDimmedBackground(tc)),
              ),
            ),
            // Dark Overlay Backdrop (rgba(9,9,11,0.44))
            Positioned.fill(
              child: GestureDetector(
                onTap: _handleContinue,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: _backdropBase.withValues(alpha: _backdropAlpha),
                ),
              ),
            ),
            // Centered Modal Card
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.of(context).size.width - 48;

                    double scale = availableWidth / _designCardW;
                    if (scale > 1.25) scale = 1.25;
                    if (scale <= 0) scale = 1.0;

                    return FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        child: GestureDetector(
                          onTap: _handleContinue,
                          child: _buildSuccessCard(scale),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DIMMED BACKGROUND — recreates "Auth & Clock In" screen
  // (now theme-aware for dark mode)
  // ══════════════════════════════════════════════════════════════
  Widget _buildDimmedBackground(_ThemeColors tc) {
    return Container(
      color: tc.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header keeps orange gradient in both themes (brand color)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_headerStart, _headerMid, _headerEnd],
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
                  children: const [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left_rounded,
                            color: Colors.white, size: 22),
                        SizedBox(width: 4),
                        Text('Back',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 20),
                    Text('Auth & Clock In',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    SizedBox(height: 6),
                    Text('Select your initial verification method',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
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
                  color: tc.cardFill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: tc.darkBorder.withValues(alpha: 0.4),
                    width: 1,
                  ),
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
          color: tc.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _cardBorderLight.withValues(alpha: tc.isDark ? 0.6 : 1.0),
            width: 1.5,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _cardBorderLight.withValues(alpha: tc.isDark ? 0.6 : 1.0),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: _optionOrange, size: 24),
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

  // ══════════════════════════════════════════════════════════════
  // SUCCESS CARD — stays identical in both themes (brand gradient)
  // ══════════════════════════════════════════════════════════════
  Widget _buildSuccessCard(double scale) {
    final isClockIn = widget.type.toUpperCase() == 'IN';
    final accent = isClockIn ? _neonGreen : const Color(0xFFC4FF0A);
    final title = isClockIn ? 'Verified &\nClocked In!' : 'Clocked Out!';
    final subtitle = widget.subtitle ??
        (isClockIn
            ? 'Starting your shift and redirecting...'
            : 'Ending your shift and redirecting...');

    final cardW = _designCardW * scale;
    final cardH = _designCardH * scale;

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_designRadius * scale),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_gradTop, _gradMid, _gradEnd],
          stops: [0.0, 0.5, 1.0],
        ),
        border: Border.all(
          color: _cardBorder,
          width: _designBorderWidth * scale,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10 * scale,
            offset: Offset(0, 12.5 * scale),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Check icon (white rounded box + neon border + check)
          Positioned(
            top: _designIconTop * scale,
            left: _designIconLeft * scale,
            child: SizedBox(
              width: _designIconSize * scale,
              height: _designIconSize * scale,
              child: CustomPaint(
                painter: _CheckIconPainter(color: accent),
              ),
            ),
          ),
          // Success Title Text
          Positioned(
            top: _designTitleTop * scale,
            left: _designTitleLeft * scale,
            width: _designTitleW * scale,
            height: _designTitleH * scale,
            child: Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: _designTitleFontSize * scale,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
          // Subtitle Text
          Positioned(
            top: _designSubtitleTop * scale,
            left: _designSubtitleLeft * scale,
            width: _designSubtitleW * scale,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _subtitleColor,
                fontSize: _designSubtitleFontSize * scale,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CHECK ICON PAINTER — exact SVG from HTML design
// ══════════════════════════════════════════════════════════════
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
        1.5 * scale,
        1.5 * scale,
        110.496 * scale,
        110.496 * scale,
      ),
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

    // Inner Circle
    canvas.drawCircle(
      Offset(55.989 * scale, 55.989 * scale),
      19.998 * scale,
      strokePaint,
    );

    // Inner Checkmark Path
    final checkPath = Path()
      ..moveTo(49.9897 * scale, 55.9889 * scale)
      ..lineTo(53.9894 * scale, 59.9886 * scale)
      ..lineTo(61.9887 * scale, 51.9893 * scale);
    canvas.drawPath(checkPath, strokePaint);
  }

  @override
  bool shouldRepaint(_CheckIconPainter old) => old.color != color;
}