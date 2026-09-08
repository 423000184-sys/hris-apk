// lib/screens/clock_in_success_screen.dart
import 'dart:async';
<<<<<<< HEAD
=======
import 'dart:math' as math;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import '../services/database_service.dart';

<<<<<<< HEAD
enum VerificationMethod { keyFob, pin }

class ClockInSuccessScreen extends StatefulWidget {
  final Employee employee;
  final Duration autoRedirectDelay;
  final VoidCallback? onContinue;
  final ValueChanged<VerificationMethod>? onMethodSelected;
=======
// ═══════════════════════════════════════════════════════════════════════════
// ClockInSuccessScreen
// Shows the "Verified & Clocked In!" confirmation after successful auth.
// Automatically saves time-in to the database when the screen loads.
// ═══════════════════════════════════════════════════════════════════════════
class ClockInSuccessScreen extends StatefulWidget {
  /// The employee who just authenticated — used to save the time-in record.
  final Employee employee;

  /// How long to stay on this screen before auto-redirecting (default 3 s).
  final Duration autoRedirectDelay;

  /// Called when the auto-redirect timer fires or the user taps "Continue".
  /// If null the screen just pops itself.
  final VoidCallback? onContinue;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  const ClockInSuccessScreen({
    super.key,
    required this.employee,
    this.autoRedirectDelay = const Duration(seconds: 3),
    this.onContinue,
<<<<<<< HEAD
    this.onMethodSelected,
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  });

  @override
  State<ClockInSuccessScreen> createState() => _ClockInSuccessScreenState();
}

class _ClockInSuccessScreenState extends State<ClockInSuccessScreen>
    with TickerProviderStateMixin {
<<<<<<< HEAD
=======

  // ── Animation controllers ────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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

<<<<<<< HEAD
  bool _clockInDone = false;
  VerificationMethod _selectedMethod = VerificationMethod.keyFob;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _headerFrom = Color(0xFFFF8A00);
  static const Color _headerMid = Color(0xFFFF6B00);
  static const Color _headerTo = Color(0xFFF54900);
  static const Color _contentBg = Color(0xFFF5F5F5);
  static const Color _cardBorder = Color(0xFF382A20);
  static const Color _iconBorder = Color(0xFF51FF00);
=======
  // Clock-in state
  bool   _clockInDone  = false;
  String _clockInTime  = '--:--';

  // ── Design tokens ────────────────────────────────────────────────────────
  static const Color _orange    = Color(0xFFFF5500);
  static const Color _black     = Color(0xFF040404);
  static const Color _blackCard = Color(0xFF0D0D0D);
  static const Color _white     = Color(0xFFFFFFFF);
  static const Color _white50   = Color(0x80FFFFFF);
  static const Color _green     = Color(0xFF39FF14);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  @override
  void initState() {
    super.initState();

<<<<<<< HEAD
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _checkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _rippleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _textSlideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _progressCtrl = AnimationController(vsync: this, duration: widget.autoRedirectDelay);
=======
    _fadeCtrl      = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _checkCtrl     = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl     = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _rippleCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _textSlideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _progressCtrl  = AnimationController(vsync: this, duration: widget.autoRedirectDelay);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(begin: 0.5, end: 1).animate(
        CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));
    _checkAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _checkCtrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _rippleAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));
    _textSlideAnim = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _textSlideCtrl, curve: Curves.easeOutCubic));
    _textFadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _textSlideCtrl, curve: Curves.easeOut));
    _progressAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _progressCtrl, curve: Curves.linear));

<<<<<<< HEAD
=======
    // Staggered entry sequence
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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

