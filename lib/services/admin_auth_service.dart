// lib/services/admin_auth_service.dart
// ═══════════════════════════════════════════════════════════════════
// SECURED ADMIN AUTH SERVICE  v3.2
// Hardened: custom-claims-first, UID-based Firestore fallback,
//           audit-integrated, in-flight dedup, shorter admin
//           cache, per-account lockout, password complexity,
//           graceful error recovery, revoked-check added.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class AdminAuthService {
  AdminAuthService._();
  static final instance = AdminAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const int _maxSignInAttempts = 5;
  static const Duration _signInWindow = Duration(seconds: 60);
  static const int _maxAccountFailures = 5;
  static const Duration _accountLockoutWindow = Duration(minutes: 15);
  static const Duration _cacheTtl = Duration(minutes: 2);
  static const int _minPasswordLen = 8;
  static const int _maxPasswordLen = 128;

  final List<DateTime> _signInAttempts = [];
  final Map<String, _AccountFailures> _accountFailures = {};
  final Map<String, _AdminCheck> _adminCache = {};
  final Map<String, Future<bool>> _inFlightAdmin = {};

  // ═══════════════════════════════════════════════════════════════
  // 🛡️ ADMIN CHECK (Custom Claims -> Firestore Fallback)
  // ═══════════════════════════════════════════════════════════════
  Future<bool> isAdmin(User? user) async {
    if (user == null) return false;

    try {
      final token = await _getTokenWithThrottle(user);
      if (token != null) {
        final claims = token.claims ?? const {};
        if (_claimsSayAdmin(claims)) {
          _log('✅ [AdminAuth] Admin via custom claims');
          return true;
        }
      }
    } catch (e) {
      _log('⚠️ [AdminAuth] Token refresh failed: $e');
    }

    return _verifyAdminFromFirestore(user.uid);
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 SIGN IN
  // ═══════════════════════════════════════════════════════════════
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    if (!_allowSignInAttempt()) {
      await _audit(action: 'admin_sign_in_rate_limited', outcome: 'rate_limited');
      return 'Too many attempts. Please try again in a minute.';
    }

    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return 'Email and password are required.';
    }
    if (!_isValidEmail(normalizedEmail)) {
      return 'Invalid email format.';
    }

    final lockoutErr = _checkAccountLockout(normalizedEmail);
    if (lockoutErr != null) {
      await _audit(action: 'admin_sign_in_locked', outcome: 'locked', email: normalizedEmail);
      return lockoutErr;
    }

    if (password.length < _minPasswordLen || password.length > _maxPasswordLen) {
      _recordAccountFailure(normalizedEmail);
      return 'Invalid credentials.';
    }

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        _recordAccountFailure(normalizedEmail);
        await _audit(action: 'admin_sign_in_failed', outcome: 'no_user', email: normalizedEmail);
        return 'Sign-in failed. Please try again.';
      }

      final adminOk = await isAdmin(user);
      if (!adminOk) {
        try { await _auth.signOut(); } catch (_) {}
        _recordAccountFailure(normalizedEmail);
        await _audit(action: 'admin_sign_in_denied', outcome: 'not_admin', email: normalizedEmail, adminUid: user.uid);
        return 'Access denied. This account is not registered as admin.';
      }

      _signInAttempts.clear();
      _accountFailures.remove(normalizedEmail);

      await _audit(action: 'admin_sign_in', outcome: 'success', email: normalizedEmail, adminUid: user.uid);
      return null;
    } on FirebaseAuthException catch (e) {
      _recordAccountFailure(normalizedEmail);
      await _audit(action: 'admin_sign_in_failed', outcome: e.code, email: normalizedEmail);
      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Invalid email or password.';
        case 'invalid-email':
          return 'Invalid email format.';
        case 'user-disabled':
          return 'This account has been disabled. Contact IT support.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'configuration-not-found':
          return 'Email/Password sign-in is not enabled.';
        case 'network-request-failed':
          return 'Network error. Check your connection.';
        default:
          return 'Login failed. Please try again.';
      }
    } catch (e) {
      _recordAccountFailure(normalizedEmail);
      return 'Login failed. Please try again.';
    }
  }

  Future<User?> getCurrentAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final adminOk = await isAdmin(user);
      if (!adminOk) {
        try { await _auth.signOut(); } catch (_) {}
        return null;
      }
      return user;
    } catch (e) {
      return user;
    }
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    _adminCache.clear();
    _inFlightAdmin.clear();
    try { await _auth.signOut(); } catch (_) {}
    _signInAttempts.clear();
    await _audit(action: 'admin_sign_out', outcome: 'success', adminUid: uid);
  }

  bool get isSignedIn => _auth.currentUser != null;
  String? get currentEmail => _auth.currentUser?.email;
  String? get currentUid => _auth.currentUser?.uid;

  Future<bool> refreshAdminStatus() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      _adminCache.remove(uid);
      _inFlightAdmin.remove(uid);
    }
    return isAdmin(_auth.currentUser);
  }

  Future<IdTokenResult?> _getTokenWithThrottle(User user) async {
    try { return await user.getIdTokenResult(true); } catch (_) { return null; }
  }

  bool _claimsSayAdmin(Map<dynamic, dynamic> claims) {
    if (claims['admin'] == true) return true;
    if (claims['isAdmin'] == true) return true;
    if (claims['role']?.toString().toLowerCase() == 'admin') return true;
    if (claims['roles'] is List &&
        (claims['roles'] as List).map((e) => e.toString().toLowerCase()).contains('admin')) {
      return true;
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🛡️ FIRESTORE ADMIN CHECK (UID-Based)
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _verifyAdminFromFirestore(String uid) async {
    final cached = _adminCache[uid];
    if (cached != null && !cached.isExpired) return cached.isAdmin;

    final pending = _inFlightAdmin[uid];
    if (pending != null) return pending;

    final future = _fetchAdminFromFirestore(uid);
    _inFlightAdmin[uid] = future;
    try { return await future; } finally { _inFlightAdmin.remove(uid); }
  }

  Future<bool> _fetchAdminFromFirestore(String uid) async {
    bool isAdmin = false;
    try {
      // 1. Check admins/{uid} collection (Tugma sa screenshot mo)
      final byUid = await _fs.collection('admins').doc(uid).get();
      if (byUid.exists) {
        isAdmin = _isActive(byUid.data());
        _log('🔍 [AdminAuth] Found in admins/$uid. isActive=$isAdmin');
      } else {
        // 2. Fallback: Check users/{uid} kung may role na admin
        final userDoc = await _fs.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final data = userDoc.data() ?? {};
          final role = (data['role'] ?? '').toString().toLowerCase();
          final isActive = data['isActive'] ?? data['active'] ?? true;
          final revoked = data['revoked'] == true;
          isAdmin = role == 'admin' && isActive == true && !revoked;
          _log('🔍 [AdminAuth] Found in users/$uid. role=$role, isAdmin=$isAdmin');
        } else {
          _log('❌ [AdminAuth] UID $uid not found in admins or users collection.');
        }
      }
    } catch (e) {
      // 🛠️ IDAGDAG ITO PARA MAKITA ANG ERROR SA CONSOLE
      _log('❌ [AdminAuth] Firestore admin fetch error: $e');
      isAdmin = false;
    }
    _adminCache[uid] = _AdminCheck(isAdmin, DateTime.now());
    return isAdmin;
  }

  bool _isActive(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data['isActive'] != false &&
        data['disabled'] != true &&
        data['revoked'] != true;
  }

  // ═══════════════════════════════════════════════════════════════
  // ⏱️ RATE LIMITING & LOCKOUT
  // ═══════════════════════════════════════════════════════════════
  bool _allowSignInAttempt() {
    final now = DateTime.now();
    _signInAttempts.removeWhere((t) => now.difference(t) > _signInWindow);
    if (_signInAttempts.length >= _maxSignInAttempts) return false;
    _signInAttempts.add(now);
    return true;
  }

  String? _checkAccountLockout(String email) {
    final entry = _accountFailures[email];
    if (entry == null) return null;
    final now = DateTime.now();
    if (now.difference(entry.lastFailureAt) > _accountLockoutWindow) {
      _accountFailures.remove(email);
      return null;
    }
    if (entry.count >= _maxAccountFailures) {
      final remaining = _accountLockoutWindow - now.difference(entry.lastFailureAt);
      final mins = remaining.inMinutes + 1;
      return 'Account temporarily locked. Try again in $mins minute(s).';
    }
    return null;
  }

  void _recordAccountFailure(String email) {
    final entry = _accountFailures[email] ?? _AccountFailures(count: 0, lastFailureAt: DateTime.now());
    entry.count += 1;
    entry.lastFailureAt = DateTime.now();
    _accountFailures[email] = entry;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🧹 UTILITIES
  // ═══════════════════════════════════════════════════════════════
  static String _normalizeEmail(String raw) {
    try { return _nfc(raw.trim().toLowerCase()); } catch (_) { return raw.trim().toLowerCase(); }
  }

  static String _nfc(String s) {
    return s.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
  }

  static bool _isValidEmail(String email) {
    if (email.length > 254) return false;
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);
  }

  // ═══════════════════════════════════════════════════════════════
  // 📝 AUDIT LOGGING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _audit({
    required String action, required String outcome, String? email, String? adminUid,
  }) async {
    try {
      final uid = adminUid ?? _auth.currentUser?.uid ?? 'anonymous';
      final metadata = <String, dynamic>{'outcome': outcome, 'userAgent': 'flutter_admin_app'};
      if (email != null && email.isNotEmpty) {
        metadata['email_hash'] = _hashEmail(email);
      }
      await _fs.collection('security_events').add({
        'type': 'auth_event',
        'action': action,
        'targetId': uid,
        'targetType': 'session',
        'actorUid': uid,
        'metadata': metadata,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Swallowed upang hindi makagambala sa login flow
    }
  }

  static String _hashEmail(String email) {
    var h = 5381;
    for (final code in email.codeUnits) {
      h = ((h << 5) + h + code) & 0x7FFFFFFF;
    }
    return h.toRadixString(16);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}

class _AdminCheck {
  final bool isAdmin;
  final DateTime fetchedAt;
  _AdminCheck(this.isAdmin, this.fetchedAt);
  bool get isExpired => DateTime.now().difference(fetchedAt) > AdminAuthService._cacheTtl;
}

class _AccountFailures {
  int count;
  DateTime lastFailureAt;
  _AccountFailures({required this.count, required this.lastFailureAt});
}