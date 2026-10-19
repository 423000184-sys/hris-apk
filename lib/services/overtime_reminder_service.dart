// lib/services/overtime_reminder_service.dart
// v2.0: ⏰ Overtime Reminder Service
//    - Per-employee shift end (read from Firestore)
//    - Schedule 5PM + hourly reminders (6PM, 7PM, 8PM...)
//    - Auto-cancel kapag nag-clock out
//    - Recovery kung nag-restart ang app habang naka-clock in
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void _log(String m) {
  if (kDebugMode) debugPrint('[OTReminder] $m');
}

class OvertimeReminderService {
  OvertimeReminderService._();
  static final OvertimeReminderService instance = OvertimeReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'overtime_reminder_channel';
  static const String _channelName = 'Overtime Reminder';
  static const String _channelDesc =
      'Hourly reminders pagkalagpas ng shift end';

  /// IDs: 9100 (shift-end), 9101-9110 (hourly OT)
  static const int _shiftEndId = 9100;
  static const int _otBaseId = 9100;

  // ═══════════════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);
    await _createChannel();

    _initialized = true;
    _log('✅ OvertimeReminderService initialized');
  }

  Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _log('📢 Channel created: $_channelId');
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 PER-EMPLOYEE SHIFT END (from Firestore)
  //    Fallback: 17:00 (5:00 PM)
  // ═══════════════════════════════════════════════════════════════
  Future<({int hour, int minute})> _getShiftEndForEmployee(
      String employeeId,
      ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get()
          .timeout(const Duration(seconds: 5));

      final data = doc.data();
      if (data == null) return (hour: 17, minute: 0);

      // Try multiple possible field names
      final shiftEnd = data['shiftEnd'] as String? ??
          data['workEnd'] as String? ??
          data['endTime'] as String?;

      if (shiftEnd == null || shiftEnd.isEmpty) {
        _log('ℹ️ No shiftEnd field for $employeeId — using default 17:00');
        return (hour: 17, minute: 0);
      }

      // Format: "17:00" o "17:00:00"
      if (shiftEnd.contains(':')) {
        final parts = shiftEnd.split(':');
        final hour = int.tryParse(parts[0]) ?? 17;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        _log('🎯 Shift end for $employeeId: $hour:$minute');
        return (hour: hour, minute: minute);
      }

      // Format: "5:00 PM"
      if (shiftEnd.toUpperCase().contains('PM')) {
        final clean = shiftEnd.replaceAll(RegExp(r'[^\d:]'), '');
        final parts = clean.split(':');
        var hour = int.tryParse(parts[0]) ?? 5;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        if (hour < 12) hour += 12; // 5 PM → 17
        return (hour: hour, minute: minute);
      }

      // Format: "8:00 AM"
      if (shiftEnd.toUpperCase().contains('AM')) {
        final clean = shiftEnd.replaceAll(RegExp(r'[^\d:]'), '');
        final parts = clean.split(':');
        var hour = int.tryParse(parts[0]) ?? 8;
        final minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        if (hour == 12) hour = 0;
        return (hour: hour, minute: minute);
      }

      // Format: "5 PM" (no colon)
      if (shiftEnd.toUpperCase().contains('PM')) {
        final clean = shiftEnd.replaceAll(RegExp(r'[^\d]'), '');
        var hour = int.tryParse(clean) ?? 5;
        if (hour < 12) hour += 12;
        return (hour: hour, minute: 0);
      }
    } catch (e) {
      _log('⚠️ Failed to read shift end: $e');
    }
    return (hour: 17, minute: 0);
  }

  // ═══════════════════════════════════════════════════════════════
  // ⏰ SCHEDULE — base method (accepts explicit shift end time)
  // ═══════════════════════════════════════════════════════════════
  Future<void> schedule({
    int shiftEndHour = 17,
    int shiftEndMinute = 0,
    int maxOvertimeHours = 6,
  }) async {
    if (!_initialized) await init();
    await cancelAll();

    final now = tz.TZDateTime.now(tz.local);

    // Start: today at shiftEnd (or tomorrow kung past na)
    var start = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      shiftEndHour,
      shiftEndMinute,
    );
    if (!start.isAfter(now)) {
      start = start.add(const Duration(days: 1));
    }

    // 1️⃣ Shift-end reminder
    await _scheduleOne(
      id: _shiftEndId,
      when: start,
      title: '🏁 Shift End',
      body: 'Time to clock out. Please open the app to clock out.',
    );
    _log('✅ Shift-end reminder: $start');

    // 2️⃣ Hourly overtime reminders
    for (int i = 1; i <= maxOvertimeHours; i++) {
      final when = start.add(Duration(hours: i));
      await _scheduleOne(
        id: _otBaseId + i,
        when: when,
        title: '⏰ ${i}h overtime',
        body: 'Hindi ka pa nag-clo-clock out. '
            'Mag-clock out na para hindi tumagal ang OT.',
      );
      _log('✅ OT+${i}h reminder: $when');
    }

    _log('🎯 Total: ${maxOvertimeHours + 1} reminders scheduled');
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ AUTO-SCHEDULE FOR EMPLOYEE (reads shift end from Firestore)
  // ═══════════════════════════════════════════════════════════════
  Future<void> scheduleForEmployee({
    required String employeeId,
    int maxOvertimeHours = 6,
  }) async {
    if (!_initialized) await init();

    final shift = await _getShiftEndForEmployee(employeeId);
    await schedule(
      shiftEndHour: shift.hour,
      shiftEndMinute: shift.minute,
      maxOvertimeHours: maxOvertimeHours,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 📅 SCHEDULE ONE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _scheduleOne({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: true,
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF8A00),
      ongoing: false,
      autoCancel: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'overtime_reminder',
      );
    } catch (e) {
      _log('⚠️ Exact failed for id=$id: $e — falling back to inexact');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'overtime_reminder',
        );
      } catch (e2) {
        _log('❌ Failed to schedule id=$id: $e2');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🚫 CANCEL ALL
  // ═══════════════════════════════════════════════════════════════
  Future<void> cancelAll() async {
    if (!_initialized) await init();

    // Cancel shift-end + 10 hourly slots
    await _plugin.cancel(_shiftEndId);
    for (int i = 1; i <= 10; i++) {
      await _plugin.cancel(_otBaseId + i);
    }
    _log('🚫 Overtime reminders cancelled');
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔄 RECOVERY — kapag nag-restart ang app habang naka-clock in
  //    Tawagin sa main_screen.dart initState() at didChangeAppLifecycleState()
  // ═══════════════════════════════════════════════════════════════
  Future<void> recoverIfStillClockedIn(String employeeId) async {
    if (!_initialized) await init();

    try {
      // Check kung naka-clock in pa
      final today = DateTime.now();
      final todayStr = '${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';

      final logs = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: todayStr)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6));

      if (logs.docs.isEmpty) {
        _log('ℹ️ No attendance for today — skipping recovery');
        return;
      }

      final lastLog = logs.docs.first.data();
      final lastType = (lastLog['type'] ?? '').toString().toUpperCase();

      if (lastType == 'IN') {
        // Naka-clock in pa → i-recover ang reminders
        _log('🔄 Still clocked in — re-scheduling OT reminders');
        await scheduleForEmployee(employeeId: employeeId);
      } else {
        // Nag-clock out na → cancel
        _log('✅ Already clocked out — cancelling any pending');
        await cancelAll();
      }
    } catch (e) {
      _log('⚠️ Recovery failed: $e');
    }
  }
}