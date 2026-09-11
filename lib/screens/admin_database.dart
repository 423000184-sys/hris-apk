import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AdminDatabase {
  static final FirebaseFirestore fs = FirebaseFirestore.instance;

  static CollectionReference get employees => fs.collection('employees');
  static CollectionReference get activityLogs => fs.collection('activity logs');
  static CollectionReference get locations => fs.collection('user locations');
  static CollectionReference get attendanceLogs => fs.collection('attendance_logs');

  static const List<String> employeeLinkedCollections = [
    'activity_logs',
    'attendance_logs',
    'clock_ins',
    'clock_outs',
    'leave_applications',
    'user_locations',
  ];

  static String _msg(Object e) => e is FirebaseException ? (e.message ?? e.toString()) : e.toString();

  // ─── SORT HELPER (client-side, safe kahit walang createdAt) ──

  static void _sortByCreatedAtDesc(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final ca = a['createdAt'];
      final cb = b['createdAt'];
      if (ca is Timestamp && cb is Timestamp) return cb.compareTo(ca);
      if (ca is Timestamp) return -1; // may createdAt muna sa taas
      if (cb is Timestamp) return 1;
      return 0; // pareho walang createdAt, huwag baguhin ang order
    });
  }

  // ─── EMPLOYEES ──────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamEmployees() {
    try {
      return employees.snapshots().map((s) {
        final list = s.docs
            .map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id})
            .toList();
        _sortByCreatedAtDesc(list);
        debugPrint('📡 streamEmployees: ${list.length} docs from Firestore');
        return list;
      }).handleError((e) {
        debugPrint('❌ streamEmployees ERROR: ${_msg(e)}');
      });
    } catch (e) {
      debugPrint('❌ streamEmployees setup ERROR: ${_msg(e)}');
      return Stream.value([]);
    }
  }

  static Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final s = await employees.get(); // walang orderBy sa query mismo — kinukuha LAHAT
      final list = s.docs
          .map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id})
          .toList();
      _sortByCreatedAtDesc(list);
      debugPrint('📥 getEmployees: ${list.length} docs from Firestore');
      return list;
    } catch (e) {
      debugPrint('❌ getEmployees ERROR: ${_msg(e)}');
      return [];
    }
  }

  // ─── ACTIVITY LOGS ──────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamLogs(String type) {
    try {
      return activityLogs
          .where('type', isEqualTo: type)
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList())
          .handleError((e) {
        debugPrint('streamLogs ($type): ${_msg(e)}');
      });
    } catch (e) {
      debugPrint('streamLogs setup ($type): ${_msg(e)}');
      return Stream.value([]);
    }
  }

  static Future<List<Map<String, dynamic>>> getLogs(String type) async {
    try {
      final s = await activityLogs.where('type', isEqualTo: type).orderBy('timestamp', descending: true).get();
      return s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('getLogs ($type): ${_msg(e)}');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserLogs(String empId) async {
    try {
      final s = await activityLogs.where('employeeId', isEqualTo: empId).orderBy('timestamp', descending: true).get();
      return s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('getUserLogs: ${_msg(e)}');
      return [];
    }
  }

  // ─── ATTENDANCE LOGS ────────────────────────────────────────

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

    return {
      ...data,
      'id': doc.id,
      'timestamp': ts,
    };
  }

  static Stream<List<Map<String, dynamic>>> streamAttendanceLogs() {
    try {
      return attendanceLogs
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((s) => s.docs.map(_convertAttendanceDoc).toList())
          .handleError((e) {
        debugPrint('streamAttendanceLogs: ${_msg(e)}');
      });
    } catch (e) {
      debugPrint('streamAttendanceLogs setup: ${_msg(e)}');
      return Stream.value([]);
    }
  }

  static Future<List<Map<String, dynamic>>> getAttendanceLogs() async {
    try {
      final s = await attendanceLogs.orderBy('timestamp', descending: true).get();
      return s.docs.map(_convertAttendanceDoc).toList();
    } catch (e) {
      debugPrint('getAttendanceLogs: ${_msg(e)}');
      return [];
    }
  }

  // ─── LOCATIONS ──────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamLocations() {
    try {
      return locations.snapshots().map(
            (s) => s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList(),
      ).handleError((e) {
        debugPrint('streamLocations: ${_msg(e)}');
      });
    } catch (e) {
      debugPrint('streamLocations setup: ${_msg(e)}');
      return Stream.value([]);
    }
  }

  static Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      final s = await locations.get();
      return s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('getLocations: ${_msg(e)}');
      return [];
    }
  }

  // ─── CRUD OPERATIONS ────────────────────────────────────────

  static Future<String?> addEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String department,
    required String nfcTagId,
    required String pin,
  }) async {
    try {
      final nfcCheck = await employees.where('nfcTagId', isEqualTo: nfcTagId.toUpperCase()).get();
      if (nfcCheck.docs.isNotEmpty) return 'A keyfob with serial "$nfcTagId" is already registered.';

      final pinCheck = await employees.where('pin', isEqualTo: pin).get();
      if (pinCheck.docs.isNotEmpty) return 'PIN "$pin" is already in use.';

      String authUid = '';
      if (email.isNotEmpty && password.isNotEmpty) {
        try {
          final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
          authUid = cred.user?.uid ?? '';
        } catch (authErr) {
          if (authErr is FirebaseAuthException && authErr.code == 'email-already-in-use') {
            debugPrint('Auth account already exists for $email; continuing.');
          } else {
            return 'Firebase Auth error: $authErr';
          }
        }
      }

      final docRef = await employees.add({
        'firstName': firstName,
        'lastName': lastName,
        'name': '$firstName $lastName',
        'email': email,
        'password': password,
        'authUid': authUid,
        'role': role,
        'department': department,
        'nfcTagId': nfcTagId.toUpperCase(),
        'pin': pin,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await activityLogs.add({
        'type': 'registration',
        'employeeId': docRef.id,
        'employee_name': '$firstName $lastName',
        'email': email,
        'role': role,
        'department': department,
        'timestamp': FieldValue.serverTimestamp(),
        'device': 'Admin Panel',
      });

      return null;
    } catch (e) {
      return _msg(e);
    }
  }

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

  static Future<String?> wipeAllLogs({
    List<String> collections = employeeLinkedCollections,
  }) async {
    try {
      for (final collection in collections) {
        await _deleteAll(collection);
      }
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  static Future<String?> wipeEverything() async {
    try {
      for (final collection in employeeLinkedCollections) {
        await _deleteAll(collection);
      }
      await _deleteAll('employees');
      return null;
    } catch (e) {
      return _msg(e);
    }
  }

  static Future<void> _deleteWhere(String collection, String field, String value) async {
    final query = fs.collection(collection).where(field, isEqualTo: value);
    await _deleteQueryInBatches(query);
  }

  static Future<void> _deleteAll(String collection) async {
    final query = fs.collection(collection);
    await _deleteQueryInBatches(query);
  }

  static Future<void> _deleteQueryInBatches(Query query) async {
    const chunkSize = 400;
    while (true) {
      final snapshot = await query.limit(chunkSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = fs.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < chunkSize) break;
    }
  }

  static Future<String?> backfillPasswords(Map<String, String> emailToPassword) async {
    try {
      final snap = await employees.get();
      int count = 0;
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
            final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
            authUid = cred.user?.uid ?? '';
            await doc.reference.update({'authUid': authUid});
          } catch (authErr) {
            debugPrint('Auth backfill warning for $email: $authErr');
          }
        }
        count++;
      }
      return 'Backfill complete: $count employee(s) updated.';
    } catch (e) {
      return 'Backfill error: ${_msg(e)}';
    }
  }
}