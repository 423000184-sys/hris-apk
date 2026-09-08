// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/geofence_service.dart';
import '../services/alarm_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import 'attendance_history_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens
// ─────────────────────────────────────────────────────────────────────────────
class _T {
  static const Color bg        = Color(0xFF111111);
  static const Color surface   = Color(0xFF1C1C1C);
  static const Color surface2  = Color(0xFF232323);
  static const Color orange    = Color(0xFFFF8C00);
  static const Color orangeHot = Color(0xFFFF6600);
  static const Color white     = Color(0xFFFFFFFF);
  static const Color white70   = Color(0xB3FFFFFF);
  static const Color white40   = Color(0x66FFFFFF);
  static const Color white15   = Color(0x26FFFFFF);
  static const Color green     = Color(0xFF39D98A);
  static const Color red       = Color(0xFFFF4D6D);
  static const Color blue      = Color(0xFF4DA3FF);

  static const double fs1  = 30;
  static const double fs2  = 22;
  static const double fs3  = 18;
  static const double fs4  = 15;
  static const double fs5  = 13;
  static const double fs6  = 11;

  static const FontWeight fwNormal = FontWeight.w400;
  static const FontWeight fwMed    = FontWeight.w500;
  static const FontWeight fwSemi   = FontWeight.w600;
  static const FontWeight fwBold   = FontWeight.w700;
  static const FontWeight fwBlack  = FontWeight.w900;

