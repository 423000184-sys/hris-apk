import 'package:flutter/material.dart';
import 'landing_screen.dart';
<<<<<<< HEAD
import 'admin_dashboard.dart';

/// R.A.C.O.M.A Splash Screen (STATIC — no animation)
/// Converted from the HTML/CSS mockup (screen-container 400x850).
/// Uses assets/images/logo.png for the center icon and both background watermarks.
///
/// IMPORTANT SETUP:
/// 1. Put your image at:  assets/images/logo.png
/// 2. In pubspec.yaml add:
///    flutter:
///      assets:
///        - assets/images/logo.png
class SplashScreen extends StatefulWidget {
  final String startPage;
  const SplashScreen({super.key, this.startPage = 'landing'});
=======

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

<<<<<<< HEAD
class _SplashScreenState extends State<SplashScreen> {
  static const String _logoAsset = 'assets/images/logo.png';

  // How long the splash stays on screen before navigating.
  static const Duration _holdDuration = Duration(milliseconds: 1800);
=======
class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _progressValue;
  String _statusText = 'Initializing.';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();

<<<<<<< HEAD
    // No AnimationController anymore — just wait, then navigate.
    Future.delayed(_holdDuration, () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => widget.startPage == 'admin'
              ? const AdminDashboard()
              : const LandingScreen(),
        ),
      );
=======
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.6, curve: Curves.easeIn),
      ),
    );

    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    _controller.addListener(() {
      final v = _controller.value;
      String next = 'Initializing.';
      if (v > 0.6) next = 'Initializing..';
      if (v > 0.75) next = 'Initializing...';
      if (v > 0.9) next = 'Ready.';
      if (_statusText != next && mounted) setState(() => _statusText = next);
    });

    _controller.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const LandingScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      });
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    });
  }

  @override
<<<<<<< HEAD
  Widget build(BuildContext context) {
    // Reference design size from the HTML mock (400x850). We scale
    // everything to the real device size using this ratio.
    const double designW = 400;
    const double designH = 850;

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double h = constraints.maxHeight;
          final double sx = w / designW;
          final double sy = h / designH;

          return Container(
            width: w,
            height: h,
            // matches: linear-gradient(180deg, #fff 0%, #fff 45%, #ffe8d1 100%)
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFFFFFFF),
                  Color(0xFFFFE8D1),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ---------- bg-hand-top ----------
                Positioned(
                  top: -180 * sy,
                  right: -200 * sx,
                  child: Transform.rotate(
                    angle: _degToRad(270),
                    child: Opacity(
                      opacity: 0.25,
                      child: Image.asset(
                        _logoAsset,
                        width: 600 * sx,
                        height: 600 * sy,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),

                // ---------- bg-hand-bottom ----------
                Positioned(
                  bottom: -130 * sy,
                  left: -150 * sx,
                  child: Transform.rotate(
                    angle: _degToRad(425),
                    child: Opacity(
                      opacity: 0.80,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Color.fromRGBO(255, 138, 0, 0.10),
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          _logoAsset,
                          width: 500 * sx,
                          height: 500 * sy,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),

                // ---------- App icon (outer gray frame + orange box + logo) ----------
                // No FadeTransition / ScaleTransition anymore — shown immediately at full size/opacity.
                Positioned(
                  left: 128.24 * sx,
                  top: 289.26 * sy,
                  child: Container(
                    width: 128 * sx,
                    height: 128 * sy,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
                      ),
                      borderRadius: BorderRadius.circular(32 * sx),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 95.99 * sx,
                      height: 95.99 * sy,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFF8A00), Color(0xFFF97316)],
                        ),
                        borderRadius: BorderRadius.circular(24 * sx),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF97316).withOpacity(0.2),
                            blurRadius: 10,
                            offset: Offset(0, 12.5 * sy),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          _logoAsset,
                          width: 58 * sx,
                          height: 58 * sy,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),

                // ---------- Title block ----------
                // No FadeTransition anymore — shown immediately.
                Positioned(
                  left: 100.99 * sx,
                  top: 417.24 * sy,
                  width: 182.47 * sx,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'R.A.C.O.M.A',
                        textAlign: TextAlign.center,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 30 * sx,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 8 * sy),
                      Text(
                        'Smart HR Information System',
                        textAlign: TextAlign.center,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 14 * sx,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------- Loader ----------
                // Progress bar is now static (full width), not animated.
                Positioned(
                  left: 92.22 * sx,
                  top: 720.47 * sy,
                  width: 200 * sx,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Initializing...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12 * sx,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      SizedBox(height: 12 * sy),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 200 * sx,
                          height: 3.99 * sy,
                          color: const Color(0xFFF8FAFC),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.94, // fixed, matches original end value
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF97316),
                                borderRadius: BorderRadius.circular(999),
                              ),
=======
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // ── Decorative fingerprint watermark ──────────────────────────
          Positioned(
            top: -40,
            right: -40,
            child: Opacity(
              opacity: 0.07,
              child: Icon(
                Icons.fingerprint_rounded,
                size: 320,
                color: const Color(0xFFFF6B00),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFFF6B00).withOpacity(0.3),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF6B00).withOpacity(0.25),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.back_hand_rounded,
                              size: 52,
                              color: const Color(0xFFFF6B00),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                            ),
                          ),
                        ),
                      ),
<<<<<<< HEAD
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;
=======
                    ),

                    const SizedBox(height: 32),

                    // App name
                    FadeTransition(
                      opacity: _textOpacity,
                      child: const Text(
                        'R.A.C.O.M.A',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 6,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Tagline
                    FadeTransition(
                      opacity: _textOpacity,
                      child: const Text(
                        'Smart HR Information System',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF888888),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── Progress bar at bottom ─────────────────────────────────────
          Positioned(
            left: 40,
            right: 40,
            bottom: 60,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _progressValue.value,
                        backgroundColor: const Color(0xFF222222),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF6B00),
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}