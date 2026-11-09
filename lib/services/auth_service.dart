// lib/services/auth_service.dart
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import 'database_service.dart';
import 'device_info_service.dart';

/// Thrown when another device already holds a live session for this account.
class DeviceConflictException implements Exception {
  final String deviceModel;
  DeviceConflictException(this.deviceModel);

  @override
  String toString() =>
      'Naka-login ka pa sa $deviceModel. Mag-logout muna doon bago mag-login dito.';
}

class AuthService {
  static AuthService? _instance;
  AuthService._();
  static AuthService get instance => _instance ??= AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Sessions without a heartbeat for this long are treated as dead
  /// (lost phone, uninstalled app) so the user is never locked out forever.
  static const Duration _staleAfter = Duration(hours: 12);
  static const Duration _heartbeatEvery = Duration(minutes: 5);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;
  Timer? _heartbeat;

  /// Fires when this device was signed out because another device took over.
  final StreamController<void> _forcedSignOut =
  StreamController<void>.broadcast();
  Stream<void> get onForcedSignOut => _forcedSignOut.stream;

  User? get currentUser => _auth.currentUser;

  // ─────────────────────────── REGISTER ───────────────────────────
  /// Register a new user with Email and Password
  Future<void> registerEmployee({
    required String email,
    required String password,
    required Employee employee,
  }) async {
    UserCredential result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user == null) throw 'Registration failed: User is null';

    final employeeData = employee.toMap();
    employeeData['uid'] = user.uid;
    employeeData['role'] =
    employee.position.toLowerCase() == 'driver' ? 'driver' : 'user';
    await _firestore.collection('employees').doc(user.uid).set(employeeData);

    await _firestore.collection('activity_logs').add({
      'type': 'registration',
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'timestamp': FieldValue.serverTimestamp(),
      'details': 'New account created via mobile',
      'device': 'Mobile App',
    });

