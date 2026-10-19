// lib/services/trusted_time_service.dart
// 🔐 Trusted Time Service
//    - Server-verified time para hindi ma-tamper ang device clock
//    - Gumagamit ng Firestore serverTimestamp() bilang source of truth
//    - Nag-cache ng offset para hindi laging mag-query
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

void _log(String m) {
  if (kDebugMode) debugPrint('[TrustedTime] $m');
}

class TrustedTimeService {
  TrustedTimeService._();
  static final TrustedTimeService instance = TrustedTimeService._();

  /// Difference sa pagitan ng server time at device time.
  /// `server_now = device_now + offset`
  Duration _offset = Duration.zero;

  bool _synced = false;
  DateTime? _lastSyncAt;
  DateTime? _lastServerTime;

  /// Threshold para ituring na tampered ang device clock.
  static const Duration _tamperThreshold = Duration(minutes: 5);

  /// Refresh interval — re-sync kada 15 minuto
  static const Duration _syncTtl = Duration(minutes: 15);

  bool get isSynced => _synced;

  /// Ang pinaka-importanteng getter — ito ang gagamitin sa buong app
  /// imbes na `DateTime.now()`.
  DateTime now() => DateTime.now().add(_offset);

  /// `true` kapag ang device clock ay malayo sa server clock.
  bool get isTampered {
    if (!_synced) return false;
    return _offset.abs() > _tamperThreshold;
  }

  /// Positive kung naka-set pasulong ang device clock, negative kung pabalik.
  Duration get offset => _offset;

  /// Server time from last successful sync.
  DateTime? get lastServerTime => _lastServerTime;

  // ═══════════════════════════════════════════════════════════════
  // SYNC
  // ═══════════════════════════════════════════════════════════════
  Future<void> syncWithServer({bool force = false}) async {
    if (!force &&
        _lastSyncAt != null &&
        DateTime.now().difference(_lastSyncAt!) < _syncTtl) {
      return;
    }

    try {
      final ref = FirebaseFirestore.instance
          .collection('_time_ping')
          .doc('client_sync');

      // 1️⃣ Write serverTimestamp()
      await ref.set({
        'ping': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2️⃣ Read it back — ngayon ito na ang "server time"
      final snap = await ref.get().timeout(const Duration(seconds: 6));
      final serverTime = (snap.data()?['ping'] as Timestamp?)?.toDate();

      if (serverTime == null) {
        _log('⚠️ No server timestamp returned');
        return;
      }

      final deviceTime = DateTime.now();
      _offset = serverTime.difference(deviceTime);
      _synced = true;
      _lastSyncAt = deviceTime;
      _lastServerTime = serverTime;

      _log('✅ Synced. Server=$serverTime Device=$deviceTime '
          'Offset=${_offset.inSeconds}s');

      if (isTampered) {
        _log('🚨 TAMPER DETECTED! Offset=${_offset.inMinutes}m');
      }
    } catch (e) {
      _log('⚠️ Sync failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LOG ANOMALY (para sa admin)
  // ═══════════════════════════════════════════════════════════════
  Future<void> logTamperEvent({
    required String employeeId,
    required String employeeName,
    required String context,
  }) async {
    if (!_synced || !isTampered) return;

    try {
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'time_tamper_detected',
        'severity': 'high',
        'employeeId': employeeId,
        'employeeName': employeeName,
        'details': 'Device clock offset '
            '${_offset.inMinutes}min (context: $context). '
            'Device=${DateTime.now().toIso8601String()}, '
            'Server=$_lastServerTime',
        'offsetSeconds': _offset.inSeconds,
        'context': context,
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
      _log('📢 Tamper event logged for $employeeId');
    } catch (e) {
      _log('⚠️ Failed to log tamper: $e');
    }
  }
}