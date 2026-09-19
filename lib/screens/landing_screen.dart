// lib/screens/landing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'login_screen.dart';
import '../widgets/bootstrap_grid.dart';

// ═══════════════════════════════════════════════════════════════════════════
// _T — colors that are the same for both themes
// ═══════════════════════════════════════════════════════════════════════════
class _T {
  static const Color headerStart = Color(0xFFF54900);
  static const Color headerMid   = Color(0xFFFF6B00);
  static const Color headerEnd   = Color(0xFFFF8A00);

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

  // Desktop (web PC / macOS) colors from HTML mock
  static const Color desktopBg       = Color(0xFF0C0C0E);
  static const Color desktopNavText  = Color(0xFFD4D4D8);
  static const Color desktopMuted    = Color(0xFF9F9FA9);
  static const Color desktopBadge    = Color(0xFFFF8904);
  static const Color desktopDivider  = Color(0x14FFFFFF); // ~ rgba(255,255,255,.05)
}

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors for mobile layout
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get heroBgStart => isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get heroBgEnd   => isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

  Color get heroTitle => isDark ? Colors.white : const Color(0xFF000000);
  Color get heroDesc  => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF3F3F46);

  Color get scaffoldBg => isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

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

  static const String _logoAsset = 'assets/images/logo.png';

  /// Breakpoint above which (on web) we render the desktop
  /// two-column Bootstrap layout. Below this, mobile layout is used.
  static const double _desktopBreakpoint = 992.0;

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
  }

  void _goToLogin() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;

  /// TRUE only on web when viewport is wide (PC / macOS).
  bool _useDesktopLayout(BuildContext context) {
    if (!kIsWeb) return false;
    final w = MediaQuery.of(context).size.width;
    return w >= _desktopBreakpoint;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final useDesktop = _useDesktopLayout(context);

    return Scaffold(
      backgroundColor:
      useDesktop ? _T.desktopBg : tc.scaffoldBg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            _buildNavbar(useDesktop: useDesktop),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: useDesktop
                    ? _buildDesktopBody()
                    : _buildMobileBody(tc),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NAVBAR — two styles
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildNavbar({required bool useDesktop}) {
    if (useDesktop) return _buildDesktopNavbar();
    return _buildMobileNavbar();
  }

  /// Desktop nav — matches HTML mock (dark, plain "Sign In").
  Widget _buildDesktopNavbar() {
    return Container(
      decoration: const BoxDecoration(
        color: _T.desktopBg,
        border: Border(
          bottom: BorderSide(color: _T.desktopDivider, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          child: Row(
            children: [
              // Orange logo tile
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _T.ctaSolid,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Colors.black,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'R.A.C.O.M.A.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _goToLogin,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      color: _T.desktopNavText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

  /// Mobile nav — original orange gradient with "Log In" border button.
  Widget _buildMobileNavbar() {
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
                onTap: _goToLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Text(
                    'Log In',
                    style: TextStyle(
                      color: Colors.white,
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

  // ═══════════════════════════════════════════════════════════════════════
  // DESKTOP BODY — 2-column Bootstrap layout (matches HTML mock)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDesktopBody() {
    return Container(
      width: double.infinity,
      color: _T.desktopBg,
      padding: const EdgeInsets.symmetric(vertical: 96),
      child: BsContainer(
        maxWidth: 1600,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left column: hero content ──
            Expanded(flex: 6, child: _buildDesktopHeroLeft()),
            const SizedBox(width: 80),
            // ── Right column: dashboard preview ──
            Expanded(flex: 4, child: _buildDesktopDashboard()),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeroLeft() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Badge pill ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.verified_user_rounded,
                  color: _T.desktopBadge, size: 16),
              SizedBox(width: 8),
              Text(
                'Verified Location Tracking',
                style: TextStyle(
                  color: _T.desktopBadge,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // ── Heading ──
        const Text(
          'Clock in',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            height: 1.05,
            color: Colors.white,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_T.heroDescGradStart, _T.heroDescGradEnd],
          ).createShader(bounds),
          child: const Text(
            'where it matters.',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w700,
              height: 1.05,
              color: Colors.white,
            ),
          ),
        ),

        const SizedBox(height: 28),

        // ── Description ──
        const SizedBox(
          width: 576,
          child: Text(
            'Seamless, location-based time tracking for modern teams. '
                'Automatically verify when you are on-site and ready to work, '
                'ensuring accurate logs and eliminating guesswork.',
            style: TextStyle(
              color: _T.desktopMuted,
              fontSize: 18,
              height: 1.55,
            ),
          ),
        ),

        const SizedBox(height: 48),

        // ── Working Zone ──
        Row(
          children: const [
            Icon(Icons.location_on_rounded,
                color: _T.workZoneIcon, size: 20),
            SizedBox(width: 8),
            Text(
              'The Working Zone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SizedBox(
          width: 576,
          child: Text(
            'Authorized working zones are defined geographical areas '
                'designated for your workplace. Once you enter the perimeter, '
                'our Live GPS system authenticates your location, enabling the '
                'Clock In feature securely.',
            style: TextStyle(
              color: _T.desktopMuted,
              fontSize: 16,
              height: 1.55,
            ),
          ),
        ),

        const SizedBox(height: 32),

        // ── Get Started CTA ──
        _buildDesktopCTA(),
      ],
    );
  }

  Widget _buildDesktopCTA() {
    return SizedBox(
      width: 340,
      child: GestureDetector(
        onTap: _goToLogin,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _T.ctaSolid,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF97316).withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Get Started',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.black, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Desktop dashboard preview — same mock, with an orange glow behind.
  Widget _buildDesktopDashboard() {
    return Stack(
      children: [
        // Orange glow behind the card
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: _T.ctaSolid.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        ),
        // The card itself
        _buildDashboardPreview(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MOBILE BODY — original layout (unchanged behaviour)
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildMobileBody(_ThemeColors tc) {
    return Container(
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
    );
  }

  // ── HERO (mobile) ──────────────────────────────────────────────────────
  Widget _buildHeroSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
              border: Border.all(color: _T.circleBorder, width: 2),
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _T.buildingBg,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(255, 140, 0, 0.8),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
                const Positioned(
                  bottom: 40,
                  child: Text(
                    'Authorized Zone',
                    style: TextStyle(
                      color: _T.labelLime,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
          _buildMobileCTAButton(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── CTA (mobile) ───────────────────────────────────────────────────────
  Widget _buildMobileCTAButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _goToLogin,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _T.ctaSolid,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _T.ctaSolid.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(width: 8),
              Text(
                'LOGIN',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.black, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Working Zone (mobile) ──────────────────────────────────────────────
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

  // ── DASHBOARD PREVIEW (used by both layouts) ───────────────────────────
  Widget _buildDashboardPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _T.dashCardBg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_T.statusStart, _T.statusEnd],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _T.locCardBg,
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                        style: TextStyle(color: Colors.white70, fontSize: 11),
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