    await DatabaseService.instance.insertEmployee(employee);
  }

  // ───────────────────────────── LOGIN ─────────────────────────────
  /// Login with Email and Password. Enforces one device, one login.
  Future<Employee?> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await DeviceInfoService.instance.getUniqueDeviceId();
    final deviceModel = await DeviceInfoService.instance.getDeviceModel();

    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = result.user;
    if (user == null) return null;

    try {
      final doc = await _firestore.collection('employees').doc(user.uid).get();
      if (!doc.exists) {
        await _auth.signOut();
        return null;
      }
      final employee = Employee.fromMap(doc.data() as Map<String, dynamic>);

      // Atomically claim the session or throw DeviceConflictException.
      await _claimSession(user.uid, deviceId, deviceModel);
      _watchSession(user.uid, deviceId);
      _startHeartbeat(user.uid, deviceId);

      await _firestore.collection('activity_logs').add({
        'type': 'login',
        'uid': user.uid,
        'employee_id': employee.employeeId,
        'employee_name': employee.fullName,
        'timestamp': FieldValue.serverTimestamp(),
        'device': deviceModel,
        'device_id': deviceId,
      });

      await DatabaseService.instance.insertEmployee(employee);
      return employee;
    } catch (_) {
      // Never leave a half-logged-in Firebase session behind.
      _stopSessionTracking();
      await _auth.signOut();
      rethrow;
    }
  }

  // ─────────────────────── SESSION MANAGEMENT ───────────────────────
  /// Call on app start when a persisted Firebase user exists.
  /// Returns true if this device may continue, false if it was signed out.
  Future<bool> resumeSession() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final deviceId = await DeviceInfoService.instance.getUniqueDeviceId();
      final deviceModel = await DeviceInfoService.instance.getDeviceModel();

      await _claimSession(user.uid, deviceId, deviceModel);
      _watchSession(user.uid, deviceId);
      _startHeartbeat(user.uid, deviceId);
      return true;
    } on DeviceConflictException {
      await _auth.signOut();
      return false;
    } catch (_) {
      // Offline or transient error: don't kick the user out.
      return true;
    }
  }

  /// Claims the session in a transaction so two devices can't win at once.
  Future<void> _claimSession(
      String uid,
      String deviceId,
      String deviceModel,
      ) async {
    final ref = _firestore.collection('active_sessions').doc(uid);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);

      if (snap.exists) {
        final data = snap.data()!;
        final activeId = data['device_id'] as String?;
        final lastSeen = (data['last_seen'] as Timestamp?)?.toDate();
        final isStale = lastSeen == null ||
            DateTime.now().difference(lastSeen) > _staleAfter;

        if (activeId != null && activeId != deviceId && !isStale) {
          throw DeviceConflictException(
            (data['device_model'] as String?) ?? 'ibang device',
          );
        }
      }

      tx.set(ref, {
        'device_id': deviceId,
        'device_model': deviceModel,
        'last_seen': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Signs this device out if another device takes over the session,
  /// then notifies the UI through [onForcedSignOut].
  void _watchSession(String uid, String deviceId) {
    _sessionSub?.cancel();
    _sessionSub = _firestore
        .collection('active_sessions')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
      final activeId = snap.data()?['device_id'] as String?;
      if (snap.exists && activeId != null && activeId != deviceId) {
        _stopSessionTracking();
        await _auth.signOut();
        _forcedSignOut.add(null);
      }
    }, onError: (_) {});
  }

  /// Refreshes last_seen only while this device still owns the session.
  void _startHeartbeat(String uid, String deviceId) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) async {
      try {
        final ref = _firestore.collection('active_sessions').doc(uid);
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (snap.exists && snap.data()?['device_id'] == deviceId) {
            tx.update(ref, {'last_seen': FieldValue.serverTimestamp()});
          }
        });
      } catch (_) {
        // Ignore; next tick will retry.
      }
    });
  }

  void _stopSessionTracking() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Releases the session only if this device still owns it.
  Future<void> _releaseSession(String uid, String deviceId) async {
    final ref = _firestore.collection('active_sessions').doc(uid);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists && snap.data()?['device_id'] == deviceId) {
        tx.delete(ref);
      }
    });
  }

  // ─────────────────────────── SIGN OUT ───────────────────────────
  /// Sign out from Firebase, release the session, and log the event.
  Future<void> signOut({Employee? employee}) async {
    final user = _auth.currentUser;
    _stopSessionTracking();

    if (user != null) {
      try {
        final deviceModel = await DeviceInfoService.instance.getDeviceModel();
        final deviceId = await DeviceInfoService.instance.getUniqueDeviceId();

        await _releaseSession(user.uid, deviceId);

        if (employee != null) {
          await _firestore.collection('activity_logs').add({
            'type': 'logout',
            'uid': user.uid,
            'employee_id': employee.employeeId,
            'employee_name': employee.fullName,
            'timestamp': FieldValue.serverTimestamp(),
            'device': deviceModel,
            'device_id': deviceId,
          });
        }
      } catch (_) {
        // Logging/release failure must never block the sign out.
      }
    }
    await _auth.signOut();
  }

  // ───────────────────────── DELETE ACCOUNT ─────────────────────────
  /// Deletes the current user's account and all associated data from
  /// Local Database, Firebase Auth, Firestore, and notifies Admin.
  Future<void> deleteAccount(Employee employee) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No authenticated user found.';

    final String uid = user.uid;
    final String employeeId = employee.id; // Internal SQLite ID
    final String empIdStr = employee.employeeId; // Public ID (e.g. EMP-001)

    await _firestore.collection('activity_logs').add({
      'type': 'account_deletion',
      'uid': uid,
      'employee_id': empIdStr,
      'employee_name': employee.fullName,
      'timestamp': FieldValue.serverTimestamp(),
      'details': 'User permanently deleted their account and data.',
      'device': 'Mobile App',
    });

    _stopSessionTracking();
    await _firestore.collection('active_sessions').doc(uid).delete();
    await _firestore.collection('employees').doc(uid).delete();

    final attendanceDocs = await _firestore
        .collection('attendance_logs')
        .where('employeeId', isEqualTo: empIdStr)
        .get();

    for (var doc in attendanceDocs.docs) {
      await doc.reference.delete();
    }

    await DatabaseService.instance.deleteEmployeeData(employeeId);
    await user.delete();
  }
}