<<<<<<< HEAD
    _saveClockIn();
    _redirectTimer = Timer(widget.autoRedirectDelay, _handleContinue);
  }

  Future<void> _saveClockIn() async {
    try {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:'
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
=======
    // ── Save time-in immediately when screen loads ──────────────────────
    _saveClockIn();

    // Auto-redirect
    _redirectTimer = Timer(widget.autoRedirectDelay, _handleContinue);
  }

  // ── Save clock-in to DB + Firestore ──────────────────────────────────────
  Future<void> _saveClockIn() async {
    try {
      final now     = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      final dateStr = now.toIso8601String().substring(0, 10); // 'YYYY-MM-DD'

      // Build the Attendance object
      final attendance = Attendance(
        id         : const Uuid().v4(),
        employeeId : widget.employee.id,
        date       : dateStr,
        timeIn     : timeStr,
        timeOut    : null,
        status     : AttendanceStatus.present,
        method     : AttendanceMethod.face,
        createdAt  : now,
      );

      // Save to local SQLite via DatabaseService.logAttendance()
      if (!kIsWeb) {
        await DatabaseService.instance.logAttendance(attendance);

        // Also save the clock-in file to local storage
        await DatabaseService.instance.saveClockInFile(
          employee  : widget.employee,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          attendance: attendance,
        );
      }

<<<<<<< HEAD
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
=======
      // Save to Firestore activity log
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type'         : 'clock_in',
        'employeeId'   : widget.employee.id,
        'employee_name': widget.employee.fullName,
        'email'        : widget.employee.email,
        'timeIn'       : timeStr,
        'date'         : dateStr,
        'timestamp'    : FieldValue.serverTimestamp(),
        'device'       : kIsWeb ? 'Web Browser' : 'Mobile App',
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      });

      if (mounted) {
        setState(() {
          _clockInDone = true;
<<<<<<< HEAD
=======
          _clockInTime = _fmt12(timeStr);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        });
      }
    } catch (e) {
      debugPrint('Clock-in save error: $e');
    }
  }

<<<<<<< HEAD
=======
  String _fmt12(String t) {
    try {
      final parts = t.split(':');
      int h = int.parse(parts[0]);
      final m = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) h = 12;
      if (h > 12) h -= 12;
      return '${h.toString().padLeft(2, '0')}:$m $period';
    } catch (_) {
      return t;
    }
  }

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  void _handleContinue() {
    if (!mounted) return;
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).pop();
    }
  }

