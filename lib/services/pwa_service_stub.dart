// lib/services/pwa_service_stub.dart
import 'package:flutter/material.dart';

class PwaService {
  static void init({
    bool enableBrowserRedirect = true,
    bool enableMobileInstallGuide = true,
    bool enableDesktopInstallGuide = true,
  }) {
    // Walang ginagawa para sa mobile (Android/iOS)
  }

  static Widget wrap({
    required String appName,
    required Widget logo,
    required Widget child,
  }) {
    // Ibinabalik lang ang child nang walang wrapper
    return child;
  }
}