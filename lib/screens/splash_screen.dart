// lib/screens/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'landing_screen.dart';
import 'admin_dashboard.dart';
import 'main_screen.dart';
import '../models/employee.dart';
import '../services/clock_status_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../theme/app_theme.dart';

enum _SplashState { loading, networkError, navigating }

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

  _SplashState _state = _SplashState.loading;
  String _errorMessage = 'No internet connection.';

  StreamSubscription<bool>? _connectivitySub;
  Timer? _bootstrapTimeout;
  static const Duration _bootstrapTimeoutDur = Duration(seconds: 15);
  static const Duration _networkCheckTimeout = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.3, curve: Curves.easeIn)),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.3, 0.6, curve: Curves.easeIn)),
    );
    _progressValue = Tween<double>(begin: 0.0, end: 0.94).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.5, 1.0, curve: Curves.easeInOut)),
    );

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint('🌐 Splash: connectivity changed → online=$online');
            if (online && _state == _SplashState.networkError) {
              debugPrint('🌐 Splash: network back → auto-retry bootstrap');
              _retryBootstrap();
            }
          });
    } catch (e) {
      debugPrint('⚠️ Splash: could not listen to connectivity: $e');
    }

    _controller.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _bootstrap();
      });
    });
  }

  @override
  void dispose() {
    _bootstrapTimeout?.cancel();
    _connectivitySub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _hasNetwork() async {
    try {
      final dynamic s = ConnectivityService.instance;

      try {
        final dynamic result = s.checkConnection();
        if (result is Future) {
          final dynamic v = await result.timeout(_networkCheckTimeout);
          if (v is bool) {
            debugPrint('🌐 Network check (checkConnection): $v');
            return v;
          }
        }
      } catch (e) {
        debugPrint('⚠️ checkConnection failed: $e');
      }

      try {
        final dynamic result = s.isConnected();
        if (result is Future) {
          final dynamic v = await result.timeout(_networkCheckTimeout);
          if (v is bool) {
            debugPrint('🌐 Network check (isConnected): $v');
            return v;
          }
        }
      } catch (e) {
        debugPrint('⚠️ isConnected failed: $e');
      }

      try {
        final dynamic v = s.isOnline;
        if (v is bool) {
          if (v == true) {
            debugPrint('🌐 Network check (isOnline getter): $v');
            return true;
          }
          debugPrint('🌐 isOnline getter says false — IGNORING (may be stale)');
        }
      } catch (e) {
        debugPrint('⚠️ isOnline getter failed: $e');
      }

      debugPrint('🌐 Network check: could not determine — assuming online');
      return true;
    } catch (e) {
      debugPrint('⚠️ Network check error: $e');
      return true;
    }
  }

  void _retryBootstrap() {
    if (!mounted) return;
    setState(() {
      _state = _SplashState.loading;
      _errorMessage = 'No internet connection.';
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _bootstrapTimeout?.cancel();
    _bootstrapTimeout = Timer(_bootstrapTimeoutDur, () {
      if (!mounted) return;
      if (_state == _SplashState.loading) {
        debugPrint('⏰ Splash: bootstrap timeout — showing network error');
        setState(() {
          _state = _SplashState.networkError;
          _errorMessage =
          'Connection is taking too long.\nPlease check your internet.';
        });
      }
    });

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      debugPrint('🌐 Splash: checking network...');
      final hasNet = await _hasNetwork();

      if (!mounted) return;

      if (!hasNet) {
        _bootstrapTimeout?.cancel();
        debugPrint('🚫 Splash: no network → showing error overlay');
        setState(() {
          _state = _SplashState.networkError;
          _errorMessage =
          'No internet connection.\nPlease check your network and try again.';
        });
        return;
      }

      debugPrint('✅ Splash: network OK — continuing bootstrap');

      if (widget.startPage == 'admin') {
        debugPrint('🚪 Splash: admin page → AdminDashboard');
        _bootstrapTimeout?.cancel();
        _goReplacement(const AdminDashboard());
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('🚪 Splash: No Firebase user → Landing');
        _bootstrapTimeout?.cancel();
        _goReplacement(const LandingScreen());
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('authUid', isEqualTo: user.uid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));

      if (snap.docs.isEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 8));

        if (!doc.exists) {
          debugPrint('🚪 Splash: Employee not found → Landing');
          _bootstrapTimeout?.cancel();
          _goReplacement(const LandingScreen());
          return;
        }

        final data = doc.data();
        if (data == null) {
          _bootstrapTimeout?.cancel();
          _goReplacement(const LandingScreen());
          return;
        }

        final employee = Employee.fromFirestore(data, doc.id);
        _bootstrapTimeout?.cancel();
        await _checkClockedInAndNavigate(employee);
        return;
      }

      final doc = snap.docs.first;
      final employee = Employee.fromFirestore(doc.data(), doc.id);
      _bootstrapTimeout?.cancel();
      await _checkClockedInAndNavigate(employee);
    } catch (e) {
      debugPrint('❌ Splash bootstrap error: $e');
      _bootstrapTimeout?.cancel();

      if (!mounted) return;

      final errStr = e.toString().toLowerCase();
      final isNetError = errStr.contains('network') ||
          errStr.contains('socket') ||
          errStr.contains('timeout') ||
          errStr.contains('unavailable') ||
          errStr.contains('connection');

      if (isNetError) {
        setState(() {
          _state = _SplashState.networkError;
          _errorMessage =
          'Connection was lost during check.\nPlease check your internet and try again.';
        });
      } else {
        _goReplacement(const LandingScreen());
      }
    }
  }

  Future<void> _checkClockedInAndNavigate(Employee employee) async {
    final candidateIds = <String>{
      if (employee.employeeId.isNotEmpty) employee.employeeId,
      if (employee.id.isNotEmpty) employee.id,
    }.toList();

    debugPrint('🔍 Splash: Checking clock-in for '
        '${employee.fullName} (candidates: $candidateIds)');

    bool clockedIn = false;
    String? matchedId;

    for (final id in candidateIds) {
      try {
        final result =
        await ClockStatusService.instance.isCurrentlyClockedIn(id);
        debugPrint('🔍 Splash: ClockStatusService($id) → $result');
        if (result) {
          clockedIn = true;
          matchedId = id;
          break;
        }
      } catch (e) {
        debugPrint('⚠️ Splash: ClockStatusService($id) error: $e');
      }
    }

    if (!clockedIn) {
      debugPrint('🔄 Splash: Service returned false — trying Firestore direct');
      final fbResult = await _checkClockedInDirectly(candidateIds);
      clockedIn = fbResult.$1;
      matchedId = fbResult.$2;
    }

    if (!mounted) return;

    if (clockedIn) {
      debugPrint('✅ Splash: ${employee.fullName} is CLOCKED IN '
          '(via $matchedId) → MainScreen');
      _goReplacement(MainScreen(employee: employee));
    } else {
      debugPrint('🚪 Splash: NOT clocked in → Landing');
      _goReplacement(const LandingScreen());
    }
  }

  Future<(bool, String?)> _checkClockedInDirectly(
      List<String> candidateIds) async {
    if (candidateIds.isEmpty) return (false, null);

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    for (final id in candidateIds) {
      try {
        debugPrint('🔄 Splash: Firestore query — employee_id=$id, '
            'date=$todayStr');

        final snap = await FirebaseFirestore.instance
            .collection('attendance_logs')
            .where('employee_id', isEqualTo: id)
            .where('date', isEqualTo: todayStr)
            .get()
            .timeout(const Duration(seconds: 8));

        if (snap.docs.isEmpty) {
          debugPrint('   ↳ No logs found for id=$id');
          continue;
        }

        final logs = snap.docs.map((d) {
          final data = d.data();
          final ts = _resolveTimestamp(data);
          return {'data': data, 'ts': ts ?? DateTime(2000)};
        }).toList()
          ..sort((a, b) =>
              (a['ts'] as DateTime).compareTo(b['ts'] as DateTime));

        String? lastType;
        for (final log in logs) {
          final data = log['data'] as Map<String, dynamic>;
          final type = (data['type'] ?? '').toString().toUpperCase();
          if (type == 'IN' || type == 'CLOCK_IN') {
            lastType = 'IN';
          } else if (type == 'OUT' || type == 'CLOCK_OUT') {
            lastType = 'OUT';
          }
        }

        debugPrint('   ↳ id=$id → lastType=$lastType (${logs.length} logs)');

        if (lastType == 'IN') {
          return (true, id);
        }
      } catch (e) {
        debugPrint('⚠️ Splash: Firestore direct check($id) error: $e');
      }
    }

    return (false, null);
  }

  DateTime? _resolveTimestamp(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      final parts = rawTime.trim().split(':');
      if (parts.length >= 2) {
        try {
          final now = DateTime.now();
          return DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
            parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
          );
        } catch (_) {}
      }
    }

    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) return rawTs.toDate().toLocal();
    if (rawTs is String && rawTs.trim().isNotEmpty) {
      return DateTime.tryParse(rawTs.trim())?.toLocal();
    }
    if (rawTs is int) return DateTime.fromMillisecondsSinceEpoch(rawTs);

    return null;
  }

  void _goReplacement(Widget page) {
    if (!mounted) return;
    setState(() => _state = _SplashState.navigating);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double designW = 400;
    const double designH = 850;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette;

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
                      child: Image.asset(_logoAsset,
                          width: 600 * sx,
                          height: 600 * sy,
                          fit: BoxFit.contain),
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
                        colorFilter: const ColorFilter.mode(
                            Color.fromRGBO(255, 138, 0, 0.10),
                            BlendMode.srcIn),
                        child: Image.asset(_logoAsset,
                            width: 500 * sx,
                            height: 500 * sy,
                            fit: BoxFit.contain),
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
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: iconOuterGradient),
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
                                colors: [
                                  Color(0xFFFF8A00),
                                  Color(0xFFF97316)
                                ]),
                            borderRadius: BorderRadius.circular(24 * sx),
                            boxShadow: [
                              BoxShadow(
                                  color: const Color(0xFFF97316)
                                      .withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: Offset(0, 12.5 * sy))
                            ],
                          ),
                          alignment: Alignment.center,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                                Colors.white, BlendMode.srcIn),
                            child: Image.asset(_logoAsset,
                                width: 58 * sx,
                                height: 58 * sy,
                                fit: BoxFit.contain),
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
                        Text('R.A.C.O.M.A',
                            textAlign: TextAlign.center,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 30 * sx,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary)),
                        SizedBox(height: 8 * sy),
                        Text('Smart HR Information System',
                            textAlign: TextAlign.center,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 14 * sx,
                                fontWeight: FontWeight.w500,
                                color: palette.textSecondary)),
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
                      final label = _state == _SplashState.networkError
                          ? 'Offline'
                          : 'Initializing...';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12 * sx,
                                  color: palette.textSecondary)),
                          SizedBox(height: 12 * sy),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 200 * sx,
                              height: 3.99 * sy,
                              color: palette.fill,
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor:
                                _state == _SplashState.networkError
                                    ? 0.0
                                    : _progressValue.value,
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF97316),
                                      borderRadius:
                                      BorderRadius.circular(999)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (_state == _SplashState.networkError)
                  Positioned.fill(
                    child: _buildNetworkErrorOverlay(
                      palette: palette,
                      isDark: isDark,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNetworkErrorOverlay({
    required dynamic palette,
    required bool isDark,
  }) {
    return Container(
      color: palette.bg.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFFF8A00),
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No Connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: palette.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                child: ElevatedButton.icon(
                  onPressed: _retryBootstrap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Automatically retries when network returns.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: palette.textMuted ?? palette.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _degToRad(double deg) => deg * 3.1415926535 / 180;
}