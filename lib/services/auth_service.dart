// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/employee.dart';
import 'database_service.dart';

class AuthService {
  static AuthService? _instance;
  AuthService._();
  static AuthService get instance => _instance ??= AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  /// Register a new user with Email and Password
  Future<void> registerEmployee({
    required String email,
    required String password,
    required Employee employee,
  }) async {
    // 1. Create user in Firebase Auth
    UserCredential result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user == null) throw 'Registration failed: User is null';

    // 2. Save detailed profile to Firestore
    final employeeData = employee.toMap();
    employeeData['uid'] = user.uid;
    employeeData['role'] = employee.position.toLowerCase() == 'driver' ? 'driver' : 'user';
    await _firestore.collection('employees').doc(user.uid).set(employeeData);

    // 3. Create a registration activity log
    await _firestore.collection('activity_logs').add({
      'type': 'registration',
      'employee_id': employee.employeeId,
      'employee_name': employee.fullName,
      'timestamp': FieldValue.serverTimestamp(),
      'details': 'New account created via mobile',
      'device': 'Mobile App',
    });

    // 4. Save to Local SQLite
    await DatabaseService.instance.insertEmployee(employee);
  }

  /// Login with Email and Password
  Future<Employee?> login({
    required String email,
    required String password,
  }) async {
    // 1. Sign in with Firebase Auth
    UserCredential result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    User? user = result.user;
    if (user == null) return null;

    // 2. Fetch employee data
    DocumentSnapshot doc = await _firestore.collection('employees').doc(user.uid).get();
    
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final employee = Employee.fromMap(data);
      
      // 3. Log the login event
      await _firestore.collection('activity_logs').add({
        'type': 'login',
        'uid': user.uid,
        'employee_id': employee.employeeId,
        'employee_name': employee.fullName,
        'timestamp': FieldValue.serverTimestamp(),
        'device': 'Mobile App',
      });

      // 4. Sync/Update Local SQLite
      await DatabaseService.instance.insertEmployee(employee);
      
      return employee;
    }
    return null;
  }

  /// Sign out from Firebase and log the event
  Future<void> signOut({Employee? employee}) async {
    final user = _auth.currentUser;
    if (user != null && employee != null) {
      try {
        await _firestore.collection('activity_logs').add({
          'type': 'logout',
          'uid': user.uid,
          'employee_id': employee.employeeId,
          'employee_name': employee.fullName,
          'timestamp': FieldValue.serverTimestamp(),
          'device': 'Mobile App',
        });
      } catch (e) {
        print('Error logging logout: $e');
      }
    }
    await _auth.signOut();
  }

  /// Deletes the current user's account and all associated data from 
  /// Local Database, Firebase Auth, Firestore, and notifies Admin.
  Future<void> deleteAccount(Employee employee) async {
    final user = _auth.currentUser;
    if (user == null) throw 'No authenticated user found.';

    final String uid = user.uid;
    final String employeeId = employee.id; // Internal SQLite ID
    final String empIdStr = employee.employeeId; // Public Employee ID (e.g. EMP-001)

    // 1. Log the deletion event for Admin audit
    await _firestore.collection('activity_logs').add({
      'type': 'account_deletion',
      'uid': uid,
      'employee_id': empIdStr,
      'employee_name': employee.fullName,
      'timestamp': FieldValue.serverTimestamp(),
      'details': 'User permanently deleted their account and data.',
      'device': 'Mobile App',
    });

    // 2. Delete data from Firestore (Employee Profile)
    await _firestore.collection('employees').doc(uid).delete();

    // 3. Delete attendance records from Firestore (if synced)
    final attendanceDocs = await _firestore
        .collection('attendance')
        .where('employee_id', isEqualTo: employeeId)
        .get();
    
    for (var doc in attendanceDocs.docs) {
      await doc.reference.delete();
    }

    // 4. Delete from Local SQLite Database
    await DatabaseService.instance.deleteEmployeeData(employeeId);

    // 5. Finally, delete from Firebase Auth
    await user.delete();
  }
}
