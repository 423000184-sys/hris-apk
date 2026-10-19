// lib/services/notification_service.dart
// v2.0: 🔔 EXACT daily work reminder — consistent na bago mag 8:00 AM
//       ✅ Gumagamit ng exactAllowWhileIdle para hindi ma-delay ng OS
//       🔑 Hinihingi ang SCHEDULE_EXACT_ALARM permission (Android 12+)
//       ⚠️ May fallback sa inexact kapag denied ang exact alarm
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// ⚠️ DEPRECATED — Use `LocalNotificationService` instead.
/// Kept for backward compatibility.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const int _workReminderId = 8001;
  static const String _channelId = 'work_reminder_channel';
  static const String _channelName = 'Work Reminder';
  static const String _channelDesc = 'Daily reminder to go to work';

  /// 🎯 TARGET: araw-araw 7:30 AM (bago mag 8:00 AM shift)
  ///     Pwede mong baguhin sa pamamagitan ng `scheduleDailyWorkReminder`
  ///     parameters (hour, minute).
  static const int _defaultHour = 7;
  static const int _defaultMinute = 30;

  // ═══════════════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> init({void Function(NotificationResponse)? onTap}) async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final String tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
      debugPrint('🌍 Timezone: $tzName');
    } catch (e) {
      debugPrint('⚠️ Timezone error: $e');
    }

    const AndroidInitializationSettings androidInit =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('🔔 Notification tapped: ${response.payload}');
        onTap?.call(response);
      },
    );

    await _createAndroidChannel();
    _initialized = true;
    debugPrint('✅ NotificationService initialized');
  }

  Future<void> _createAndroidChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      // 🔑 Show heads-up notification (pop-up sa ibabaw ng screen)
      showBadge: true,
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(channel);
      debugPrint('📢 Channel created: $_channelId');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PERMISSIONS
  // ═══════════════════════════════════════════════════════════════
  Future<bool> requestPermissions() async {
    bool granted = true;

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      // 1️⃣ Notification permission (Android 13+)
      final notifGranted = await androidImpl.requestNotificationsPermission();
      granted = notifGranted ?? false;
      debugPrint('🔔 Notif permission: $notifGranted');

      // 2️⃣ 🔑 EXACT ALARM permission (Android 12+)
      //    Ito ang KEY para consistent ang notification!
      try {
        final exactAlarmGranted =
        await androidImpl.requestExactAlarmsPermission();
        debugPrint('⏰ Exact alarm permission: $exactAlarmGranted');
      } catch (e) {
        debugPrint('⚠️ Exact alarm permission error: $e');
      }
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final iosGranted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      granted = iosGranted ?? false;
      debugPrint('🔔 iOS permission: $iosGranted');
    }

    // 3️⃣ Battery optimization bypass — para hindi ma-kill ang app
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
        debugPrint('🔋 Battery optimization bypass requested');
      }
    } catch (e) {
      debugPrint('⚠️ Battery opt request: $e');
    }

    return granted;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔔 SCHEDULE DAILY WORK REMINDER — EXACT mode
  // ═══════════════════════════════════════════════════════════════
  Future<void> scheduleDailyWorkReminder({
    int hour = _defaultHour,
    int minute = _defaultMinute,
    String title = '⏰ Time to Go to Work!',
    String body = 'Clock in before 8:00 AM. Be safe on the way! 🚶‍♂️',
  }) async {
    if (!_initialized) await init();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    // 🎯 Compute the NEXT scheduled time (today or tomorrow)
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // Kung nakalipas na ang oras ngayon, i-schedule para bukas
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    debugPrint('⏰ Scheduling daily reminder for: $scheduled');

    // ═══════════════════════════════════════════════════════════════
    // 🎯 Notification details
    // ═══════════════════════════════════════════════════════════════
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max, // 🔑 MAX priority para heads-up
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: true, // 🔑 Full-screen intent para sa lock screen
      icon: '@mipmap/ic_launcher',
      // 🎨 Customization
      color: Color(0xFFFF8A00),
      // Show timestamp kung kailan na-schedule
      showWhen: true,
      // Ongoing = sticky, Ongoing = false = dismissible
      ongoing: false,
      autoCancel: true,
      // Grouping
      groupKey: 'work_reminder_group',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // 🎵 Sound name sa iOS (kailangan nasa bundle)
      // sound: 'default',
      // Critical alerts (iOS 12+, kailangan ng special permission)
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // ═══════════════════════════════════════════════════════════════
    // 🔑 CRITICAL FIX: exactAllowWhileIdle
    //    Ito ang nagbibigay ng EXACT timing — hindi na ma-delay ng OS.
    //    Kailangan ng SCHEDULE_EXACT_ALARM permission.
    // ═══════════════════════════════════════════════════════════════
    try {
      await _plugin.zonedSchedule(
        _workReminderId,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'work_reminder',
      );
      debugPrint('✅ EXACT reminder scheduled for $scheduled');
    } catch (e) {
      // ⚠️ FALLBACK: Kung denied ang exact alarm permission,
      //    gamitin ang inexact (may possibility ng delay pero at least
      //    may notification pa rin)
      debugPrint('⚠️ Exact scheduling failed: $e');
      debugPrint('⚠️ Falling back to inexact mode...');

      try {
        await _plugin.zonedSchedule(
          _workReminderId,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: 'work_reminder',
        );
        debugPrint('✅ INEXACT reminder scheduled for $scheduled '
            '(may delay ng hanggang 1 oras)');
      } catch (e2) {
        debugPrint('❌ Scheduling completely failed: $e2');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════
  Future<void> runDiagnostics() async {
    debugPrint('═══════════════════════════════════');
    debugPrint('🔍 NOTIFICATION DIAGNOSTICS');
    debugPrint('═══════════════════════════════════');
    debugPrint('🌍 TZ: ${tz.local.name}');
    debugPrint('🌍 Now: ${tz.TZDateTime.now(tz.local)}');

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final n = await androidImpl.areNotificationsEnabled();
      final e = await androidImpl.canScheduleExactNotifications();
      debugPrint('🔔 Notif enabled: $n');
      debugPrint('⏰ Exact alarms: $e');

      if (e == false) {
        debugPrint('⚠️ EXACT ALARM PERMISSION DENIED!');
        debugPrint('   → Notification may be delayed by up to 1 hour.');
        debugPrint('   → Go to Settings → Apps → R.A.C.O.M.A. → '
            'Alarms & reminders → ALLOW');
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('📋 Pending: ${pending.length}');
    for (final p in pending) {
      debugPrint('   → "${p.title}" (id=${p.id})');
    }
    debugPrint('═══════════════════════════════════');
  }

  Future<void> cancelDailyWorkReminder() async {
    await _plugin.cancel(_workReminderId);
    debugPrint('🚫 Daily reminder cancelled');
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    debugPrint('🚫 All notifications cancelled');
  }

  // ✅ ENGLISH test
  Future<void> showTestNotification() async {
    if (!_initialized) await init();
    await _plugin.show(
      9999,
      '🧪 Test Notification',
      'If you see this, notifications are working!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
    debugPrint('✅ Test notification shown');
  }
}