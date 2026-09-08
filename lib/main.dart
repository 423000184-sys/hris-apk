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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Solid status bar matching the app's orange header.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFFF8A00),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
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
          home: SplashScreen(startPage: startPage),
        );
      },
    );
  }
}