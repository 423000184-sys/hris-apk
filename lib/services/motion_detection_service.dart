// lib/services/motion_detection_service.dart
// ═══════════════════════════════════════════════════════════════════
// MOTION DETECTION SERVICE v1.0
// Detects if the phone has been stationary for too long.
// Purpose: flag possible "iniwan ang phone sa drawer" scenarios.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'admin_notification_service.dart';
import 'employee_notification_service.dart';

class MotionDetectionService {
  MotionDetectionService._();
  static final instance = MotionDetectionService._();

  // ─── Config ───
  static const Duration checkInterval = Duration(minutes: 5);
  static const double stationaryThresholdMeters = 15.0; // <15m = stationary
  static const Duration stationaryDurationThreshold = Duration(minutes: 30);
  static const Duration flagCooldown = Duration(hours: 2);

  // ─── State ───
  Timer? _timer;
  String? _employeeId;
  String? _employeeDocId;
  String? _employeeName;
  bool _enabled = true;
  bool _checking = false;

  Position? _lastPosition;
  DateTime? _stationarySince;
  DateTime? _lastFlagAt;
  DateTime? _lastUpdateAt;
  int _checkCount = 0;
  int _stationaryFlagCount = 0;

  // ─── Getters ───
  bool get isRunning => _timer != null;
  bool get isEnabled => _enabled;
  DateTime? get stationarySince => _stationarySince;
  DateTime? get lastFlagAt => _lastFlagAt;
  int get checkCount => _checkCount;
  int get stationaryFlagCount => _stationaryFlagCount;

  // ═══════════════════════════════════════════════════════════════
  // START / STOP
  // ═══════════════════════════════════════════════════════════════
  void start({
    required String employeeId,
    required String employeeDocId,
    required String employeeName,
  }) {
    if (employeeId.isEmpty) {
      debugPrint('⚠️ [Motion] No employee ID — skip start');
      return;
    }

    if (_timer != null && _employeeId == employeeId) {
      debugPrint('ℹ️ [Motion] Already running for $employeeId');
      return;
    }

    stop();

    _employeeId = employeeId;
    _employeeDocId = employeeDocId;
    _employeeName = employeeName;
    _enabled = true;
    _stationarySince = null;
    _lastFlagAt = null;
    _checkCount = 0;
    _stationaryFlagCount = 0;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🚶 [Motion] STARTED for $employeeName');
    debugPrint('═══════════════════════════════════════════');

    // First check after 2 mins (para hindi agad-agad)
    Future.delayed(const Duration(minutes: 2), () {
      if (_timer != null) _checkMotion();
    });

    _timer = Timer.periodic(checkInterval, (_) => _checkMotion());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _checking = false;
    _lastPosition = null;
    _stationarySince = null;
  }

  void reset() {
    stop();
    _employeeId = null;
    _employeeDocId = null;
    _employeeName = null;
    _lastFlagAt = null;
    _checkCount = 0;
    _stationaryFlagCount = 0;
    debugPrint('🚶 [Motion] RESET');
  }

