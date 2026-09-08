import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'database_service.dart';
import 'geofence_service.dart';
import 'alarm_service.dart';
import 'security_service.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Check every 30 seconds for higher responsiveness during testing
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    final now = DateTime.now();
    
    // TARGET DEADLINE: 9:30 PM (21:30)
    // ALARM START: 9:00 PM (21:00) - 30 minutes before
    
    // Check if current time is between 9:00 PM (21:00) and 9:30 PM (21:30)
    final bool isAlarmWindow = (now.hour == 21 && now.minute >= 0 && now.minute < 30);

    if (isAlarmWindow) {
      final empId = await SecurityService.instance.getCurrentEmployeeId();
      if (empId == null) return;

      final todayAtt = await DatabaseService.instance.getTodayAttendance(empId);
      final isClockedIn = todayAtt?.isClockedIn ?? false;

      if (!isClockedIn) {
        final geo = GeofenceService.instance;
        final geoResult = await geo.checkGeofence();

        // Alarm if OUTSIDE radius
        if (!geoResult.isInside) {
          // Trigger the alarm sound and vibration
          AlarmService.instance.startAlarm();

          flutterLocalNotificationsPlugin.show(
            AppBackgroundService.notificationId,
            'WARNING: 9:30 PM DEADLINE',
            'Alarm active! You have ${30 - now.minute} minutes left to time in at the office.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                AppBackgroundService.notificationChannelId,
                'HRIS Background Service',
                ongoing: true,
                importance: Importance.max,
                priority: Priority.high,
                fullScreenIntent: true,
                audioAttributesUsage: AudioAttributesUsage.alarm,
              ),
            ),
          );
        }
      }
    }
  });
}

class AppBackgroundService {
  static const notificationId = 888;
  static const notificationChannelId = 'hris_foreground';

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'HRIS Background Service',
      description: 'Monitoring attendance and location.',
      importance: Importance.high,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'HRIS Monitoring Active',
        initialNotificationContent: 'Waiting for alarm window...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }
}
