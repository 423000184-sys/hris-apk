<<<<<<< HEAD
=======
import 'dart:math' as math;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/geofence_service.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
<<<<<<< HEAD
// Design Tokens — converted 1:1 from the new HTML mock
// ═══════════════════════════════════════════════════════════════════════════
class _T {
  // Header / brand (bg-gradient-to-t: f54900 -> ff6b00 -> ff8a00)
  static const Color headerStart = Color(0xFFF54900);
  static const Color headerMid   = Color(0xFFFF6B00);
  static const Color headerEnd   = Color(0xFFFF8A00);

  // Hero (light section)
  static const Color heroBgStart = Color(0xFFFFFFFF);
  static const Color heroBgEnd   = Color(0xFFFFF2EA);

  // Radar / zone circle — gradient fill + border
  static const Color circleGradTop    = Color.fromRGBO(255, 138, 0, 0.62);
  static const Color circleGradMid    = Color.fromRGBO(250, 106, 0, 0.62);
  static const Color circleGradBottom = Color.fromRGBO(245, 73, 0, 0.62);
  static const Color circleBorder     = Color(0xFFFF8C00);

  static const Color buildingBg   = Color(0xFFF59E0B); // amber-500
  static const Color labelLime    = Color(0xFFC2FF00); // circle caption text
  static const Color lime400      = Color(0xFFA3E635); // "Inside Authorized Zone" subtext
  static const Color green400     = Color(0xFF4ADE80); // live GPS pulse dot

  static const Color badgeBg   = Color(0xFFFF8904);
  static const Color heroTitle = Color(0xFF000000);
  static const Color heroDescGradStart = Color(0xFFEA580C); // orange-600
  static const Color heroDescGradEnd   = Color(0xFFF59E0B); // amber-500
  static const Color heroDesc  = Color(0xFF3F3F46); // zinc-700

  static const Color workZoneIcon = Color(0xFFEA580C); // orange-600

  static const Color ctaSolid = Color(0xFFFF6900);

  // Dashboard preview (dark section)
  static const Color dashCardBg   = Color(0xFF111115);
  static const Color statusStart  = Color(0xFF1C1C21);
  static const Color statusEnd    = Color(0xFF0D0D12);
  static const Color toggleBg     = Color(0xFF1A1A21);
  static const Color toggleActive = Color(0xFF2A2A35);
  static const Color locCardBg    = Color(0xFF1A1A21);
  static const Color iconCircleBg = Color(0xFF0D0D12);
  static const Color mutedGrey    = Color(0xFFA1A1AA); // zinc-400
  static const Color inactiveTab  = Color(0xFF71717A); // zinc-500
  static const Color white        = Color(0xFFFFFFFF);

