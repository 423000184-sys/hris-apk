// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart'; // 🆕 OneSignal
import '../theme/app_theme.dart';
import '../models/employee.dart' as model;
import '../data/local/dao/connectivity_service.dart';
import '../widgets/employee_notification_bell.dart';
import '../services/local_notification_service.dart';
import '../services/employee_notification_watcher.dart';
import '../services/presence_monitor_service.dart';
import '../services/motion_detection_service.dart';
import '../services/geofence_service.dart';
import '../services/security_hardening_service.dart';
import '../services/presence_challenge_service.dart';
import 'dashboard_screen.dart';
import 'clock_screen.dart';
import 'attendance_history_screen.dart';
import 'apply_leave_screen.dart';
import 'itinerary_screen.dart';
import 'profile_screen.dart';
import 'landing_screen.dart';
import 'fingerprint_screen.dart';
import 'facial_recognition_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint('[MainScreen] $message');
}

class MainScreen extends StatefulWidget {
  final model.Employee? employee;
  const MainScreen({super.key, this.employee});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  bool _showClockOverlay = false;

  EmployeeNotificationWatcher? _notifWatcher;

  bool _isOnline = true;
  StreamSubscription<bool>? _networkSub;

  Timer? _presenceHeartbeat;
  Timer? _resumeDebounce;

  StreamSubscription<dynamic>? _geofenceZonesSub;
  bool _geofenceListenerStarted = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fpStreamSub;
  bool _fingerprintEnrolled = true;
  bool _fpStatusLoaded = false;
  bool _fpPromptDismissed = false;

  bool _challengeScreenOpen = false;
  bool _missedSummaryShown = false;

  final GlobalKey<DashboardScreenState> _dashboardKey =
  GlobalKey<DashboardScreenState>();

