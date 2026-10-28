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

  static const String _collection = 'admin_notifications';

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
    final title = 'Face Scan Issue — ${_labelForSubCategory(subCategory)}';

    final metadata = <String, dynamic>{
      'status': 'pending',
      'category': 'face_auth_issue',
      'categoryLabel': 'Face Recognition Issue',
      'subCategory': subCategory,
      if (faceMatchPercent != null) 'faceMatchPercent': faceMatchPercent,
      if (deviceModel != null) 'deviceModel': deviceModel,
      if (authMode != null) 'authMode': authMode,
      if (stage != null) 'stage': stage,
      if (errorDetail != null && errorDetail.isNotEmpty) 'errorDetail': errorDetail,
      if (additionalNotes != null && additionalNotes.isNotEmpty) 'additionalNotes': additionalNotes,
    };

    final payload = <String, dynamic>{
      'type': 'support_request',
      'title': title,
      'message': issueMessage,
      'priority': 'high',
      'read': false,
      'employeeId': employeeId,
      'employeeDocId': employeeDocId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'device': deviceModel,
      'zoneType': zoneType,
      'platform': kIsWeb ? 'web' : 'mobile',
      'timestamp': FieldValue.serverTimestamp(),
      'metadata': metadata,
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
      case 'face_not_recognized': return 'Face not recognized';
      case 'camera_error':        return 'Camera problem';
      case 'liveness_failed':     return 'Liveness check failed';
      case 'no_enrollment':       return 'No face registered';
      case 'geofence_issue':      return 'Location / geofence issue';
      case 'security_issue':      return 'Security check failed';
      default:                    return 'Other';
    }
  }
}