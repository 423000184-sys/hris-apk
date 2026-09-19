// lib/services/employee_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/employee_notification.dart';

class EmployeeNotificationService {
  EmployeeNotificationService._();
  static final instance = EmployeeNotificationService._();

  final _col =
  FirebaseFirestore.instance.collection('employee_notifications');

  // ═══════════════════════════════════════════════════════════════
  // STREAMS — Client-side sort
  // ═══════════════════════════════════════════════════════════════
  Stream<List<EmployeeNotification>> streamForEmployee(String employeeId) {
    return _col
        .where('employeeId', whereIn: [employeeId, 'ALL'])
        .snapshots()
        .map((s) {
      final list = s.docs.map(EmployeeNotification.fromDoc).toList();

      list.sort((a, b) {
        final ta = a.timestamp ?? DateTime(1970);
        final tb = b.timestamp ?? DateTime(1970);
        return tb.compareTo(ta);
      });

      return list;
    });
  }

  Stream<int> streamUnreadCount(String employeeId) {
    return _col
        .where('employeeId', whereIn: [employeeId, 'ALL'])
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════
  Future<void> markAsRead(String notifId) async {
    try {
      await _col.doc(notifId).update({'read': true});
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  Future<void> markAllAsRead(String employeeId) async {
    try {
      final snap = await _col
          .where('employeeId', whereIn: [employeeId, 'ALL'])
          .where('read', isEqualTo: false)
          .limit(500)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markAllAsRead error: $e');
    }
  }

  Future<void> deleteNotification(String notifId) async {
    try {
      await _col.doc(notifId).delete();
    } catch (e) {
      debugPrint('deleteNotification error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SEND — base method
  // ═══════════════════════════════════════════════════════════════
  Future<void> send({
    required String type,
    required String title,
    required String message,
    required String employeeId,
    String senderName = 'Admin',
    String priority = 'normal',
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📤 [EmployeeNotif] SENDING:');
      debugPrint('   to      : $employeeId');
      debugPrint('   type    : $type');
      debugPrint('   title   : $title');
      debugPrint('   message : $message');
      debugPrint('   sender  : $senderName');
      debugPrint('═══════════════════════════════════════════');

      final docRef = await _col.add({
        'type': type,
        'title': title,
        'message': message,
        'employeeId': employeeId,
        'senderName': senderName,
        'priority': priority,
        'read': false,
        'metadata': metadata,
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ [EmployeeNotif] Sent — docId: ${docRef.id}');
    } catch (e) {
      debugPrint('❌ [EmployeeNotif] send error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ANNOUNCEMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> sendAnnouncement({
    required String title,
    required String message,
    String employeeId = 'ALL',
    String priority = 'normal',
  }) {
    return send(
      type: 'announcement',
      title: title,
      message: message,
      employeeId: employeeId,
      priority: priority,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PAYROLL — ✅ ENGLISH
  // ═══════════════════════════════════════════════════════════════
  Future<void> sendPayrollAlert({
    required String employeeId,
    required String employeeName,
    required String month,
    required double netPay,
  }) {
    return send(
      type: 'payroll',
      title: 'Payslip Available',
      message:
      'Hi $employeeName, your payslip for $month is now available. Net pay: ₱${netPay.toStringAsFixed(2)}',
      employeeId: employeeId,
      priority: 'high',
      metadata: {'month': month, 'netPay': netPay},
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // REMINDER
  // ═══════════════════════════════════════════════════════════════
  Future<void> sendReminder({
    required String title,
    required String message,
    String employeeId = 'ALL',
    String priority = 'normal',
  }) {
    return send(
      type: 'reminder',
      title: title,
      message: message,
      employeeId: employeeId,
      priority: priority,
    );
  }
}