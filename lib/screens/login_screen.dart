// lib/screens/login_screen.dart
//
// Authenticates employees by:
//   • NFC tap  → matches tag.data identifier against Firestore `nfcTagId` field
//   • 4-digit PIN → matches against Firestore `pin` field
//
// On successful auth → goes to FingerprintScreen (Step 2) before MainScreen.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/security_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../models/employee.dart';
import 'fingerprint_screen.dart'; // ← Step 2 screen
import 'landing_screen.dart';

// Login step enum
enum _LoginStep { selectMethod, pinEntry, nfcWait }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {

  String       _pinInput     = '';
  bool         _isLoading    = false;
  bool         _nfcAvailable = false;
  String?      _errorMessage;
  _LoginStep   _step         = _LoginStep.selectMethod;

  late AnimationController _shakeController;
  late Animation<double>   _shakeAnim;
  late AnimationController _fadeController;
  late Animation<double>   _fadeAnim;
  late AnimationController _slideController;
  late Animation<Offset>   _slideAnim;
  late AnimationController _nfcPulseController;
  late Animation<double>   _nfcPulseAnim;

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color _bg         = Color(0xFF0A0A0A);
  static const Color _card       = Color(0xFF1A1A1A);
  static const Color _cardBorder = Color(0xFF2A2A2A);
  static const Color _orange     = Color(0xFFFF8C00);
  static const Color _orangeLight= Color(0xFFFFAA33);
  static const Color _white      = Color(0xFFFFFFFF);
  static const Color _white70    = Color(0xB3FFFFFF);
  static const Color _white40    = Color(0x66FFFFFF);
  static const Color _white15    = Color(0x26FFFFFF);
  static const Color _white08    = Color(0x14FFFFFF);
  static const Color _success    = Color(0xFF00E5A0);
  static const Color _error      = Color(0xFFFF4D6D);

