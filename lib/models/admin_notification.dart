// lib/models/admin_notification.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Zone types para sa attendance notifications
enum AttendanceZone {
  inside,   // 📍 Inside perimeter
  wfh,      // 🏠 Work from home
  driver,   // 🚗 Driver/Rider (field duty)
  outside,  // ⚠️ Outside perimeter
  unknown,
}

class AdminNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final String? employeeId;
  final String? employeeName;
  final DateTime? timestamp;
  final bool read;
  final String priority;
  final Map<String, dynamic> metadata;

  // ═══════════════════════════════════════════════════════════════
  // 🆕 PASSWORD CHANGE REQUEST FIELDS
  // ═══════════════════════════════════════════════════════════════
  final String? status;              // pending | approved | rejected
  final String? reason;
  final String? employeeIdentifier;  // Employee ID string (e.g. "EMP-01-2026")
  final String? employeeEmail;

  const AdminNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.employeeId,
    this.employeeName,
    this.timestamp,
    this.read = false,
    this.priority = 'normal',
    this.metadata = const {},
    this.status,                    // 🆕
    this.reason,                    // 🆕
    this.employeeIdentifier,        // 🆕
    this.employeeEmail,             // 🆕
  });

  // ═══════════════════════════════════════════════════════════════
  // ✅ ZONE HELPERS
  // ═══════════════════════════════════════════════════════════════
  AttendanceZone get zone {
    final raw = metadata['zone']?.toString().toLowerCase();
    switch (raw) {
      case 'inside':
        return AttendanceZone.inside;
      case 'wfh':
        return AttendanceZone.wfh;
      case 'driver':
        return AttendanceZone.driver;
      case 'outside':
        return AttendanceZone.outside;
      default:
        return AttendanceZone.unknown;
    }
  }

  String get zoneLabel {
    switch (zone) {
      case AttendanceZone.inside:
        return 'Inside perimeter';
      case AttendanceZone.wfh:
        return 'Work from home';
      case AttendanceZone.driver:
        return 'Driver mode';
      case AttendanceZone.outside:
        return 'Outside perimeter';
      case AttendanceZone.unknown:
        return '';
    }
  }

  String get zoneEmoji {
    switch (zone) {
      case AttendanceZone.inside:
        return '📍';
      case AttendanceZone.wfh:
        return '🏠';
      case AttendanceZone.driver:
        return '🚗';
      case AttendanceZone.outside:
        return '⚠️';
      case AttendanceZone.unknown:
        return '';
    }
  }

  bool get isGeofenceAlert => type == 'geofence_alert' || priority == 'high';
  bool get isClockIn => type == 'clock_in' || type == 'wfh_toggle';
  bool get isClockOut => type == 'clock_out';
  bool get isFaceEnrollment => type == 'face_enrollment';
  bool get isLeaveRequest => type == 'leave_request';

  // ═══════════════════════════════════════════════════════════════
  // ✅ PASSWORD CHANGE HELPERS
  // ═══════════════════════════════════════════════════════════════
  bool get isPasswordChange => type == 'password_change';

  /// True kung pending ang password change request.
  bool get isPasswordChangePending =>
      isPasswordChange && (status ?? 'pending') == 'pending';

  /// True kung approved na.
  bool get isPasswordChangeApproved =>
      isPasswordChange && status == 'approved';

  /// True kung rejected na.
  bool get isPasswordChangeRejected =>
      isPasswordChange && status == 'rejected';

  // ═══════════════════════════════════════════════════════════════
  // FACTORY
  // ═══════════════════════════════════════════════════════════════
  factory AdminNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    DateTime? ts;
    final raw = d['timestamp'];
    if (raw is Timestamp) ts = raw.toDate();

    return AdminNotification(
      id: doc.id,
      type: (d['type'] ?? 'unknown').toString(),
      title: (d['title'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      employeeId: d['employeeId']?.toString(),
      employeeName: d['employeeName']?.toString(),
      timestamp: ts,
      read: d['read'] == true,
      priority: (d['priority'] ?? 'normal').toString(),
      metadata: (d['metadata'] as Map?)?.cast<String, dynamic>() ?? {},
      status: d['status']?.toString(),                        // 🆕
      reason: d['reason']?.toString(),                        // 🆕
      employeeIdentifier: d['employeeIdentifier']?.toString(),// 🆕
      employeeEmail: d['employeeEmail']?.toString(),          // 🆕
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // COPY-WITH  (pinanatili ang lumang API + dinagdagan)
  // ═══════════════════════════════════════════════════════════════
  AdminNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    String? employeeId,
    String? employeeName,
    DateTime? timestamp,
    bool? read,
    String? priority,
    Map<String, dynamic>? metadata,
    String? status,
    String? reason,
    String? employeeIdentifier,
    String? employeeEmail,
  }) {
    return AdminNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      timestamp: timestamp ?? this.timestamp,
      read: read ?? this.read,
      priority: priority ?? this.priority,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      employeeIdentifier: employeeIdentifier ?? this.employeeIdentifier,
      employeeEmail: employeeEmail ?? this.employeeEmail,
    );
  }
}