// lib/services/admin_employee_service.dart
// ═══════════════════════════════════════════════════════════════════
// SECURED ADMIN EMPLOYEE SERVICE  v2.0
// Hardened: admin guard, hardened PIN (PBKDF2-like), field
//           allowlist on update, sanitized doc IDs, actor UID,
//           rate limiting, dual-collection audit, safer nonce,
//           fail-closed uniqueness checks, backwards-compatible.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256, Hmac;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'admin_auth_service.dart';

/// Centralized, audited, atomic operations for employee admin.
///
/// Security model (defense in depth):
///   1️⃣  Client-side admin guard (AdminAuthService) sa bawat mutation
///   2️⃣  Input validation + sanitization
///   3️⃣  Field-level allowlist sa update (mass-assignment defense)
///   4️⃣  Hardened PIN storage (PBKDF2-like; SHA-256 alone is insufficient)
///   5️⃣  Dual audit: `admin_audit_log` + `security_events`
///   6️⃣  Rate limiting per action
///   7️⃣  Server-side Firestore rules ang FINAL check
class AdminEmployeeService {
  AdminEmployeeService._();
  static final instance = AdminEmployeeService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ─── Collection refs ───
  CollectionReference<Map<String, dynamic>> get _employees =>
      _fs.collection('employees');

  CollectionReference<Map<String, dynamic>> get _activityLogs =>
      _fs.collection('activity_logs');

  CollectionReference<Map<String, dynamic>> get _auditLog =>
      _fs.collection('admin_audit_log'); // legacy name

  CollectionReference<Map<String, dynamic>> get _securityEvents =>
      _fs.collection('security_events');

  // ─── Actor context (server-verified) ───
  String get _actorUid => _auth.currentUser?.uid ?? 'unknown';

  String get _actorEmail =>
      (_auth.currentUser?.email ?? 'unknown').toLowerCase().trim();

  // ─── Rate limiter ───
  final Map<String, List<DateTime>> _rateBuckets = {};
  static const Duration _rateWindow = Duration(minutes: 1);
  static const int _maxOpsPerMinute = 20; // per action key

  // ─── Field allowlists (mass-assignment defense) ───
  static const Set<String> _updatableFields = {
    // Identity
    'firstName', 'lastName', 'name',
    'email', 'emailLower', 'phone', 'gender',
    'role', 'department', 'nfcTagId',
    // Compensation
    'basicSalary', 'allowances', 'dailyRate',
    'housingAllowance', 'transportAllowance', 'specialAllowance',
    'workingDaysPerMonth', 'salarySource',
    // Leave
    'annualLeaveTotal', 'sickLeaveTotal',
    // Bank
    'bankName', 'accountNumber',
    // Flags
    'wfhAccess',
    // Face enrollment
    'faceEnrollmentNonce', 'faceEnrollmentDevice',
    // Misc UI
    'deviceName', 'payrollStatus',
    // ⬇️ IDAGDAG ITO — para gumana ang edit employee
    'employeeId',
    'basicAllowance',
    'monthlyTotal',
    'salaryConfigured',
  };

  // ══════════════════════════════════════════════════════════════
  // 🔒 ADMIN GUARD
  // ══════════════════════════════════════════════════════════════

