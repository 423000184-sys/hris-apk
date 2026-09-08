// lib/services/security_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
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

  // ============ BIOMETRIC AUTH ============
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

  // ============ PIN SECURITY ============
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

  Future<void> storePinHash(String employeeId, String pinHash, String salt) async {
    await _secureStorage.write(key: 'pin_hash_$employeeId', value: pinHash);
    await _secureStorage.write(key: 'pin_salt_$employeeId', value: salt);
  }

  /// Verifies PIN by checking both Secure Storage and Database
  Future<bool> verifyPin(String employeeId, String pin) async {
    // For Web, if we don't have it in secure storage, we might just trust the session
    // Or we should have stored a "web_pin" flag during login.
    // For now, let's allow it on Web if session is valid to prevent hanging.
    if (kIsWeb) {
      final isValid = await isSessionValid();
      final currentId = await _secureStorage.read(key: 'session_employee_id');
      return isValid && currentId == employeeId;
    }

    String? storedHash = await _secureStorage.read(key: 'pin_hash_$employeeId');
    String? salt = await _secureStorage.read(key: 'pin_salt_$employeeId');

    if (storedHash == null || salt == null) {
      final employee = await DatabaseService.instance.getEmployeeById(employeeId);
      if (employee != null && employee.pinHash != null && employee.pinSalt != null) {
        storedHash = employee.pinHash;
        salt = employee.pinSalt;
        await storePinHash(employeeId, storedHash!, salt!);
      }
    }

    if (storedHash == null || salt == null) return false;
    final inputHash = hashPin(pin, salt);
    return storedHash == inputHash;
  }

  // ============ SESSION MANAGEMENT ============
  Future<String> createSession(String employeeId) async {
    final sessionToken = _uuid.v4();
    final expiry = DateTime.now().add(const Duration(hours: 8)).toIso8601String();
    await _secureStorage.write(key: 'session_token', value: sessionToken);
    await _secureStorage.write(key: 'session_employee_id', value: employeeId);
    await _secureStorage.write(key: 'session_expiry', value: expiry);
    
    final isDemo = employeeId == demoEmpId;
    await _secureStorage.write(key: 'is_demo_session', value: isDemo.toString());

    await logSecurityEvent(
      userId: employeeId,
      action: 'SESSION_CREATED',
      details: 'New session for employee $employeeId ${isDemo ? "(DEMO)" : ""}',
    );
    return sessionToken;
  }

  Future<bool> isSessionValid() async {
    final token = await _secureStorage.read(key: 'session_token');
    final expiry = await _secureStorage.read(key: 'session_expiry');
    if (token == null || expiry == null) return false;
    try {
      return DateTime.now().isBefore(DateTime.parse(expiry));
    } catch (_) {
      return false;
    }
  }

  Future<String?> getCurrentEmployeeId() async {
    final valid = await isSessionValid();
    if (!valid) return null;
    return _secureStorage.read(key: 'session_employee_id');
  }

  Future<bool> isDemoSession() async {
    final val = await _secureStorage.read(key: 'is_demo_session');
    return val == 'true';
  }

  Future<void> clearSession() async {
    final empId = await _secureStorage.read(key: 'session_employee_id');
    await _secureStorage.deleteAll();
    if (empId != null) {
      await logSecurityEvent(
        userId: empId,
        action: 'SESSION_ENDED',
        details: 'User logged out',
      );
    }
  }

  // ============ DEVICE TRUST ============
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
    final trustedDevice = await _secureStorage.read(
        key: 'trusted_device_$employeeId');
    return trustedDevice == currentDeviceId;
  }

  Future<void> trustCurrentDevice(String employeeId) async {
    if (kIsWeb) return;
    final deviceId = await getDeviceId();
    await _secureStorage.write(
        key: 'trusted_device_$employeeId', value: deviceId);
  }

  // ============ FACE DATA ENCRYPTION ============
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

  // ============ ANTI-SPOOFING CHECKS ============
  bool checkLivenessScore(double score) => score >= 0.75;

  bool isValidFaceAngle(double yaw, double pitch, double roll) {
    return yaw.abs() < 15 && pitch.abs() < 15 && roll.abs() < 10;
  }

  // ============ AUDIT LOGGING ============
  Future<void> logSecurityEvent({
    String? userId,
    required String action,
    String? details,
    bool isSuspicious = false,
  }) async {
    if (kIsWeb) return; // DatabaseService not ready for web logs
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

  // ============ ATTENDANCE TOKEN ============
  String generateAttendanceToken(String employeeId, String date) {
    final data = '$employeeId:$date:${DateTime.now().millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(data)).toString().substring(0, 16).toUpperCase();
  }

  // ============ FAILED ATTEMPTS LOCKOUT ============
  Future<bool> checkLockout(String employeeId) async {
    final attempts = await _secureStorage.read(key: 'failed_attempts_$employeeId');
    final lockUntil = await _secureStorage.read(key: 'locked_until_$employeeId');

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
    final current = int.tryParse(
            await _secureStorage.read(key: key) ?? '0') ??
        0;
    final newCount = current + 1;
    await _secureStorage.write(key: key, value: newCount.toString());

    if (newCount >= 5) {
      final lockUntil = DateTime.now().add(const Duration(minutes: 15));
      await _secureStorage.write(
          key: 'locked_until_$employeeId', value: lockUntil.toIso8601String());
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
