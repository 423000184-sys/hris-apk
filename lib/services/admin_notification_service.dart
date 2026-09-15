// lib/services/admin_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/admin_notification.dart';

class AdminNotificationService {
  AdminNotificationService._();
  static final instance = AdminNotificationService._();

  final _col = FirebaseFirestore.instance.collection('admin_notifications');

  Stream<List<AdminNotification>> streamAll({int limit = 50}) {
    return _col
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  Stream<int> streamUnreadCount() {
    return _col
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Future<void> markAsRead(String id) async {
    try {
      await _col.doc(id).update({'read': true});
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final snap = await _col.where('read', isEqualTo: false).limit(500).get();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markAllAsRead error: $e');
    }
  }

  Future<void> deleteNotification(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      debugPrint('deleteNotification error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final snap = await _col.limit(500).get();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('clearAll error: $e');
    }
  }

  Future<void> notify({
    required String type,
    required String title,
    required String message,
    String? employeeId,
    String? employeeName,
    String priority = 'normal',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _col.add({
        'type': type,
        'title': title,
        'message': message,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'priority': priority,
        'read': false,
        'metadata': metadata,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [Notify] $type — $title');
    } catch (e) {
      debugPrint('❌ notify error: $e');
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────
  Future<void> notifyClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
    bool inRange = true,
    double? faceMatchPercent,
  }) {
    return notify(
      type: 'clock_in',
      title: wfh
          ? '$employeeName clocked in (WFH)'
          : '$employeeName clocked in',
      message:
      '$timeStr · ${wfh ? "Work-from-home" : (inRange ? "GPS verified" : "Outside zone")}'
          '${faceMatchPercent != null ? " · Face ${faceMatchPercent.toStringAsFixed(0)}%" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: wfh ? 'normal' : (inRange ? 'normal' : 'high'),
      metadata: {
        'time': timeStr,
        'wfh': wfh,
        'in_range': inRange,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
      },
    );
  }

  Future<void> notifyClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
  }) {
    return notify(
      type: 'clock_out',
      title: '$employeeName clocked out',
      message: '$timeStr · ${wfh ? "Work-from-home" : "On-site"}',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {'time': timeStr, 'wfh': wfh},
    );
  }

  Future<void> notifyLeaveRequest({
    required String employeeId,
    required String employeeName,
    required String leaveType,
    required String dateRange,
  }) {
    return notify(
      type: 'leave_request',
      title: '$employeeName requested $leaveType',
      message: '$dateRange · Pending approval',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'high',
      metadata: {'leave_type': leaveType, 'date_range': dateRange},
    );
  }

  Future<void> notifyWfhToggle({
    required String employeeId,
    required String employeeName,
    required bool enabled,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: enabled
          ? 'WFH enabled for $employeeName'
          : 'WFH disabled for $employeeName',
      message: enabled
          ? 'Employee can now clock in from anywhere.'
          : 'Employee must be within office zone.',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {'enabled': enabled},
    );
  }
}