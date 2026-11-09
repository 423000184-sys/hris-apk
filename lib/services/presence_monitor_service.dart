// lib/services/presence_monitor_service.dart
// ═══════════════════════════════════════════════════════════════════
// PRESENCE MONITOR SERVICE v2.2
// v2.0 FIXES:
//   • MotionDetectionService started/stopped together
//   • _lastHeartbeatAt for accurate no-heartbeat trigger
//   • Per-day idempotency guard
//   • All Tagalog strings translated
// v2.1 OVERTIME (per-employee manual flag)
// v2.2 AUTO OVERTIME (zero per-employee setup):
//   • Reads global settings/geofence_config.overtimeAutoDetect
//   • If employee is INSIDE office zone past 5 PM → treat as OT
//   • Auto clock-out triggers only when employee leaves zone
//   • Hard-cap safety: force clock-out at overtimeHardCapTime
//   • No per-employee Firestore fields needed
// v2.3 PRESENCE CHALLENGE:
//   • Hooks PresenceChallengeService.start/stop alongside lifetime
//   • NOTE: no_heartbeat trigger intentionally left untouched
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/employee.dart';
import 'admin_notification_service.dart';
import 'geofence_service.dart';
import 'network_guard.dart';
import 'presence_backup_service.dart';
import 'employee_notification_service.dart';
import 'clock_status_service.dart';
import 'motion_detection_service.dart';
import 'presence_challenge_service.dart'; // 🆕 v2.3

/// 🛰️ Presence Monitor — 3-Layer + Real-Time Settings + AUTO CLOCK-OUT + AUTO OT
class PresenceMonitorService {
  PresenceMonitorService._();
  static final instance = PresenceMonitorService._();

  Timer? _liveTimer;
  Timer? _backupTimer;

  String? _employeeId;
  String? _employeeName;
  String? _employeeEmail;
  String? _employeeDocId;
  String? _lastZone;
  DateTime? _lastNotifiedAt;
  DateTime? _lastBackupAt;
  bool _checking = false;
  bool _backingUp = false;
  bool _enabled = true;
  int _checkCount = 0;
  int _backupCount = 0;

  // 🆕 AUTO-BACKUP ON NOTIFICATION
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifListenerSub;
  final Set<String> _processedNotifIds = {};
  DateTime? _lastAutoBackupAt;
  static const Duration _autoBackupCooldown = Duration(seconds: 30);

  // 🆕 REAL-TIME SETTINGS LISTENER
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  bool _firstSettingsSnapshot = true;
  bool _lastEntryReminders = false;
  bool _lastViolation = false;
  bool _lastAutoOut = false;
  bool _lastOvertimeAutoDetect = false;
  bool _forceTriggerNextCheck = false;

  // 🆕 EMPLOYEE ENTRY REMINDER STATE
  DateTime? _lastEmployeeAlertAt;
  static const Duration _employeeAlertCooldown = Duration(minutes: 10);

  // 🆕 GEOFENCE VIOLATION STATE
  DateTime? _outsideSince;
  DateTime? _lastViolationNotifAt;
  static const Duration _violationThreshold = Duration(minutes: 15);
  static const Duration _violationCooldown = Duration(minutes: 30);

  // ═══════════════════════════════════════════════════════════════
  // 🔥 AUTO CLOCK-OUT STATE
  // ═══════════════════════════════════════════════════════════════
  String? _lastAutoClockOutNotifDate;
  String? _lastAutoClockOutPerformedDate;
  String? _lastAutoClockOutTrigger;
  DateTime? _autoClockOutAt;
  DateTime? _lastHeartbeatAt;

  // ═══════════════════════════════════════════════════════════════
  // 🆕 AUTO OVERTIME STATE (GLOBAL)
  // ═══════════════════════════════════════════════════════════════
  bool _overtimeAutoDetectEnabled = false;   // from settings
  String _overtimeHardCapTime = '23:00';     // from settings
  bool _overtimeActive = false;              // computed per-check
  DateTime? _overtimeStartedAt;

  // Trigger thresholds
  static const int _shiftEndHour = 17;
  static const int _shiftEndMinute = 0;
  static const Duration _noHeartbeatThreshold = Duration(minutes: 30);
  static const Duration _shiftEndGracePeriod = Duration(minutes: 15);

  // ⚙️ Config
  static const Duration checkInterval = Duration(minutes: 5);
  static const Duration backupInterval = Duration(minutes: 60);
  static const Duration heartbeatInterval = Duration(minutes: 30);

  // ─── Getters ───────────────────────────────────────────────────
  bool get isRunning => _liveTimer != null;
  bool get isEnabled => _enabled;
  bool get isOvertimeActive => _overtimeActive;
  bool get isOvertimeAutoDetectEnabled => _overtimeAutoDetectEnabled;
  String get overtimeHardCapTime => _overtimeHardCapTime;
  DateTime? get overtimeStartedAt => _overtimeStartedAt;
  String? get currentZone => _lastZone;
  String? get employeeId => _employeeId;
  String? get employeeName => _employeeName;
  DateTime? get lastNotifiedAt => _lastNotifiedAt;
  DateTime? get lastBackupAt => _lastBackupAt;
  DateTime? get lastEmployeeAlertAt => _lastEmployeeAlertAt;
  DateTime? get lastViolationNotifAt => _lastViolationNotifAt;
  DateTime? get outsideSince => _outsideSince;
  DateTime? get autoClockOutAt => _autoClockOutAt;
  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;
  String? get lastAutoClockOutTrigger => _lastAutoClockOutTrigger;
  int get checkCount => _checkCount;
  int get backupCount => _backupCount;