  // ═══════════════════════════════════════════════════════════════
  // CORE CHECK
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkMotion() async {
    if (!_enabled) return;
    if (_checking) return;
    if (_employeeId == null) return;

    _checking = true;
    _checkCount++;

    try {
      // Check kung naka-enable sa settings
      final settingsEnabled = await _isSettingEnabled('motionDetection');
      if (!settingsEnabled) {
        debugPrint('🔕 [Motion] OFF in settings — skip');
        return;
      }

      // Kunin ang current position
      final pos = await _getCurrentPosition();
      if (pos == null) {
        debugPrint('⚠️ [Motion] Position null — skip');
        return;
      }

      final now = DateTime.now();

      // Unang check — i-record lang
      if (_lastPosition == null) {
        _lastPosition = pos;
        _lastUpdateAt = now;
        debugPrint('📍 [Motion] Initial position recorded');
        await _saveMotionState(
          pos: pos,
          stationary: false,
          stationarySince: null,
        );
        return;
      }

      // Compute distance mula last position
      final distanceMoved = _distanceMeters(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        pos.latitude,
        pos.longitude,
      );

      debugPrint('🚶 [Motion] Check #$_checkCount — '
          'moved ${distanceMoved.toStringAsFixed(1)}m');

      final isStationary = distanceMoved < stationaryThresholdMeters;

      if (isStationary) {
        // Naka-stationary — i-check kung gaano na katagal
        _stationarySince ??= now;
        final stationaryDur = now.difference(_stationarySince!);

        debugPrint('🟡 [Motion] Stationary for ${stationaryDur.inMinutes}min '
            '(threshold=${stationaryDurationThreshold.inMinutes}min)');

        if (stationaryDur >= stationaryDurationThreshold) {
          await _handleStationaryFlag(
            stationaryDur: stationaryDur,
            distance: distanceMoved,
            pos: pos,
          );
        }

        await _saveMotionState(
          pos: pos,
          stationary: true,
          stationarySince: _stationarySince,
        );
      } else {
        // Gumalaw — reset
        if (_stationarySince != null) {
          final dur = now.difference(_stationarySince!);
          debugPrint('✅ [Motion] Moved after ${dur.inMinutes}min — reset');
        }
        _stationarySince = null;

        await _saveMotionState(
          pos: pos,
          stationary: false,
          stationarySince: null,
        );
      }

      _lastPosition = pos;
      _lastUpdateAt = now;
    } catch (e) {
      debugPrint('❌ [Motion] Check failed: $e');
    } finally {
      _checking = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FLAG HANDLER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleStationaryFlag({
    required Duration stationaryDur,
    required double distance,
    required Position pos,
  }) async {
    final now = DateTime.now();

    // Cooldown check — huwag mag-spam
    if (_lastFlagAt != null &&
        now.difference(_lastFlagAt!) < flagCooldown) {
      debugPrint('⏱️ [Motion] Flag cooldown active — skip');
      return;
    }

    _lastFlagAt = now;
    _stationaryFlagCount++;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🚨 [Motion] STATIONARY FLAG');
    debugPrint('   emp      : $_employeeName ($_employeeId)');
    debugPrint('   duration : ${stationaryDur.inMinutes}min');
    debugPrint('   flag #   : $_stationaryFlagCount');
    debugPrint('═══════════════════════════════════════════');

    try {
      // 1. Save sa Firestore — motion_flags subcollection
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(_employeeDocId ?? _employeeId)
          .collection('motion_flags')
          .add({
        'employeeId': _employeeId,
        'employee_name': _employeeName,
        'stationaryMinutes': stationaryDur.inMinutes,
        'distanceMoved': distance,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'flagCount': _stationaryFlagCount,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Update employee doc — summary
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(_employeeDocId ?? _employeeId)
          .set({
        'motionFlag': true,
        'motionFlagAt': FieldValue.serverTimestamp(),
        'motionStationaryMinutes': stationaryDur.inMinutes,
        'motionFlagCount': _stationaryFlagCount,
      }, SetOptions(merge: true));

      // 3. Notify employee — ask to move phone or confirm
      await _notifyEmployee(stationaryDur);

      // 4. Notify admin
      await _notifyAdmin(stationaryDur, pos);

      // 5. Log sa activity_logs
      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'motion_flag',
          'action': 'Stationary Detected',
          'employeeId': _employeeDocId ?? _employeeId,
          'employee_id': _employeeId,
          'employee_name': _employeeName,
          'stationaryMinutes': stationaryDur.inMinutes,
          'flagCount': _stationaryFlagCount,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ [Motion] Flag handling failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _notifyEmployee(Duration stationaryDur) async {
    if (_employeeId == null) return;

    try {
      await EmployeeNotificationService.instance.send(
        type: 'motion_flag',
        title: '📍 Nag-request ng confirmation',
        message:
        'Hindi gumalaw ang phone mo for ${stationaryDur.inMinutes} minutes. '
            'Please move it or tap to confirm na nandiyan ka pa.',
        employeeId: _employeeId!,
        senderName: 'System',
        priority: 'high',
        metadata: {
          'stationaryMinutes': stationaryDur.inMinutes,
          'alertType': 'motion_flag',
          'triggeredAt': DateTime.now().toIso8601String(),
        },
      );
      debugPrint('✅ [Motion] Employee notified');
    } catch (e) {
      debugPrint('❌ [Motion] Employee notify failed: $e');
    }
  }

  Future<void> _notifyAdmin(Duration stationaryDur, Position pos) async {
    if (_employeeId == null || _employeeName == null) return;

    try {
      await AdminNotificationService.instance.notify(
        type: 'motion_flag',
        title: '🚨 Motion Flag — $_employeeName',
        message:
        'Phone stationary for ${stationaryDur.inMinutes} mins. '
            'Possible iniwan ang phone.',
        employeeId: _employeeId,
        employeeName: _employeeName,
        priority: 'high',
        metadata: {
          'stationaryMinutes': stationaryDur.inMinutes,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'flagCount': _stationaryFlagCount,
        },
      );
      debugPrint('✅ [Motion] Admin notified');
    } catch (e) {
      debugPrint('❌ [Motion] Admin notify failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  Future<Position?> _getCurrentPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ [Motion] getCurrentPosition failed: $e');
      return null;
    }
  }

  /// Haversine distance in meters
  double _distanceMeters(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  Future<bool> _isSettingEnabled(String key) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data == null) return false;
      return data[key] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveMotionState({
    required Position pos,
    required bool stationary,
    DateTime? stationarySince,
  }) async {
    if (_employeeId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('employee_presence')
          .doc(_employeeId)
          .set({
        'motionStationary': stationary,
        if (stationarySince != null)
          'motionStationarySince': Timestamp.fromDate(stationarySince),
        if (!stationary) 'motionStationarySince': null,
        'motionLastLat': pos.latitude,
        'motionLastLng': pos.longitude,
        'motionLastAccuracy': pos.accuracy,
        'motionLastUpdate': FieldValue.serverTimestamp(),
        'motionCheckCount': _checkCount,
        'motionFlagCount': _stationaryFlagCount,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ [Motion] Save state failed: $e');
    }
  }

  /// Clear motion flag manually (para admin action)
  Future<void> clearFlag({String? reason}) async {
    if (_employeeDocId == null && _employeeId == null) return;

    final docId = _employeeDocId ?? _employeeId!;
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .set({
        'motionFlag': false,
        'motionFlagClearedAt': FieldValue.serverTimestamp(),
        'motionFlagClearedReason': reason ?? 'manual_clear',
      }, SetOptions(merge: true));

      _lastFlagAt = null;
      _stationarySince = null;
      _stationaryFlagCount = 0;

      debugPrint('🧹 [Motion] Flag cleared');
    } catch (e) {
      debugPrint('⚠️ [Motion] Clear flag failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBUG
  // ═══════════════════════════════════════════════════════════════
  Map<String, dynamic> debugInfo() => {
    'isRunning': isRunning,
    'isEnabled': _enabled,
    'employeeId': _employeeId,
    'checkCount': _checkCount,
    'stationaryFlagCount': _stationaryFlagCount,
    'stationarySince': _stationarySince?.toIso8601String(),
    'lastFlagAt': _lastFlagAt?.toIso8601String(),
    'lastUpdateAt': _lastUpdateAt?.toIso8601String(),
  };

  void dispose() {
    reset();
  }
}