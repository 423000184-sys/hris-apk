// lib/services/notification_service.dart
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
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(channel);
      debugPrint('📢 Channel created: $_channelId');
    }
  }

  Future<bool> requestPermissions() async {
    bool granted = true;

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final notifGranted = await androidImpl.requestNotificationsPermission();
      granted = notifGranted ?? false;
      debugPrint('🔔 Notif permission: $notifGranted');
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

  // ✅ ENGLISH defaults
  Future<void> scheduleDailyWorkReminder({
    int hour = 7,
    int minute = 30,
    String title = '⏰ Time to Go to Work!',
    String body =
    'Clock in before 8:00 AM. Be safe on the way! 🚶‍♂️',
  }) async {
    if (!_initialized) await init();

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    debugPrint('⏰ Scheduling for: $scheduled');

    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: false,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

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

    debugPrint('✅ Scheduled for $scheduled');
  }

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
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
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