  // ═══════════════════════════════════════════════════════════════
  // START / STOP
  // ═══════════════════════════════════════════════════════════════
  void start({required Employee employee}) {
    final id = employee.employeeId.isNotEmpty
        ? employee.employeeId
        : employee.id;
    final docId = employee.id.isNotEmpty ? employee.id : id;

    if (id.isEmpty) {
      debugPrint('⚠️ [PresenceMonitor] No employee ID — skip start');
      return;
    }

    if (_liveTimer != null && _employeeId == id) {
      debugPrint('ℹ️ [PresenceMonitor] Already running for $id');
      return;
    }

    if (_employeeId != null && _employeeId != id) {
      debugPrint('🔄 [PresenceMonitor] Employee changed — resetting');
      _resetState();
    }

    stop();

    _employeeId = id;
    _employeeName = employee.fullName;
    _employeeEmail = employee.email;
    _employeeDocId = docId;
    _enabled = true;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🛰️ [PresenceMonitor] STARTED');
    debugPrint('   employee : $id ($_employeeName)');
    debugPrint('   docId    : $docId');
    debugPrint('═══════════════════════════════════════════');

    checkNow();
    Future.delayed(const Duration(seconds: 30), () => _backupNow());

    _liveTimer = Timer.periodic(checkInterval, (_) => checkNow());
    _backupTimer = Timer.periodic(backupInterval, (_) => _backupNow());
    _startNotificationListener();
    _startSettingsListener();

    // 🆕 v2.3 — start presence challenge scheduler
    PresenceChallengeService.instance.start(
      id,
      employeeName: employee.fullName,
    );
    debugPrint('🎯 [PresenceMonitor] PresenceChallengeService started for $id');

    try {
      MotionDetectionService.instance.start(
        employeeId: id,
        employeeDocId: docId,
        employeeName: employee.fullName,
      );
      debugPrint('🚶 [PresenceMonitor] MotionDetectionService started');
    } catch (e) {
      debugPrint('⚠️ [PresenceMonitor] MotionDetection start failed: $e');
    }
  }

  void stop() {
    final wasRunning = _liveTimer != null || _backupTimer != null;
    _liveTimer?.cancel();
    _backupTimer?.cancel();
    _notifListenerSub?.cancel();
    _settingsSub?.cancel();
    _liveTimer = null;
    _backupTimer = null;
    _notifListenerSub = null;
    _settingsSub = null;

    try {
      MotionDetectionService.instance.stop();
    } catch (e) {
      debugPrint('⚠️ [PresenceMonitor] MotionDetection stop failed: $e');
    }

    // 🆕 v2.3 — stop presence challenge scheduler
    try {
      PresenceChallengeService.instance.stop();
    } catch (e) {
      debugPrint('⚠️ [PresenceMonitor] PresenceChallenge stop failed: $e');
    }

    if (wasRunning) debugPrint('🛰️ [PresenceMonitor] STOPPED');
  }

  void reset() {
    stop();
    _resetState();
    debugPrint('🛰️ [PresenceMonitor] RESET');
  }

