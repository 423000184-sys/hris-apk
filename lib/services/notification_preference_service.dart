// lib/services/notification_preference_service.dart
// v1.1: ✅ Verify permissions bago mag-schedule
//       ✅ Consistent title/body sa NotificationService
//       ✅ Diagnostics log pagkatapos mag-toggle
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';

class NotificationPreferenceService {
  NotificationPreferenceService._();
  static final NotificationPreferenceService instance =
  NotificationPreferenceService._();

  static const String _keyPushEnabled = 'push_notifications_enabled';

  // 🎯 Consistent defaults — same as LocalNotificationService
  static const int _reminderHour = 7;
  static const int _reminderMinute = 30;
  static const String _reminderTitle = '⏰ Time to Go to Work!';
  static const String _reminderBody =
      'Clock in before 8:00 AM. Be safe on the way! 🚶‍♂️';

  /// Default: ON
  Future<bool> isPushEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyPushEnabled) ?? true;
    } catch (e) {
      debugPrint('⚠️ [NotifPref] read error: $e');
      return true;
    }
  }

  Future<void> setPushEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPushEnabled, enabled);
      debugPrint('🔔 [NotifPref] Push notifications: '
          '${enabled ? "ENABLED" : "DISABLED"}');

      if (enabled) {
        await _enableAndSchedule();
      } else {
        await _disableAndCancel();
      }

      // 🔍 Diagnostics — log para makita ang status
      try {
        await LocalNotificationService.instance.runDiagnostics();
      } catch (e) {
        debugPrint('⚠️ [NotifPref] diagnostics error: $e');
      }
    } catch (e) {
      debugPrint('❌ [NotifPref] save error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ ENABLE: Request permissions muna, tapos schedule
  // ═══════════════════════════════════════════════════════════════
  Future<void> _enableAndSchedule() async {
    try {
      // 🔑 STEP 1: Request permissions (notifications + exact alarm)
      //    Kailangan ito para sure na consistent ang notification.
      final granted =
      await LocalNotificationService.instance.requestPermissions();
      debugPrint('🔑 [NotifPref] Permissions granted: $granted');

      if (!granted) {
        debugPrint('⚠️ [NotifPref] Notification permission denied — '
            'cannot schedule reminder');
        return;
      }

      // 🔑 STEP 2: Schedule daily reminder with EXACT mode
      await LocalNotificationService.instance.scheduleDailyWorkReminder(
        hour: _reminderHour,
        minute: _reminderMinute,
        title: _reminderTitle,
        body: _reminderBody,
      );
      debugPrint('✅ [NotifPref] Daily reminder scheduled '
          'at $_reminderHour:'
          '${_reminderMinute.toString().padLeft(2, '0')}');
    } catch (e) {
      debugPrint('⚠️ [NotifPref] schedule error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ❌ DISABLE: Cancel all scheduled notifications
  // ═══════════════════════════════════════════════════════════════
  Future<void> _disableAndCancel() async {
    try {
      await LocalNotificationService.instance.cancelAll();
      debugPrint('🚫 [NotifPref] All notifications CANCELLED');
    } catch (e) {
      debugPrint('⚠️ [NotifPref] cancel error: $e');
    }
  }
}