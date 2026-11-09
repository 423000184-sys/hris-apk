// lib/services/session_lock_service.dart
// 🔐 One-Device-One-Login enforcement
//    - Firestore-backed session lock
//    - Real-time revocation via snapshots
//    - Heartbeat to detect stale sessions
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/widgets.dart';
import 'security_hardening_service.dart';
import 'device_info_service.dart';

void _log(String m) {
  if (kDebugMode) debugPrint('[SessionLock] $m');
}

enum SessionLockStatus {
  /// Walang active session sa ibang device — pwede mag-login
  unlocked,

  /// Same device ang may session — pwede i-refresh (re-login OK)
  sameDevice,

  /// May active session sa IBANG device — BLOCK ang bagong login
  locked,

  /// Hindi ma-check (offline, error) — fail-open
  unknown,
}

class SessionLockResult {
  final SessionLockStatus status;
  final String? otherDeviceModel;
  final String? otherEmployeeName;
  final DateTime? otherLoginAt;

  const SessionLockResult({
    required this.status,
    this.otherDeviceModel,
    this.otherEmployeeName,
    this.otherLoginAt,
  });

  bool get isLocked => status == SessionLockStatus.locked;
  bool get canProceed =>
      status == SessionLockStatus.unlocked ||
          status == SessionLockStatus.sameDevice ||
          status == SessionLockStatus.unknown;
}

class SessionLockService {
  SessionLockService._();
  static final SessionLockService instance = SessionLockService._();

  static const String _collection = 'active_sessions';

  /// Kung hindi nag-heartbeat sa loob ng N minuto, ituring na stale
  /// at pwede nang i-takeover ng bagong device.
  static const Duration _staleThreshold = Duration(minutes: 5);

