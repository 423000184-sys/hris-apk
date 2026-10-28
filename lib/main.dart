// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'screens/splash_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/employee_notifications_screen.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'services/network_guard.dart';
import 'services/local_notification_service.dart';
import 'services/offline_attendance_service.dart';
import 'services/admin_notification_alert_service.dart';
import 'services/admin_notification_queue.dart';
import 'services/notification_backup_service.dart';
import 'services/language_service.dart';
import 'services/security_service.dart';
import 'services/fcm_service.dart';
import 'services/employee_notification_listener.dart';
import 'services/demo_mode_service.dart';
import 'widgets/network_gate.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';

import 'data/local/dao/connectivity_service.dart';

const String kOneSignalAppId = '0c862ae2-7ee8-46db-8f9e-6740e82c065c';

// 🆕 Global navigator key — ginagamit para sa notification routing
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _logGlobalError(Object error, StackTrace stack) async {
  try {
    debugPrint('🚨 [Global Error] $error');
    debugPrint('🚨 [Global Stack] $stack');

    if (!kIsWeb) {
      try {
        await FirebaseFirestore.instance
            .collection('security_events')
            .add({
          'type': 'app_error',
          'severity': 'high',
          'details': error.toString(),
          'stack': stack.toString().substring(
              0,
              stack.toString().length > 500
                  ? 500
                  : stack.toString().length),
          'platform': 'mobile',
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  } catch (_) {}
}

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _logGlobalError(details.exception, details.stack ?? StackTrace.empty);
    };

    try {
      await DemoModeService.instance.load();
    } catch (e) {
      debugPrint('⚠️ [DemoMode] Load failed: $e');
    }

    if (!kIsWeb) {
      try {
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
      } catch (e) {
        debugPrint('⚠️ [FCM] Background handler failed: $e');
      }
    }

    try {
      await SecurityService.instance.bootstrap();
    } catch (e) {
      debugPrint('⚠️ Security bootstrap failed: $e');
    }

    try {
      await NetworkGuard.instance.start();
    } catch (e) {}

    try {
      await ConnectivityService.instance.init();
    } catch (e) {}

    try {
      await LanguageService.instance.init();
    } catch (e) {}

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
      debugPrint('Firebase Initialized Successfully');

      // ═══════════════════════════════════════════════════════════════
      // 🔔 INITIALIZE ONESIGNAL
      // ═══════════════════════════════════════════════════════════════
      try {
        OneSignal.Debug.setLogLevel(OSLogLevel.none);
        OneSignal.initialize(kOneSignalAppId);

        // 🆕 Request permission (iOS + Android 13+)
        OneSignal.Notifications.requestPermission(true);
        debugPrint('🔔 [OneSignal] Initialized');

        // ✅ FOREGROUND HANDLER — para makita ang notification kahit bukas ang app
        OneSignal.Notifications.addForegroundWillDisplayListener((event) {
          debugPrint(
              '🔔 [OneSignal] Foreground notification: ${event.notification.title}');
          // Ipakita agad sa system tray / heads-up
          event.notification.display();
        });

        // ✅ CLICK HANDLER — para ma-route sa tamang screen kapag clinick
        // Gagana ito kahit naka-killed, naka-background, o naka-foreground ang app
        OneSignal.Notifications.addClickListener((event) {
          debugPrint(
              '🔔 [OneSignal] Notification clicked: ${event.notification.title}');

          final data = event.notification.additionalData;
          if (data != null && data['route'] == 'notifications') {
            SharedPreferences.getInstance().then((prefs) {
              final lastEmpId = prefs.getString('fp_preauth_employee_id') ??
                  prefs.getString('last_logged_in_employee_id');

              if (lastEmpId != null && lastEmpId.isNotEmpty) {
                navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EmployeeNotificationsScreen(employeeId: lastEmpId),
                  ),
                );
              }
            });
          }
        });
      } catch (e) {
        debugPrint('⚠️ [OneSignal] Init failed: $e');
      }

      if (kIsWeb) {
        try {
          await FirebaseAuth.instance
              .setPersistence(Persistence.LOCAL)
              .timeout(const Duration(seconds: 3));
        } catch (e) {}
      }

      try {
        final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
        final testRef = FirebaseFirestore.instance
            .collection('test_collection')
            .doc(testId);
        await testRef.set({
          'test': true,
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10));
        await testRef.delete();
        debugPrint('✅ Firestore OK');
      } catch (e) {}

      try { await AdminNotificationQueue.instance.init(); } catch (e) {}
      try { await AdminNotificationAlertService.instance.init(); } catch (e) {}
      try { await NotificationBackupService.instance.init(); } catch (e) {}
      try { await FcmService.instance.init(); } catch (e) {}
    } catch (e) {
      debugPrint('Firebase Initialization Failed/Timed Out: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // 🔔 AUTO-LINK ONESIGNAL — i-link ang device sa huling employee
    //    na nag-login dito. Ito ang nagsisigurong kahit naka-killed ang
    //    app, makakarating pa rin ang push notification sa device.
    //    ⚠️ IMPORTANTE: Ang employeeId na ito ay dapat EXACT MATCH sa
    //       external_id na ginagamit ng `OneSignalSender.sendToEmployee()`.
    // ═══════════════════════════════════════════════════════════════
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastEmpId = prefs.getString('fp_preauth_employee_id') ??
          prefs.getString('last_logged_in_employee_id');

      if (lastEmpId != null && lastEmpId.isNotEmpty) {
        OneSignal.login(lastEmpId);
        debugPrint('🔔 [OneSignal] Auto-linked device to employee: $lastEmpId');

        // I-start ang in-app listener para sa live badge/notification screen
        if (!kIsWeb) {
          try {
            await EmployeeNotificationListener.instance.start(lastEmpId);
          } catch (e) {}
        }
      } else {
        debugPrint('🔔 [OneSignal] No previous employee ID on this device.');
      }
    } catch (e) {
      debugPrint('⚠️ [OneSignal] Auto-link error: $e');
    }

    if (!kIsWeb) {
      try {
        await DatabaseService.instance.database
            .timeout(const Duration(seconds: 3));
      } catch (e) {}

      try {
        await OfflineAttendanceService.instance.init();
        await Future.delayed(const Duration(seconds: 1));
        await OfflineAttendanceService.instance.dumpAll();
        NetworkGuard.instance.onStatusChange.listen((online) {
          if (online) OfflineAttendanceService.instance.syncPending();
        });
        OfflineAttendanceService.instance.startAutoSync();
      } catch (e) {}

      try {
        await LocalNotificationService.instance.init();
        await Future.delayed(const Duration(seconds: 1));
        final granted =
        await LocalNotificationService.instance.requestPermissions();
        if (granted) {
          await LocalNotificationService.instance.scheduleDailyWorkReminder(
            hour: 7,
            minute: 30,
            title: '⏰ Go to Work!',
            body: 'Time to go to work! Clock in before 8:00 AM.',
          );
        }
      } catch (e) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('theme_mode');
    } catch (e) {}

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeNotifier()),
          ChangeNotifierProvider.value(value: LanguageService.instance),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    _logGlobalError(error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = kIsWeb;

    return Consumer2<ThemeNotifier, LanguageService>(
      builder: (context, themeNotifier, langService, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'HRIS Biometrics',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeNotifier.themeMode,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
            scrollbars: false,
          ),
          builder: (context, child) {
            if (isAdmin) return child ?? const SizedBox.shrink();
            return NetworkGate(
              showBannerOnly: true,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: isAdmin
              ? const AdminLoginScreen()
              : const SplashScreen(startPage: 'landing'),
        );
      },
    );
  }
}