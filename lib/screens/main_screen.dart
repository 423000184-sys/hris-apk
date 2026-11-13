// lib/screens/main_screen.dart
// v2.5: 🚫 Removed fingerprint registration gate — clock in/out no longer
//       requires fingerprint enrollment. No banner, no dialog, no FAB state,
//       no web sidebar/profile badges.
// v2.4: ⏱️ Added local clock marker — instant UI feedback on successful clock-in/out
//       without waiting for the Firestore snapshot.
// v2.3: 🛠️ Fixed infinite rebuild loops in Network listener.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
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
import '../services/demo_mode_service.dart';
import '../services/overtime_reminder_service.dart';
import '../services/trusted_time_service.dart';
import '../services/app_permission_service.dart';
import 'dashboard_screen.dart';
import 'clock_screen.dart';
import 'attendance_history_screen.dart';
import 'apply_leave_screen.dart';
import 'itinerary_screen.dart';
import 'profile_screen.dart';
import 'landing_screen.dart';
import 'facial_recognition_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint('[MainScreen] $message');
}

// ══════════════════════════════════════════════════════════════
// LOCAL CLOCK MARKER
// ══════════════════════════════════════════════════════════════
// Persists the last successful clock state locally so the UI can
// react instantly without waiting for the Firestore snapshot.
// Keyed per employee (both docId and employeeId) so multiple
// accounts on the same device don't collide.
//
// Usage from ClockScreen (call this the moment the write succeeds):
//   await saveLocalClockMarker(
//     employeeIds: [employee.id, employee.employeeId],
//     isClockIn: true, // false for OUT
//   );
//
// Usage from any widget that wants instant state:
//   final marker = await readLocalClockMarker([emp.id, emp.employeeId]);
//   // marker == true → clocked in; false → clocked out; null → unknown
// ══════════════════════════════════════════════════════════════

const String _kClockMarkerPrefix = 'local_clock_marker_';
const String _kClockMarkerAtSuffix = '_at';

String _clockMarkerKey(String employeeId) => '$_kClockMarkerPrefix$employeeId';

String _clockMarkerAtKey(String employeeId) =>
    '$_kClockMarkerPrefix$employeeId$_kClockMarkerAtSuffix';

/// Saves the clock state (`true` = clocked IN, `false` = clocked OUT)
/// for every provided employee identifier. Also records a timestamp.
///
/// Safe to call with an empty/duplicate list; blanks are skipped.
Future<void> saveLocalClockMarker({
  required List<String> employeeIds,
  required bool isClockIn,
}) async {
  final ids =
  employeeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  if (ids.isEmpty) return;

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final prefs = await SharedPreferences.getInstance();

  for (final id in ids) {
    await prefs.setBool(_clockMarkerKey(id), isClockIn);
    await prefs.setInt(_clockMarkerAtKey(id), nowMs);
  }
  _secureLog(
    '⏱️ [LocalMarker] saved isClockIn=$isClockIn for ${ids.length} id(s): $ids',
  );
}

/// Reads the last local clock state for the given identifiers.
/// Returns `null` if no marker exists for any of them.
Future<bool?> readLocalClockMarker(List<String> employeeIds) async {
  final ids =
  employeeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  if (ids.isEmpty) return null;

  final prefs = await SharedPreferences.getInstance();
  for (final id in ids) {
    final v = prefs.getBool(_clockMarkerKey(id));
    if (v != null) return v;
  }
  return null;
}

/// Returns the epoch-ms timestamp of the last marker for the given ids,
/// or `null` if none.
Future<int?> readLocalClockMarkerAt(List<String> employeeIds) async {
  final ids =
  employeeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  if (ids.isEmpty) return null;

  final prefs = await SharedPreferences.getInstance();
  for (final id in ids) {
    final v = prefs.getInt(_clockMarkerAtKey(id));
    if (v != null) return v;
  }
  return null;
}

