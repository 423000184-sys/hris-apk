// lib/services/presence_monitor_service.dart
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

/// 🛰️ Presence Monitor — 3-Layer + Real-Time Settings Listener
class PresenceMonitorService {
  PresenceMonitorService._();
  static final instance = PresenceMonitorService._();

  Timer? _liveTimer;
  Timer? _backupTimer;

  String? _employeeId;
  String? _employeeName;
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
  bool _forceTriggerNextCheck = false;

  // 🆕 EMPLOYEE ENTRY REMINDER STATE
  DateTime? _lastEmployeeAlertAt;
  static const Duration _employeeAlertCooldown = Duration(minutes: 10);

  // 🆕 GEOFENCE VIOLATION STATE
  DateTime? _outsideSince;
  DateTime? _lastViolationNotifAt;
  static const Duration _violationThreshold = Duration(minutes: 15);
  static const Duration _violationCooldown = Duration(minutes: 30);

  // 🆕 AUTO CLOCK-OUT STATE
  String? _lastAutoClockOutNotifDate;
  static const int _shiftEndHour = 17;
  static const int _shiftEndMinute = 0;

  // ⚙️ Config
  static const Duration checkInterval = Duration(minutes: 5);
  static const Duration backupInterval = Duration(minutes: 60);
  static const Duration heartbeatInterval = Duration(minutes: 30);

  // ─── Getters ───────────────────────────────────────────────────
  bool get isRunning => _liveTimer != null;
  bool get isEnabled => _enabled;
  String? get currentZone => _lastZone;
  String? get employeeId => _employeeId;
  String? get employeeName => _employeeName;
  DateTime? get lastNotifiedAt => _lastNotifiedAt;
  DateTime? get lastBackupAt => _lastBackupAt;
  DateTime? get lastEmployeeAlertAt => _lastEmployeeAlertAt;
  DateTime? get lastViolationNotifAt => _lastViolationNotifAt;
  DateTime? get outsideSince => _outsideSince;
  int get checkCount => _checkCount;
  int get backupCount => _backupCount;

