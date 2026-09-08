import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/geofence_service.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Design Tokens
// ═══════════════════════════════════════════════════════════════════════════
class _T {
  static const Color orange   = Color(0xFFFF6B00);
  static const Color bg       = Color(0xFF0A0A0A);
  static const Color bgCard   = Color(0xFF111111);
  static const Color bgCircle = Color(0xFF1A1000);
  static const Color white    = Color(0xFFFFFFFF);
  static const Color white70  = Color(0xB3FFFFFF);
  static const Color white40  = Color(0x66FFFFFF);
  static const Color white15  = Color(0x26FFFFFF);
  static const Color deny     = Color(0xFFFF2244);
  static const Color success  = Color(0xFF22DD66);
}

// ═══════════════════════════════════════════════════════════════════════════
// LandingScreen
// ═══════════════════════════════════════════════════════════════════════════
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late AnimationController _radarCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _radarAnim;
  late Animation<double>   _fadeAnim;

  GeofenceResult? _geoResult;
  bool _geoChecking = true;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _fadeCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();

    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _radarAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_radarCtrl);
    _fadeAnim  = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: _T.orange,
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _runGeoCheck();
  }

  // ✅ Now uses GeofenceService — single source of truth
  Future<void> _runGeoCheck() async {
    if (mounted) setState(() => _geoChecking = true);
    final result = await GeofenceService.instance.checkGeofence();
    if (mounted) setState(() { _geoResult = result; _geoChecking = false; });
  }

  void _onGetStarted() {
    if (_geoChecking) { _snack('Verifying your location…'); return; }
    if (!(_geoResult?.isInside ?? false)) {
      final dist = _geoResult?.distanceMeters;
      _snack(dist != null
          ? 'You are ${dist.toStringAsFixed(0)} m from the office zone.'
          : _geoResult?.message ?? 'Outside work zone');
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: _T.white, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF1E1000),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      action: SnackBarAction(label: 'RETRY', textColor: _T.orange, onPressed: _runGeoCheck),
    ));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _radarCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildNavbar(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(),
                  _buildWorkingZoneSection(),
                  _buildCTAButton(),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── NAVBAR ──────────────────────────────────────────────────────────────────
  Widget _buildNavbar() {
    final bool isBlocked = _geoChecking || !(_geoResult?.isInside ?? false);

    return Container(
      color: _T.orange,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                ),
                child: const Center(
                  child: Text('✋', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'R.A.C.O.M.A',
                style: TextStyle(
                  color: _T.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              // ✅ onTap is null when blocked = truly unclickable
              GestureDetector(
                onTap: isBlocked
                    ? null
                    : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBlocked ? _T.white40 : _T.white,
                      width: 1.5,
                    ),
                  ),
                  child: Text('Log In',
                      style: TextStyle(
                          color: isBlocked ? _T.white40 : _T.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HERO SECTION ────────────────────────────────────────────────────────────
  Widget _buildHeroSection() {
    final isInside   = _geoResult?.isInside ?? false;
    final isChecking = _geoChecking;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Circular Geofence Widget
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_pulseAnim, _radarAnim]),
              builder: (_, __) {
                final ringColor = isChecking
                    ? _T.orange.withValues(alpha: 0.5)
                    : isInside
                    ? _T.orange
                    : _T.deny;

                return Transform.scale(
                  scale: _pulseAnim.value,
                  child: Container(
                    width: 260, height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _T.bgCircle,
                      border: Border.all(color: ringColor, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: ringColor.withValues(alpha: 0.25),
                          blurRadius: 48,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(alignment: Alignment.center, children: [
                        CustomPaint(
                          size: const Size(260, 260),
                          painter: _RadarPainter(
                            progress: _radarAnim.value,
                            color: ringColor,
                            isChecking: isChecking,
                            isInside: isInside,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ringColor.withValues(alpha: 0.15),
                                border: Border.all(color: ringColor.withValues(alpha: 0.6), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: ringColor.withValues(alpha: 0.4),
                                    blurRadius: 24, spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isChecking
                                    ? Icons.gps_fixed_rounded
                                    : isInside
                                    ? Icons.business_rounded
                                    : Icons.location_off_rounded,
                                color: ringColor, size: 30,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              child: Text(
                                isChecking
                                    ? 'Locating…'
                                    : isInside
                                    ? 'Inside Authorized Zone'
                                    : 'Outside Work Zone',
                                key: ValueKey('$isChecking-$isInside'),
                                style: TextStyle(
                                  color: ringColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          // "Verified Location Tracking" pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _T.white15,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: _T.white15, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user_rounded, color: _T.orange, size: 14),
                const SizedBox(width: 6),
                const Text(
                  'Verified Location Tracking',
                  style: TextStyle(
                    color: _T.white70, fontSize: 12,
                    fontWeight: FontWeight.w600, letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Headline
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 40, fontWeight: FontWeight.w900,
                height: 1.1, letterSpacing: -1.0,
              ),
              children: [
                TextSpan(text: 'Clock in\n', style: TextStyle(color: _T.white)),
                TextSpan(
                  text: 'where it\nmatters.',
                  style: TextStyle(
                    color: _T.orange,
                    shadows: [Shadow(color: Color(0xAAFF6B00), blurRadius: 20)],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Seamless, location-based time tracking for modern teams. '
                'Automatically verify when you are on-site and ready to work, '
                'ensuring accurate logs and eliminating guesswork.',
            style: TextStyle(
              color: _T.white70, fontSize: 14.5,
              height: 1.65, fontWeight: FontWeight.w400, letterSpacing: 0.1,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── WORKING ZONE SECTION ────────────────────────────────────────────────────
  Widget _buildWorkingZoneSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.map_outlined, color: _T.orange, size: 20),
            const SizedBox(width: 8),
            const Text('The Working Zone',
                style: TextStyle(
                  color: _T.white, fontSize: 20,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3,
                )),
          ]),
          const SizedBox(height: 12),
          const Text(
            'Authorized working zones are defined geographical areas designated '
                'for your workplace. Once you enter the perimeter, our Live GPS system '
                'authenticates your location, enabling the Clock In feature securely.',
            style: TextStyle(
              color: _T.white70, fontSize: 14.5,
              height: 1.65, fontWeight: FontWeight.w400, letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _T.white15,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _T.orange.withValues(alpha: 0.25), width: 1),
            ),
            child: Row(children: [
              const Icon(Icons.location_pin, color: _T.orange, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${GeofenceService.officeAddress}  •  ${GeofenceService.officeLat}°N, ${GeofenceService.officeLng}°E',
                  style: const TextStyle(
                    color: _T.white70, fontSize: 12,
                    fontWeight: FontWeight.w500, letterSpacing: 0.2,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  // ── CTA BUTTON ──────────────────────────────────────────────────────────────
  Widget _buildCTAButton() {
    final isChecking = _geoChecking;
    final isAllowed  = _geoResult?.isInside ?? false;
    // ✅ blocked when NOT allowed OR still checking
    final blocked    = !isAllowed || isChecking;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // ✅ AbsorbPointer makes button truly unclickable when blocked
      child: AbsorbPointer(
        absorbing: blocked,
        child: GestureDetector(
          onTap: _onGetStarted,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: blocked ? const Color(0xFF2A2A2A) : _T.orange,
              borderRadius: BorderRadius.circular(14),
              boxShadow: blocked
                  ? []
                  : [BoxShadow(
                color: _T.orange.withValues(alpha: 0.45),
                blurRadius: 28, offset: const Offset(0, 8),
              )],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isChecking)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(color: _T.orange, strokeWidth: 2.5),
                  )
                else if (blocked)
                  const Icon(Icons.location_off_rounded, color: Color(0xFF888888), size: 18)
                else
                  const SizedBox.shrink(),
                const SizedBox(width: 8),
                Text(
                  isChecking ? 'Checking Location…' : blocked ? 'Outside Work Zone' : 'Get Started',
                  style: TextStyle(
                    color: blocked ? const Color(0xFF888888) : _T.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16, letterSpacing: 0.4,
                  ),
                ),
                if (!isChecking && !blocked) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, color: _T.white, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Radar Painter
// ═══════════════════════════════════════════════════════════════════════════
class _RadarPainter extends CustomPainter {
  final double progress;
  final Color  color;
  final bool   isChecking;
  final bool   isInside;

  const _RadarPainter({
    required this.progress, required this.color,
    required this.isChecking, required this.isInside,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(
        Offset(cx, cy), r * i / 3.5,
        Paint()
          ..color = color.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    final sweepAngle = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78),
      sweepAngle - 1.2, 1.2, true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle - 1.2,
          endAngle: sweepAngle,
          colors: [Colors.transparent, color.withValues(alpha: 0.18)],
          transform: GradientRotation(sweepAngle - 1.2),
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.78)),
    );

    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * 0.78 * math.cos(sweepAngle), cy + r * 0.78 * math.sin(sweepAngle)),
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    final dotX = cx + r * 0.78 * math.cos(sweepAngle);
    final dotY = cy + r * 0.78 * math.sin(sweepAngle);
    canvas.drawCircle(Offset(dotX, dotY), 3, Paint()..color = color.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.isInside != isInside;
}