// lib/services/language_service.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { english, tagalog }

// ══════════════════════════════════════════════════════════════
// 🌐 LANGUAGE SERVICE — Global language provider
//
// Usage:
//   1. Initialize sa main.dart: await LanguageService.instance.init();
//   2. Wrap app with ChangeNotifierProvider.value(value: LanguageService.instance)
//   3. Sa widget: LanguageService.instance.t('sign_out') // → "Sign Out"
//   4. Sa widget: context.watch<LanguageService>().t('sign_out') // auto-rebuild
//   5. Change language: LanguageService.instance.setLanguage(AppLanguage.tagalog);
// ══════════════════════════════════════════════════════════════
class LanguageService extends ChangeNotifier {
  LanguageService._();
  static final LanguageService instance = LanguageService._();

  static const String _prefsKey = 'app_language';

  AppLanguage _language = AppLanguage.english;
  AppLanguage get language => _language;
  bool get isTagalog => _language == AppLanguage.tagalog;
  bool get isEnglish => _language == AppLanguage.english;

  /// Load saved language preference
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      _language = saved == 'tagalog'
          ? AppLanguage.tagalog
          : AppLanguage.english;
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ [Language] Init error: $e');
    }
  }

  /// Change language and persist
  Future<void> setLanguage(AppLanguage lang) async {
    if (_language == lang) return;
    _language = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        lang == AppLanguage.tagalog ? 'tagalog' : 'english',
      );
    } catch (e) {
      debugPrint('⚠️ [Language] Save error: $e');
    }
  }

  /// Toggle between English and Tagalog
  Future<void> toggle() async {
    await setLanguage(
      _language == AppLanguage.english
          ? AppLanguage.tagalog
          : AppLanguage.english,
    );
  }

  /// Translate a key
  String t(String key) {
    final dict =
    _language == AppLanguage.tagalog ? _tagalog : _english;
    return dict[key] ?? _english[key] ?? key;
  }

  // ═══════════════════════════════════════════════════════════
  // 📚 ENGLISH DICTIONARY (default / fallback)
  // ═══════════════════════════════════════════════════════════
  static const Map<String, String> _english = {
    // ─── Profile Screen ───
    'profile_title': 'Profile & Settings',
    'personal_details': 'Personal Details',
    'email_address': 'Email Address',
    'phone_number': 'Phone Number',
    'department': 'Department',
    'position': 'Position',
    'app_settings': 'App Settings',
    'dark_mode': 'Dark Mode',
    'dark_mode_subtitle': 'Toggle dark theme',
    'push_notifications': 'Push Notifications',
    'push_on': 'Receiving updates and alerts',
    'push_off': 'All notifications are turned off',
    'push_loading': 'Loading...',
    'language': 'Language',
    'security': 'Security',
    'change_password': 'Change Password',
    'privacy_policy': 'Privacy Policy',
    'sign_out': 'Sign Out',
    'unknown': 'Unknown',

    // ─── Language selection ───
    'select_language': 'Select Language',
    'english': 'English',
    'tagalog': 'Tagalog',
    'language_updated': 'Language updated',
    'language_english_msg': 'App language set to English',
    'language_tagalog_msg': 'Nakaset na ang wika sa Tagalog',

    // ─── Snackbar messages ───
    'notif_on_msg': '✅ Notifications ON — you will now receive updates.',
    'notif_off_msg': '🔕 Notifications OFF — you will no longer receive updates.',
    'feature_coming_soon': 'feature coming soon!',

    // ─── Clock Screen ───
    'clock_in': 'Clock In',
    'clock_out': 'Clock Out',
    'clocked_in_at': 'Clocked IN at',
    'clocked_out_at': 'Clocked OUT at',
    'you_are_currently': 'You are currently',
    'in_range': 'In Range.',
    'out_of_range': 'Out of Range.',
    'wfh_mode': 'WFH Mode.',
    'checking': 'Checking...',
    'in_range_subtitle': 'Our system verified your location. You are ready to go.',
    'out_of_range_subtitle': 'You are outside the authorized zone. Clock in/out is disabled.',
    'wfh_subtitle': 'Work-from-home access is active. You can clock in/out anywhere.',
    'checking_subtitle': 'Verifying your location. Please wait.',
    'saving': 'Saving...',
    'locked': 'Locked',
    'done': 'Done',
    'shortcuts': 'Short Cuts',
    'home': 'Home',
    'profile': 'Profile',
    'leaves': 'Leaves',
    'logs': 'Logs',
    'itinerary': 'Itinerary',

    // ─── Facial Recognition ───
    'facial_recognition': 'Facial Recognition',
    'auth_clock_in': 'Auth & Clock In',
    'face_liveness': 'Face + Liveness verification',
    'cancel_auth': 'Cancel Authentication',
    'scanning_face': 'Scanning Face...',
    'liveness_check': 'Liveness Check',
    'verifying_identity': 'Verifying Identity...',
    'try_again': 'Try Again',
    'face_registered': 'Face Registered!',
    'auto_capture_face': 'Auto-Capture Face',
    'captured': 'Captured!',
    'saving_template': 'Saving Template...',
    'checking_face_data': 'Checking Face Data...',
    'verifying_location': 'Verifying Location...',

    // ─── Success Screen ───
    'verified_clocked_in': 'Verified &\nClocked In!',
    'clocked_out': 'Clocked Out!',
    'starting_shift': 'Starting your shift and redirecting...',
    'ending_shift': 'Ending your shift and redirecting...',

    // ─── Notifications ───
    'notifications': 'Notifications',
    'no_notifications': 'No notifications yet',
    'mark_all_read': 'Mark all as read',

    // ─── Records ───
    'records': 'Records',
    'attendance_history': 'Attendance History',
    'reports': 'Reports',
    'sync_status': 'Sync Status',

    // ─── Login ───
    'login': 'Login',
    'email': 'Email',
    'password': 'Password',
    'forgot_password': 'Forgot Password?',
    'welcome_back': 'Welcome Back',
  };

  // ═══════════════════════════════════════════════════════════
  // 📚 TAGALOG DICTIONARY
  // ═══════════════════════════════════════════════════════════
  static const Map<String, String> _tagalog = {
    // ─── Profile Screen ───
    'profile_title': 'Profile at Settings',
    'personal_details': 'Personal na Impormasyon',
    'email_address': 'Email Address',
    'phone_number': 'Numero ng Telepono',
    'department': 'Departamento',
    'position': 'Posisyon',
    'app_settings': 'Settings ng App',
    'dark_mode': 'Dark Mode',
    'dark_mode_subtitle': 'I-toggle ang dark theme',
    'push_notifications': 'Push Notifications',
    'push_on': 'Tumatanggap ng mga update at alerto',
    'push_off': 'Naka-off ang lahat ng notification',
    'push_loading': 'Naglo-load...',
    'language': 'Wika',
    'security': 'Seguridad',
    'change_password': 'Palitan ang Password',
    'privacy_policy': 'Patakaran sa Privacy',
    'sign_out': 'Mag-sign Out',
    'unknown': 'Hindi Kilala',

    // ─── Language selection ───
    'select_language': 'Pumili ng Wika',
    'english': 'Ingles',
    'tagalog': 'Tagalog',
    'language_updated': 'Na-update ang wika',
    'language_english_msg': 'Nakaset na ang wika sa Ingles',
    'language_tagalog_msg': 'Nakaset na ang wika sa Tagalog',

    // ─── Snackbar messages ───
    'notif_on_msg': '✅ Bukas ang notifications — makakatanggap ka na ng updates.',
    'notif_off_msg': '🔕 Sarado ang notifications — hindi ka na makakatanggap ng updates.',
    'feature_coming_soon': 'paparating na ang feature!',

    // ─── Clock Screen ───
    'clock_in': 'Clock In',
    'clock_out': 'Clock Out',
    'clocked_in_at': 'Nag-clock IN ng',
    'clocked_out_at': 'Nag-clock OUT ng',
    'you_are_currently': 'Kasalukuyan kang',
    'in_range': 'Nasa Loob.',
    'out_of_range': 'Nasa Labas.',
    'wfh_mode': 'WFH Mode.',
    'checking': 'Sinusuri...',
    'in_range_subtitle': 'Na-verify na ng system ang lokasyon mo. Ready ka na.',
    'out_of_range_subtitle': 'Nasa labas ka ng authorized zone. Naka-disable ang clock in/out.',
    'wfh_subtitle': 'Aktibo ang work-from-home access. Pwede kang mag-clock in/out kahit saan.',
    'checking_subtitle': 'Vine-verify ang lokasyon mo. Maghintay lang.',
    'saving': 'Sina-save...',
    'locked': 'Naka-lock',
    'done': 'Tapos',
    'shortcuts': 'Mga Shortcut',
    'home': 'Home',
    'profile': 'Profile',
    'leaves': 'Mga Leave',
    'logs': 'Mga Log',
    'itinerary': 'Itinerary',

    // ─── Facial Recognition ───
    'facial_recognition': 'Facial Recognition',
    'auth_clock_in': 'Auth at Clock In',
    'face_liveness': 'Face + Liveness verification',
    'cancel_auth': 'I-cancel ang Authentication',
    'scanning_face': 'Sina-scan ang Mukha...',
    'liveness_check': 'Liveness Check',
    'verifying_identity': 'Vine-verify ang Identity...',
    'try_again': 'Subukan Ulit',
    'face_registered': 'Naka-register na ang Mukha!',
    'auto_capture_face': 'Auto-Capture ng Mukha',
    'captured': 'Nakuha!',
    'saving_template': 'Sina-save ang Template...',
    'checking_face_data': 'Sinusuri ang Face Data...',
    'verifying_location': 'Vine-verify ang Lokasyon...',

    // ─── Success Screen ───
    'verified_clocked_in': 'Verified at\nNaka-Clock In!',
    'clocked_out': 'Naka-Clock Out!',
    'starting_shift': 'Sinisimulan ang shift mo at ire-redirect...',
    'ending_shift': 'Tinatapos ang shift mo at ire-redirect...',

    // ─── Notifications ───
    'notifications': 'Mga Notification',
    'no_notifications': 'Wala pang notification',
    'mark_all_read': 'Markahan lahat na nabasa',

    // ─── Records ───
    'records': 'Mga Record',
    'attendance_history': 'Kasaysayan ng Attendance',
    'reports': 'Mga Report',
    'sync_status': 'Status ng Sync',

    // ─── Login ───
    'login': 'Mag-login',
    'email': 'Email',
    'password': 'Password',
    'forgot_password': 'Nakalimutan ang Password?',
    'welcome_back': 'Maligayang Pagbabalik',
  };
}