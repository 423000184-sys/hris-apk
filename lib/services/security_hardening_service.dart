// lib/services/security_hardening_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central security hardening service.
///
/// Responsibilities:
///   • Device integrity (root / emulator / mock GPS detection)
///   • PIN hashing (peppered lookup + salted iterated verify)
///   • Session tokens (secure-storage backed, TTL enforced)
///   • Exponential backoff rate limiting
///   • Screenshot prevention (FLAG_SECURE via MethodChannel)
///   • Real device binding (hashed hardware fingerprint)
///   • Version gate (force-update)
class SecurityHardeningService {
  SecurityHardeningService._();
  static final SecurityHardeningService instance =
  SecurityHardeningService._();

  // ─────────────────────────────────────────────────────────────
  // Secure storage (Android Keystore / iOS Keychain)
  // ─────────────────────────────────────────────────────────────
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // ─────────────────────────────────────────────────────────────
  // Tunables
  // ─────────────────────────────────────────────────────────────
  /// ⚠️ 120k iterations sa Dart = 5-15s delay sa mid-range phone.
  /// 10k is enough for 4-digit PIN combined with server-side rate limiting
  /// + peppered lookup hash.
  static const int pinIterations = 10000;
  static const int pinSaltLength = 16;

  /// App-wide pepper para sa lookup hash lang.
  /// ⚠️ Change this value in production. Better: load from
  /// `--dart-define=PIN_PEPPER=xxx` or Firebase Remote Config.
  static const String _pepper =
      'R4C0M4-2024-PEPPER-CHANGE-ME-IN-PROD-7f8a9b1c';

  static const Duration sessionTtl = Duration(hours: 12);

  // Secure-storage keys
  static const _kSessionToken = 'sec_session_token';
  static const _kSessionExpiry = 'sec_session_expiry';
  static const _kSessionEmp = 'sec_session_emp';
  static const _kDeviceId = 'sec_device_id';

  // SharedPreferences keys (non-sensitive lang dapat)
  static const _kFailCount = 'sec_fail_count';
  static const _kBackoffUntil = 'sec_backoff_until';

  static const MethodChannel _channel =
  MethodChannel('com.racoma.app/security');

  // ─────────────────────────────────────────────────────────────
  // Integrity state
  // ─────────────────────────────────────────────────────────────
  bool _integrityChecked = false;
  bool _integrityCompromised = false;
  List<String> _integrityIssues = const [];

  bool get isCompromised => _integrityCompromised;
  List<String> get integrityIssues => _integrityIssues;

