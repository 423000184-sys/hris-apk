// lib/services/killed_state_listener.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
// BACKGROUND ENTRY POINT — TOP-LEVEL FUNCTION
// Ito ang tumatakbo sa background isolate.
// Kahit i-swipe away ng user ang app, tumatakbo pa rin ito.
// ═══════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  debugPrint('🚀 [BG] Service started');

  // Firebase init sa background isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      debugPrint('✅ [BG] Firebase initialized');
    }
  } catch (e) {
    debugPrint('⚠️ [BG] Firebase init error: $e');
    return;
  }

  // Foreground service handlers
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // Init local notification plugin (background isolate)
  final notifPlugin = FlutterLocalNotificationsPlugin();
  try {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await notifPlugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'employee_notifications_channel',
      'Employee Notifications',
      description: 'Notifications from admin / HRIS',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await notifPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    debugPrint('✅ [BG] Notif plugin initialized');
  } catch (e) {
    debugPrint('⚠️ [BG] Notif init error: $e');
  }

  // Kunin ang employee ID
  String? employeeId;
  try {
    final prefs = await SharedPreferences.getInstance();
    employeeId = prefs.getString('fp_preauth_employee_id');
  } catch (e) {
    debugPrint('⚠️ [BG] prefs error: $e');
  }

  if (employeeId == null || employeeId.isEmpty) {
    debugPrint('⚠️ [BG] No employeeId — service idle');
    // Tuloy pa rin ang service pero walang polling
  } else {
    debugPrint('🎧 [BG] Listening for: $employeeId');
  }

  // Load shown IDs mula sa prefs
  final shownIds = <String>{};
  try {
    final prefs = await SharedPreferences.getInstance();
    shownIds.addAll(prefs.getStringList('bg_shown_notif_ids') ?? []);
  } catch (_) {}

  Future<void> saveShownIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = shownIds.length > 100
          ? shownIds.toList().sublist(shownIds.length - 100)
          : shownIds.toList();
      await prefs.setStringList('bg_shown_notif_ids', list);
    } catch (_) {}
  }

  // Polling loop — every 15 seconds
  Timer.periodic(const Duration(seconds: 15), (timer) async {
    try {
      // Re-read employeeId (baka nag-login o nag-logout)
      String? currentEmpId;
      try {
        final prefs = await SharedPreferences.getInstance();
        currentEmpId = prefs.getString('fp_preauth_employee_id');
      } catch (_) {}

      if (currentEmpId == null || currentEmpId.isEmpty) return;

      // Query Firestore
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection('employee_notifications')
            .where('employeeId', whereIn: [currentEmpId, 'ALL'])
            .where('read', isEqualTo: false)
            .limit(20)
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('⚠️ [BG] Firestore fetch error: $e');
        return;
      }

      for (final doc in snap.docs) {
        if (shownIds.contains(doc.id)) continue;
        shownIds.add(doc.id);
        await saveShownIds();

        final data = doc.data();
        final title = data['title']?.toString() ?? 'Notification';
        final body = data['message']?.toString() ?? '';
        final type = data['type']?.toString() ?? 'general';

        try {
          await notifPlugin.show(
            doc.id.hashCode & 0x7FFFFFFF,
            title,
            body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                'employee_notifications_channel',
                'Employee Notifications',
                channelDescription: 'Notifications from admin / HRIS',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                playSound: true,
                enableVibration: true,
                styleInformation: BigTextStyleInformation(body),
              ),
            ),
            payload: jsonEncode({'type': type, 'notifId': doc.id}),
          );
          debugPrint('🔔 [BG] Shown: $title');
        } catch (e) {
          debugPrint('⚠️ [BG] Show error: $e');
        }
      }
    } catch (e) {
      // Outer try-catch para hindi mag-crash ang timer
      debugPrint('⚠️ [BG] Poll cycle error: $e');
    }
  });
}

// ═══════════════════════════════════════════════════════════════
// CONTROLLER — para sa main app (start/stop)
// ═══════════════════════════════════════════════════════════════
class KilledStateListener {
  KilledStateListener._();
  static final KilledStateListener instance = KilledStateListener._();

  static const String _channelId = 'hris_bg_service';
  static const int _notifId = 9001;
  bool _configured = false;

  Future<void> start() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    try {
      final service = FlutterBackgroundService();

      if (!_configured) {
        await service.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: onStart,
            isForegroundMode: true,
            autoStart: false,
            autoStartOnBoot: false,
            notificationChannelId: _channelId,
            initialNotificationTitle: 'HRIS Active',
            initialNotificationContent: 'Monitoring attendance',
            foregroundServiceNotificationId: _notifId,
            foregroundServiceTypes: [
              AndroidForegroundType.dataSync,
            ],
          ),
          iosConfiguration: IosConfiguration(
            autoStart: false,
            onForeground: onStart,
            onBackground: (service) => true,
          ),
        );
        _configured = true;
      }

      final isRunning = await service.isRunning();
      if (!isRunning) {
        await service.startService();
        debugPrint('✅ [BG] Service started');
      } else {
        debugPrint('ℹ️ [BG] Already running');
      }
    } catch (e) {
      debugPrint('❌ [BG] start error: $e');
    }
  }

  Future<void> stop() async {
    if (kIsWeb) return;
    try {
      FlutterBackgroundService().invoke('stopService');
      debugPrint('🛑 [BG] Stop requested');
    } catch (e) {
      debugPrint('⚠️ [BG] stop error: $e');
    }
  }

  /// Tawagin pagkatapos ng login para siguradong may employee ID
  Future<void> setEmployeeId(String employeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fp_preauth_employee_id', employeeId);
      debugPrint('✅ [BG] Employee ID set: $employeeId');
    } catch (e) {
      debugPrint('⚠️ [BG] setEmployeeId error: $e');
    }
  }
}