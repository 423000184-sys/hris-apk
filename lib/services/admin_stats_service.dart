// lib/services/admin_stats_service.dart
import 'package:cloud_functions/cloud_functions.dart'; // ✅ ITO ANG KULANG
import 'package:firebase_auth/firebase_auth.dart';

/// Fetches server-computed stats. Client never trusts local time or
/// local geo calculations — lahat galing Cloud Function.
class AdminStatsService {
  final FirebaseFunctions _fn = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> fetchOverviewStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not signed in');

    // Refresh token para siguradong latest custom claim
    await user.getIdToken(true);

    final callable = _fn.httpsCallable('getAdminOverviewStats');
    final res = await callable.call();
    return Map<String, dynamic>.from(res.data as Map);
  }
}