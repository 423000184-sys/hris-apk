// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'services/network_guard.dart';
import 'services/local_notification_service.dart';
import 'services/offline_attendance_service.dart';
import 'services/admin_notification_alert_service.dart';
import 'services/admin_notification_queue.dart';
import 'services/notification_backup_service.dart';
import 'services/language_service.dart'; // 🆕
import 'widgets/network_gate.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════
  // 🌐 NETWORK GUARD
  // ═══════════════════════════════════════════════════════════
  try {
    await NetworkGuard.instance.start();
    debugPrint(
        '🌐 NetworkGuard started (online=${NetworkGuard.instance.isOnline})');
  } catch (e) {
    debugPrint('⚠️ NetworkGuard start failed: $e');
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 LANGUAGE SERVICE INIT
  // ═══════════════════════════════════════════════════════════
  try {
    await LanguageService.instance.init();
    debugPrint(
        '🌐 LanguageService initialized (lang=${LanguageService.instance.language.name})');
  } catch (e) {
    debugPrint('⚠️ LanguageService init failed: $e');
  }

  // ═══════════════════════════════════════════════════════════
  // 🔥 FIREBASE INIT + SERVICES
  // ═══════════════════════════════════════════════════════════
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    debugPrint('Firebase Initialized Successfully');

    debugPrint('═══════════════════════════════════════');
    debugPrint('🔍 FIREBASE PROJECT VERIFICATION');
    debugPrint('═══════════════════════════════════════');
    debugPrint('📦 Project ID: ${Firebase.app().options.projectId}');
    debugPrint('📦 App ID: ${Firebase.app().options.appId}');
    debugPrint('📦 Storage Bucket: ${Firebase.app().options.storageBucket}');
    debugPrint('═══════════════════════════════════════');

    // ─── Firestore write test ───────────────────────────────
    try {
      debugPrint('🧪 Testing Firestore write permission...');
      final testId = 'test_${DateTime.now().millisecondsSinceEpoch}';
      final testRef = FirebaseFirestore.instance
          .collection('test_collection')
          .doc(testId);

      await testRef.set({
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));

      final check = await testRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (check.exists) {
        debugPrint('✅ 🧪 Firestore WRITE PERMISSION OK! (verified on server)');
        await testRef.delete();
      } else {
        debugPrint('❌ 🧪 Firestore WRITE cached but NOT on server!');
      }
    } catch (e) {
      debugPrint('❌ 🧪 Firestore WRITE FAILED: $e');
      debugPrint('   → I-check mo yung Firestore Rules sa Firebase Console');
    }

    // ═══════════════════════════════════════════════════════════
    // 📥 ADMIN NOTIFICATION QUEUE
    // ═══════════════════════════════════════════════════════════
    try {
      await AdminNotificationQueue.instance.init();
      debugPrint('📥 AdminNotificationQueue READY');
    } catch (e) {
      debugPrint('⚠️ AdminNotificationQueue init failed: $e');
    }

    // ═══════════════════════════════════════════════════════════
    // 🔔 ADMIN NOTIFICATION ALERT SERVICE
    // ═══════════════════════════════════════════════════════════
    try {
      await AdminNotificationAlertService.instance.init();
      debugPrint('🔔 AdminNotificationAlertService READY');
    } catch (e) {
      debugPrint('⚠️ AdminNotifAlertService init failed: $e');
    }

    // ═══════════════════════════════════════════════════════════
    // 💾 NOTIFICATION BACKUP SERVICE
    // ═══════════════════════════════════════════════════════════
    try {
      await NotificationBackupService.instance.init();
      debugPrint('💾 NotificationBackupService READY');
    } catch (e) {
      debugPrint('⚠️ NotificationBackupService init failed: $e');
    }
  } catch (e) {
    debugPrint('Firebase Initialization Failed/Timed Out: $e');
  }

  // ═══════════════════════════════════════════════════════════
  // 📱 NATIVE-ONLY SERVICES (Android/iOS)
  // ═══════════════════════════════════════════════════════════
  if (!kIsWeb) {
    // ─── Local SQLite database ──────────────────────────────
    try {
      await DatabaseService.instance.database
          .timeout(const Duration(seconds: 3));
      debugPrint('Local Database Initialized');
    } catch (e) {
      debugPrint('Local DB Init Failed: $e');
    }

    // ─── Offline attendance ─────────────────────────────────
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

    // ─── Local notifications ────────────────────────────────
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
    } catch (e) {
      debugPrint('⚠️ Notification init failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🌗 THEME RESET
  // ═══════════════════════════════════════════════════════════
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme_mode');
    debugPrint('🌗 Theme pref reset to system default');
  } catch (e) {
    debugPrint('🌗 Reset error: $e');
  }

  // ═══════════════════════════════════════════════════════════
  // 🚀 RUN APP
  // ═══════════════════════════════════════════════════════════
  const String startPage =
  String.fromEnvironment('page', defaultValue: 'landing');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        // 🆕 Language provider — global, auto-rebuild sa lahat ng screens
        ChangeNotifierProvider.value(value: LanguageService.instance),
      ],
      child: const MyApp(startPage: startPage),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String startPage;
  const MyApp({super.key, required this.startPage});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = startPage == 'admin';

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
            if (isAdmin) return child ?? const SizedBox.shrink();
            return NetworkGate(
              showBannerOnly: true,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashScreen(startPage: startPage),
        );
      },
    );
  }
}