  static const List<String> _notFoundCodes = [
    'user-not-found',
    'invalid-credential',
    'invalid-login-credentials',
    'INVALID_LOGIN_CREDENTIALS',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _nfcPulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2));

    _shakeAnim = Tween<double>(begin: 0, end: 10)
        .animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
    _nfcPulseAnim = Tween<double>(begin: 0.9, end: 1.1)
        .animate(CurvedAnimation(parent: _nfcPulseController, curve: Curves.easeInOut));

    _nfcPulseController.repeat(reverse: true);
    _fadeController.forward();
    _slideController.forward();

    _checkCapabilities();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _nfcPulseController.dispose();
    if (!kIsWeb) {
      try { NfcManager.instance.stopSession(); } catch (_) {}
    }
    super.dispose();
  }

  // ── NFC ────────────────────────────────────────────────────────────────────
  Future<void> _checkCapabilities() async {
    if (kIsWeb) return;
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (e) {
      debugPrint('NFC check error: $e');
    }
  }

  Future<void> _startNfcSession() async {
    if (kIsWeb) return;
    try {
      await NfcManager.instance.stopSession();
      NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          if (_isLoading) return;
          final serial = _extractTagId(tag);
          if (serial == null) { _setError('Could not read keyfob ID.'); return; }

          if (mounted) setState(() { _isLoading = true; _errorMessage = null; });

          try {
            final employee = await _findEmployeeByNfc(serial);
            if (employee != null) {
              await NfcManager.instance.stopSession();
              await _openSession(employee);
            } else {
              await NfcManager.instance.stopSession();
              _setError('Keyfob not registered. Contact your Admin.');
            }
          } catch (e) {
            _setError('NFC login error: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('NFC session error: $e');
    }
  }

  Future<Employee?> _findEmployeeByNfc(String serial) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('nfcTagId', isEqualTo: serial)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return _docToEmployee(snap.docs.first);
    } catch (e) {
      debugPrint('_findEmployeeByNfc error: $e');
      return null;
    }
  }

  String? _extractTagId(NfcTag tag) {
    try {
      final tagMap = tag.data as Map<String, dynamic>;
      List<int>? tryKey(String key) {
        final tech = tagMap[key] as Map<dynamic, dynamic>?;
        if (tech == null) return null;
        final raw = tech['identifier'];
        if (raw is List) return raw.cast<int>();
        return null;
      }
      final id = tryKey('nfca') ?? tryKey('nfcb') ?? tryKey('nfcf') ??
          tryKey('nfcv') ?? tryKey('isodep') ??
          tryKey('mifare-classic') ?? tryKey('mifare-ultralight');
      if (id == null || id.isEmpty) return null;
      return id.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
    } catch (_) {
      return null;
    }
  }

  // ── PIN login ──────────────────────────────────────────────────────────────
  Future<void> _loginWithPin() async {
    if (_pinInput.length < 4) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      Employee? employee;
      employee = await _findEmployeeByPin(_pinInput);

      if (employee == null && !kIsWeb) {
        final localEmployees = await DatabaseService.instance.getAllEmployees();
        for (final emp in localEmployees) {
          final valid = await SecurityService.instance.verifyPin(emp.id, _pinInput);
          if (valid) { employee = emp; break; }
        }
      }

      if (employee == null) throw 'Invalid PIN. Please try again.';
      await _openSession(employee);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('Invalid PIN')
              ? 'Invalid PIN. Please try again.'
              : 'Login error: ${e.toString()}';
          _isLoading = false;
          _pinInput  = '';
        });
        _shakeController.forward(from: 0);
      }
    }
  }

  Future<Employee?> _findEmployeeByPin(String pin) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: pin)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final employee = _docToEmployee(snap.docs.first);
      if (!kIsWeb) {
        try { await DatabaseService.instance.insertEmployee(employee); } catch (_) {}
      }
      return employee;
    } catch (e) {
      debugPrint('_findEmployeeByPin error: $e');
      return null;
    }
  }

  Employee _docToEmployee(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data      = doc.data();
    final firstName = data['firstName'] ?? '';
    final lastName  = data['lastName']  ?? '';
    final fullName  = data['name']      ?? '$firstName $lastName'.trim();
    return Employee.fromMap({
      'id'               : doc.id,
      'employee_id'      : data['employeeId'] ?? doc.id,
      'first_name'       : firstName,
      'last_name'        : lastName,
      'full_name'        : fullName,
      'email'            : data['email']      ?? '',
      'department'       : data['role']       ?? data['department'] ?? '',
      'position'         : data['role']       ?? data['position']   ?? '',
      'phone'            : data['phone'],
      'photo_path'       : data['photoPath'],
      'face_embedding'   : data['faceEmbedding'],
      'fingerprint_hash' : data['fingerprintHash'],
      'pin_hash'         : null,
      'pin_salt'         : null,
      'nfc_tag_id'       : data['nfcTagId'],
      'is_active'        : data['status'] == 'active' ? 1 : 0,
      'created_at'       : (data['createdAt'] as Timestamp?)?.toDate().toIso8601String()
          ?? DateTime.now().toIso8601String(),
      'updated_at'       : (data['updatedAt'] as Timestamp?)?.toDate().toIso8601String()
          ?? DateTime.now().toIso8601String(),
    });
  }

  Future<void> _signIntoFirebaseAuth(Employee employee) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees').doc(employee.id).get();
      final data     = snap.data();
      final email    = (data?['email']    as String? ?? '').trim();
      final password = (data?['password'] as String? ?? '').trim();
      if (email.isEmpty || password.isEmpty) {
        debugPrint('Firebase Auth skipped — no email/password for ${employee.fullName}.');
        return;
      }
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email, password: password);
        debugPrint('Firebase Auth ✓ signed in: $email');
      } catch (signInErr) {
        final code = signInErr is FirebaseAuthException ? signInErr.code : '';
        if (_notFoundCodes.contains(code)) {
          try {
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
                email: email, password: password);
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            if (uid.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('employees').doc(employee.id)
                  .update({'authUid': uid});
            }
          } catch (createErr) {
            debugPrint('Firebase Auth create error: $createErr');
          }
        }
      }
    } catch (e) {
      debugPrint('Firebase Auth outer error: $e');
    }
  }

  // ── Open session → navigate to FingerprintScreen (Step 2) ─────────────────
  Future<void> _openSession(Employee employee) async {
    try {
      await SecurityService.instance.createSession(employee.id);
      if (!kIsWeb) LocationTrackingService.instance.startTracking(employee.id);
      await _signIntoFirebaseAuth(employee);

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type'          : 'login',
          'employeeId'    : employee.id,
          'employee_name' : employee.fullName,
          'email'         : employee.email,
          'role'          : employee.position,
          'timestamp'     : FieldValue.serverTimestamp(),
          'device'        : kIsWeb ? 'Web Browser' : 'Mobile App',
        });
      } catch (logErr) {
        debugPrint('Activity log error: $logErr');
      }

      if (!mounted) return;

      // ── Always go to fingerprint screen after PIN or NFC ──────────────────
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FingerprintScreen(employee: employee),
        ),
            (route) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() { _errorMessage = 'Session error: $e'; _isLoading = false; });
      }
    }
  }

  void _onPinKey(String key) {
    if (_isLoading) return;
    setState(() => _errorMessage = null);
    if (key == 'del') {
      if (_pinInput.isNotEmpty) {
        setState(() => _pinInput = _pinInput.substring(0, _pinInput.length - 1));
      }
    } else if (_pinInput.length < 4) {
      setState(() => _pinInput += key);
      if (_pinInput.length == 4) {
        Future.delayed(const Duration(milliseconds: 250), _loginWithPin);
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() { _errorMessage = msg; _isLoading = false; _pinInput = ''; });
      _shakeController.forward(from: 0);
    }
  }

  void _goToStep(_LoginStep step) {
    _slideController.reset();
    setState(() {
      _step         = step;
      _errorMessage = null;
      _pinInput     = '';
    });
    _slideController.forward();
    if (step == _LoginStep.nfcWait) _startNfcSession();
  }

  void _goBack() {
    if (_step == _LoginStep.selectMethod) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LandingScreen()));
    } else {
      if (_step == _LoginStep.nfcWait && !kIsWeb) {
        try { NfcManager.instance.stopSession(); } catch (_) {}
      }
      _goToStep(_LoginStep.selectMethod);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _goBack(); },
      child: Scaffold(
        backgroundColor: _bg,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            _buildOrangeHeader(),
            Expanded(
              child: SlideTransition(
                position: _slideAnim,
                child: _buildStepContent(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildOrangeHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6B00), Color(0xFFFF9500), Color(0xFFFFAA00)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: _goBack,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left_rounded, color: _white, size: 22),
                const SizedBox(width: 4),
                Text('Back', style: TextStyle(
                    color: _white.withOpacity(0.9),
                    fontSize: 15, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('Auth & Clock In', style: TextStyle(
                color: _white, fontSize: 32,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 6),
            Text('Select your initial verification method',
                style: TextStyle(
                    color: _white.withOpacity(0.85),
                    fontSize: 15, fontWeight: FontWeight.w400)),
          ]),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _LoginStep.selectMethod: return _buildSelectMethodStep();
      case _LoginStep.pinEntry:     return _buildPinEntryStep();
      case _LoginStep.nfcWait:      return _buildNfcWaitStep();
    }
  }

  Widget _buildSelectMethodStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Initial Login',
          child: Row(children: [
            Expanded(child: _MethodButton(
              icon: Icons.contactless_rounded,
              label: 'Key Fob',
              enabled: !kIsWeb && _nfcAvailable,
              onTap: () => _goToStep(_LoginStep.nfcWait),
            )),
            const SizedBox(width: 14),
            Expanded(child: _MethodButton(
              icon: Icons.key_rounded,
              label: 'Use PIN',
              onTap: () => _goToStep(_LoginStep.pinEntry),
            )),
          ]),
        ),
        if (kIsWeb || !_nfcAvailable) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _white08,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _white15),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: _white40, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(
                kIsWeb
                    ? 'NFC is not available on web. Use PIN to sign in.'
                    : 'NFC not available on this device. Use PIN to sign in.',
                style: TextStyle(color: _white40, fontSize: 12),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildPinEntryStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Enter Your PIN',
          child: Column(children: [
            const SizedBox(height: 8),
            _buildPinDots(),
            const SizedBox(height: 24),
            _buildPinPad(),
            const SizedBox(height: 16),
            _buildFeedback(),
          ]),
        ),
        const SizedBox(height: 16),
        _buildFooterNote(),
      ]),
    );
  }

  Widget _buildNfcWaitStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),
        _buildStepCard(
          stepLabel: 'Step 1: Tap Key Fob',
          child: Column(children: [
            const SizedBox(height: 24),
            AnimatedBuilder(
              animation: _nfcPulseAnim,
              builder: (_, __) => Transform.scale(
                scale: _isLoading ? 1.0 : _nfcPulseAnim.value,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _orange.withOpacity(0.12),
                    border: Border.all(color: _orange.withOpacity(0.5), width: 2),
                  ),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(
                      color: _orange, strokeWidth: 2.5))
                      : const Icon(Icons.contactless_rounded,
                      color: _orange, size: 50),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isLoading ? 'Reading keyfob…' : 'Hold your keyfob\nclose to the device',
              textAlign: TextAlign.center,
              style: TextStyle(color: _white70, fontSize: 15,
                  height: 1.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) _buildFeedback(),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStepCard({required String stepLabel, required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder, width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Text(stepLabel,
            style: TextStyle(color: _white70, fontSize: 13,
                fontWeight: FontWeight.w500, letterSpacing: 0.3))),
        const SizedBox(height: 20),
        child,
      ]),
    );
  }

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_shakeAnim.value *
            ((_shakeController.value * 10).round().isEven ? 1 : -1), 0),
        child: child,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled   = i < _pinInput.length;
          final hasError = _errorMessage != null;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError
                  ? _error.withOpacity(filled ? 1 : 0)
                  : filled ? _orange : Colors.transparent,
              border: Border.all(
                color: hasError ? _error.withOpacity(0.7)
                    : filled ? _orange : _white40,
                width: 2,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPinPad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['',  '0', 'del'],
    ];
    return Column(
      children: List.generate(4, (rowIdx) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: List.generate(3, (colIdx) {
            final key = rows[rowIdx][colIdx];
            if (key.isEmpty) return const Expanded(child: SizedBox());
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    left: colIdx > 0 ? 10 : 0, right: colIdx < 2 ? 10 : 0),
                child: _PinKey(label: key, onTap: () => _onPinKey(key)),
              ),
            );
          }),
        ),
      )),
    );
  }

  Widget _buildFeedback() {
    if (_isLoading) {
      return const SizedBox(height: 36,
          child: Center(child: CircularProgressIndicator(
              color: _orange, strokeWidth: 2.5)));
    }
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _error.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _error.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: _error, size: 16),
          const SizedBox(width: 8),
          Flexible(child: Text(_errorMessage!,
              style: TextStyle(color: _error, fontSize: 13,
                  fontWeight: FontWeight.w600))),
        ]),
      );
    }
    return const SizedBox(height: 8);
  }

  Widget _buildFooterNote() => Text(
    'Account creation is restricted to Admin.',
    textAlign: TextAlign.center,
    style: TextStyle(color: _white40, fontSize: 11),
  );
}

