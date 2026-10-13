// lib/services/clock_status_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';

class ClockStatusService {
  ClockStatusService._();
  static final ClockStatusService instance = ClockStatusService._();

  /// Check kung naka-clock in pa si employee ngayon (walang pang OUT log).
  /// Returns true kung:
  ///   - May IN log ngayong araw
  ///   - WALANG OUT log after ng latest IN
  Future<bool> isCurrentlyClockedIn(String employeeId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: today)
          .get()
          .timeout(const Duration(seconds: 8));

      if (snap.docs.isEmpty) {
        debugPrint('🔍 ClockStatus: No logs today → NOT clocked in');
        return false;
      }

      // Sort by timestamp ascending
      final docs = snap.docs.toList();
      docs.sort((a, b) {
        final aT = a.data()['timestamp'];
        final bT = b.data()['timestamp'];
        // Fallback sa 'time' field kung walang timestamp
        final aVal = aT?.toString() ?? a.data()['time']?.toString() ?? '';
        final bVal = bT?.toString() ?? b.data()['time']?.toString() ?? '';
        return aVal.compareTo(bVal);
      });

      // Get latest log
      String? latestType;
      for (final d in docs) {
        final t = (d.data()['type'] ?? '').toString().toUpperCase();
        if (t == 'IN' || t == 'CLOCK_IN' || t == 'OUT' || t == 'CLOCK_OUT') {
          latestType = t;
        }
      }

      final clockedIn = latestType == 'IN' || latestType == 'CLOCK_IN';
      debugPrint('🔍 ClockStatus: Latest type = $latestType → '
          'clockedIn = $clockedIn');
      return clockedIn;
    } catch (e) {
      debugPrint('❌ ClockStatus error: $e');
      return false;
    }
  }

  /// Kunin ang latest IN log (arrival info) para sa dashboard display.
  Future<Map<String, dynamic>?> getLatestClockInLog(String employeeId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: today)
          .where('type', isEqualTo: 'IN')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));

      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data();
    } catch (e) {
      debugPrint('❌ getLatestClockInLog error: $e');
      return null;
    }
  }
}