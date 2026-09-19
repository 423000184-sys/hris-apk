// lib/services/local_notification_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'notification_preference_service.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance =
  LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Channel 1: Firestore notifications (admin → employee) ──
  static const _channelId = 'employee_notifications_channel';
  static const _channelName = 'Employee Notifications';
  static const _channelDesc = 'Notifications from admin / HRIS';

  // ── Channel 2: Daily work reminder ──
  static const _reminderChannelId = 'work_reminder_channel';
  static const _reminderChannelName = 'Work Reminder';
  static const _reminderChannelDesc = 'Daily reminder to go to work';

  // ── Scheduled IDs ──
  static const int _dailyReminderId = 8001;

  // ✅ Callback kapag na-tap ang notification
  void Function(String? payload)? onNotificationTap;

  // ═══════════════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_initialized) return;

    // ✅ Timezone setup — kailangan para sa scheduled notifications
    tz.initializeTimeZones();
    try {
      final String tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
      debugPrint('🌍 LocalNotificationService: timezone=$tzName');
    } catch (e) {
      debugPrint('⚠️ Timezone error: $e');
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('🔔 Notification tapped: ${response.payload}');
        onNotificationTap?.call(response.payload);
      },
    );

    // ✅ Android channels
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Channel 1: Firestore notifs
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );

      // Channel 2: Work reminder
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          _reminderChannelName,
          description: _reminderChannelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      debugPrint('📢 Channels created: $_channelId, $_reminderChannelId');
    }

    _initialized = true;
    debugPrint('✅ LocalNotificationService initialized');
  }

  // ═══════════════════════════════════════════════════════════════
  // REQUEST PERMISSIONS
  // ═══════════════════════════════════════════════════════════════
  Future<bool> requestPermissions() async {
    if (!_initialized) await init();

    bool granted = true;

    // Android 13+
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final notifGranted =
        await androidPlugin.requestNotificationsPermission();
        final exactGranted =
        await androidPlugin.requestExactAlarmsPermission();

        granted = (notifGranted ?? true) && (exactGranted ?? true);
        debugPrint(
            '🔔 Android — notifications=$notifGranted, exact=$exactGranted');
      }

      // Battery optimization bypass
      try {
        if (await Permission.ignoreBatteryOptimizations.isDenied) {
          await Permission.ignoreBatteryOptimizations.request();
          debugPrint('🔋 Battery optimization bypass requested');
        }
      } catch (e) {
        debugPrint('⚠️ Battery opt request: $e');
      }
    }

    // iOS
    if (Platform.isIOS) {
      final iosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      granted = iosGranted ?? true;
      debugPrint('🔔 iOS permission granted=$iosGranted');
    }

    return granted;
  }

  // ═══════════════════════════════════════════════════════════════
  // SHOW — IMMEDIATE notification (Firestore notifs from admin)
  // ═══════════════════════════════════════════════════════════════
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
    debugPrint('🔔 Device notification shown: $title');
  }

  // ═══════════════════════════════════════════════════════════════
  // SCHEDULE — DAILY WORK REMINDER (e.g. 7:30 AM araw-araw)
  // ═══════════════════════════════════════════════════════════════
  Future<void> scheduleDailyWorkReminder({
    int hour = 7,
    int minute = 30,
    String title = '⏰ Go to Work!',
    String body = 'Time to go to work! Clock in before 8:00 AM.',
  }) async {
    if (!_initialized) await init();

    // Calculate next occurrence
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled =
    tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    debugPrint('⏰ Scheduling daily reminder for $scheduled');

    const androidDetails = AndroidNotificationDetails(
      _reminderChannelId,
      _reminderChannelName,
      channelDescription: _reminderChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      fullScreenIntent: false,
      icon: '@mipmap/ic_launcher',
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
      macOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      _dailyReminderId,
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

    debugPrint('✅ Daily work reminder scheduled for $scheduled');
  }

  // ═══════════════════════════════════════════════════════════════
  // Schedule daily reminder ONLY IF push is ENABLED
  // ═══════════════════════════════════════════════════════════════
  Future<void> scheduleDailyWorkReminderIfEnabled({
    int hour = 7,
    int minute = 30,
    String title = '⏰ Go to Work!',
    String body = 'Time to go to work! Clock in before 8:00 AM.',
  }) async {
    if (!_initialized) await init();

    try {
      final enabled =
      await NotificationPreferenceService.instance.isPushEnabled();

      if (!enabled) {
        debugPrint(
            '🔕 [LocalNotif] Push OFF — skipping daily reminder schedule');
        return;
      }

      debugPrint('🔔 [LocalNotif] Push ON — scheduling daily reminder');

      await scheduleDailyWorkReminder(
        hour: hour,
        minute: minute,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('⚠️ [LocalNotif] scheduleIfEnabled error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CANCEL
  // ═══════════════════════════════════════════════════════════════
  Future<void> cancelDailyWorkReminder() async {
    await _plugin.cancel(_dailyReminderId);
    debugPrint('🚫 Daily work reminder cancelled');
  }

  Future<void> clearAll() async {
    await _plugin.cancelAll();
    debugPrint('🚫 All notifications cleared');
  }

  /// ✅ Alias para sa consistency sa NotificationPreferenceService
  Future<void> cancelAll() async {
    await clearAll();
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

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final n = await androidPlugin.areNotificationsEnabled();
        final e = await androidPlugin.canScheduleExactNotifications();
        debugPrint('🔔 Notif enabled: $n');
        debugPrint('⏰ Exact alarms: $e');
      }
    }

    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('📋 Pending: ${pending.length}');
    for (final p in pending) {
      debugPrint('   → "${p.title}" (id=${p.id})');
    }
    debugPrint('═══════════════════════════════════');
  }
}