  // ═══════════════════════════════════════════════════════════════
  // START / STOP
  // ═══════════════════════════════════════════════════════════════
  void start({required Employee employee}) {
    final id = employee.employeeId.isNotEmpty
        ? employee.employeeId
        : employee.id;

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
    _employeeDocId = employee.id.isNotEmpty ? employee.id : id;
    _enabled = true;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🛰️ [PresenceMonitor] STARTED');
    debugPrint('   employee : $id ($_employeeName)');
    debugPrint('═══════════════════════════════════════════');

    checkNow();
    Future.delayed(const Duration(seconds: 30), () => _backupNow());

    _liveTimer = Timer.periodic(checkInterval, (_) => checkNow());
    _backupTimer = Timer.periodic(backupInterval, (_) => _backupNow());
    _startNotificationListener();
    _startSettingsListener();
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
    _employeeDocId = null;
    _lastZone = null;
    _lastNotifiedAt = null;
    _lastBackupAt = null;
    _lastAutoBackupAt = null;
    _lastEmployeeAlertAt = null;
    _lastViolationNotifAt = null;
    _outsideSince = null;
    _lastAutoClockOutNotifDate = null;
    _firstSettingsSnapshot = true;
    _lastEntryReminders = false;
    _lastViolation = false;
    _lastAutoOut = false;
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
      checkNow();
    }
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
      }
      debugPrint('📡 [Settings] Seeded — entry: $_lastEntryReminders, '
          'violation: $_lastViolation, autoOut: $_lastAutoOut');
      return;
    }

    if (data == null) return;

    final entryOn = data['entryReminders'] == true;
    final violationOn = data['geofenceViolation'] == true;
    final autoOutOn = data['autoClockOut'] == true;

    final entryJustOn = entryOn && !_lastEntryReminders;
    final violationJustOn = violationOn && !_lastViolation;
    final autoOutJustOn = autoOutOn && !_lastAutoOut;

    final anyJustOn = entryJustOn || violationJustOn || autoOutJustOn;
    final anyJustOff = (!entryOn && _lastEntryReminders) ||
        (!violationOn && _lastViolation) ||
        (!autoOutOn && _lastAutoOut);

    _lastEntryReminders = entryOn;
    _lastViolation = violationOn;
    _lastAutoOut = autoOutOn;

    if (anyJustOn) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📡 [Settings] Toggle(s) turned ON → forcing check');
      debugPrint('   entry    : $entryOn ${entryJustOn ? "★ JUST ON" : ""}');
      debugPrint('   violation: $violationOn ${violationJustOn ? "★ JUST ON" : ""}');
      debugPrint('   autoOut  : $autoOutOn ${autoOutJustOn ? "★ JUST ON" : ""}');
      debugPrint('═══════════════════════════════════════════');

      if (entryJustOn) {
        _lastEmployeeAlertAt = null;
        debugPrint('🔄 [Settings] Reset entry reminder cooldown');
      }
      if (violationJustOn) {
        _lastViolationNotifAt = null;
        _outsideSince = null;
        debugPrint('🔄 [Settings] Reset violation cooldown + outsideSince');
      }
      if (autoOutJustOn) {
        _lastAutoClockOutNotifDate = null;
        debugPrint('🔄 [Settings] Reset auto clock-out notif date');
      }

      _forceTriggerNextCheck = true;
      checkNow();
    } else if (anyJustOff) {
      debugPrint('📡 [Settings] Toggle(s) turned OFF — future checks skip');
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
          previousZone: _lastZone,
          priority: priority,
          notifyReason: reason,
        );

        _lastNotifiedAt = now;
      }

      // ═══ 1. ENTRY REMINDERS ═══
      final shouldTriggerEntry = forceFromSettings ||
          (zone == 'outside' && (isFirstCheck || changed));

      if (shouldTriggerEntry) {
        debugPrint('📍 [Entry] Triggering — forced=$forceFromSettings, '
            'zone=$zone');
        await _notifyEmployeeOutOfRange(
          distance,
          forced: forceFromSettings,
        );
      }

      // ═══ 2. GEOFENCE VIOLATION ═══
      if (zone == 'outside') {
        _outsideSince ??= now;
        final outsideDuration = now.difference(_outsideSince!);

        debugPrint('🚨 [Violation] Check — outside for ${outsideDuration.inMinutes}min, '
            'threshold=${_violationThreshold.inMinutes}min, '
            'forced=$forceFromSettings');

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
          debugPrint('🚨 [Violation] FORCED but inside — sending test');
          await _notifyGeofenceViolation(
            distance,
            Duration.zero,
            forced: true,
          );
        }
        if (_outsideSince != null) {
          debugPrint('✅ [Violation] Back inside — resetting out-since');
          _outsideSince = null;
        }
      }

      // ═══ 3. AUTO CLOCK-OUT ═══
      debugPrint('⏰ [AutoClockOut] Calling — forced=$forceFromSettings');
      await _checkAutoClockOut(forced: forceFromSettings);

      _lastZone = zone;
    } catch (e, st) {
      debugPrint('❌ [Live] Check failed: $e');
      debugPrint('$st');
    } finally {
      _checking = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ENTRY REMINDER — ✅ ENGLISH
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
      debugPrint('⏱️ [EntryReminder] Cooldown active — skip');
      return;
    }

    final enabled = await _isSettingEnabled(
      'entryReminders',
      defaultValue: false,
    );
    if (!enabled) {
      debugPrint('🔕 [EntryReminder] OFF in admin settings — skip');
      return;
    }

    _lastEmployeeAlertAt = now;

    final distStr = distanceMeters > 0
        ? '${distanceMeters.toStringAsFixed(0)}m from the office'
        : 'far from the work zone';

    debugPrint('📍 [EntryReminder] ${forced ? "(FORCED) " : ""}'
        'Out-of-range — notifying employee');

    try {
      final title = forced
          ? '📍 Out of Range Alert (Test)'
          : '📍 Out of Range Alert';

      final message = forced
          ? 'Test notification for Entry Reminders. When enabled, employees receive this alert when they leave the work zone.'
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
      debugPrint('✅ [EntryReminder] Sent ${forced ? "(FORCED)" : ""}');
    } catch (e) {
      debugPrint('❌ [EntryReminder] failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GEOFENCE VIOLATION — ✅ ENGLISH
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
      debugPrint('⏱️ [Violation] Cooldown active — skip');
      return;
    }

    final enabled = await _isSettingEnabled(
      'geofenceViolation',
      defaultValue: false,
    );
    if (!enabled) {
      debugPrint('🔕 [Violation] OFF in admin settings — skip');
      return;
    }

    _lastViolationNotifAt = now;

    final distStr = distanceMeters > 0
        ? '${distanceMeters.toStringAsFixed(0)}m from the office'
        : 'far from the work zone';
    final minStr = outsideDuration.inMinutes;

    debugPrint('🚨 [Violation] ${forced ? "(FORCED) " : ""}'
        '${minStr}min outside — notifying employee');

    try {
      final title = forced
          ? '🚨 Geofence Violation (Test)'
          : '🚨 Geofence Violation';

      final message = forced
          ? 'Test notification for Geofence Violation. When enabled, employees automatically receive this alert after being outside the work zone for 15+ minutes.'
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
      debugPrint('✅ [Violation] Sent ${forced ? "(FORCED)" : ""}');
    } catch (e) {
      debugPrint('❌ [Violation] failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO CLOCK-OUT — ✅ ENGLISH
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkAutoClockOut({bool forced = false}) async {
    if (_employeeId == null || _employeeName == null) return;

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    if (!forced && _lastAutoClockOutNotifDate == todayStr) {
      debugPrint('ℹ️ [AutoClockOut] Already notified today — skip');
      return;
    }

    if (!forced) {
      final shiftEnd = DateTime(
        now.year,
        now.month,
        now.day,
        _shiftEndHour,
        _shiftEndMinute,
      );
      if (now.isBefore(shiftEnd)) {
        debugPrint('ℹ️ [AutoClockOut] Shift not yet ended — skip');
        return;
      }
    }

    final enabled = await _isSettingEnabled(
      'autoClockOut',
      defaultValue: false,
    );
    if (!enabled) {
      debugPrint('🔕 [AutoClockOut] OFF in admin settings — skip');
      return;
    }

    if (!forced) {
      bool isClockedIn = false;
      try {
        isClockedIn = await ClockStatusService.instance
            .isCurrentlyClockedIn(_employeeId!)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('⚠️ [AutoClockOut] clock status check failed: $e');
        return;
      }

      if (!isClockedIn) {
        debugPrint('ℹ️ [AutoClockOut] Not clocked in anymore — skip');
        return;
      }
    } else {
      debugPrint('⏰ [AutoClockOut] FORCED — skipping time/date/clock checks');
    }

    _lastAutoClockOutNotifDate = todayStr;

    debugPrint('═══════════════════════════════════════════');
    debugPrint('⏰ [AutoClockOut] ${forced ? "(FORCED) " : ""}Sending...');
    debugPrint('   emp    : $_employeeName ($_employeeId)');
    debugPrint('═══════════════════════════════════════════');

    try {
      final title = forced
          ? '⏰ Time to Clock Out (Test)'
          : '⏰ Time to Clock Out';

      final message = forced
          ? 'Test notification for Auto Clock-Out. When enabled, employees automatically receive this alert when their shift ends (5:00 PM) and they are still clocked in.'
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
      debugPrint('✅ [AutoClockOut] Sent ${forced ? "(FORCED)" : ""}');
    } catch (e) {
      debugPrint('❌ [AutoClockOut] failed: $e');
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
      if (data == null) {
        debugPrint('ℹ️ [$key] No settings doc — default $defaultValue');
        return defaultValue;
      }

      final raw = data[key];
      if (raw is bool) {
        debugPrint('ℹ️ [$key] = $raw');
        return raw;
      }

      debugPrint('ℹ️ [$key] not set — default $defaultValue');
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
      }, SetOptions(merge: true));
      debugPrint('📄 [Live] Presence doc updated ($zone)');
    } catch (e) {
      debugPrint('⚠️ [Live] Presence update failed: $e');
    }
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
      'lastEmployeeAlertAt': _lastEmployeeAlertAt?.toIso8601String(),
      'lastViolationNotifAt': _lastViolationNotifAt?.toIso8601String(),
      'outsideSince': _outsideSince?.toIso8601String(),
      'lastAutoClockOutNotifDate': _lastAutoClockOutNotifDate,
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