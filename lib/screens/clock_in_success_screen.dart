import 'dart:async';
import 'package:flutter/material.dart';
import '../models/employee.dart';

/// Reference frame width used in the original HTML/Figma design
/// (the mockup phone frame was 399.99px wide with 6.93px border,
/// giving an inner content width of 386.13px).
const double _kDesignFrameWidth = 386.13;

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

  // ---- Exact colors from the HTML design ----
  static const _neonGreen = Color(0xFF51FF00);
  static const _cardBorder = Color(0xFF27272A);
  static const _subtitleColor = Color(0xFFDFDFDF);
  static const _backdropBase = Color(0xFF09090B);
  static const double _backdropAlpha = 0.44;

  // Gradient: #ff8a00 (0%), #fa6a00 (50%), #f54900 (100%)
  static const _gradTop = Color(0xFFFF8A00);
  static const _gradMid = Color(0xFFFA6A00);
  static const _gradEnd = Color(0xFFF54900);

  // ---- Design-frame (399.99px mockup) reference measurements ----
  // These are the RAW numbers from the HTML. We no longer use them
  // directly as pixel values — instead everything is scaled against
  // _kDesignFrameWidth so the card looks identical on any real device.
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

  // ---- Colors for the dimmed background behind the modal ----
  static const _headerStart = Color(0xFFFF8A00);
  static const _headerMid = Color(0xFFFF6B00);
  static const _headerEnd = Color(0xFFF54900);
  static const _cardBorderLight = Color(0xFFFDBA74);
  static const _optionOrange = Color(0xFFF97316);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // "Auth & Clock In" screen recreated as a static, dimmed
            // background — since ClockInSuccessScreen is usually reached
            // via pushReplacement, there's nothing left underneath it.
            // This matches the HTML design where the previous screen is
            // still visible (dimmed) behind the success overlay.
            Positioned.fill(
              child: Opacity(
                opacity: 0.55,
                child: IgnorePointer(child: _buildDimmedBackground()),
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
                    // Available width after the 24px horizontal padding
                    // on each side (matches the HTML's own padding).
                    final availableWidth = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : MediaQuery.of(context).size.width - 48;

                    // Scale factor relative to the original design frame.
                    // Cap it so the card doesn't blow up on tablets/web.
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

  /// Recreates the "Auth & Clock In" header + "Step 1: Initial Login"
  /// card, purely as decorative background content. It is not tappable
  /// (wrapped in IgnorePointer by the caller) — its only job is to make
  /// the success screen look like it's overlaid on top of the previous
  /// step, matching the HTML design.
  Widget _buildDimmedBackground() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(children: [
                  const Text('Step 1: Initial Login',
                      style: TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: _dimmedOptionPlaceholder(
                            Icons.contactless_rounded, 'Key Fob')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _dimmedOptionPlaceholder(
                            Icons.key_rounded, 'Use PIN')),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorderLight, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _cardBorderLight, width: 1.5),
            ),
            child: Icon(icon, color: _optionOrange, size: 24),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

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

/// Renders the exact SVG check icon from the HTML design:
/// white rounded box, neon-green rounded border, neon-green
/// circle + checkmark inside.
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