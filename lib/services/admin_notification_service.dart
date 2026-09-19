// lib/services/admin_notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/admin_notification.dart';
import 'admin_notification_queue.dart';
import 'network_guard.dart';

class AdminNotificationService {
  AdminNotificationService._();
  static final instance = AdminNotificationService._();

  final _col = FirebaseFirestore.instance.collection('admin_notifications');

  // ═══════════════════════════════════════════════════════════════
  // 🚦 GEOFENCE THROTTLE — anti-spam per employee
  // ═══════════════════════════════════════════════════════════════
  final Map<String, DateTime> _geofenceCooldown = {};
  static const _geofenceCooldownDuration = Duration(minutes: 2);

  // ═══════════════════════════════════════════════════════════════
  // STREAMS
  // ═══════════════════════════════════════════════════════════════
  Stream<List<AdminNotification>> streamAll({int limit = 50}) {
    return _col
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  Stream<int> streamUnreadCount() {
    return _col
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════
  Future<void> markAsRead(String id) async {
    try {
      await _col.doc(id).update({'read': true});
    } catch (e) {
      debugPrint('markAsRead error: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final snap = await _col.where('read', isEqualTo: false).limit(500).get();
      for (final d in snap.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('markAllAsRead error: $e');
    }
  }

  Future<void> deleteNotification(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      debugPrint('deleteNotification error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final snap = await _col.limit(500).get();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('clearAll error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 BASE NOTIFY — with offline queue fallback
  // ═══════════════════════════════════════════════════════════════
  Future<void> notify({
    required String type,
    required String title,
    required String message,
    String? employeeId,
    String? employeeName,
    String priority = 'normal',
    Map<String, dynamic> metadata = const {},
  }) async {
    final payload = <String, dynamic>{
      'type': type,
      'title': title,
      'message': message,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'priority': priority,
      'read': false,
      'metadata': metadata,
    };

    // ✅ Try direct write muna kung online
    if (NetworkGuard.instance.isOnline) {
      try {
        await _col
            .add({
          ...payload,
          'timestamp': FieldValue.serverTimestamp(),
        })
            .timeout(const Duration(seconds: 8));
        debugPrint('✅ [Notify] $type — $title (direct)');
        return;
      } catch (e) {
        debugPrint('⚠️ [Notify] Direct write failed, queueing: $e');
      }
    }

    // ✅ Offline o nag-fail — i-queue
    await AdminNotificationQueue.instance.enqueue(payload);
    debugPrint('📥 [Notify] $type — queued for sync');
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CLOCK IN — normal (zone-aware)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
    bool inRange = true,
    double? faceMatchPercent,
    double? distanceMeters,
    String? zoneType,
  }) {
    final zone = zoneType ?? (wfh ? 'wfh' : (inRange ? 'inside' : 'outside'));
    final badge = _zoneEmoji(zone);

    final title = wfh
        ? '$badge $employeeName clocked in (WFH)'
        : (inRange
        ? '$badge $employeeName clocked in'
        : '$badge $employeeName clocked in (Outside)');

    final message = [
      timeStr,
      _zoneLabel(zone),
      if (distanceMeters != null)
        '${distanceMeters.toStringAsFixed(0)}m from office',
      if (faceMatchPercent != null)
        'Face ${faceMatchPercent.toStringAsFixed(0)}%',
    ].join(' · ');

    return notify(
      type: zone == 'outside' ? 'geofence_alert' : 'clock_in',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: zone == 'outside' ? 'high' : 'normal',
      metadata: {
        'zone': zone,
        'time': timeStr,
        'wfh': wfh,
        'in_range': inRange,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CLOCK OUT — normal (zone-aware)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
    bool inRange = true,
    double? faceMatchPercent,
    double? distanceMeters,
    String? zoneType,
  }) {
    final zone = zoneType ?? (wfh ? 'wfh' : (inRange ? 'inside' : 'outside'));
    final badge = _zoneEmoji(zone);

    final title = '$badge $employeeName clocked out';

    final message = [
      timeStr,
      _zoneLabel(zone),
      if (distanceMeters != null) '${distanceMeters.toStringAsFixed(0)}m',
    ].join(' · ');

    return notify(
      type: 'clock_out',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'normal',
      metadata: {
        'zone': zone,
        'time': timeStr,
        'wfh': wfh,
        'in_range': inRange,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ WFH — separate notif
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyWFHClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    double? faceMatchPercent,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: '🏠 $employeeName — WFH Clock In',
      message: '$timeStr · Work-from-home'
          '${faceMatchPercent != null ? " · Face ${faceMatchPercent.toStringAsFixed(0)}%" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'normal',
      metadata: {
        'zone': 'wfh',
        'time': timeStr,
        'wfh': true,
        'in_range': false,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
      },
    );
  }

  Future<void> notifyWFHClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: '🏠 $employeeName — WFH Clock Out',
      message: '$timeStr · Work-from-home ended',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'wfh',
        'time': timeStr,
        'wfh': true,
        'in_range': false,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ DRIVER — separate notif
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyDriverClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    double? faceMatchPercent,
  }) {
    return notify(
      type: 'clock_in',
      title: '🚗 $employeeName (Driver) clocked in',
      message: '$timeStr · Field duty — geofence exempt'
          '${faceMatchPercent != null ? " · Face ${faceMatchPercent.toStringAsFixed(0)}%" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'driver',
        'time': timeStr,
        'wfh': false,
        'in_range': false,
        'role': 'driver',
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
      },
    );
  }

  Future<void> notifyDriverClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
  }) {
    return notify(
      type: 'clock_out',
      title: '🚗 $employeeName (Driver) clocked out',
      message: '$timeStr · Field duty ended',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'driver',
        'time': timeStr,
        'wfh': false,
        'in_range': false,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ GEOFENCE ALERT — outside perimeter (URGENT)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyGeofenceAlert({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    required double distanceMeters,
    String action = 'clock_in',
  }) {
    return notify(
      type: 'geofence_alert',
      title: '⚠️ Geofence Alert — $employeeName',
      message: 'Attempted $action outside zone · '
          '${distanceMeters.toStringAsFixed(0)}m from office at $timeStr',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'high',
      metadata: {
        'zone': 'outside',
        'time': timeStr,
        'distance_meters': distanceMeters,
        'action': action,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🚨 GEOFENCE ALERT — THROTTLED (anti-spam)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyGeofenceAlertThrottled({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    required double distanceMeters,
    String action = 'clock_in',
  }) async {
    final now = DateTime.now();
    final last = _geofenceCooldown[employeeId];

    if (last != null && now.difference(last) < _geofenceCooldownDuration) {
      final remain = _geofenceCooldownDuration - now.difference(last);
      debugPrint('⏱️ [GeofenceAlert] Throttled for $employeeName — '
          '${remain.inSeconds}s remaining');
      return;
    }

    _geofenceCooldown[employeeId] = now;
    debugPrint('🚨 [GeofenceAlert] FIRING for $employeeName '
        '(distance=${distanceMeters.toStringAsFixed(0)}m)');

    return notifyGeofenceAlert(
      employeeId: employeeId,
      employeeName: employeeName,
      timeStr: timeStr,
      distanceMeters: distanceMeters,
      action: action,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ FACE ENROLLMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyFaceEnrollment({
    required String employeeId,
    required String employeeName,
    required int enrolledAngles,
  }) {
    return notify(
      type: 'face_enrollment',
      title: '📸 $employeeName — Face enrolled',
      message: '$enrolledAngles angle(s) captured · Biometric active',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'enrolled_angles': enrolledAngles,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ LEAVE REQUEST (URGENT)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyLeaveRequest({
    required String employeeId,
    required String employeeName,
    required String leaveType,
    required String dateRange,
    String? reason,
  }) {
    return notify(
      type: 'leave_request',
      title: '📋 $employeeName — Leave Request',
      message: '$leaveType · $dateRange'
          '${reason != null && reason.isNotEmpty ? " · $reason" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'high',
      metadata: {
        'leave_type': leaveType,
        'date_range': dateRange,
        if (reason != null) 'reason': reason,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 PASSWORD CHANGE REQUEST (URGENT — admin approval needed)  (BAGO)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyPasswordChangeRequest({
    required String employeeId,
    required String employeeName,
    String? email,
    String? reason,
    String priority = 'high',
  }) {
    final parts = <String>[
      if (email != null && email.isNotEmpty) email,
      if (reason != null && reason.isNotEmpty) reason,
    ];

    return notify(
      type: 'password_change',
      title: '🔐 $employeeName — Password Change Request',
      message: parts.isEmpty
          ? 'Humingi ng password reset. Kailangan ng admin approval.'
          : parts.join(' · '),
      employeeId: employeeId,
      employeeName: employeeName,
      priority: priority,
      metadata: {
        'request_type': 'password_change',
        'zone': 'wfh',
        if (email != null) 'email': email,
        if (reason != null) 'reason': reason,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ WFH TOGGLE (admin action)
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyWfhToggle({
    required String employeeId,
    required String employeeName,
    required bool enabled,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: enabled
          ? '🏠 WFH enabled for $employeeName'
          : '🏢 WFH disabled for $employeeName',
      message: enabled
          ? 'Employee can now clock in from anywhere.'
          : 'Employee must be within office zone.',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'enabled': enabled,
        'zone': enabled ? 'wfh' : 'inside',
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🛰️ PRESENCE UPDATE — live IN/OUT status from PresenceMonitor
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyPresenceUpdate({
    required String employeeId,
    required String employeeName,
    required String zone,
    required double distanceMeters,
    required bool changed,
    String? previousZone,
    String priority = 'normal',
    String notifyReason = 'heartbeat',
  }) {
    final isInside = zone == 'inside';
    final emoji = isInside ? '🟢' : '🔴';
    final statusText = isInside ? 'IN RANGE' : 'OUT OF RANGE';

    String title;
    String message;

    if (changed && previousZone != null && previousZone.isNotEmpty) {
      final fromText =
      previousZone == 'inside' ? 'IN RANGE' : 'OUT OF RANGE';
      title = '$emoji Status Change — $employeeName';
      message = 'Moved from $fromText → $statusText · '
          '${distanceMeters.toStringAsFixed(0)}m from office';
    } else {
      title = '$emoji $employeeName — $statusText';
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      message = '${distanceMeters.toStringAsFixed(0)}m from office · '
          'Checked at $hh:$mm';
    }

    return notify(
      type: 'presence_update',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: priority,
      metadata: {
        'zone': zone,
        'in_range': isInside,
        'distance_meters': distanceMeters,
        'changed': changed,
        'notify_reason': notifyReason,
        if (previousZone != null) 'previous_zone': previousZone,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _zoneEmoji(String zone) {
    switch (zone) {
      case 'inside':
        return '📍';
      case 'wfh':
        return '🏠';
      case 'driver':
        return '🚗';
      case 'outside':
        return '⚠️';
      default:
        return '✅';
    }
  }

  String _zoneLabel(String zone) {
    switch (zone) {
      case 'inside':
        return 'GPS verified';
      case 'wfh':
        return 'Work-from-home';
      case 'driver':
        return 'Field duty';
      case 'outside':
        return 'Outside zone';
      default:
        return 'On-site';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBUG HELPER — clear throttle (para sa testing)
  // ═══════════════════════════════════════════════════════════════
  void clearThrottle() {
    _geofenceCooldown.clear();
    debugPrint('🧹 [GeofenceAlert] Throttle cleared');
  }

  void clearThrottleFor(String employeeId) {
    _geofenceCooldown.remove(employeeId);
    debugPrint('🧹 [GeofenceAlert] Throttle cleared for $employeeId');
  }
}