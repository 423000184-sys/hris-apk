// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'services/network_guard.dart';
import 'widgets/network_gate.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Start global network monitoring
  try {
    await NetworkGuard.instance.start();
    debugPrint(
        '🌐 NetworkGuard started (online=${NetworkGuard.instance.isOnline})');
  } catch (e) {
    debugPrint('⚠️ NetworkGuard start failed: $e');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    debugPrint('Firebase Initialized Successfully');
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
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme_mode');
    debugPrint('🌗 Theme pref reset to system default');
  } catch (e) {
    debugPrint('🌗 Reset error: $e');
  }

  const String startPage =
  String.fromEnvironment('page', defaultValue: 'landing');

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const MyApp(startPage: startPage),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String startPage;
  const MyApp({super.key, required this.startPage});

  @override
  Widget build(BuildContext context) {
    // ✅ Kung admin, WALANG NetworkGate — exempt
    final bool isAdmin = startPage == 'admin';

    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
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

          // ✅ NetworkGate ONLY for employee side
          builder: (context, child) {
            if (isAdmin) {
              // Admin: walang blocking overlay
              return child ?? const SizedBox.shrink();
            }
            // Employee: full network guard
            return NetworkGate(
              child: child ?? const SizedBox.shrink(),
            );
          },

          home: SplashScreen(startPage: startPage),
        );
      },
    );
  }
}