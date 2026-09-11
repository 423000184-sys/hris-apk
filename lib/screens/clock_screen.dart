// lib/screens/clock_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

// Additional brand colors
class _MockColors {
  static const Color darkBorder = Color(0xFF27272A);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFF0000);
  static const Color translucentGray = Color.fromRGBO(131, 131, 131, 0.28);
}

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors for clock screen
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);

  // Text colors
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);

  // Location card — text ON the orange card is always white
  // (that card is always orange, both themes)

  // Clock out button bg (normal state = white-ish, dark mode = dark)
  Color get clockButtonBg =>
      isDark ? const Color(0xFF1F1F23) : Colors.white.withValues(alpha: 0.2);

  // Disabled clock button
  Color get clockButtonDisabledBg => isDark
      ? const Color(0xFF27272A).withValues(alpha: 0.5)
      : Colors.grey.withValues(alpha: 0.3);

  // Success overlay card
  Color get successCardBg =>
      isDark ? const Color(0xFF18181B) : Colors.white;

  // Dialog bg
  Color get dialogBg => isDark ? const Color(0xFF18181B) : Colors.white;

  // Splash progress track
  Color get progressTrack =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
}

class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  const ClockScreen({
    super.key,
    this.initialEmployee,
    this.onBack,
    this.onContinue,
  });

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _successCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _successAnim;
  late Animation<double> _glowAnim;

  Employee? _employee;
  Attendance? _lastRecord;

  String? _webTimeIn;
  String? _webTimeOut;
  String? _webDate;
  bool _webClockedIn = false;

  String? _mobileTimeInOverride;
  String? _mobileTimeOutOverride;
  bool? _mobileClockedInOverride;

  Timer? _durationTimer;
  String _elapsedDuration = '00:00:00';
  DateTime? _rawClockInDateTime;

  bool _loading = true;
  bool _processing = false;
  bool _showSuccess = false;
  bool _hasClockedOutToday = false;
  String _successMsg = '';
  String _successSubMsg = '';

  GeofenceResult? _geofenceResult;
  bool _gpsLoading = true;

  late Timer _timer;
  DateTime _now = DateTime.now();

  final _uuid = const Uuid();
  StreamSubscription? _firestoreSub;

  bool get _isClockedIn => kIsWeb
      ? _webClockedIn
      : (_mobileClockedInOverride ?? _lastRecord?.isClockedIn ?? false);

  String? get _displayTimeIn =>
      kIsWeb ? _webTimeIn : (_mobileTimeInOverride ?? _lastRecord?.timeIn);

  String? get _displayTimeOut =>
      kIsWeb ? _webTimeOut : (_mobileTimeOutOverride ?? _lastRecord?.timeOut);

  bool get _isInsideZone => _geofenceResult?.isInside ?? false;

  bool get _isAlreadyClockedOutToday {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_lastRecord != null && _lastRecord!.date == today) {
      return _lastRecord!.timeOut != null;
    }
    if (kIsWeb && _webDate == today) {
      return _webTimeOut != null;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.2, end: 0.8)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadData();
    _checkGeofence();
  }

  @override
  void dispose() {
    _timer.cancel();
    _durationTimer?.cancel();
    _fadeCtrl.dispose();
    _successCtrl.dispose();
    _glowCtrl.dispose();
    _firestoreSub?.cancel();
    super.dispose();
  }

  void _startElapsedTimer() {
    _durationTimer?.cancel();
    if (_rawClockInDateTime == null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rawClockInDateTime != null && _isClockedIn) {
        final now = DateTime.now();
        final difference = now.difference(_rawClockInDateTime!);
        final hours = difference.inHours.toString().padLeft(2, '0');
        final minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() {
            _elapsedDuration = '$hours:$minutes:$seconds';
          });
        }
      }
    });
  }

  Future<void> _loadData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee? emp;
    Attendance? att;

    if (empId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(empId);
      att = await DatabaseService.instance.getTodayAttendance(empId);

      if (att != null && att.timeIn != null && att.timeOut == null) {
        try {
          final parts = att.timeIn!.split(':');
          if (parts.length >= 2) {
            final now = DateTime.now();
            _rawClockInDateTime = DateTime(
              now.year,
              now.month,
              now.day,
              int.parse(parts[0]),
              int.parse(parts[1]),
              parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
            );
          }
        } catch (_) {}
      }
    }
    emp ??= widget.initialEmployee;

    if (kIsWeb && emp != null) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      try {
        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: emp.employeeId)
            .where('date', isEqualTo: today)
            .orderBy('timestamp', descending: false)
            .get();
        String? lastIn, lastOut;
        for (final doc in snap.docs) {
          final d = doc.data();
          if (d['type'] == 'IN') {
            lastIn = d['time']?.toString();
            if (lastIn != null) {
              try {
                final parts = lastIn.split(':');
                if (parts.length >= 2) {
                  final now = DateTime.now();
                  _rawClockInDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    int.parse(parts[0]),
                    int.parse(parts[1]),
                    parts.length > 2
                        ? int.parse(parts[2].substring(0, 2))
                        : 0,
                  );
                }
              } catch (_) {}
            }
          }
          if (d['type'] == 'OUT') lastOut = d['time']?.toString();
        }
        if (mounted) {
          setState(() {
            _webTimeIn = lastIn;
            _webTimeOut = lastOut;
            _webDate = today;
            _webClockedIn = lastIn != null && lastOut == null;
          });
        }

        _firestoreSub?.cancel();
        _firestoreSub = FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: emp.employeeId)
            .where('date', isEqualTo: today)
            .orderBy('timestamp', descending: false)
            .snapshots()
            .listen((s) {
          if (!mounted) return;
          String? li, lo;
          for (final doc in s.docs) {
            final d = doc.data();
            if (d['type'] == 'IN') li = d['time']?.toString();
            if (d['type'] == 'OUT') lo = d['time']?.toString();
          }
          setState(() {
            _webTimeIn = li;
            _webTimeOut = lo;
            _webDate = today;
            _webClockedIn = li != null && lo == null;
          });
        });
      } catch (e) {
        debugPrint('Firestore web load: $e');
      }
    }

    if (mounted) {
      setState(() {
        _employee = emp;
        _lastRecord = att;
        _loading = false;
      });
      if (_isClockedIn && _rawClockInDateTime != null) {
        _startElapsedTimer();
      }
    }
  }

  Future<void> _checkGeofence() async {
    if (mounted) setState(() => _gpsLoading = true);
    try {
      final res = await GeofenceService.instance.checkGeofence();
      if (mounted) setState(() => _geofenceResult = res);
    } catch (_) {} finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  void _handleClockTap() async {
    if (_processing) return;

    if (_isAlreadyClockedOutToday) {
      _showSnack('You have already clocked out today.', AppColors.warning);
      return;
    }

    await _checkGeofence();
    if (!mounted) return;

    if (!_isInsideZone) {
      _showGeofenceDialog();
      return;
    }

    setState(() => _processing = true);
    final success = await _recordClockOut();
    if (!mounted) return;
    setState(() => _processing = false);

    if (success) {
      await Future.delayed(const Duration(milliseconds: 1600));
      if (mounted) widget.onContinue?.call();
    }
  }

  Future<bool> _recordClockOut() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) return false;

    final record = _lastRecord;

    try {
      if (kIsWeb) {
        await FirebaseFirestore.instance.collection('attendance_logs').add({
          'employee_id': emp.employeeId,
          'employee_name': emp.fullName,
          'date': today,
          'time': timeStr,
          'type': 'OUT',
          'method': 'Manual',
          'platform': 'Web',
          'timestamp': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          setState(() {
            _webTimeOut = timeStr;
            _webClockedIn = false;
            _rawClockInDateTime = null;
            _elapsedDuration = '00:00:00';
            _durationTimer?.cancel();
          });
        }
        _showSuccessOverlay(
          'Clock Out Success',
          '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}\n(Logged to Cloud)',
        );
      } else {
        if (record != null) {
          await DatabaseService.instance.updateTimeOut(record.id, timeStr);
          await FirebaseFirestore.instance.collection('attendance_logs').add({
            'employee_id': emp.employeeId,
            'employee_name': emp.fullName,
            'date': today,
            'time': timeStr,
            'type': 'OUT',
            'method': 'Manual',
            'platform': 'Mobile',
            'timestamp': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            setState(() {
              _mobileTimeOutOverride = timeStr;
              _mobileClockedInOverride = false;
              _rawClockInDateTime = null;
              _elapsedDuration = '00:00:00';
            });
          }
          _durationTimer?.cancel();
          _showSuccessOverlay('Clock Out Success',
              '${emp.fullName}\n${DateFormat("hh:mm a").format(now)}');
        } else {
          _showSnack('No active clock-in record found.', AppColors.error);
          return false;
        }
        await _loadData();
      }
      setState(() {
        _hasClockedOutToday = true;
      });
      return true;
    } catch (e) {
      _showSnack('Record failed: $e', AppColors.error);
      return false;
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    if (_loading) return _buildSplash(tc);
    return Scaffold(
      backgroundColor: tc.bg,
      body: Stack(children: [
        FadeTransition(
          opacity: _fadeAnim,
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(tc),
                    const SizedBox(height: 20),
                    _buildStatusBanner(),
                    const SizedBox(height: 16),
                    _buildLocationCard(tc),
                    const SizedBox(height: 16),
                    _buildTimeRow(tc),
                    const SizedBox(height: 28),
                    _buildClockOutButton(tc),
                  ]),
            ),
          ),
        ),
        if (_showSuccess) _buildSuccessOverlay(tc),
      ]),
    );
  }

  // ── HEADER ──────────────────────────────────────────────────────────
  Widget _buildHeader(_ThemeColors tc) {
    final name = _employee?.firstName ??
        _employee?.fullName.split(' ').first ??
        'Employee';

    return SizedBox(
      height: 72,
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.gradientOrange,
            border: Border.all(color: _MockColors.darkBorder, width: 1.15),
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('HI, ${name.toUpperCase()}',
                  style: TextStyle(
                      color: tc.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0)),
              Text('Employee Dashboard',
                  style: TextStyle(
                      color: tc.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
        const Spacer(),
        GestureDetector(
          onTap: () => widget.onBack?.call(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              shape: BoxShape.circle,
              border: Border.all(color: _MockColors.orangeBorder, width: 1.15),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── STATUS BANNER (always dark hero) ───────────────────────────────
  Widget _buildStatusBanner() {
    final inRange = _isInsideZone;
    final loading = _gpsLoading;
    final statusText =
    loading ? 'Detecting...' : (inRange ? 'In Range.' : 'Out of Range.');
    final statusColor = loading ? Colors.white70 : AppColors.orange;
    final subText = inRange || loading
        ? 'Our system verified your location. You are\nready to go.'
        : 'You are outside the authorized zone.\nMove closer to clock out.';

    return Container(
      width: double.infinity,
      height: 175,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A3A), Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
        ),
        border: Border.all(color: _MockColors.orangeBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      height: 1.25,
                    ),
                    children: [
                      const TextSpan(text: 'You are currently\n'),
                      TextSpan(
                        text: statusText,
                        style: TextStyle(color: statusColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subText,
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION CARD ──────────────────────────────────────────────────
  Widget _buildLocationCard(_ThemeColors tc) {
    final inRange = _isInsideZone;
    final loading = _gpsLoading;
    final zoneText = loading
        ? 'Checking your zone…'
        : (inRange ? 'Inside Authorized Zone' : 'Outside Authorized Zone');
    final dist = _geofenceResult?.distanceMeters;
    final accentColor = loading
        ? AppColors.orange
        : (inRange ? _MockColors.lime : _MockColors.red);
    final cardBorderColor = loading
        ? _MockColors.orangeBorder
        : (inRange ? _MockColors.orangeBorder : _MockColors.red);
    final cardBg = loading || inRange ? null : _MockColors.translucentGray;
    final cardGradient = loading || inRange ? AppColors.gradientOrange : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Location Status',
            style: TextStyle(
                color: tc.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        Icon(Icons.navigation_rounded, color: tc.textPrimary, size: 13),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _checkGeofence,
          behavior: HitTestBehavior.opaque,
          child: Text('Live GPS',
              style: TextStyle(
                  color: tc.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: cardBg,
          gradient: cardGradient,
          border: Border.all(color: cardBorderColor, width: 1.15),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: loading
                ? const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.orange),
            )
                : Icon(Icons.location_on_rounded, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(zoneText,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: (!loading && !inRange)
                        ? FontWeight.w700
                        : FontWeight.w400,
                  )),
              const SizedBox(height: 4),
              const Text('HQ Main Office',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(GeofenceService.officeAddress,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3)),
              if (dist != null) ...[
                const SizedBox(height: 4),
                Text('${dist.toStringAsFixed(0)} m from office',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }

  // ── TIME ROW ──────────────────────────────────────────────────────
  Widget _buildTimeRow(_ThemeColors tc) {
    final clocked = _isClockedIn;
    final timeIn = _fmt12(_displayTimeIn);
    final timeOut = _fmt12(_displayTimeOut);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange, width: 1.15),
      ),
      child: Row(children: [
        Expanded(
          child: _toggleSegment(tc, 'Clock In', timeIn, active: !clocked),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _toggleSegment(tc, 'Clock Out', timeOut, active: clocked),
        ),
      ]),
    );
  }

  Widget _toggleSegment(_ThemeColors tc, String title, String time,
      {required bool active}) {
    // Segment na active = white bg (para kitang-kita sa orange gradient)
    // Segment na hindi active = transparent (orange gradient ang nakikita)
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border:
        active ? Border.all(color: _MockColors.orangeBorder, width: 1) : null,
        boxShadow: active
            ? [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ]
            : null,
      ),
      child: Column(children: [
        Text(title,
            style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(time,
            style: TextStyle(
                color:
                active ? const Color(0xFFA1A1AA) : Colors.white,
                fontSize: 11)),
      ]),
    );
  }

  // ── CLOCK OUT BUTTON ────────────────────────────────────────────────
  Widget _buildClockOutButton(_ThemeColors tc) {
    final canAct = _isInsideZone;
    final isAlreadyClockedOut = _isAlreadyClockedOutToday;
    final isEnabled = canAct && !isAlreadyClockedOut;

    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(
          isAlreadyClockedOut ? 'Already Clocked Out' : 'Clock Out',
          style: TextStyle(
            color: isAlreadyClockedOut ? tc.textMuted : tc.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: isEnabled ? _handleClockTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 105,
            height: 112,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: isEnabled ? _MockColors.orangeBorder : tc.textMuted,
                width: 1.15,
              ),
              borderRadius: BorderRadius.circular(20),
              color: isEnabled
                  ? tc.clockButtonBg
                  : tc.clockButtonDisabledBg,
            ),
            child: _processing
                ? const Center(
                child: CircularProgressIndicator(
                    color: AppColors.orange, strokeWidth: 2))
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient:
                    isEnabled ? AppColors.gradientOrange : null,
                    color: isEnabled ? null : tc.textMuted,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isEnabled
                          ? _MockColors.orangeBorder
                          : tc.textMuted,
                      width: 1.15,
                    ),
                  ),
                  child: Icon(
                    isAlreadyClockedOut
                        ? Icons.check_circle_rounded
                        : Icons.timer_off_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isAlreadyClockedOut ? 'Done' : 'Clock Out',
                  style: TextStyle(
                    color: isEnabled ? tc.textPrimary : tc.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (isAlreadyClockedOut) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'You have already clocked out today',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ],
      if (_isClockedIn && !isAlreadyClockedOut) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border:
            Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_rounded,
                  size: 16, color: AppColors.orange),
              const SizedBox(width: 8),
              Text(
                'Duty Time: $_elapsedDuration',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.orange,
                ),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),
      Center(
          child: Text(DateFormat('hh:mm a').format(_now),
              style: TextStyle(
                  color: tc.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5))),
      const SizedBox(height: 2),
      Center(
          child: Text(DateFormat('EEEE, MMMM d yyyy').format(_now),
              style: TextStyle(color: tc.textSecondary, fontSize: 11))),
    ]);
  }

  // ── SUCCESS OVERLAY ────────────────────────────────────────────────
  Widget _buildSuccessOverlay(_ThemeColors tc) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: ScaleTransition(
            scale: _successAnim,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: tc.successCardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.12),
                      blurRadius: 40,
                      spreadRadius: 4)
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 44),
                ),
                const SizedBox(height: 16),
                Text(_successMsg,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: tc.textPrimary,
                        letterSpacing: 0.3)),
                const SizedBox(height: 10),
                Text(_successSubMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: tc.textSecondary, height: 1.7, fontSize: 14)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── GEOFENCE DIALOG ────────────────────────────────────────────────
  void _showGeofenceDialog() {
    final dist = _geofenceResult?.distanceMeters?.toStringAsFixed(0) ?? '?';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.location_off_rounded,
                color: AppColors.error, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Outside Work Zone',
                style: TextStyle(
                    color: tc.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              const Icon(Icons.gps_off_rounded,
                  color: AppColors.error, size: 32),
              const SizedBox(height: 10),
              Text('You are ${dist}m away from the office.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: tc.textSecondary, fontSize: 13, height: 1.5)),
              const SizedBox(height: 8),
              const Text('Move inside the authorized zone to clock out.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.4)),
            ]),
          ),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.info.withValues(alpha: 0.15),
                foregroundColor: AppColors.info,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: AppColors.info.withValues(alpha: 0.3))),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _checkGeofence();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry Location Check',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Dismiss',
                  style:
                  TextStyle(color: tc.textSecondary, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  // ── SPLASH ──────────────────────────────────────────────────────────
  Widget _buildSplash(_ThemeColors tc) {
    return Scaffold(
      backgroundColor: tc.bg,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: AppColors.gradientOrange,
            ),
            child: const Icon(Icons.fingerprint,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          Text('Loading attendance terminal…',
              style: TextStyle(color: tc.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: tc.progressTrack,
                valueColor:
                const AlwaysStoppedAnimation(AppColors.orange),
                minHeight: 4,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────
  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  void _showSuccessOverlay(String title, String message) {
    setState(() {
      _showSuccess = true;
      _successMsg = title;
      _successSubMsg = message;
    });
    _successCtrl.forward(from: 0);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSuccess = false);
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }
}