  // ═════════════════════════════════════════════════════════════
  // 1. DEVICE INTEGRITY
  // ═════════════════════════════════════════════════════════════
  Future<bool> checkDeviceIntegrity() async {
    if (kIsWeb) {
      _integrityChecked = true;
      return true;
    }
    if (_integrityChecked) return !_integrityCompromised;

    final issues = <String>[];

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        if (!a.isPhysicalDevice) issues.add('emulator');

        const suPaths = <String>[
          '/system/app/Superuser.apk',
          '/sbin/su',
          '/system/bin/su',
          '/system/xbin/su',
          '/data/local/xbin/su',
          '/data/local/bin/su',
          '/system/sd/xbin/su',
          '/system/bin/failsafe/su',
          '/data/local/su',
          '/su/bin/su',
          '/magisk/.core/bin/su',
          '/system/xbin/daemonsu',
        ];
        for (final p in suPaths) {
          try {
            if (await File(p).exists()) {
              issues.add('root:$p');
              break;
            }
          } catch (_) {}
        }

        try {
          final mounts = await File('/proc/mounts').readAsString();
          if (mounts.contains('magisk') || mounts.contains('supersu')) {
            issues.add('magisk_mount');
          }
        } catch (_) {}
      } else if (Platform.isIOS) {
        try {
          final i = await plugin.iosInfo;
          if (!i.isPhysicalDevice) issues.add('emulator');
        } catch (_) {}
      }
    } catch (_) {}

    // Skip root warnings sa debug builds
    if (kDebugMode) {
      issues.removeWhere(
            (i) => i.startsWith('root:') || i == 'magisk_mount',
      );
    }

    _integrityIssues = List.unmodifiable(issues);
    _integrityCompromised = issues.isNotEmpty;
    _integrityChecked = true;
    return !_integrityCompromised;
  }

  // ═════════════════════════════════════════════════════════════
  // 2. PIN HASHING
  // ═════════════════════════════════════════════════════════════

  /// Fast hash for lookup (with pepper).
  ///
  /// Purpose: makahanap ng employee record mula sa PIN nang walang
  /// plaintext sa DB. Ito ay SHA-256, hindi password-hash — pero
  /// ginagamit lang ito para sa Firestore `.where()` lookup.
  /// Ang totoong verify ay [verifyPin] / [verifyPinAsync].
  String pinLookupHash(String pin) =>
      sha256.convert(utf8.encode('$_pepper:$pin')).toString();

  /// Salted iterated hash para sa verification.
  ///
  /// ⚠️ SYNCHRONOUS — may 1-2 second blocking time sa mid-range phone
  /// sa 10k iterations. Kung sa UI thread, gamitin ang [pinHashAsync].
  String pinHash(
      String pin,
      String salt, {
        int iterations = pinIterations,
      }) {
    final saltBytes = utf8.encode(salt);
    final initial = <int>[...utf8.encode('$salt|$pin|$salt')];

    // ✅ FIX: Explicit na List<int> — hindi Uint8List
    var digest = sha256
        .convert(initial)
        .bytes
        .toList(growable: false);

    for (var i = 0; i < iterations; i++) {
      final input = <int>[]
        ..addAll(digest)
        ..addAll(saltBytes);
      // ✅ FIX: .toList() para siguradong List<int>, hindi Uint8List
      digest = sha256
          .convert(input)
          .bytes
          .toList(growable: false);
    }

    // Hex encode — mas efficient kaysa .map().join()
    final buf = StringBuffer();
    for (final b in digest) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Async wrapper — runs sa Isolate para hindi mag-freeze ang UI.
  /// Recommended para sa UI thread calls.
  Future<String> pinHashAsync(
      String pin,
      String salt, {
        int iterations = pinIterations,
      }) {
    return Isolate.run(
          () => pinHash(pin, salt, iterations: iterations),
    );
  }

  /// Constant-time compare para iwas timing attacks.
  bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Synchronous verify — para sa non-UI contexts.
  bool verifyPin(String pin, String salt, String expectedHash) {
    final got = pinHash(pin, salt);
    return _constantTimeEqual(got, expectedHash);
  }

  /// ✅ RECOMMENDED — async verify gamit ang Isolate.
  /// Hindi nag-f-freeze ang UI kahit 10k+ iterations.
  Future<bool> verifyPinAsync(
      String pin,
      String salt,
      String expectedHash,
      ) async {
    final got = await pinHashAsync(pin, salt);
    return _constantTimeEqual(got, expectedHash);
  }

  String generateSalt([int len = pinSaltLength]) {
    final r = math.Random.secure();
    return List<int>.generate(len, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ═════════════════════════════════════════════════════════════
  // 3. SESSION TOKEN
  // ═════════════════════════════════════════════════════════════
  Future<String> issueSessionToken(String employeeId) async {
    final token = _randomHex(32);
    final expiry = DateTime.now().add(sessionTtl);
    await _secure.write(key: _kSessionToken, value: token);
    await _secure.write(
      key: _kSessionExpiry,
      value: expiry.millisecondsSinceEpoch.toString(),
    );
    await _secure.write(key: _kSessionEmp, value: employeeId);
    return token;
  }

  Future<String?> getValidSessionToken() async {
    final token = await _secure.read(key: _kSessionToken);
    final expiryStr = await _secure.read(key: _kSessionExpiry);
    if (token == null || expiryStr == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(expiryStr) ?? 0,
    );
    if (expiry.isBefore(DateTime.now())) {
      await clearSession();
      return null;
    }
    return token;
  }

  Future<String?> getCurrentEmployeeId() async {
    final ok = await getValidSessionToken();
    if (ok == null) return null;
    return _secure.read(key: _kSessionEmp);
  }

  Future<void> clearSession() async {
    await _secure.delete(key: _kSessionToken);
    await _secure.delete(key: _kSessionExpiry);
    await _secure.delete(key: _kSessionEmp);
  }

  // ═════════════════════════════════════════════════════════════
  // 4. EXPONENTIAL BACKOFF
  // ═════════════════════════════════════════════════════════════
  Future<Duration?> getActiveBackoff() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kBackoffUntil) ?? 0;
    if (until <= 0) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(until);
    if (dt.isBefore(DateTime.now())) {
      await prefs.remove(_kBackoffUntil);
      return null;
    }
    return dt.difference(DateTime.now());
  }

  Future<Duration> registerFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kFailCount) ?? 0) + 1;
    await prefs.setInt(_kFailCount, count);

    Duration delay;
    if (count <= 2) {
      delay = Duration.zero;
    } else if (count == 3) {
      delay = const Duration(seconds: 30);
    } else if (count == 4) {
      delay = const Duration(minutes: 2);
    } else if (count == 5) {
      delay = const Duration(minutes: 15);
    } else if (count <= 8) {
      delay = const Duration(hours: 1);
    } else {
      delay = const Duration(hours: 6);
    }

    if (delay > Duration.zero) {
      final until = DateTime.now().add(delay);
      await prefs.setInt(_kBackoffUntil, until.millisecondsSinceEpoch);
    }
    return delay;
  }

  Future<void> resetFailures() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailCount);
    await prefs.remove(_kBackoffUntil);
  }

  Future<int> getFailureCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFailCount) ?? 0;
  }

  // ═════════════════════════════════════════════════════════════
  // 5. SCREENSHOT PROTECTION
  // ═════════════════════════════════════════════════════════════
  Future<void> enableSecureScreen() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('enableSecure');
    } catch (_) {}
  }

  Future<void> disableSecureScreen() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('disableSecure');
    } catch (_) {}
  }

  // ═════════════════════════════════════════════════════════════
  // 6. DEVICE BINDING (real fingerprint, hindi random)
  // ═════════════════════════════════════════════════════════════
  Future<String> getDeviceFingerprint() async {
    if (kIsWeb) return 'web-${_randomHex(8)}';
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        return _sha256Hex(
          '${a.id}|${a.brand}|${a.model}|${a.device}|'
              '${a.board}|${a.hardware}',
        );
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return _sha256Hex(
          '${i.identifierForVendor}|${i.model}|${i.systemVersion}',
        );
      }
    } catch (_) {}
    return _sha256Hex(_randomHex(16));
  }

  Future<String> getOrCreateDeviceId() async {
    var id = await _secure.read(key: _kDeviceId);
    if (id == null || id.isEmpty) {
      id = _randomHex(16);
      await _secure.write(key: _kDeviceId, value: id);
    }
    return id;
  }

  /// Combined device binding token (for logs / server-side checks).
  Future<String> getDeviceBindingToken() async {
    final fp = await getDeviceFingerprint();
    final id = await getOrCreateDeviceId();
    return _sha256Hex('$id::$fp');
  }

  // ═════════════════════════════════════════════════════════════
  // 7. MISC HELPERS
  // ═════════════════════════════════════════════════════════════
  Future<void> ensureLatestVersion({String? minVersion}) async {
    if (minVersion == null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.version.replaceAll('.', '')) ?? 0;
      final min = int.tryParse(minVersion.replaceAll('.', '')) ?? 0;
      if (current < min) {
        throw StateError('App version outdated. Please update.');
      }
    } catch (_) {}
  }

  String _randomHex(int bytes) {
    final r = math.Random.secure();
    return List<int>.generate(bytes, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<void> wipeSecureData() async => _secure.deleteAll();
}