  static const double r4  = 4;
  static const double r8  = 8;
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
}

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final Employee? initialEmployee;

  const DashboardScreen({
    super.key,
    this.onTabSwitch,
    this.initialEmployee,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {

  Employee?        _employee;
  Attendance?      _todayAttendance;
  List<Attendance> _recent       = [];
  Map<String, int> _stats        = {};
  bool             _loading      = true;
  bool             _isVerifying  = false;
  bool             _isShowingAlarmDialog = false;
  int              _pendingCount = 0;
  String?          _overriddenEmployeeId;
  String?          _spotCheckPhotoPath;
  DateTime?        _spotCheckTime;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;
  late Timer          _clock;
  DateTime            _now = DateTime.now();

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;
  late AnimationController _heroGlowCtrl;
  late Animation<double>   _heroGlowAnim;

  bool get _isClockedIn => _todayAttendance?.isClockedIn ?? false;

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try { return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t)); }
    catch (_) { return t; }
  }

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _heroGlowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _heroGlowAnim = Tween<double>(begin: 0.3, end: 0.8)
        .animate(CurvedAnimation(parent: _heroGlowCtrl, curve: Curves.easeInOut));

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _syncSub = SyncService.instance.events.listen((e) {
      if (!mounted) return;
      setState(() => _pendingCount = e.pendingCount);
      if (e.type == SyncEventType.syncDone) _loadData();
    });

    _connectSub = ConnectivityService.instance.onStatusChange.listen((on) {
      if (mounted && on) _loadData();
    });

    _attendanceSub = DatabaseService.instance.onAttendanceChanged.listen((id) {
      if (!mounted) return;
      setState(() => _overriddenEmployeeId = id);
      _loadData();
    });

    _loadData();
  }

  @override
  void dispose() {
    _clock.cancel();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _heroGlowCtrl.dispose();
    _syncSub?.cancel();
    _connectSub?.cancel();
    _attendanceSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final loggedId = await SecurityService.instance.getCurrentEmployeeId();
    final targetId = _overriddenEmployeeId ?? loggedId;

    Employee? emp;
    if (targetId != null && !kIsWeb) {
      emp = await DatabaseService.instance.getEmployeeById(targetId);
    }
    emp ??= widget.initialEmployee;

    Attendance?      today;
    Map<String, int> stats  = {};
    List<Attendance> recent = [];
    int              pending = 0;

    final id = targetId ?? emp?.id;
    if (id != null && !kIsWeb) {
      today   = await DatabaseService.instance.getTodayAttendance(id);
      stats   = await DatabaseService.instance.getAttendanceStats(id);
      recent  = await DatabaseService.instance.getAttendanceByEmployee(id, limit: 5);
      pending = await SyncService.instance.getPendingCount();
    }

    if (mounted) {
      setState(() {
        _employee        = emp;
        _todayAttendance = today;
        _stats           = stats;
        _recent          = recent;
        _pendingCount    = pending;
        _loading         = false;
      });
    }
  }

  void _triggerAlarm() {
    if (_isShowingAlarmDialog) return;
    setState(() => _isShowingAlarmDialog = true);
    AlarmService.instance.startAlarm();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _T.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_T.r20)),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _T.red.withOpacity(0.15), shape: BoxShape.circle),
            child: const Icon(Icons.warning_amber_rounded, color: _T.red, size: 20),
          ),
          const SizedBox(width: 12),
          const Text('System Alert',
              style: TextStyle(color: _T.white, fontWeight: _T.fwBlack, fontSize: _T.fs4)),
        ]),
        content: const Text(
          'You are outside the work radius and have not timed in before 9:30 PM.',
          style: TextStyle(color: _T.white70, fontSize: _T.fs5, height: 1.5),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _T.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_T.r12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                AlarmService.instance.stopAlarm();
                FlutterBackgroundService().invoke('stop_alarm_from_ui');
                Navigator.of(context).pop();
                setState(() => _isShowingAlarmDialog = false);
              },
              child: const Text('STOP THE ALARM',
                  style: TextStyle(color: Colors.white, fontWeight: _T.fwBlack)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startLocationVerification() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      if (!mounted) return;
      final String? path = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => _VerificationCameraScreen(camera: cam)));
      if (path != null && mounted) {
        setState(() {
          _spotCheckPhotoPath = path;
          _spotCheckTime      = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Camera error: $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _openHistory() {
    if (widget.onTabSwitch != null) {
      widget.onTabSwitch!(1);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceHistoryScreen()))
          .then((_) => _loadData());
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // BUILD
  // ───────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.bg,
      body: _loading ? _buildLoader() : _buildBody(),
    );
  }

  Widget _buildLoader() => const Center(
    child: CircularProgressIndicator(color: _T.orange, strokeWidth: 2),
  );

  Widget _buildBody() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Stack(
        children: [
          RefreshIndicator(
            color: _T.orange,
            backgroundColor: _T.surface,
            onRefresh: () async {
              setState(() => _overriddenEmployeeId = null);
              await _loadData();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildSliverHeader(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        _buildHeroBanner(),
                        const SizedBox(height: 16),
                        _buildClockToggle(),
                        const SizedBox(height: 24),
                        _buildLocationStatus(),
                        const SizedBox(height: 24),
                        _buildShortcuts(),
                        const SizedBox(height: 24),
                        _buildStatsSection(),
                        const SizedBox(height: 24),
                        _buildRecentActivity(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20, right: 20, bottom: 16,
            child: _buildFloatingClockOutBar(),
          ),
        ],
      ),
    );
  }

  // ── SLIVER HEADER ── matches screenshot: avatar circle + name + history btn
  SliverAppBar _buildSliverHeader() {
    final name     = _employee?.firstName ?? 'User';
    final lastName = _employee?.lastName  ?? '';

    return SliverAppBar(
      backgroundColor: _T.bg,
      elevation: 0,
      pinned: true,
      automaticallyImplyLeading: false,
      toolbarHeight: 72,
      title: Row(
        children: [
          // Avatar — photo if available, else initials
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _T.orange.withOpacity(0.5), width: 2),
            ),
            child: ClipOval(
              child: _avatarFallback(name),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'HI, ${name.toUpperCase()} ${lastName.toUpperCase()}',
                style: const TextStyle(
                  color: _T.white40, fontSize: 10,
                  fontWeight: _T.fwSemi, letterSpacing: 1.0,
                ),
              ),
              const Text(
                'Employee Dashboard',
                style: TextStyle(
                  color: _T.white, fontSize: 15, fontWeight: _T.fwBold,
                ),
              ),
            ],
          ),
          const Spacer(),
          // History icon button
          GestureDetector(
            onTap: _openHistory,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _T.surface,
                shape: BoxShape.circle,
                border: Border.all(color: _T.white15),
              ),
              child: const Icon(Icons.history_rounded, color: _T.white70, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _T.orange,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Colors.white, fontWeight: _T.fwBlack, fontSize: 18,
          ),
        ),
      ),
    );
  }

  // ── HERO BANNER ── silk texture, "You are currently clocked in/out"
  Widget _buildHeroBanner() {
    final clocked = _isClockedIn;

    return AnimatedBuilder(
      animation: _heroGlowAnim,
      builder: (_, __) => Container(
        width: double.infinity,
        height: 175,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_T.r20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1E1E), Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
          ),
          border: Border.all(color: _T.white15, width: 1),
          boxShadow: [
            BoxShadow(
              color: clocked
                  ? _T.orange.withOpacity(0.15 * _heroGlowAnim.value)
                  : Colors.black.withOpacity(0.3),
              blurRadius: 40, spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_T.r20),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                right: -40, top: -40,
                child: Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: clocked
                        ? _T.orange.withOpacity(0.07)
                        : _T.white15.withOpacity(0.04),
                  ),
                ),
              ),
              Positioned(
                right: 20, bottom: -60,
                child: Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _T.white15.withOpacity(0.03),
                  ),
                ),
              ),
              // Silk lines
              CustomPaint(
                size: const Size(double.infinity, 175),
                painter: _SilkPainter(),
              ),
              // Text content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 24, fontWeight: _T.fwBlack,
                          color: _T.white, height: 1.25, letterSpacing: -0.3,
                        ),
                        children: [
                          const TextSpan(text: 'You are currently\n'),
                          TextSpan(
                            text: clocked ? 'clocked in.' : 'clocked out.',
                            style: TextStyle(
                              color: clocked ? _T.orange : _T.white40,
                              shadows: clocked
                                  ? [Shadow(color: _T.orange.withOpacity(0.5), blurRadius: 20)]
                                  : [],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      clocked
                          ? 'Our system verified your location. You are\nready to go.'
                          : 'Clock in from the authorized zone to\nstart your shift.',
                      style: const TextStyle(
                        color: _T.white40, fontSize: 12, height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CLOCK TOGGLE ── matches screenshot exactly: two halves, orange active
  Widget _buildClockToggle() {
    final clocked = _isClockedIn;
    final timeIn  = _fmt12(_todayAttendance?.timeIn);
    final timeOut = _fmt12(_todayAttendance?.timeOut);

    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: _T.surface,
        borderRadius: BorderRadius.circular(_T.r16),
        border: Border.all(color: _T.orange.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        children: [
          // ── Clock In side
          Expanded(
            child: GestureDetector(
              onTap: clocked ? null : () => widget.onTabSwitch?.call(1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: clocked ? _T.surface2 : _T.surface2,
                  borderRadius: BorderRadius.circular(_T.r12),
                  border: Border.all(
                    color: clocked ? _T.white15 : _T.orange.withOpacity(0.6),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Clock In',
                      style: TextStyle(
                        color: clocked ? _T.white70 : _T.orange,
                        fontSize: _T.fs5, fontWeight: _T.fwBold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      clocked ? timeIn : '--:--',
                      style: TextStyle(
                        color: clocked ? _T.white40 : _T.orange.withOpacity(0.6),
                        fontSize: _T.fs6, fontWeight: _T.fwMed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Clock Out side
          Expanded(
            child: GestureDetector(
              onTap: clocked ? () => widget.onTabSwitch?.call(1) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  gradient: clocked
                      ? const LinearGradient(
                    colors: [_T.orange, _T.orangeHot],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                      : null,
                  color: clocked ? null : _T.surface,
                  borderRadius: BorderRadius.circular(_T.r12),
                  boxShadow: clocked
                      ? [BoxShadow(
                      color: _T.orange.withOpacity(0.35),
                      blurRadius: 12, offset: const Offset(0, 4))]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Clock Out',
                      style: TextStyle(
                        color: clocked ? Colors.white : _T.white40,
                        fontSize: _T.fs5, fontWeight: _T.fwBold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      clocked ? timeOut : '--:--',
                      style: TextStyle(
                        color: clocked
                            ? Colors.white.withOpacity(0.75)
                            : _T.white15,
                        fontSize: _T.fs6, fontWeight: _T.fwMed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOCATION STATUS
  Widget _buildLocationStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Location Status',
              style: TextStyle(color: _T.white, fontSize: _T.fs4, fontWeight: _T.fwBold)),
          const Spacer(),
          const Icon(Icons.navigation_rounded, color: _T.orange, size: 13),
          const SizedBox(width: 4),
          const Text('Live GPS',
              style: TextStyle(color: _T.orange, fontSize: _T.fs6, fontWeight: _T.fwSemi)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(_T.r16),
            border: Border.all(color: _T.white15),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _T.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(_T.r12),
              ),
              child: const Icon(Icons.location_on_rounded, color: _T.orange, size: 20),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HQ Main Office',
                      style: TextStyle(
                          color: _T.white, fontSize: _T.fs4, fontWeight: _T.fwBold)),
                  const SizedBox(height: 3),
                  Text(
                    _isClockedIn ? 'Inside Authorized Zone' : 'Outside Authorized Zone',
                    style: TextStyle(
                      color: _isClockedIn ? _T.green : _T.red,
                      fontSize: _T.fs6, fontWeight: _T.fwSemi,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: _isClockedIn ? _T.green : _T.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isClockedIn ? _T.green : _T.red).withOpacity(0.6),
                    blurRadius: 8, spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }

  // ── SHORTCUTS ── 4 items row
  Widget _buildShortcuts() {
    final shortcuts = [
      _ShortcutItem(Icons.access_time_rounded,   'Logs',     _T.orange, () => widget.onTabSwitch?.call(1)),
      _ShortcutItem(Icons.calendar_month_rounded, 'Leaves',  _T.blue,   () => widget.onTabSwitch?.call(2)),
      _ShortcutItem(Icons.location_on_rounded,    'Location',_T.green,  _startLocationVerification),
      _ShortcutItem(Icons.bar_chart_rounded,      'Reports', _T.red,    () => widget.onTabSwitch?.call(3)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Shortcuts',
            style: TextStyle(color: _T.white, fontSize: _T.fs4, fontWeight: _T.fwBold)),
        const SizedBox(height: 12),
        Row(
          children: shortcuts.asMap().entries.map((e) {
            final s      = e.value;
            final isLast = e.key == shortcuts.length - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 10),
                child: GestureDetector(
                  onTap: s.onTap,
                  child: Container(
                    height: 70,
                    decoration: BoxDecoration(
                      color: _T.surface,
                      borderRadius: BorderRadius.circular(_T.r16),
                      border: Border.all(color: _T.white15),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: s.color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(_T.r8),
                          ),
                          child: Icon(s.icon, color: s.color, size: 16),
                        ),
                        const SizedBox(height: 5),
                        Text(s.label,
                            style: TextStyle(
                              color: s.color,
                              fontSize: 9,
                              fontWeight: _T.fwBold,
                              letterSpacing: 0.3,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── STATS SECTION
  Widget _buildStatsSection() {
    final items = [
      _StatItem('${_stats['present'] ?? 0}', 'Present', _T.green),
      _StatItem('${_stats['late'] ?? 0}',    'Late',    _T.orange),
      _StatItem('${_stats['absent'] ?? 0}',  'Absent',  _T.red),
      _StatItem('${_stats['hours'] ?? 0}h',  'Hours',   _T.blue),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('This Month',
              style: TextStyle(color: _T.white, fontSize: _T.fs4, fontWeight: _T.fwBold)),
          const Spacer(),
          Text(DateFormat('MMMM yyyy').format(_now),
              style: const TextStyle(color: _T.white40, fontSize: _T.fs6)),
        ]),
        const SizedBox(height: 12),
        Row(
          children: items.asMap().entries.map((e) {
            final s      = e.value;
            final isLast = e.key == items.length - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: s.color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(_T.r16),
                    border: Border.all(color: s.color.withOpacity(0.2)),
                  ),
                  child: Column(children: [
                    Text(s.value,
                        style: TextStyle(
                          color: s.color, fontSize: 20,
                          fontWeight: _T.fwBlack, letterSpacing: -0.5,
                        )),
                    const SizedBox(height: 3),
                    Text(s.label,
                        style: TextStyle(
                          color: s.color.withOpacity(0.7),
                          fontSize: 9, fontWeight: _T.fwBold,
                        )),
                  ]),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── RECENT ACTIVITY
  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Recent Activity',
              style: TextStyle(color: _T.white, fontSize: _T.fs4, fontWeight: _T.fwBold)),
          const Spacer(),
          GestureDetector(
            onTap: _openHistory,
            child: const Text('See all',
                style: TextStyle(
                    color: _T.orange, fontSize: _T.fs5, fontWeight: _T.fwSemi)),
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _T.surface,
            borderRadius: BorderRadius.circular(_T.r16),
            border: Border.all(color: _T.white15),
          ),
          child: _recent.isEmpty
              ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No records yet',
                style: TextStyle(color: _T.white40, fontSize: _T.fs5))),
          )
              : Column(
            children: _recent.asMap().entries.map((e) {
              return _buildActivityItem(e.value, e.key == _recent.length - 1);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(Attendance a, bool isLast) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _T.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(_T.r10),
            ),
            child: const Icon(Icons.access_time_rounded, color: _T.orange, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.date,
                  style: const TextStyle(
                      color: _T.white, fontSize: _T.fs5, fontWeight: _T.fwBold)),
              const SizedBox(height: 2),
              Text('In: ${a.timeIn ?? "--"}  ·  Out: ${a.timeOut ?? "Active"}',
                  style: const TextStyle(color: _T.white40, fontSize: _T.fs6)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _T.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _T.green.withOpacity(0.25)),
            ),
            child: const Text('Present',
                style: TextStyle(
                    color: _T.green, fontSize: 10, fontWeight: _T.fwBold)),
          ),
        ]),
      ),
      if (!isLast)
        Divider(color: _T.white15, height: 1, thickness: 0.5, indent: 16, endIndent: 16),
    ]);
  }

  // ── FLOATING CLOCK OUT BAR ── orange pill pinned at bottom
  Widget _buildFloatingClockOutBar() {
    if (!_isClockedIn) return const SizedBox.shrink();

    final timeNow = DateFormat('hh:mm a').format(_now);

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Transform.scale(
        scale: _pulseAnim.value,
        child: GestureDetector(
          onTap: () => widget.onTabSwitch?.call(1),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_T.orange, _T.orangeHot],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(_T.r16),
              boxShadow: [
                BoxShadow(
                  color: _T.orange.withOpacity(0.45),
                  blurRadius: 20, offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Text('Clock Out',
                  style: TextStyle(
                    color: Colors.white, fontSize: _T.fs4, fontWeight: _T.fwBlack,
                  )),
              const Spacer(),
              Text(timeNow,
                  style: const TextStyle(
                    color: Colors.white, fontSize: _T.fs5, fontWeight: _T.fwSemi,
                  )),
              const SizedBox(width: 12),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(_T.r8),
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Silk texture painter
// ─────────────────────────────────────────────────────────────────────────────
class _SilkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = -5; i < 20; i++) {
      final path  = Path();
      final startX = i * 22.0;
      path.moveTo(startX, 0);
      path.cubicTo(
        startX + 30, size.height * 0.3,
        startX - 10, size.height * 0.7,
        startX + 20, size.height,
      );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SilkPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────
class _ShortcutItem {
  final IconData    icon;
  final String      label;
  final Color       color;
  final VoidCallback? onTap;
  const _ShortcutItem(this.icon, this.label, this.color, this.onTap);
}

class _StatItem {
  final String value, label;
  final Color  color;
  const _StatItem(this.value, this.label, this.color);
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification Camera Screen
// ─────────────────────────────────────────────────────────────────────────────
class _VerificationCameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const _VerificationCameraScreen({required this.camera});

  @override
  State<_VerificationCameraScreen> createState() =>
      _VerificationCameraScreenState();
}

class _VerificationCameraScreenState
    extends State<_VerificationCameraScreen> {
  CameraController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _ctrl = CameraController(widget.camera, ResolutionPreset.medium);
    await _ctrl!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: _T.orange)),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        CameraPreview(_ctrl!),
        Center(
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: _T.orange, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 50, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () async {
                final file = await _ctrl!.takePicture();
                if (context.mounted) Navigator.pop(context, file.path);
              },
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _T.orange,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context, null),
                child: Container(
                  width: 36, height: 36,
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Location Verification',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
          ),
        ),
      ]),
    );
  }
}