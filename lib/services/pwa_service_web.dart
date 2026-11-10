// lib/services/pwa_service_web.dart
import 'package:flutter/material.dart';
import 'package:pwa_installer/pwa_installer.dart';

class PwaService {
  static void init({
    bool enableBrowserRedirect = true,
    bool enableMobileInstallGuide = true,
    bool enableDesktopInstallGuide = true,
  }) {
    PwaInstaller.init(
      enableBrowserRedirect: enableBrowserRedirect,
      enableMobileInstallGuide: enableMobileInstallGuide,
      enableDesktopInstallGuide: enableDesktopInstallGuide,
    );
  }

  static Widget wrap({
    required String appName,
    required Widget logo,
    required Widget child,
  }) {
    return PwaInstaller(
      appName: appName,
      logo: logo,
      child: child,
    );
  }
}