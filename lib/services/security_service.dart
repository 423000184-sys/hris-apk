// lib/services/security_service.dart
import 'dart:async';   // ✅ IDINAGDAG — para sa unawaited() at Future.wait()
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';
import 'package:uuid/uuid.dart';

class SecurityService {
  static SecurityService? _instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final _uuid = const Uuid();

  static const String demoEmpId = 'demo_user_001';

  SecurityService._();
  static SecurityService get instance => _instance ??= SecurityService._();

  // ═══════════════════════════════════════════════════════════════
  // 🆕 SESSION MEMORY CACHE — pinabilis ang session checks
  // ═══════════════════════════════════════════════════════════════
  String? _cachedSessionToken;
  String? _cachedSessionExpiry;
  String? _cachedSessionEmployeeId;
  bool? _cachedIsDemoSession;
  DateTime? _cacheTime;
  static const Duration _cacheTTL = Duration(seconds: 30);

  bool get _isCacheValid {
    if (_cacheTime == null) return false;
    return DateTime.now().difference(_cacheTime!) < _cacheTTL;
  }

  void _invalidateCache() {
    _cachedSessionToken = null;
    _cachedSessionExpiry = null;
    _cachedSessionEmployeeId = null;
    _cachedIsDemoSession = null;
    _cacheTime = null;
  }

