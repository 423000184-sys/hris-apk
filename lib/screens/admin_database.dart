import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AdminDatabase {
  static final FirebaseFirestore fs = FirebaseFirestore.instance;

  static CollectionReference get employees => fs.collection('employees');
  static CollectionReference get activityLogs => fs.collection('activity logs');
  static CollectionReference get locations => fs.collection('user locations');

<<<<<<< HEAD
  // NOTE: These match the collection names actually seen in your Firestore
  // console (underscores), which differ from the space-named collections
  // above ('activity logs' / 'user locations'). If those space-named getters
  // are meant to point at the same underscore collections, let me know and
  // I'll fix them too — for now this list is kept separate so the new
  // delete/wipe logic reaches your real data.
  static const List<String> employeeLinkedCollections = [
    'activity_logs',
    'attendance_logs',
    'clock_ins',
    'clock_outs',
    'leave_applications',
    'user_locations',
  ];

  static String _msg(Object e) => e is FirebaseException ? (e.message ?? e.toString()) : e.toString();

  // --- STREAMS WITH ERROR HANDLING ---

  static Stream<List<Map<String, dynamic>>> streamEmployees() {
    try {
      return employees.orderBy('createdAt', descending: true).snapshots().map(
            (s) => s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList(),
      ).handleError((e) {
        debugPrint('streamEmployees: ${_msg(e)}');
      });
    } catch (e) {
      debugPrint('streamEmployees setup: ${_msg(e)}');
      return Stream.value([]);
    }
  }

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

  // --- FUTURES & QUERIES ---

=======
  static String _msg(Object e) => e is FirebaseException ? (e.message ?? e.toString()) : e.toString();

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  static Future<List<Map<String, dynamic>>> getEmployees() async {
    try {
      final s = await employees.orderBy('createdAt', descending: true).get();
      return s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('getEmployees: ${_msg(e)}');
      return [];
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

  static Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      final s = await locations.get();
      return s.docs.map((d) => <String, dynamic>{...(d.data() as Map<String, dynamic>), 'id': d.id}).toList();
    } catch (e) {
      debugPrint('getLocations: ${_msg(e)}');
      return [];
    }
  }

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

<<<<<<< HEAD
  /// Deletes an employee AND cascades delete to every record in
  /// [employeeLinkedCollections] that references their employeeId.
  static Future<String?> deleteEmployee(String docId) async {
    try {
      for (final collection in employeeLinkedCollections) {
        await _deleteWhere(collection, 'employeeId', docId);
      }
=======
  static Future<String?> deleteEmployee(String docId) async {
    try {
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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

<<<<<<< HEAD
  /// Wipes every document out of the given collections entirely.
  /// Defaults to all employee-linked log collections. IRREVERSIBLE —
  /// only call this after the UI has confirmed with the admin.
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

  /// Wipes every employee AND every log collection — a full reset.
  /// IRREVERSIBLE — only call after the UI confirms with the admin[cite: 2].
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
    const chunkSize = 400; // stay under Firestore's 500-write batch limit
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

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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