  void _resetState() {
    _employeeId = null;
    _employeeName = null;
    _employeeEmail = null;
    _employeeDocId = null;
    _lastZone = null;
    _lastNotifiedAt = null;
    _lastBackupAt = null;
    _lastAutoBackupAt = null;
    _lastEmployeeAlertAt = null;
    _lastViolationNotifAt = null;
    _outsideSince = null;
    _lastAutoClockOutNotifDate = null;
    _lastAutoClockOutPerformedDate = null;
    _lastAutoClockOutTrigger = null;
    _autoClockOutAt = null;
    _lastHeartbeatAt = null;
    // Auto OT state
    _overtimeAutoDetectEnabled = false;
    _overtimeHardCapTime = '23:00';
    _overtimeActive = false;
    _overtimeStartedAt = null;
    // Settings state
    _firstSettingsSnapshot = true;
    _lastEntryReminders = false;
    _lastViolation = false;
    _lastAutoOut = false;
    _lastOvertimeAutoDetect = false;
    _forceTriggerNextCheck = false;
    _checking = false;
    _backingUp = false;
    _checkCount = 0;
    _backupCount = 0;
    _processedNotifIds.clear();
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;

    if (!value) {
      stop();
      debugPrint('🛰️ [PresenceMonitor] Disabled');
    } else if (_employeeId != null) {
      debugPrint('🛰️ [PresenceMonitor] Re-enabled');
      _liveTimer = Timer.periodic(checkInterval, (_) => checkNow());
      _backupTimer = Timer.periodic(backupInterval, (_) => _backupNow());
      _startNotificationListener();
      _startSettingsListener();
      // 🆕 v2.3 — re-hook challenge service on re-enable
      PresenceChallengeService.instance.start(
        _employeeId!,
        employeeName: _employeeName,
      );
      checkNow();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🆕 AUTO OVERTIME — GLOBAL DETECTION
  // ═══════════════════════════════════════════════════════════════

  /// Compute whether OT is active based on:
  ///   • overtimeAutoDetect master switch
  ///   • Current time past 5:00 PM
  ///   • Employee is INSIDE the office zone
  ///   • Not past hard cap time
  bool _computeAutoOvertime({
    required String zone,
    required DateTime now,
  }) {
    if (!_overtimeAutoDetectEnabled) {
      // Master switch OFF → no auto OT
      if (_overtimeActive) {
        debugPrint('🔕 [OT-Auto] Master switch OFF — disabling');
      }
      _overtimeActive = false;
      _overtimeStartedAt = null;
      return false;
    }

    // Check time — OT only counts after 5:00 PM
    final shiftEnd = DateTime(
      now.year,
      now.month,
      now.day,
      _shiftEndHour,
      _shiftEndMinute,
    );
    if (now.isBefore(shiftEnd)) {
      // Hindi pa 5 PM → normal work hours
      _overtimeActive = false;
      _overtimeStartedAt = null;
      return false;
    }

    // Check hard cap — force exit kahit nag-OT pa
    final capParts = _overtimeHardCapTime.split(':');
    if (capParts.length == 2) {
      try {
        final capHour = int.parse(capParts[0]);
        final capMin = int.parse(capParts[1]);
        final capTime = DateTime(now.year, now.month, now.day, capHour, capMin);
        if (now.isAfter(capTime)) {
          debugPrint('⏰ [OT-Auto] Past hard cap ($_overtimeHardCapTime) — '
              'force auto clock-out allowed');
          _overtimeActive = false;
          return false;
        }
      } catch (_) {}
    }

    // Check zone — dapat INSIDE office
    if (zone != 'inside') {
      if (_overtimeActive) {
        debugPrint('🚪 [OT-Auto] Left office zone — OT ended');
      }
      _overtimeActive = false;
      _overtimeStartedAt = null;
      return false;
    }

    // ✅ ALL CHECKS PASSED — OT ACTIVE
    if (!_overtimeActive) {
      _overtimeStartedAt = now;
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔥 [OT-Auto] OVERTIME DETECTED');
      debugPrint('   employee : $_employeeName');
      debugPrint('   since    : ${now.hour}:${now.minute.toString().padLeft(2, '0')}');
      debugPrint('   hard cap : $_overtimeHardCapTime');
      debugPrint('   → Auto clock-out SUSPENDED while inside zone');
      debugPrint('═══════════════════════════════════════════');
    }
    _overtimeActive = true;
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // REAL-TIME SETTINGS LISTENER
  // ═══════════════════════════════════════════════════════════════
  void _startSettingsListener() {
    _settingsSub?.cancel();
    _firstSettingsSnapshot = true;

    _settingsSub = FirebaseFirestore.instance
        .collection('settings')
        .doc('geofence_config')
        .snapshots()
        .listen(
      _onSettingsChange,
      onError: (e) => debugPrint('⚠️ [Settings] Listener error: $e'),
    );

    debugPrint('📡 [Settings] Real-time listener started');
  }

  void _onSettingsChange(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!_enabled || _employeeId == null) return;

    final data = snap.data();

    if (_firstSettingsSnapshot) {
      _firstSettingsSnapshot = false;
      if (data != null) {
        _lastEntryReminders = data['entryReminders'] == true;
        _lastViolation = data['geofenceViolation'] == true;
        _lastAutoOut = data['autoClockOut'] == true;
        _lastOvertimeAutoDetect = data['overtimeAutoDetect'] == true;
        _overtimeAutoDetectEnabled = _lastOvertimeAutoDetect;
        _overtimeHardCapTime =
            data['overtimeHardCapTime']?.toString() ?? '23:00';
      }
      debugPrint('📡 [Settings] Seeded — '
          'entry: $_lastEntryReminders, '
          'violation: $_lastViolation, '
          'autoOut: $_lastAutoOut, '
          'otAuto: $_lastOvertimeAutoDetect '
          '(cap: $_overtimeHardCapTime)');
      return;
    }

    if (data == null) return;

    final entryOn = data['entryReminders'] == true;
    final violationOn = data['geofenceViolation'] == true;
    final autoOutOn = data['autoClockOut'] == true;
    final otAutoOn = data['overtimeAutoDetect'] == true;
    final capTime = data['overtimeHardCapTime']?.toString() ?? '23:00';

    final entryJustOn = entryOn && !_lastEntryReminders;
    final violationJustOn = violationOn && !_lastViolation;
    final autoOutJustOn = autoOutOn && !_lastAutoOut;
    final otAutoJustOn = otAutoOn && !_lastOvertimeAutoDetect;
    final otAutoJustOff = !otAutoOn && _lastOvertimeAutoDetect;

    final anyJustOn = entryJustOn ||
        violationJustOn ||
        autoOutJustOn ||
        otAutoJustOn;
    final anyJustOff = (!entryOn && _lastEntryReminders) ||
        (!violationOn && _lastViolation) ||
        (!autoOutOn && _lastAutoOut) ||
        otAutoJustOff;

    _lastEntryReminders = entryOn;
    _lastViolation = violationOn;
    _lastAutoOut = autoOutOn;
    _lastOvertimeAutoDetect = otAutoOn;
    _overtimeAutoDetectEnabled = otAutoOn;
    _overtimeHardCapTime = capTime;

    if (anyJustOn) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📡 [Settings] Toggle(s) turned ON → forcing check');
      debugPrint('   entry    : $entryOn');
      debugPrint('   violation: $violationOn');
      debugPrint('   autoOut  : $autoOutOn');
      debugPrint('   otAuto   : $otAutoOn (cap: $capTime)');
      debugPrint('═══════════════════════════════════════════');

      if (entryJustOn) _lastEmployeeAlertAt = null;
      if (violationJustOn) {
        _lastViolationNotifAt = null;
        _outsideSince = null;
      }
      if (autoOutJustOn) {
        _lastAutoClockOutNotifDate = null;
        _lastAutoClockOutPerformedDate = null;
      }
      if (otAutoJustOn) {
        // Reset OT state — let it recompute on next check
        _overtimeActive = false;
        _overtimeStartedAt = null;
      }

      _forceTriggerNextCheck = true;
      checkNow();
    } else if (anyJustOff) {
      debugPrint('📡 [Settings] Toggle(s) turned OFF — future checks skip');
      if (otAutoJustOff) {
        debugPrint('🔕 [OT-Auto] Auto-OT DISABLED — resuming normal triggers');
        _overtimeActive = false;
        _overtimeStartedAt = null;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO-BACKUP — Listen for new notifications
  // ═══════════════════════════════════════════════════════════════
  void _startNotificationListener() {
    _notifListenerSub?.cancel();
    _notifListenerSub = FirebaseFirestore.instance
        .collection('admin_notifications')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen(
      _onNotificationSnapshot,
      onError: (e) => debugPrint('⚠️ [AutoBackup] Listener error: $e'),
    );
    _seedNotificationIds();
  }

  Future<void> _seedNotificationIds() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();
      for (final doc in snap.docs) {
        _processedNotifIds.add(doc.id);
      }
    } catch (e) {
      debugPrint('⚠️ [AutoBackup] Seed error: $e');
    }
  }

  void _onNotificationSnapshot(
      QuerySnapshot<Map<String, dynamic>> snap) {
    if (!_enabled || _employeeId == null) return;

    for (final doc in snap.docs) {
      if (_processedNotifIds.contains(doc.id)) continue;
      _processedNotifIds.add(doc.id);

      final data = doc.data();
      final empId = data['employeeId']?.toString();
      if (empId != _employeeId) continue;

      final ts = data['timestamp'];
      if (ts is Timestamp) {
        final age = DateTime.now().difference(ts.toDate()).inSeconds;
        if (age > 180) continue;
      }

      if (!_shouldTriggerBackup(data)) continue;

      final now = DateTime.now();
      if (_lastAutoBackupAt != null &&
          now.difference(_lastAutoBackupAt!) < _autoBackupCooldown) {
        continue;
      }

      _lastAutoBackupAt = now;
      final type = data['type']?.toString() ?? 'unknown';
      _backupNow(reason: 'notify_$type');
      break;
    }
  }

  bool _shouldTriggerBackup(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final metadata = data['metadata'];
    final changed = metadata is Map && metadata['changed'] == true;

    switch (type) {
      case 'geofence_alert':
      case 'geofence_violation':
      case 'clock_in':
      case 'clock_out':
      case 'auto_clock_out':
      case 'wfh_toggle':
      case 'face_enrollment':
      case 'leave_request':
        return true;
      case 'presence_update':
        return changed;
      default:
        return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYER 1 — LIVE CHECK (every 5 min + on-demand)
  // ═══════════════════════════════════════════════════════════════
  Future<void> checkNow({bool forceNotify = false}) async {
    if (!_enabled) return;
    if (_checking) return;
    if (_employeeId == null || _employeeName == null) return;

    _checking = true;
    _checkCount++;

    final forceFromSettings = _forceTriggerNextCheck;
    _forceTriggerNextCheck = false;

    try {
      debugPrint('🛰️ [Live] Check #$_checkCount '
          '${forceFromSettings ? "(FORCED)" : ""} starting...');

      final geo = await GeofenceService.instance
          .checkGeofence()
          .timeout(const Duration(seconds: 15));

      final zone = geo.isInside ? 'inside' : 'outside';
      final distance = geo.distanceMeters ?? 0;
      final accuracy = geo.accuracyMeters;
      final now = DateTime.now();

      final isFirstCheck = _lastZone == null;
      final changed = !isFirstCheck && _lastZone != zone;
      final previousZone = _lastZone;
      final timeSinceLastNotify = _lastNotifiedAt == null
          ? null
          : now.difference(_lastNotifiedAt!);
      final heartbeatDue = timeSinceLastNotify == null ||
          timeSinceLastNotify >= heartbeatInterval;

      debugPrint('🛰️ [Live] zone=$zone, dist=${distance.toStringAsFixed(0)}m, '
          'changed=$changed, forced=$forceFromSettings');

      await _updateLivePresence(
        zone: zone,
        distance: distance,
        accuracy: accuracy,
      );

      _lastHeartbeatAt = now;

      // ═══════════════════════════════════════════════════════════
      // 🆕 AUTO OVERTIME DETECTION
      // ═══════════════════════════════════════════════════════════
      final otActive = _computeAutoOvertime(zone: zone, now: now);

      // ═══ NOTIFICATIONS ═══
      final shouldNotify = forceNotify ||
          isFirstCheck ||
          changed ||
          heartbeatDue;

      if (shouldNotify) {
        final priority = changed ? 'high' : 'normal';
        String reason;
        if (forceNotify) {
          reason = 'forced';
        } else if (changed) {
          reason = 'status_change';
        } else if (isFirstCheck) {
          reason = 'initial';
        } else {
          reason = 'heartbeat';
        }

        await AdminNotificationService.instance.notifyPresenceUpdate(
          employeeId: _employeeId!,
          employeeName: _employeeName!,
          zone: zone,
          distanceMeters: distance,
          changed: changed,
          previousZone: previousZone,
          priority: priority,
          notifyReason: reason,
        );

        _lastNotifiedAt = now;
      }

      // ═══ 1. ENTRY REMINDERS ═══
      final shouldTriggerEntry = !otActive &&
          (forceFromSettings ||
              (zone == 'outside' && (isFirstCheck || changed)));

      if (shouldTriggerEntry) {
        await _notifyEmployeeOutOfRange(
          distance,
          forced: forceFromSettings,
        );
      } else if (otActive) {
        debugPrint('📍 [Entry] Skipped — auto-OT active');
      }

      // ═══ 2. GEOFENCE VIOLATION ═══
      if (!otActive) {
        if (zone == 'outside') {
          _outsideSince ??= now;
          final outsideDuration = now.difference(_outsideSince!);
          if (forceFromSettings ||
              outsideDuration >= _violationThreshold) {
            await _notifyGeofenceViolation(
              distance,
              outsideDuration,
              forced: forceFromSettings,
            );
          }
        } else {
          if (forceFromSettings) {
            await _notifyGeofenceViolation(
              distance,
              Duration.zero,
              forced: true,
            );
          }
          if (_outsideSince != null) {
            _outsideSince = null;
          }
        }
      } else {
        debugPrint('🚨 [Violation] Skipped — auto-OT active');
      }

      // ═════════════════════════════════════════════════════════
      // 🔥 3. AUTO CLOCK-OUT TRIGGERS
      // ═════════════════════════════════════════════════════════
      debugPrint('⏰ [AutoClockOut] Checking triggers '
          '${otActive ? "(OT ACTIVE)" : ""}...');

      // Trigger 1: Geofence exit — SKIP IF AUTO-OT ACTIVE
      if (!otActive &&
          changed &&
          previousZone == 'inside' &&
          zone == 'outside') {
        debugPrint('⏰ [AutoClockOut] TRIGGER: geofence_exit');
        await _performAutoClockOut(
          trigger: 'geofence_exit',
          locationData: {
            'distanceMeters': distance,
            'accuracyMeters': accuracy,
          },
        );
      } else if (otActive &&
          changed &&
          previousZone == 'inside' &&
          zone == 'outside') {
        debugPrint('⏭️ [AutoClockOut] geofence_exit SKIPPED — auto-OT');
      }

      // Trigger 2: Shift end (5:00 PM + still clocked in)
      // SKIP IF AUTO-OT ACTIVE
      final shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        _shiftEndHour,
        _shiftEndMinute,
      );
      final afterShiftEnd = now.isAfter(shiftEnd);
      final withinGrace = now.isBefore(shiftEnd.add(_shiftEndGracePeriod));

      if (afterShiftEnd && withinGrace && !otActive) {
        debugPrint('⏰ [AutoClockOut] TRIGGER: shift_end');
        await _performAutoClockOut(
          trigger: 'shift_end',
          locationData: {
            'distanceMeters': distance,
            'accuracyMeters': accuracy,
          },
        );
      } else if (afterShiftEnd && withinGrace && otActive) {
        debugPrint('⏭️ [AutoClockOut] shift_end SKIPPED — auto-OT active');
      }

      // Trigger 3: HARD CAP — force clock-out kahit nag-OT
      // Safety net para sa nakalimutang mag-clock-out
      if (otActive == false && afterShiftEnd) {
        // Ito ay para sa hard cap — naka-on kahit OT pa
        final capParts = _overtimeHardCapTime.split(':');
        if (capParts.length == 2) {
          try {
            final capHour = int.parse(capParts[0]);
            final capMin = int.parse(capParts[1]);
            final capTime = DateTime(now.year, now.month, now.day,
                capHour, capMin);
            if (now.isAfter(capTime)) {
              debugPrint('🚨 [AutoClockOut] HARD CAP HIT '
                  '($_overtimeHardCapTime) — forcing clock-out');
              await _performAutoClockOut(
                trigger: 'hard_cap',
                locationData: {
                  'distanceMeters': distance,
                  'accuracyMeters': accuracy,
                  'hardCapTime': _overtimeHardCapTime,
                },
              );
            }
          } catch (_) {}
        }
      }

      // Trigger 4: No heartbeat 30+ min (always active)
      // ⚠️ NOTE: no_heartbeat logic intentionally left untouched.
      if (_lastHeartbeatAt != null) {
        final sinceLastPing = now.difference(_lastHeartbeatAt!);
        if (sinceLastPing >= _noHeartbeatThreshold) {
          debugPrint('⏰ [AutoClockOut] TRIGGER: no_heartbeat '
              '(${sinceLastPing.inMinutes}min)');
          await _performAutoClockOut(
            trigger: 'no_heartbeat',
            locationData: {
              'distanceMeters': distance,
              'accuracyMeters': accuracy,
            },
          );
        }
      }

      // ═══ 4. LEGACY: Auto clock-out REMINDER ═══
      if (!otActive) {
        await _checkAutoClockOutReminder(forced: forceFromSettings);
      }

      _lastZone = zone;
    } catch (e, st) {
      debugPrint('❌ [Live] Check failed: $e');
      debugPrint('$st');
    } finally {
      _checking = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔥 AUTO CLOCK-OUT — CORE METHOD
  // ═══════════════════════════════════════════════════════════════
  Future<void> _performAutoClockOut({
    required String trigger,
    Map<String, dynamic>? locationData,
    bool forced = false,
  }) async {
    if (_employeeId == null || _employeeName == null) return;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Per-day idempotency (not per-trigger)
    if (!forced && _lastAutoClockOutPerformedDate == todayStr) {
      debugPrint('⏭️ [AutoClockOut] Already performed today — skip');
      return;
    }

    // Double-guard: block shift_end & geofence_exit if auto-OT is active
    // EXCEPT for hard_cap and no_heartbeat (safety)
    if (!forced &&
        (trigger == 'shift_end' || trigger == 'geofence_exit') &&
        _overtimeActive) {
      debugPrint('⏭️ [AutoClockOut] $trigger SKIPPED — auto-OT active '
          '(double-guard)');
      return;
    }

    // Check if autoClockOut is enabled in settings
    final enabled = await _isSettingEnabled(
      'autoClockOut',
      defaultValue: false,
    );
    if (!enabled && !forced) {
      debugPrint('🔕 [AutoClockOut] OFF in admin settings — skip');
      return;
    }

    // Check if currently clocked in
    bool isClockedIn = false;
    try {
      isClockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(_employeeId!)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('⚠️ [AutoClockOut] Clock status check failed: $e');
      return;
    }

    if (!isClockedIn) {
      debugPrint('ℹ️ [AutoClockOut] Not clocked in — skip');
      _lastAutoClockOutPerformedDate = todayStr;
      _lastAutoClockOutTrigger = trigger;
      return;
    }

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔥 [AutoClockOut] PERFORMING — trigger=$trigger');
    debugPrint('   emp    : $_employeeName ($_employeeId)');
    debugPrint('   time   : $todayStr ${now.hour}:${now.minute}');
    debugPrint('   OT     : $_overtimeActive');
    debugPrint('═══════════════════════════════════════════');

    try {
      final locPayload = <String, dynamic>{
        if (locationData != null) ...locationData,
        'autoClockOutTrigger': trigger,
        'autoClockOutAt': FieldValue.serverTimestamp(),
        'autoClockOutAtLocal': now.toIso8601String(),
        'overtimeActiveAtTime': _overtimeActive,
        if (_overtimeStartedAt != null)
          'overtimeStartedAt': Timestamp.fromDate(_overtimeStartedAt!),
      };

      final dateStr = todayStr;
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

      await FirebaseFirestore.instance
          .collection('attendance_logs')
          .add({
        'employee_id': _employeeId,
        'employeeId': _employeeId,
        'employee_name': _employeeName,
        'employee_email': _employeeEmail ?? '',
        'type': 'OUT',
        'date': dateStr,
        'time': timeStr,
        'timestamp': FieldValue.serverTimestamp(),
        'verification_method': 'auto',
        'remarks': 'auto_clock_out:$trigger',
        'device': 'system_auto',
        'deviceName': 'Auto Clock-Out',
        'platform': 'system',
        'zone_type': _lastZone == 'inside' ? 'inside' : 'outside',
        'source': 'presence_monitor',
        ...locPayload,
      });

      debugPrint('✅ [AutoClockOut] attendance_logs WRITTEN');

      try {
        await FirebaseFirestore.instance.collection('activity_logs').add({
          'type': 'auto_clock_out',
          'action': 'Auto Clock-Out ($trigger)',
          'employeeId': _employeeDocId ?? _employeeId,
          'employee_id': _employeeId,
          'employee_name': _employeeName,
          'email': _employeeEmail ?? '',
          'verification_method': 'auto',
          'trigger': trigger,
          'time': timeStr,
          'date': dateStr,
          'timestamp': FieldValue.serverTimestamp(),
          'device': 'Auto Clock-Out',
          'device_binding': 'presence_monitor',
          'platform': 'system',
          ...locPayload,
        });
      } catch (e) {
        debugPrint('⚠️ [AutoClockOut] activity_logs failed: $e');
      }

      try {
        await FirebaseFirestore.instance.collection('security_events').add({
          'type': 'auto_clock_out',
          'severity': 'info',
          'details': 'Auto clock-out triggered: $trigger',
          'employeeId': _employeeDocId ?? _employeeId,
          'employee_id': _employeeId,
          'employee_name': _employeeName,
          'trigger': trigger,
          'overtimeActive': _overtimeActive,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      try {
        final docId = _employeeDocId ?? _employeeId;
        if (docId != null) {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(docId)
              .set({
            'lastAutoClockOutAt': FieldValue.serverTimestamp(),
            'lastAutoClockOutTrigger': trigger,
            'isClockedIn': false,
            'lastClockOutAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}

      // Notify employee
      try {
        final triggerMsg = {
          'geofence_exit': 'You left the work zone',
          'shift_end': 'Your shift has ended (5:00 PM)',
          'no_heartbeat': 'Your phone was not detected for 30+ mins',
          'hard_cap': 'Reached maximum work hours ($_overtimeHardCapTime)',
          'manual': 'Manual admin trigger',
        }[trigger] ??
            trigger;

        await EmployeeNotificationService.instance.send(
          type: 'auto_clock_out',
          title: '⏰ Auto Clocked Out',
          message:
          'You were automatically clocked out. $triggerMsg. Time: $timeStr. If this is a mistake, contact your admin.',
          employeeId: _employeeId!,
          senderName: 'System',
          priority: 'high',
          metadata: {
            'trigger': trigger,
            'time': timeStr,
            'date': dateStr,
            'alertType': 'auto_clock_out_performed',
            'triggeredAt': now.toIso8601String(),
          },
        );
      } catch (e) {
        debugPrint('⚠️ [AutoClockOut] Notify employee failed: $e');
      }

      // Notify admin
      try {
        await AdminNotificationService.instance.notifyAutoClockOut(
          employeeId: _employeeId!,
          employeeName: _employeeName!,
          trigger: trigger,
          timeStr: timeStr,
          dateStr: dateStr,
        );
      } catch (e) {
        debugPrint('⚠️ [AutoClockOut] Notify admin failed: $e');
      }

      _lastAutoClockOutPerformedDate = todayStr;
      _lastAutoClockOutTrigger = trigger;
      _autoClockOutAt = now;
      _lastAutoClockOutNotifDate = todayStr;

      debugPrint('🎉 [AutoClockOut] COMPLETE — $trigger');
    } catch (e, st) {
      debugPrint('❌ [AutoClockOut] FAILED: $e');
      debugPrint('$st');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ENTRY REMINDER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _notifyEmployeeOutOfRange(
      double distanceMeters, {
        bool forced = false,
      }) async {
    if (_employeeId == null || _employeeName == null) return;

    final now = DateTime.now();
    if (_lastEmployeeAlertAt != null &&
        now.difference(_lastEmployeeAlertAt!) < _employeeAlertCooldown &&
        !forced) {
      return;
    }

    final enabled = await _isSettingEnabled(
      'entryReminders',
      defaultValue: false,
    );
    if (!enabled) return;

    _lastEmployeeAlertAt = now;

    final distStr = distanceMeters > 0
        ? '${distanceMeters.toStringAsFixed(0)}m from the office'
        : 'far from the work zone';

    try {
      final title = forced
          ? '📍 Out of Range Alert (Test)'
          : '📍 Out of Range Alert';

      final message = forced
          ? 'Test notification for Entry Reminders.'
          : 'You are outside the working zone ($distStr). Please return within the office radius for accurate attendance.';

      await EmployeeNotificationService.instance.send(
        type: 'geofence_alert',
        title: title,
        message: message,
        employeeId: _employeeId!,
        senderName: 'System',
        priority: 'high',
        metadata: {
          'distanceMeters': distanceMeters,
          'alertType': 'out_of_range',
          'forced': forced,
          'triggeredAt': now.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('❌ [EntryReminder] failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GEOFENCE VIOLATION
  // ═══════════════════════════════════════════════════════════════
  Future<void> _notifyGeofenceViolation(
      double distanceMeters,
      Duration outsideDuration, {
        bool forced = false,
      }) async {
    if (_employeeId == null || _employeeName == null) return;

    final now = DateTime.now();
    if (_lastViolationNotifAt != null &&
        now.difference(_lastViolationNotifAt!) < _violationCooldown &&
        !forced) {
      return;
    }

    final enabled = await _isSettingEnabled(
      'geofenceViolation',
      defaultValue: false,
    );
    if (!enabled) return;

    _lastViolationNotifAt = now;

    final distStr = distanceMeters > 0
        ? '${distanceMeters.toStringAsFixed(0)}m from the office'
        : 'far from the work zone';
    final minStr = outsideDuration.inMinutes;

    try {
      final title = forced
          ? '🚨 Geofence Violation (Test)'
          : '🚨 Geofence Violation';

      final message = forced
          ? 'Test notification for Geofence Violation.'
          : 'You have been outside the work zone for $minStr minutes ($distStr). Please return inside to avoid attendance flagging.';

      await EmployeeNotificationService.instance.send(
        type: 'geofence_violation',
        title: title,
        message: message,
        employeeId: _employeeId!,
        senderName: 'System',
        priority: 'high',
        metadata: {
          'distanceMeters': distanceMeters,
          'outsideMinutes': minStr,
          'alertType': 'geofence_violation',
          'forced': forced,
          'triggeredAt': now.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('❌ [Violation] failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LEGACY: Auto clock-out REMINDER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkAutoClockOutReminder({bool forced = false}) async {
    if (_employeeId == null || _employeeName == null) return;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (!forced && _lastAutoClockOutNotifDate == todayStr) return;

    if (!forced) {
      final shiftEnd = DateTime(
        now.year, now.month, now.day,
        _shiftEndHour, _shiftEndMinute,
      );
      if (now.isBefore(shiftEnd)) return;
    }

    final enabled = await _isSettingEnabled(
      'autoClockOut',
      defaultValue: false,
    );
    if (!enabled) return;

    if (_lastAutoClockOutPerformedDate == todayStr &&
        _autoClockOutAt != null &&
        now.difference(_autoClockOutAt!).inMinutes < 5) {
      return;
    }

    _lastAutoClockOutNotifDate = todayStr;

    try {
      final title = forced
          ? '⏰ Time to Clock Out (Test)'
          : '⏰ Time to Clock Out';

      final message = forced
          ? 'Test notification for Auto Clock-Out.'
          : 'Your shift has ended (5:00 PM). Please remember to clock out to keep your attendance record accurate.';

      await EmployeeNotificationService.instance.send(
        type: 'auto_clock_out',
        title: title,
        message: message,
        employeeId: _employeeId!,
        senderName: 'System',
        priority: 'high',
        metadata: {
          'shiftEnd': '17:00',
          'alertType': 'auto_clock_out',
          'forced': forced,
          'triggeredAt': now.toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('❌ [AutoClockOut-Reminder] failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPER — read setting from Firestore
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _isSettingEnabled(
      String key, {
        bool defaultValue = false,
      }) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get()
          .timeout(const Duration(seconds: 5));

      final data = doc.data();
      if (data == null) return defaultValue;

      final raw = data[key];
      if (raw is bool) return raw;

      return defaultValue;
    } catch (e) {
      debugPrint('⚠️ [$key] read failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LAYER 2 — BACKUP → .txt file
  // ═══════════════════════════════════════════════════════════════
  Future<void> _backupNow({String reason = 'hourly'}) async {
    if (!_enabled) return;
    if (_backingUp) return;
    if (_employeeId == null || _employeeName == null) return;

    _backingUp = true;
    _backupCount++;

    try {
      final presenceDoc = await FirebaseFirestore.instance
          .collection('employee_presence')
          .doc(_employeeId)
          .get();

      if (!presenceDoc.exists) return;

      final data = presenceDoc.data() ?? {};
      final zone = (data['zone'] ?? 'unknown').toString();
      final distance = (data['distanceMeters'] as num?)?.toDouble() ?? 0;
      final accuracy = (data['accuracyMeters'] as num?)?.toDouble();

      final result = await PresenceBackupService.instance.generateBackup(
        employeeId: _employeeId!,
        employeeName: _employeeName!,
        zone: zone,
        distanceMeters: distance,
        accuracyMeters: accuracy,
        checkCount: _checkCount,
      );

      if (result.success) {
        _lastBackupAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('❌ [Backup] Failed: $e');
    } finally {
      _backingUp = false;
    }
  }

  Future<void> forceBackup() async => _backupNow(reason: 'manual');

  // ═══════════════════════════════════════════════════════════════
  // LAYER 1 — Update live presence doc
  // ═══════════════════════════════════════════════════════════════
  Future<void> _updateLivePresence({
    required String zone,
    required double distance,
    double? accuracy,
  }) async {
    if (_employeeId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('employee_presence')
          .doc(_employeeId)
          .set({
        'employeeId': _employeeId,
        'employeeName': _employeeName,
        'employeeEmail': _employeeEmail,
        'zone': zone,
        'inRange': zone == 'inside',
        'distanceMeters': distance,
        if (accuracy != null) 'accuracyMeters': accuracy,
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastUpdatedLocal': DateTime.now().toIso8601String(),
        'isOnline': NetworkGuard.instance.isOnline,
        'checkCount': _checkCount,
        if (_outsideSince != null)
          'outsideSince': Timestamp.fromDate(_outsideSince!),
        if (_autoClockOutAt != null)
          'lastAutoClockOutAt': Timestamp.fromDate(_autoClockOutAt!),
        if (_lastAutoClockOutTrigger != null)
          'lastAutoClockOutTrigger': _lastAutoClockOutTrigger,
        if (_lastHeartbeatAt != null)
          'lastHeartbeatAt': Timestamp.fromDate(_lastHeartbeatAt!),
        // Auto OT info
        'overtimeAutoDetectEnabled': _overtimeAutoDetectEnabled,
        'overtimeActive': _overtimeActive,
        if (_overtimeStartedAt != null)
          'overtimeStartedAt': Timestamp.fromDate(_overtimeStartedAt!),
        'overtimeHardCap': _overtimeHardCapTime,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ [Live] Presence update failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MANUAL TRIGGERS (for admin testing)
  // ═══════════════════════════════════════════════════════════════
  Future<void> forceAutoClockOut({String trigger = 'manual'}) async {
    debugPrint('🔥 [AutoClockOut] MANUAL TRIGGER: $trigger');
    await _performAutoClockOut(trigger: trigger, forced: true);
  }

  Future<void> forceNotifyNextCheck() async {
    debugPrint('🔥 [Presence] Forcing next check with notify');
    _forceTriggerNextCheck = true;
    await checkNow(forceNotify: true);
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBUG INFO
  // ═══════════════════════════════════════════════════════════════
  Map<String, dynamic> debugInfo() {
    return {
      'isRunning': isRunning,
      'isEnabled': _enabled,
      'employeeId': _employeeId,
      'employeeName': _employeeName,
      'currentZone': _lastZone,
      'checkCount': _checkCount,
      'lastEntryReminders': _lastEntryReminders,
      'lastViolation': _lastViolation,
      'lastAutoOut': _lastAutoOut,
      'lastNotifiedAt': _lastNotifiedAt?.toIso8601String(),
      'lastHeartbeatAt': _lastHeartbeatAt?.toIso8601String(),
      'lastEmployeeAlertAt': _lastEmployeeAlertAt?.toIso8601String(),
      'lastViolationNotifAt': _lastViolationNotifAt?.toIso8601String(),
      'outsideSince': _outsideSince?.toIso8601String(),
      'lastAutoClockOutNotifDate': _lastAutoClockOutNotifDate,
      'lastAutoClockOutPerformedDate': _lastAutoClockOutPerformedDate,
      'lastAutoClockOutTrigger': _lastAutoClockOutTrigger,
      'autoClockOutAt': _autoClockOutAt?.toIso8601String(),
      'motionDetectionRunning': MotionDetectionService.instance.isRunning,
      // Auto OT fields
      'overtimeAutoDetectEnabled': _overtimeAutoDetectEnabled,
      'overtimeActive': _overtimeActive,
      'overtimeStartedAt': _overtimeStartedAt?.toIso8601String(),
      'overtimeHardCapTime': _overtimeHardCapTime,
      // 🆕 v2.3
      'presenceChallengeRunning': PresenceChallengeService.instance.debugInfo(),
    };
  }

  void printDebugInfo() {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🛰️ [PresenceMonitor] DEBUG INFO');
    debugPrint('═══════════════════════════════════════════');
    debugInfo().forEach((key, value) => debugPrint('   $key: $value'));
    debugPrint('═══════════════════════════════════════════');
  }

  void dispose() {
    reset();
  }
}