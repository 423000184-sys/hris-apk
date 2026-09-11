// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/geofence_service.dart';
import 'login_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// _T — colors that are the same for both themes (brand, status, accent)
// ═══════════════════════════════════════════════════════════════════════════
class _T {
  // Header / brand (same in both themes)
  static const Color headerStart = Color(0xFFF54900);
  static const Color headerMid   = Color(0xFFFF6B00);
  static const Color headerEnd   = Color(0xFFFF8A00);

  // Radar / zone circle
  static const Color circleGradTop    = Color.fromRGBO(255, 138, 0, 0.62);
  static const Color circleGradMid    = Color.fromRGBO(250, 106, 0, 0.62);
  static const Color circleGradBottom = Color.fromRGBO(245, 73, 0, 0.62);
  static const Color circleBorder     = Color(0xFFFF8C00);

  static const Color buildingBg = Color(0xFFF59E0B);
  static const Color labelLime  = Color(0xFFC2FF00);
  static const Color lime400    = Color(0xFFA3E635);
  static const Color green400   = Color(0xFF4ADE80);

  static const Color badgeBg = Color(0xFFFF8904);
  static const Color heroDescGradStart = Color(0xFFEA580C);
  static const Color heroDescGradEnd   = Color(0xFFF59E0B);
  static const Color workZoneIcon      = Color(0xFFEA580C);

  static const Color ctaSolid = Color(0xFFFF6900);
  static const Color deny     = Color(0xFFFF2244);

