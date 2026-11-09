// lib/services/demo_request_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class RedeemResult {
  final bool success;
  final String message;
  const RedeemResult({required this.success, required this.message});
}

class DemoRequestService {
  static final DemoRequestService instance = DemoRequestService._();
  DemoRequestService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _col = 'demo_requests';
  static const String _kReqId = 'my_demo_request_id';
  static const String _kReqEmail = 'my_demo_request_email';

  // ═══════════════════════════════════════════════════════════════
  // USER: Submit request — starts in 'sending' status
  // ═══════════════════════════════════════════════════════════════
  Future<String> submitRequest({
    required String name,
    required String email,
    String? company,
    String? phone,
    String? reason,
  }) async {
    final doc = await _db.collection(_col).add({
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'company': (company ?? '').trim(),
      'phone': (phone ?? '').trim(),
      'reason': (reason ?? '').trim(),
      'status': 'sending', // 🔑 not visible to admin until email sent
      'requestedAt': FieldValue.serverTimestamp(),
      'platform': kIsWeb ? 'web' : 'mobile',
      'accessCode': null,
      'expiresAt': null,
      'maxUses': 1,
      'usedCount': 0,
      'emailSent': false,
      'emailAttempts': 0,
      'approvalEmailSent': false,
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kReqId, doc.id);
      await prefs.setString(_kReqEmail, email.trim().toLowerCase());
    } catch (_) {}

    return doc.id;
  }

  // ═══════════════════════════════════════════════════════════════
  // USER: Retry email send (kung nag-fail ang Cloud Function)
  // ═══════════════════════════════════════════════════════════════
  Future<void> retryEmailNotification(String requestId) async {
    await _db.collection(_col).doc(requestId).update({
      'status': 'sending',
      'emailError': null,
      'emailAttempts': 0,
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // USER: Watch own request
  // ═══════════════════════════════════════════════════════════════
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRequest(String id) =>
      _db.collection(_col).doc(id).snapshots();

  Future<DocumentSnapshot<Map<String, dynamic>>?> getMyRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kReqId);
      if (id == null || id.isEmpty) return null;
      final snap = await _db.collection(_col).doc(id).get();
      return snap.exists ? snap : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearMyRequest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kReqId);
      await prefs.remove(_kReqEmail);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════
  // USER: Redeem code
  // ═══════════════════════════════════════════════════════════════
  Future<RedeemResult> redeemCode({
    required String requestId,
    required String code,
  }) async {
    try {
      final ref = _db.collection(_col).doc(requestId);
      final snap = await ref.get();
      if (!snap.exists) {
        return const RedeemResult(
            success: false, message: 'Request not found.');
      }
      final data = snap.data()!;
      final status = (data['status'] ?? '').toString();

      if (status == 'rejected') {
        return const RedeemResult(
            success: false, message: 'Your request was rejected.');
      }
      if (status == 'pending' || status == 'sending') {
        return const RedeemResult(
            success: false,
            message: 'Still waiting for admin approval.');
      }
      if (status == 'email_failed') {
        return const RedeemResult(
            success: false,
            message: 'Email delivery failed. Please retry.');
      }
      if (status != 'approved') {
        return RedeemResult(
            success: false, message: 'Request status: $status');
      }

      final storedCode =
      (data['accessCode'] ?? '').toString().trim().toUpperCase();
      if (storedCode.isEmpty ||
          storedCode != code.trim().toUpperCase()) {
        return const RedeemResult(
            success: false, message: 'Invalid access code.');
      }

      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp &&
          expiresAt.toDate().isBefore(DateTime.now())) {
        await ref.update({'status': 'expired'});
        return const RedeemResult(
            success: false,
            message: 'Access code expired. Request a new one.');
      }

      final usedCount = (data['usedCount'] ?? 0) as int;
      final maxUses = (data['maxUses'] ?? 1) as int;
      if (usedCount >= maxUses) {
        await ref.update({'status': 'exhausted'});
        return const RedeemResult(
            success: false, message: 'Access code already used.');
      }

      await ref.update({
        'usedCount': FieldValue.increment(1),
        'lastUsedAt': FieldValue.serverTimestamp(),
      });

      return const RedeemResult(
          success: true, message: 'Access granted.');
    } catch (e) {
      return RedeemResult(
          success: false, message: 'Error: ${e.toString()}');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ADMIN: Streams
  // ═══════════════════════════════════════════════════════════════
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingRequests() {
    return _db
        .collection(_col)
        .where('status', isEqualTo: 'pending')
        .orderBy('requestedAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchAllRequests() {
    return _db
        .collection(_col)
        .orderBy('requestedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  // ═══════════════════════════════════════════════════════════════
  // ADMIN: Approve / Reject
  // ═══════════════════════════════════════════════════════════════
  Future<void> approveRequest({
    required String requestId,
    required String adminUid,
    int validHours = 2,
    int maxUses = 1,
  }) async {
    final code = _generateAccessCode();
    final expiresAt = DateTime.now().add(Duration(hours: validHours));

    await _db.collection(_col).doc(requestId).update({
      'status': 'approved',
      'accessCode': code,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'maxUses': maxUses,
      'usedCount': 0,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminUid,
    });
  }

  Future<void> rejectRequest({
    required String requestId,
    required String adminUid,
    String? reason,
  }) async {
    await _db.collection(_col).doc(requestId).update({
      'status': 'rejected',
      'rejectReason': (reason ?? '').trim(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': adminUid,
    });
  }

  String _generateAccessCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var seed = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(chars[seed % chars.length]);
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    }
    return buf.toString();
  }
}