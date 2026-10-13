// lib/services/admin_notification_alert_service.dart
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_notification.dart';
import 'admin_notification_service.dart';

class AdminNotificationAlertService {
  AdminNotificationAlertService._();
  static final instance = AdminNotificationAlertService._();

  final _player = AudioPlayer();
  StreamSubscription<List<AdminNotification>>? _sub;
  final _seenIds = <String>{};
  DateTime? _lastAlertAt;
  static const _cooldown = Duration(seconds: 4);
  static const _prefsKey = 'admin_notif_sound_enabled';

  bool _enabled = true;
  bool get enabled => _enabled;

  bool _initialized = false;
  bool get initialized => _initialized;

  // ═══════════════════════════════════════════════════════════════
  // INIT — call this in main.dart after Firebase.initializeApp()
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? true;
      debugPrint('🔔 [AlertService] Sound enabled from prefs: $_enabled');
    } catch (e) {
      debugPrint('🔔 [AlertService] prefs load error: $e');
    }

    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.lowLatency);
    } catch (e) {
      debugPrint('🔔 [AlertService] player setup error: $e');
    }

    // Seed current IDs so old notifications don't fire on first load
    try {
      final first = await AdminNotificationService.instance
          .streamAll(limit: 50)
          .first
          .timeout(const Duration(seconds: 5));
      for (final n in first) {
        _seenIds.add(n.id);
      }
      debugPrint('🔔 [AlertService] Seeded ${_seenIds.length} existing IDs');
    } catch (e) {
      debugPrint('🔔 [AlertService] seed error (non-fatal): $e');
    }

    // Listen to stream
    _sub = AdminNotificationService.instance
        .streamAll(limit: 20)
        .listen(_onItems, onError: (e) {
      debugPrint('🔔 [AlertService] stream error: $e');
    });

    _initialized = true;
    debugPrint('🔔 [AlertService] READY — enabled=$_enabled');
  }

  // ═══════════════════════════════════════════════════════════════
  // HANDLER
  // ═══════════════════════════════════════════════════════════════
  void _onItems(List<AdminNotification> items) {
    for (final n in items) {
      if (_seenIds.contains(n.id)) continue;
      _seenIds.add(n.id);
      if (n.read) continue;

      // Cooldown — prevents rapid-fire sounds during bulk events
      final now = DateTime.now();
      if (_lastAlertAt != null &&
          now.difference(_lastAlertAt!) < _cooldown) {
        debugPrint('🔔 [AlertService] SKIP (cooldown) ${n.id}');
        continue;
      }
      _lastAlertAt = now;

      _playFor(n);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ URGENT DETECTION — centralized
  // ═══════════════════════════════════════════════════════════════
  bool _isUrgent(AdminNotification n) {
    // 1. Explicit HIGH priority
    if (n.priority == 'high') return true;

    // 2. Geofence breach
    if (n.type == 'geofence_alert') return true;

    // 3. Leave requests — need immediate attention
    if (n.type == 'leave_request') return true;

    // 4. Presence status change (IN ↔ OUT) — NOT heartbeat
    if (n.type == 'presence_update') {
      final changed = n.metadata['changed'];
      if (changed == true) return true;
    }

    // 5. Face enrollment high failure? future
    // 6. Password change request — requires admin approval  (NEW)
    if (n.type == 'password_change') return true;

    return false;
  }

  Future<void> _playFor(AdminNotification n) async {
    if (!_enabled) {
      debugPrint('🔔 [AlertService] MUTED — skip ${n.type}');
      return;
    }

    final urgent = _isUrgent(n);

    debugPrint(
        '🔔 [AlertService] PLAY ${urgent ? "🚨 URGENT" : "🔔 normal"} '
            '| type=${n.type} | priority=${n.priority} | title=${n.title}');

    try {
      if (urgent) {
        await HapticFeedback.heavyImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}

    try {
      if (urgent) {
        await _player.play(AssetSource('sounds/alert_urgent.mp3'));
      } else {
        await _player.play(AssetSource('sounds/notif.mp3'));
      }
    } catch (e) {
      debugPrint('🔔 [AlertService] mp3 play failed: $e — using system sound');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (e2) {
        debugPrint('🔔 [AlertService] system sound failed: $e2');
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('🔔 [AlertService] prefs save error: $e');
    }
    debugPrint('🔔 [AlertService] enabled=$value');
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Manual test — can be called from a debug page
  Future<void> testUrgent() async {
    debugPrint('🔔 [AlertService] manual test — URGENT');
    try {
      await HapticFeedback.heavyImpact();
      await _player.play(AssetSource('sounds/alert_urgent.mp3'));
    } catch (e) {
      debugPrint('🔔 testUrgent error: $e');
    }
  }

  Future<void> testNormal() async {
    debugPrint('🔔 [AlertService] manual test — NORMAL');
    try {
      await HapticFeedback.lightImpact();
      await _player.play(AssetSource('sounds/notif.mp3'));
    } catch (e) {
      debugPrint('🔔 testNormal error: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _player.dispose();
  }
}