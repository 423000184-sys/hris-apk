// lib/screens/admin_database.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AdminDatabase {
  static final FirebaseFirestore fs = FirebaseFirestore.instance;

  static CollectionReference get employees => fs.collection('employees');
  static CollectionReference get activityLogs => fs.collection('activity logs');
  static CollectionReference get activityLogsUnder => fs.collection('activity_logs');
  static CollectionReference get locations => fs.collection('user locations');
  static CollectionReference get attendanceLogs => fs.collection('attendance_logs');
  static CollectionReference get securityEvents => fs.collection('security_events');

  // Hindi isinama: 'admins' at 'config' (admin login at settings; baka ma-lock out ka)
  // Idagdag dito ang iba pang collections na nasa Firebase console mo.
  static const List<String> allCollections = [
    '_time_ping',
    '_time_sync',
    'active_sessions',
    'activity logs',
    'activity_logs',
    'admin_audit_log',
    'admin_audit_logs',
    'admin_login_logs',
    'admin_notifications',
    'attendance_logs',
    'attendance_receipts',
    'client_locations',
    'clock_ins',
    'clock_outs',
    'demo_requests',
    'device_audit',
    'employee_notifications',
    'employee_presence',
    'employees',
    'face_verifications',
    'leave_applications',
    'password_change_requests',
    'pdf_exports',
    'pdf_passwords',
    'presence_challenges',
    'security_events',
    'settings',
    'support_replies',
    'support_reports',
    'tasks',
    'user locations',
    'user_locations',
  ];

  static const List<String> employeeLinkedCollections = [
    'activity logs',
    'activity_logs',
    'attendance_logs',
    'clock_ins',
    'clock_outs',
    'leave_applications',
    'security_events',
    'user_locations',
    'pdf_passwords',
    'face_verifications',
  ];

  static String _msg(Object e) =>
  e is FirebaseException ? (e.message ?? e.toString()) : e.toString();

  // ─── SORT HELPERS ───────────────────────────────────────────
  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ca = a['createdAt'];
      final cb = b['createdAt'];
      if (ca is Timestamp && cb is Timestamp) return cb.compareTo(ca);
      if (ca is Timestamp) return -1;
      if (cb is Timestamp) return 1;
      return 0;
    });
  }

  static void _sortByTimestampDesc(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ca = a['timestamp'];
      final cb = b['timestamp'];
      if (ca is Timestamp && cb is Timestamp) return cb.compareTo(ca);
      if (ca is Timestamp) return -1;
      if (cb is Timestamp) return 1;
      return 0;
    });
  }

  // ══════════════════════════════════════════════════════════════
  // 🔐 FINGERPRINT HELPERS
  // ══════════════════════════════════════════════════════════════
  static bool isFingerprintEnrolled(Map<String, dynamic> e) {
    final v = e['fingerprintEnrolled'];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return false;
  }

  static DateTime? fingerprintEnrolledAt(Map<String, dynamic> e) {
    final v = e['fingerprintEnrolledAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static String fingerprintDeviceOf(Map<String, dynamic> e) {
    final m = (e['fingerprintDeviceModel'] ?? '').toString().trim();
    if (m.isNotEmpty) return m;
    final f = (e['fingerprintDeviceFingerprint'] ?? '').toString().trim();
    if (f.isNotEmpty) return f;
    return '—';
  }

  // ─── EMPLOYEES ──────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamEmployees() {
    try {
      return employees.snapshots().map((s) {
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
        _sortByCreatedAtDesc(list);
        return list;
      }).handleError((e) {
        debugPrint('❌ streamEmployees ERROR: ${_msg(e)}');
      });
    } catch (e) {
      return Stream.value([]);
    }
  }

  static Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final s = await employees.get();
      final list = s.docs
      .map((d) => <String, dynamic>{
        ...(d.data() as Map<String, dynamic>),
        'id': d.id,
      })
      .toList();
      _sortByCreatedAtDesc(list);
      return list;
    } catch (e) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 🔐 FINGERPRINT: Streams / Queries
  // ══════════════════════════════════════════════════════════════
  static Stream<List<Map<String, dynamic>>> streamFingerprintEnrolled() {
    try {
      return employees
      .where('fingerprintEnrolled', isEqualTo: true)
      .snapshots()
      .map((s) {
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
        _sortByCreatedAtDesc(list);
        return list;
      }).handleError((e) => <Map<String, dynamic>>[]);
    } catch (e) {
      return Stream.value([]);
    }
  }

  static Stream<List<Map<String, dynamic>>> streamFingerprintNotEnrolled() {
    try {
      return employees.snapshots().map((s) {
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .where((e) => !isFingerprintEnrolled(e))
        .toList();
        _sortByCreatedAtDesc(list);
        return list;
      }).handleError((e) => <Map<String, dynamic>>[]);
    } catch (e) {
      return Stream.value([]);
    }
  }

  static Future<Map<String, int>> getFingerprintStats() async {
    try {
      final snap = await employees.get();
      int enrolled = 0;
      int notEnrolled = 0;
      int terminated = 0;

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['terminated'] == true) {
          terminated++;
          continue;
        }
        if (isFingerprintEnrolled(data)) {
          enrolled++;
        } else {
          notEnrolled++;
        }
      }
      return {
        'enrolled': enrolled,
        'notEnrolled': notEnrolled,
        'terminated': terminated,
        'total': enrolled + notEnrolled,
      };
    } catch (e) {
      return {'enrolled': 0, 'notEnrolled': 0, 'terminated': 0, 'total': 0};
    }
  }

  static Future<String?> resetEmployeeFingerprint(
    String docId, {
      String? reason,
      String? performedBy,
    }) async {
      try {
        if (docId.isEmpty) return 'Invalid employee ID.';
        final ref = employees.doc(docId);
        final snap = await ref.get();
        if (!snap.exists) return 'Employee not found.';
        final data = snap.data() as Map<String, dynamic>? ?? {};

        await ref.set({
          'fingerprintEnrolled': false,
          'fingerprintEnrolledAt': null,
          'fingerprintDeviceModel': null,
          'fingerprintDeviceBinding': null,
          'fingerprintDeviceFingerprint': null,
          'fingerprintResetAt': FieldValue.serverTimestamp(),
          'fingerprintResetBy': performedBy ?? 'admin',
          'fingerprintResetReason': reason ?? 'manual reset',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        try {
          await activityLogsUnder.add({
            'type': 'fingerprint_reset',
            'action': 'Fingerprint Reset',
            'employeeId': docId,
            'employee_id': (data['employeeId'] ?? docId).toString(),
            'employee_name': (data['name'] ?? data['fullName'] ?? 'Unknown').toString(),
            'resetBy': performedBy ?? 'admin',
            'reason': reason ?? 'manual reset',
            'timestamp': FieldValue.serverTimestamp(),
            'device': 'Admin Panel',
          });
        } catch (_) {}

        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    static Future<Map<String, dynamic>> resetAllFingerprints({
      String? performedBy,
      bool onlyEnrolled = true,
    }) async {
      final result = <String, dynamic>{'success': false, 'resetCount': 0, 'error': null};
      try {
        const int pageSize = 50;
        const int batchLimit = 400;
        int count = 0;
        WriteBatch batch = fs.batch();
        DocumentSnapshot? last;

        Query base = employees;
        if (onlyEnrolled) {
          base = base.where('fingerprintEnrolled', isEqualTo: true);
        }

        Future<void> commitIfNeeded({bool force = false}) async {
          if (count >= batchLimit || (force && count > 0)) {
            await batch.commit();
            batch = fs.batch();
            count = 0;
          }
        }

        while (true) {
          Query q = base.orderBy(FieldPath.documentId).limit(pageSize);
          if (last != null) q = q.startAfterDocument(last);

          final snap = await q.get();
          if (snap.docs.isEmpty) break;
          last = snap.docs.last;

          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['terminated'] == true) continue;
            if (onlyEnrolled && data['fingerprintEnrolled'] != true) continue;

            batch.set(
              doc.reference,
              {
                'fingerprintEnrolled': false,
                'fingerprintEnrolledAt': null,
                'fingerprintDeviceModel': null,
                'fingerprintDeviceBinding': null,
                'fingerprintDeviceFingerprint': null,
                'fingerprintResetAt': FieldValue.serverTimestamp(),
                'fingerprintResetBy': performedBy ?? 'admin',
                'fingerprintResetReason': 'bulk reset',
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            count++;
            result['resetCount'] = (result['resetCount'] as int) + 1;
            await commitIfNeeded();
          }
          if (snap.docs.length < pageSize) break;
        }
        await commitIfNeeded(force: true);
        result['success'] = true;
        return result;
      } catch (e) {
        result['error'] = _msg(e);
        return result;
      }
    }

    static Stream<List<Map<String, dynamic>>> streamFingerprintEvents({int limit = 50}) {
      try {
        return activityLogsUnder
        .where('type', whereIn: [
          'fingerprint_registered',
          'fingerprint_verified',
          'fingerprint_reset',
          'fingerprint_bulk_reset',
        ])
        .limit(limit)
        .snapshots()
        .map((s) {
          final list = s.docs
          .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          })
          .toList();
          _sortByTimestampDesc(list);
          return list;
        }).handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    static Future<List<Map<String, dynamic>>> getFingerprintEvents({int limit = 100}) async {
      try {
        final s = await activityLogsUnder
        .where('type', whereIn: [
          'fingerprint_registered',
          'fingerprint_verified',
          'fingerprint_reset',
          'fingerprint_bulk_reset',
        ])
        .limit(limit)
        .get();
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
        _sortByTimestampDesc(list);
        return list;
      } catch (e) {
        return [];
      }
    }

    // ─── ACTIVITY LOGS ──────
    static Stream<List<Map<String, dynamic>>> streamLogs(String type) {
      try {
        return activityLogs.where('type', isEqualTo: type).snapshots().map((s) {
          final list = s.docs
          .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          })
          .toList();
          _sortByTimestampDesc(list);
          return list;
        }).handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    static Future<List<Map<String, dynamic>>> getLogs(String type) async {
      try {
        final s = await activityLogs.where('type', isEqualTo: type).get();
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
        _sortByTimestampDesc(list);
        return list;
      } catch (e) {
        return [];
      }
    }

    static Future<List<Map<String, dynamic>>> getUserLogs(String empId) async {
      try {
        final s = await activityLogs.where('employeeId', isEqualTo: empId).get();
        final list = s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
        _sortByTimestampDesc(list);
        return list;
      } catch (e) {
        return [];
      }
    }

    static Stream<List<Map<String, dynamic>>> streamRecentActivity({int limit = 30}) {
      try {
        return activityLogsUnder
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) {
          final list = s.docs
          .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          })
          .toList();
          _sortByTimestampDesc(list);
          return list;
        }).handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    // ─── CLIENT MEETING LOGS ──────
    static Stream<List<Map<String, dynamic>>> streamClientMeetings() {
      try {
        return attendanceLogs
        .where('type', isEqualTo: 'client_meeting')
        .snapshots()
        .map((s) {
          final list = s.docs
          .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id,
          })
          .toList();
          _sortByTimestampDesc(list);
          return list;
        }).handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    static Future<String?> approveClientMeeting(String docId) async {
      try {
        await attendanceLogs.doc(docId).update({
          'status': 'approved',
          'payrollStatus': 'Approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'reviewedBy': 'admin',
        });
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    static Future<String?> rejectClientMeeting(String docId) async {
      try {
        await attendanceLogs.doc(docId).update({
          'status': 'rejected',
          'payrollStatus': 'Rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'reviewedBy': 'admin',
        });
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    // ─── ATTENDANCE LOGS ──────
    static Map<String, dynamic> _convertAttendanceDoc(DocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;
      DateTime? ts;
      final timestampVal = data['timestamp'];
      if (timestampVal is Timestamp) {
        ts = timestampVal.toDate();
      } else if (timestampVal is String) {
        final dateStr = data['date'] as String?;
        final timeStr = data['time'] as String?;
        if (dateStr != null && timeStr != null) {
          try {
            ts = DateTime.parse('$dateStr $timeStr');
          } catch (_) {}
        } else {
          try {
            ts = DateTime.parse(timestampVal);
          } catch (_) {}
        }
      }
      return {...data, 'id': doc.id, 'timestamp': ts};
    }

    static Stream<List<Map<String, dynamic>>> streamAttendanceLogs() {
      try {
        return attendanceLogs.snapshots().map((s) {
          final list = s.docs.map(_convertAttendanceDoc).toList();
          list.sort((a, b) {
            final ta = a['timestamp'] as DateTime?;
            final tb = b['timestamp'] as DateTime?;
            if (ta != null && tb != null) return tb.compareTo(ta);
            return 0;
          });
          return list;
        }).handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    static Future<List<Map<String, dynamic>>> getAttendanceLogs() async {
      try {
        final s = await attendanceLogs.get();
        final list = s.docs.map(_convertAttendanceDoc).toList();
        list.sort((a, b) {
          final ta = a['timestamp'] as DateTime?;
          final tb = b['timestamp'] as DateTime?;
          if (ta != null && tb != null) return tb.compareTo(ta);
          return 0;
        });
        return list;
      } catch (e) {
        return [];
      }
    }

    // ─── LOCATIONS ──────
    static Stream<List<Map<String, dynamic>>> streamLocations() {
      try {
        return locations
        .snapshots()
        .map((s) => s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList())
        .handleError((e) => <Map<String, dynamic>>[]);
      } catch (e) {
        return Stream.value([]);
      }
    }

    static Future<List<Map<String, dynamic>>> getLocations() async {
      try {
        final s = await locations.get();
        return s.docs
        .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id,
        })
        .toList();
      } catch (e) {
        return [];
      }
    }

    // ─── CRUD OPERATIONS ──────
    static Future<String?> updateEmployee(String docId, Map<String, dynamic> data) async {
      try {
        await employees.doc(docId).update({...data, 'updatedAt': FieldValue.serverTimestamp()});
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    static Future<String?> deleteEmployee(String docId) async {
      try {
        for (final collection in employeeLinkedCollections) {
          await _deleteWhere(collection, 'employeeId', docId);
        }
        await employees.doc(docId).delete();
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    static Future<String?> deleteLog(String docId) async {
      try {
        await activityLogs.doc(docId).delete();
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    // ✅ WIPE METHODS
    // ══════════════════════════════════════════════════════════════
    static Future<String?> wipeAllLogs({List<String>? collections}) async {
      final targets = collections ?? employeeLinkedCollections;
      try {
        await Future.wait(targets.map((collection) async {
          await _deleteAll(collection);
        }));
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    /// Deletes every collection in [allCollections]; reports per-collection
    /// failures and verifies that nothing is left behind.
    static Future<String?> wipeEverything() async {
      final failed = <String>[];
      final leftover = <String>[];

      await Future.wait(allCollections.map((name) async {
        try {
          await _deleteAll(name);
          final remaining = await fs.collection(name).limit(1).get();
          if (remaining.docs.isNotEmpty) leftover.add(name);
        } catch (e) {
          failed.add('$name: ${_msg(e)}');
        }
      }));

      if (failed.isEmpty && leftover.isEmpty) return null;
      return [
        if (failed.isNotEmpty) 'Failed: ${failed.join('; ')}',
          if (leftover.isNotEmpty) 'Still has data: ${leftover.join(', ')}',
      ].join(' | ');
    }

    static Future<String?> wipeSelected(List<String> selectedCategories) async {
      try {
        final Set<String> collectionsToDelete = {};

        for (final category in selectedCategories) {
          switch (category) {
            case 'All Employees':
              collectionsToDelete.add('employees');
              break;
            case 'All Activity Logs':
              collectionsToDelete.addAll(['activity logs', 'activity_logs']);
              break;
            case 'All Attendance Records':
              collectionsToDelete.addAll(['attendance_logs', 'clock_ins', 'clock_outs']);
              break;
            case 'All Location Tracking Data':
              collectionsToDelete.addAll(['user_locations', 'user locations', 'presence_challenges']);
              break;
            case 'All Leave Applications':
              collectionsToDelete.add('leave_applications');
              break;
            case 'All PDF Exports':
              collectionsToDelete.add('pdf_exports');
              break;
            case 'All Security Events':
              collectionsToDelete.add('security_events');
              break;
            case 'All Settings & Configs':
              collectionsToDelete.addAll(['settings', 'demo_requests', 'device_audit']);
              break;
            case 'All Task Records':
              collectionsToDelete.add('tasks');
              break;
            case 'All Fingerprint Registrations':
              await resetAllFingerprints(performedBy: 'admin', onlyEnrolled: true);
              break;
            case 'All Face Registrations':
              collectionsToDelete.add('face_verifications');
              break;
            default:
              continue;
          }
        }

        final failed = <String>[];
        await Future.wait(collectionsToDelete.map((collectionName) async {
          try {
            await _deleteQueryInBatches(
              fs.collection(collectionName),
              chunkSize: collectionName == 'employees' ? 50 : 300,
            );
          } catch (e) {
            failed.add('$collectionName: ${_msg(e)}');
          }
        }));

        if (failed.isNotEmpty) return 'Failed: ${failed.join('; ')}';
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    // ─── HELPER: Delete operations (Pipelined) ───
    static Future<void> _deleteWhere(String collection, String field, String value) async {
      final query = fs.collection(collection).where(field, isEqualTo: value);
      await _deleteQueryInBatches(query, chunkSize: collection == 'employees' ? 50 : 300);
    }

    static Future<void> _deleteAll(String collection) async {
      await _deleteQueryInBatches(
        fs.collection(collection),
        chunkSize: collection == 'employees' ? 50 : 300,
      );
    }

    static Future<void> _deleteQueryInBatches(
      Query query, {
        int chunkSize = 300,
        int maxInFlight = 4,
      }) async {
        final inFlight = <Future<void>>[];
        DocumentSnapshot? last;

        while (true) {
          Query q = query.orderBy(FieldPath.documentId).limit(chunkSize);
          if (last != null) q = q.startAfterDocument(last);

          final snapshot = await q.get();
          if (snapshot.docs.isEmpty) break;
          last = snapshot.docs.last;

          final batch = fs.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          inFlight.add(batch.commit());

          if (inFlight.length >= maxInFlight) {
            await Future.wait(inFlight);
            inFlight.clear();
          }
          if (snapshot.docs.length < chunkSize) break;
        }
        await Future.wait(inFlight);
      }

      // ══════════════════════════════════════════════════════════════
      // 🔐 BACKFILLS
      // ══════════════════════════════════════════════════════════════
      static Future<String?> backfillPasswords(Map<String, String> emailToPassword) async {
        try {
          const int pageSize = 50;
          int count = 0;
          DocumentSnapshot? last;

          while (true) {
            Query q = employees.orderBy(FieldPath.documentId).limit(pageSize);
            if (last != null) q = q.startAfterDocument(last);

            final snap = await q.get();
            if (snap.docs.isEmpty) break;
            last = snap.docs.last;

            for (final doc in snap.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final email = (data['email'] ?? '').toString().trim();
              final existing = (data['password'] ?? '').toString().trim();

              if (existing.isNotEmpty) continue;
              final password = emailToPassword[email];
              if (password == null || password.isEmpty) continue;

              await doc.reference.update({'password': password});
              String authUid = (data['authUid'] ?? '').toString();

              if (authUid.isEmpty && email.isNotEmpty) {
                try {
                  final cred = await FirebaseAuth.instance
                  .createUserWithEmailAndPassword(email: email, password: password);
                  authUid = cred.user?.uid ?? '';
                  await doc.reference.update({'authUid': authUid});
                } catch (_) {}
              }
              count++;
            }
            if (snap.docs.length < pageSize) break;
          }
          return 'Backfill complete: $count employee(s) updated.';
        } catch (e) {
          return 'Backfill error: ${_msg(e)}';
        }
      }

      static Future<String?> backfillFingerprintDefaults() async {
        try {
          const int pageSize = 50;
          const int batchLimit = 400;
          int count = 0;
          WriteBatch batch = fs.batch();
          DocumentSnapshot? last;

          Future<void> commitIfNeeded({bool force = false}) async {
            if (count >= batchLimit || (force && count > 0)) {
              await batch.commit();
              batch = fs.batch();
              count = 0;
            }
          }

          while (true) {
            Query q = employees.orderBy(FieldPath.documentId).limit(pageSize);
            if (last != null) q = q.startAfterDocument(last);

            final snap = await q.get();
            if (snap.docs.isEmpty) break;
            last = snap.docs.last;

            for (final doc in snap.docs) {
              final data = doc.data() as Map<String, dynamic>;
              if (data.containsKey('fingerprintEnrolled')) continue;

              batch.set(
                doc.reference,
                {
                  'fingerprintEnrolled': false,
                  'fingerprintEnrolledAt': null,
                  'fingerprintDeviceModel': null,
                  'fingerprintDeviceBinding': null,
                  'fingerprintDeviceFingerprint': null,
                },
                SetOptions(merge: true),
              );
              count++;
              await commitIfNeeded();
            }
            if (snap.docs.length < pageSize) break;
          }
          await commitIfNeeded(force: true);
          return 'Backfill complete: $count employee(s) updated.';
        } catch (e) {
          return 'Backfill error: ${_msg(e)}';
        }
      }
}
