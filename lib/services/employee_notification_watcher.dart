// lib/services/employee_notification_watcher.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/employee_notification.dart';
import 'local_notification_service.dart';

class EmployeeNotificationWatcher {
  final String employeeId;
  StreamSubscription? _sub;

  /// Mga notification ID na naipakita na — para hindi ma-spam sa re-open
  final Set<String> _shownIds = {};

  /// Sa unang snapshot, i-mark ang lahat ng existing as "seen"
  /// para hindi lahat ng lumang notifications ay mag-pop-up sa unang bukas
  bool _firstSnapshotDone = false;

  EmployeeNotificationWatcher(this.employeeId);

  void start() {
    _sub = FirebaseFirestore.instance
        .collection('employee_notifications')
        .where('employeeId', whereIn: [employeeId, 'ALL'])
        .snapshots()
        .listen(_onSnapshot, onError: (e) {
      debugPrint('❌ Watcher error: $e');
    });
  }

  void _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    // ── Unang snapshot: i-mark lahat as seen, walang pop-up ──
    if (!_firstSnapshotDone) {
      for (final d in snap.docs) {
        _shownIds.add(d.id);
      }
      _firstSnapshotDone = true;
      debugPrint('🔔 Watcher: marked ${snap.docs.length} existing as seen');
      return;
    }

    // ── Susunod na snapshots: ipakita ang BAGONG notifications ──
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final doc = change.doc;
      final n = EmployeeNotification.fromDoc(doc);

      // Skip kung naipakita na
      if (_shownIds.contains(n.id)) continue;
      _shownIds.add(n.id);

      // ✅ Show device notification
      LocalNotificationService.instance.show(
        id: n.id.hashCode & 0x7FFFFFFF, // ensure positive int
        title: n.title,
        body: n.message,
        payload: n.id,
      );
    }
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}