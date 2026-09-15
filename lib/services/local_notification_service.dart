// lib/services/local_notification_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance =
  LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'employee_notifications_channel';
  static const _channelName = 'Employee Notifications';
  static const _channelDesc = 'Notifications from admin / HRIS';

  // ✅ Callback kapag na-tap ang notification
  void Function(String? payload)? onNotificationTap;

  Future<void> init() async {
    if (_initialized) return;

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

    // ✅ Android 13+ runtime permission
    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      debugPrint('🔔 Notification permission granted: $granted');

      // Gumawa ng channel (required sa Android 8+)
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
    }

    // ✅ iOS permission
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    _initialized = true;
    debugPrint('✅ LocalNotificationService initialized');
  }

  /// Ipakita ang device notification
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

  /// I-clear lahat ng notifications sa tray
  Future<void> clearAll() async {
    await _plugin.cancelAll();
  }
}