  // Dashboard preview (always dark - it's a mock)
  static const Color dashCardBg   = Color(0xFF111115);
  static const Color statusStart  = Color(0xFF1C1C21);
  static const Color statusEnd    = Color(0xFF0D0D12);
  static const Color toggleBg     = Color(0xFF1A1A21);
  static const Color toggleActive = Color(0xFF2A2A35);
  static const Color locCardBg    = Color(0xFF1A1A21);
  static const Color iconCircleBg = Color(0xFF0D0D12);
  static const Color mutedGrey    = Color(0xFFA1A1AA);
  static const Color inactiveTab  = Color(0xFF71717A);
  static const Color white        = Color(0xFFFFFFFF);
}

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors resolved per build
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;

  const _ThemeColors(this.isDark);

  // Hero section background
  Color get heroBgStart => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get heroBgEnd   => isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

  // Title & description
  Color get heroTitle => isDark ? Colors.white : const Color(0xFF000000);
  Color get heroDesc  => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF3F3F46);

  // Scaffold background (behind the hero container)
  Color get scaffoldBg => isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

  // Watermark opacity
  double get watermarkOpacity => isDark ? 0.15 : 0.80;
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
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  GeofenceResult? _geoResult;
  bool _geoChecking = true;

  static const String _logoAsset = 'assets/images/logo.png';

  @override
  void initState() {
    super.initState();

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
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _runGeoCheck();
  }

  Future<void> _runGeoCheck() async {
    if (mounted) setState(() => _geoChecking = true);
    final result = await GeofenceService.instance.checkGeofence();
    if (mounted) {
      setState(() {
        _geoResult = result;
        _geoChecking = false;
      });
    }
  }

  void _onGetStarted() {
    if (_geoChecking) {
      _snack('Verifying your location…');
      return;
    }
    if (!(_geoResult?.isInside ?? false)) {
      final dist = _geoResult?.distanceMeters;
      _snack(dist != null
          ? 'You are ${dist.toStringAsFixed(0)} m from the office zone.'
          : _geoResult?.message ?? 'Outside work zone');
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: _T.white, fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFF1F2128),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      action: SnackBarAction(
          label: 'RETRY', textColor: _T.ctaSolid, onPressed: _runGeoCheck),
    ));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Resolve theme-aware colors from current Theme
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.scaffoldBg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _buildNavbar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [tc.heroBgStart, tc.heroBgEnd],
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // Background watermark
                      Positioned(
                        bottom: -130,
                        left: -150,
                        child: IgnorePointer(
                          child: Transform.rotate(
                            angle: _degToRad(425),
                            child: Opacity(
                              opacity: tc.watermarkOpacity,
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(
                                  Color.fromRGBO(255, 138, 0, 0.10),
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  _logoAsset,
                                  width: 500,
                                  height: 500,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) {
                                    debugPrint('logo.png failed to load');
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Foreground content
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeroSection(tc),
                          _buildWorkingZoneSection(tc),
                          _buildDashboardPreview(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  // ── NAVBAR ──────────────────────────────────────────────────────────────
  Widget _buildNavbar() {
    final bool isBlocked = _geoChecking || !(_geoResult?.isInside ?? false);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_T.headerStart, _T.headerMid, _T.headerEnd],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.back_hand_rounded,
                    color: _T.white, size: 20),
              ),
              const SizedBox(width: 8),
              const Text(
                'R.A.C.O.M.A',
                style: TextStyle(
                  color: _T.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: isBlocked
                    ? null
                    : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white
                          .withValues(alpha: isBlocked ? 0.3 : 1),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'Log In',
                    style: TextStyle(
                      color: Colors.white
                          .withValues(alpha: isBlocked ? 0.5 : 1),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── HERO SECTION ────────────────────────────────────────────────────────
  Widget _buildHeroSection(_ThemeColors tc) {
    final isInside = _geoResult?.isInside ?? false;
    final isChecking = _geoChecking;
    final circleBorder = isChecking
        ? _T.circleBorder
        : isInside
        ? _T.circleBorder
        : _T.deny;
    final labelColor = isInside || isChecking ? _T.labelLime : _T.deny;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Geofence circle
          Container(
            width: 256,
            height: 256,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _T.circleGradTop,
                  _T.circleGradMid,
                  _T.circleGradBottom
                ],
              ),
              border: Border.all(color: circleBorder, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
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
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _T.badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.verified_user_rounded,
                    color: _T.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Verified Location Tracking',
                  style: TextStyle(
                    color: _T.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Headline
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clock in',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: tc.heroTitle,
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
                      color: Colors.white,
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
                color: tc.heroDesc,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
          ),

          const SizedBox(height: 20),

          _buildCTAButton(),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── CTA BUTTON ──────────────────────────────────────────────────────────
  Widget _buildCTAButton() {
    final isChecking = _geoChecking;
    final isAllowed = _geoResult?.isInside ?? false;
    final blocked = !isAllowed || isChecking;

    return SizedBox(
      width: double.infinity,
      child: AbsorbPointer(
        absorbing: blocked,
        child: GestureDetector(
          onTap: _onGetStarted,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: blocked ? const Color(0xFFE5E5E5) : _T.ctaSolid,
              borderRadius: BorderRadius.circular(16),
              boxShadow: blocked
                  ? []
                  : [
                BoxShadow(
                  color: _T.ctaSolid.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isChecking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2.5),
                  )
                else if (blocked)
                  const Icon(Icons.location_off_rounded,
                      color: Color(0xFF888888), size: 18)
                else
                  const SizedBox.shrink(),
                const SizedBox(width: 8),
                Text(
                  isChecking
                      ? 'Checking Location…'
                      : blocked
                      ? 'Outside Work Zone'
                      : 'Get Started',
                  style: TextStyle(
                    color: blocked ? const Color(0xFF888888) : Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (!isChecking && !blocked) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.black, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── WORKING ZONE SECTION ────────────────────────────────────────────────
  Widget _buildWorkingZoneSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: _T.workZoneIcon, size: 20),
              const SizedBox(width: 8),
              Text(
                'The Working Zone',
                style: TextStyle(
                  color: tc.heroTitle,
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
              color: tc.heroDesc,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── DASHBOARD PREVIEW (always dark - it's a mock) ───────────────────────
  Widget _buildDashboardPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _T.dashCardBg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF27272A),
                    border: Border.all(color: const Color(0xFF3F3F46)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'JH',
                    style: TextStyle(
                      color: Color(0xFFFB923C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HI, JOHN HOWARD',
                        style: TextStyle(
                          color: _T.mutedGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Employee Dashboard',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_T.statusStart, _T.statusEnd],
                ),
                border:
                Border.all(color: Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'You are currently',
                    style: TextStyle(
                      color: _T.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    'ready to work.',
                    style: TextStyle(
                      color: _T.ctaSolid,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Our system verified your location. You are ready to go.',
                    style: TextStyle(color: _T.mutedGrey, fontSize: 12),
                  ),
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
                        child: Text(
                          'Inside Zone',
                          style: TextStyle(
                            color: _T.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const Center(
                        child: Text(
                          'Outside Zone',
                          style: TextStyle(
                            color: _T.inactiveTab,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
                const Text(
                  'Location Status',
                  style: TextStyle(
                    color: _T.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _T.green400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live GPS',
                      style: TextStyle(color: _T.mutedGrey, fontSize: 12),
                    ),
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
                border:
                Border.all(color: Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _T.iconCircleBg,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🏢', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HQ Main Office',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Inside Authorized Zone',
                        style: TextStyle(
                          color: _T.lime400,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Clock in button
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: _T.ctaSolid,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
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
                      Text(
                        'Clock In',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '01:45 PM',
                        style:
                        TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: _T.white, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}