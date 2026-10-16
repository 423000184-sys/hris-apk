// lib/screens/landing_screen.dart
// v2.2: 🔒 Demo mode now REQUIRES internet connection
//       ⚠️ Offline users cannot enter demo mode — snackbar shown
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee.dart';
import '../services/demo_mode_service.dart';
import '../services/security_hardening_service.dart';
import '../services/security_service.dart';
import '../widgets/bootstrap_grid.dart';
import 'admin_login_screen.dart';
import 'login_screen.dart';
import 'main_screen.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint('[LandingScreen] $message');
}

// ═══════════════════════════════════════════════════════════════════════════
// COLORS
// ═══════════════════════════════════════════════════════════════════════════
class _T {
  static const Color headerStart = Color(0xFFF54900);
  static const Color headerMid = Color(0xFFFF6B00);
  static const Color headerEnd = Color(0xFFFF8A00);

  static const Color circleGradTop = Color.fromRGBO(255, 138, 0, 0.62);
  static const Color circleGradMid = Color.fromRGBO(250, 106, 0, 0.62);
  static const Color circleGradBottom = Color.fromRGBO(245, 73, 0, 0.62);
  static const Color circleBorder = Color(0xFFFF8C00);

  static const Color buildingBg = Color(0xFFF59E0B);
  static const Color labelLime = Color(0xFFC2FF00);
  static const Color lime400 = Color(0xFFA3E635);
  static const Color green400 = Color(0xFF4ADE80);

  static const Color badgeBg = Color(0xFFFF8904);
  static const Color heroDescGradStart = Color(0xFFEA580C);
  static const Color heroDescGradEnd = Color(0xFFF59E0B);
  static const Color workZoneIcon = Color(0xFFEA580C);

  static const Color ctaSolid = Color(0xFFFF6900);

  static const Color dashCardBg = Color(0xFF111115);
  static const Color statusStart = Color(0xFF1C1C21);
  static const Color statusEnd = Color(0xFF0D0D12);
  static const Color toggleBg = Color(0xFF1A1A21);
  static const Color toggleActive = Color(0xFF2A2A35);
  static const Color locCardBg = Color(0xFF1A1A21);
  static const Color iconCircleBg = Color(0xFF0D0D12);
  static const Color mutedGrey = Color(0xFFA1A1AA);
  static const Color inactiveTab = Color(0xFF71717A);
  static const Color white = Color(0xFFFFFFFF);

  static const Color desktopBg = Color(0xFF0C0C0E);
  static const Color desktopNavText = Color(0xFFD4D4D8);
  static const Color desktopMuted = Color(0xFF9F9FA9);
  static const Color desktopBadge = Color(0xFFFF8904);
  static const Color desktopDivider = Color(0x14FFFFFF);

  static const Color shieldBg = Color(0xFF0C0C0E);
  static const Color danger = Color(0xFFDC2626);

