// lib/services/employee_notification_watcher.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/employee_notification.dart';
import 'local_notification_service.dart';
import 'notification_preference_service.dart';

class EmployeeNotificationWatcher {
  final String employeeId;
  StreamSubscription? _sub;

  final Set<String> _shownIds = {};
  bool _firstSnapshotDone = false;

  EmployeeNotificationWatcher(this.employeeId);

  void start() {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔔 [Watcher] STARTING for employee: $employeeId');
    debugPrint('═══════════════════════════════════════════');

    _sub = FirebaseFirestore.instance
        .collection('employee_notifications')
        .where('employeeId', whereIn: [employeeId, 'ALL'])
        .snapshots()
        .listen(_onSnapshot, onError: (e) {
      debugPrint('❌ [Watcher] Stream error: $e');
    });
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    // ── Unang snapshot: i-mark lahat as seen, walang pop-up ──
    if (!_firstSnapshotDone) {
      for (final d in snap.docs) {
        _shownIds.add(d.id);
      }
      _firstSnapshotDone = true;
      debugPrint('🔔 [Watcher] Marked ${snap.docs.length} existing as seen');
      return;
    }

    debugPrint('🔔 [Watcher] Snapshot — ${snap.docChanges.length} changes');

    // ── Susunod na snapshots: ipakita ang BAGONG notifications ──
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) {
        debugPrint('   skip (not added): ${change.type}');
        continue;
      }

      final doc = change.doc;
      final n = EmployeeNotification.fromDoc(doc);

      if (_shownIds.contains(n.id)) {
        debugPrint('   skip (already shown): ${n.id}');
        continue;
      }
      _shownIds.add(n.id);

      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔔 [Watcher] NEW NOTIF DETECTED:');
      debugPrint('   id      : ${n.id}');
      debugPrint('   type    : ${n.type}');
      debugPrint('   title   : ${n.title}');
      debugPrint('   message : ${n.message}');
      debugPrint('═══════════════════════════════════════════');

      _maybeShowNotification(n);
    }
  }

  Future<void> _maybeShowNotification(EmployeeNotification n) async {
    try {
      // ✅ Check preference
      bool enabled = false;
      try {
        enabled = await NotificationPreferenceService.instance.isPushEnabled();
      } catch (e) {
        debugPrint('⚠️ [Watcher] Preference check error: $e');
        enabled = true; // Default TRUE kung may error
      }

      debugPrint('🔔 [Watcher] Push preference enabled = $enabled');

      // ✅ FORCE SHOW — kahit OFF ang preference (para sa testing)
      // ⚠️ IMPORTANTE: Alisin ang `//` sa baba para i-bypass ang preference
      // if (!enabled) {
      //   debugPrint('🔕 [Watcher] Push OFF — skipping notif: "${n.title}"');
      //   return;
      // }

      // ✅ Actually trigger the local notification (may tunog)
      debugPrint('🔔 [Watcher] Calling LocalNotificationService.show()...');
      await LocalNotificationService.instance.show(
        id: n.id.hashCode & 0x7FFFFFFF,
        title: n.title,
        body: n.message,
        payload: n.id,
      );
      debugPrint('✅ [Watcher] Local notif shown successfully!');
    } catch (e, st) {
      debugPrint('❌ [Watcher] show error: $e');
      debugPrint('$st');
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    debugPrint('🔔 [Watcher] STOPPED');
  }
}