<<<<<<< HEAD
  void _selectMethod(VerificationMethod method) {
    setState(() => _selectedMethod = method);
    widget.onMethodSelected?.call(method);
  }

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _contentBg,
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
                              color: _white.withOpacity(0.8),
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Back',
                              style: TextStyle(
                                color: _white.withOpacity(0.8),
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
                          color: _white.withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
=======
    return Scaffold(
      backgroundColor: _black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _white, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Successfully Clock in',
          style: TextStyle(
            color: _white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.code_rounded, color: _orange, size: 20),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              const Text(
                'Auth & Clock In',
                style: TextStyle(
                  color: _white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select your initial verification method',
                style: TextStyle(
                  color: _white50,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: Text(
                  'Step 1: Initial Login',
                  style: TextStyle(
                    color: _white.withOpacity(0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildSuccessCard(context),
              const SizedBox(height: 24),
              _buildRedirectProgress(),
              const SizedBox(height: 20),
              _buildContinueButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUCCESS CARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSuccessCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCC4400), Color(0xFFFF6600), Color(0xFFFF8800)],
          stops: [0, 0.5, 1],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _orange.withOpacity(0.35),
            blurRadius: 40,
            spreadRadius: 4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_scaleAnim, _pulseAnim, _rippleAnim, _checkAnim]),
            builder: (context, _) {
              return SizedBox(
                width: 160,
                height: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ..._buildRipples(),
                    Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _green.withOpacity(0.3 * _checkAnim.value),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: _scaleAnim.value,
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: _blackCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _green.withOpacity(0.6 * _checkAnim.value),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _green.withOpacity(0.25 * _checkAnim.value),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _AnimatedCheckmark(
                            progress: _checkAnim.value,
                            color: _green,
                            size: 44,
                          ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                        ),
                      ),
                    ),
                  ],
                ),
<<<<<<< HEAD
              ),
              // Empty space below header (no orange circle)
              Expanded(
                child: Container(
                  color: _contentBg,
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
              color: Colors.black.withOpacity(0.44),
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
=======
              );
            },
          ),

          const SizedBox(height: 28),

          SlideTransition(
            position: _textSlideAnim,
            child: FadeTransition(
              opacity: _textFadeAnim,
              child: Column(
                children: [
                  const Text(
                    'Verified & Clocked\nIn!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── Show the actual clock-in time ──────────────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _clockInDone
                        ? Container(
                      key: const ValueKey('time'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _green.withOpacity(0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded,
                              color: _green, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Clocked in at $_clockInTime',
                            style: const TextStyle(
                              color: _white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                        : Text(
                      key: const ValueKey('saving'),
                      'Saving your attendance…',
                      style: TextStyle(
                        color: _white.withOpacity(0.65),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Text(
                    'Starting your shift and redirecting…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _white.withOpacity(0.65),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

<<<<<<< HEAD
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
                animation: Listenable.merge([_pulseAnim, _rippleAnim, _checkAnim]),
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
                                color: _iconBorder.withOpacity(0.3 * _checkAnim.value),
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
                              color: _iconBorder.withOpacity(_checkAnim.value.clamp(0, 1)),
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
            // "Starting your shift and redirecting..." - exact HTML styling
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
                            style: const TextStyle(
                              color: Color(0xFFDFDFDF),
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
            // Progress bar (auto-redirect) - stays
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
=======
  List<Widget> _buildRipples() {
    return List.generate(3, (i) {
      final t       = (_rippleAnim.value + i / 3) % 1.0;
      final radius  = 60 + t * 50.0;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      final opacity = (1 - t) * 0.25;
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
<<<<<<< HEAD
            color: _iconBorder.withOpacity(opacity),
=======
            color: _green.withOpacity(opacity),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            width: 1.5,
          ),
        ),
      );
    });
  }

<<<<<<< HEAD
=======
  // ══════════════════════════════════════════════════════════════════════════
  // REDIRECT PROGRESS
  // ══════════════════════════════════════════════════════════════════════════
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
                    color: _white.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
=======
                      color: _white50,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ),
                Text(
                  '${remaining}s',
                  style: const TextStyle(
<<<<<<< HEAD
                    color: _white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
=======
                      color: _orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w800),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progressAnim.value,
<<<<<<< HEAD
                backgroundColor: _white.withOpacity(0.2),
                valueColor: const AlwaysStoppedAnimation<Color>(_white),
=======
                backgroundColor: _white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(_orange),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                minHeight: 3,
              ),
            ),
          ],
        );
      },
    );
  }
<<<<<<< HEAD
}

// ---- Helper widgets ----

class _AnimatedCheckmark extends StatelessWidget {
  final double progress;
  final Color color;
=======

  // ══════════════════════════════════════════════════════════════════════════
  // CONTINUE BUTTON
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: _HoverButton(
        onPressed: () {
          _redirectTimer?.cancel();
          _handleContinue();
        },
        child: const Text(
          'CONTINUE TO DASHBOARD',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ANIMATED CHECKMARK
// ════════════════════════════════════════════════════════════════════════════
class _AnimatedCheckmark extends StatelessWidget {
  final double progress;
  final Color  color;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
<<<<<<< HEAD
  final Color color;
=======
  final Color  color;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

  const _CheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
<<<<<<< HEAD
      ..color = color
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3 * progress)
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
=======
      ..color      = color
      ..strokeWidth = size.width * 0.1
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style      = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color      = color.withOpacity(0.3 * progress)
      ..strokeWidth = size.width * 0.16
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style      = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final cx    = size.width  * 0.5;
    final cy    = size.height * 0.5;
    final start = Offset(cx - size.width * 0.28, cy);
    final mid   = Offset(cx - size.width * 0.05, cy + size.height * 0.22);
    final end   = Offset(cx + size.width * 0.30, cy - size.height * 0.18);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

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
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter old) =>
      old.progress != progress || old.color != color;
<<<<<<< HEAD
=======
}

// ════════════════════════════════════════════════════════════════════════════
// HOVER BUTTON
// ════════════════════════════════════════════════════════════════════════════
class _HoverButton extends StatefulWidget {
  final Widget        child;
  final VoidCallback  onPressed;

  const _HoverButton({required this.child, required this.onPressed});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => setState(() => _pressed = true),
      onTapUp:    (_) { setState(() => _pressed = false); widget.onPressed(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _pressed
                ? [const Color(0xFFFF7A1A), const Color(0xFFFF3D00)]
                : [const Color(0xFFFF5500), const Color(0xFFCC2200)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5500).withOpacity(_pressed ? 0.5 : 0.25),
              blurRadius: _pressed ? 24 : 12,
              offset: Offset(0, _pressed ? 4 : 6),
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}