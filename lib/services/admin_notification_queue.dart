// lib/services/admin_notification_queue.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_guard.dart';

class AdminNotificationQueue {
  AdminNotificationQueue._();
  static final instance = AdminNotificationQueue._();

  static const _prefsKey = 'admin_notif_queue_v1';
  final _col = FirebaseFirestore.instance.collection('admin_notifications');

  final List<Map<String, dynamic>> _pending = [];
  bool _syncing = false;
  StreamSubscription<bool>? _netSub;

  List<Map<String, dynamic>> get pending => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;

  Future<void> init() async {
    await _loadFromPrefs();
    _netSub = NetworkGuard.instance.onStatusChange.listen((online) {
      if (online) syncPending();
    });
    if (NetworkGuard.instance.isOnline && _pending.isNotEmpty) {
      syncPending();
    }
    debugPrint('📥 [NotifQueue] ready — pending=${_pending.length}');
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List;
      _pending
        ..clear()
        ..addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
      debugPrint('📥 [NotifQueue] Loaded ${_pending.length} from prefs');
    } catch (e) {
      debugPrint('📥 [NotifQueue] Load error: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_pending));
    } catch (e) {
      debugPrint('📥 [NotifQueue] Save error: $e');
    }
  }

  Future<void> enqueue(Map<String, dynamic> payload) async {
    _pending.add({
      ...payload,
      'queued_at': DateTime.now().toIso8601String(),
    });
    await _saveToPrefs();
    debugPrint('📥 [NotifQueue] Enqueued — total=${_pending.length}');
    if (NetworkGuard.instance.isOnline) {
      syncPending();
    }
  }

  Future<void> syncPending() async {
    if (_syncing || _pending.isEmpty) return;
    if (!NetworkGuard.instance.isOnline) return;

    _syncing = true;
    debugPrint('📤 [NotifQueue] Syncing ${_pending.length} pending...');

    final snapshot = List<Map<String, dynamic>>.from(_pending);
    int sent = 0;

    for (final item in snapshot) {
      try {
        final payload = Map<String, dynamic>.from(item)
          ..remove('queued_at');

        await _col
            .add({
          ...payload,
          'timestamp': FieldValue.serverTimestamp(),
          'read': payload['read'] ?? false,
        })
            .timeout(const Duration(seconds: 8));

        _pending.remove(item);
        sent++;
        debugPrint('📤 [NotifQueue] Sent: ${item['type']}');
      } catch (e) {
        debugPrint('📤 [NotifQueue] Send failed (keeping in queue): $e');
        break;
      }
    }

    await _saveToPrefs();
    _syncing = false;
    debugPrint(
        '📤 [NotifQueue] Done — sent=$sent, remaining=${_pending.length}');
  }

  Future<void> clear() async {
    _pending.clear();
    await _saveToPrefs();
  }

  void dispose() {
    _netSub?.cancel();
  }
}