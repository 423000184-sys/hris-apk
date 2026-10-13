// lib/services/fcm_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';

void _secureLog(String m) {
  if (kDebugMode) debugPrint('[FCM] $m');
}

// ═══════════════════════════════════════════════════════════════
// 🔔 BACKGROUND HANDLER — TOP-LEVEL (KAILANGAN ITO)
// Tumatakbo KAHIT KILLED ang app. Separate isolate.
// ═══════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage msg) async {
  debugPrint('🔔 [BG] ========== MESSAGE RECEIVED ==========');
  debugPrint('🔔 [BG] ID: ${msg.messageId}');
  debugPrint('🔔 [BG] Title: ${msg.notification?.title ?? msg.data['title']}');
  debugPrint('🔔 [BG] Body: ${msg.notification?.body ?? msg.data['body']}');
  debugPrint('🔔 [BG] Data: ${msg.data}');
  debugPrint('🔔 [BG] ==========================================');

  // Kung may `notification` payload → Android AUTO-SHOW. Skip na.
  if (msg.notification != null) {
    debugPrint('ℹ️ [BG] Notification payload → auto-show by Android');
    return;
  }

  // Kung data-only → MANUAL SHOW
  if (msg.data.isNotEmpty) {
    debugPrint('📢 [BG] Data-only → manually showing local notif');
    await _showLocalFromBackground(msg);
  }
}

Future<void> _showLocalFromBackground(RemoteMessage msg) async {
  try {
    final title = msg.data['title']?.toString() ??
        msg.notification?.title ??
        'Notification';
    final body =
        msg.data['body']?.toString() ?? msg.notification?.body ?? '';
    final type = msg.data['type']?.toString() ?? 'general';
    final priority = msg.data['priority']?.toString() ?? 'normal';

    debugPrint('📢 [BG] Showing: $title — $body');

    final plugin = FlutterLocalNotificationsPlugin();

    const androidInit =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Channel — IMPORTANT: same ID sa main isolate
    const channel = AndroidNotificationChannel(
      'employee_notifications_channel',
      'Employee Notifications',
      description: 'Notifications from admin',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    final isHigh = priority == 'high' || priority == 'critical';

    await plugin.show(
      (msg.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch) &
      0x7FFFFFFF,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'employee_notifications_channel',
          'Employee Notifications',
          channelDescription: 'Notifications from admin',
          importance: isHigh ? Importance.high : Importance.defaultImportance,
          priority: isHigh ? Priority.high : Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          autoCancel: true,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode({
        'type': type,
        'notifId': msg.data['notifId'] ?? '',
      }),
    );
    debugPrint('✅ [BG] Local notif SHOWN successfully');
  } catch (e, st) {
    debugPrint('❌ [BG] Show error: $e');
    debugPrint('$st');
  }
}

// ═══════════════════════════════════════════════════════════════
// FCM SERVICE
// ═══════════════════════════════════════════════════════════════
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  final _msg = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _initialized = false;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  static const String _kTokenKey = 'fcm_token';

  void Function(Map<String, dynamic> data)? onNotificationTap;

  Future<void> init({VoidCallback? onNotificationTapCallback}) async {
    if (_initialized) {
      _secureLog('⏩ Already initialized');
      return;
    }
    _initialized = true;

    _secureLog('🚀 Initializing FCM...');

    // 1) Permission
    try {
      final settings = await _msg.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _secureLog('🔔 Permission: ${settings.authorizationStatus}');
    } catch (e) {
      _secureLog('⚠️ Permission: $e');
    }

    // 2) Foreground listener
    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((msg) {
      _secureLog('📩 [FG] Message: ${msg.notification?.title}');
      _showViaLocalService(msg);
    });

    // 3) Background tap
    await _openedSub?.cancel();
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _secureLog('👆 Tapped: ${msg.data}');
      _handleTap(msg.data);
    });

    // 4) Terminated tap
    try {
      final initialMsg = await _msg.getInitialMessage();
      if (initialMsg != null) {
        _secureLog('🚀 Opened from terminated');
        _handleTap(initialMsg.data);
      }
    } catch (e) {
      _secureLog('⚠️ getInitialMessage: $e');
    }

    // 5) Token
    await _refreshToken();

    // 6) Token refresh
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _msg.onTokenRefresh.listen((newToken) {
      _secureLog('🔄 Token refreshed');
      _currentToken = newToken;
      _saveToken(newToken);
    });

    // 7) iOS foreground presentation
    try {
      await _msg.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    _secureLog('✅ FCM initialized');
  }

  Future<void> _showViaLocalService(RemoteMessage msg) async {
    final notif = msg.notification;
    final title = notif?.title ?? msg.data['title']?.toString();
    final body = notif?.body ?? msg.data['body']?.toString();

    if (title == null) return;

    try {
      await LocalNotificationService.instance.show(
        id: (msg.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch) &
        0x7FFFFFFF,
        title: title,
        body: body ?? '',
        payload: jsonEncode(msg.data),
      );
      _secureLog('🔔 Shown via LocalNotificationService');
    } catch (e) {
      _secureLog('⚠️ Local show failed: $e');
    }
  }

  void _handleTap(Map<String, dynamic> data) {
    onNotificationTap?.call(data);
    _secureLog('📬 Notification tapped: $data');
  }

  Future<void> _refreshToken() async {
    try {
      final token = await _msg.getToken();
      if (token == null || token.isEmpty) {
        _secureLog('⚠️ No FCM token');
        return;
      }
      _currentToken = token;
      _secureLog('🎫 Token: ${token.substring(0, 20)}...');
      await _saveToken(token);
    } catch (e) {
      _secureLog('⚠️ Token fetch: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final empId = prefs.getString('fp_preauth_employee_id');
      if (empId == null || empId.isEmpty) return;

      await _firestore.collection('employees').doc(empId).set({
        'fcmToken': token,
        'fcmPlatform': kIsWeb
            ? 'web'
            : (Platform.isAndroid ? 'android' : 'ios'),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _secureLog('✅ Token saved to employee $empId');
    } catch (e) {
      _secureLog('⚠️ Save token: $e');
    }
  }

  Future<void> associateWithEmployee(String employeeDocId) async {
    if (_currentToken == null) await _refreshToken();
    if (_currentToken == null) return;

    try {
      await _firestore.collection('employees').doc(employeeDocId).set({
        'fcmToken': _currentToken,
        'fcmPlatform': kIsWeb
            ? 'web'
            : (Platform.isAndroid ? 'android' : 'ios'),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _secureLog('✅ FCM token associated with $employeeDocId');
    } catch (e) {
      _secureLog('⚠️ Associate: $e');
    }
  }

  Future<void> clearEmployeeToken(String employeeDocId) async {
    try {
      await _firestore.collection('employees').doc(employeeDocId).set({
        'fcmToken': FieldValue.delete(),
        'fcmUpdatedAt': FieldValue.delete(),
        'fcmPlatform': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _initialized = false;
  }
}