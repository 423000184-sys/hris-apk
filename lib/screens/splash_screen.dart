import 'package:flutter/material.dart';
import 'landing_screen.dart';
import 'admin_dashboard.dart';

class SplashScreen extends StatefulWidget {
  final String startPage;
  const SplashScreen({super.key, this.startPage = 'landing'});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<double> _progressValue;
  String _statusText = 'Initializing.';

  @override
  void initState() {
    super.initState();

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
            pageBuilder: (_, __, ___) => widget.startPage == 'admin'
                ? const AdminDashboard()
                : const LandingScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      });
    });
  }

  @override
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
              child: const Icon(
                Icons.fingerprint_rounded,
                size: 320,
                color: Color(0xFFFF6B00),
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
                          child: const Center(
                            child: Icon(
                              Icons.back_hand_rounded,
                              size: 52,
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                        ),
                      ),
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
}