  static const Color deny = Color(0xFFFF2244);
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
    with SingleTickerProviderStateMixin {

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
=======
    with TickerProviderStateMixin {

  late AnimationController _pulseCtrl;
  late AnimationController _radarCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<double>   _radarAnim;
  late Animation<double>   _fadeAnim;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  GeofenceResult? _geoResult;
  bool _geoChecking = true;

<<<<<<< HEAD
  static const String _logoAsset = 'assets/images/logo.png';

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  @override
  void initState() {
    super.initState();

<<<<<<< HEAD
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
    );

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: _T.headerStart,
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _runGeoCheck();
  }

<<<<<<< HEAD
=======
  // ✅ Now uses GeofenceService — single source of truth
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
      backgroundColor: const Color(0xFF1F2128),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      action: SnackBarAction(label: 'RETRY', textColor: _T.ctaSolid, onPressed: _runGeoCheck),
=======
      backgroundColor: const Color(0xFF1E1000),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      action: SnackBarAction(label: 'RETRY', textColor: _T.orange, onPressed: _runGeoCheck),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    ));
  }

  @override
  void dispose() {
<<<<<<< HEAD
=======
    _pulseCtrl.dispose();
    _radarCtrl.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< HEAD
      backgroundColor: _T.heroBgEnd,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _buildNavbar(),
            Expanded(
              child: Stack(
                children: [
                  // ── Layer 1: gradient background (fills the whole area) ──
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_T.heroBgStart, _T.heroBgEnd],
                        ),
                      ),
                    ),
                  ),

                  // ── Layer 2: hand watermark — sits ON TOP of the gradient
                  //    but BEHIND the scrollable content, so it now actually
                  //    shows through instead of being hidden underneath an
                  //    opaque container.
                  Positioned(
                    bottom: -90,
                    left: -110,
                    child: IgnorePointer(
                      child: Transform.rotate(
                        angle: _degToRad(425),
                        child: Opacity(
                          opacity: 0.9,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              Color.fromRGBO(255, 138, 0, 0.35),
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              _logoAsset,
                              width: 500,
                              height: 500,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Layer 3: foreground scrollable content. No opaque
                  //    background here anymore — it's transparent so the
                  //    watermark underneath stays visible.
                  SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroSection(),
                        _buildWorkingZoneSection(),
                        _buildDashboardPreview(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    );
  }

<<<<<<< HEAD
  double _degToRad(double deg) => deg * 3.1415926535 / 180;

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  // ── NAVBAR ──────────────────────────────────────────────────────────────────
  Widget _buildNavbar() {
    final bool isBlocked = _geoChecking || !(_geoResult?.isInside ?? false);

    return Container(
<<<<<<< HEAD
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_T.headerStart, _T.headerMid, _T.headerEnd],
        ),
      ),
=======
      color: _T.orange,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
<<<<<<< HEAD
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.back_hand_rounded, color: _T.white, size: 20),
              ),
              const SizedBox(width: 8),
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              const Text(
                'R.A.C.O.M.A',
                style: TextStyle(
                  color: _T.white,
                  fontSize: 18,
<<<<<<< HEAD
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
=======
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              // ✅ onTap is null when blocked = truly unclickable
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              GestureDetector(
                onTap: isBlocked
                    ? null
                    : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Container(
<<<<<<< HEAD
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withOpacity(isBlocked ? 0.3 : 1),
                      width: 1,
=======
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isBlocked ? _T.white40 : _T.white,
                      width: 1.5,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    ),
                  ),
                  child: Text('Log In',
                      style: TextStyle(
<<<<<<< HEAD
                          color: _T.white.withOpacity(isBlocked ? 0.5 : 1),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
=======
                          color: isBlocked ? _T.white40 : _T.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.3)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
    final circleBorder = isChecking
        ? _T.circleBorder
        : isInside ? _T.circleBorder : _T.deny;
    final labelColor = isInside || isChecking ? _T.labelLime : _T.deny;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [

          // Geofence circle — gradient fill (top -> mid -> bottom), border, glow marker
          Container(
            width: 256, height: 256, // w-64 h-64
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_T.circleGradTop, _T.circleGradMid, _T.circleGradBottom],
              ),
              border: Border.all(color: circleBorder, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _T.buildingBg,
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(255, 140, 0, 0.8),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Icon(
                    isChecking
                        ? Icons.gps_fixed_rounded
                        : isInside
                        ? Icons.business_rounded
                        : Icons.location_off_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
                Positioned(
                  bottom: 40,
                  child: Text(
                    isChecking
                        ? 'Locating…'
                        : isInside
                        ? 'Inside Authorized Zone'
                        : 'Outside Work Zone',
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Verified badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _T.badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.verified_user_rounded, color: _T.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Verified Location Tracking',
                  style: TextStyle(
                    color: _T.white, fontSize: 13, fontWeight: FontWeight.w500,
=======

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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  ),
                ),
              ],
            ),
          ),

<<<<<<< HEAD
          const SizedBox(height: 20),

          // Headline: "Clock in" (black) + "where it matters." (orange->amber gradient text)
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clock in',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: _T.heroTitle,
                  ),
                ),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_T.heroDescGradStart, _T.heroDescGradEnd],
                  ).createShader(bounds),
                  child: const Text(
                    'where it matters.',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: Colors.white, // masked by ShaderMask
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Seamless, location-based time tracking for modern teams. '
                  'Automatically verify when you are on-site and ready to work, '
                  'ensuring accurate logs and eliminating guesswork.',
              style: TextStyle(
                color: _T.heroDesc, fontSize: 13.5, height: 1.6,
              ),
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),

          const SizedBox(height: 20),

