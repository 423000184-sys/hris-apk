// lib/security/admin_guard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Wraps admin-only pages. Verifies custom claim `admin == true`
/// AND logs the access attempt (success or denied).
class AdminGuard extends StatefulWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  late Future<bool> _check;

  @override
  void initState() {
    super.initState();
    _check = _verifyAndAudit();
  }

  Future<bool> _verifyAndAudit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await _audit(user: null, granted: false, reason: 'no_session');
      return false;
    }

    try {
      // Force refresh para makuha ang latest custom claims
      final token = await user.getIdTokenResult(true);
      final isAdmin = token.claims?['admin'] == true;

      await _audit(
        user: user,
        granted: isAdmin,
        reason: isAdmin ? 'granted' : 'missing_admin_claim',
      );
      return isAdmin;
    } catch (_) {
      await _audit(user: user, granted: false, reason: 'verify_error');
      return false;
    }
  }

  Future<void> _audit({
    required User? user,
    required bool granted,
    required String reason,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('admin_audit').add({
        'action': 'ADMIN_OVERVIEW_ACCESS',
        'granted': granted,
        'reason': reason,
        'admin_uid': user?.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silent fail — huwag i-block ang UI kung audit fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != true) {
          return const Scaffold(
            body: Center(
              child: Text(
                '403 — Admin access required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        return widget.child;
      },
    );
  }
}