  void _updateCache({
    String? token,
    String? expiry,
    String? employeeId,
    bool? isDemo,
  }) {
    if (token != null) _cachedSessionToken = token;
    if (expiry != null) _cachedSessionExpiry = expiry;
    if (employeeId != null) _cachedSessionEmployeeId = employeeId;
    if (isDemo != null) _cachedIsDemoSession = isDemo;
    _cacheTime = DateTime.now();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 BOOTSTRAP — initialize security layer
  // ═══════════════════════════════════════════════════════════════
  bool _bootstrapped = false;

  Future<void> bootstrap() async {
    if (_bootstrapped) {
      debugPrint('🔒 [SecurityService] Already bootstrapped — skipping');
      return;
    }

    try {
      debugPrint('🔒 [SecurityService] Starting bootstrap...');

      try {
        final prefs = await SharedPreferences.getInstance();

        final existingFp = prefs.getString('device_fingerprint_id');
        if (existingFp == null || existingFp.isEmpty) {
          final rand = Random.secure();
          final bytes = List<int>.generate(12, (_) => rand.nextInt(256));
          final newFp =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          await prefs.setString('device_fingerprint_id', newFp);
          debugPrint('🔒 [SecurityService] Device fingerprint created');
        } else {
          debugPrint('🔒 [SecurityService] Device fingerprint exists');
        }

        final existingSecret = prefs.getString('receipt_signing_secret');
        if (existingSecret == null || existingSecret.isEmpty) {
          final rand = Random.secure();
          final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
          final newSecret =
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          await prefs.setString('receipt_signing_secret', newSecret);
          debugPrint('🔒 [SecurityService] Receipt signing secret created');
        }

        final pinLockoutMs = prefs.getInt('pin_lockout_until') ?? 0;
        if (pinLockoutMs > 0) {
          final lockoutUntil =
          DateTime.fromMillisecondsSinceEpoch(pinLockoutMs);
          if (lockoutUntil.isBefore(DateTime.now())) {
            await prefs.remove('pin_lockout_until');
            await prefs.remove('pin_failed_attempts');
            debugPrint('🔒 [SecurityService] Expired PIN lockout cleared');
          }
        }

        final fpLockoutMs = prefs.getInt('fp_lockout_until') ?? 0;
        if (fpLockoutMs > 0) {
          final lockoutUntil =
          DateTime.fromMillisecondsSinceEpoch(fpLockoutMs);
          if (lockoutUntil.isBefore(DateTime.now())) {
            await prefs.remove('fp_lockout_until');
            await prefs.remove('fp_failed_attempts');
            debugPrint('🔒 [SecurityService] Expired FP lockout cleared');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [SecurityService] SharedPrefs init warning: $e');
      }

      // Firestore log — fire and forget (huwag hintayin)
      unawaited(() async {
        try {
          await FirebaseFirestore.instance
              .collection('security_events')
              .add({
            'type': 'security_bootstrap',
            'severity': 'info',
            'details': 'SecurityService bootstrap completed',
            'platform': kIsWeb ? 'web' : 'mobile',
            'timestamp': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('⚠️ [SecurityService] Bootstrap log warning: $e');
        }
      }());

      _bootstrapped = true;
      debugPrint('✅ [SecurityService] Bootstrap complete');
    } catch (e) {
      debugPrint('❌ [SecurityService] Bootstrap error: $e');
      _bootstrapped = true;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 MARK SESSION ACTIVE — heartbeat
  // ═══════════════════════════════════════════════════════════════
  Future<void> markSessionActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;

      await prefs.setInt('last_session_active', now);
      debugPrint('🔒 [SecurityService] Session marked active: $now');

      // ✅ FAST: Gamitin ang cache-based getCurrentEmployeeId
      final lastSync = prefs.getInt('last_session_sync') ?? 0;
      final timeSinceSync = now - lastSync;
      const fiveMinutes = 5 * 60 * 1000;

      if (timeSinceSync > fiveMinutes && !kIsWeb) {
        try {
          final currentUserId = await getCurrentEmployeeId();
          if (currentUserId != null && currentUserId.isNotEmpty) {
            // Fire and forget — huwag hintayin
            unawaited(FirebaseFirestore.instance
                .collection('security_events')
                .add({
              'type': 'session_active',
              'severity': 'info',
              'details': 'Session active heartbeat',
              'employeeId': currentUserId,
              'timestamp': FieldValue.serverTimestamp(),
            }).timeout(const Duration(seconds: 3))
                .then((_) async {
              await prefs.setInt('last_session_sync', now);
            }).catchError((e) {
              // Silent fail — offline
            }));
          }
        } catch (e) {
          // Silent fail
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SecurityService] markSessionActive error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BIOMETRIC AUTH
  // ═══════════════════════════════════════════════════════════════
  Future<bool> isBiometricAvailable() async {
    try {
      if (kIsWeb) return false;
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      if (kIsWeb) return [];
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  Future<bool> authenticateWithBiometric({
    String reason = 'Authenticate to access HRIS',
    bool stickyAuth = true,
  }) async {
    try {
      if (kIsWeb) return false;
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: stickyAuth,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      await logSecurityEvent(
        action: 'BIOMETRIC_AUTH_FAILED',
        details: 'Error: $e',
        isSuspicious: true,
      );
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PIN SECURITY
  // ═══════════════════════════════════════════════════════════════
  String hashPin(String pin, String salt) {
    final combined = '$pin$salt${_getSecretPepper()}';
    return sha256.convert(utf8.encode(combined)).toString();
  }

  String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _getSecretPepper() => 'HRIS_BIO_2024_SECURE_PEPPER_KEY';

  Future<void> storePinHash(
      String employeeId, String pinHash, String salt) async {
    await _secureStorage.write(key: 'pin_hash_$employeeId', value: pinHash);
    await _secureStorage.write(key: 'pin_salt_$employeeId', value: salt);
  }

  Future<bool> verifyPin(String employeeId, String pin) async {
    if (kIsWeb) {
      final isValid = await isSessionValid();
      final currentId = await _secureStorage.read(key: 'session_employee_id');
      return isValid && currentId == employeeId;
    }

    String? storedHash =
    await _secureStorage.read(key: 'pin_hash_$employeeId');
    String? salt = await _secureStorage.read(key: 'pin_salt_$employeeId');

    if (storedHash == null || salt == null) {
      final employee =
      await DatabaseService.instance.getEmployeeById(employeeId);
      if (employee != null &&
          employee.pinHash != null &&
          employee.pinSalt != null) {
        storedHash = employee.pinHash;
        salt = employee.pinSalt;
        await storePinHash(employeeId, storedHash!, salt!);
      }
    }

    if (storedHash == null || salt == null) return false;
    final inputHash = hashPin(pin, salt);
    return storedHash == inputHash;
  }

  // ═══════════════════════════════════════════════════════════════
  // SESSION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════
  Future<String> createSession(String employeeId) async {
    final sessionToken = _uuid.v4();
    final expiry =
    DateTime.now().add(const Duration(hours: 8)).toIso8601String();

    // ✅ Write sa secure storage (sensitive data)
    await _secureStorage.write(key: 'session_token', value: sessionToken);
    await _secureStorage.write(
        key: 'session_employee_id', value: employeeId);
    await _secureStorage.write(key: 'session_expiry', value: expiry);

    final isDemo = employeeId == demoEmpId;
    await _secureStorage.write(
        key: 'is_demo_session', value: isDemo.toString());

    // 🆕 UPDATE MEMORY CACHE — instant para sa mga susunod na read
    _updateCache(
      token: sessionToken,
      expiry: expiry,
      employeeId: employeeId,
      isDemo: isDemo,
    );

    // Fire and forget log
    unawaited(logSecurityEvent(
      userId: employeeId,
      action: 'SESSION_CREATED',
      details:
      'New session for employee $employeeId ${isDemo ? "(DEMO)" : ""}',
    ));

    return sessionToken;
  }

  // ═════════════════════════════════════════════════════════════════
  // ✅ FIXED: isSessionValid() — cache-first para mabilis
  // ═════════════════════════════════════════════════════════════════
  Future<bool> isSessionValid() async {
    // 🆕 FAST PATH: Cache hit — instant return
    if (_isCacheValid && _cachedSessionToken != null) {
      final expiry = _cachedSessionExpiry;
      if (expiry == null) return false;
      try {
        return DateTime.now().isBefore(DateTime.parse(expiry));
      } catch (_) {
        return false;
      }
    }

    // Cache miss — read from secure storage (parallel)
    try {
      final results = await Future.wait<String?>([
        _secureStorage.read(key: 'session_token'),
        _secureStorage.read(key: 'session_expiry'),
      ]);

      final token = results[0];
      final expiry = results[1];

      if (token == null || expiry == null) {
        _updateCache(token: '', expiry: '', employeeId: '');
        return false;
      }

      _cachedSessionToken = token;
      _cachedSessionExpiry = expiry;
      _cacheTime = DateTime.now();

      try {
        return DateTime.now().isBefore(DateTime.parse(expiry));
      } catch (_) {
        return false;
      }
    } catch (e) {
      debugPrint('⚠️ [SecurityService] isSessionValid error: $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // ✅ FIXED: getCurrentEmployeeId() — cache-first
  // ═════════════════════════════════════════════════════════════════
  Future<String?> getCurrentEmployeeId() async {
    // 🆕 FAST PATH: Cache hit
    if (_isCacheValid) {
      if (_cachedSessionEmployeeId != null &&
          _cachedSessionEmployeeId!.isNotEmpty) {
        // Check expiry from cache
        if (_cachedSessionExpiry != null) {
          try {
            if (DateTime.now().isBefore(
                DateTime.parse(_cachedSessionExpiry!))) {
              return _cachedSessionEmployeeId;
            }
          } catch (_) {}
        }
      }
      // Cache present but session invalid
      if (_cachedSessionToken == null || _cachedSessionToken!.isEmpty) {
        return null;
      }
    }

    // Cache miss — read from secure storage
    final valid = await isSessionValid();
    if (!valid) return null;

    // Session valid — read employee ID (only if not cached)
    if (_cachedSessionEmployeeId != null &&
        _cachedSessionEmployeeId!.isNotEmpty) {
      return _cachedSessionEmployeeId;
    }

    try {
      final empId = await _secureStorage.read(key: 'session_employee_id');
      _cachedSessionEmployeeId = empId;
      _cacheTime = DateTime.now();
      return empId;
    } catch (e) {
      debugPrint('⚠️ [SecurityService] getCurrentEmployeeId error: $e');
      return null;
    }
  }

  Future<bool> isDemoSession() async {
    // Cache-first
    if (_isCacheValid && _cachedIsDemoSession != null) {
      return _cachedIsDemoSession!;
    }
    try {
      final val = await _secureStorage.read(key: 'is_demo_session');
      final isDemo = val == 'true';
      _cachedIsDemoSession = isDemo;
      _cacheTime = DateTime.now();
      return isDemo;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearSession() async {
    // 🆕 Invalidate cache IMMEDIATELY
    _invalidateCache();

    String? empId;
    try {
      empId = await _secureStorage.read(key: 'session_employee_id');
    } catch (_) {}

    await _secureStorage.deleteAll();

    if (empId != null) {
      unawaited(logSecurityEvent(
        userId: empId,
        action: 'SESSION_ENDED',
        details: 'User logged out',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DEVICE TRUST
  // ═══════════════════════════════════════════════════════════════
  Future<String> getDeviceId() async {
    if (kIsWeb) return 'web_browser_client';

    final cached = await _secureStorage.read(key: 'trusted_device_id');
    if (cached != null) return cached;

    final info = DeviceInfoPlugin();
    String deviceId = _uuid.v4();
    try {
      final android = await info.androidInfo;
      deviceId = '${android.id}_${android.model}';
    } catch (_) {
      try {
        final ios = await info.iosInfo;
        deviceId = ios.identifierForVendor ?? deviceId;
      } catch (_) {}
    }

    final hashedId = sha256.convert(utf8.encode(deviceId)).toString();
    await _secureStorage.write(key: 'trusted_device_id', value: hashedId);
    return hashedId;
  }

  Future<bool> isTrustedDevice(String employeeId) async {
    if (kIsWeb) return true;
    final currentDeviceId = await getDeviceId();
    final trustedDevice =
    await _secureStorage.read(key: 'trusted_device_$employeeId');
    return trustedDevice == currentDeviceId;
  }

  Future<void> trustCurrentDevice(String employeeId) async {
    if (kIsWeb) return;
    final deviceId = await getDeviceId();
    await _secureStorage.write(
        key: 'trusted_device_$employeeId', value: deviceId);
  }

  // ═══════════════════════════════════════════════════════════════
  // FACE DATA ENCRYPTION
  // ═══════════════════════════════════════════════════════════════
  String encryptFaceEmbedding(List<double> embedding) {
    final json = jsonEncode(embedding);
    final bytes = utf8.encode(json);
    return base64Url.encode(bytes);
  }

  List<double>? decryptFaceEmbedding(String? encrypted) {
    if (encrypted == null) return null;
    try {
      final bytes = base64Url.decode(encrypted);
      final json = utf8.decode(bytes);
      final list = jsonDecode(json) as List;
      return list.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ANTI-SPOOFING CHECKS
  // ═══════════════════════════════════════════════════════════════
  bool checkLivenessScore(double score) => score >= 0.75;

  bool isValidFaceAngle(double yaw, double pitch, double roll) {
    return yaw.abs() < 15 && pitch.abs() < 15 && roll.abs() < 10;
  }

  // ═══════════════════════════════════════════════════════════════
  // AUDIT LOGGING
  // ═══════════════════════════════════════════════════════════════
  Future<void> logSecurityEvent({
    String? userId,
    required String action,
    String? details,
    bool isSuspicious = false,
  }) async {
    if (kIsWeb) return;
    try {
      final deviceId = await getDeviceId();
      await DatabaseService.instance.insertAuditLog({
        'id': _uuid.v4(),
        'user_id': userId,
        'action': action,
        'details': details,
        'device_id': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
        'is_suspicious': isSuspicious ? 1 : 0,
      });
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // ATTENDANCE TOKEN
  // ═══════════════════════════════════════════════════════════════
  String generateAttendanceToken(String employeeId, String date) {
    final data =
        '$employeeId:$date:${DateTime.now().millisecondsSinceEpoch}';
    return sha256
        .convert(utf8.encode(data))
        .toString()
        .substring(0, 16)
        .toUpperCase();
  }

  // ═══════════════════════════════════════════════════════════════
  // FAILED ATTEMPTS LOCKOUT
  // ═══════════════════════════════════════════════════════════════
  Future<bool> checkLockout(String employeeId) async {
    final attempts =
    await _secureStorage.read(key: 'failed_attempts_$employeeId');
    final lockUntil =
    await _secureStorage.read(key: 'locked_until_$employeeId');

    if (lockUntil != null) {
      final lockTime = DateTime.parse(lockUntil);
      if (DateTime.now().isBefore(lockTime)) return true;
      await _secureStorage.delete(key: 'locked_until_$employeeId');
      await _secureStorage.delete(key: 'failed_attempts_$employeeId');
    }
    return false;
  }

  Future<void> recordFailedAttempt(String employeeId) async {
    final key = 'failed_attempts_$employeeId';
    final current =
        int.tryParse(await _secureStorage.read(key: key) ?? '0') ?? 0;
    final newCount = current + 1;
    await _secureStorage.write(key: key, value: newCount.toString());

    if (newCount >= 5) {
      final lockUntil = DateTime.now().add(const Duration(minutes: 15));
      await _secureStorage.write(
          key: 'locked_until_$employeeId',
          value: lockUntil.toIso8601String());
      await logSecurityEvent(
        userId: employeeId,
        action: 'ACCOUNT_LOCKED',
        details: 'Too many failed attempts',
        isSuspicious: true,
      );
    }
  }

  Future<void> recordLogout(String employeeId) async {
    await clearSession();
  }

  Future<void> clearFailedAttempts(String employeeId) async {
    await _secureStorage.delete(key: 'failed_attempts_$employeeId');
  }
}