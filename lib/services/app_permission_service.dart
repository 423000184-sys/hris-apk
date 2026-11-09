import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  static final AppPermissionService instance = AppPermissionService._();
  AppPermissionService._();

  Future<void> requestAllPermissions(BuildContext context) async {
    await _requestPermission(
      context,
      permission: Permission.notification,
      title: 'Allow Notifications',
      description: 'We need this to send you real-time updates, payroll alerts, and important company announcements.',
    );

    bool isLocationGranted = await _requestPermission(
      context,
      permission: Permission.locationWhenInUse,
      title: 'Allow Location',
      description: 'Your location is required to verify your time-in and time-out at the office.',
    );

    if (isLocationGranted) {
      await _requestPermission(
        context,
        permission: Permission.locationAlways,
        title: 'Allow Background Location',
        description: 'To automatically clock you in/out even when the app is minimized or the screen is locked, please select "Allow all the time" on the next screen.',
        isBackgroundLocation: true,
      );
    }
  }

  Future<bool> requestCameraPermission(BuildContext context) async {
    return await _requestPermission(
      context,
      permission: Permission.camera,
      title: 'Allow Camera',
      description: 'We need access to your camera to scan your face for attendance verification.',
    );
  }

  Future<bool> requestMicrophonePermission(BuildContext context) async {
    return await _requestPermission(
      context,
      permission: Permission.microphone,
      title: 'Allow Microphone',
      description: 'We need access to your microphone to detect finger snaps for quick clock-in.',
    );
  }

  Future<bool> _requestPermission(
      BuildContext context, {
        required Permission permission,
        required String title,
        required String description,
        bool isBackgroundLocation = false,
      }) async {
    var status = await permission.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (context.mounted) _showSettingsDialog(context, title, description);
      return false;
    }

    if (context.mounted) {
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isBackgroundLocation ? Icons.location_searching_rounded : Icons.security_rounded,
                color: const Color(0xFFFF8A00),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          content: Text(description, style: const TextStyle(fontSize: 14, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Now', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (shouldRequest != true) return false;
    }

    status = await permission.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      if (context.mounted) _showSettingsDialog(context, title, description);
      return false;
    }

    return false;
  }

  void _showSettingsDialog(BuildContext context, String title, String description) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$title Disabled', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'You have disabled the $title permission. To use this feature, please go to App Settings and allow it manually.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF8A00), foregroundColor: Colors.white),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}