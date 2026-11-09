// lib/services/client_meeting_assignment_service.dart
// ═══════════════════════════════════════════════════════════════════
// v2.0 — Inalis ang composite index requirement.
//        Single-field query lang + client-side filter/sort.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/client_meeting_assignment.dart';

class ClientMeetingAssignmentService {
  ClientMeetingAssignmentService._();
  static final ClientMeetingAssignmentService instance =
  ClientMeetingAssignmentService._();

  final _fs = FirebaseFirestore.instance;
  static const _col = 'client_meeting_assignments';

  // ═══════════════════════════════════════════════════════════════
  // EMPLOYEE SIDE
  // ═══════════════════════════════════════════════════════════════

  /// Get active assignment for an employee.
  ///
  /// ✅ FIX: Single-field query lang (`employee_id`) — walang composite
  ///         index na kailangan. Client-side filter para sa status at
  ///         time window.
  Future<ClientMeetingAssignment?> getActiveAssignmentForEmployee(
      String empId,
      ) async {
    if (empId.isEmpty) {
      debugPrint('⚠️ [AssignmentService] Empty empId');
      return null;
    }

    try {
      debugPrint('🔍 [AssignmentService] Querying for employee_id=$empId');

      // ✅ STEP 1: Try exact match
      var snap = await _fs
          .collection(_col)
          .where('employee_id', isEqualTo: empId)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '📋 [AssignmentService] Exact match: ${snap.docs.length} doc(s)');

      // ✅ STEP 2: Case-insensitive fallback — fetch active & filter
      if (snap.docs.isEmpty) {
        debugPrint('🔄 [AssignmentService] Trying case-insensitive fallback…');
        final allActive = await _fs
            .collection(_col)
            .where('status', isEqualTo: 'active')
            .limit(100)
            .get()
            .timeout(const Duration(seconds: 10));

        final target = empId.toLowerCase().trim();
        final matched = allActive.docs.where((d) {
          final stored =
          (d.data()['employee_id'] ?? '').toString().toLowerCase().trim();
          return stored == target;
        }).toList();

        debugPrint('🔄 [AssignmentService] Fallback matched: '
            '${matched.length} doc(s)');

        if (matched.isNotEmpty) {
          // Create a fake snapshot-like list
          snap = await _fs
              .collection(_col)
              .where('employee_id',
              isEqualTo: matched.first.data()['employee_id'])
              .limit(50)
              .get();
        }
      }

      final now = DateTime.now();
      final candidates = <ClientMeetingAssignment>[];

      for (final doc in snap.docs) {
        try {
          final data = doc.data();
          final a = ClientMeetingAssignment.fromFirestore(data, doc.id);

          if (a.status != AssignmentStatus.active) {
            debugPrint('  ⊘ Skip ${a.id} — status=${a.status.value}');
            continue;
          }

          if (a.shouldAutoExpire) {
            debugPrint('  ⏰ Auto-expiring: ${a.id}');
            _markAsExpired(a.id);
            continue;
          }

          if (!a.isWithinTimeWindow) {
            debugPrint('  ⏱️ Skip ${a.id} — '
                'early=${a.isTooEarly}, late=${a.isTooLate}');
            continue;
          }

          candidates.add(a);
        } catch (e) {
          debugPrint('  ⚠️ Parse error doc ${doc.id}: $e');
        }
      }

      if (candidates.isEmpty) {
        debugPrint('❌ [AssignmentService] No usable assignment for $empId');
        return null;
      }

      candidates.sort(
              (a, b) => a.scheduledStart.compareTo(b.scheduledStart));

      debugPrint('✅ [AssignmentService] Using: ${candidates.first.id} '
          '(${candidates.first.clientName})');

      return candidates.first;
    } catch (e, st) {
      debugPrint('❌ [AssignmentService] getActive error: $e');
      debugPrint('❌ [AssignmentService] Stack: $st');
      return null;
    }
  }

  /// Mark assignment as used, link sa meeting log.
  Future<bool> markAsUsed({
    required String assignmentId,
    required String meetingLogId,
  }) async {
    if (assignmentId.isEmpty) return false;

    try {
      await _fs.collection(_col).doc(assignmentId).update({
        'status': AssignmentStatus.used.value,
        'used_at': FieldValue.serverTimestamp(),
        'meeting_log_id': meetingLogId,
      });
      debugPrint('✅ [AssignmentService] Marked used: $assignmentId');
      return true;
    } catch (e) {
      debugPrint('⚠️ [AssignmentService] markAsUsed error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ADMIN SIDE
  // ═══════════════════════════════════════════════════════════════

  Future<String?> createAssignment({
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String clientId,
    required String clientName,
    required String clientAddress,
    required double clientLat,
    required double clientLng,
    required double clientRadius,
    required String purpose,
    String? notes,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    required String assignedBy,
    required String assignedByName,
    Duration gracePeriod = const Duration(minutes: 15),
  }) async {
    try {
      final assignment = ClientMeetingAssignment(
        id: '',
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
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        gracePeriod: gracePeriod,
        assignedBy: assignedBy,
        assignedByName: assignedByName,
        assignedAt: DateTime.now(),
        status: AssignmentStatus.active,
      );

      final ref = await _fs.collection(_col).add(
        assignment.toMap(includeTimestamp: true),
      );

      debugPrint('✅ [AssignmentService] Created: ${ref.id}');
      return ref.id;
    } catch (e, st) {
      debugPrint('❌ [AssignmentService] createAssignment error: $e');
      debugPrint('❌ [AssignmentService] Stack: $st');
      return null;
    }
  }

  Future<bool> cancelAssignment(String assignmentId) async {
    if (assignmentId.isEmpty) return false;

    try {
      await _fs.collection(_col).doc(assignmentId).update({
        'status': AssignmentStatus.cancelled.value,
        'cancelled_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ [AssignmentService] Cancelled: $assignmentId');
      return true;
    } catch (e) {
      debugPrint('❌ [AssignmentService] cancelAssignment error: $e');
      return false;
    }
  }

  Future<bool> updateAssignment({
    required String assignmentId,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    String? purpose,
    String? notes,
  }) async {
    if (assignmentId.isEmpty) return false;

    try {
      final update = <String, dynamic>{};
      if (scheduledStart != null) {
        update['scheduled_start'] = Timestamp.fromDate(scheduledStart);
      }
      if (scheduledEnd != null) {
        update['scheduled_end'] = Timestamp.fromDate(scheduledEnd);
      }
      if (purpose != null) update['purpose'] = purpose;
      if (notes != null) update['notes'] = notes;
      update['updated_at'] = FieldValue.serverTimestamp();

      await _fs.collection(_col).doc(assignmentId).update(update);
      debugPrint('✅ [AssignmentService] Updated: $assignmentId');
      return true;
    } catch (e) {
      debugPrint('❌ [AssignmentService] updateAssignment error: $e');
      return false;
    }
  }

  /// Get assignments (for management list).
  ///
  /// ✅ FIX: Single-field query lang kung may status filter.
  ///         Walang `orderBy` — client-side sort na lang.
  Future<List<ClientMeetingAssignment>> getAdminAssignments({
    AssignmentStatus? status,
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    int limit = 100,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _fs.collection(_col);

      // Isa lang ang pwede nating i-query para walang index requirement.
      // Priority: employeeId > status
      if (employeeId != null && employeeId.isNotEmpty) {
        q = q.where('employee_id', isEqualTo: employeeId);
      } else if (status != null) {
        q = q.where('status', isEqualTo: status.value);
      }

      final snap = await q
          .limit(limit * 2) // buffer para sa client-side filtering
          .get()
          .timeout(const Duration(seconds: 10));

      var list = snap.docs
          .map((d) => ClientMeetingAssignment.fromFirestore(d.data(), d.id))
          .toList();

      // Client-side filter: status (kung hindi pa na-filter sa query)
      if (status != null && (employeeId == null || employeeId.isEmpty)) {
        list = list.where((a) => a.status == status).toList();
      }

      // Client-side filter: date range
      if (fromDate != null) {
        list = list
            .where((a) => !a.scheduledStart.isBefore(fromDate))
            .toList();
      }
      if (toDate != null) {
        list = list
            .where((a) => !a.scheduledStart.isAfter(toDate))
            .toList();
      }

      // Client-side sort (descending)
      list.sort(
              (a, b) => b.scheduledStart.compareTo(a.scheduledStart));

      // Apply final limit
      if (list.length > limit) list = list.sublist(0, limit);

      return list;
    } catch (e, st) {
      debugPrint('❌ [AssignmentService] getAdminAssignments error: $e');
      debugPrint('❌ [AssignmentService] Stack: $st');
      return [];
    }
  }

  /// Stream version for real-time admin view.
  ///
  /// ✅ FIX: Single-field query lang.
  Stream<List<ClientMeetingAssignment>> streamActiveAssignments() {
    return _fs
        .collection(_col)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ClientMeetingAssignment.fromFirestore(d.data(), d.id))
          .toList();
      list.sort(
              (a, b) => a.scheduledStart.compareTo(b.scheduledStart));
      return list;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _markAsExpired(String assignmentId) async {
    try {
      await _fs.collection(_col).doc(assignmentId).update({
        'status': AssignmentStatus.expired.value,
        'expired_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [AssignmentService] _markAsExpired error: $e');
    }
  }

  /// Bulk auto-expire lahat ng lumampas na.
  Future<int> autoExpireStale() async {
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(hours: 2));

      // ✅ Single-field lang din
      final snap = await _fs
          .collection(_col)
          .where('status', isEqualTo: 'active')
          .get();

      final toExpire = snap.docs.where((doc) {
        final end = doc.data()['scheduled_end'];
        if (end is Timestamp) return end.toDate().isBefore(cutoff);
        return false;
      }).toList();

      if (toExpire.isEmpty) return 0;

      final batch = _fs.batch();
      for (final doc in toExpire) {
        batch.update(doc.reference, {
          'status': AssignmentStatus.expired.value,
          'expired_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      debugPrint('✅ [AssignmentService] Auto-expired ${toExpire.length}');
      return toExpire.length;
    } catch (e) {
      debugPrint('⚠️ [AssignmentService] autoExpireStale error: $e');
      return 0;
    }
  }
}