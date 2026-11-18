// lib/services/notification_preference_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_notification_service.dart';

class NotificationPreferenceService {
  NotificationPreferenceService._();
  static final NotificationPreferenceService instance =
      NotificationPreferenceService._();

  static const String _keyPushEnabled = 'push_notifications_enabled';

  // 🎯 Iisang source ng oras at text ng work reminder
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

      try {
        await LocalNotificationService.instance.runDiagnostics();
      } catch (e) {
        debugPrint('⚠️ [NotifPref] diagnostics error: $e');
      }
    } catch (e) {
      debugPrint('❌ [NotifPref] save error: $e');
    }
  }

  /// Tawagin sa main() pagkatapos ng LocalNotificationService.init(),
  /// at sa didChangeAppLifecycleState(resumed).
  /// Self-heal: ibabalik ang alarm kung nawala, at ina-upgrade sa exact
  /// kapag na-allow na ang permission.
  Future<void> ensureReminderScheduled() async {
    try {
      if (!await isPushEnabled()) return;
      await _schedule();
    } catch (e) {
      debugPrint('⚠️ [NotifPref] ensure schedule error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ ENABLE: Humingi ng permissions, tapos mag-schedule
  // ═══════════════════════════════════════════════════════════════
  Future<void> _enableAndSchedule() async {
    try {
      // Sa Android 12+, nagbubukas lang ng Settings ang exact alarm request
      // at agad nagre-return. Kaya hindi ito dapat harang sa pag-schedule.
      final granted =
          await LocalNotificationService.instance.requestPermissions();
      debugPrint('🔑 [NotifPref] Permissions granted: $granted');

      await _schedule();
    } catch (e) {
      debugPrint('⚠️ [NotifPref] schedule error: $e');
    }
  }

  Future<void> _schedule() async {
    await LocalNotificationService.instance.scheduleDailyWorkReminder(
      hour: _reminderHour,
      minute: _reminderMinute,
      title: _reminderTitle,
      body: _reminderBody,
    );
    debugPrint('✅ [NotifPref] Daily reminder scheduled at $_reminderHour:'
        '${_reminderMinute.toString().padLeft(2, '0')}');
  }

  // ═══════════════════════════════════════════════════════════════
  // ❌ DISABLE: Work reminder lang ang cina-cancel (id 8001)
  //    Hindi cancelAll() para hindi mabura ang overtime reminders
  // ═══════════════════════════════════════════════════════════════
  Future<void> _disableAndCancel() async {
    try {
      await LocalNotificationService.instance.cancelDailyWorkReminder();
      debugPrint('🚫 [NotifPref] Work reminder CANCELLED');
    } catch (e) {
      debugPrint('⚠️ [NotifPref] cancel error: $e');
    }
  }
}