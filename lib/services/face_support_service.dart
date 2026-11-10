// lib/services/face_support_service.dart
// v1.0: 📨 FACE SCAN ISSUE REPORTING
//   • Employee can report facial recognition problems to Admin
//   • Creates a `support_request` notification with category `face_auth_issue`
//   • Auto-includes diagnostics: stage, mode, match %, device, network
//   • Queues offline if no internet (synced by OfflineAttendanceService)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import '../services/offline_attendance_service.dart';
import '../services/network_guard.dart';

void _log(String m) {
  if (kDebugMode) debugPrint('[FaceSupport] $m');
}

class FaceSupportResult {
  final bool ok;
  final bool queuedOffline;
  final String? error;
  const FaceSupportResult._({required this.ok, required this.queuedOffline, this.error});

  factory FaceSupportResult.sent() => const FaceSupportResult._(ok: true, queuedOffline: false);
  factory FaceSupportResult.queued() => const FaceSupportResult._(ok: true, queuedOffline: true);
  factory FaceSupportResult.failed(String e) => FaceSupportResult._(ok: false, queuedOffline: false, error: e);
}

class FaceSupportService {
  FaceSupportService._();
  static final FaceSupportService instance = FaceSupportService._();

  static const String _collection = 'support_reports';

  /// Sends a "Face Recognition Issue" ticket to the admin notification feed.
  Future<FaceSupportResult> reportIssue({
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String employeeDocId,
    required String subCategory, // face_not_recognized, camera_error, liveness_failed, no_enrollment, geofence_issue, security_issue, other
    required String issueMessage,
    String? additionalNotes,
    double? faceMatchPercent,
    String? deviceModel,
    String? zoneType,
    String? authMode, // enroll | verify
    String? stage,    // idle | scanning | error | success
    String? errorDetail,
  }) async {
    // 🔑 Fallback kung walang ma-detect na category
    final safeSubCategory = subCategory.trim().isEmpty ? 'other' : subCategory.trim();

    // 🔑 Dynamic Detection para malaman kung Fingerprint ba o Face
    final isFingerprint = safeSubCategory.contains('fingerprint') || safeSubCategory.contains('sensor');
    final issueCategory = isFingerprint ? 'fingerprint' : 'facial_recognition';
    final issueTypeLabel = isFingerprint ? 'Fingerprint Issue' : 'Face Recognition Issue';
    final title = '$issueTypeLabel — ${_labelForSubCategory(safeSubCategory)}';

    final now = DateTime.now();
    final payload = <String, dynamic>{
      // 🔑 Root-level fields
      'status': 'pending', // 👈 Dapat laging pending pag bagong send
      'category': issueCategory,
      'categoryLabel': issueTypeLabel,
      'subCategory': safeSubCategory, // 👈 Gamitin ang safeSubCategory
      'issueMessage': issueMessage,
      'employeeId': employeeId,
      'employeeDocId': employeeDocId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'deviceModel': deviceModel,
      'zoneType': zoneType,
      'platform': kIsWeb ? 'web' : 'mobile',
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),

      // Optional fields
      if (faceMatchPercent != null) 'faceMatchPercent': faceMatchPercent,
      if (authMode != null) 'authMode': authMode,
      if (stage != null) 'stage': stage,
      if (errorDetail != null && errorDetail.isNotEmpty) 'errorDetail': errorDetail,
      if (additionalNotes != null && additionalNotes.isNotEmpty) 'additionalNotes': additionalNotes,

      // 🔔 Para sa Bell Icon notification
      'type': 'support_request',
      'title': title,
      'message': issueMessage,
      'priority': 'high',
      'read': false,
    };
    // Fast path: try online directly.
    if (NetworkGuard.instance.isOnline) {
      try {
        await FirebaseFirestore.instance.collection(_collection).add(payload);
        _log('✅ Sent face issue ticket to admin (online)');
        return FaceSupportResult.sent();
      } catch (e) {
        _log('⚠️ Online send failed: $e — will queue offline');
      }
    }

    // Offline fallback — queue and let the existing sync worker push it later.
    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: _collection,
        data: {
          ...payload,
          // OfflineAttendanceService works with concrete DateTime values,
          // not Firestore FieldValue, so swap the sentinel here.
          'timestamp': DateTime.now(),
        },
      );
      _log('📥 Queued face issue ticket (offline)');
      return FaceSupportResult.queued();
    } catch (e) {
      _log('❌ Failed to queue face issue: $e');
      return FaceSupportResult.failed(e.toString());
    }
  }

  static String _labelForSubCategory(String c) {
    switch (c) {
      case 'face_not_recognized':       return 'Face not recognized';
      case 'camera_error':              return 'Camera problem';
      case 'liveness_failed':           return 'Liveness check failed';
      case 'no_enrollment':             return 'No face registered';
      case 'fingerprint_not_recognized':return 'Fingerprint not recognized';
      case 'sensor_error':              return 'Sensor error';
      case 'lockout_issue':             return 'Locked out';
      case 'geofence_issue':            return 'Location / geofence issue';
      case 'security_issue':            return 'Security check failed';
      default:                          return 'Other';
    }
  }
}