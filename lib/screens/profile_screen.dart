// lib/screens/profile_screen.dart
// v1.2: 🎭 DEMO MODE now shows the SAME skeleton loading screen as normal mode.
//       Skeleton appears briefly (900ms), then fades into demo UI.
// v1.1: 🎭 DEMO MODE — skip session check, Firestore listeners,
//       presence challenge, security monitoring. Use demoEmployee.
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'privacy_policy_screen.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/security_hardening_service.dart';
import '../services/auth_service.dart';
import '../services/notification_preference_service.dart';
import '../services/language_service.dart';
import '../services/admin_notification_service.dart';
import '../services/demo_mode_service.dart';
import '../models/employee.dart';
import '../data/local/dao/connectivity_service.dart';
import '../widgets/skeleton_screens.dart';
import 'landing_screen.dart';
import 'login_screen.dart';
import 'reports_screen.dart';

// ═══════════════════════════════════════════════════════════════
// ✅ HAND WATERMARK
// ═══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';

double _degToRad(double deg) => deg * 3.1415926535 / 180;

Widget _buildHandWatermark({required double opacity}) {
  return Positioned(
    bottom: -130,
    left: -150,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: _degToRad(425),
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color.fromRGBO(255, 138, 0, 0.10),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              _kLogoAsset,
              width: 500,
              height: 500,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                debugPrint('logo.png failed to load');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _Mock {
  static const Color orange = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color red = Color(0xFFFB2C36);
  static const Color switchTrackOff = Color(0xFF3F3F46);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder => isDark ? const Color(0xFF3F3F46) : _Mock.orange;
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textMuted =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get rowDivider =>
      isDark ? const Color(0xFF27272A) : _Mock.orange.withValues(alpha: 0.3);
  Color get sectionLabel => isDark ? Colors.white : Colors.black;

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

enum _NetworkState { online, offline, checking }

class ProfileScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ProfileScreen({super.key, this.initialEmployee});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  Employee? _employee;
  bool _loading = true;

  bool _pushEnabled = true;
  bool _pushLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  StreamSubscription<bool>? _connectivitySub;

  bool _sendingPasswordRequest = false;
  DateTime? _lastPasswordRequest;
  static const _passwordCooldown = Duration(minutes: 10);
  static const String _kPasswordReqPrefsKey = 'profile_pwd_req_last';

  ThemeMode _themeMode = ThemeMode.system;

  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;

  // ═══════════════════════════════════════════════════════════════
  // 🔒 SECURITY STATE
  // ═══════════════════════════════════════════════════════════════
  static const Duration _sessionCacheTTL = Duration(seconds: 5);
  static const Duration _inactivityLimit = Duration(minutes: 30);

  // 🆕 Demo skeleton display duration
  static const Duration _demoSkeletonDuration = Duration(milliseconds: 900);

  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  bool _loggedOut = false;
  bool _sessionValidated = false;
  DateTime? _lastUserActivityAt;
  bool? _cachedSessionValid;
  DateTime? _cachedSessionTime;

  LanguageService get lang => LanguageService.instance;

  bool get _isDemo => DemoModeService.instance.isEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _lastUserActivityAt = DateTime.now();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — skip connectivity listener + security
    //             pero IPAKITA ANG SKELETON sa simula
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] Profile — DEMO PATH');
      debugPrint('   • Skipping connectivity listener');
      debugPrint('   • Skipping security monitoring');
      debugPrint('   • Skeleton shown for ${_demoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _employee = widget.initialEmployee ?? DemoModeService.demoEmployee;
      _networkState = _NetworkState.online;
      _sessionValidated = true;
      _loading = false;

      // 🆕 Keep skeleton visible at start
      _isInitialLoading = true;

      _loadPushPreference();
      _loadThemeMode();
      _loadPasswordCooldown();

      // 🆕 Hide skeleton after short delay
      Future.delayed(_demoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    _load();
    _loadPushPreference();
    _loadThemeMode();
    _loadPasswordCooldown();

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted || _loggedOut) return;
            debugPrint('🌐 [Profile] connectivity changed → online=$online');

            if (!online) {
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
                _showOfflineOverlay = false;
                _loading = true;
              });

              _overlayDelayTimer =
                  Timer(const Duration(milliseconds: 1200), () {
                    if (mounted && _networkState == _NetworkState.offline) {
                      setState(() => _showOfflineOverlay = true);
                    }
                  });
            } else if (_networkState == _NetworkState.offline) {
              _overlayDelayTimer?.cancel();
              _showOfflineOverlay = false;
              _retryNetworkCheck();
            }
          });
    } catch (e) {
      debugPrint('⚠️ [Profile] connectivity listen failed: $e');
    }

    _startSecurityMonitoring();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isInitialLoading = false);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 SECURITY — Session validation
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _validateSession({bool forceRefresh = false}) async {
    // 🎭 DEMO MODE — always valid
    if (_isDemo) return true;

    if (_loggedOut) return false;

    if (!forceRefresh &&
        _cachedSessionValid != null &&
        _cachedSessionTime != null &&
        DateTime.now().difference(_cachedSessionTime!) < _sessionCacheTTL) {
      return _cachedSessionValid!;
    }

    try {
      final valid = await SecurityService.instance
          .isSessionValid()
          .timeout(const Duration(seconds: 5));

      if (!valid) {
        _logSecurityEvent(
          type: 'profile_session_invalid',
          severity: 'high',
          details: 'Session expired on Profile screen',
        );
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }

      final sessionEmpId =
      await SecurityService.instance.getCurrentEmployeeId();
      final docId = widget.initialEmployee?.id ?? _employee?.id;
      final empId =
          widget.initialEmployee?.employeeId ?? _employee?.employeeId;

      final matches = sessionEmpId == null ||
          sessionEmpId.isEmpty ||
          (docId != null && docId.isNotEmpty && sessionEmpId == docId) ||
          (empId != null && empId.isNotEmpty && sessionEmpId == empId);

      if (!matches) {
        debugPrint('🚨 [Profile] Cross-employee attempt: '
            'session=$sessionEmpId docId=$docId empId=$empId');
        _logSecurityEvent(
          type: 'profile_cross_access',
          severity: 'critical',
          details: 'Session ($sessionEmpId) != viewing',
        );
        _cachedSessionValid = false;
        _cachedSessionTime = DateTime.now();
        return false;
      }

      _cachedSessionValid = true;
      _cachedSessionTime = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('🚨 [Profile] Session validation error: $e');
      _cachedSessionValid = false;
      _cachedSessionTime = DateTime.now();
      return false;
    }
  }

  void _startSecurityMonitoring() {
    // 🎭 DEMO MODE — skip
    if (_isDemo) return;

    final empDocId = widget.initialEmployee?.id ?? _employee?.id;
    if (empDocId != null && empDocId.isNotEmpty) {
      _sessionSub?.cancel();
      _sessionSub = FirebaseFirestore.instance
          .collection('sessions')
          .doc(empDocId)
          .snapshots()
          .listen(
            (snap) {
          if (!mounted || _loggedOut) return;
          final data = snap.data();
          if (data == null) return;

          if (data['revoked'] == true) {
            _forceLogout('Session revoked by admin');
            return;
          }
          final expiresAt = data['expiresAt'] as Timestamp?;
          if (expiresAt != null &&
              expiresAt.toDate().isBefore(DateTime.now())) {
            _forceLogout('Session expired');
          }
        },
        onError: (e) => debugPrint('Session listener error: $e'),
      );
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted || _loggedOut) return;
      try {
        await SecurityService.instance.markSessionActive();
        final valid = await _validateSession(forceRefresh: true);
        if (!valid && mounted && !_loggedOut) {
          await _forceLogout('Session invalidated');
        }
      } catch (e) {
        debugPrint('⚠️ [Profile] Heartbeat failed: $e');
      }
    });

    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted || _loggedOut) return;
      if (_lastUserActivityAt == null) return;
      final idle = DateTime.now().difference(_lastUserActivityAt!);
      if (idle > _inactivityLimit) {
        await _forceLogout('Inactivity (${idle.inMinutes}m)');
      }
    });

    _validateSession(forceRefresh: true).then((valid) {
      if (mounted) {
        setState(() => _sessionValidated = valid);
        if (!valid && !_loggedOut) {
          _forceLogout('Initial session invalid');
        }
      }
    });
  }

  Future<void> _forceLogout(String reason) async {
    // 🎭 DEMO MODE — ignore
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Profile force logout ignored: $reason');
      return;
    }

    if (_loggedOut || !mounted) return;
    _loggedOut = true;

    debugPrint('🚨 [Profile] Force logout: $reason');

    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    _sessionSub?.cancel();
    _employeeSub?.cancel();
    _connectivitySub?.cancel();

    // 🆕 ONESIGNAL LOGOUT
    try {
      OneSignal.logout();
      debugPrint('🔔 [OneSignal] Unlinked device (Force Logout)');
    } catch (e) {
      debugPrint('⚠️ [OneSignal] Logout failed: $e');
    }

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}
    try {
      await SecurityService.instance.clearSession();
    } catch (_) {}
    try {
      await AuthService.instance.signOut(employee: _employee);
    } catch (_) {}

    _logSecurityEvent(
      type: 'profile_forced_logout',
      severity: 'high',
      details: 'Force logout: $reason',
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
        settings: const RouteSettings(name: '/login'),
      ),
          (route) => false,
    );
  }

  void _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) {
    // 🎭 DEMO MODE — skip Firestore write
    if (_isDemo) {
      debugPrint('🎭 [DemoMode] Profile security event (skipped): $type');
      return;
    }

    FirebaseFirestore.instance.collection('security_events').add({
      'type': type,
      'severity': severity,
      'details': details,
      'employeeId': _employee?.id ?? widget.initialEmployee?.id,
      'employeeName': _employee?.fullName ?? 'Unknown',
      'stage': 'profile',
      'platform': kIsWeb ? 'web' : 'mobile',
      'timestamp': FieldValue.serverTimestamp(),
    }).catchError((e) {
      debugPrint('⚠️ [Profile] security log error: $e');
    });
  }

  void _recordActivity() {
    _lastUserActivityAt = DateTime.now();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordActivity();
      // 🎭 DEMO MODE — skip
      if (_isDemo) return;

      _validateSession(forceRefresh: true).then((valid) {
        if (!valid && mounted && !_loggedOut) {
          _forceLogout('Session invalid on resume');
        }
      });
    }
  }

  Future<void> _loadPasswordCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_kPasswordReqPrefsKey);
      if (ms != null) {
        _lastPasswordRequest = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}
  }

  Future<void> _savePasswordCooldown(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kPasswordReqPrefsKey, time.millisecondsSinceEpoch);
    } catch (_) {}
  }

  void _loadThemeMode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final notifier = context.read<ThemeNotifier>();
        final mode = notifier.themeMode;
        setState(() => _themeMode = mode);
      } catch (e) {
        debugPrint('⚠️ [Profile] _loadThemeMode failed: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _employeeSub?.cancel();
    _sessionSub?.cancel();
    _connectivitySub?.cancel();
    _overlayDelayTimer?.cancel();
    _heartbeatTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<bool> _hasNetwork() async {
    if (_isDemo) return true;
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted || _loggedOut) return;
    _recordActivity();

    _overlayDelayTimer?.cancel();
    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
      _loading = true;
    });

    final hasNet = await _hasNetwork();
    if (!mounted) return;

    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _loading = false;
      });
      return;
    }

    setState(() => _networkState = _NetworkState.online);

    await Future.delayed(const Duration(milliseconds: 400));

    await _load();
  }

  Future<void> _load() async {
    if (_loggedOut) return;
    _recordActivity();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — use demoEmployee, skip DB
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      if (!mounted) return;
      setState(() {
        _employee = widget.initialEmployee ?? DemoModeService.demoEmployee;
        _loading = false;
      });
      debugPrint('🎭 [DemoMode] Profile loaded with demoEmployee');
      return;
    }

    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      if (mounted && !_loggedOut) {
        _forceLogout('Session invalid on load');
      }
      return;
    }

    final startTime = DateTime.now();

    try {
      final empId = await SecurityService.instance.getCurrentEmployeeId();
      Employee? employee;

      if (empId != null) {
        employee = await DatabaseService.instance.getEmployeeById(empId);
      }
      employee ??= widget.initialEmployee;

      final elapsed = DateTime.now().difference(startTime);
      if (elapsed.inMilliseconds < 800) {
        await Future.delayed(
            Duration(milliseconds: 800 - elapsed.inMilliseconds));
      }

      if (!mounted || _loggedOut) return;

      setState(() {
        _employee = employee;
        _loading = false;
      });

      debugPrint('👤 [Profile] Initial load: ${employee?.fullName} '
          '(id=${employee?.id})');

      _startEmployeeListener();
      _startSecurityMonitoring();
    } catch (e) {
      debugPrint('❌ [Profile] _load error: $e');
      if (mounted && !_loggedOut) setState(() => _loading = false);
    }
  }

  void _startEmployeeListener() {
    // 🎭 DEMO MODE — skip Firestore listener
    if (_isDemo) return;

    final docId = _employee?.id;
    if (docId == null || docId.isEmpty) {
      debugPrint('⚠️ [Profile] No employee doc ID — skip listener');
      return;
    }

    debugPrint('🎧 [Profile] Starting live listener for doc: $docId');

    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted || _loggedOut) return;
        final data = snap.data();
        if (data == null) {
          debugPrint('⚠️ [Profile] Doc deleted or empty');
          return;
        }

        final status = (data['status'] ?? '').toString().toLowerCase();
        const blocked = {'suspended', 'terminated', 'deleted', 'blocked'};
        if (blocked.contains(status)) {
          _forceLogout('Account status: $status');
          return;
        }

        Employee? updated;
        try {
          updated = Employee.fromFirestore(data, snap.id);
        } catch (e) {
          debugPrint('❌ [Profile] Parse error: $e');
          return;
        }

        final oldPhoto = _employee?.photoUrl ?? _employee?.photoPath;
        final newPhoto = updated.photoUrl ?? updated.photoPath;
        final photoChanged = oldPhoto != newPhoto;

        final oldName = _employee?.fullName;
        final newName = updated.fullName;
        final nameChanged = oldName != newName;

        setState(() => _employee = updated);

        debugPrint('🔄 [Profile] Live update: name="${updated.fullName}"'
            '${photoChanged ? " • 📸 PHOTO CHANGED!" : ""}'
            '${nameChanged ? " • NAME CHANGED!" : ""}');

        DatabaseService.instance.insertEmployee(updated).catchError((e) {
          debugPrint('⚠️ [Profile] Local save error: $e');
        });
      },
      onError: (e) {
        debugPrint('❌ [Profile] Listener error: $e');
      },
    );
  }

  Future<void> _loadPushPreference() async {
    final enabled =
    await NotificationPreferenceService.instance.isPushEnabled();
    if (mounted) {
      setState(() {
        _pushEnabled = enabled;
        _pushLoading = false;
      });
      debugPrint('🔔 [Profile] Push pref loaded: $enabled');
    }
  }

  Future<void> _onPushToggle(bool value) async {
    _recordActivity();
    setState(() => _pushEnabled = value);

    await NotificationPreferenceService.instance.setPushEnabled(value);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              value
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ? lang.t('notif_on_msg') : lang.t('notif_off_msg'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor:
        value ? const Color(0xFF16A34A) : const Color(0xFF52525B),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onThemeModeChanged(ThemeMode mode) async {
    _recordActivity();
    if (mode == _themeMode) return;
    setState(() => _themeMode = mode);

    try {
      await context.read<ThemeNotifier>().setThemeMode(mode);
    } catch (e) {
      debugPrint('❌ [Profile] setThemeMode failed: $e');
    }

    if (!mounted) return;

    final label = _themeModeLabel(mode);
    final msg = '🎨 Theme: $label';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: _Mock.orange,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
      case ThemeMode.system:
        return 'System Settings';
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ NEW: Navigate to Reports Screen
  // ═══════════════════════════════════════════════════════════════
  Future<void> _openReports() async {
    _recordActivity();

    if (_loggedOut) return;

    // 🔒 Session check before entering (bypassed in demo)
    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      _showSnack('🚨 Session expired. Please log in again.', isError: true);
      _forceLogout('Session invalid on Reports open');
      return;
    }

    if (_networkState != _NetworkState.online) {
      _showSnack(
        '⚠️ No internet. Please check your connection.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportsScreen(initialEmployee: _employee),
      ),
    );
  }

  Future<void> _requestPasswordChange() async {
    _recordActivity();

    // 🎭 DEMO MODE — show toast only, no Firestore write
    if (_isDemo) {
      _showSnack('🎭 Demo Mode — password change is not available.');
      return;
    }

    final valid = await _validateSession(forceRefresh: true);
    if (!valid) {
      _showSnack('🚨 Session expired. Please log in again.', isError: true);
      _forceLogout('Session invalid on password request');
      return;
    }

    if (_networkState != _NetworkState.online) {
      _showSnack(
        '⚠️ No internet. Please check your connection.',
        isError: true,
      );
      return;
    }

    final now = DateTime.now();
    if (_lastPasswordRequest != null &&
        now.difference(_lastPasswordRequest!) < _passwordCooldown) {
      final remain = _passwordCooldown - now.difference(_lastPasswordRequest!);
      _showSnack(
        '⏳ You already sent a request recently. Try again in ${remain.inMinutes}m.',
        isError: true,
      );
      return;
    }

    final employee = _employee;
    if (employee == null) {
      _showSnack('⚠️ Unable to fetch employee info.', isError: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final dtc = _ThemeColors(isDark);
        return AlertDialog(
          backgroundColor: dtc.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: dtc.cardBorder, width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_reset_rounded,
                  color: _Mock.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Change Password',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: dtc.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'This will notify the admin about your password reset request. '
                'You will set your own new password once it has been approved.'
                '\n\nEmployee: ${employee.fullName}'
                '\nEmail: ${employee.email}',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: dtc.textMuted,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: dtc.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _Mock.orange),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Send Request',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    setState(() => _sendingPasswordRequest = true);

    try {
      await AdminNotificationService.instance.notifyPasswordChangeRequest(
        employeeId: employee.id,
        employeeName: employee.fullName,
        email: employee.email,
        reason: 'Employee-initiated password reset',
      );

      _lastPasswordRequest = DateTime.now();
      await _savePasswordCooldown(_lastPasswordRequest!);

      _logSecurityEvent(
        type: 'profile_password_request',
        severity: 'info',
        details: 'Password change requested',
      );

      if (!mounted) return;
      _showSnack('✅ Your request has been sent to the admin.');
    } catch (e) {
      debugPrint('❌ [PasswordChange] $e');
      if (!mounted) return;
      _showSnack(
        '⚠️ Failed to send the request. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _sendingPasswordRequest = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor:
        isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showLanguageDialog() async {
    _recordActivity();
    final current = lang.language;

    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final dialogTc = _ThemeColors(isDark);

        return AlertDialog(
          backgroundColor: dialogTc.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: dialogTc.cardBorder, width: 1),
          ),
          title: Row(
            children: [
              const Icon(Icons.translate_rounded,
                  color: _Mock.orange, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lang.t('select_language'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: dialogTc.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _languageOption(
                tc: dialogTc,
                value: AppLanguage.english,
                label: '🇬🇧  English',
                subtitle: 'Use English language',
                selected: current == AppLanguage.english,
                onTap: () => Navigator.pop(ctx, AppLanguage.english),
              ),
              const SizedBox(height: 8),
              _languageOption(
                tc: dialogTc,
                value: AppLanguage.tagalog,
                label: '🇵🇭  Tagalog',
                subtitle: 'Use the Tagalog language',
                selected: current == AppLanguage.tagalog,
                onTap: () => Navigator.pop(ctx, AppLanguage.tagalog),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: dialogTc.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (picked == null || picked == current) return;

    await lang.setLanguage(picked);

    if (!mounted) return;

    final msg = picked == AppLanguage.tagalog
        ? 'Language set to Tagalog'
        : 'App language set to English';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _languageOption({
    required _ThemeColors tc,
    required AppLanguage value,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _Mock.orange.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? _Mock.orange.withValues(alpha: 0.5)
                : tc.cardBorder.withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? _Mock.orange : tc.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: tc.textMuted),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: _Mock.orange, size: 22)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: tc.textMuted, size: 22),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    _recordActivity();

    _logSecurityEvent(
      type: 'profile_logout',
      severity: 'info',
      details: 'User-initiated logout',
    );

    // 🎭 DEMO MODE — also clear demo session flag
    if (_isDemo) {
      try {
        await DemoModeService.instance.endDemoSession();
      } catch (_) {}
    }

    // 🆕 ONESIGNAL LOGOUT
    try {
      OneSignal.logout();
      debugPrint('🔔 [OneSignal] Unlinked device (Manual Logout)');
    } catch (e) {
      debugPrint('⚠️ [OneSignal] Logout failed: $e');
    }

    try {
      await AuthService.instance.signOut(employee: _employee);
    } catch (e) {
      debugPrint('⚠️ [Profile] AuthService signOut failed: $e');
    }
    try {
      await SecurityHardeningService.instance.clearSession();
    } catch (_) {}
    try {
      await SecurityService.instance.clearSession();
    } catch (_) {}

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPasswordReqPrefsKey);
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LandingScreen()),
          (_) => false,
    );
  }

  void _comingSoon(String feature) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature ${lang.t('feature_coming_soon')}')),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final langService = context.watch<LanguageService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

    if (_loading || _isInitialLoading || isOffline || isChecking) {
      return Scaffold(
        backgroundColor: tc.bg,
        body: SafeArea(
          child: Stack(
            children: [
              const ProfileSkeleton(),
              if (isOffline)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showOfflineOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_showOfflineOverlay,
                      child: _buildNetworkErrorOverlay(tc),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildHandWatermark(opacity: tc.watermarkOpacity),

            Column(
              children: [
                _buildHeader(langService, tc),

                Expanded(
                  child: SingleChildScrollView(
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    child: Transform.translate(
                      offset: const Offset(0, -88),
                      child: Column(
                        children: [
                          _buildProfileCard(tc),
                          const SizedBox(height: 4),

                          // ✅ DEMO badge
                          if (_isDemo) ...[
                            const SizedBox(height: 8),
                            _buildDemoBadge(),
                          ],

                          // ✅ NEW: REPORTS SECTION
                          _sectionLabel(tc, 'REPORTS'),
                          const SizedBox(height: 10),
                          _sectionCard(tc, [
                            _chevronRow(
                              tc: tc,
                              icon: Icons.receipt_long_rounded,
                              label: 'Payslip & Reports',
                              subtitle: 'View and download your payslip',
                              onTap: _openReports,
                              isLast: true,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          _sectionLabel(tc, langService.t('personal_details')),
                          const SizedBox(height: 10),
                          _sectionCard(tc, [
                            _detailRow(
                              tc: tc,
                              icon: Icons.email_rounded,
                              label: langService.t('email_address'),
                              value: _employee?.email ?? '—',
                            ),
                            _detailRow(
                              tc: tc,
                              icon: Icons.phone_android_rounded,
                              label: langService.t('phone_number'),
                              value: _employee?.phone ?? '—',
                            ),
                            _detailRow(
                              tc: tc,
                              icon: Icons.location_on_rounded,
                              label: langService.t('department'),
                              value: _employee?.department ?? '—',
                            ),
                            _detailRow(
                              tc: tc,
                              icon: Icons.work_outline_rounded,
                              label: langService.t('position'),
                              value: _employee?.position ?? '—',
                              isLast: true,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          _sectionLabel(tc, langService.t('app_settings')),
                          const SizedBox(height: 10),
                          _sectionCard(tc, [
                            _themeModeRow(tc: tc),
                            _toggleRow(
                              tc: tc,
                              icon: _pushEnabled
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_off_rounded,
                              label: langService.t('push_notifications'),
                              subtitle: _pushLoading
                                  ? langService.t('push_loading')
                                  : (_pushEnabled
                                  ? langService.t('push_on')
                                  : langService.t('push_off')),
                              value: _pushEnabled,
                              onChanged:
                              _pushLoading ? (_) {} : _onPushToggle,
                            ),
                            _chevronRow(
                              tc: tc,
                              icon: Icons.translate_rounded,
                              label: langService.t('language'),
                              subtitle: langService.isTagalog
                                  ? 'Tagalog 🇵🇭'
                                  : 'English 🇬🇧',
                              onTap: _showLanguageDialog,
                              isLast: true,
                            ),
                          ]),
                          const SizedBox(height: 24),

                          _sectionLabel(tc, langService.t('security')),
                          const SizedBox(height: 10),
                          _sectionCard(tc, [
                            _chevronRow(
                              tc: tc,
                              icon: Icons.lock_reset_rounded,
                              label: langService.t('change_password'),
                              subtitle: _sendingPasswordRequest
                                  ? 'Sending…'
                                  : 'Request from admin',
                              onTap: _sendingPasswordRequest
                                  ? null
                                  : _requestPasswordChange,
                            ),
                            _chevronRow(
                              tc: tc,
                              icon: Icons.privacy_tip_rounded,
                              label: langService.t('privacy_policy'),
                              subtitle: 'Read our data privacy policy',
                              onTap: () {
                                _recordActivity();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                    const PrivacyPolicyScreen(),
                                  ),
                                );
                              },
                              isLast: true,
                            ),
                          ]),

                          const SizedBox(height: 32),
                          _buildSignOut(tc, langService),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 🎭 DEMO BADGE
  Widget _buildDemoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF54900).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFF54900).withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.science_rounded,
              color: Color(0xFFF54900), size: 14),
          SizedBox(width: 6),
          Text(
            'DEMO MODE — Session Only',
            style: TextStyle(
              color: Color(0xFFF54900),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkErrorOverlay(_ThemeColors tc) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFF8A00),
                  Color(0xFFFA6A00),
                  Color(0xFFF54900),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _networkErrorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 180,
                  child: ElevatedButton.icon(
                    onPressed: _retryNetworkCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _Mock.orange,
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
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(LanguageService langService, _ThemeColors tc) {
    return Container(
      width: double.infinity,
      height: 206,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 1),
      decoration: const BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Text(
          langService.t('profile_title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  static const double _kAvatarSize = 80;

  Widget _buildProfileCard(_ThemeColors tc) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: EdgeInsets.only(top: _kAvatarSize / 2),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, _kAvatarSize / 2 + 12, 16, 20),
          decoration: BoxDecoration(
            color: tc.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tc.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                _employee?.fullName ?? lang.t('unknown'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: tc.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _employee?.position ?? 'Position',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _Mock.orange,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: tc.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tc.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.badge_outlined,
                        size: 14, color: _Mock.orange),
                    const SizedBox(width: 6),
                    Text(
                      _employee?.employeeId ?? _employee?.id ?? '—',
                      style: const TextStyle(
                          fontSize: 12, color: _Mock.orange),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _kAvatarSize,
              height: _kAvatarSize,
              decoration: BoxDecoration(
                gradient: AppColors.gradientOrange,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _Mock.orange, width: 3.3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildAvatarContent(),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _Mock.lime,
                  shape: BoxShape.circle,
                  border:
                  Border.all(color: const Color(0xFF18181B), width: 1),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarContent() {
    final url = _employee?.photoUrl ?? _employee?.photoPath;

    if (url == null || url.isEmpty || url == '—') {
      return _avatarInitials();
    }

    if (url.startsWith('data:image')) {
      if (url.length > 5 * 1024 * 1024) {
        debugPrint('🚨 [Profile] Data URI too large — skip');
        return _avatarInitials();
      }
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          width: _kAvatarSize,
          height: _kAvatarSize,
          errorBuilder: (_, __, ___) => _avatarInitials(),
        );
      } catch (e) {
        debugPrint('❌ [Profile] Base64 error: $e');
        return _avatarInitials();
      }
    }

    if (url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: _kAvatarSize,
        height: _kAvatarSize,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: _Mock.orange,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _avatarInitials(),
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final file = File(url);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: _kAvatarSize,
            height: _kAvatarSize,
            errorBuilder: (_, __, ___) => _avatarInitials(),
          );
        }
      } catch (_) {}
    }

    return _avatarInitials();
  }

  Widget _avatarInitials() {
    return Center(
      child: Text(
        _employee?.initials ?? '??',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _sectionLabel(_ThemeColors tc, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: tc.sectionLabel,
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(_ThemeColors tc, List<Widget> rows,
      {Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? tc.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  BoxDecoration _rowDivider(_ThemeColors tc, bool isLast) => BoxDecoration(
    border: isLast
        ? null
        : Border(
      bottom: BorderSide(color: tc.rowDivider),
    ),
  );

  Widget _detailRow({
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(tc, isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: tc.textMuted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _Mock.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(tc, isLast),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _Mock.orange)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: tc.textMuted)),
              ],
            ),
          ),
          _ToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _themeModeRow({
    required _ThemeColors tc,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _rowDivider(tc, isLast),
      child: Row(
        children: [
          _iconBox(_themeModeIcon(_themeMode)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Theme',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _Mock.orange,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _themeModeLabel(_themeMode),
                  style: TextStyle(fontSize: 12, color: tc.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            decoration: BoxDecoration(
              color: tc.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tc.cardBorder, width: 1.2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ThemeMode>(
                value: _themeMode,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: tc.cardBg,
                icon: const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: _Mock.orange,
                  size: 22,
                ),
                style: const TextStyle(
                  color: _Mock.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (mode) {
                  if (mode != null) _onThemeModeChanged(mode);
                },
                items: const [
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Row(
                      children: [
                        Icon(Icons.light_mode_rounded,
                            size: 16, color: _Mock.orange),
                        SizedBox(width: 8),
                        Text('Light Mode'),
                      ],
                    ),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Row(
                      children: [
                        Icon(Icons.dark_mode_rounded,
                            size: 16, color: _Mock.orange),
                        SizedBox(width: 8),
                        Text('Dark Mode'),
                      ],
                    ),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Row(
                      children: [
                        Icon(Icons.brightness_auto_rounded,
                            size: 16, color: _Mock.orange),
                        SizedBox(width: 8),
                        Text('System Settings'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chevronRow({
    required _ThemeColors tc,
    required IconData icon,
    required String label,
    String? subtitle,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _rowDivider(tc, isLast),
        child: Row(
          children: [
            _iconBox(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _Mock.orange)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                        TextStyle(fontSize: 12, color: tc.textMuted)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: tc.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSignOut(_ThemeColors tc, LanguageService langService) {
    return InkWell(
      onTap: _logout,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tc.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Mock.red),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, color: _Mock.red, size: 18),
            const SizedBox(width: 8),
            Text(
              langService.t('sign_out'),
              style: const TextStyle(
                color: _Mock.red,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 48,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: value ? AppColors.gradientOrange : null,
          color: value ? null : _Mock.switchTrackOff,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}