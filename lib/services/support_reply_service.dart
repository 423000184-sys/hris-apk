// lib/services/support_reply_service.dart
// ═══════════════════════════════════════════════════════════════════
// SUPPORT REPLY SERVICE  v1.2
//   - Reply → writes to support_replies
//   - Update admin_notifications metadata
//   - Create employee_notifications entry (employee gets notified)
// Updates:
//   - All user-facing text now in English.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';

class SupportReply {
  final String id;
  final String requestId;
  final String message;
  final String adminName;
  final String adminId;
  final DateTime? timestamp;

  const SupportReply({
    required this.id,
    required this.requestId,
    required this.message,
    required this.adminName,
    required this.adminId,
    this.timestamp,
  });

  factory SupportReply.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['timestamp'];
    return SupportReply(
      id: doc.id,
      requestId: (d['requestId'] ?? '').toString(),
      message: (d['message'] ?? '').toString(),
      adminName: (d['adminName'] ?? '').toString(),
      adminId: (d['adminId'] ?? '').toString(),
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class SupportReplyService {
  SupportReplyService._();
  static final instance = SupportReplyService._();

  static const String _repliesCol = 'support_replies';
  static const String _adminNotifsCol = 'admin_notifications';
  static const String _employeeNotifsCol = 'employee_notifications';

  /// Send a reply — also creates employee-side notification.
  Future<bool> sendReply({
    required String requestId,
    required String message,
    String newStatus = 'in_progress',
    String? employeeId,
    String? employeeDocId,
    String? employeeName,
    String? categoryLabel,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) return false;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final adminUid = user?.uid ?? '';
      final adminName = _resolveAdminName(user);

      final batch = FirebaseFirestore.instance.batch();

      // 1. Reply doc
      final replyRef =
      FirebaseFirestore.instance.collection(_repliesCol).doc();
      batch.set(replyRef, <String, dynamic>{
        'requestId': requestId,
        'message': trimmed,
        'adminUid': adminUid,
        'adminName': adminName,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Update parent admin_notification
      final notifRef =
      FirebaseFirestore.instance.collection(_adminNotifsCol).doc(requestId);
      batch.update(notifRef, <String, dynamic>{
        'metadata.status': newStatus,
        'metadata.lastReplyAt': FieldValue.serverTimestamp(),
        'metadata.lastReplyBy': adminName,
        'metadata.replyCount': FieldValue.increment(1),
      });

      // 3. Employee-side notification
      if (employeeId != null && employeeId.trim().isNotEmpty) {
        final empNotifRef = FirebaseFirestore.instance
            .collection(_employeeNotifsCol)
            .doc();
        batch.set(empNotifRef, <String, dynamic>{
          'type': 'support_reply',
          'title': 'Reply from HR',
          'message': trimmed,
          'employeeId': employeeId.trim(),
          'employeeDocId': employeeDocId ?? '',
          'employeeName': employeeName ?? '',
          'senderName': adminName,
          'categoryLabel': categoryLabel ?? 'Support',
          'requestId': requestId,
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
        debugPrint('📨 [SupportReply] Employee notif queued → $employeeId');
      } else {
        debugPrint('⚠️ [SupportReply] Missing employeeId — no employee notification sent.');
      }

      await batch.commit().timeout(const Duration(seconds: 12));
      debugPrint('✅ [SupportReply] Reply sent ($newStatus)');
      return true;
    } catch (e) {
      debugPrint('❌ [SupportReply] sendReply failed: $e');
      return false;
    }
  }

  /// Update status. If 'resolved' + employeeId → send employee notif din.
  Future<bool> updateStatus({
    required String requestId,
    required String status,
    String? note,
    String? employeeId,
    String? employeeDocId,
    String? employeeName,
    String? categoryLabel,
  }) async {
    if (status != 'pending' &&
        status != 'in_progress' &&
        status != 'resolved') {
      return false;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final adminUid = user?.uid ?? '';
      final adminName = _resolveAdminName(user);

      final updates = <String, dynamic>{
        'metadata.status': status,
        'metadata.statusChangedAt': FieldValue.serverTimestamp(),
        'metadata.statusChangedBy': adminName,
        'metadata.statusChangedByUid': adminUid,
      };
      if (note != null && note.trim().isNotEmpty) {
        updates['metadata.statusNote'] = note.trim();
      }

      final batch = FirebaseFirestore.instance.batch();
      final notifRef =
      FirebaseFirestore.instance.collection(_adminNotifsCol).doc(requestId);
      batch.update(notifRef, updates);

      // Employee notification only when resolved
      if (status == 'resolved' &&
          employeeId != null &&
          employeeId.trim().isNotEmpty) {
        final empNotifRef = FirebaseFirestore.instance
            .collection(_employeeNotifsCol)
            .doc();
        batch.set(empNotifRef, <String, dynamic>{
          'type': 'support_resolved',
          'title': 'Your concern has been resolved',
          'message':
          'HR has resolved your concern (${categoryLabel ?? "Support"}). '
              'If you have any further questions, feel free to send a new support request.',
          'employeeId': employeeId.trim(),
          'employeeDocId': employeeDocId ?? '',
          'employeeName': employeeName ?? '',
          'senderName': adminName,
          'categoryLabel': categoryLabel ?? 'Support',
          'requestId': requestId,
          'read': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit().timeout(const Duration(seconds: 12));
      debugPrint('✅ [SupportReply] Status → $status');
      return true;
    } catch (e) {
      debugPrint('❌ [SupportReply] updateStatus failed: $e');
      return false;
    }
  }

  Stream<List<SupportReply>> streamReplies(String requestId) {
    return FirebaseFirestore.instance
        .collection(_repliesCol)
        .where('requestId', isEqualTo: requestId)
        .orderBy('timestamp', descending: false)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(SupportReply.fromDoc).toList());
  }

  static String _resolveAdminName(User? user) {
    final display = user?.displayName;
    if (display != null && display.trim().isNotEmpty) return display;
    final email = user?.email ?? '';
    if (email.contains('@')) return email.split('@').first;
    return 'HR';
  }
}