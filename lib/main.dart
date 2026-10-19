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
import 'package:onesignal_flutter/onesignal_flutter.dart'; // 🆕

import 'screens/splash_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/landing_screen.dart';
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
import 'services/demo_mode_service.dart'; // 🎭 NEW
import 'widgets/network_gate.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';

import 'data/local/dao/connectivity_service.dart';

// 🆕 OneSignal App ID
const String kOneSignalAppId = '0c862ae2-7ee8-46db-8f9e-6740e82c065c';

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

    // ═══════════════════════════════════════════════════════════════
    // 🎭 LOAD DEMO MODE (early — bago ang lahat ng UI)
    // ═══════════════════════════════════════════════════════════════
    try {
      await DemoModeService.instance.load();
      debugPrint('🎭 [DemoMode] Loaded — '
          'enabled=${DemoModeService.instance.isEnabled}');
    } catch (e) {
      debugPrint('⚠️ [DemoMode] Load failed: $e');
    }

    // ═══════════════════════════════════════════════════════════════
    // 🆕 REGISTER FCM BACKGROUND HANDLER
    // ═══════════════════════════════════════════════════════════════
    if (!kIsWeb) {
      try {
        FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler);
        debugPrint('🔔 [FCM] Background handler registered');
      } catch (e) {
        debugPrint('⚠️ [FCM] Background handler failed: $e');
      }
    }

    try {
      await SecurityService.instance.bootstrap();
      debugPrint('🔒 [Security] Bootstrap complete');
    } catch (e) {
      debugPrint('⚠️ Security bootstrap failed: $e');
    }

    try {
      await NetworkGuard.instance.start();
      debugPrint('🌐 NetworkGuard started');
    } catch (e) {
      debugPrint('⚠️ NetworkGuard start failed: $e');
    }

    try {
      await ConnectivityService.instance.init();
    } catch (e) {
      debugPrint('⚠️ ConnectivityService init failed: $e');
    }

    try {
      await LanguageService.instance.init();
    } catch (e) {
      debugPrint('⚠️ LanguageService init failed: $e');
    }

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
      debugPrint('Firebase Initialized Successfully');

      await _initAppCheck();

      // ═══════════════════════════════════════════════════════════════
      // 🆕 INITIALIZE ONESIGNAL
      // ═══════════════════════════════════════════════════════════════
      if (!kIsWeb) {
        try {
          OneSignal.Debug.setLogLevel(OSLogLevel.none);
          OneSignal.initialize(kOneSignalAppId);
          OneSignal.Notifications.requestPermission(true);
          debugPrint('🔔 [OneSignal] Initialized — App ID: $kOneSignalAppId');
        } catch (e) {
          debugPrint('⚠️ [OneSignal] Init failed: $e');
        }
      }

      // ═══════════════════════════════════════════════════════════
      // 🔥 SET PERSISTENCE TO LOCAL FOR WEB
      // ═══════════════════════════════════════════════════════════
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance
              .setPersistence(Persistence.LOCAL)
              .timeout(const Duration(seconds: 3));
          debugPrint('✅ [main] Persistence = LOCAL');
        } catch (e) {
          debugPrint('⚠️ [main] setPersistence failed: $e');
        }
      }

      // Firestore write test
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
      } catch (e) {
        debugPrint('❌ Firestore FAIL: $e');
      }

      try {
        await AdminNotificationQueue.instance.init();
        debugPrint('📥 AdminNotificationQueue READY');
      } catch (e) {
        debugPrint('⚠️ AdminNotificationQueue init failed: $e');
      }

      try {
        await AdminNotificationAlertService.instance.init();
        debugPrint('🔔 AdminNotificationAlertService READY');
      } catch (e) {
        debugPrint('⚠️ AdminNotifAlertService init failed: $e');
      }

      try {
        await NotificationBackupService.instance.init();
        debugPrint('💾 NotificationBackupService READY');
      } catch (e) {
        debugPrint('⚠️ NotificationBackupService init failed: $e');
      }

      try {
        await FcmService.instance.init();
        debugPrint('🔔 [FCM] FcmService initialized');
      } catch (e) {
        debugPrint('⚠️ [FCM] FcmService init failed: $e');
      }
    } catch (e) {
      debugPrint('Firebase Initialization Failed/Timed Out: $e');
    }

    if (!kIsWeb) {
      try {
        await DatabaseService.instance.database
            .timeout(const Duration(seconds: 3));
        debugPrint('Local Database Initialized');
      } catch (e) {
        debugPrint('Local DB Init Failed: $e');
      }

      try {
        await OfflineAttendanceService.instance.init();
        debugPrint('✅ Offline attendance initialized');

        await Future.delayed(const Duration(seconds: 1));
        await OfflineAttendanceService.instance.dumpAll();

        NetworkGuard.instance.onStatusChange.listen((online) {
          if (online) {
            debugPrint('🌐 Online → syncing pending attendance...');
            OfflineAttendanceService.instance.syncPending();
          }
        });

        OfflineAttendanceService.instance.startAutoSync();
      } catch (e) {
        debugPrint('⚠️ Offline attendance init failed: $e');
      }

      try {
        await LocalNotificationService.instance.init();
        debugPrint('🔔 LocalNotificationService initialized');

        await Future.delayed(const Duration(seconds: 1));

        final granted =
        await LocalNotificationService.instance.requestPermissions();
        debugPrint('🔔 Permission granted: $granted');

        if (granted) {
          await LocalNotificationService.instance.scheduleDailyWorkReminder(
            hour: 7,
            minute: 30,
            title: '⏰ Go to Work!',
            body: 'Time to go to work! Clock in before 8:00 AM.',
          );
          await LocalNotificationService.instance.runDiagnostics();
        }

        try {
          final prefs = await SharedPreferences.getInstance();
          final lastEmpId =
              prefs.getString('fp_preauth_employee_id') ??
                  prefs.getString('last_logged_in_employee_id');

          if (lastEmpId != null && lastEmpId.isNotEmpty) {
            await EmployeeNotificationListener.instance.start(lastEmpId);
            debugPrint('🎧 [Global NotifListener] Started for $lastEmpId');
          } else {
            debugPrint(
                '🎧 [Global NotifListener] No employee ID — will start on login');
          }
        } catch (e) {
          debugPrint('⚠️ [Global NotifListener] Start failed: $e');
        }
      } catch (e) {
        debugPrint('⚠️ Notification init failed: $e');
      }
    }

    if (kIsWeb) {
      try {
        await LocalNotificationService.instance.init();
        debugPrint('🔔 [Web] LocalNotificationService initialized');

        final prefs = await SharedPreferences.getInstance();
        final lastEmpId =
            prefs.getString('fp_preauth_employee_id') ??
                prefs.getString('last_employee_employee_id');

        if (lastEmpId != null && lastEmpId.isNotEmpty) {
          await EmployeeNotificationListener.instance.start(lastEmpId);
          debugPrint('🎧 [Web NotifListener] Started for $lastEmpId');
        } else {
          debugPrint('🎧 [Web NotifListener] No employee ID — skip');
        }
      } catch (e) {
        debugPrint('⚠️ [Web] Notification init failed: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('theme_mode');
    } catch (e) {
      debugPrint('🌗 Reset error: $e');
    }

    if (kIsWeb) {
      debugPrint('🔍 [Auth] Waiting for session restore...');
      for (int i = 0; i < 6; i++) {
        if (FirebaseAuth.instance.currentUser != null) {
          debugPrint(
              '✅ [Auth] User restored after ${i * 500}ms: '
                  '${FirebaseAuth.instance.currentUser!.uid}');
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (FirebaseAuth.instance.currentUser == null) {
        debugPrint('❌ [Auth] No user session found after 3s');
      }
    }

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

Future<void> _initAppCheck() async {
  debugPrint('🔒 App Check: skipped (not configured)');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 💻 KAPAG WEB (PC/Laptop/Mac) = AUTOMATIC NA ADMIN DASHBOARD
    // 📱 KAPAG MOBILE (APK/iOS) = AUTOMATIC NA EMPLOYEE LANDING SCREEN
    final bool isAdmin = kIsWeb;

    return Consumer2<ThemeNotifier, LanguageService>(
      builder: (context, themeNotifier, langService, child) {
        return MaterialApp(
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
            // Kung Admin, wag na lagyan ng NetworkGate para hindi mag-clash
            if (isAdmin) return child ?? const SizedBox.shrink();
            return NetworkGate(
              showBannerOnly: true,
              child: child ?? const SizedBox.shrink(),
            );
          },
          // 🔥 AUTO-ROUTING BASE SA DEVICE
          home: isAdmin
              ? const AdminLoginScreen() // Kung naka-browser, deretso Admin Login
              : const SplashScreen(startPage: 'landing'), // Kung mobile, deretso Employee Landing
        );
      },
    );
  }
}