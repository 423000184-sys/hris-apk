// lib/services/clock_status_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';
import 'offline_attendance_service.dart';

class ClockStatusService {
  ClockStatusService._();
  static final ClockStatusService instance = ClockStatusService._();

  static const Set<String> _ins = {
    'IN', 'CLOCK_IN', 'CLOCKIN', 'TIME_IN', 'TIMEIN', 'CHECK_IN', 'CHECKIN',
  };
  static const Set<String> _outs = {
    'OUT', 'CLOCK_OUT', 'CLOCKOUT', 'TIME_OUT', 'TIMEOUT', 'CHECK_OUT',
    'CHECKOUT',
  };

  String _normType(dynamic raw) {
    final t = (raw ?? '')
        .toString()
        .toUpperCase()
        .trim()
        .replaceAll(RegExp(r'[\s\-]+'), '_');
    if (_ins.contains(t)) return 'IN';
    if (_outs.contains(t)) return 'OUT';
    return '';
  }

  /// Check kung naka-clock in pa si employee ngayon (walang pang OUT log).
  /// Returns true kung:
  ///   - May IN log ngayong araw
  ///   - WALANG OUT log after ng latest IN
  Future<bool> isCurrentlyClockedIn(String employeeId) async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final events = <({DateTime t, String type})>[];

    try {
      final local = await OfflineAttendanceService.instance
          .getTodayForEmployee(employeeId);
      for (final r in local) {
        final t = DateTime.tryParse(r['timestamp'] as String? ?? '');
        final type = _normType(r['type']);
        if (t != null && type.isNotEmpty) events.add((t: t, type: type));
      }
    } catch (e) {
      debugPrint('⚠️ ClockStatus local read failed: $e');
    }

    try {
      final col = FirebaseFirestore.instance.collection('attendance_logs');
      final docs = <String, Map<String, dynamic>>{};
      for (final field in const ['employee_id', 'employeeId']) {
        try {
          final s = await col
              .where(field, isEqualTo: employeeId)
              .where('date', isEqualTo: today)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 8));
          for (final d in s.docs) {
            docs[d.id] = d.data();
          }
        } catch (e) {
          debugPrint('⚠️ ClockStatus query($field) failed: $e');
        }
      }

      for (final data in docs.values) {
        final type = _normType(data['type'] ?? data['action']);
        if (type.isEmpty) continue;

        DateTime? t;
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          t = ts.toDate();
        } else if (data['time'] is String) {
          final p = (data['time'] as String).split(':');
          if (p.length >= 2) {
            t = DateTime(now.year, now.month, now.day,
                int.tryParse(p[0]) ?? 0,
                int.tryParse(p[1]) ?? 0,
                p.length > 2 ? int.tryParse(p[2]) ?? 0 : 0);
          }
        }
        if (t != null) events.add((t: t, type: type));
      }
    } catch (e) {
      debugPrint('⚠️ ClockStatus remote read failed: $e');
    }

    if (events.isEmpty) {
      debugPrint('🔍 ClockStatus: no logs today → NOT clocked in');
      return false;
    }

    events.sort((a, b) => a.t.compareTo(b.t));
    final clockedIn = events.last.type == 'IN';
    debugPrint('🔍 ClockStatus: latest=${events.last.type} → $clockedIn');
    return clockedIn;
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