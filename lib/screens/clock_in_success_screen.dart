// lib/screens/clock_in_success_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import '../services/database_service.dart';

enum VerificationMethod { keyFob, pin }

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors for clock-in success screen
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  // Page background below the orange header
  Color get contentBg =>
      isDark ? const Color(0xFF0F0F10) : const Color(0xFFF5F5F5);
}

class ClockInSuccessScreen extends StatefulWidget {
  final Employee employee;
  final Duration autoRedirectDelay;
  final VoidCallback? onContinue;
  final ValueChanged<VerificationMethod>? onMethodSelected;

  const ClockInSuccessScreen({
    super.key,
    required this.employee,
    this.autoRedirectDelay = const Duration(seconds: 3),
    this.onContinue,
    this.onMethodSelected,
  });

  @override
  State<ClockInSuccessScreen> createState() => _ClockInSuccessScreenState();
}

class _ClockInSuccessScreenState extends State<ClockInSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _scaleCtrl;
  late final AnimationController _checkCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _textSlideCtrl;
  late final AnimationController _progressCtrl;

  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _checkAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _rippleAnim;
  late final Animation<Offset> _textSlideAnim;
  late final Animation<double> _textFadeAnim;
  late final Animation<double> _progressAnim;

  Timer? _redirectTimer;

  bool _clockInDone = false;
  VerificationMethod _selectedMethod = VerificationMethod.keyFob;

  // Brand colors (same in both themes)
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _headerFrom = Color(0xFFFF8A00);
  static const Color _headerMid = Color(0xFFFF6B00);
  static const Color _headerTo = Color(0xFFF54900);
  static const Color _cardBorder = Color(0xFF382A20);
  static const Color _iconBorder = Color(0xFF51FF00);

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _rippleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _textSlideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _progressCtrl =
        AnimationController(vsync: this, duration: widget.autoRedirectDelay);

    _fadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.5, end: 1)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));
    _checkAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _rippleAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));
    _textSlideAnim =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
            CurvedAnimation(parent: _textSlideCtrl, curve: Curves.easeOutCubic));
    _textFadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _textSlideCtrl, curve: Curves.easeOut));
    _progressAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _progressCtrl, curve: Curves.linear));

    _fadeCtrl.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _scaleCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _checkCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _pulseCtrl.repeat(reverse: true);
        _rippleCtrl.repeat();
        _textSlideCtrl.forward();
        _progressCtrl.forward();
      }
    });

    _saveClockIn();
    _redirectTimer = Timer(widget.autoRedirectDelay, _handleContinue);
  }

  Future<void> _saveClockIn() async {
    try {
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      final dateStr = now.toIso8601String().substring(0, 10);
      final employeeIdVal = widget.employee.employeeId ?? widget.employee.id;

      final attendance = Attendance(
        id: const Uuid().v4(),
        employeeId: employeeIdVal,
        date: dateStr,
        timeIn: timeStr,
        timeOut: null,
        status: AttendanceStatus.present,
        method: AttendanceMethod.face,
        createdAt: now,
      );

      if (!kIsWeb) {
        await DatabaseService.instance.logAttendance(attendance);
        await DatabaseService.instance.saveClockInFile(
          employee: widget.employee,
          attendance: attendance,
        );
      }

      await FirebaseFirestore.instance.collection('attendance_logs').add({
        'type': 'IN',
        'employee_id': employeeIdVal,
        'employeeId': employeeIdVal,
        'employee_name': widget.employee.fullName,
        'email': widget.employee.email,
        'time': timeStr,
        'timestamp': timeStr,
        'date': dateStr,
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });

      if (mounted) {
        setState(() {
          _clockInDone = true;
        });
      }
    } catch (e) {
      debugPrint('Clock-in save error: $e');
    }
  }

  void _handleContinue() {
    if (!mounted) return;
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _selectMethod(VerificationMethod method) {
    setState(() => _selectedMethod = method);
    widget.onMethodSelected?.call(method);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _scaleCtrl.dispose();
    _checkCtrl.dispose();
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _textSlideCtrl.dispose();
    _progressCtrl.dispose();
    _redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: tc.contentBg,
      body: Stack(
        children: [
          // --- Background: header only (no orange circle) ---
          Column(
            children: [
              Container(
                height: 287.13 + statusBarHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_headerFrom, _headerMid, _headerTo],
                    stops: [0.0, 0.33, 1.0],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: _cardBorder,
                      width: 1.15,
                    ),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 24,
                      top: 48 + statusBarHeight,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: _white.withValues(alpha: 0.8),
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Back',
                              style: TextStyle(
                                color: _white.withValues(alpha: 0.8),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      top: 95.99 + statusBarHeight,
                      child: const Text(
                        'Auth & Clock In',
                        style: TextStyle(
                          color: _white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      top: 136.99 + statusBarHeight,
                      child: Text(
                        'Select your initial verification method',
                        style: TextStyle(
                          color: _white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Empty space below header (theme-aware)
              Expanded(
                child: Container(
                  color: tc.contentBg,
                ),
              ),
            ],
          ),

          // --- Overlay ---
          FadeTransition(
            opacity: _fadeAnim,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withValues(alpha: 0.44),
            ),
          ),

          // --- Success modal ---
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSuccessCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        width: 338.14,
        height: 343.03,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_headerFrom, _headerMid, _headerTo],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF27272A),
            width: 1.15,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 12.5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Checkmark
            Positioned(
              left: 113.06,
              top: 33.15,
              child: AnimatedBuilder(
                animation:
                Listenable.merge([_pulseAnim, _rippleAnim, _checkAnim]),
                builder: (context, _) {
                  return SizedBox(
                    width: 112,
                    height: 112,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ..._buildRipples(),
                        Transform.scale(
                          scale: _pulseAnim.value,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _iconBorder.withValues(
                                    alpha: 0.3 * _checkAnim.value),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: _white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _iconBorder.withValues(
                                  alpha: _checkAnim.value.clamp(0, 1)),
                              width: 4,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: _AnimatedCheckmark(
                              progress: _checkAnim.value,
                              color: _iconBorder,
                              size: 44,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // "Verified & Clocked In!"
            Positioned(
              left: 33.15,
              top: 177.13,
              width: 271.84,
              height: 66,
              child: SlideTransition(
                position: _textSlideAnim,
                child: FadeTransition(
                  opacity: _textFadeAnim,
                  child: const Text(
                    'Verified & Clocked\nIn!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _white,
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
            // "Starting your shift and redirecting..."
            Positioned(
              left: 60.75,
              top: 255.14,
              child: SlideTransition(
                position: _textSlideAnim,
                child: FadeTransition(
                  opacity: _textFadeAnim,
                  child: Container(
                    width: 216.63,
                    height: 22.75,
                    child: Stack(
                      children: [
                        Positioned(
                          left: -9,
                          top: -0.85,
                          child: Text(
                            'Starting your shift and redirecting...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _white.withValues(alpha: 0.88),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Progress bar (auto-redirect)
            Positioned(
              left: 33.15,
              bottom: 20,
              right: 33.15,
              child: _buildRedirectProgress(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRipples() {
    return List.generate(3, (i) {
      final t = (_rippleAnim.value + i / 3) % 1.0;
      final radius = 50 + t * 40.0;
      final opacity = (1 - t) * 0.25;
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _iconBorder.withValues(alpha: opacity),
            width: 1.5,
          ),
        ),
      );
    });
  }

  Widget _buildRedirectProgress() {
    return AnimatedBuilder(
      animation: _progressAnim,
      builder: (_, __) {
        final remaining = widget.autoRedirectDelay.inSeconds -
            (widget.autoRedirectDelay.inSeconds * _progressAnim.value).floor();
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Auto-redirecting to dashboard',
                  style: TextStyle(
                    color: _white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${remaining}s',
                  style: const TextStyle(
                    color: _white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progressAnim.value,
                backgroundColor: _white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(_white),
                minHeight: 3,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---- Helper widgets ----

class _AnimatedCheckmark extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;

  const _AnimatedCheckmark({
    required this.progress,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CheckmarkPainter(progress: progress, color: color),
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _CheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3 * progress)
      ..strokeWidth = size.width * 0.16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final start = Offset(cx - size.width * 0.28, cy);
    final mid = Offset(cx - size.width * 0.05, cy + size.height * 0.22);
    final end = Offset(cx + size.width * 0.30, cy - size.height * 0.18);

    final path = Path();
    if (progress < 0.5) {
      final t = progress / 0.5;
      path.moveTo(start.dx, start.dy);
      path.lineTo(
        start.dx + (mid.dx - start.dx) * t,
        start.dy + (mid.dy - start.dy) * t,
      );
    } else {
      final t = (progress - 0.5) / 0.5;
      path.moveTo(start.dx, start.dy);
      path.lineTo(mid.dx, mid.dy);
      path.lineTo(
        mid.dx + (end.dx - mid.dx) * t,
        mid.dy + (end.dy - mid.dy) * t,
      );
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, path.getBounds().isEmpty ? paint : paint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter old) =>
      old.progress != progress || old.color != color;
}