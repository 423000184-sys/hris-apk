// lib/models/client_meeting_assignment.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════════
// STATUS ENUM
// ═══════════════════════════════════════════════════════════════
enum AssignmentStatus {
  active,     // pwede pa gamitin, nasa time window
  used,       // nagamit na, may meeting log na
  expired,    // nalampasan ang time window + grace
  cancelled,  // admin cancelled
}

extension AssignmentStatusX on AssignmentStatus {
  String get value {
    switch (this) {
      case AssignmentStatus.active:
        return 'active';
      case AssignmentStatus.used:
        return 'used';
      case AssignmentStatus.expired:
        return 'expired';
      case AssignmentStatus.cancelled:
        return 'cancelled';
    }
  }

  static AssignmentStatus fromString(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'active':
        return AssignmentStatus.active;
      case 'used':
        return AssignmentStatus.used;
      case 'expired':
        return AssignmentStatus.expired;
      case 'cancelled':
        return AssignmentStatus.cancelled;
      default:
        return AssignmentStatus.active;
    }
  }

  String get label {
    switch (this) {
      case AssignmentStatus.active:
        return 'Active';
      case AssignmentStatus.used:
        return 'Used';
      case AssignmentStatus.expired:
        return 'Expired';
      case AssignmentStatus.cancelled:
        return 'Cancelled';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════
class ClientMeetingAssignment {
  final String id;

  // Employee info
  final String employeeId;
  final String employeeName;
  final String employeeEmail;

  // Client info
  final String clientId;
  final String clientName;
  final String clientAddress;
  final double clientLat;
  final double clientLng;
  final double clientRadius;

  // Meeting info
  final String purpose;
  final String? notes;

  // Time window
  final DateTime scheduledStart;
  final DateTime scheduledEnd;

  // Grace period (default ±15 min)
  final Duration gracePeriod;

  // Admin info
  final String assignedBy;
  final String assignedByName;
  final DateTime? assignedAt;

  // Status tracking
  final AssignmentStatus status;
  final DateTime? usedAt;
  final String? meetingLogId;

  // Metadata
  final DateTime? createdAt;

  const ClientMeetingAssignment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeEmail,
    required this.clientId,
    required this.clientName,
    required this.clientAddress,
    required this.clientLat,
    required this.clientLng,
    required this.clientRadius,
    required this.purpose,
    this.notes,
    required this.scheduledStart,
    required this.scheduledEnd,
    this.gracePeriod = const Duration(minutes: 15),
    required this.assignedBy,
    required this.assignedByName,
    this.assignedAt,
    this.status = AssignmentStatus.active,
    this.usedAt,
    this.meetingLogId,
    this.createdAt,
  });

  // ─── Effective time window (with grace) ─────────────────────
  DateTime get effectiveStart =>
      scheduledStart.subtract(gracePeriod);

  DateTime get effectiveEnd =>
      scheduledEnd.add(gracePeriod);

  // ─── Time checks ─────────────────────────────────────────────
  bool get isWithinTimeWindow {
    final now = DateTime.now();
    return now.isAfter(effectiveStart) && now.isBefore(effectiveEnd);
  }

  bool get isTooEarly {
    final now = DateTime.now();
    return now.isBefore(effectiveStart);
  }

  bool get isTooLate {
    final now = DateTime.now();
    return now.isAfter(effectiveEnd);
  }

  // ─── Status check ────────────────────────────────────────────
  bool get isUsable {
    if (status != AssignmentStatus.active) return false;
    if (!isWithinTimeWindow) return false;
    return true;
  }

  // ─── Auto-expire check (para sa `getActiveAssignment`) ───────
  bool get shouldAutoExpire {
    if (status != AssignmentStatus.active) return false;
    // Expire after 2 hours past scheduled_end
    final expiryTime = scheduledEnd.add(const Duration(hours: 2));
    return DateTime.now().isAfter(expiryTime);
  }

  // ─── Formatted helpers ───────────────────────────────────────
  String get timeWindowLabel {
    final startHr = scheduledStart.hour.toString().padLeft(2, '0');
    final startMin = scheduledStart.minute.toString().padLeft(2, '0');
    final endHr = scheduledEnd.hour.toString().padLeft(2, '0');
    final endMin = scheduledEnd.minute.toString().padLeft(2, '0');
    return '$startHr:$startMin - $endHr:$endMin';
  }

  String get dateLabel {
    final mo = scheduledStart.month.toString().padLeft(2, '0');
    final d = scheduledStart.day.toString().padLeft(2, '0');
    final y = scheduledStart.year;
    return '$mo/$d/$y';
  }

  // ═══════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════
  factory ClientMeetingAssignment.fromFirestore(
      Map<String, dynamic> data, String id) {
    return ClientMeetingAssignment(
      id: id,
      employeeId: (data['employee_id'] ?? '').toString(),
      employeeName: (data['employee_name'] ?? '').toString(),
      employeeEmail: (data['employee_email'] ?? '').toString(),
      clientId: (data['client_id'] ?? '').toString(),
      clientName: (data['client_name'] ?? '').toString(),
      clientAddress: (data['client_address'] ?? '').toString(),
      clientLat: (data['client_lat'] as num?)?.toDouble() ?? 0,
      clientLng: (data['client_lng'] as num?)?.toDouble() ?? 0,
      clientRadius: (data['client_radius'] as num?)?.toDouble() ?? 100,
      purpose: (data['purpose'] ?? '').toString(),
      notes: data['notes']?.toString(),
      scheduledStart: _toDateTime(data['scheduled_start']) ?? DateTime.now(),
      scheduledEnd: _toDateTime(data['scheduled_end']) ?? DateTime.now(),
      gracePeriod: Duration(
          minutes: (data['grace_period_min'] as num?)?.toInt() ?? 15),
      assignedBy: (data['assigned_by'] ?? '').toString(),
      assignedByName: (data['assigned_by_name'] ?? '').toString(),
      assignedAt: _toDateTime(data['assigned_at']),
      status: AssignmentStatusX.fromString(data['status']?.toString()),
      usedAt: _toDateTime(data['used_at']),
      meetingLogId: data['meeting_log_id']?.toString(),
      createdAt: _toDateTime(data['created_at']),
    );
  }

  Map<String, dynamic> toMap({bool includeTimestamp = false}) {
    return {
      'employee_id': employeeId,
      'employee_name': employeeName,
      'employee_email': employeeEmail,
      'client_id': clientId,
      'client_name': clientName,
      'client_address': clientAddress,
      'client_lat': clientLat,
      'client_lng': clientLng,
      'client_radius': clientRadius,
      'purpose': purpose,
      'notes': notes,
      'scheduled_start': Timestamp.fromDate(scheduledStart),
      'scheduled_end': Timestamp.fromDate(scheduledEnd),
      'grace_period_min': gracePeriod.inMinutes,
      'assigned_by': assignedBy,
      'assigned_by_name': assignedByName,
      'assigned_at': assignedAt != null
          ? Timestamp.fromDate(assignedAt!)
          : FieldValue.serverTimestamp(),
      'status': status.value,
      'used_at': usedAt != null ? Timestamp.fromDate(usedAt!) : null,
      'meeting_log_id': meetingLogId,
      'created_at': includeTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp()),
    };
  }

  ClientMeetingAssignment copyWith({
    String? id,
    AssignmentStatus? status,
    DateTime? usedAt,
    String? meetingLogId,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
  }) {
    return ClientMeetingAssignment(
      id: id ?? this.id,
      employeeId: employeeId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      clientId: clientId,
      clientName: clientName,
      clientAddress: clientAddress,
      clientLat: clientLat,
      clientLng: clientLng,
      clientRadius: clientRadius,
      purpose: purpose,
      notes: notes,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      gracePeriod: gracePeriod,
      assignedBy: assignedBy,
      assignedByName: assignedByName,
      assignedAt: assignedAt,
      status: status ?? this.status,
      usedAt: usedAt ?? this.usedAt,
      meetingLogId: meetingLogId ?? this.meetingLogId,
      createdAt: createdAt,
    );
  }

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}