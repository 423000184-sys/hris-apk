// ===================================================================
// FILE 1 (NEW): lib/services/attendance_override_service.dart
// ===================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

import 'onesignal_sender.dart';

const int kMinOverrideReasonLength = 10;

/// Identity of the HR/Admin performing an override.
class OverrideActor {
  const OverrideActor({
    required this.uid,
    required this.name,
    required this.role,
    required this.email,
  });

  final String uid;
  final String name;
  final String role;
  final String email;

  /// An override is only allowed when the actor is a real, named person.
  bool get isIdentified {
    final n = name.trim().toLowerCase();
    return uid.isNotEmpty &&
        uid != 'unknown' &&
        n.isNotEmpty &&
        n != 'unknown' &&
        n != 'unknown hr' &&
        n != 'admin/hr' &&
        role.trim().isNotEmpty;
  }
}

class OverrideException implements Exception {
  OverrideException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AttendanceOverrideService {
  AttendanceOverrideService._();
  static final AttendanceOverrideService instance =
  AttendanceOverrideService._();

  /// Applies an override atomically: log update + immutable audit entry +
  /// in-app notification (one transaction). Push is sent after commit
  /// (best effort, never rolls back the override).
  ///
  /// Throws [OverrideException] for anonymous actor, short reason,
  /// missing log, or employee mismatch.
  Future<void> applyOverride({
    required String logId,
    required String employeeId,
    required DateTime newTime,
    required OverrideActor actor,
    required String reason,
  }) async {
    final cleanReason = reason.trim();
    if (!actor.isIdentified) {
      throw OverrideException(
          'Override blocked: HR identity (name and role) is required.');
    }
    if (cleanReason.length < kMinOverrideReasonLength) {
      throw OverrideException(
          'Reason must be at least $kMinOverrideReasonLength characters.');
    }
    if (logId.isEmpty || employeeId.isEmpty) {
      throw OverrideException('Missing log or employee ID.');
    }

    final db = FirebaseFirestore.instance;
    final logRef = db.collection('attendance_logs').doc(logId);
    final overrideRef = logRef.collection('overrides').doc();
    final auditRef = db.collection('admin_audit_log').doc();
    final notifRef = db.collection('notifications').doc();

    String fieldType = '';
    DateTime? oldTime;

    await db.runTransaction((tx) async {
      final snap = await tx.get(logRef);
      final data = snap.data();
      if (!snap.exists || data == null) {
        throw OverrideException('Attendance log not found.');
      }
      final owner = (data['employee_id'] ?? '').toString();
      if (owner != employeeId) {
        throw OverrideException('Log does not belong to this employee.');
      }

      fieldType = (data['type'] ?? '').toString().toUpperCase();
      final prev = data['timestamp'];
      oldTime = prev is Timestamp ? prev.toDate() : null;
      // Keep the very first original time across multiple overrides.
      final firstOriginal = data['originalTimestamp'] ?? prev;
      final newTs = Timestamp.fromDate(newTime);

      tx.update(logRef, {
        'timestamp': newTs,
        'time': DateFormat('HH:mm:ss').format(newTime),
        'isOverridden': true,
        'originalTimestamp': firstOriginal,
        'overriddenByUid': actor.uid,
        'overriddenByName': actor.name.trim(),
        'overriddenByRole': actor.role.trim(),
        'overriddenByEmail': actor.email,
        'overrideReason': cleanReason,
        'overrideAt': FieldValue.serverTimestamp(),
      });

      // Immutable trail (lock with rules: create-only, no update/delete).
      tx.set(overrideRef, {
        'fieldType': fieldType,
        'oldTimestamp': prev,
        'newTimestamp': newTs,
        'byUid': actor.uid,
        'byName': actor.name.trim(),
        'byRole': actor.role.trim(),
        'byEmail': actor.email,
        'reason': cleanReason,
        'at': FieldValue.serverTimestamp(),
      });

      tx.set(auditRef, {
        'action': 'attendance_time_overridden',
        'targetType': 'attendance_log',
        'targetId': logId,
        'actorUid': actor.uid,
        'actorEmail': actor.email,
        'actorName': actor.name.trim(),
        'actorRole': actor.role.trim(),
        'details': {
          'employeeId': employeeId,
          'fieldType': fieldType,
          'from': prev,
          'to': newTs,
          'reason': cleanReason,
        },
        'timestamp': FieldValue.serverTimestamp(),
      });

      // In-app notification, visible to the employee.
      tx.set(notifRef, {
        'employee_id': employeeId,
        'type': 'ATTENDANCE_OVERRIDE',
        'title': 'Attendance time edited',
        'message': _buildMessage(
          actor: actor,
          fieldType: fieldType,
          oldTime: oldTime,
          newTime: newTime,
          reason: cleanReason,
        ),
        'logId': logId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    // Push notification (best effort).
    try {
      await OneSignalSender.instance.sendToEmployee(
        employeeId: employeeId,
        title: 'Attendance time edited',
        message: _buildMessage(
          actor: actor,
          fieldType: fieldType,
          oldTime: oldTime,
          newTime: newTime,
          reason: cleanReason,
        ),
        type: 'ATTENDANCE_OVERRIDE',
      );
    } catch (e) {
      debugPrint('⚠️ Override push failed (override still saved): $e');
    }
  }

  String _buildMessage({
    required OverrideActor actor,
    required String fieldType,
    required DateTime? oldTime,
    required DateTime newTime,
    required String reason,
  }) {
    final f = DateFormat('MMM d, hh:mm a');
    final from = oldTime != null ? f.format(oldTime) : 'unknown';
    return '${actor.name.trim()} (${actor.role.trim()}) changed your '
        '${fieldType.isEmpty ? 'attendance' : fieldType} time from $from '
        'to ${f.format(newTime)}. Reason: $reason';
  }
}