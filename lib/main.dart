import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'screens/landing_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/splash_screen.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'theme/theme_notifier.dart';
import 'theme/app_theme.dart'; // ← add this

void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  // Solid status bar matching the app's orange header. This also helps the
  // status bar blend with any camera-cutout "pill" some Android OEMs draw
  // around a punch-hole front camera — a plain-orange background is far
  // less jarring against it than a transparent bar showing black.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFF8A00),
      statusBarIconBrightness: Brightness.light, // light icons on dark-ish orange
      statusBarBrightness: Brightness.dark, // iOS: light icons too
    ),
  );


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


  const String startPage =
  String.fromEnvironment('page', defaultValue: 'landing');

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const MyApp(startPage: startPage),
    ),
  );

  final themeNotifier = ThemeNotifier();

  const String startPage =
  String.fromEnvironment('page', defaultValue: 'landing');
  runApp(MyApp(startPage: startPage, themeNotifier: themeNotifier));

}

class MyApp extends StatelessWidget {
  final String startPage;

  const MyApp({super.key, required this.startPage});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'HRIS Biometrics',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeNotifier.themeMode,
          // Splash screen is now the actual entry point.
          // It will navigate to AdminDashboard or LandingScreen after it finishes.
          home: SplashScreen(startPage: startPage),
        );
      },
  final ThemeNotifier themeNotifier;
  const MyApp({super.key, required this.startPage, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeNotifier>.value(
      value: themeNotifier,
      child: Consumer<ThemeNotifier>(
        builder: (context, notifier, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'HRIS Biometrics',
            theme: AppTheme.lightTheme,      // ← your full light theme
            darkTheme: AppTheme.darkTheme,   // ← your full dark theme
            themeMode: notifier.themeMode,   // ← switches globally
            home: startPage == 'admin'
                ? const AdminDashboard()
                : const LandingScreen(),
          );
        },
      ),
  }
}