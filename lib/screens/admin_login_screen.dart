// lib/screens/admin_login_screen.dart
// v3.6: 🎭 Demo Mode support — any credentials work when demo is enabled
//       🔒 Demo Mode requires internet connection
//       🔘 Added "Enter Demo Mode" button for quick testing
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../data/local/dao/connectivity_service.dart';
import '../services/admin_auth_service.dart';
import '../services/network_guard.dart';
import '../services/security_hardening_service.dart';
import '../services/device_info_service.dart';
import '../services/demo_mode_service.dart';
import 'admin_dashboard.dart';
import 'landing_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;
  final VoidCallback? onBack;
  final List<String> allowedEmailDomains;
  final bool forceLogout;

  const AdminLoginScreen({
    super.key,
    this.onLoginSuccess,
    this.onBack,
    this.allowedEmailDomains = const [],
    this.forceLogout = false,
  });

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _heroAsset = 'assets/images/logo1.png';

  static const int _maxFailedAttempts = 5;
  static const int _lockoutMinutes = 15;

  static const Duration _loginTimeout = Duration(seconds: 25);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const int _minInputLength = 6;
  static const Duration _autoClearTimeout = Duration(seconds: 30);

  static const int _cloudMaxAttemptsPerHour = 10;
  static const int _cloudMaxAttemptsPerDay = 30;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _sessionCleared = false;
  bool _sessionClearing = true;
  bool _redirecting = false;
  bool _authReady = false;
  User? _restoredUser;

  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _capsLockOn = false;
  String? _errorMessage;
  String? _infoMessage;

  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  DateTime? _lastFailedAttemptAt;
  DateTime? _authBackoffUntil;
  Timer? _lockoutTimer;
  Timer? _loginGuardTimer;
  Timer? _autoClearTimer;
  Timer? _clockTimer;
  Timer? _tickerTimer;
  Timer? _connectivityTimer;

  Timer? _holdTimer;
  bool _returningToEmployee = false;

  String? _deviceFingerprint;
  String? _deviceBinding;
  bool _deviceCompromised = false;
  bool _integrityChecked = false;
  String _deviceModel = 'Unknown Device';

  String? _sessionNonce;
  int _loginAttemptsThisSession = 0;

  bool _showSuccess = false;

  /// 🌐 Live connectivity state (works even in demo)
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  DateTime _now = DateTime.now();

  double _passwordStrength = 0.0;
  String _passwordStrengthLabel = '';

  late AnimationController _ctrl;
  late AnimationController _pulseCtrl;
  late AnimationController _successCtrl;
  late AnimationController _orbCtrl;
  late AnimationController _glowCtrl;

  late Animation<double> _fade;
  late Animation<double> _slide;
  late Animation<double> _pulseAnim;
  late Animation<double> _successAnim;
  late Animation<double> _orbAnim;
  late Animation<double> _glowAnim;

  final List<String> _tickerMessages = [
    'John D. clocked in — 2m ago',
    'Maria S. clocked out — 5m ago',
    'System backup completed — 12m ago',
    'New employee enrolled — 1h ago',
    'Security scan passed — 2h ago',
  ];
  int _tickerIndex = 0;

  static const Color _bg = Colors.white;
  static const Color _textPrimary = Color(0xFF000000);
  static const Color _textMuted = Color(0xFF71717A);
  static const Color _cardBorder = Color(0xFFE5E7EB);
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _orangeDeep = Color(0xFFF54900);
  static const Color _red = Color(0xFFEF4444);
  static const Color _green = Color(0xFF16A34A);

  // 🎭 DEMO
  bool get _isDemo => DemoModeService.instance.isEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🌐 Sync initial connectivity
    try {
      _isOnline = ConnectivityService.instance.isOnline;
    } catch (_) {
      _isOnline = true;
    }

    // 🌐 Listen for connectivity changes (works even in demo)
    try {
      _connectivitySub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            setState(() => _isOnline = online);
            _log('🌐 connectivity changed: online=$online');
          });
    } catch (e) {
      _log('⚠️ connectivity listen failed: $e');
    }

    _clearSessionAndInitialize();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 DEMO MODE
  // ═══════════════════════════════════════════════════════════════
  bool _isOnlineSafely() {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

  void _showOfflineSnack([String? custom]) {
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
                  custom ??
                      'Internet connection is required to continue.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 🎭 Enter demo mode — enables DemoModeService and immediately goes to dashboard.
  Future<void> _enterDemoMode() async {
    if (_loading) return;

    // 🔌 Internet required even for demo
    if (!_isOnlineSafely()) {
      _log('🎭 [DemoMode] BLOCKED — no internet');
      _showOfflineSnack(
          'Internet connection is required for Demo Mode.');
      return;
    }

    _log('🎭 [DemoMode] Enabling admin demo session...');

    if (!kIsWeb) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      // ✅ Enable demo mode globally
      await DemoModeService.instance.startDemoSession();

      // Mock a minimal session nonce for the demo run
      _sessionNonce = _generateSessionNonce();

      // Best-effort audit log (silently ignored if it fails)
      _fireAndForget(() async {
        await FirebaseFirestore.instance
            .collection('admin_login_logs')
            .add({
          'emailMasked': 'demo@racoma.com',
          'success': true,
          'reason': 'demo_mode',
          'deviceFingerprint': _deviceFingerprint,
          'deviceCompromised': false,
          'sessionNonce': _sessionNonce,
          'platform': kIsWeb ? 'web' : 'mobile',
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 3));
      }, tag: 'demoAuditLog');

      // Clear sensitive input just in case
      _passCtrl.clear();

      if (!mounted) return;

      // Show success overlay
      setState(() => _showSuccess = true);
      _successCtrl.forward(from: 0);

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      // 🚀 Navigate to dashboard
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
            (_) => false,
      );
    } catch (e) {
      _log('❌ [DemoMode] Failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _showSuccess = false;
        _errorMessage = 'Failed to start Demo Mode. Please try again.';
      });
      _successCtrl.reset();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SESSION CLEANUP
  // ═══════════════════════════════════════════════════════════════
  Future<void> _clearSessionAndInitialize() async {
    if (widget.forceLogout) {
      _log('🔒 Force Logout...');
      try {
        if (FirebaseAuth.instance.currentUser != null) {
          await FirebaseAuth.instance.signOut();
        }
      } catch (e) {
        _log('signOut err: $e');
      }
      try {
        await AdminAuthService.instance.signOut();
      } catch (_) {}
      try {
        await SecurityHardeningService.instance.clearSession();
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys().toList();
        for (final key in keys) {
          if (key.startsWith('fp_preauth_') ||
              key.startsWith('admin_session_') ||
              key.contains('session_nonce') ||
              key.contains('preauth')) {
            await prefs.remove(key);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _sessionCleared = true;
      _sessionClearing = false;
    });

    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _orbCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 16, end: 0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _successAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut));
    _orbAnim = CurvedAnimation(parent: _orbCtrl, curve: Curves.linear);
    _glowAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _ctrl.forward();

    _sessionNonce = _generateSessionNonce();
    _bootstrapSecurity();
    _loadSavedState();
    _loadDeviceModel();
    _startClock();
    _startTicker();

    _passCtrl.addListener(_updatePasswordStrength);
    _passCtrl.addListener(_onPasswordChanged);
    _passCtrl.addListener(_checkCapsLock);
    _emailCtrl.addListener(_clearMessagesOnType);
    _passCtrl.addListener(_clearMessagesOnType);

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    _waitForAuthRestore();
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTH RESTORE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _waitForAuthRestore() async {
    // 🎭 In demo mode, skip restore — go straight to form
    if (_isDemo) {
      _log('🎭 [DemoMode] Skipping auth restore');
      if (mounted) {
        setState(() {
          _authReady = true;
          _restoredUser = null;
        });
      }
      return;
    }

    if (widget.forceLogout) {
      if (mounted) {
        setState(() {
          _authReady = true;
          _restoredUser = null;
        });
      }
      return;
    }

    _log('🔄 Polling for Firebase session...');
    User? user;
    for (int i = 0; i < 6; i++) {
      user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _log('✅ Session restored after ${i * 500}ms: ${user.uid}');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;

    setState(() {
      _restoredUser = user;
      _authReady = true;
    });

    if (user != null) {
      _attemptAutoRedirect(user);
    } else {
      _log('❌ No session found. Showing login form.');
    }
  }

  Future<void> _attemptAutoRedirect(User user) async {
    if (_redirecting || widget.forceLogout || _isDemo) return;

    _redirecting = true;
    _log('🔍 Auto-redirect check for ${user.uid}');

    try {
      final verified = await _checkEmailVerified();
      if (!mounted) return;

      if (verified) {
        _log('✅ Admin verified! Going to Dashboard...');
        _clockTimer?.cancel();
        _tickerTimer?.cancel();

        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
              (_) => false,
        );
      } else {
        _log('❌ Admin revoked/inactive. Signing out.');
        try {
          await AdminAuthService.instance.signOut();
        } catch (_) {}
        if (mounted) {
          setState(() {
            _redirecting = false;
            _restoredUser = null;
          });
        }
      }
    } catch (e) {
      _log('Auto-redirect error: $e');
      if (mounted) setState(() => _redirecting = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // TIMERS
  // ═══════════════════════════════════════════════════════════════
  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _tickerIndex = (_tickerIndex + 1) % _tickerMessages.length;
      });
    });
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadDeviceModel() async {
    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (mounted) setState(() => _deviceModel = model);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // CAPS LOCK
  // ═══════════════════════════════════════════════════════════════
  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyUpEvent) {
      _checkCapsLock();
    }
    return false;
  }

  void _checkCapsLock() {
    if (kIsWeb) return;
    try {
      final capsOn = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.capsLock);
      if (capsOn != _capsLockOn && mounted) {
        setState(() => _capsLockOn = capsOn);
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // SECURITY BOOTSTRAP
  // ═══════════════════════════════════════════════════════════════
  Future<void> _bootstrapSecurity() async {
    try {
      await SecurityHardeningService.instance.enableSecureScreen();
    } catch (_) {}
    try {
      final ok =
      await SecurityHardeningService.instance.checkDeviceIntegrity();
      _deviceCompromised = !ok;
      _integrityChecked = true;
    } catch (_) {
      _integrityChecked = true;
    }
    try {
      _deviceFingerprint =
      await SecurityHardeningService.instance.getDeviceFingerprint();
    } catch (_) {}
    try {
      _deviceBinding =
      await SecurityHardeningService.instance.getDeviceBindingToken();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _lockoutTimer?.cancel();
    _loginGuardTimer?.cancel();
    _holdTimer?.cancel();
    _autoClearTimer?.cancel();
    _clockTimer?.cancel();
    _tickerTimer?.cancel();
    _connectivityTimer?.cancel();
    _connectivitySub?.cancel();

    if (_sessionCleared) {
      _ctrl.dispose();
      _pulseCtrl.dispose();
      _successCtrl.dispose();
      _orbCtrl.dispose();
      _glowCtrl.dispose();
    }

    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    SecurityHardeningService.instance.disableSecureScreen();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_passCtrl.text.isNotEmpty) _passCtrl.clear();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  static String _maskEmail(String email) {
    if (email.isEmpty) return '';
    final parts = email.split('@');
    if (parts.length != 2) return '***';
    final local = parts[0];
    if (local.length <= 2) return '**@${parts[1]}';
    return '${local[0]}***${local[local.length - 1]}@${parts[1]}';
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[AdminLogin] $message');
  }

  void _fireAndForget(
      Future<void> Function() action, {
        String tag = 'async',
      }) {
    unawaited(
      action().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (kDebugMode) debugPrint('[AdminLogin] $tag timed out');
        },
      ).catchError((e, st) {
        if (kDebugMode) {
          debugPrint('[AdminLogin] $tag failed: $e');
        }
      }),
    );
  }

  static String _sanitize(dynamic raw, {int maxLen = 200}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > maxLen) s = s.substring(0, maxLen);
    return s;
  }

  String _generateSessionNonce() {
    final rand = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashEmail(String email) {
    return sha256.convert(utf8.encode(email.toLowerCase().trim())).toString();
  }

  Duration _computeBackoffDelay() {
    if (_failedAttempts <= 0) return Duration.zero;
    final seconds = math.min(math.pow(2, _failedAttempts).toInt(), 30);
    return Duration(seconds: seconds);
  }

  bool _isEmailDomainAllowed(String email) {
    if (widget.allowedEmailDomains.isEmpty) return true;
    final at = email.indexOf('@');
    if (at < 0) return false;
    final domain = email.substring(at + 1).toLowerCase();
    return widget.allowedEmailDomains
        .any((d) => domain == d.toLowerCase() || domain.endsWith('.$d'));
  }

  // ═══════════════════════════════════════════════════════════════
  // CLOUD RATE LIMIT
  // ═══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _checkCloudRateLimit(String email) async {
    try {
      final hash = _hashEmail(email);
      final now = DateTime.now();
      final hourWindow = now.subtract(const Duration(hours: 1));
      final dayWindow = now.subtract(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('security_events')
          .where('type', isEqualTo: 'admin_login_failed')
          .where('emailHash', isEqualTo: hash)
          .where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(dayWindow))
          .limit(50)
          .get()
          .timeout(_probeTimeout);

      int hourCount = 0;
      int dayCount = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        DateTime? dt;
        if (ts is Timestamp) dt = ts.toDate();
        if (dt == null) continue;
        dayCount++;
        if (dt.isAfter(hourWindow)) hourCount++;
      }

      if (hourCount >= _cloudMaxAttemptsPerHour) {
        return {'allowed': false, 'reason': 'cloud_hour_limit'};
      }
      if (dayCount >= _cloudMaxAttemptsPerDay) {
        return {'allowed': false, 'reason': 'cloud_day_limit'};
      }
      return {'allowed': true};
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminLogin] cloud rate check: $e');
      return {'allowed': true, 'reason': 'check_failed'};
    }
  }

  Future<void> _logCloudFailedAttempt(String email, String reason) async {
    try {
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_login_failed',
        'severity': 'medium',
        'emailHash': _hashEmail(email),
        'emailMasked': _maskEmail(email),
        'reason': _sanitize(reason, maxLen: 64),
        'deviceFingerprint': _deviceFingerprint,
        'deviceCompromised': _deviceCompromised,
        'sessionNonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'admin_login',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      _log('cloud failed log: $e');
    }
  }

  Future<void> _logNewDeviceLogin(String email) async {
    try {
      final hash = _hashEmail(email);
      final prefs = await SharedPreferences.getInstance();
      final knownKey = 'admin_known_devices_$hash';
      final known = prefs.getStringList(knownKey) ?? [];
      final fp = _deviceFingerprint ?? 'unknown';
      if (known.contains(fp)) return;

      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_new_device_login',
        'severity': 'high',
        'emailHash': hash,
        'emailMasked': _maskEmail(email),
        'deviceFingerprint': fp,
        'deviceBinding': _deviceBinding,
        'deviceModel': _deviceModel,
        'sessionNonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'admin_login',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 4));

      known.add(fp);
      if (known.length > 10) known.removeRange(0, known.length - 10);
      await prefs.setStringList(knownKey, known);
    } catch (e) {
      _log('new device log: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PASSWORD HANDLING
  // ═══════════════════════════════════════════════════════════════
  void _onPasswordChanged() {
    _autoClearTimer?.cancel();
    if (_passCtrl.text.isEmpty) return;
    _autoClearTimer = Timer(_autoClearTimeout, () {
      if (!mounted) return;
      if (_passCtrl.text.isNotEmpty && !_loading) {
        _passCtrl.clear();
        setState(() => _infoMessage = 'Password auto-cleared for security.');
      }
    });
  }

  void _handleHoldStart() {
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _returnToEmployeeSide();
    });
  }

  void _handleHoldEnd() {
    _holdTimer?.cancel();
  }

  Future<void> _returnToEmployeeSide() async {
    if (_returningToEmployee) return;
    _returningToEmployee = true;
    try {
      if (!kIsWeb) HapticFeedback.mediumImpact();
      if (!mounted) return;
      _passCtrl.clear();
      try {
        await Clipboard.setData(const ClipboardData(text: ''));
      } catch (_) {}
      try {
        await AdminAuthService.instance.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LandingScreen()),
            (_) => false,
      );
    } catch (e) {
      _log('❌ returnToEmployeeSide: $e');
    } finally {
      _returningToEmployee = false;
    }
  }

  Widget _wrapWithHiddenReturn({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _handleHoldStart(),
      onTapUp: (_) => _handleHoldEnd,
      onTapCancel: _handleHoldEnd,
      onLongPressStart: (_) => _handleHoldStart(),
      onLongPressEnd: (_) => _handleHoldEnd(),
      onLongPressCancel: _handleHoldEnd,
      child: child,
    );
  }

  void _clearMessagesOnType() {
    if (_errorMessage == null && _infoMessage == null) return;
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
      _infoMessage = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SAVED STATE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('admin_saved_email') ?? '';
      final rememberMe = prefs.getBool('admin_remember_me') ?? false;
      final failedCount = prefs.getInt('admin_failed_attempts') ?? 0;
      final lockoutMs = prefs.getInt('admin_lockout_until') ?? 0;
      final lastFailMs = prefs.getInt('admin_last_failed_at') ?? 0;

      if (!mounted) return;

      setState(() {
        _emailCtrl.text = savedEmail;
        _rememberMe = rememberMe;
        _failedAttempts = failedCount;

        if (lastFailMs > 0) {
          _lastFailedAttemptAt =
              DateTime.fromMillisecondsSinceEpoch(lastFailMs);
        }
        if (lockoutMs > 0) {
          final lockout = DateTime.fromMillisecondsSinceEpoch(lockoutMs);
          if (lockout.isAfter(DateTime.now())) {
            _lockoutUntil = lockout;
            _startLockoutCountdown();
          } else {
            _failedAttempts = 0;
            _lockoutUntil = null;
            _fireAndForget(_clearLockoutPrefs, tag: 'clearLockout');
          }
        }
      });
    } catch (_) {}
  }

  void _updatePasswordStrength() {
    if (!mounted) return;
    final pwd = _passCtrl.text;
    if (pwd.isEmpty) {
      if (_passwordStrength != 0) {
        setState(() {
          _passwordStrength = 0;
          _passwordStrengthLabel = '';
        });
      }
      return;
    }
    double score = 0;
    if (pwd.length >= 8) score += 0.25;
    if (pwd.length >= 12) score += 0.15;
    if (RegExp(r'[a-z]').hasMatch(pwd)) score += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(pwd)) score += 0.15;
    if (RegExp(r'[0-9]').hasMatch(pwd)) score += 0.15;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\[\]\\/;`~+=]').hasMatch(pwd)) {
      score += 0.15;
    }
    score = score.clamp(0.0, 1.0);

    String label;
    if (score < 0.4) {
      label = 'Weak';
    } else if (score < 0.7) {
      label = 'Fair';
    } else if (score < 0.9) {
      label = 'Strong';
    } else {
      label = 'Very Strong';
    }
    setState(() {
      _passwordStrength = score;
      _passwordStrengthLabel = label;
    });
  }

  Color _strengthColor(double s) {
    if (s < 0.4) return _red;
    if (s < 0.7) return const Color(0xFFF59E0B);
    if (s < 0.9) return _green;
    return const Color(0xFF059669);
  }

  // ═══════════════════════════════════════════════════════════════
  // LOCKOUT
  // ═══════════════════════════════════════════════════════════════
  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutUntil == null || _lockoutUntil!.isBefore(DateTime.now())) {
        timer.cancel();
        setState(() {
          _lockoutUntil = null;
          _failedAttempts = 0;
        });
        _fireAndForget(_clearLockoutPrefs, tag: 'clearLockout');
        return;
      }
      setState(() {});
    });
  }

  Future<void> _clearLockoutPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_failed_attempts');
      await prefs.remove('admin_lockout_until');
      await prefs.remove('admin_last_failed_at');
    } catch (_) {}
  }

  String _remainingLockoutText() {
    if (_lockoutUntil == null) return '';
    final diff = _lockoutUntil!.difference(DateTime.now());
    if (diff.isNegative) return '0:00';
    final m = diff.inMinutes;
    final s = diff.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _isLockedOut =>
      _lockoutUntil != null && _lockoutUntil!.isAfter(DateTime.now());

  Future<void> _recordFailedAttempt() async {
    _failedAttempts++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('admin_failed_attempts', _failedAttempts);
      await prefs.setInt(
          'admin_last_failed_at', DateTime.now().millisecondsSinceEpoch);
      if (_failedAttempts >= _maxFailedAttempts) {
        final until =
        DateTime.now().add(const Duration(minutes: _lockoutMinutes));
        await prefs.setInt(
            'admin_lockout_until', until.millisecondsSinceEpoch);
        if (mounted) {
          setState(() => _lockoutUntil = until);
          _startLockoutCountdown();
        }
      }
      _lastFailedAttemptAt = DateTime.now();
    } catch (_) {}
  }

  Future<void> _resetFailedAttempts() async {
    _failedAttempts = 0;
    _lockoutUntil = null;
    _authBackoffUntil = null;
    _lockoutTimer?.cancel();
    await _clearLockoutPrefs();
  }

  void _logLoginAttempt({
    required String email,
    required bool success,
    String? reason,
  }) {
    _fireAndForget(() async {
      final maskedEmail = _maskEmail(email);
      await FirebaseFirestore.instance.collection('admin_login_logs').add({
        'emailMasked': maskedEmail,
        'success': success,
        'reason': _sanitize(reason ?? (success ? 'ok' : 'unknown'), maxLen: 64),
        'deviceFingerprint': _deviceFingerprint,
        'deviceCompromised': _deviceCompromised,
        'sessionNonce': _sessionNonce,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 3));
    }, tag: 'auditLog');
  }

  // ═══════════════════════════════════════════════════════════════
  // ADMIN VERIFICATION
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _checkEmailVerified() async {
    // 🎭 Demo mode — always verified
    if (_isDemo) {
      _log('🎭 [DemoMode] Auto-verified');
      return true;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final uid = user.uid;
      if (uid.isEmpty) return false;

      try {
        final adminDoc = await FirebaseFirestore.instance
            .collection('admins')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 5));

        if (adminDoc.exists) {
          final data = adminDoc.data();
          final isActive = data?['isActive'];
          final revoked = data?['revoked'] == true;
          if (revoked) return false;
          if (isActive == null || isActive == true) return true;
          return false;
        }
      } catch (_) {
        // Firestore check failed — fall back to emailVerified
      }

      if (!user.emailVerified) {
        try {
          await user.reload();
          final refreshed = FirebaseAuth.instance.currentUser;
          return refreshed?.emailVerified ?? false;
        } catch (_) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LOGIN — MAIN HANDLER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();

    // ═══════════════════════════════════════════════════════════
    // 🎭 DEMO MODE — accept ANY credentials (requires internet)
    // ═══════════════════════════════════════════════════════════
    if (_isDemo) {
      _log('🎭 [DemoMode] _handleLogin — DEMO PATH');

      // 🔌 Internet required even in demo
      if (!_isOnlineSafely()) {
        _showOfflineSnack(
            'Internet connection is required for Demo Mode.');
        return;
      }

      final email = _emailCtrl.text.trim().toLowerCase();
      final password = _passCtrl.text;

      // Basic validation — still need "something" typed
      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _errorMessage =
          'Enter any email and password (demo accepts anything).';
        });
        return;
      }

      if (_loading) return;
      setState(() {
        _loading = true;
        _errorMessage = null;
        _infoMessage = null;
      });

      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;

      _sessionNonce = _generateSessionNonce();
      _passCtrl.clear();

      try {
        await Clipboard.setData(const ClipboardData(text: ''));
      } catch (_) {}

      // Best-effort audit log (ignored on failure)
      _fireAndForget(() async {
        await FirebaseFirestore.instance
            .collection('admin_login_logs')
            .add({
          'emailMasked': _maskEmail(email),
          'success': true,
          'reason': 'demo_mode_any_credentials',
          'deviceFingerprint': _deviceFingerprint,
          'deviceCompromised': false,
          'sessionNonce': _sessionNonce,
          'platform': kIsWeb ? 'web' : 'mobile',
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 3));
      }, tag: 'demoAuditLog');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _showSuccess = true;
      });
      _successCtrl.forward(from: 0);

      if (!kIsWeb) {
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
      }

      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;

      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!();
        return;
      }

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AdminDashboard()),
            (_) => false,
      );
      return;
    }

    // ─── Local gates ─────────────────────────────────────────
    if (_isLockedOut) {
      setState(() => _errorMessage =
      'Account locked. Try again in ${_remainingLockoutText()}.');
      return;
    }
    if (_authBackoffUntil != null &&
        _authBackoffUntil!.isAfter(DateTime.now())) {
      final remaining =
          _authBackoffUntil!.difference(DateTime.now()).inSeconds;
      setState(() =>
      _errorMessage = 'Please wait ${remaining}s before trying again.');
      return;
    }
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailCtrl.text.trim().toLowerCase();
    final password = _passCtrl.text;

    if (password.length < _minInputLength) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }
    if (!_isEmailDomainAllowed(email)) {
      _logLoginAttempt(
          email: email, success: false, reason: 'domain_not_allowed');
      setState(() => _errorMessage =
      'Email domain is not allowed for admin access. Contact IT.');
      return;
    }
    if (_deviceCompromised) {
      _logLoginAttempt(
          email: email, success: false, reason: 'compromised_device');
      setState(() => _errorMessage =
      'This device is flagged as compromised. Access blocked.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    final cloudCheck = await _checkCloudRateLimit(email);
    if (!mounted) return;
    if (cloudCheck['allowed'] != true) {
      _logLoginAttempt(
          email: email,
          success: false,
          reason: cloudCheck['reason']?.toString() ?? 'cloud_limit');
      setState(() {
        _loading = false;
        _errorMessage = cloudCheck['reason'] == 'cloud_hour_limit'
            ? 'Too many attempts in the last hour. Please wait.'
            : 'Daily login limit reached. Contact IT support.';
      });
      return;
    }

    bool timedOut = false;
    _loginGuardTimer?.cancel();
    _loginGuardTimer = Timer(_loginTimeout, () {
      if (!mounted) return;
      timedOut = true;
      setState(() {
        _loading = false;
        _errorMessage = 'Login timed out. Check your connection.';
      });
    });

    String? error;
    try {
      error = await AdminAuthService.instance
          .signIn(email: email, password: password)
          .timeout(_loginTimeout,
          onTimeout: () => throw TimeoutException('Login timed out.'));
    } on TimeoutException {
      error = 'Login timed out. Please try again.';
    } on FirebaseAuthException catch (e) {
      error = _humanizeAuthError(e.code);
    } on FirebaseException catch (e) {
      error = _humanizeFirebaseError(e.code);
    } catch (e) {
      if (kDebugMode) debugPrint('[AdminLogin] unexpected: $e');
      error = 'Unexpected error. Please try again.';
    } finally {
      _loginGuardTimer?.cancel();
      _loginGuardTimer = null;
      if (mounted && !timedOut) {
        setState(() => _loading = false);
      }
    }

    if (!mounted) return;
    if (timedOut) return;

    _loginAttemptsThisSession++;

    if (error != null) {
      await _recordFailedAttempt();
      _fireAndForget(() => _logCloudFailedAttempt(email, _classifyError(error!)),
          tag: 'cloudFailedLog');
      _logLoginAttempt(
          email: email, success: false, reason: _classifyError(error));

      final backoff = _computeBackoffDelay();
      if (backoff > Duration.zero) {
        _authBackoffUntil = DateTime.now().add(backoff);
      }

      if (!mounted) return;
      final remaining = _maxFailedAttempts - _failedAttempts;
      setState(() {
        if (_isLockedOut) {
          _errorMessage =
          'Too many failed attempts. Locked for $_lockoutMinutes minutes.';
        } else if (remaining <= 2 && remaining > 0) {
          _errorMessage = '$error\n⚠️ $remaining attempt(s) left.';
        } else if (backoff > Duration.zero) {
          _errorMessage =
          '$error\n⏱️ Wait ${backoff.inSeconds}s before next try.';
        } else {
          _errorMessage = error;
        }
      });
      if (!kIsWeb) {
        try {
          HapticFeedback.heavyImpact();
        } catch (_) {}
      }
      return;
    }

    final verified = await _checkEmailVerified();
    if (!verified) {
      try {
        await AdminAuthService.instance.signOut();
      } catch (_) {}
      _logLoginAttempt(
          email: email, success: false, reason: 'not_verified_or_revoked');
      if (!mounted) return;
      setState(() => _errorMessage =
      'You are not an admin or your access has been revoked. Contact IT.');
      return;
    }

    _sessionNonce = _generateSessionNonce();
    _fireAndForget(() => _logNewDeviceLogin(email), tag: 'newDeviceLog');
    _passCtrl.clear();

    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}

    await _resetFailedAttempts();
    _logLoginAttempt(email: email, success: true);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('admin_saved_email', email);
        await prefs.setBool('admin_remember_me', true);
      } else {
        await prefs.remove('admin_saved_email');
        await prefs.setBool('admin_remember_me', false);
      }
    } catch (_) {}

    if (!mounted) return;

    setState(() => _showSuccess = true);
    _successCtrl.forward(from: 0);
    if (!kIsWeb) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    if (widget.onLoginSuccess != null) {
      widget.onLoginSuccess!();
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminDashboard()),
          (_) => false,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ERROR MESSAGES
  // ═══════════════════════════════════════════════════════════════
  String _humanizeAuthError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Invalid email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait.';
      case 'network-request-failed':
        return 'You appear to be offline. Check your connection and try again.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  String _humanizeFirebaseError(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Access denied. Please contact your administrator.';
      case 'unavailable':
        return 'Service temporarily unavailable.';
      default:
        return 'Server error. Please try again.';
    }
  }

  String _classifyError(String error) {
    final e = error.toLowerCase();
    if (e.contains('password') || e.contains('credential')) {
      return 'invalid_credentials';
    }
    if (e.contains('network') ||
        e.contains('connection') ||
        e.contains('offline')) {
      return 'network_error';
    }
    if (e.contains('disabled')) return 'account_disabled';
    if (e.contains('timeout')) return 'timeout';
    return 'other';
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_sessionClearing || !_authReady || _redirecting) {
      return _buildLoadingScreen(
        _redirecting
            ? 'Redirecting to dashboard...'
            : (_sessionClearing
            ? 'Preparing secure session...'
            : 'Checking session...'),
      );
    }

    return _buildMainScaffold();
  }

  Widget _buildLoadingScreen([String message = 'Loading...']) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: _orange,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _buildFormSide()),
                      Expanded(flex: 6, child: _buildHeroSide()),
                    ],
                  );
                }
                return _buildFormSide();
              },
            ),
            if (!_isOnline) _buildOfflineBanner(),
            if (_showSuccess) _buildSuccessOverlay(),
          ],
        ),
      ),
    );
  }

  // 🌐 Offline banner
  Widget _buildOfflineBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: _red,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'No internet connection — login requires network',
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
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    final isDemoSuccess = _isDemo;
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.95),
        child: Center(
          child: AnimatedBuilder(
            animation: _successAnim,
            builder: (_, __) => Transform.scale(
              scale: _successAnim.value,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_orange, _orangeDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _orange.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      isDemoSuccess
                          ? Icons.science_rounded
                          : Icons.check_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isDemoSuccess
                        ? 'Demo Mode Active'
                        : 'Login Successful',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isDemoSuccess
                        ? 'Entering admin dashboard (demo)...'
                        : 'Redirecting to dashboard...',
                    style: const TextStyle(
                        fontSize: 13, color: _textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormSide() {
    return Container(
      color: _bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(color: _cardBorder.withValues(alpha: 0.5)),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 40),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AnimatedBuilder(
                            animation: _ctrl,
                            builder: (context, _) {
                              return Opacity(
                                opacity: _fade.value,
                                child: Transform.translate(
                                  offset: Offset(0, _slide.value),
                                  child: _buildFormContent(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormContent() {
    final locked = _isLockedOut;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _wrapWithHiddenReturn(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientOrange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _orange.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.front_hand_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('R.A.C.O.M.A.',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                            letterSpacing: -0.4,
                            height: 1.1,
                          )),
                      SizedBox(height: 2),
                      Text('ADMIN CONSOLE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _orange,
                            letterSpacing: 2,
                          )),
                    ],
                  ),
                  const Spacer(),
                  if (_isDemo) _demoBadge(),
                ],
              ),
            ),
            const SizedBox(height: 36),
            const Text('Welcome back.',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                  letterSpacing: -0.8,
                  height: 1.15,
                )),
            const SizedBox(height: 8),
            Text(
              _isDemo
                  ? 'Demo mode is active — any email and password will work.'
                  : 'Enter your admin credentials to continue.',
              style: const TextStyle(
                  fontSize: 13, color: _textMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            _buildDeviceInfoCard(),
            const SizedBox(height: 20),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _securityBadge(
                  icon: Icons.shield_rounded,
                  label: kIsWeb ? 'SECURE WEB' : 'FLAG_SECURE',
                  color: _green,
                ),
                if (_deviceFingerprint != null)
                  _securityBadge(
                      icon: Icons.fingerprint_rounded,
                      label: 'DEVICE ID',
                      color: _orange),
                if (_deviceCompromised)
                  _securityBadge(
                      icon: Icons.warning_amber_rounded,
                      label: 'UNSAFE DEVICE',
                      color: _red),
                if (_isDemo)
                  _securityBadge(
                      icon: Icons.science_rounded,
                      label: 'DEMO',
                      color: _orange),
              ],
            ),
            const SizedBox(height: 20),
            if (locked) ...[
              _buildLockedBanner(),
              const SizedBox(height: 16),
            ],
            if (_deviceCompromised && !_isDemo) ...[
              _banner(
                icon: Icons.security_rounded,
                title: 'Unsafe Device Detected',
                message:
                'This device failed the security integrity check. Login is disabled.',
                color: _red,
              ),
              const SizedBox(height: 16),
            ],
            if (_errorMessage != null && !locked) ...[
              _banner(
                  icon: Icons.error_outline_rounded,
                  message: _errorMessage!,
                  color: _red),
              const SizedBox(height: 16),
            ],
            if (_infoMessage != null && _errorMessage == null) ...[
              _banner(
                  icon: Icons.info_outline_rounded,
                  message: _infoMessage!,
                  color: _green),
              const SizedBox(height: 16),
            ],
            _fieldLabel('Email Address'),
            const SizedBox(height: 8),
            Semantics(
              textField: true,
              label: 'Admin email address',
              child: TextFormField(
                controller: _emailCtrl,
                focusNode: _emailFocus,
                enabled: !locked && !_loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                cursorColor: _orange,
                onFieldSubmitted: (_) => _passFocus.requestFocus(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$')
                      .hasMatch(v.trim())) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
                decoration: _inputDeco(
                    hint: _isDemo ? 'any@email.com' : 'admin@racoma.com',
                    icon: Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 16),
            _fieldLabel('Password'),
            const SizedBox(height: 8),
            Semantics(
              textField: true,
              label: 'Admin password',
              child: TextFormField(
                controller: _passCtrl,
                focusNode: _passFocus,
                enabled: !locked && !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                cursorColor: _orange,
                onFieldSubmitted: (_) => _loading ? null : _handleLogin(),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Password is required';
                  }
                  return null;
                },
                decoration: _inputDeco(
                    hint: _isDemo ? 'any password' : '••••••••',
                    icon: Icons.lock_outline_rounded)
                    .copyWith(
                  suffixIcon: IconButton(
                    onPressed: locked || _loading
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => RotationTransition(
                        turns: Tween(begin: 0.5, end: 1.0).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        _obscure
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        key: ValueKey(_obscure),
                        color: _textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_capsLockOn && _passCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_capslock_rounded,
                        size: 14, color: Color(0xFF92400E)),
                    SizedBox(width: 6),
                    Text('Caps Lock is ON',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        )),
                  ],
                ),
              ),
            ],
            if (_passCtrl.text.isNotEmpty && !_isDemo) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _passwordStrength,
                        minHeight: 4,
                        backgroundColor: _cardBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _strengthColor(_passwordStrength),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(_passwordStrengthLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _strengthColor(_passwordStrength),
                      )),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: locked || _loading
                        ? null
                        : (v) => setState(() => _rememberMe = v ?? false),
                    activeColor: _orange,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: const BorderSide(color: _cardBorder, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: locked || _loading
                      ? null
                      : () => setState(() => _rememberMe = !_rememberMe),
                  child: const Text('Remember Me',
                      style: TextStyle(
                          fontSize: 13,
                          color: _textPrimary,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_loading || locked) ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _cardBorder,
                  disabledForegroundColor: _textMuted,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: locked
                        ? const LinearGradient(
                        colors: [_cardBorder, _cardBorder])
                        : const LinearGradient(
                      colors: [_orange, _orangeDeep],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: (_loading || locked)
                        ? null
                        : [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    child: _loading
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          locked
                              ? 'Locked (${_remainingLockoutText()})'
                              : (_isDemo
                              ? 'Enter Dashboard (Demo)'
                              : 'Log In'),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: Colors.white),
                        ),
                        if (!locked && !_loading && kIsWeb) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('↵',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ═══════════════════════════════════════════════════════════
            // 🎭 DEMO MODE BUTTON
            // ═══════════════════════════════════════════════════════════
            if (!_isDemo) ...[
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _enterDemoMode,
                  icon: const Icon(Icons.science_rounded, size: 18),
                  label: const Text('Enter Demo Mode'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _orange,
                    side: BorderSide(
                        color: _orange.withValues(alpha: 0.5), width: 1.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Skip login — for testing and demos only',
                  style: TextStyle(
                      fontSize: 11,
                      color: _textMuted,
                      fontStyle: FontStyle.italic),
                ),
              ),
            ] else ...[
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.science_rounded, size: 16, color: _orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Demo Mode active — any credentials will be accepted.',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _orange),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildTrustFooter(),
            const SizedBox(height: 24),
            Text(
              'Copyright © ${DateTime.now().year} R.A.C.O.M.A. HRIS.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, color: _textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.science_rounded, size: 12, color: _orange),
          SizedBox(width: 5),
          Text('DEMO',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _orange,
                  letterSpacing: 0.8)),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
            letterSpacing: 0.2));
  }

  Widget _buildDeviceInfoCard() {
    final timeStr = '${_now.hour.toString().padLeft(2, '0')}:'
        '${_now.minute.toString().padLeft(2, '0')}';
    final dateStr = '${_monthName(_now.month)} ${_now.day}, ${_now.year}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F0), Color(0xFFFFEFE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withValues(alpha: 0.25)),
            ),
            child: Icon(_deviceIcon(), color: _orange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_deviceModel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 10, color: _textMuted),
                    const SizedBox(width: 3),
                    Text('$timeStr · $dateStr',
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: _textMuted,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                        color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('LIVE',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: _green,
                        letterSpacing: 0.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _deviceIcon() {
    if (kIsWeb) return Icons.language_rounded;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return Icons.phone_android_rounded;
      case TargetPlatform.iOS:
        return Icons.phone_iphone_rounded;
      case TargetPlatform.macOS:
        return Icons.laptop_mac_rounded;
      case TargetPlatform.windows:
        return Icons.laptop_windows_rounded;
      case TargetPlatform.linux:
        return Icons.laptop_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  String _monthName(int m) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[(m - 1).clamp(0, 11)];
  }

  Widget _buildLockedBanner() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _red.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.scale(
              scale: _pulseAnim.value,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.15),
                    shape: BoxShape.circle),
                child: const Icon(Icons.lock_clock_rounded,
                    color: _red, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Account Temporarily Locked',
                      style: TextStyle(
                          fontSize: 13,
                          color: _red,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    'Too many failed attempts.\nRetry in ${_remainingLockoutText()}.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: _red.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustFooter() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _green.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Transform.scale(
              scale: 0.9 + (_pulseAnim.value * 0.1),
              child: const Icon(Icons.verified_user_rounded,
                  color: _green, size: 16),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'End-to-end encrypted · 256-bit AES · Device Integrity',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF065F46),
                    height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _securityBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _banner({
    required IconData icon,
    required String message,
    required Color color,
    String? title,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                ],
                Text(message,
                    style: TextStyle(
                        fontSize: 12,
                        color: color,
                        fontWeight: FontWeight.w600,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSide() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A1A),
            Color(0xFF0F0F10),
            Color(0xFF09090B),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeroGridPainter())),
          AnimatedBuilder(
            animation: _orbAnim,
            builder: (_, __) {
              final t = _orbAnim.value * 2 * math.pi;
              return Stack(
                children: [
                  Positioned(
                    top: -120 + math.sin(t) * 30,
                    right: -120 + math.cos(t) * 30,
                    child: Container(
                      width: 450,
                      height: 450,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          _orange.withValues(alpha: 0.35),
                          _orange.withValues(alpha: 0.0),
                        ]),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -180 + math.cos(t) * 40,
                    left: -120 + math.sin(t) * 40,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          _orangeDeep.withValues(alpha: 0.28),
                          _orangeDeep.withValues(alpha: 0.0),
                        ]),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
              top: 24,
              right: 24,
              child: _cornerAccent(topLeft: false, topRight: true)),
          Positioned(
              bottom: 24,
              left: 24,
              child: _cornerAccent(topLeft: true, topRight: false)),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _glowAnim,
                      builder: (_, __) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _orange.withValues(
                                  alpha: 0.3 + _glowAnim.value * 0.4),
                              width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _green,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: _green.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text('ONLINE',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _green,
                                    letterSpacing: 1.2)),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('v3.5.0',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                              color: _green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                      color: _green, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              const Text('PRODUCTION',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: _green,
                                      letterSpacing: 0.6)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                Center(
                  child: AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (_, __) => SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: _orange.withValues(
                                        alpha: 0.2 * _glowAnim.value),
                                    blurRadius: 80,
                                    spreadRadius: 10),
                              ],
                            ),
                          ),
                          Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _orange.withValues(
                                      alpha: 0.1 + _glowAnim.value * 0.15),
                                  width: 1),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            height: 200,
                            child: CustomPaint(
                                painter: _DashedRingPainter(
                                    color: _orange.withValues(alpha: 0.3))),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(55),
                            child: Image.asset(_heroAsset,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    _heroFallback()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _featurePill(
                          icon: Icons.fingerprint_rounded,
                          label: 'Biometric'),
                      _featurePill(
                          icon: Icons.bolt_rounded, label: 'Real-time'),
                      _featurePill(
                          icon: Icons.shield_rounded, label: 'Secured'),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                _buildMetricsRow(),
                const SizedBox(height: 24),
                _buildSystemStatusCard(),
                const Spacer(flex: 1),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _orange.withValues(alpha: 0.4)),
                  ),
                  child: const Text('⚡ SECURE ADMIN PANEL',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _orange,
                          letterSpacing: 1)),
                ),
                const SizedBox(height: 14),
                const Text('Manage your workforce\nwith confidence.',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                        letterSpacing: -0.8)),
                const SizedBox(height: 12),
                Text(
                  'Real-time attendance · Biometric verification · Payroll',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.5),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _heroStat(
                      icon: Icons.access_time_rounded,
                      value: '${_now.hour.toString().padLeft(2, '0')}:'
                          '${_now.minute.toString().padLeft(2, '0')}:'
                          '${_now.second.toString().padLeft(2, '0')}',
                      label: 'Local Time',
                    ),
                    const SizedBox(width: 32),
                    _heroStat(
                      icon: Icons.calendar_today_rounded,
                      value:
                      '${_monthName(_now.month)} ${_now.day}, ${_now.year}',
                      label: 'Today',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildActivityTicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerAccent({required bool topLeft, required bool topRight}) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _CornerAccentPainter(
            color: _orange.withValues(alpha: 0.5),
            topLeft: topLeft,
            topRight: topRight),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
            child: _metricCard(
                icon: Icons.people_alt_rounded,
                value: '248',
                label: 'Employees')),
        const SizedBox(width: 12),
        Expanded(
            child: _metricCard(
                icon: Icons.fingerprint_rounded,
                value: '1.2K',
                label: 'Today\'s Logs')),
        const SizedBox(width: 12),
        Expanded(
            child: _metricCard(
                icon: Icons.speed_rounded,
                value: '99.9%',
                label: 'Uptime')),
      ],
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: _orange),
              const Spacer(),
              Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                      color: _green, shape: BoxShape.circle)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                  height: 1.1)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  Widget _buildSystemStatusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, size: 12, color: Colors.white54),
              const SizedBox(width: 6),
              Text('SYSTEM STATUS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.5),
                      letterSpacing: 1.2)),
              const Spacer(),
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: _green, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              const Text('All systems operational',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _green)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusItem('Firebase', true),
              const SizedBox(width: 16),
              _statusItem('Database', true),
              const SizedBox(width: 16),
              _statusItem('Auth API', true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusItem(String label, bool ok) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 11, color: ok ? _green : _red),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildActivityTicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: _orange.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.5),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Text(
                _tickerMessages[_tickerIndex],
                key: ValueKey(_tickerIndex),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
                    letterSpacing: 0.2),
              ),
            ),
          ),
          Icon(Icons.trending_up_rounded,
              size: 12, color: Colors.white.withValues(alpha: 0.4)),
        ],
      ),
    );
  }

  Widget _featurePill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _orange),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _heroStat({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: _orange),
            const SizedBox(width: 4),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _orange.withValues(alpha: 0.9),
                    letterSpacing: 0.8)),
          ],
        ),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
                height: 1.1)),
      ],
    );
  }

  Widget _heroFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_orange, _orangeDeep],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(40),
      child: const Center(
        child: Icon(Icons.admin_panel_settings_rounded,
            color: Colors.white, size: 100),
      ),
    );
  }

  InputDecoration _inputDeco({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
      TextStyle(color: _textMuted.withValues(alpha: 0.5), fontSize: 13),
      prefixIcon: Icon(icon, color: _textMuted, size: 18),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _cardBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _cardBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _orange, width: 1.8)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _red, width: 1.8)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// PAINTERS
// ═══════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final Color color;
  const _GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

class _HeroGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    const spacing = 50.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_HeroGridPainter old) => false;
}

class _DashedRingPainter extends CustomPainter {
  final Color color;
  const _DashedRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const dashCount = 24;
    const dashAngle = (2 * math.pi) / dashCount;
    const gapFraction = 0.4;
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * dashAngle,
        dashAngle * (1 - gapFraction),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

class _CornerAccentPainter extends CustomPainter {
  final Color color;
  final bool topLeft;
  final bool topRight;
  const _CornerAccentPainter({
    required this.color,
    this.topLeft = false,
    this.topRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (topRight) {
      canvas.drawLine(Offset(size.width, 0),
          Offset(size.width, size.height * 0.7), paint);
      canvas.drawLine(Offset(0, 0), Offset(size.width * 0.7, 0), paint);
    }
    if (topLeft) {
      canvas.drawLine(Offset(0, size.height),
          Offset(0, size.height * 0.3), paint);
      canvas.drawLine(Offset(size.width, size.height),
          Offset(size.width * 0.3, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerAccentPainter old) =>
      old.color != color ||
          old.topLeft != topLeft ||
          old.topRight != topRight;
}