// ── METHOD BUTTON ──────────────────────────────────────────────────────────────
class _MethodButton extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final bool         enabled;

  const _MethodButton({
    required this.icon, required this.label,
    required this.onTap, this.enabled = true,
  });

  @override
  State<_MethodButton> createState() => _MethodButtonState();
}

class _MethodButtonState extends State<_MethodButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

  static const Color _orange  = Color(0xFFFF8C00);
  static const Color _white15 = Color(0x26FFFFFF);

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:   widget.enabled ? (_) => _pressCtrl.forward() : null,
      onTapUp:     widget.enabled ? (_) { _pressCtrl.reverse(); widget.onTap(); } : null,
      onTapCancel: widget.enabled ? () => _pressCtrl.reverse() : null,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.45,
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                gradient: widget.enabled
                    ? const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF2A1800), Color(0xFF1A1200)],
                ) : null,
                color: widget.enabled ? null : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.enabled ? _orange.withOpacity(0.45) : _white15,
                  width: 1.5,
                ),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: widget.enabled ? _orange.withOpacity(0.15) : _white15,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(widget.icon,
                      color: widget.enabled ? _orange : const Color(0x66FFFFFF),
                      size: 28),
                ),
                const SizedBox(height: 14),
                Text(widget.label, style: TextStyle(
                    color: widget.enabled
                        ? const Color(0xFFFFFFFF) : const Color(0x66FFFFFF),
                    fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── PIN KEY BUTTON ─────────────────────────────────────────────────────────────
class _PinKey extends StatefulWidget {
  final String       label;
  final VoidCallback onTap;
  const _PinKey({required this.label, required this.onTap});
  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scaleAnim;

  static const Color _orange  = Color(0xFFFF8C00);
  static const Color _white   = Color(0xFFFFFFFF);
  static const Color _white15 = Color(0x26FFFFFF);
  static const Color _white08 = Color(0x14FFFFFF);

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.93)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDel = widget.label == 'del';
    return GestureDetector(
      onTapDown:   (_) => _pressCtrl.forward(),
      onTapUp:     (_) { _pressCtrl.reverse(); widget.onTap(); },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: isDel ? _white08 : _white15,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDel ? const Color(0x26FFFFFF) : _orange.withOpacity(0.2),
            ),
          ),
          child: Center(
            child: isDel
                ? const Icon(Icons.backspace_outlined,
                color: Color(0xB3FFFFFF), size: 22)
                : Text(widget.label, style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: _white)),
          ),
        ),
      ),
    );
  }
}