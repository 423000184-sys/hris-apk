// lib/services/device_binding_service.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'device_info_service.dart'; // 🔑 Gagamitin natin ito

class DeviceBindingService {
  DeviceBindingService._();
  static final DeviceBindingService _instance = DeviceBindingService._();
  factory DeviceBindingService() => _instance;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kBoundEmployeeKey = 'bound_employee_id';

  String? _cachedDeviceId;

  // ═══════════════════════════════════════════════════════════════════
  // DEVICE ID — 🆕 Gagamit na ng DeviceInfoService (hardware-based)
  // ═══════════════════════════════════════════════════════════════════
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final id = await DeviceInfoService.instance.getUniqueDeviceId();
    _cachedDeviceId = id;
    return id;
  }

  // ═══════════════════════════════════════════════════════════════════
  // CHECK IF DEVICE IS BOUND
  // ═══════════════════════════════════════════════════════════════════
  Future<DeviceBindingStatus> checkBinding(String employeeId) async {
    try {
      final deviceId = await getDeviceId();
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get();

      if (!doc.exists) {
        return const DeviceBindingStatus(
          allowed: false,
          reason: 'Employee not found',
        );
      }

      final data = doc.data()!;
      final activeDeviceId = (data['activeDeviceId'] as String?)?.trim() ?? '';

      // 🆕 Admin revoke check
      final revokedAtMs =
          (data['deviceBindingRevokedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
      final boundAtMs =
          (data['deviceBoundAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;

      // Kung ang admin revoke ay MAS BAGO kaysa sa huling bind → pwedeng mag-bind ulit
      if (revokedAtMs > 0 && revokedAtMs > boundAtMs) {
        return const DeviceBindingStatus(
          allowed: true,
          needsBinding: true,
          reason: 'Admin revoked the binding — re-bind allowed',
        );
      }

      // Case 1: Walang naka-bind → pwede itong device
      if (activeDeviceId.isEmpty) {
        return const DeviceBindingStatus(
          allowed: true,
          needsBinding: true,
          reason: 'No device bound yet',
        );
      }

      // Case 2: Ito na ang bound device → allowed
      if (activeDeviceId == deviceId) {
        return const DeviceBindingStatus(
          allowed: true,
          needsBinding: false,
          reason: 'This device is bound',
        );
      }

      // 🆕 Case 3: Ibang device ID pero pareho pa rin ang phone (auto-heal).
      // Nangyayari ito kapag nag-restart ng app o nag-clear ng data.
      // Papayagan natin itong mag-auto-bind ULIT basta't walang revocation flag.
      return DeviceBindingStatus(
        allowed: true,
        needsBinding: true, // Puwede nang mag-bind muli
        reason: 'Device ID changed (likely reinstall) — re-binding allowed',
        boundDeviceId: activeDeviceId,
      );
    } catch (e) {
      debugPrint('❌ [DeviceBinding] Check failed: $e');
      // Fail-open: kung offline, payagan muna para hindi ma-lock out
      return const DeviceBindingStatus(
        allowed: true,
        needsBinding: false,
        reason: 'Offline — allowing (fail-open)',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // BIND THIS DEVICE TO EMPLOYEE
  // ═══════════════════════════════════════════════════════════════════
  Future<void> bindDevice(String employeeId) async {
    final deviceId = await getDeviceId();
    final deviceModel = await DeviceInfoService.instance.getDeviceModel();

    await FirebaseFirestore.instance
        .collection('employees')
        .doc(employeeId)
        .set({
      'activeDeviceId': deviceId,
      'activeDeviceModel': deviceModel,
      'deviceBoundAt': FieldValue.serverTimestamp(),
      'deviceBindingRevokedAt': FieldValue.delete(),
    }, SetOptions(merge: true));

    await _storage.write(key: _kBoundEmployeeKey, value: employeeId);
    debugPrint('🔗 [DeviceBinding] Bound $deviceId to $employeeId');
  }


  Future<void> revokeBinding(String employeeId) async {
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(employeeId)
        .set({
      'activeDeviceId': null,
      'activeDeviceModel': null,
      'deviceBindingRevokedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    debugPrint('🔓 [DeviceBinding] Revoked binding for $employeeId');
  }

  // ═══════════════════════════════════════════════════════════════════
  // GET CURRENTLY BOUND EMPLOYEE (para sa startup check)
  // ═══════════════════════════════════════════════════════════════════
  Future<String?> getBoundEmployeeId() async {
    return _storage.read(key: _kBoundEmployeeKey);
  }

  // ═══════════════════════════════════════════════════════════════════
  // WIPE ALL LOCAL DATA
  // ═══════════════════════════════════════════════════════════════════
  Future<void> wipeLocalData({bool keepDeviceId = true}) async {
    debugPrint('🧹 [DeviceBinding] ============ WIPE START ============');
    final deviceId = await getDeviceId();

    try {
      await _storage.deleteAll();
      if (keepDeviceId) {
        // 🆕 Idinagdag natin ang Device ID sa secure storage para stable
        await _storage.write(key: 'cached_device_id', value: deviceId);
      }
      debugPrint('✅ [Wipe] Secure storage cleared');
    } catch (e) {
      debugPrint('⚠️ [Wipe] Secure storage: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('✅ [Wipe] SharedPreferences cleared');
    } catch (e) {
      debugPrint('⚠️ [Wipe] SharedPreferences: $e');
    }

    try {
      final dbDir = await getDatabasesPath();
      final files = Directory(dbDir).listSync();
      for (final file in files) {
        if (file is File && file.path.endsWith('.db')) {
          try {
            await deleteDatabase(file.path);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Wipe] SQLite: $e');
    }

    try {
      OneSignal.logout();
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    debugPrint('🧹 [DeviceBinding] ============ WIPE DONE ============');
  }
}

class DeviceBindingStatus {
  final bool allowed;
  final bool needsBinding;
  final String reason;
  final String? boundDeviceId;

  const DeviceBindingStatus({
    required this.allowed,
    this.needsBinding = false,
    required this.reason,
    this.boundDeviceId,
  });

  @override
  String toString() =>
      'DeviceBindingStatus(allowed=$allowed, needsBinding=$needsBinding, reason=$reason)';
}