<<<<<<< HEAD
          // Get Started button (solid orange, black text)
          _buildCTAButton(),

          const SizedBox(height: 16),
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ],
      ),
    );
  }

  // ── CTA BUTTON ──────────────────────────────────────────────────────────────
  Widget _buildCTAButton() {
    final isChecking = _geoChecking;
    final isAllowed  = _geoResult?.isInside ?? false;
<<<<<<< HEAD
    final blocked    = !isAllowed || isChecking;

    return SizedBox(
      width: double.infinity,
=======
    // ✅ blocked when NOT allowed OR still checking
    final blocked    = !isAllowed || isChecking;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // ✅ AbsorbPointer makes button truly unclickable when blocked
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      child: AbsorbPointer(
        absorbing: blocked,
        child: GestureDetector(
          onTap: _onGetStarted,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
<<<<<<< HEAD
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: blocked ? const Color(0xFFE5E5E5) : _T.ctaSolid,
              borderRadius: BorderRadius.circular(16),
              boxShadow: blocked
                  ? []
                  : [BoxShadow(
                color: _T.ctaSolid.withOpacity(0.4),
                blurRadius: 40, offset: const Offset(0, 10),
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              )],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isChecking)
                  const SizedBox(
                    width: 16, height: 16,
<<<<<<< HEAD
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
=======
                    child: CircularProgressIndicator(color: _T.orange, strokeWidth: 2.5),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  )
                else if (blocked)
                  const Icon(Icons.location_off_rounded, color: Color(0xFF888888), size: 18)
                else
                  const SizedBox.shrink(),
                const SizedBox(width: 8),
                Text(
                  isChecking ? 'Checking Location…' : blocked ? 'Outside Work Zone' : 'Get Started',
                  style: TextStyle(
<<<<<<< HEAD
                    color: blocked ? const Color(0xFF888888) : Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
=======
                    color: blocked ? const Color(0xFF888888) : _T.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16, letterSpacing: 0.4,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  ),
                ),
                if (!isChecking && !blocked) ...[
                  const SizedBox(width: 8),
<<<<<<< HEAD
                  const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 18),
=======
                  const Icon(Icons.arrow_forward_rounded, color: _T.white, size: 18),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
<<<<<<< HEAD

  // ── WORKING ZONE SECTION (new, from updated mock) ───────────────────────────
  Widget _buildWorkingZoneSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.location_on_rounded, color: _T.workZoneIcon, size: 20),
              SizedBox(width: 8),
              Text(
                'The Working Zone',
                style: TextStyle(
                  color: _T.heroTitle,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Authorized working zones are defined geographical areas designated '
                'for your workplace. Once you enter the perimeter, our Live GPS '
                'system authenticates your location, enabling the Clock In feature securely.',
            style: TextStyle(
              color: _T.heroDesc,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── DASHBOARD PREVIEW (dark card) ────────────────────────────────────────
  Widget _buildDashboardPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _T.dashCardBg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + greeting
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF27272A),
                    border: Border.all(color: const Color(0xFF3F3F46)),
                  ),
                  alignment: Alignment.center,
                  child: const Text('JH',
                      style: TextStyle(color: Color(0xFFFB923C), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HI, JOHN HOWARD',
                          style: TextStyle(color: _T.mutedGrey, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      Text('Employee Dashboard',
                          style: TextStyle(color: _T.white, fontSize: 14, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [_T.statusStart, _T.statusEnd],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('You are currently',
                      style: TextStyle(color: _T.white, fontSize: 20, fontWeight: FontWeight.w600, height: 1.2)),
                  Text('ready to work.',
                      style: TextStyle(color: _T.ctaSolid, fontSize: 20, fontWeight: FontWeight.w600, height: 1.2)),
                  SizedBox(height: 4),
                  Text('Our system verified your location. You are ready to go.',
                      style: TextStyle(color: _T.mutedGrey, fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Toggle
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _T.toggleBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _T.toggleActive,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('Inside Zone',
                            style: TextStyle(color: _T.white, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const Center(
                        child: Text('Outside Zone',
                            style: TextStyle(color: _T.inactiveTab, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Location status header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Location Status', style: TextStyle(color: _T.white, fontSize: 12, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: _T.green400),
                    ),
                    const SizedBox(width: 6),
                    const Text('Live GPS', style: TextStyle(color: _T.mutedGrey, fontSize: 12)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // HQ office info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _T.locCardBg,
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _T.iconCircleBg,
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🏢', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HQ Main Office',
                          style: TextStyle(color: _T.white, fontSize: 14, fontWeight: FontWeight.w500)),
                      Text('Inside Authorized Zone',
                          style: TextStyle(color: _T.lime400, fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Clock in button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: _T.ctaSolid,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clock In',
                          style: TextStyle(color: _T.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('01:45 PM',
                          style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.1),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: _T.white, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
=======
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
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}