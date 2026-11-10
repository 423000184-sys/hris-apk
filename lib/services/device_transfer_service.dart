// lib/services/device_transfer_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show kOneSignalAppId;

class DeviceTransferService {
  DeviceTransferService._();
  static final DeviceTransferService _instance = DeviceTransferService._();
  factory DeviceTransferService() => _instance;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _cachedApiKey;

  // ═══════════════════════════════════════════════════════════════════
  // FETCH OneSignal REST API key from Firestore (admin-only)
  // ═══════════════════════════════════════════════════════════════════
  Future<String> _getApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey!;
    final doc = await _firestore.collection('config').doc('notifications').get();
    final key = doc.data()?['onesignal_rest_api_key'] as String?;
    if (key == null || key.isEmpty) {
      throw Exception(
        'OneSignal REST API key missing in Firestore config/notifications',
      );
    }
    _cachedApiKey = key;
    return key;
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEND REVOKE SIGNAL TO OLD DEVICE
  // ═══════════════════════════════════════════════════════════════════
  Future<RevokeResult> revokeOldDevice({
    required String employeeId,
    required String employeeName,
    required String reason,
  }) async {
    try {
      // 1. Kunin ang current activeDeviceId (para sa audit)
      final empDoc = await _firestore
          .collection('employees')
          .doc(employeeId)
          .get();

      if (!empDoc.exists) {
        return RevokeResult(
          success: false,
          message: 'Employee not found: $employeeId',
        );
      }

      final oldDeviceId = empDoc.data()?['activeDeviceId'] as String?;

      if (oldDeviceId == null || oldDeviceId.isEmpty) {
        return RevokeResult(
          success: false,
          message: 'Walang naka-bind na device sa employee na ito.',
        );
      }

      // 2. Mag-send ng OneSignal push sa OLD device
      final apiKey = await _getApiKey();
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $apiKey',
        },
        body: jsonEncode({
          'app_id': kOneSignalAppId,
          'include_external_user_ids': [employeeId],
          'data': {
            'type': 'DEVICE_REVOKED',
            'reason': reason,
            'oldDeviceId': oldDeviceId,
          },
          'priority': 10,
          'content_available': true,
          'android_channel_id': 'employee_notifications_channel',
          'ttl': 3600,
        }),
      );

      debugPrint(
          '📤 [Transfer] OneSignal response: ${response.statusCode} ${response.body}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return RevokeResult(
          success: false,
          message: 'OneSignal API error ${response.statusCode}: ${response.body}',
        );
      }

      // 3. Clear activeDeviceId in Firestore (para makapasok ang bagong device)
      await _firestore.collection('employees').doc(employeeId).update({
        'activeDeviceId': FieldValue.delete(),
        'deviceBoundAt': FieldValue.delete(),
        'pendingWipeAcknowledgedAt': FieldValue.delete(),
        'lastTransferAt': FieldValue.serverTimestamp(),
        'lastTransferBy': _auth.currentUser?.uid,
      });

      // 4. Audit log
      await _firestore.collection('device_audit').add({
        'employeeId': employeeId,
        'employeeName': employeeName,
        'action': 'REVOKE',
        'oldDeviceId': oldDeviceId,
        'newDeviceId': null,
        'performedBy': _auth.currentUser?.uid ?? 'unknown',
        'performedByName': _auth.currentUser?.displayName ??
            _auth.currentUser?.email ??
            'Admin',
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ [Transfer] Revoked device for $employeeId');

      return RevokeResult(
        success: true,
        message:
        'Revoke signal sent. Old device will be wiped on next connection.',
        oldDeviceId: oldDeviceId,
      );
    } catch (e) {
      debugPrint('❌ [Transfer] Revoke failed: $e');
      return RevokeResult(success: false, message: 'Error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STREAM: Get device audit history for an employee
  // ═══════════════════════════════════════════════════════════════════
  Stream<QuerySnapshot> getAuditHistory(String employeeId) {
    return _firestore
        .collection('device_audit')
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }
}

class RevokeResult {
  final bool success;
  final String message;
  final String? oldDeviceId;

  const RevokeResult({
    required this.success,
    required this.message,
    this.oldDeviceId,
  });
}