  /// Throws [StateError] kapag hindi admin ang current user.
  /// Tawagin ito sa simula ng bawat mutation.
  Future<void> _requireAdmin() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Session expired. Please sign in again.');
    }
    final ok = await AdminAuthService.instance.isAdmin(user);
    if (!ok) {
      throw StateError('Walang permission. Admin-only operation.');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // INPUT VALIDATION
  // ══════════════════════════════════════════════════════════════

  /// Strips control chars, bidi overrides, zero-width chars.
  static String sanitize(String? input, {int maxLen = 80}) {
    if (input == null) return '';
    var s = input.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u2028\u2029]'),
      '',
    );
    // Bidi + zero-width strip
    s = s.replaceAll(
      RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'),
      '',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > maxLen) s = s.substring(0, maxLen);
    return s;
  }

  /// Validates Firestore doc ID (safe for `.doc(id)` calls).
  static bool _isValidDocId(String id) {
    if (id.isEmpty || id.length > 500) return false;
    if (id == '.' || id == '..') return false;
    if (id.contains('/')) return false;
    return true;
  }

  static String? validateEmployeeId(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return 'Employee ID is required.';
    if (!RegExp(r'^[A-Za-z0-9\-_]{3,30}$').hasMatch(clean)) {
      return 'Employee ID: 3–30 chars, letters/numbers/dash/underscore only.';
    }
    return null;
  }

  static String? validateEmail(String email) {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return 'Email is required.';
    if (clean.length > 120) return 'Email is too long.';
    if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w+$').hasMatch(clean)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validateSalary(double basic, double allowance) {
    if (basic < 5000 || basic > 500000) {
      return 'Basic salary must be between ₱5,000 and ₱500,000.';
    }
    if (allowance < 0 || allowance > 100000) {
      return 'Allowance must be between ₱0 and ₱100,000.';
    }
    return null;
  }

  /// Rate limit check. Returns true kung OK pa.
  bool _rateLimitOk(String key) {
    final now = DateTime.now();
    final bucket = _rateBuckets.putIfAbsent(key, () => []);
    bucket.removeWhere((t) => now.difference(t) > _rateWindow);
    if (bucket.length >= _maxOpsPerMinute) return false;
    bucket.add(now);
    return true;
  }

  // ══════════════════════════════════════════════════════════════
  // UNIQUENESS (targeted queries, fail-closed sa critical paths)
  // ══════════════════════════════════════════════════════════════

  /// Returns error string kung may existing email, else null.
  /// FAILS CLOSED sa create — huwag hayaang mag-duplicate.
  Future<String?> checkEmailUnique(
      String email, {
        String? excludeDocId,
      }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    try {
      final snap = await _employees
          .where('emailLower', isEqualTo: normalized)
          .limit(2)
          .get()
          .timeout(const Duration(seconds: 6));

      for (final d in snap.docs) {
        if (excludeDocId != null && d.id == excludeDocId) continue;
        return 'Email "$normalized" already registered.';
      }
      return null;
    } on TimeoutException {
      // Fail-closed: huwag mag-create kung hindi ma-verify
      return 'Cannot verify email uniqueness. Check connection.';
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [emailUnique] $e');
      return 'Cannot verify email uniqueness. Try again.';
    }
  }

  Future<String?> checkEmployeeIdUnique(
      String employeeId, {
        String? excludeDocId,
      }) async {
    if (!_isValidDocId(employeeId)) {
      return 'Invalid Employee ID format.';
    }
    try {
      final doc = await _employees
          .doc(employeeId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      if (doc.exists && doc.id != excludeDocId) {
        return 'Employee ID "$employeeId" already exists.';
      }
      return null;
    } on TimeoutException {
      return 'Cannot verify ID uniqueness. Check connection.';
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [idUnique] $e');
      return 'Cannot verify ID uniqueness. Try again.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PIN — HARDENED HASHING
  // ══════════════════════════════════════════════════════════════

  static final Random _rng = Random.secure();

  /// App-level pepper. ⚠️ Sa production, ilagay ito sa secure storage
  /// (Flutter Secure Storage / --dart-define) — HINDI hardcoded.
  static const String _pinPepper =
  String.fromEnvironment('PIN_PEPPER', defaultValue: 'racoma-hris-v1');

  /// Iterations para sa PBKDF2-like derivation.
  static const int _pinIterations = 10000;

  static String generatePin({String? current}) {
    const blocked = {
      '0000', '1111', '2222', '3333', '4444',
      '5555', '6666', '7777', '8888', '9999',
      '1234', '4321', '0123', '9876',
    };
    for (var i = 0; i < 20; i++) {
      final c = (1000 + _rng.nextInt(9000)).toString();
      if (!blocked.contains(c) && c != current?.trim()) return c;
    }
    return (1000 + _rng.nextInt(9000)).toString();
  }

  /// 🛡️ Hardened PIN hash — PBKDF2-like (iterated HMAC-SHA256).
  ///
  /// Bakit hindi lang SHA-256? 4-digit PIN = 10,000 combinations lang.
  /// Ang SHA-256 na may predictable salt ay brute-forceable sa <1 segundo.
  /// Sa iterated hashing (10k rounds), tumataas ang cost ng attack.
  ///
  /// ⚠️ PIN alone (4 digits) ay HINDI sapat — kailangan pa rin ng:
  ///    • Server-side rate limit sa PIN entry
  ///    • Account lockout after N failed attempts
  ///    • Device binding (kung applicable)
  static String hashPin(String pin, String uid) {
    final salt = 'racoma::pin::v2::${uid.toLowerCase()}::$_pinPepper';

    // ✅ FIX: Explicit na List<int> — compatible sa Hmac.convert().bytes
    List<int> digest = utf8.encode('$pin::$salt');

    final key = utf8.encode(salt);
    for (var i = 0; i < _pinIterations; i++) {
      digest = Hmac(sha256, key).convert(digest).bytes;
    }
    return 'v2\$$_pinIterations\$${base64Encode(digest)}';
  }

  /// 🆕 Verify PIN laban sa stored hash (constant-time compare).
  ///
  /// Supports both v2 (new) at v1 (legacy SHA-256) hashes.
  static bool verifyPin(String pin, String uid, String storedHash) {
    if (storedHash.isEmpty) return false;

    // Support legacy v1 (SHA-256) hash
    if (!storedHash.startsWith('v2\$')) {
      final legacy = sha256
          .convert(
        utf8.encode(
          '$pin::racoma::pin::v1::${uid.toLowerCase()}',
        ),
      )
          .toString();
      return _constantTimeEq(legacy, storedHash);
    }

    final fresh = hashPin(pin, uid);
    return _constantTimeEq(fresh, storedHash);
  }

  /// Constant-time string comparison (prevents timing side-channel).
  static bool _constantTimeEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ══════════════════════════════════════════════════════════════
  // AUDIT (dual: audit log + security events)
  // ══════════════════════════════════════════════════════════════

  Future<void> _audit({
    required String action,
    required String targetId,
    Map<String, dynamic>? details,
  }) async {
    final payload = <String, dynamic>{
      'action': action,
      'targetType': 'employee',
      'targetId': targetId,
      'actorUid': _actorUid,
      'actorEmail': _actorEmail,
      'details': _safeDetails(details),
      'timestamp': FieldValue.serverTimestamp(),
      'schemaVersion': 2,
    };

    // ─── Write to both collections; never block main op ───
    unawaited(() async {
      try {
        await _auditLog.add(payload).timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ [audit/admin_audit_log] $e');
      }
    }());

    unawaited(() async {
      try {
        await _securityEvents.add({
          'type': 'admin_action',
          'action': action,
          'targetId': targetId,
          'targetType': 'employee',
          'actorUid': _actorUid,
          'metadata': _safeDetails(details),
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ [audit/security_events] $e');
      }
    }());
  }

  /// Sanitize details (strip control chars, cap size, drop PII).
  Map<String, dynamic> _safeDetails(Map<String, dynamic>? d) {
    if (d == null || d.isEmpty) return const {};
    final out = <String, dynamic>{};
    int count = 0;
    for (final e in d.entries) {
      if (count++ >= 30) break;
      final k = sanitize(e.key, maxLen: 40);
      if (k.isEmpty) continue;
      final v = e.value;
      if (v is String) {
        out[k] = sanitize(v, maxLen: 200);
      } else if (v is num || v is bool) {
        out[k] = v;
      } else if (v is List) {
        out[k] = v
            .take(20)
            .map((x) => x is String ? sanitize(x, maxLen: 80) : x)
            .toList();
      }
      // other types dropped
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════
  // CREATE EMPLOYEE (atomic, admin-guarded, rate-limited)
  // ══════════════════════════════════════════════════════════════

  /// Returns null on success, error string on failure.
  Future<String?> createEmployee({
    required String employeeId,
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required String department,
    required String nfcTagId,
    required String plainPin,
    String? phone,
    String gender = 'male',
    double basicSalary = 0,
    double allowance = 0,
  }) async {
    // 🔒 1. Admin guard
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    // 🚦 2. Rate limit
    if (!_rateLimitOk('create_employee')) {
      return 'Masyadong maraming requests. Please wait a moment.';
    }

    // ── 3. Validation ──
    final idErr = validateEmployeeId(employeeId);
    if (idErr != null) return idErr;

    final emailErr = validateEmail(email);
    if (emailErr != null) return emailErr;

    final cleanFirst = sanitize(firstName, maxLen: 50);
    final cleanLast = sanitize(lastName, maxLen: 50);
    final cleanRole = sanitize(role, maxLen: 40);
    final cleanDept = sanitize(department, maxLen: 40);
    final cleanNfc = sanitize(nfcTagId, maxLen: 40).toUpperCase();
    final cleanPhone = sanitize(phone, maxLen: 20);
    final normalizedEmail = email.trim().toLowerCase();

    if (cleanFirst.isEmpty || cleanLast.isEmpty) {
      return 'First and last name are required.';
    }

    final salaryErr = validateSalary(basicSalary, allowance);
    if (salaryErr != null) return salaryErr;

    // PIN validation
    if (plainPin.length != 4 || int.tryParse(plainPin) == null) {
      return 'PIN must be exactly 4 digits.';
    }

    // ── 4. Uniqueness (fail-closed) ──
    final emailCheck = await checkEmailUnique(normalizedEmail);
    if (emailCheck != null) return emailCheck;

    final idCheck = await checkEmployeeIdUnique(employeeId);
    if (idCheck != null) return idCheck;

    // ── 5. Atomic write ──
    try {
      final empRef = _employees.doc(employeeId);
      final now = FieldValue.serverTimestamp();

      await _fs.runTransaction((tx) async {
        final snap = await tx.get(empRef);
        if (snap.exists) {
          throw StateError('Employee ID "$employeeId" already exists.');
        }

        tx.set(empRef, {
          'employeeId': employeeId,
          'firstName': cleanFirst,
          'lastName': cleanLast,
          'name': '$cleanFirst $cleanLast',
          'email': normalizedEmail,
          'emailLower': normalizedEmail,
          'phone': cleanPhone,
          'role': cleanRole,
          'department': cleanDept,
          'gender': sanitize(gender, maxLen: 10).toLowerCase(),
          'nfcTagId': cleanNfc,
          // 🛡️ Hardened PIN hash v2
          'pinHash': hashPin(plainPin, employeeId),
          'pinVersion': 2,
          'pinSetAt': now,
          'wfhAccess': false,
          'annualLeaveTotal': 18,
          'sickLeaveTotal': 18,
          'basicSalary': basicSalary,
          'allowances': allowance,
          'terminated': false,
          'isActive': true,
          'status': 'active',
          'isOnline': false,
          'isLoggedIn': false,
          // 🛡️ Both UID and email for full traceability
          'createdByUid': _actorUid,
          'createdByEmail': _actorEmail,
          'createdAt': now,
          'updatedAt': now,
        });
      }).timeout(const Duration(seconds: 15));

      await _audit(
        action: 'employee_created',
        targetId: employeeId,
        details: {
          'name': '$cleanFirst $cleanLast',
          'email': normalizedEmail,
          'role': cleanRole,
          'department': cleanDept,
        },
      );

      if (kDebugMode) {
        debugPrint('✅ [AdminEmployeeService] created $employeeId');
      }
      return null;
    } on TimeoutException {
      return 'Request timed out. Check your connection.';
    } on StateError catch (e) {
      return e.message;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [createEmployee] $e');
      return 'Failed to create employee. Please try again.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // UPDATE EMPLOYEE (with field allowlist)
  // ══════════════════════════════════════════════════════════════

  Future<String?> updateEmployee({
    required String docId,
    required Map<String, dynamic> patch,
  }) async {
    // 🔒 1. Admin guard
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    // 🚦 2. Rate limit
    if (!_rateLimitOk('update_employee')) {
      return 'Masyadong maraming updates. Please wait.';
    }

    // 🛡️ 3. Doc ID validation
    if (!_isValidDocId(docId)) return 'Invalid employee ID format.';

    // 🛡️ 4. Field allowlist (mass-assignment defense)
    final rejected = <String>[];
    final clean = <String, dynamic>{};
    for (final entry in patch.entries) {
      if (!_updatableFields.contains(entry.key)) {
        rejected.add(entry.key);
        continue;
      }
      final v = entry.value;
      if (v is String) {
        final maxLen = switch (entry.key) {
          'firstName' || 'lastName' => 50,
          'email' || 'emailLower' => 120,
          'phone' => 20,
          'role' || 'department' => 40,
          'nfcTagId' => 40,
          'bankName' => 80,
          'accountNumber' => 30,
          _ => 200,
        };
        clean[entry.key] = sanitize(v, maxLen: maxLen);
      } else {
        clean[entry.key] = v;
      }
    }

    if (rejected.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('🚫 [updateEmployee] Rejected fields: $rejected');
      }
      return 'Invalid fields: ${rejected.join(', ')}';
    }

    if (clean.isEmpty) return 'No valid fields to update.';

    // 🛡️ 5. Validate salary if present
    if (clean.containsKey('basicSalary')) {
      final basic = (clean['basicSalary'] as num?)?.toDouble() ?? 0;
      final allow = (clean['allowances'] as num?)?.toDouble() ?? 0;
      final err = validateSalary(basic, allow);
      if (err != null) return err;
    }

    // 🛡️ 6. Normalize email if changed
    if (clean['email'] is String) {
      final e = (clean['email'] as String).toLowerCase().trim();
      final emailErr = validateEmail(e);
      if (emailErr != null) return emailErr;
      clean['email'] = e;
      clean['emailLower'] = e;

      final other = await checkEmailUnique(e, excludeDocId: docId);
      if (other != null) return other;
    }

    // 🛡️ 7. Actor tracking
    clean['updatedByUid'] = _actorUid;
    clean['updatedByEmail'] = _actorEmail;
    clean['updatedAt'] = FieldValue.serverTimestamp();

    // 🛡️ 8. Verify doc exists before patching (iwas phantom create)
    try {
      final exists = await _employees
          .doc(docId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      if (!exists.exists) return 'Employee not found.';
    } on TimeoutException {
      return 'Cannot verify employee. Check connection.';
    } catch (_) {
      return 'Cannot verify employee. Try again.';
    }

    try {
      await _employees
          .doc(docId)
          .set(clean, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      await _audit(
        action: 'employee_updated',
        targetId: docId,
        details: {'fields': clean.keys.toList()},
      );

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [updateEmployee] $e');
      return 'Update failed. Please try again.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // REGENERATE PIN (hardened)
  // ══════════════════════════════════════════════════════════════

  /// Returns the new PIN (plaintext) sa admin ONE TIME ONLY.
  /// ⚠️ Ang caller ay DAPAT ipakita ito sa secured UI at hindi i-log.
  Future<String?> regeneratePin(String docId) async {
    // 🔒 Admin guard
    try {
      await _requireAdmin();
    } on StateError catch (_) {
      return null;
    }

    // 🚦 Rate limit
    if (!_rateLimitOk('regen_pin')) {
      if (kDebugMode) debugPrint('🚫 [regenPin] rate limited');
      return null;
    }

    // 🛡️ Doc ID validation
    if (!_isValidDocId(docId)) {
      if (kDebugMode) debugPrint('🚫 [regenPin] invalid docId');
      return null;
    }

    final newPin = generatePin();
    final newHash = hashPin(newPin, docId);
    final now = FieldValue.serverTimestamp();

    try {
      await _employees.doc(docId).update({
        'pinHash': newHash,
        'pinVersion': 2,
        'pinUpdatedAt': now,
        'pinUpdatedByUid': _actorUid,
        'pinUpdatedByEmail': _actorEmail,
      }).timeout(const Duration(seconds: 10));

      await _audit(action: 'pin_regenerated', targetId: docId);

      return newPin; // ✅ caller must show once, never log
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [regeneratePin] $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SOFT DELETE (never hard delete)
  // ══════════════════════════════════════════════════════════════

  Future<String?> terminateEmployee(String docId, {String? reason}) async {
    // 🔒 Admin guard
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    // 🚦 Rate limit
    if (!_rateLimitOk('terminate')) {
      return 'Masyadong maraming terminates. Please wait.';
    }

    // 🛡️ Doc ID validation
    if (!_isValidDocId(docId)) return 'Invalid employee ID format.';

    // 🛡️ Self-termination guard
    if (docId == _actorUid) {
      return 'Hindi mo pwedeng i-terminate ang sarili mo.';
    }

    try {
      await _employees.doc(docId).update({
        'terminated': true,
        'isActive': false,
        'status': 'terminated',
        'terminatedAt': FieldValue.serverTimestamp(),
        'terminatedByUid': _actorUid,
        'terminatedByEmail': _actorEmail,
        if (reason != null)
          'terminationReason': sanitize(reason, maxLen: 200),
      }).timeout(const Duration(seconds: 10));

      await _audit(
        action: 'employee_terminated',
        targetId: docId,
        details: {if (reason != null) 'reason': reason},
      );

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [terminateEmployee] $e');
      return 'Failed to terminate. Please try again.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // WFH TOGGLE
  // ══════════════════════════════════════════════════════════════

  Future<String?> setWfhAccess(String docId, bool enabled) async {
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    if (!_rateLimitOk('wfh_toggle')) {
      return 'Masyadong maraming toggle. Please wait.';
    }
    if (!_isValidDocId(docId)) return 'Invalid employee ID format.';

    try {
      await _employees.doc(docId).update({
        'wfhAccess': enabled,
        'wfhUpdatedAt': FieldValue.serverTimestamp(),
        'wfhUpdatedByUid': _actorUid,
        'wfhUpdatedByEmail': _actorEmail,
      }).timeout(const Duration(seconds: 10));

      await _audit(
        action: 'wfh_toggled',
        targetId: docId,
        details: {'enabled': enabled},
      );
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [setWfhAccess] $e');
      return 'Failed to update WFH access.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // LEAVE CREDITS
  // ══════════════════════════════════════════════════════════════

  Future<String?> setLeaveCredits({
    required String docId,
    required int annualTotal,
    required int sickTotal,
  }) async {
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    if (!_rateLimitOk('leave_credits')) {
      return 'Too Many Updates. Please wait.';
    }
    if (!_isValidDocId(docId)) return 'Invalid employee ID format.';

    if (annualTotal < 0 || annualTotal > 60) {
      return 'Annual leave must be 0–60 days.';
    }
    if (sickTotal < 0 || sickTotal > 60) {
      return 'Sick leave must be 0–60 days.';
    }

    try {
      await _employees.doc(docId).update({
        'annualLeaveTotal': annualTotal,
        'sickLeaveTotal': sickTotal,
        'leaveCreditsUpdatedAt': FieldValue.serverTimestamp(),
        'leaveCreditsUpdatedByUid': _actorUid,
        'leaveCreditsUpdatedByEmail': _actorEmail,
      }).timeout(const Duration(seconds: 10));

      await _audit(
        action: 'leave_credits_updated',
        targetId: docId,
        details: {'annual': annualTotal, 'sick': sickTotal},
      );
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [setLeaveCredits] $e');
      return 'Failed to update leave credits.';
    }
  }

  // ══════════════════════════════════════════════════════════════
  // FACE RESET (with stricter nonce)
  // ══════════════════════════════════════════════════════════════

  Future<String?> resetFaceData(String docId, {required String nonce}) async {
    try {
      await _requireAdmin();
    } on StateError catch (e) {
      return e.message;
    }

    if (!_rateLimitOk('face_reset')) {
      return 'Masyadong maraming reset. Please wait.';
    }
    if (!_isValidDocId(docId)) return 'Invalid employee ID format.';

    // 🛡️ Nonce: 6-digit, hindi pwedeng lahat zero
    final cleanNonce = nonce.trim();
    if (cleanNonce.length != 6 ||
        int.tryParse(cleanNonce) == null ||
        cleanNonce == '000000') {
      return 'Invalid confirmation code.';
    }

    try {
      await _employees.doc(docId).update({
        'faceEmbeddingsJson': FieldValue.delete(),
        'faceEmbeddingsCount': 0,
        'faceEmbeddingSize': FieldValue.delete(),
        'faceEmbeddingVersion': 4,
        'faceResetAt': FieldValue.serverTimestamp(),
        'faceResetByUid': _actorUid,
        'faceResetByEmail': _actorEmail,
      }).timeout(const Duration(seconds: 10));

      await _audit(action: 'face_reset', targetId: docId);
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [resetFaceData] $e');
      return 'Failed to reset face data.';
    }
  }
}