  Color _navBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  }

  Color _navBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  }

  static const Color _navActive = Color(0xFFFF8A00);
  static const Color _navInactive = Color(0xFF71717A);

  // ══════════════════════════════════════════════════════════════
  // FINGERPRINT HELPERS
  // ══════════════════════════════════════════════════════════════
  bool _isEnrolledFromData(Map<String, dynamic>? data) {
    if (data == null) return false;
    final v = data['fingerprintEnrolled'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  void _startFingerprintListener() {
    final id = widget.employee?.id;
    if (id == null || id.isEmpty) {
      _secureLog('⚠️ [FP] No employee ID — fingerprint listener skipped');
      _fpStatusLoaded = true;
      return;
    }

    try {
      _secureLog('🔐 Starting fingerprint status listener for $id');
      _fpStreamSub?.cancel();
      _fpStreamSub = FirebaseFirestore.instance
          .collection('employees')
          .doc(id)
          .snapshots()
          .listen(
            (snap) {
          if (!mounted) return;
          final data = snap.data();
          final enrolled = _isEnrolledFromData(data);
          _secureLog('🔐 [FP] Status update: enrolled=$enrolled');

          setState(() {
            _fingerprintEnrolled = enrolled;
            _fpStatusLoaded = true;
            if (enrolled) _fpPromptDismissed = false;
          });
        },
        onError: (e) {
          _secureLog('❌ [FP] Listener error: $e');
          if (mounted) setState(() => _fpStatusLoaded = true);
        },
      );
    } catch (e) {
      _secureLog('❌ [FP] Listener setup failed: $e');
      _fpStatusLoaded = true;
    }
  }

  void _stopFingerprintListener() {
    _fpStreamSub?.cancel();
    _fpStreamSub = null;
  }

  Future<void> _openFingerprintRegistration() async {
    final emp = widget.employee;
    if (emp == null) return;

    if (!_isOnline) {
      _showOfflineSnack(
          '⚠️ Kailangan ng internet para mag-register ng fingerprint.');
      return;
    }

    _secureLog('🔐 Opening FingerprintScreen (registration flow)');

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FingerprintScreen(
          employee: emp,
          standaloneMode: true,
        ),
      ),
    );

    if (!mounted) return;
    _secureLog('🔐 Returned from FingerprintScreen');
  }

  // ══════════════════════════════════════════════════════════════
  // PRESENCE CHALLENGE HANDLER
  // ══════════════════════════════════════════════════════════════
  Future<void> _handlePresenceChallenge(ChallengeDue due) async {
    if (!mounted) return;
    if (_challengeScreenOpen) {
      _secureLog('⚠️ [Challenge] Screen already open — skipping');
      return;
    }

    final emp = widget.employee;
    if (emp == null) {
      _secureLog('⚠️ [Challenge] No employee — skipping');
      return;
    }

    final challenge = due.challenge;
    _secureLog('🎯 [Challenge] Fired: ${challenge.id} '
        '(inside=${due.isInside}, '
        'dist=${due.distanceMeters?.toStringAsFixed(0)}m)');

    if (!due.isInside) {
      final proceed = await _showOutsideWarningDialog(due);
      if (proceed != true) {
        _secureLog('🚪 [Challenge] User dismissed outside warning');
        return;
      }
    }

    _secureLog('🎯 [Challenge] AUTO-OPENING verification for ${challenge.id}');
    _challengeScreenOpen = true;

    try {
      final passed = await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FacialRecognitionScreen(
            employee: emp,
            challenge: challenge,
          ),
        ),
      );

      if (!mounted) return;

      if (passed == true) {
        _secureLog('✅ [Challenge] PASSED for ${challenge.id}');
        _showChallengeSnack(
          '✅ Presence verified. Salamat!',
          const Color(0xFF16A34A),
        );
      } else {
        _secureLog('❌ [Challenge] FAILED for ${challenge.id}');
        _showChallengeSnack(
          '⚠️ Presence verification failed. Admin has been notified.',
          const Color(0xFFDC2626),
        );
      }
    } catch (e) {
      _secureLog('❌ [Challenge] Navigation error: $e');
    } finally {
      _challengeScreenOpen = false;
    }
  }

  Future<bool?> _showOutsideWarningDialog(ChallengeDue due) {
    if (!mounted) return Future.value(false);

    final dist = due.distanceMeters;
    final radius = due.radiusUsed;
    final zone = due.zoneName ?? 'Unknown';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.location_off_rounded,
                color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nasa Labas Ka ng Work Zone',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Random presence check required. Pero nasa labas ka ng '
                  'perimeter ng office.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kvRow('Nearest zone', zone),
                  if (dist != null)
                    _kvRow('Distance', '${dist.toStringAsFixed(0)}m'),
                  if (radius != null)
                    _kvRow('Allowed radius', '${radius.toStringAsFixed(0)}m'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ Bumalik ka muna sa loob ng work zone para maging '
                  'valid ang presence check.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Bumalik sa Loob',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Continue Anyway',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleMissedSummary(int missedCount) {
    if (!mounted) return;
    if (_missedSummaryShown) {
      _secureLog('ℹ️ [Challenge] Missed summary already shown — skip');
      return;
    }
    _missedSummaryShown = true;

    _secureLog('⚠️ [Challenge] $missedCount missed challenge(s) flagged');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Missed Presence Check',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'May $missedCount presence check na hindi mo nasagot.\n\n'
                'Ang mga ito ay na-flag na sa iyong attendance record at '
                'na-notify na ang admin.\n\n'
                'Mangyaring huwag i-exit ang app habang naka-clock-in para '
                'hindi ito maulit.',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Naiintindihan ko',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showChallengeSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PRESENCE HELPERS
  // ══════════════════════════════════════════════════════════════
  String? get _presenceDocId {
    final id = widget.employee?.id;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> _markOnline() async {
    final id = _presenceDocId;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(id)
          .update({
        'isOnline': true,
        'isLoggedIn': true,
        'status': 'online',
        'lastActive': FieldValue.serverTimestamp(),
      });
      _secureLog('✅ [Presence] Online heartbeat sent: $id');
    } catch (e) {
      _secureLog('⚠️ [Presence] Online update failed: $e');
    }
  }

  Future<void> _markOffline() async {
    final id = _presenceDocId;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(id)
          .update({
        'isOnline': false,
        'isLoggedIn': false,
        'status': 'inactive',
      });
      _secureLog('✅ [Presence] Marked OFFLINE: $id');
    } catch (e) {
      _secureLog('⚠️ [Presence] Offline update failed: $e');
    }
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = Timer.periodic(
      const Duration(minutes: 5),
          (_) => _markOnline(),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // GEOFENCE LISTENER
  // ══════════════════════════════════════════════════════════════
  void _startGeofenceListener() {
    if (_geofenceListenerStarted) {
      _secureLog('⚠️ [Geofence] Listener already started — skip');
      return;
    }

    try {
      _secureLog('🚀 Starting Geofence real-time listener...');
      GeofenceService.instance.startZonesListener();
      GeofenceService.instance.forceReload();
      _geofenceListenerStarted = true;
      _secureLog('✅ Geofence listener ACTIVE');
    } catch (e) {
      _secureLog('❌ Geofence listener failed: $e');
    }
  }

  void _stopGeofenceListener() {
    try {
      GeofenceService.instance.stopZonesListener();
      _geofenceZonesSub?.cancel();
      _geofenceZonesSub = null;
      _geofenceListenerStarted = false;
      _secureLog('🛑 Geofence listener stopped');
    } catch (e) {
      _secureLog('⚠️ Geofence stop failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LOGOUT
  // ══════════════════════════════════════════════════════════════
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Logout?'),
        content: const Text(
          'Are you sure you want to logout? Your status will be set to Inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _markOffline();
    } catch (_) {}

    try {
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'type': 'logout',
        'employeeId': _presenceDocId,
        'employee_id': _presenceDocId,
        'employee_name': widget.employee?.fullName ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'device': kIsWeb ? 'Web Browser' : 'Mobile App',
      });
    } catch (_) {}

    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    // 🆕 OneSignal — i-logout ang external ID
    try {
      OneSignal.logout();
      debugPrint('🔔 [OneSignal] Logged out');
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_show_landing', true);
      await prefs.setInt(
        'force_show_landing_at',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LandingScreen(),
        settings: const RouteSettings(
          name: '/landing-after-manual-logout',
          arguments: {'skipSessionRestore': true},
        ),
      ),
          (route) => false,
    );
  }

  void switchTab(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _showClockOverlay = false;
    });
  }

  void switchTabWithHistory(int index) {
    if (!mounted) return;
    if (_selectedIndex == index) return;
    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _showClockOverlay = false;
    });
  }

  void goBackToPrevious() {
    if (!mounted) return;
    _secureLog('🔙 Returning to previous tab: $_previousIndex');
    setState(() {
      _selectedIndex = _previousIndex;
      _showClockOverlay = false;
    });
  }

  // ══════════════════════════════════════════════════════════════
  // OPEN CLOCK SCREEN
  // ══════════════════════════════════════════════════════════════
  void _openClockOverlay() {
    if (!_isOnline) {
      _showOfflineSnack('⚠️ Walang internet. Paki-check ang connection.');
      return;
    }

    if (!_fingerprintEnrolled) {
      _secureLog(
          '🔐 Fingerprint not enrolled — redirecting to registration first');
      _showFingerprintRequiredDialog();
      return;
    }

    _secureLog('🟢 Opening ClockScreen overlay');

    try {
      GeofenceService.instance.invalidateCache();
      _secureLog('🔄 Geofence cache invalidated bago mag-clock');
    } catch (e) {
      _secureLog('⚠️ Geofence refresh failed: $e');
    }

    setState(() => _showClockOverlay = true);
  }

  void _toggleClockOverlay() {
    if (_showClockOverlay) {
      _secureLog('🔽 Closing ClockScreen overlay (FAB tap)');
      setState(() => _showClockOverlay = false);
    } else {
      _openClockOverlay();
    }
  }

  void _showFingerprintRequiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(children: const [
          Icon(Icons.fingerprint_rounded,
              color: Color(0xFFFF8A00), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fingerprint Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        content: const Text(
          'Kailangan mo munang i-register ang fingerprint mo bago '
              'makapag-clock in/out.\n\n'
              'Ito ay isang beses lang gagawin. Tapos, fingerprint '
              'na ang gagamitin mo para sa bawat clock action.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mamaya'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.app_registration_rounded, size: 16),
            label: const Text(
              'Register Now',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _openFingerprintRegistration();
            },
          ),
        ],
      ),
    );
  }

  void _refreshDashboard() {
    _secureLog('🔄 Refreshing dashboard data...');
    _dashboardKey.currentState?.loadTodayAttendance();
    _dashboardKey.currentState?.loadPayslipAmount();
  }

  void _closeClockOverlayAndRefresh() {
    if (!mounted) return;
    _secureLog(
        '✅ Clock action done — closing overlay + refreshing dashboard');
    setState(() {
      _showClockOverlay = false;
      _selectedIndex = 0;
    });
    _refreshDashboard();
  }

  void _showOfflineSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _bootstrapChallengeService(model.Employee emp) async {
    final challengeEmpId =
    emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;

    if (challengeEmpId.isEmpty) {
      _secureLog('⚠️ [Challenge] Empty employee ID — skipping start');
      return;
    }

    try {
      _secureLog('🚀 [Challenge] Bootstrapping service for $challengeEmpId');
      await PresenceChallengeService.instance.start(
        challengeEmpId,
        employeeName: emp.fullName,
      );
      _secureLog('🛰️ [Challenge] Service STARTED');

      await PresenceChallengeService.instance.checkNow();
      _secureLog('⚡ [Challenge] Initial checkNow() done');
    } catch (e) {
      _secureLog('❌ [Challenge] Bootstrap failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // INIT + DISPOSE
  // ══════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    try {
      SecurityHardeningService.instance.enableSecureScreen();
    } catch (_) {}

    LocalNotificationService.instance.init();

    _startGeofenceListener();
    _startFingerprintListener();

    final empId = widget.employee?.employeeId ?? '';
    if (empId.isNotEmpty) {
      _notifWatcher = EmployeeNotificationWatcher(empId)..start();
      _secureLog('🔔 Watcher attached to employee: $empId');
    }

    final emp = widget.employee;
    if (emp != null) {
      // 🆕 OneSignal — para ma-target ang notification sa employee na ito
      final bgEmpId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
      if (bgEmpId.isNotEmpty) {
        try {
          OneSignal.login(bgEmpId);
          _secureLog('🔔 [OneSignal] Logged in as $bgEmpId');
        } catch (e) {
          _secureLog('⚠️ [OneSignal] Login failed: $e');
        }
      }

      PresenceMonitorService.instance.start(employee: emp);
      _secureLog('🛰️ Presence monitor started for ${emp.fullName}');

      MotionDetectionService.instance.start(
        employeeId: emp.employeeId.isNotEmpty ? emp.employeeId : emp.id,
        employeeDocId: emp.id,
        employeeName: emp.fullName,
      );
      _secureLog('🚶 Motion detection started for ${emp.fullName}');

      _markOnline();
      _startPresenceHeartbeat();

      PresenceChallengeService.instance.onDue = _handlePresenceChallenge;
      _secureLog('🎯 [Challenge] onDue callback hooked (AUTO mode)');

      PresenceChallengeService.instance.onMissedSummary = _handleMissedSummary;
      _secureLog('🎯 [Challenge] onMissedSummary callback hooked');

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _bootstrapChallengeService(emp);
      });
    }

    try {
      _isOnline = ConnectivityService.instance.isOnline;
    } catch (_) {
      _isOnline = true;
    }

    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            _secureLog('🌐 connectivity → online=$online');
            setState(() => _isOnline = online);
            if (online) {
              _markOnline();
              try {
                GeofenceService.instance.forceReload();
              } catch (_) {}
              try {
                PresenceChallengeService.instance.checkNow();
              } catch (_) {}
            }
          });
    } catch (e) {
      _secureLog('⚠️ connectivity failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _presenceHeartbeat?.cancel();
    _resumeDebounce?.cancel();
    _markOffline();
    _stopGeofenceListener();

    _stopFingerprintListener();

    _notifWatcher?.stop();
    PresenceMonitorService.instance.stop();

    MotionDetectionService.instance.stop();

    PresenceChallengeService.instance.onDue = null;
    PresenceChallengeService.instance.onMissedSummary = null;

    _networkSub?.cancel();

    try {
      SecurityHardeningService.instance.disableSecureScreen();
    } catch (_) {}

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_presenceDocId == null) return;

    _secureLog('📱 Lifecycle → $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _markOnline();
        _startPresenceHeartbeat();
        try {
          GeofenceService.instance.forceReload();
          _secureLog('🔄 Geofence zones refreshed');
        } catch (_) {}

        _resumeDebounce?.cancel();
        _resumeDebounce = Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          try {
            PresenceChallengeService.instance.checkNow();
            _secureLog('⚡ [Challenge] checkNow() on resume');
          } catch (e) {
            _secureLog('⚠️ [Challenge] checkNow failed: $e');
          }
        });
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _presenceHeartbeat?.cancel();
        _markOffline();
        break;
    }
  }

  static const List<_NavData> _navItems = [
    _NavData(label: 'Home', index: 0, svg: _homeSvg),
    _NavData(label: 'Logs', index: 1, svg: _logsSvg),
    _NavData(label: 'Leave', index: 2, svg: _leaveSvg),
    _NavData(label: 'Profile', index: 3, svg: _profileSvg),
  ];

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb && MediaQuery.of(context).size.width >= 768;

    final empId = widget.employee?.employeeId ?? '';
    final empName = widget.employee?.fullName ?? 'Guest';

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Row(
        children: [
          if (isWeb) _buildWebSidebar(),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: isWeb ? 0 : 70,
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      DashboardScreen(
                        key: _dashboardKey,
                        onTabSwitch: switchTabWithHistory,
                        onClockAction: _openClockOverlay,
                        initialEmployee: widget.employee,
                      ),
                      AttendanceHistoryScreen(
                        initialEmployee: widget.employee,
                        onBack: goBackToPrevious,
                      ),
                      LeaveFormScreen(
                        employeeId: empId,
                        employeeName: empName,
                        onGoHome: goBackToPrevious,
                      ),
                      ProfileScreen(initialEmployee: widget.employee),
                    ],
                  ),
                ),

                if (_showClockOverlay && widget.employee != null)
                  Positioned.fill(
                    child: ClockScreen(
                      initialEmployee: widget.employee,
                      onBack: () {
                        if (mounted) {
                          setState(() => _showClockOverlay = false);
                        }
                      },
                      onClockIn: _closeClockOverlayAndRefresh,
                      onClockOut: _closeClockOverlayAndRefresh,
                      onShortcutHome: _closeClockOverlayAndRefresh,
                      onShortcutProfile: () {
                        if (mounted) {
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = 3;
                          });
                        }
                      },
                      onShortcutLeaves: () {
                        if (mounted) {
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = 2;
                          });
                        }
                      },
                      onNavTap: (i) {
                        if (mounted) {
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = i;
                          });
                        }
                      },
                    ),
                  ),

                if (!_isOnline)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: _buildOfflineBanner(),
                    ),
                  ),

                if (_fpStatusLoaded &&
                    !_fingerprintEnrolled &&
                    !_fpPromptDismissed &&
                    _isOnline &&
                    widget.employee != null &&
                    !_showClockOverlay)
                  Positioned(
                    top: !_isOnline ? 60 : 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: _buildFingerprintBanner(),
                    ),
                  ),

                if (empId.isNotEmpty)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: SafeArea(
                      child: EmployeeNotificationBell(
                        employeeId: empId,
                        iconColor: AppColors.orange,
                        size: 22,
                      ),
                    ),
                  ),

                if (!isWeb)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildMobileBottomNav(context),
                  ),
              ],
            ),
          ),
        ],
      ),

      floatingActionButton: _buildClockFab(context),
      floatingActionButtonLocation: isWeb
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Walang internet — offline mode',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFingerprintBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A00), Color(0xFFF54900)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Register Your Fingerprint',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Kailangan ito para makapag-clock in/out.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: _openFingerprintRegistration,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFFF8A00),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Register',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _fpPromptDismissed = true),
            icon: const Icon(Icons.close_rounded,
                color: Colors.white, size: 18),
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildClockFab(BuildContext context) {
    final enabled = _isOnline;
    final needsRegistration = _fpStatusLoaded && !_fingerprintEnrolled;
    final overlayOpen = _showClockOverlay;

    final Color bg = !enabled
        ? const Color(0xFF7A7A7A)
        : (needsRegistration && !overlayOpen
        ? const Color(0xFFDC2626)
        : _navActive);

    final String iconKey;
    final IconData icon;
    if (!enabled) {
      iconKey = 'offline';
      icon = Icons.wifi_off_rounded;
    } else if (overlayOpen) {
      iconKey = 'close';
      icon = Icons.close_rounded;
    } else if (needsRegistration) {
      iconKey = 'register';
      icon = Icons.app_registration_rounded;
    } else {
      iconKey = 'fingerprint';
      icon = Icons.fingerprint_rounded;
    }

    final String tooltip;
    if (!enabled) {
      tooltip = 'Offline';
    } else if (overlayOpen) {
      tooltip = 'Close Clock Screen';
    } else if (needsRegistration) {
      tooltip = 'Register Fingerprint';
    } else {
      tooltip = 'Clock In / Out';
    }

    final VoidCallback? onPressed = !enabled
        ? null
        : (overlayOpen ? _toggleClockOverlay : _openClockOverlay);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: enabled && !overlayOpen
            ? [
          BoxShadow(
            color: bg.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ]
            : null,
      ),
      child: FloatingActionButton(
        backgroundColor: bg,
        elevation: enabled ? 4 : 0,
        tooltip: tooltip,
        onPressed: onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) {
            return RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Icon(
            icon,
            key: ValueKey(iconKey),
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildWebSidebar() {
    final w = MediaQuery.of(context).size.width;
    final sidebarWidth = w >= 1200 ? 260.0 : 220.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildWebLogo(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                ..._navItems.map((item) => _webNavItem(item)),
                const Divider(height: 24),
                _webQuickLink(
                  label: _fingerprintEnrolled
                      ? 'Clock In/Out'
                      : 'Register Fingerprint',
                  icon: _fingerprintEnrolled
                      ? Icons.fingerprint_rounded
                      : Icons.app_registration_rounded,
                  onTap: _openClockOverlay,
                ),
              ],
            ),
          ),
          _buildWebProfileFooter(),
        ],
      ),
    );
  }

  Widget _buildWebLogo() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orange.withValues(alpha: 0.35),
                  blurRadius: 14,
                )
              ],
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HRIS',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
              Text('BIOMETRICS',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _webNavItem(_NavData item) {
    final active = _selectedIndex == item.index;
    final color = active ? _navActive : _navInactive;
    return InkWell(
      onTap: () => switchTabWithHistory(item.index),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.string(item.svg(color), width: 18, height: 18),
            const SizedBox(width: 14),
            Text(
              item.label.toUpperCase(),
              style: TextStyle(
                color: active ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            if (active) ...[
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _webQuickLink({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 14),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebProfileFooter() {
    final emp = widget.employee;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientOrange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(
                    emp?.initials ?? '?',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_fpStatusLoaded)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _fingerprintEnrolled
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFDC2626),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 2),
                    ),
                    child: Icon(
                      _fingerprintEnrolled
                          ? Icons.check_rounded
                          : Icons.priority_high_rounded,
                      size: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emp?.fullName ?? 'Guest',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                Row(children: [
                  Text(
                    emp?.position ?? 'User',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                  if (_fpStatusLoaded) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: _fingerprintEnrolled
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _fingerprintEnrolled ? 'FP ✓' : 'No FP',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: _fingerprintEnrolled
                              ? const Color(0xFF166534)
                              : const Color(0xFF991B1B),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          if (emp?.employeeId != null && emp!.employeeId.isNotEmpty)
            EmployeeNotificationBell(
              employeeId: emp.employeeId,
              iconColor: AppColors.textMuted,
              size: 20,
            ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.textMuted, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _navBg(context),
        border: Border(
          top: BorderSide(
            color: _navBorder(context),
            width: 1.15,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ..._navItems.sublist(0, 2).map(_navItemWidget),
              const SizedBox(width: 56),
              ..._navItems.sublist(2, 4).map(_navItemWidget),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItemWidget(_NavData item) {
    final active = _selectedIndex == item.index;
    final color = active ? _navActive : _navInactive;
    return GestureDetector(
      onTap: () => switchTabWithHistory(item.index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(item.svg(color), width: 24, height: 24),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SVG icons
  // ══════════════════════════════════════════════════════════════
  static String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2)}';

  static String _homeSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8.99951 3H3.99951C3.44723 3 2.99951 3.44772 2.99951 4V11C2.99951 11.5523 3.44723 12 3.99951 12H8.99951C9.5518 12 9.99951 11.5523 9.99951 11V4C9.99951 3.44772 9.5518 3 8.99951 3Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M19.9985 3H14.9985C14.4463 3 13.9985 3.44772 13.9985 4V7C13.9985 7.55228 14.4463 8 14.9985 8H19.9985C20.5508 8 20.9985 7.55228 20.9985 7V4C20.9985 3.44772 20.5508 3 19.9985 3Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M19.9985 11.999H14.9985C14.4463 11.999 13.9985 12.4467 13.9985 12.999V19.999C13.9985 20.5513 14.4463 20.999 14.9985 20.999H19.9985C20.5508 20.999 20.9985 20.5513 20.9985 19.999V12.999C20.9985 12.4467 20.5508 11.999 19.9985 11.999Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M8.99951 15.999H3.99951C3.44723 15.999 2.99951 16.4467 2.99951 16.999V19.999C2.99951 20.5513 3.44723 20.999 3.99951 20.999H8.99951C9.5518 20.999 9.99951 20.5513 9.99951 19.999V16.999C9.99951 16.4467 9.5518 15.999 8.99951 15.999Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _logsSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M11.9991 21.9982C17.5215 21.9982 21.9982 17.5215 21.9982 11.9991C21.9982 6.47676 17.5215 2 11.9991 2C6.47676 2 2 6.47676 2 11.9991C2 17.5215 6.47676 21.9982 11.9991 21.9982Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M11.999 5.99902V11.999L15.999 13.999" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _leaveSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M14 2H6C5.46957 2 4.96086 2.21071 4.58579 2.58579C4.21071 2.96086 4 3.46957 4 4V20C4 20.5304 4.21071 21.0391 4.58579 21.4142C4.96086 21.7893 5.46957 22 6 22H18C18.5304 22 19.0391 21.7893 19.4142 21.4142C19.7893 21.0391 20 20.5304 20 20V8L14 2Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M14 2V8H20" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M9 15L11 17L15 13" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _profileSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18.9983 20.9985V18.9987C18.9983 17.9379 18.5769 16.9206 17.8268 16.1705C17.0767 15.4204 16.0594 14.999 14.9986 14.999H8.99916C7.93839 14.999 6.92106 15.4204 6.17098 16.1705C5.4209 16.9206 4.99951 17.9379 4.99951 18.9987V20.9985" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M11.9995 11C14.2087 11 15.9995 9.20914 15.9995 7C15.9995 4.79086 14.2087 3 11.9995 3C9.79037 3 8.00049 4.79086 8.00049 7C8.00049 9.20914 9.79037 11 11.9995 11Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }
}

class _NavData {
  final String label;
  final int index;
  final String Function(Color color) svg;

  const _NavData({
    required this.label,
    required this.index,
    required this.svg,
  });
}