import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_biometrics/main.dart';
import 'package:provider/provider.dart';
import 'package:hris_biometrics/theme/theme_notifier.dart';

void main() {
  testWidgets('Splash screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final themeNotifier = ThemeNotifier();
    
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeNotifier>.value(
        value: themeNotifier,
        child: const HRISBioApp(),
      ),
    );

    // Verify that the splash screen shows the title.
    expect(find.text('HRIS Biometrics'), findsOneWidget);
  });
}
