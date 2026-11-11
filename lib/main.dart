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

// 🆕 CONDITIONAL IMPORT PARA SA PWA INSTALLER
import 'services/pwa_service_stub.dart'
if (dart.library.js_interop) 'services/pwa_service_web.dart';

import 'screens/splash_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/employee_notifications_screen.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
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
import 'services/device_binding_service.dart'; // 🆕
import 'widgets/network_gate.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';

import 'data/local/dao/connectivity_service.dart';

const String kOneSignalAppId = '0c862ae2-7ee8-46db-8f9e-6740e82c065c';

// 🆕 Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🆕 ═══════════════════════════════════════════════════════════════
// Startup binding check — kapag binuksan ang app, i-verify kung
// valid pa ang device binding. Kung na-revoke habang patay ang app
// (at hindi na-tap ng user ang notification), dito ma-catch.
// ═══════════════════════════════════════════════════════════════
Future<void> _startupBindingCheck() async {
  if (kIsWeb) return;

  // Bigyan ng 2 seconds ang initial frame para makapag-render
  await Future.delayed(const Duration(seconds: 2));

  try {
    final boundEmployeeId =
    await DeviceBindingService().getBoundEmployeeId();
    if (boundEmployeeId == null || boundEmployeeId.isEmpty) {
      debugPrint('🔎 [Startup] No bound employee — skipping check.');
      return;
    }

    final status =
    await DeviceBindingService().checkBinding(boundEmployeeId);

    if (!status.allowed) {
      debugPrint('🚨 [Startup] Device revoked: ${status.reason}');

      await DeviceBindingService().wipeLocalData();

      final nav = navigatorKey.currentState;
      if (nav == null) return;

      nav.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const SplashScreen(startPage: 'landing'),
        ),
        (route) => false,
      );

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        await showDialog<void>(
          context: ctx,
          builder: (dCtx) => AlertDialog(
            title: const Text('Device Revoked'),
            content: Text(
              'Na-revoke na ang device na ito ng admin.\n\n'
            '${status.reason}\n\n'
            'Kung may problema, makipag-ugnayan sa HR/Admin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dCtx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('⚠️ [Startup] Binding check failed: $e');
  }
}

// 🆕 ═══════════════════════════════════════════════════════════════
// Forced sign-out handler (existing)
// ═══════════════════════════════════════════════════════════════
StreamSubscription<void>? _forcedSignOutSub;

void _listenForForcedSignOut() {
  _forcedSignOutSub?.cancel();
  _forcedSignOutSub = AuthService.instance.onForcedSignOut.listen((_) async {
    // ✅ Guard para hindi mag-crash sa Web
    if (!kIsWeb) {
      try {
        OneSignal.logout();
      } catch (_) {}
    }

    final nav = navigatorKey.currentState;
    final ctx = navigatorKey.currentContext;
    if (nav == null || ctx == null) return;

    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SplashScreen(startPage: 'landing'),
      ),
      (route) => false,
    );

    final newCtx = navigatorKey.currentContext;
    if (newCtx != null) {
      showDialog<void>(
        context: newCtx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Naka-logout ka'),
          content: const Text(
            'May ibang device na nag-login sa account mo kaya na-logout ka sa device na ito.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  });
}

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
      // 🔔 INITIALIZE ONESIGNAL (MOBILE ONLY)
      // ═══════════════════════════════════════════════════════════════
      // ✅ Inayos natin ito: Nilagyan ng if(!kIsWeb) para hindi
      // mag-throw ng MissingPluginException sa browser.
      if (!kIsWeb) {
        try {
          OneSignal.Debug.setLogLevel(OSLogLevel.none);
          OneSignal.initialize(kOneSignalAppId);

          OneSignal.Notifications.requestPermission(true);
          debugPrint('🔔 [OneSignal] Initialized');

          // ✅ FOREGROUND HANDLER
          OneSignal.Notifications.addForegroundWillDisplayListener((event) {
            final data = event.notification.additionalData;

            // 🚨 DEVICE_REVOKED → wipe agad, huwag i-display ang notification
            if (data != null && data['type'] == 'DEVICE_REVOKED') {
              debugPrint('🚨 [OneSignal] DEVICE_REVOKED (foreground) — wiping...');
              DeviceBindingService().wipeLocalData().then((_) {
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SplashScreen(startPage: 'landing'),
                  ),
                  (route) => false,
                );
              });
              return; // Suppress — huwag i-display ang notif
            }

            // Normal notification
            debugPrint(
              '🔔 [OneSignal] Foreground notification: ${event.notification.title}');
            event.notification.display();
          });

          // ✅ CLICK HANDLER
          OneSignal.Notifications.addClickListener((event) async {
            debugPrint(
              '🔔 [OneSignal] Notification clicked: ${event.notification.title}');

            final data = event.notification.additionalData;

            // 🚨 DEVICE_REVOKED → wipe agad
            if (data != null && data['type'] == 'DEVICE_REVOKED') {
              debugPrint('🚨 [OneSignal] DEVICE_REVOKED (click) — wiping...');
              await DeviceBindingService().wipeLocalData();
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const SplashScreen(startPage: 'landing'),
                ),
                (route) => false,
              );
              return;
            }

            // Existing routing
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
      } else {
        debugPrint('⚠️ [OneSignal] Skipped initialization on Web.');
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
    // One device, one login — resume session
    // ═══════════════════════════════════════════════════════════════
    bool sessionOk = true;
    if (!kIsWeb) {
      try {
        if (AuthService.instance.currentUser != null) {
          sessionOk = await AuthService.instance
          .resumeSession()
          .timeout(const Duration(seconds: 5), onTimeout: () => true);
        }
      } catch (e) {
        debugPrint('⚠️ [Session] Resume failed: $e');
      }
      _listenForForcedSignOut();
    }

    // ═══════════════════════════════════════════════════════════════
    // 🔔 Auto-link OneSignal (MOBILE ONLY)
    // ═══════════════════════════════════════════════════════════════
    if (!kIsWeb) {
      try {
        if (!sessionOk) {
          OneSignal.logout();
          debugPrint(
            '🔔 [OneSignal] Skipped auto-link: session taken by another device.');
        } else {
          final prefs = await SharedPreferences.getInstance();
          final lastEmpId = prefs.getString('fp_preauth_employee_id') ??
          prefs.getString('last_logged_in_employee_id');

          if (lastEmpId != null && lastEmpId.isNotEmpty) {
            OneSignal.login(lastEmpId);
            debugPrint(
              '🔔 [OneSignal] Auto-linked device to employee: $lastEmpId');

            if (!kIsWeb) {
              try {
                await EmployeeNotificationListener.instance.start(lastEmpId);
              } catch (e) {}
            }
          } else {
            debugPrint('🔔 [OneSignal] No previous employee ID on this device.');
          }
        }
      } catch (e) {
        debugPrint('⚠️ [OneSignal] Auto-link error: $e');
      }
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

    // 🆕 PWA INITIALIZATION
    PwaService.init(
      enableBrowserRedirect: true,
      enableMobileInstallGuide: true,
      enableDesktopInstallGuide: false, // <--- BINAGO NATIN ITO PARA SA ADMIN
    );

    // 🆕 Register post-frame binding check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupBindingCheck();
    });

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
    final bool isAdmin = kIsWeb && !Uri.base.host.contains('employee');

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
            // 🆕 KUNG ADMIN, DERETSO SA APP (Walang PWA wrapper)
            if (isAdmin) {
              return child ?? const SizedBox.shrink();
            }

            // Kung Employee (Mobile o Web), i-wrap sa PWA at NetworkGate
            return PwaService.wrap(
              appName: 'HRIS Biometrics',
              logo: Image.asset('assets/images/logo.png'),
              child: NetworkGate(
                showBannerOnly: true,
                child: child ?? const SizedBox.shrink(),
              ),
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