/// Clears markers (e.g. on logout) so a fresh session starts clean.
Future<void> clearLocalClockMarkers(List<String> employeeIds) async {
  final ids =
  employeeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  if (ids.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  for (final id in ids) {
    await prefs.remove(_clockMarkerKey(id));
    await prefs.remove(_clockMarkerAtKey(id));
  }
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

  bool _challengeScreenOpen = false;
  bool _missedSummaryShown = false;

  final GlobalKey<DashboardScreenState> _dashboardKey =
  GlobalKey<DashboardScreenState>();

  bool get _isDemo => DemoModeService.instance.isEnabled;

  model.Employee? get _effectiveEmployee =>
      _isDemo ? DemoModeService.demoEmployee : widget.employee;

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
  static const Color _demoAccent = Color(0xFFFF8A00);
  static const Color _demoAccentDark = Color(0xFFF54900);

  Future<void> _recoverOvertimeReminders() async {
    if (_isDemo) return;
    final emp = widget.employee;
    if (emp == null) return;

    final empId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
    if (empId.isEmpty) return;

    try {
      await OvertimeReminderService.instance.recoverIfStillClockedIn(empId);
    } catch (e) {
      _secureLog('⚠️ [OT] Recovery failed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Local clock marker bridge
  // ─────────────────────────────────────────────────────────────

  /// Convenience: saves the local marker using the effective employee's
  /// identifiers. Called by ClockScreen at the exact moment of a
  /// successful clock-in/out, and defensively from the callbacks below.
  Future<void> _saveLocalClockMarker({required bool isClockIn}) async {
    final emp = _effectiveEmployee;
    if (emp == null) return;
    if (_isDemo) return; // demo mode must not persist anything
    await saveLocalClockMarker(
      employeeIds: [emp.id, emp.employeeId],
      isClockIn: isClockIn,
    );
  }

  Future<void> _handlePresenceChallenge(ChallengeDue due) async {
    if (_isDemo) return;
    if (!mounted) return;
    if (_challengeScreenOpen) return;

    final emp = widget.employee;
    if (emp == null) return;

    final challenge = due.challenge;

    if (!due.isInside) {
      final proceed = await _showOutsideWarningDialog(due);
      if (proceed != true) return;
    }

    _challengeScreenOpen = true;
    try {
      final passed = await Navigator.of(context, rootNavigator: true)
          .push<bool>(
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
        _showChallengeSnack(
            '✅ Presence verified. Thank you!', const Color(0xFF16A34A));
      } else {
        _showChallengeSnack(
            '⚠️ Presence verification failed. Admin has been notified.',
            const Color(0xFFDC2626));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_off_rounded,
                color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 10),
            Expanded(
                child: Text('You Are Outside the Work Zone',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'A random presence check is required. However, you are currently outside the office perimeter.',
                style: TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8)),
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
                '⚠️ Please return inside the work zone first so the presence check can be valid.',
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Return Inside',
                  style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue Anyway',
                style: TextStyle(fontWeight: FontWeight.w700)),
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
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1F2937),
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  void _handleMissedSummary(int missedCount) {
    if (_isDemo) return;
    if (!mounted) return;
    if (_missedSummaryShown) return;
    _missedSummaryShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 10),
              Expanded(
                  child: Text('Missed Presence Check',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800))),
            ],
          ),
          content: Text(
            'You have missed $missedCount presence check${missedCount > 1 ? "s" : ""}.\n\nThese have been flagged on your attendance record and the admin has been notified.\n\nPlease do not exit the app while clocked in so this does not happen again.',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I Understand',
                  style: TextStyle(fontWeight: FontWeight.w700)),
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
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? get _presenceDocId {
    if (_isDemo) return null;
    final id = widget.employee?.id;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> _markOnline() async {
    if (_isDemo) return;
    final id = _presenceDocId;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance.collection('employees').doc(id).update({
        'isOnline': true,
        'isLoggedIn': true,
        'status': 'online',
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('⚠️ [Presence] Online update failed: $e');
    }
  }

  Future<void> _markOffline() async {
    if (_isDemo) return;
    final id = _presenceDocId;
    if (id == null) return;
    try {
      await FirebaseFirestore.instance.collection('employees').doc(id).update({
        'isOnline': false,
        'isLoggedIn': false,
        'status': 'inactive',
      });
    } catch (e) {
      _secureLog('⚠️ [Presence] Offline update failed: $e');
    }
  }

  void _startPresenceHeartbeat() {
    if (_isDemo) return;
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat =
        Timer.periodic(const Duration(minutes: 5), (_) => _markOnline());
  }

  void _startGeofenceListener() {
    if (_isDemo) return;
    if (_geofenceListenerStarted) return;
    try {
      GeofenceService.instance.startZonesListener();
      GeofenceService.instance.forceReload();
      _geofenceListenerStarted = true;
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
    } catch (e) {
      _secureLog('⚠️ Geofence stop failed: $e');
    }
  }

  Future<void> _handleLogout() async {
    if (_isDemo) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: const [
            Icon(Icons.science_rounded, color: _demoAccent, size: 22),
            SizedBox(width: 10),
            Expanded(
                child: Text('Exit Demo Mode?',
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ]),
          content: const Text(
              'You will return to the login screen. Demo data will NOT be saved.',
              style: TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _demoAccent,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit Demo')),
          ],
        ),
      );
      if (confirm != true) return;
      DemoModeService.instance.disable();
      try {
        await OvertimeReminderService.instance.cancelAll();
      } catch (_) {}
      try {
        final emp = DemoModeService.demoEmployee;
        await clearLocalClockMarkers([emp.id, emp.employeeId]);
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (_) => const LandingScreen(),
            settings: const RouteSettings(
                name: '/landing-after-demo-exit',
                arguments: {'skipSessionRestore': true})),
            (route) => false,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout?'),
        content: const Text(
            'Are you sure you want to logout? Your status will be set to Inactive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await OvertimeReminderService.instance.cancelAll();
    } catch (_) {}
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
    try {
      OneSignal.logout();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_show_landing', true);
      await prefs.setInt(
          'force_show_landing_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}

    // ⏱️ Clear local clock markers so next session starts clean
    try {
      final emp = widget.employee;
      if (emp != null) {
        await clearLocalClockMarkers([emp.id, emp.employeeId]);
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => const LandingScreen(),
          settings: const RouteSettings(
              name: '/landing-after-manual-logout',
              arguments: {'skipSessionRestore': true})),
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
    setState(() {
      _selectedIndex = _previousIndex;
      _showClockOverlay = false;
    });
  }

  void _openClockOverlay() {
    if (_isDemo) {
      setState(() => _showClockOverlay = true);
      return;
    }
    if (!_isOnline) {
      _showOfflineSnack('⚠️ No internet. Please check your connection.');
      return;
    }
    try {
      GeofenceService.instance.invalidateCache();
    } catch (e) {}
    setState(() => _showClockOverlay = true);
  }

  void _toggleClockOverlay() {
    if (_showClockOverlay) {
      setState(() => _showClockOverlay = false);
    } else {
      _openClockOverlay();
    }
  }

  void _refreshDashboard() {
    _dashboardKey.currentState?.loadTodayAttendance();
    _dashboardKey.currentState?.loadPayslipAmount();
  }

  /// Closes the clock overlay, refreshes the dashboard, and — if
  /// [isClockIn] is non-null — defensively writes the local clock marker.
  /// ClockScreen should already call [saveLocalClockMarker] at the moment
  /// of success; this is an idempotent fallback.
  void _closeClockOverlayAndRefresh({bool? isClockIn}) {
    if (!mounted) return;

    if (isClockIn != null) {
      unawaited(_saveLocalClockMarker(isClockIn: isClockIn));
    }

    setState(() {
      _showClockOverlay = false;
      _selectedIndex = 0;
    });
    _refreshDashboard();
    unawaited(_recoverOvertimeReminders());
  }

  void _showOfflineSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _bootstrapChallengeService(model.Employee emp) async {
    if (_isDemo) return;
    final challengeEmpId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
    if (challengeEmpId.isEmpty) return;
    try {
      await PresenceChallengeService.instance
          .start(challengeEmpId, employeeName: emp.fullName);
      await PresenceChallengeService.instance.checkNow();
    } catch (e) {
      _secureLog('❌ [Challenge] Bootstrap failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    if (_isDemo) {
      try {
        _isOnline = ConnectivityService.instance.isOnline;
      } catch (_) {
        _isOnline = true;
      }
      try {
        _networkSub =
            ConnectivityService.instance.onStatusChange.listen((online) {
              if (!mounted) return;
              if (_isOnline == online) return; // ✅ FIX
              setState(() => _isOnline = online);
            });
      } catch (e) {}
      return;
    }

    // NORMAL MODE
    try {
      SecurityHardeningService.instance.enableSecureScreen();
    } catch (_) {}
    LocalNotificationService.instance.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppPermissionService.instance.requestAllPermissions(context);
      }
    });

    _startGeofenceListener();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await OvertimeReminderService.instance.init();
      } catch (e) {}
      try {
        await TrustedTimeService.instance.syncWithServer();
      } catch (e) {}
      await _recoverOvertimeReminders();
    });

    final empId = widget.employee?.employeeId ?? '';
    if (empId.isNotEmpty) {
      _notifWatcher = EmployeeNotificationWatcher(empId)..start();
    }

    final emp = widget.employee;
    if (emp != null) {
      final bgEmpId = emp.employeeId.isNotEmpty ? emp.employeeId : emp.id;
      if (bgEmpId.isNotEmpty) {
        try {
          OneSignal.login(bgEmpId);
        } catch (e) {}
      }
      PresenceMonitorService.instance.start(employee: emp);
      MotionDetectionService.instance.start(
        employeeId: emp.employeeId.isNotEmpty ? emp.employeeId : emp.id,
        employeeDocId: emp.id,
        employeeName: emp.fullName,
      );
      _markOnline();
      _startPresenceHeartbeat();

      PresenceChallengeService.instance.onDue = _handlePresenceChallenge;
      PresenceChallengeService.instance.onMissedSummary = _handleMissedSummary;

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

            // ✅ FIX: Stop the loop! Only trigger heavy reloads if online status changed
            if (_isOnline == online) return;

            setState(() => _isOnline = online);
            if (online) {
              _markOnline();
              try {
                GeofenceService.instance.forceReload();
              } catch (_) {}
              try {
                PresenceChallengeService.instance.checkNow();
              } catch (_) {}
              try {
                TrustedTimeService.instance.syncWithServer(force: true);
              } catch (_) {}
              unawaited(_recoverOvertimeReminders());
            }
          });
    } catch (e) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    _resumeDebounce?.cancel();
    _markOffline();
    _stopGeofenceListener();
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
    if (_isDemo) return;
    if (_presenceDocId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _markOnline();
        _startPresenceHeartbeat();
        try {
          GeofenceService.instance.forceReload();
        } catch (_) {}
        try {
          TrustedTimeService.instance.syncWithServer(force: false);
        } catch (_) {}
        unawaited(_recoverOvertimeReminders());
        _resumeDebounce?.cancel();
        _resumeDebounce = Timer(const Duration(milliseconds: 600), () {
          if (!mounted) return;
          try {
            PresenceChallengeService.instance.checkNow();
          } catch (e) {}
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
    final emp = _effectiveEmployee;
    final empId = emp?.employeeId ?? '';
    final empName = emp?.fullName ?? 'Guest';

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
                          initialEmployee: emp),
                      AttendanceHistoryScreen(
                          initialEmployee: emp, onBack: goBackToPrevious),
                      LeaveFormScreen(
                          employeeId: empId,
                          employeeName: empName,
                          onGoHome: goBackToPrevious),
                      ProfileScreen(initialEmployee: emp),
                    ],
                  ),
                ),
                if (_showClockOverlay && emp != null)
                  Positioned.fill(
                    child: ClockScreen(
                      initialEmployee: emp,
                      onBack: () {
                        if (mounted)
                          setState(() => _showClockOverlay = false);
                      },
                      // ⏱️ Pass isClockIn so the local marker is written even
                      // if ClockScreen forgot to. ClockScreen should still call
                      // saveLocalClockMarker() directly at the moment of success.
                      onClockIn: () =>
                          _closeClockOverlayAndRefresh(isClockIn: true),
                      onClockOut: () =>
                          _closeClockOverlayAndRefresh(isClockIn: false),
                      onShortcutHome: _closeClockOverlayAndRefresh,
                      onShortcutProfile: () {
                        if (mounted)
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = 3;
                          });
                      },
                      onShortcutLeaves: () {
                        if (mounted)
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = 2;
                          });
                      },
                      onNavTap: (i) {
                        if (mounted)
                          setState(() {
                            _showClockOverlay = false;
                            _selectedIndex = i;
                          });
                      },
                    ),
                  ),
                if (!_isOnline && !_isDemo)
                  Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                          bottom: false, child: _buildOfflineBanner())),
                if (_isDemo)
                  Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child:
                      SafeArea(bottom: false, child: _buildDemoBadge())),
                if (empId.isNotEmpty && !_isDemo)
                  Positioned(
                      top: 12,
                      right: 12,
                      child: SafeArea(
                          child: EmployeeNotificationBell(
                              employeeId: empId,
                              iconColor: AppColors.orange,
                              size: 22))),
                if (!isWeb)
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildMobileBottomNav(context)),
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

  Widget _buildDemoBadge() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_demoAccent, _demoAccentDark]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: _demoAccent.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('DEMO MODE — No data is saved',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _handleLogout,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(999)),
              child: const Text('EXIT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
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
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('No internet — offline mode',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
        ],
      ),
    );
  }

  Widget _buildClockFab(BuildContext context) {
    if (_isDemo) {
      final overlayOpen = _showClockOverlay;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: !overlayOpen
              ? [
            BoxShadow(
                color: _navActive.withValues(alpha: 0.4),
                blurRadius: 14,
                offset: const Offset(0, 6))
          ]
              : null,
        ),
        child: FloatingActionButton(
          backgroundColor: _navActive,
          elevation: 4,
          tooltip: overlayOpen ? 'Close Clock Screen' : 'Clock In / Out',
          onPressed: overlayOpen ? _toggleClockOverlay : _openClockOverlay,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
                child: FadeTransition(opacity: animation, child: child)),
            child: Icon(overlayOpen ? Icons.close_rounded : Icons.fingerprint_rounded,
                key: ValueKey(overlayOpen ? 'demo-close' : 'demo-fp'),
                color: Colors.white,
                size: 26),
          ),
        ),
      );
    }

    final enabled = _isOnline;
    final overlayOpen = _showClockOverlay;

    final Color bg = !enabled ? const Color(0xFF7A7A7A) : _navActive;

    final String iconKey;
    final IconData icon;
    if (!enabled) {
      iconKey = 'offline';
      icon = Icons.wifi_off_rounded;
    } else if (overlayOpen) {
      iconKey = 'close';
      icon = Icons.close_rounded;
    } else {
      iconKey = 'fingerprint';
      icon = Icons.fingerprint_rounded;
    }

    final String tooltip;
    if (!enabled) {
      tooltip = 'Offline';
    } else if (overlayOpen) {
      tooltip = 'Close Clock Screen';
    } else {
      tooltip = 'Clock In / Out';
    }

    final VoidCallback? onPressed =
    !enabled ? null : (overlayOpen ? _toggleClockOverlay : _openClockOverlay);

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
              offset: const Offset(0, 6))
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
          transitionBuilder: (child, animation) => RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
              child: FadeTransition(opacity: animation, child: child)),
          child:
          Icon(icon, key: ValueKey(iconKey), color: Colors.white, size: 26),
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
                color: AppColors.orange.withValues(alpha: 0.12), width: 1)),
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
                  label: 'Clock In/Out',
                  icon: Icons.fingerprint_rounded,
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
                  color: AppColors.orange.withValues(alpha: 0.12), width: 1))),
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
                      blurRadius: 14)
                ]),
            child: Icon(
                _isDemo ? Icons.science_rounded : Icons.fingerprint_rounded,
                color: Colors.white,
                size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isDemo ? 'DEMO' : 'HRIS',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
              Text(_isDemo ? 'MODE' : 'BIOMETRICS',
                  style: const TextStyle(
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
              color: active
                  ? color.withValues(alpha: 0.3)
                  : Colors.transparent),
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
                  letterSpacing: 1.5),
            ),
            if (active) ...[
              const Spacer(),
              Container(
                  width: 4,
                  height: 4,
                  decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _webQuickLink(
      {required String label,
        required IconData icon,
        required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 14),
            Text(label.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                    letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildWebProfileFooter() {
    final emp = _effectiveEmployee;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: AppColors.orange.withValues(alpha: 0.12), width: 1))),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: AppColors.gradientOrange,
                borderRadius: BorderRadius.circular(4)),
            child: Center(
                child: Text(emp?.initials ?? '?',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emp?.fullName ?? 'Guest',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Row(children: [
                  Text(emp?.position ?? 'User',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                  if (_isDemo) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: _demoAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('DEMO',
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: _demoAccent,
                              letterSpacing: 0.3)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          if (emp?.employeeId != null &&
              emp!.employeeId.isNotEmpty &&
              !_isDemo)
            EmployeeNotificationBell(
                employeeId: emp.employeeId,
                iconColor: AppColors.textMuted,
                size: 20),
          IconButton(
            onPressed: _handleLogout,
            icon: Icon(
                _isDemo ? Icons.science_rounded : Icons.logout_rounded,
                color: _isDemo ? _demoAccent : AppColors.textMuted,
                size: 17),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _navBg(context),
        border: Border(top: BorderSide(color: _navBorder(context), width: 1.15)),
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
            Text(item.label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SVG icons
  // ══════════════════════════════════════════════════════════════
  static String _hex(Color c) => '#${c.toARGB32().toRadixString(16).substring(2)}';

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