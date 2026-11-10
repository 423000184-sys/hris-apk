// lib/services/admin_support_service.dart
// Admin actions for employee "Contact Admin" reports.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'admin_audit_service.dart';
import 'employee_notification_service.dart';
import 'onesignal_sender.dart';

class AdminSupportService {
  AdminSupportService._();
  static final AdminSupportService instance = AdminSupportService._();

  /// Change this to match whatever FaceSupportService.reportIssue() writes to.
  static const String collection = 'support_reports';

  // ── Reset only the fingerprint LOCK (keep enrollment) ──
  Future<String?> resetFingerprintLock({
    required String employeeDocId,
    required String adminUid,
    String? note,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeDocId)
          .update({
        'fingerprintLocked': false,
        'fingerprintLockReason': FieldValue.delete(),
        'fingerprintLockedAt': FieldValue.delete(),
        'fingerprintInvalidatedAt': FieldValue.delete(),
        'fingerprintInvalidReason': FieldValue.delete(),
        'fingerprintAdminUnlockedAt': FieldValue.serverTimestamp(),
        'fingerprintAdminUnlockedBy': adminUid,
        if (note != null && note.isNotEmpty)
          'fingerprintAdminUnlockNote': note,
      });

      await AdminAuditService.instance.log(
        action: 'fingerprint_admin_unlock',
        targetId: employeeDocId,
        targetType: 'employee',
        adminUid: adminUid,
        metadata: {'note': note ?? ''},
      );
      return null;
    } catch (e) {
      debugPrint('❌ resetFingerprintLock: $e');
      return e.toString();
    }
  }

  // ── Wipe fingerprint enrollment — forces fresh re-registration ──
  Future<String?> forceFingerprintReEnrollment({
    required String employeeDocId,
    required String adminUid,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeDocId)
          .update({
        'fingerprintEnrolled': false,
        'fingerprintLocked': false,
        'fingerprintCredentialHash': FieldValue.delete(),
        'fingerprintEnrollmentSnapshot': FieldValue.delete(),
        'fingerprintEnrolledAt': FieldValue.delete(),
        'fingerprintDeviceBinding': FieldValue.delete(),
        'fingerprintDeviceFingerprint': FieldValue.delete(),
        'fingerprintInvalidReason': 'admin_reset',
        'fingerprintAdminResetAt': FieldValue.serverTimestamp(),
        'fingerprintAdminResetBy': adminUid,
      });

      await AdminAuditService.instance.log(
        action: 'fingerprint_admin_reset',
        targetId: employeeDocId,
        targetType: 'employee',
        adminUid: adminUid,
      );
      return null;
    } catch (e) {
      debugPrint('❌ forceFingerprintReEnrollment: $e');
      return e.toString();
    }
  }

  // ── Wipe face enrollment — forces fresh re-registration ──
  Future<String?> forceFaceReEnrollment({
    required String employeeDocId,
    required String adminUid,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeDocId)
          .update({
        'faceAdminResetAt': FieldValue.serverTimestamp(),
        'faceAdminResetBy': adminUid,
      });

      await AdminAuditService.instance.log(
        action: 'face_admin_reset',
        targetId: employeeDocId,
        targetType: 'employee',
        adminUid: adminUid,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Clear biometric lockout ──
  Future<String?> clearBiometricLockout({
    required String employeeDocId,
    required String adminUid,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeDocId)
          .update({
        'fingerprintLockoutClearedAt': FieldValue.serverTimestamp(),
        'fingerprintLockoutClearedBy': adminUid,
      });

      await AdminAuditService.instance.log(
        action: 'fingerprint_lockout_cleared',
        targetId: employeeDocId,
        targetType: 'employee',
        adminUid: adminUid,
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Reply to employee via in-app + OneSignal push ──
  Future<void> notifyEmployee({
    required String employeeId,
    required String title,
    required String message,
  }) async {
    try {
      await EmployeeNotificationService.instance.send(
        type: 'reminder',
        title: title,
        message: message,
        employeeId: employeeId,
        priority: 'high',
      );
      await OneSignalSender.instance.sendToEmployee(
        employeeId: employeeId,
        title: title,
        message: message,
        type: 'reminder',
      );
    } catch (e) {
      debugPrint('⚠️ notifyEmployee: $e');
    }
  }

  // ── Mark the report resolved ──
  Future<String?> resolveReport({
    required String reportId,
    required String adminUid,
    String? reply,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(reportId)
          .update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': adminUid,
        if (reply != null && reply.isNotEmpty) 'adminReply': reply,
      });

      await AdminAuditService.instance.log(
        action: 'support_report_resolved',
        targetId: reportId,
        targetType: 'support_report',
        adminUid: adminUid,
        metadata: {'reply': reply ?? ''},
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}