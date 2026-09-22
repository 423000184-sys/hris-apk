// lib/services/notification_preference_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';

class NotificationPreferenceService {
  NotificationPreferenceService._();
  static final NotificationPreferenceService instance =
  NotificationPreferenceService._();

  static const String _keyPushEnabled = 'push_notifications_enabled';

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
        // ✅ Reschedule daily 7:30 AM reminder — ENGLISH
        try {
          await LocalNotificationService.instance
              .scheduleDailyWorkReminder(
            hour: 7,
            minute: 30,
            title: '⏰ Go to Work!',
            body: 'Time to go to work! Clock in before 8:00 AM.',
          );
          debugPrint('✅ [NotifPref] Daily reminder RESCHEDULED');
        } catch (e) {
          debugPrint('⚠️ [NotifPref] reschedule error: $e');
        }
      } else {
        // ❌ Cancel all scheduled notifications
        try {
          await LocalNotificationService.instance.cancelAll();
          debugPrint('🚫 [NotifPref] All notifications CANCELLED');
        } catch (e) {
          debugPrint('⚠️ [NotifPref] cancel error: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ [NotifPref] save error: $e');
    }
  }
}