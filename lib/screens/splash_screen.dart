import 'package:flutter/material.dart';
import 'landing_screen.dart';
import 'admin_dashboard.dart';
import '../theme/app_theme.dart'; // para sa context.palette

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

  static const String _logoAsset = 'assets/images/logo.png';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3, curve: Curves.easeIn)),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.6, curve: Curves.easeIn)),
    );

    _progressValue = Tween<double>(begin: 0.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeInOut)),
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 400), () {
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
    const double designW = 400;
    const double designH = 850;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette; // ← galing na sa AppPalette mo

    final List<Color> bgGradientColors = isDark
        ? [palette.bg, palette.bg, const Color(0xFF2A1B0D)]
        : [palette.bg, palette.bg, const Color(0xFFFFE8D1)];

    final List<Color> iconOuterGradient = isDark
        ? [palette.surface, palette.card]
        : const [Color(0xFFF1F5F9), Color(0xFFE2E8F0)];

    return Scaffold(
      backgroundColor: palette.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double h = constraints.maxHeight;
          final double sx = w / designW;
          final double sy = h / designH;

          return Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bgGradientColors,
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  top: -180 * sy,
                  right: -200 * sx,
                  child: Transform.rotate(
                    angle: _degToRad(270),
                    child: Opacity(
                      opacity: isDark ? 0.12 : 0.25,
                      child: Image.asset(_logoAsset, width: 600 * sx, height: 600 * sy, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -130 * sy,
                  left: -150 * sx,
                  child: Transform.rotate(
                    angle: _degToRad(425),
                    child: Opacity(
                      opacity: 0.80,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.mode(Color.fromRGBO(255, 138, 0, 0.10), BlendMode.srcIn),
                        child: Image.asset(_logoAsset, width: 500 * sx, height: 500 * sy, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 128.24 * sx,
                  top: 289.26 * sy,
                  child: FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        width: 128 * sx,
                        height: 128 * sy,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: iconOuterGradient),
                          borderRadius: BorderRadius.circular(32 * sx),
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 95.99 * sx,
                          height: 95.99 * sy,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF8A00), Color(0xFFF97316)]),
                            borderRadius: BorderRadius.circular(24 * sx),
                            boxShadow: [BoxShadow(color: const Color(0xFFF97316).withOpacity(0.2), blurRadius: 10, offset: Offset(0, 12.5 * sy))],
                          ),
                          alignment: Alignment.center,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                            child: Image.asset(_logoAsset, width: 58 * sx, height: 58 * sy, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 100.99 * sx,
                  top: 417.24 * sy,
                  width: 182.47 * sx,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'R.A.C.O.M.A',
                          textAlign: TextAlign.center,
                          softWrap: false,
                          style: TextStyle(fontSize: 30 * sx, fontWeight: FontWeight.w700, color: palette.textPrimary),
                        ),
                        SizedBox(height: 8 * sy),
                        Text(
                          'Smart HR Information System',
                          textAlign: TextAlign.center,
                          softWrap: false,
                          style: TextStyle(fontSize: 14 * sx, fontWeight: FontWeight.w500, color: palette.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 92.22 * sx,
                  top: 720.47 * sy,
                  width: 200 * sx,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('Initializing...', textAlign: TextAlign.center, style: TextStyle(fontSize: 12 * sx, color: palette.textSecondary)),
                          SizedBox(height: 12 * sy),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 200 * sx,
                              height: 3.99 * sy,
                              color: palette.fill,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _progressValue.value,
                                child: Container(
                                  decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(999)),
                                ),
                              ),
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
        },
      ),
    );
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;
}