  // 🎭 DEMO — orange gradient (matches app theme)
  static const Color demoGradStart = Color(0xFFFF8A00);
  static const Color demoGradEnd = Color(0xFFF54900);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get heroBgStart =>
      isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFFFFF);
  Color get heroBgEnd =>
      isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

  Color get heroTitle => isDark ? Colors.white : const Color(0xFF000000);
  Color get heroDesc =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF3F3F46);

  Color get scaffoldBg =>
      isDark ? const Color(0xFF1A0F05) : const Color(0xFFFFF2EA);

  double get watermarkOpacity => isDark ? 0.15 : 0.80;
}

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const String _logoAsset = 'assets/images/logo.png';
  static const double _desktopBreakpoint = 992.0;

  // 🔒 Navigation state
  bool _isNavigating = false;
  DateTime? _lastNavAttempt;
  static const Duration _navCooldown = Duration(milliseconds: 1200);

  bool _obscureContent = false;

  // ═══════════════════════════════════════════════════════════════════════
  // 🔒 SESSION CHECK — auto-redirect kung naka-login na
  // ═══════════════════════════════════════════════════════════════════════
  bool _checkingSession = true;
  bool _autoRedirecting = false;

  // ═══════════════════════════════════════════════════════════════════════
  // 🔒 HIDDEN ADMIN — hardened
  // ═══════════════════════════════════════════════════════════════════════
  Timer? _adminHoldTimer;
  bool _adminHoldActive = false;
  bool _adminNavigating = false;

  static const String _kAdminAttemptsKey = 'landing_admin_attempts';
  static const String _kAdminLockoutUntil = 'landing_admin_lockout_until';

  static const Duration _adminHoldDuration = Duration(seconds: 5);
  static const Duration _adminCooldown = Duration(seconds: 5);
  static const int _maxAdminAttemptsBeforeLockout = 3;
  static const Duration _adminLockoutDuration = Duration(minutes: 10);

  DateTime? _lastAdminAttempt;

  // ✅ 5-tap secret on the logo
  int _logoTapCount = 0;
  DateTime? _firstLogoTapTime;
  static const int _logoTapRequired = 5;
  static const Duration _logoTapResetWindow = Duration(seconds: 3);

  // 🔒 Device binding
  String? _deviceBinding;
  bool _deviceCompromised = false;

  // 🔌 Offline banner state
  StreamSubscription<bool>? _connectivitySub;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
    );

    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: _T.headerStart,
        statusBarIconBrightness: Brightness.light,
      ));
    }

    _initConnectivityListener();
    _bootstrapSecurityAndCheckSession();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔌 CONNECTIVITY LISTENER — real-time online/offline state
  // ═══════════════════════════════════════════════════════════════════════
  void _initConnectivityListener() {
    try {
      _isOnline = ConnectivityService.instance.isOnline;
    } catch (_) {
      _isOnline = true;
    }

    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            setState(() => _isOnline = online);
            _secureLog('🔌 Connectivity changed: online=$online');
          });
    } catch (e) {
      _secureLog('⚠️ connectivity listen error: $e');
    }
  }

  bool _isOnlineSafely() {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (e) {
      _secureLog('Connectivity check failed: $e');
      return true;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔒 BOOTSTRAP
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _bootstrapSecurityAndCheckSession() async {
    // ✅ STEP 0: CHECK kung galing sa snap logout o forced logout
    try {
      final prefs = await SharedPreferences.getInstance();
      final forceShow = prefs.getBool('force_show_landing') ?? false;
      if (forceShow) {
        await prefs.remove('force_show_landing');
        await prefs.remove('force_show_landing_at');
        _secureLog('🚪 force_show_landing flag SET — '
            'skipping session restore (snap/forced logout)');
        if (mounted) setState(() => _checkingSession = false);
        return;
      }
    } catch (e) {
      _secureLog('⚠️ flag check failed: $e');
    }

    // ✅ STEP 0b: Check din ang route arguments
    try {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map && args['skipSessionRestore'] == true) {
        _secureLog('🚪 skipSessionRestore argument — '
            'skipping session restore');
        if (mounted) setState(() => _checkingSession = false);
        return;
      }
    } catch (_) {}

    // 1. FLAG_SECURE
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (e) {
      _secureLog('FLAG_SECURE failed: $e');
    }

    // 2. Device integrity
    try {
      final ok =
      await SecurityHardeningService.instance.checkDeviceIntegrity();
      _deviceCompromised = !ok;
      if (!ok) {
        _secureLog('🚨 Device compromised: '
            '${SecurityHardeningService.instance.integrityIssues.join(",")}');
      }
    } catch (e) {
      _secureLog('Integrity check failed: $e');
    }

    // 3. Device binding
    try {
      _deviceBinding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}

    // 4. Session check
    await _checkExistingSession();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔒 SESSION CHECK + AUTO-REDIRECT
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _checkExistingSession() async {
    if (_autoRedirecting) return;

    try {
      _secureLog('🔍 Checking existing session...');

      // 1. SecurityHardeningService (secure storage + TTL)
      String? empId;
      try {
        empId = await SecurityHardeningService.instance
            .getCurrentEmployeeId()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        _secureLog('Session token check failed: $e');
      }

      // 2. Legacy SecurityService fallback
      if (empId == null || empId.isEmpty) {
        try {
          empId = await SecurityService.instance
              .getCurrentEmployeeId()
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }

      // 3. Firebase Auth fallback
      if ((empId == null || empId.isEmpty) &&
          FirebaseAuth.instance.currentUser != null) {
        try {
          final authUser = FirebaseAuth.instance.currentUser!;
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('authUid', isEqualTo: authUser.uid)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 5));
          if (snap.docs.isNotEmpty) {
            empId = snap.docs.first.id;
          }
        } catch (_) {}
      }

      if (empId == null || empId.isEmpty) {
        _secureLog('❌ No existing session');
        if (mounted) setState(() => _checkingSession = false);
        return;
      }

      // 4. Load employee + status (single query)
      _secureLog('✅ Session found: $empId — loading employee');
      Employee? employee;
      String status = '';
      bool? isActive;

      try {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get()
            .timeout(const Duration(seconds: 8));

        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            status = (data['status'] ?? '').toString().toLowerCase().trim();
            isActive = data['isActive'];
            employee = _docToEmployee(doc);
          }
        }
      } catch (e) {
        _secureLog('Employee load failed: $e');
      }

      if (employee == null) {
        _secureLog('❌ Employee doc not found — clearing session');
        try {
          await SecurityHardeningService.instance.clearSession();
        } catch (_) {}
        if (mounted) setState(() => _checkingSession = false);
        return;
      }

      // 5. Verify account status
      const blocked = {
        'suspended',
        'terminated',
        'deleted',
        'blocked',
        'archived',
      };

      if (blocked.contains(status) || isActive == false) {
        _secureLog('🚫 Account blocked: $status — clearing session');
        await _logSecurityEvent(
          type: 'landing_blocked_account',
          severity: 'high',
          details: 'Blocked account attempted auto-login: $status',
        );
        try {
          await SecurityHardeningService.instance.clearSession();
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        if (mounted) setState(() => _checkingSession = false);
        return;
      }

      // 6. Auto-redirect
      if (!mounted) return;
      _autoRedirecting = true;
      _secureLog('➡️ Auto-redirecting to dashboard');

      try {
        await Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => MainScreen(employee: employee!),
            settings: const RouteSettings(name: '/dashboard'),
          ),
        );
      } catch (e) {
        _secureLog('Auto-redirect failed: $e');
        _autoRedirecting = false;
        if (mounted) setState(() => _checkingSession = false);
      }
    } catch (e) {
      _secureLog('Session check error: $e');
      if (mounted) setState(() => _checkingSession = false);
    }
  }

  Employee _docToEmployee(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final firstName = (data['firstName'] ?? '').toString();
    final lastName = (data['lastName'] ?? '').toString();
    final fullName = (data['name'] ?? '$firstName $lastName').toString().trim();
    return Employee.fromMap({
      'id': doc.id,
      'employee_id': data['employeeId'] ?? doc.id,
      'first_name': firstName,
      'last_name': lastName,
      'full_name': fullName,
      'email': data['email'] ?? '',
      'role': data['role'] ?? 'Employee',
      'department': data['role'] ?? data['department'] ?? '',
      'position': data['role'] ?? data['position'] ?? '',
      'phone': data['phone'],
      'photo_path': data['photoPath'],
      'photo_url': data['photoUrl'],
      'face_embedding': data['faceEmbedding'],
      'fingerprint_hash': data['fingerprintHash'],
      'pin_hash': null,
      'pin_salt': null,
      'nfc_tag_id': data['nfcTagId'],
      'is_active': data['status'] == 'active' ? 1 : 0,
      'created_at': (data['createdAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
      'updated_at': (data['updatedAt'] as Timestamp?)
          ?.toDate()
          .toIso8601String() ??
          DateTime.now().toIso8601String(),
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adminHoldTimer?.cancel();
    _connectivitySub?.cancel();
    _fadeCtrl.dispose();
    SecurityHardeningService.instance.disableSecureScreen();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldObscure = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (shouldObscure != _obscureContent && mounted) {
      setState(() => _obscureContent = shouldObscure);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔔 OFFLINE SNACKBAR HELPER
  // ═══════════════════════════════════════════════════════════════════════
  void _showOfflineSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _T.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EMPLOYEE LOGIN NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _goToLogin() async {
    final now = DateTime.now();

    if (_lastNavAttempt != null &&
        now.difference(_lastNavAttempt!) < _navCooldown) {
      _secureLog('Login nav throttled');
      return;
    }

    if (_isNavigating) return;
    _isNavigating = true;
    _lastNavAttempt = now;

    try {
      final online = _isOnlineSafely();

      if (!mounted) return;

      if (!online) {
        _showOfflineSnack(
            'Need a internet connection to login');
        return;
      }

      await Navigator.of(context, rootNavigator: false).push(
        MaterialPageRoute<void>(
          builder: (_) => const LoginScreen(),
          settings: const RouteSettings(name: '/login'),
        ),
      );
    } catch (e) {
      _secureLog('Navigation error: $e');
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🎭 DEMO MODE — REQUIRES INTERNET
  //    • Kung offline → snackbar, hindi tuloy
  //    • Kung online → enable demo + navigate to LOGIN SCREEN (Step 1)
  // ═══════════════════════════════════════════════════════════════════════
  Future<void> _openDemoMode() async {
    if (_isNavigating) return;
    final now = DateTime.now();
    if (_lastNavAttempt != null &&
        now.difference(_lastNavAttempt!) < _navCooldown) {
      _secureLog('🎭 Demo nav throttled');
      return;
    }

    // 🔌 CHECK INTERNET FIRST — bago mag-navigate
    final online = _isOnlineSafely();
    _secureLog('🎭 Demo tap — online=$online');

    if (!online) {
      _showOfflineSnack(
          'Kailangan ng internet para magamit ang Demo Mode.');
      _secureLog('🎭 Demo BLOCKED — no internet connection');
      return;
    }

    _isNavigating = true;
    _lastNavAttempt = now;

    try {
      if (!kIsWeb) {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
      }

      // ✅ Enable demo + prepare pre-auth keys
      await DemoModeService.instance.startDemoSession();

      _secureLog('🎭 Demo mode activated — routing to LOGIN SCREEN');

      try {
        await _logSecurityEvent(
          type: 'demo_mode_activated',
          severity: 'info',
          details: 'User entered DEMO MODE from landing screen',
        );
      } catch (_) {}

      if (!mounted) return;

      // 🎯 Navigate to LoginScreen (Step 1)
      //    Login screen will detect DemoModeService.isEnabled
      //    and intercept the PIN/Key Fob taps → auto-login.
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: const RouteSettings(name: '/login-demo'),
        ),
      );
    } catch (e) {
      _secureLog('Demo nav error: $e');
    } finally {
      if (mounted) _isNavigating = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔒 HIDDEN ADMIN
  // ═══════════════════════════════════════════════════════════════════════
  void _handleAdminHoldStart() {
    if (_adminHoldActive) return;

    _checkAdminLockout().then((lockout) {
      if (lockout != null) {
        _secureLog('Admin access locked out for ${lockout.inSeconds}s');
        return;
      }

      _adminHoldActive = true;
      _adminHoldTimer?.cancel();
      _adminHoldTimer = Timer(_adminHoldDuration, () {
        if (!mounted) return;
        _openAdminLogin();
      });
    });
  }

  void _handleAdminHoldEnd() {
    _adminHoldTimer?.cancel();
    _adminHoldActive = false;
  }

  // ✅ 5-tap secret on the logo
  void _handleLogoTap() {
    final now = DateTime.now();

    if (_firstLogoTapTime != null &&
        now.difference(_firstLogoTapTime!) > _logoTapResetWindow) {
      _logoTapCount = 0;
      _firstLogoTapTime = null;
    }

    if (_logoTapCount == 0) {
      _firstLogoTapTime = now;
    }

    _logoTapCount++;
    _secureLog('👆 Logo tap $_logoTapCount/$_logoTapRequired');

    if (_logoTapCount >= _logoTapRequired) {
      _logoTapCount = 0;
      _firstLogoTapTime = null;
      _secureLog('🎯 5-tap secret triggered — opening admin login');
      unawaited(_openAdminLogin());
    }
  }

  Future<Duration?> _checkAdminLockout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lockoutMs = prefs.getInt(_kAdminLockoutUntil) ?? 0;
      if (lockoutMs <= 0) return null;
      final until = DateTime.fromMillisecondsSinceEpoch(lockoutMs);
      if (until.isBefore(DateTime.now())) {
        await prefs.remove(_kAdminLockoutUntil);
        await prefs.remove(_kAdminAttemptsKey);
        return null;
      }
      return until.difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordAdminAttempt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_kAdminAttemptsKey) ?? 0) + 1;
      await prefs.setInt(_kAdminAttemptsKey, count);

      if (count >= _maxAdminAttemptsBeforeLockout) {
        final until = DateTime.now().add(_adminLockoutDuration);
        await prefs.setInt(
            _kAdminLockoutUntil, until.millisecondsSinceEpoch);
        _secureLog('🚨 Admin lockout triggered after $count attempts');

        await _logSecurityEvent(
          type: 'landing_admin_lockout',
          severity: 'high',
          details: 'Locked out after $count admin access attempts',
        );
      }
    } catch (e) {
      _secureLog('Record admin attempt failed: $e');
    }
  }

  Future<void> _openAdminLogin() async {
    if (_adminNavigating) return;

    final now = DateTime.now();
    if (_lastAdminAttempt != null &&
        now.difference(_lastAdminAttempt!) < _adminCooldown) {
      return;
    }

    final lockout = await _checkAdminLockout();
    if (lockout != null) {
      _secureLog('Admin access locked out');
      _handleAdminHoldEnd();
      return;
    }

    _adminNavigating = true;
    _lastAdminAttempt = now;
    _handleAdminHoldEnd();

    try {
      if (!kIsWeb) HapticFeedback.mediumImpact();

      await _recordAdminAttempt();

      unawaited(_logAdminAccessAttempt());

      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminLoginScreen(),
          settings: const RouteSettings(name: '/admin-login'),
        ),
      );
    } catch (e) {
      _secureLog('Admin nav error: $e');
    } finally {
      _adminNavigating = false;
    }
  }

  Future<void> _logAdminAccessAttempt() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

      await FirebaseFirestore.instance
          .collection('security_events')
          .add({
        'type': 'admin_access_attempt',
        'severity': 'medium',
        'details': 'Hidden admin login triggered from landing screen',
        'actorUid': uid,
        'deviceBinding': _deviceBinding,
        'deviceCompromised': _deviceCompromised,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'landing',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      _secureLog('Admin access log failed: $e');
    }
  }

  Future<void> _logSecurityEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    try {
      if (!_isOnlineSafely()) return;
      await FirebaseFirestore.instance
          .collection('security_events')
          .add({
        'type': type,
        'severity': severity,
        'details': details,
        'deviceBinding': _deviceBinding,
        'deviceCompromised': _deviceCompromised,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'landing',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      _secureLog('Security log failed: $e');
    }
  }

  // ✅ Wrap logo with hidden admin (long-press + 5-tap)
  Widget _wrapLogoWithHiddenAdmin({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleLogoTap,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _handleAdminHoldStart(),
        onPointerUp: (_) => _handleAdminHoldEnd(),
        onPointerCancel: (_) => _handleAdminHoldEnd(),
        child: child,
      ),
    );
  }

  double _degToRad(double deg) => deg * 3.141592653589793 / 180;

  bool _useDesktopLayout(BuildContext context) {
    if (!kIsWeb) return false;
    final w = MediaQuery.of(context).size.width;
    return w >= _desktopBreakpoint;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final useDesktop = _useDesktopLayout(context);

    // 🔒 Splash habang nagche-check ng session
    if (_checkingSession) {
      return Scaffold(
        backgroundColor: useDesktop ? _T.desktopBg : tc.scaffoldBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _T.ctaSolid,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Colors.black,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'R.A.C.O.M.A.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 1.2,
                  color: _T.ctaSolid,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: _T.ctaSolid,
                  strokeWidth: 2.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Checking session…',
                style: TextStyle(
                  color: isDark ? _T.desktopMuted : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: useDesktop ? _T.desktopBg : tc.scaffoldBg,
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                _buildNavbar(useDesktop: useDesktop),
                if (!_isOnline) _buildOfflineBanner(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: useDesktop
                        ? _buildDesktopBody()
                        : _buildMobileBody(tc),
                  ),
                ),
              ],
            ),
          ),
          if (_obscureContent) _buildPrivacyShield(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🔌 OFFLINE BANNER — visible kapag walang net
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _T.danger,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'No internet - need a network to login or demo.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyShield() {
    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: _T.shieldBg,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _T.ctaSolid,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.black,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'R.A.C.O.M.A.',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Session hidden for your privacy',
                style: TextStyle(
                  color: _T.desktopMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NAVBAR
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildNavbar({required bool useDesktop}) {
    if (useDesktop) return _buildDesktopNavbar();
    return _buildMobileNavbar();
  }

  Widget _buildDesktopNavbar() {
    return Container(
      decoration: const BoxDecoration(
        color: _T.desktopBg,
        border: Border(
          bottom: BorderSide(color: _T.desktopDivider, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
          child: Row(
            children: [
              _wrapLogoWithHiddenAdmin(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _T.ctaSolid,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.access_time_rounded,
                    color: Colors.black,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'R.A.C.O.M.A.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              if (_deviceCompromised) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red, size: 12),
                      SizedBox(width: 4),
                      Text('UNSAFE DEVICE',
                          style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              GestureDetector(
                onTap: _goToLogin,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Sign In',
                    style: TextStyle(
                      color: _T.desktopNavText,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileNavbar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_T.headerStart, _T.headerMid, _T.headerEnd],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _wrapLogoWithHiddenAdmin(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.back_hand_rounded,
                      color: _T.white, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'R.A.C.O.M.A',
                style: TextStyle(
                  color: _T.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _goToLogin,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: const Text(
                    'Log In',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DESKTOP BODY
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDesktopBody() {
    return Container(
      width: double.infinity,
      color: _T.desktopBg,
      padding: const EdgeInsets.symmetric(vertical: 96),
      child: BsContainer(
        maxWidth: 1600,
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _buildDesktopHeroLeft()),
            const SizedBox(width: 80),
            Expanded(flex: 4, child: _buildDesktopDashboard()),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeroLeft() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.verified_user_rounded,
                  color: _T.desktopBadge, size: 16),
              SizedBox(width: 8),
              Text(
                'Verified Location Tracking',
                style: TextStyle(
                  color: _T.desktopBadge,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        const Text(
          'Clock in',
          style: TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w700,
            height: 1.05,
            color: Colors.white,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_T.heroDescGradStart, _T.heroDescGradEnd],
          ).createShader(bounds),
          child: const Text(
            'where it matters.',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w700,
              height: 1.05,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const SizedBox(
          width: 576,
          child: Text(
            'Seamless, location-based time tracking for modern teams. '
                'Automatically verify when you are on-site and ready to work, '
                'ensuring accurate logs and eliminating guesswork.',
            style: TextStyle(
              color: _T.desktopMuted,
              fontSize: 18,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 48),
        Row(
          children: const [
            Icon(Icons.location_on_rounded,
                color: _T.workZoneIcon, size: 20),
            SizedBox(width: 8),
            Text(
              'The Working Zone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const SizedBox(
          width: 576,
          child: Text(
            'Authorized working zones are defined geographical areas '
                'designated for your workplace. Once you enter the perimeter, '
                'our Live GPS system authenticates your location, enabling the '
                'Clock In feature securely.',
            style: TextStyle(
              color: _T.desktopMuted,
              fontSize: 16,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: 32),
        _buildDesktopCTA(),
        const SizedBox(height: 16),
        SizedBox(
          width: 340,
          child: _buildDemoModeButton(),
        ),
      ],
    );
  }

  Widget _buildDesktopCTA() {
    return SizedBox(
      width: 340,
      child: GestureDetector(
        onTap: _goToLogin,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _T.ctaSolid,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF97316).withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Get Started',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.black, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopDashboard() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: _T.ctaSolid.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
        ),
        _buildDashboardPreview(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MOBILE BODY
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildMobileBody(_ThemeColors tc) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tc.heroBgStart, tc.heroBgEnd],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            bottom: -130,
            left: -150,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: _degToRad(425),
                child: Opacity(
                  opacity: tc.watermarkOpacity,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color.fromRGBO(255, 138, 0, 0.10),
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      _logoAsset,
                      width: 500,
                      height: 500,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        _secureLog('logo.png failed to load');
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroSection(tc),
              _buildWorkingZoneSection(tc),
              _buildDashboardPreview(),
              const SizedBox(height: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 256,
            height: 256,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _T.circleGradTop,
                  _T.circleGradMid,
                  _T.circleGradBottom
                ],
              ),
              border: Border.all(color: _T.circleBorder, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _T.buildingBg,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(255, 140, 0, 0.8),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
                const Positioned(
                  bottom: 40,
                  child: Text(
                    'Authorized Zone',
                    style: TextStyle(
                      color: _T.labelLime,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: _T.badgeBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.verified_user_rounded,
                    color: _T.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Verified Location Tracking',
                  style: TextStyle(
                    color: _T.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clock in',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: tc.heroTitle,
                  ),
                ),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [_T.heroDescGradStart, _T.heroDescGradEnd],
                  ).createShader(bounds),
                  child: const Text(
                    'where it matters.',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Seamless, location-based time tracking for modern teams. '
                  'Automatically verify when you are on-site and ready to work, '
                  'ensuring accurate logs and eliminating guesswork.',
              style: TextStyle(
                color: tc.heroDesc,
                fontSize: 13.5,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildMobileCTAButton(),
          const SizedBox(height: 12),
          _buildDemoModeButton(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMobileCTAButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _goToLogin,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _T.ctaSolid,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _T.ctaSolid.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(width: 8),
              Text(
                'LOGIN',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  color: Colors.black, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🎭 DEMO MODE BUTTON — dimmed kapag offline
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildDemoModeButton() {
    final canTap = _isOnline;

    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _openDemoMode,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: canTap ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: canTap
                  ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_T.demoGradStart, _T.demoGradEnd],
              )
                  : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6B6B6B), Color(0xFF3F3F3F)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: canTap
                  ? [
                BoxShadow(
                  color: _T.demoGradStart.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  canTap
                      ? Icons.science_rounded
                      : Icons.cloud_off_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  canTap ? '🎭 Try Demo Mode' : 'Demo (offline)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkingZoneSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: _T.workZoneIcon, size: 20),
              const SizedBox(width: 8),
              Text(
                'The Working Zone',
                style: TextStyle(
                  color: tc.heroTitle,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Authorized working zones are defined geographical areas designated '
                'for your workplace. Once you enter the perimeter, our Live GPS '
                'system authenticates your location, enabling the Clock In feature securely.',
            style: TextStyle(
              color: tc.heroDesc,
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _T.dashCardBg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF27272A),
                    border: Border.all(color: const Color(0xFF3F3F46)),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'JH',
                    style: TextStyle(
                      color: Color(0xFFFB923C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HI, JOHN HOWARD',
                        style: TextStyle(
                          color: _T.mutedGrey,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Employee Dashboard',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_T.statusStart, _T.statusEnd],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are currently',
                    style: TextStyle(
                      color: _T.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    'ready to work.',
                    style: TextStyle(
                      color: _T.ctaSolid,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Our system verified your location. You are ready to go.',
                    style: TextStyle(color: _T.mutedGrey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _T.toggleBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _T.toggleActive,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text(
                          'Inside Zone',
                          style: TextStyle(
                            color: _T.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const Center(
                        child: Text(
                          'Outside Zone',
                          style: TextStyle(
                            color: _T.inactiveTab,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Location Status',
                  style: TextStyle(
                    color: _T.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _T.green400,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live GPS',
                      style: TextStyle(color: _T.mutedGrey, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _T.locCardBg,
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _T.iconCircleBg,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('🏢', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HQ Main Office',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Inside Authorized Zone',
                        style: TextStyle(
                          color: _T.lime400,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: _T.ctaSolid,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clock In',
                        style: TextStyle(
                          color: _T.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '01:45 PM',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: _T.white, size: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}