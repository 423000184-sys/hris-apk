// lib/services/employee_notification_listener.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';

void _secureLog(String m) {
  if (kDebugMode) debugPrint('[NotifListener] $m');
}

/// 🎧 Service na nagli-listen sa `employee_notifications` collection
/// para sa specific employee. Kapag may bagong notification (hal. PIN
/// reset mula sa admin), automatic na nagpapakita ng LOCAL notification
/// sa phone ng employee.
class EmployeeNotificationListener {
  EmployeeNotificationListener._();
  static final EmployeeNotificationListener instance =
  EmployeeNotificationListener._();

  StreamSubscription<QuerySnapshot>? _sub;
  String? _currentEmployeeId;
  final Set<String> _shownNotifIds = {};

  /// 🔑 Tamang constant name (may "s" sa dulo)
  static const String _kShownNotifsKey = 'shown_notif_ids';

  /// Simulan ang pag-listen para sa notification ng employee
  Future<void> start(String employeeId) async {
    if (employeeId.isEmpty) {
      _secureLog('⚠️ Empty employeeId — skip');
      return;
    }

    // Kung naka-listen na para sa parehong employee, skip
    if (_currentEmployeeId == employeeId && _sub != null) {
      _secureLog('⏩ Already listening for $employeeId');
      return;
    }

    await stop();
    _currentEmployeeId = employeeId;

    // 🆕 Restore shown notif IDs from prefs (para hindi mag-doble)
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kShownNotifsKey) ?? [];
      _shownNotifIds.clear();
      _shownNotifIds.addAll(saved);
      _secureLog('📋 Loaded ${_shownNotifIds.length} shown IDs');
    } catch (_) {}

    _secureLog('🎧 Starting listener for $employeeId');

    try {
      _sub = FirebaseFirestore.instance
          .collection('employee_notifications')
          .where('employeeId', isEqualTo: employeeId)
          .where('read', isEqualTo: false)
          .snapshots()
          .listen(
            (snapshot) {
          _secureLog(
              '📡 Snapshot: ${snapshot.docs.length} unread notifications');

          for (final doc in snapshot.docs) {
            final notifId = doc.id;
            if (_shownNotifIds.contains(notifId)) continue;

            final data = doc.data();
            if (data == null) continue;

            _shownNotifIds.add(notifId);
            _saveShownIds();
            _showNotification(notifId, data);
          }
        },
        onError: (e) => _secureLog('❌ Listener error: $e'),
      );
    } catch (e) {
      _secureLog('❌ Start failed: $e');
    }
  }

  Future<void> _saveShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Limit lang sa 100 para hindi lumaki
      final list = _shownNotifIds.length > 100
          ? _shownNotifIds
          .toList()
          .sublist(_shownNotifIds.length - 100)
          : _shownNotifIds.toList();
      await prefs.setStringList(_kShownNotifsKey, list);
    } catch (_) {}
  }

  Future<void> _showNotification(
      String notifId, Map<String, dynamic> data) async {
    try {
      final title = data['title']?.toString() ?? 'New Notification';
      final message = data['message']?.toString() ?? '';
      final type = data['type']?.toString() ?? 'general';
      final newPin = data['newPin']?.toString();

      _secureLog('🔔 Showing: $title');

      await LocalNotificationService.instance.show(
        id: notifId.hashCode & 0x7FFFFFFF,
        title: title,
        body: message,
        payload: newPin != null
            ? '{"type":"$type","notifId":"$notifId","newPin":"$newPin"}'
            : '{"type":"$type","notifId":"$notifId"}',
      );

      _secureLog('✅ Shown: $title');
    } catch (e) {
      _secureLog('⚠️ Show failed: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _currentEmployeeId = null;
    _secureLog('⏹️ Listener stopped');
  }

  /// Clear shown IDs (para sa testing)
  Future<void> clearShownIds() async {
    _shownNotifIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kShownNotifsKey);
    } catch (_) {}
  }
}