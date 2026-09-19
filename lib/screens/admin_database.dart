  // lib/screens/admin_database.dart
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:flutter/foundation.dart' show debugPrint;

  class AdminDatabase {
    static final FirebaseFirestore fs = FirebaseFirestore.instance;

    static CollectionReference get employees => fs.collection('employees');
    static CollectionReference get activityLogs => fs.collection('activity logs');
    static CollectionReference get activityLogsUnder =>
        fs.collection('activity_logs');
    static CollectionReference get locations => fs.collection('user locations');
    static CollectionReference get attendanceLogs =>
        fs.collection('attendance_logs');

    static const List<String> allCollections = [
      'activity logs',
      'activity_logs',
      'attendance_logs',
      'clock_ins',
      'clock_outs',
      'employees',
      'leave_applications',
      'pdf_exports',
      'settings',
      'tasks',
      'user_locations',
    ];

    static const List<String> employeeLinkedCollections = [
      'activity logs',
      'activity_logs',
      'attendance_logs',
      'clock_ins',
      'clock_outs',
      'leave_applications',
      'user_locations',
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

    // ─── EMPLOYEES ──────────────────────────────────────────────

    static Stream<List<Map<String, dynamic>>> streamEmployees() {
      try {
        return employees.snapshots().map((s) {
          final list = s.docs
              .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id
          })
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
        final s = await employees.get();
        final list = s.docs
            .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id
        })
            .toList();
        _sortByCreatedAtDesc(list);
        debugPrint('📥 getEmployees: ${list.length} docs from Firestore');
        return list;
      } catch (e) {
        debugPrint('❌ getEmployees ERROR: ${_msg(e)}');
        return [];
      }
    }

    // ─── ACTIVITY LOGS (legacy "activity logs" with space) ──────

    static Stream<List<Map<String, dynamic>>> streamLogs(String type) {
      try {
        return activityLogs
            .where('type', isEqualTo: type)
            .snapshots()
            .map((s) {
          final list = s.docs
              .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id
          })
              .toList();
          _sortByTimestampDesc(list);
          return list;
        }).handleError((e) {
          debugPrint('streamLogs ($type): ${_msg(e)}');
          return <Map<String, dynamic>>[];
        });
      } catch (e) {
        debugPrint('streamLogs setup ($type): ${_msg(e)}');
        return Stream.value([]);
      }
    }

    static Future<List<Map<String, dynamic>>> getLogs(String type) async {
      try {
        final s = await activityLogs.where('type', isEqualTo: type).get();
        final list = s.docs
            .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id
        })
            .toList();
        _sortByTimestampDesc(list);
        debugPrint('📥 getLogs ($type): ${list.length} docs');
        return list;
      } catch (e) {
        debugPrint('getLogs ($type): ${_msg(e)}');
        return [];
      }
    }

    static Future<List<Map<String, dynamic>>> getUserLogs(String empId) async {
      try {
        final s = await activityLogs
            .where('employeeId', isEqualTo: empId)
            .get();
        final list = s.docs
            .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id
        })
            .toList();
        _sortByTimestampDesc(list);
        return list;
      } catch (e) {
        debugPrint('getUserLogs: ${_msg(e)}');
        return [];
      }
    }

    // ══════════════════════════════════════════════════════════════
    // ✅ RECENT ACTIVITY — LIVE STREAM mula sa "activity_logs"
    //    (underscore) at "activity logs" (space), MERGED.
    // ══════════════════════════════════════════════════════════════
    static Stream<List<Map<String, dynamic>>> streamRecentActivity({
      int limit = 30,
    }) {
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
        }).handleError((e) {
          debugPrint('streamRecentActivity: ${_msg(e)}');
          return <Map<String, dynamic>>[];
        });
      } catch (e) {
        debugPrint('streamRecentActivity setup: ${_msg(e)}');
        return Stream.value([]);
      }
    }

    // ══════════════════════════════════════════════════════════════
    // ✅ CLIENT MEETING LOGS — para sa Admin Activity page
    // ══════════════════════════════════════════════════════════════
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
        }).handleError((e) {
          debugPrint('streamClientMeetings: ${_msg(e)}');
          return <Map<String, dynamic>>[];
        });
      } catch (e) {
        debugPrint('streamClientMeetings setup: ${_msg(e)}');
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
        return attendanceLogs.snapshots().map((s) {
          final list = s.docs.map(_convertAttendanceDoc).toList();
          list.sort((a, b) {
            final ta = a['timestamp'] as DateTime?;
            final tb = b['timestamp'] as DateTime?;
            if (ta != null && tb != null) return tb.compareTo(ta);
            return 0;
          });
          return list;
        }).handleError((e) {
          debugPrint('streamAttendanceLogs: ${_msg(e)}');
          return <Map<String, dynamic>>[];
        });
      } catch (e) {
        debugPrint('streamAttendanceLogs setup: ${_msg(e)}');
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
        debugPrint('getAttendanceLogs: ${_msg(e)}');
        return [];
      }
    }

    // ─── LOCATIONS ──────────────────────────────────────────────

    static Stream<List<Map<String, dynamic>>> streamLocations() {
      try {
        return locations.snapshots().map(
              (s) => s.docs
              .map((d) => <String, dynamic>{
            ...(d.data() as Map<String, dynamic>),
            'id': d.id
          })
              .toList(),
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
        return s.docs
            .map((d) => <String, dynamic>{
          ...(d.data() as Map<String, dynamic>),
          'id': d.id
        })
            .toList();
      } catch (e) {
        debugPrint('getLocations: ${_msg(e)}');
        return [];
      }
    }

    // ─── CRUD OPERATIONS ────────────────────────────────────────

    static Future<String?> addEmployee({
      required String employeeId,
      required String firstName,
      required String lastName,
      required String email,
      required String password,
      required String role,
      required String department,
      required String nfcTagId,
      required String pin,
    }) async {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔵 [addEmployee] START');
      debugPrint('   Employee ID: $employeeId');
      debugPrint('   Name: $firstName $lastName');
      debugPrint('   Email: $email');
      debugPrint('   Role: $role');
      debugPrint('   PIN: $pin');
      debugPrint('   NFC: $nfcTagId');
      debugPrint('═══════════════════════════════════════════');

      try {
        final cleanId = employeeId.trim();

        if (cleanId.isEmpty) {
          const msg = 'Employee ID is required.';
          debugPrint('❌ $msg');
          return msg;
        }

        if (cleanId.contains('/') ||
            cleanId.contains('~') ||
            cleanId.contains('*') ||
            cleanId.contains('[') ||
            cleanId.contains(']') ||
            cleanId.contains('.')) {
          const msg =
              'Employee ID cannot contain / ~ * [ ] or . characters.';
          debugPrint('❌ $msg');
          return msg;
        }

        if (cleanId.length > 100) {
          const msg = 'Employee ID is too long (max 100 characters).';
          debugPrint('❌ $msg');
          return msg;
        }

        debugPrint('✅ Employee ID is valid: "$cleanId"');

        debugPrint('🔍 [1/6] Checking duplicate Employee ID...');
        final idCheck = await employees.doc(cleanId).get();
        if (idCheck.exists) {
          final msg = 'Employee ID "$cleanId" is already registered.';
          debugPrint('❌ $msg');
          return msg;
        }
        debugPrint('✅ Employee ID is unique');

        debugPrint('🔍 [2/6] Checking duplicate NFC...');
        if (nfcTagId.isNotEmpty) {
          final nfcCheck = await employees
              .where('nfcTagId', isEqualTo: nfcTagId.toUpperCase())
              .get();
          if (nfcCheck.docs.isNotEmpty) {
            final msg =
                'A keyfob with serial "$nfcTagId" is already registered.';
            debugPrint('❌ $msg');
            return msg;
          }
          debugPrint('✅ NFC is unique');
        }

        debugPrint('🔍 [3/6] Checking duplicate PIN...');
        if (pin.isNotEmpty) {
          final pinCheck =
          await employees.where('pin', isEqualTo: pin).get();
          if (pinCheck.docs.isNotEmpty) {
            final msg =
                'PIN "$pin" is already in use. Please choose another.';
            debugPrint('❌ $msg');
            return msg;
          }
          debugPrint('✅ PIN is unique');
        }

        if (email.isNotEmpty) {
          debugPrint('🔍 [4/6] Checking duplicate email...');
          final emailCheck = await employees
              .where('email', isEqualTo: email.toLowerCase())
              .get();
          if (emailCheck.docs.isNotEmpty) {
            final msg = 'Email "$email" is already registered.';
            debugPrint('❌ $msg');
            return msg;
          }
          debugPrint('✅ Email is unique');
        }

        String authUid = '';
        if (email.isNotEmpty && password.isNotEmpty) {
          debugPrint('🔐 [5/6] Creating Firebase Auth account...');
          try {
            final cred = await FirebaseAuth.instance
                .createUserWithEmailAndPassword(
                email: email, password: password)
                .timeout(const Duration(seconds: 10));
            authUid = cred.user?.uid ?? '';
            debugPrint('✅ Auth created: $authUid');
          } on FirebaseAuthException catch (authErr) {
            if (authErr.code == 'email-already-in-use') {
              debugPrint(
                  '⚠️ Auth account already exists — trying to sign in...');
              try {
                final cred = await FirebaseAuth.instance
                    .signInWithEmailAndPassword(
                    email: email, password: password);
                authUid = cred.user?.uid ?? '';
                debugPrint('✅ Signed in existing Auth: $authUid');
              } catch (e) {
                debugPrint('⚠️ Could not sign in: $e');
              }
            } else {
              debugPrint(
                  '⚠️ Auth error (NON-BLOCKING): ${authErr.code} — ${authErr.message}');
            }
          } catch (e) {
            debugPrint('⚠️ Auth outer error (NON-BLOCKING): $e');
          }
        } else {
          debugPrint('⚠️ Skipping Auth — no email/password provided');
        }

        debugPrint('💾 [6/6] Saving to Firestore with doc ID: "$cleanId"...');
        final docRef = employees.doc(cleanId);

        await docRef.set({
          'employeeId': cleanId,
          'firstName': firstName,
          'lastName': lastName,
          'name': '$firstName $lastName',
          'fullName': '$firstName $lastName',
          'email': email.toLowerCase(),
          'password': password,
          'authUid': authUid,
          'role': role,
          'position': role,
          'department': department,
          'nfcTagId': nfcTagId.toUpperCase(),
          'pin': pin,
          'status': 'active',
          'photoUrl': null,
          'faceEmbedding': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ Firestore save SUCCESS! Doc ID: $cleanId');

        try {
          await activityLogs.add({
            'type': 'registration',
            'employeeId': cleanId,
            'employee_name': '$firstName $lastName',
            'email': email,
            'role': role,
            'department': department,
            'timestamp': FieldValue.serverTimestamp(),
            'device': 'Admin Panel',
          });
          debugPrint('✅ Activity log saved');
        } catch (logErr) {
          debugPrint('⚠️ Activity log failed (non-critical): $logErr');
        }

        debugPrint('🎉 [addEmployee] COMPLETE — Doc ID: $cleanId');
        return null;
      } catch (e) {
        final msg = _msg(e);
        debugPrint('❌ [addEmployee] FAILED: $msg');
        return msg;
      }
    }

    static Future<String?> updateEmployee(
        String docId, Map<String, dynamic> data) async {
      try {
        await employees
            .doc(docId)
            .update({...data, 'updatedAt': FieldValue.serverTimestamp()});
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
    // ✅ WIPE ALL LOGS
    // ══════════════════════════════════════════════════════════════
    static Future<String?> wipeAllLogs({
      List<String>? collections,
    }) async {
      final targets = collections ?? employeeLinkedCollections;
      try {
        for (final collection in targets) {
          await _deleteAll(collection);
        }
        return null;
      } catch (e) {
        return _msg(e);
      }
    }

    // ══════════════════════════════════════════════════════════════
    // ✅ WIPE EVERYTHING
    // ══════════════════════════════════════════════════════════════
    static Future<String?> wipeEverything() async {
      debugPrint('🗑️ [wipeEverything] START — deleting ALL collections');
      try {
        for (final collection in allCollections) {
          debugPrint('   Deleting collection: "$collection"...');
          await _deleteAll(collection);
          debugPrint('   ✅ Deleted: "$collection"');
        }
        debugPrint('🎉 [wipeEverything] COMPLETE — all collections deleted');
        return null;
      } catch (e) {
        final msg = _msg(e);
        debugPrint('❌ [wipeEverything] FAILED: $msg');
        return msg;
      }
    }

    // ─── HELPER: Delete operations ──────────────────────────────

    static Future<void> _deleteWhere(
        String collection, String field, String value) async {
      try {
        final query = fs.collection(collection).where(field, isEqualTo: value);
        await _deleteQueryInBatches(query);
      } catch (e) {
        debugPrint('⚠️ _deleteWhere($collection, $field=$value): $e');
      }
    }

    static Future<void> _deleteAll(String collection) async {
      try {
        final query = fs.collection(collection);
        await _deleteQueryInBatches(query);
      } catch (e) {
        debugPrint('⚠️ _deleteAll($collection): $e');
      }
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

    static Future<String?> backfillPasswords(
        Map<String, String> emailToPassword) async {
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
              final cred = await FirebaseAuth.instance
                  .createUserWithEmailAndPassword(
                  email: email, password: password);
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