  /// 🔑 Doc ID ay hashed employeeId — hindi lantad sa direct URL guessing.
  static String _docId(String employeeId) {
    return sha256.convert(utf8.encode(employeeId.trim())).toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔍 CHECK LOCK — tawagin ito BAGO mag-login
  // ═══════════════════════════════════════════════════════════════
  Future<SessionLockResult> checkLock({
    required String employeeId,
    String? deviceBindingOverride,
  }) async {
    if (employeeId.trim().isEmpty) {
      return const SessionLockResult(status: SessionLockStatus.unknown);
    }

    try {
      String? myDevice = deviceBindingOverride;
      myDevice ??= await SecurityHardeningService.instance
          .getDeviceBindingToken()
          .timeout(const Duration(seconds: 5));

      if (myDevice.isEmpty) {
        _log('⚠️ No device binding — fail-open');
        return const SessionLockResult(status: SessionLockStatus.unknown);
      }

      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId(employeeId))
          .get()
          .timeout(const Duration(seconds: 8));

      if (!doc.exists) {
        _log('✅ No existing session → unlocked');
        return const SessionLockResult(status: SessionLockStatus.unlocked);
      }

      final data = doc.data() ?? <String, dynamic>{};
      final otherDevice = (data['deviceBinding'] ?? '').toString();
      final revoked = data['revoked'] == true;
      final otherModel = (data['deviceModel'] ?? '').toString();
      final otherName = (data['employeeName'] ?? '').toString();

      // 1️⃣ Revoked — pwede nang mag-login
      if (revoked) {
        _log('✅ Session was revoked → unlocked');
        return const SessionLockResult(status: SessionLockStatus.unlocked);
      }

      // 2️⃣ Same device — pwede mag-re-login (refresh)
      if (otherDevice.isNotEmpty && otherDevice == myDevice) {
        _log('✅ Same device → allow refresh');
        return const SessionLockResult(status: SessionLockStatus.sameDevice);
      }

      // 3️⃣ Stale check — kung matagal nang walang heartbeat
      DateTime? loginAt;
      final hb = data['lastHeartbeat'];
      if (hb is Timestamp) loginAt = hb.toDate();
      if (loginAt == null) {
        final la = data['loginAt'];
        if (la is Timestamp) loginAt = la.toDate();
      }

      if (loginAt != null) {
        final elapsed = DateTime.now().difference(loginAt);
        if (elapsed > _staleThreshold) {
          _log('✅ Stale session (${elapsed.inMinutes}m) → unlocked');
          return const SessionLockResult(status: SessionLockStatus.unlocked);
        }
      } else {
        // Walang timestamp — treat as unlocked
        return const SessionLockResult(status: SessionLockStatus.unlocked);
      }

      // 4️⃣ Active session on another device — BLOCK
      _log('🔒 Locked by another device: $otherModel');
      return SessionLockResult(
        status: SessionLockStatus.locked,
        otherDeviceModel: otherModel.isEmpty ? 'Unknown Device' : otherModel,
        otherEmployeeName: otherName,
        otherLoginAt: loginAt,
      );
    } catch (e) {
      _log('⚠️ checkLock failed: $e — fail-open');
      return const SessionLockResult(status: SessionLockStatus.unknown);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 📝 REGISTER — tawagin ito PAGKATAPOS ng successful login
  // ═══════════════════════════════════════════════════════════════
  Future<void> registerSession({
    required String employeeId,
    required String employeeName,
    required String sessionNonce,
    String? deviceBindingOverride,
    String? deviceModelOverride,
  }) async {
    if (employeeId.trim().isEmpty) return;

    try {
      String? myDevice = deviceBindingOverride;
      myDevice ??= await SecurityHardeningService.instance
          .getDeviceBindingToken()
          .timeout(const Duration(seconds: 5));

      String model = deviceModelOverride ?? '';
      if (model.isEmpty) {
        try {
          model = await DeviceInfoService.instance
              .getDeviceModel()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          model = 'Unknown Device';
        }
      }

      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId(employeeId))
          .set({
        'employeeId': employeeId,
        'employeeName': employeeName,
        'deviceBinding': myDevice ?? 'unknown',
        'deviceModel': model,
        'platform': kIsWeb ? 'web' : 'mobile',
        'sessionNonce': sessionNonce,
        'loginAt': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
        'revoked': false,
        'revokedAt': null,
        'revokedReason': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _log('✅ Session registered for $employeeId');
    } catch (e) {
      _log('⚠️ registerSession failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 💓 HEARTBEAT — i-update ang lastHeartbeat kada 2 minuto
  // ═══════════════════════════════════════════════════════════════
  Future<void> heartbeat({
    required String employeeId,
    String? deviceBindingOverride,
  }) async {
    if (employeeId.trim().isEmpty) return;

    try {
      String? myDevice = deviceBindingOverride;
      myDevice ??= await SecurityHardeningService.instance
          .getDeviceBindingToken()
          .timeout(const Duration(seconds: 5));

      final ref = FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId(employeeId));

      final doc = await ref.get().timeout(const Duration(seconds: 5));
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      // Kung iba na ang may-ari ng session → huwag i-update
      if (data['deviceBinding'] != myDevice) return;
      if (data['revoked'] == true) return;

      await ref.update({
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _log('⚠️ heartbeat failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🚪 REVOKE — para i-force logout sa ibang device
  // ═══════════════════════════════════════════════════════════════
  Future<void> revokeSession({
    required String employeeId,
    required String reason,
  }) async {
    if (employeeId.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_docId(employeeId))
          .update({
        'revoked': true,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedReason': reason,
      });
    } catch (e) {
      _log('⚠️ revokeSession failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 📡 WATCH — real-time stream ng session doc
  //    Kapag `revoked: true` o iba ang deviceBinding → kick out
  // ═══════════════════════════════════════════════════════════════
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchSession(
      String employeeId) {
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId(employeeId))
        .snapshots();
  }

  /// Clear local state kapag nag-logout (huwag i-delete ang Firestore doc
  /// para may audit trail; `revoked: true` na lang).
  Future<void> clearLocal() async {
    // no-op — placeholder kung sakaling may local cache sa future
  }
}