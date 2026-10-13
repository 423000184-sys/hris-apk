// lib/services/presence_challenge_service.dart
// ═══════════════════════════════════════════════════════════════════
// PRESENCE CHALLENGE SERVICE v2.0
//
// v2.0 CHANGES (AUTO-ENFORCEMENT):
//   ✅ Auto-clock-out kapag 3+ missed challenges
//   ✅ Auto-clock-out kapag 15+ minutes outside zone
//   ✅ Auto-cancel (hindi missed) kapag user ay nasa labas ngayon
//   ✅ CRITICAL admin notifications para sa lahat ng auto-actions
//   ✅ Duplicate notification guard (_notifiedMissed)
//   ✅ checkNow() para sa instant checks
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'clock_status_service.dart';
import 'geofence_service.dart';
import 'offline_attendance_service.dart';

// ═══════════════════════════════════════════════════════════════
// Challenge Model
// ═══════════════════════════════════════════════════════════════
class PresenceChallenge {
  final String id;
  final String employeeId;
  final DateTime dueAt;
  final DateTime expiresAt;

  const PresenceChallenge({
    required this.id,
    required this.employeeId,
    required this.dueAt,
    required this.expiresAt,
  });

  factory PresenceChallenge.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return PresenceChallenge(
      id: d.id,
      employeeId: m['employeeId'] as String,
      dueAt: (m['dueAt'] as Timestamp).toDate(),
      expiresAt: (m['expiresAt'] as Timestamp).toDate(),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isDue => !DateTime.now().isBefore(dueAt);

  @override
  String toString() =>
      'PresenceChallenge(id=$id, dueAt=$dueAt, expiresAt=$expiresAt)';
}

// ═══════════════════════════════════════════════════════════════
// ChallengeDue — may geofence info
// ═══════════════════════════════════════════════════════════════
class ChallengeDue {
  final PresenceChallenge challenge;
  final bool isInside;
  final double? distanceMeters;
  final double? radiusUsed;
  final String? zoneName;
  final String? zoneStatus;

  const ChallengeDue({
    required this.challenge,
    required this.isInside,
    this.distanceMeters,
    this.radiusUsed,
    this.zoneName,
    this.zoneStatus,
  });

  @override
  String toString() =>
      'ChallengeDue(id=${challenge.id}, inside=$isInside, '
          'dist=${distanceMeters?.toStringAsFixed(0)}m, zone=$zoneName)';
}

// ═══════════════════════════════════════════════════════════════
// Service
// ═══════════════════════════════════════════════════════════════
class PresenceChallengeService {
  PresenceChallengeService._();
  static final instance = PresenceChallengeService._();

  // ─── CONFIG ────────────────────────────────────────────────
  static const bool testMode = false;
  static const int challengesPerDay = 3;
  static const int _testChallengesPerDay = 1;

  static const Duration responseWindow = Duration(minutes: 5);

  /// ⚡ TEST: 2 min
  /// ⚠️ PRODUCTION: `Duration(minutes: 45)`
  static const Duration afterClockInBuffer = Duration(minutes: 2);

  static const Duration beforeShiftEndBuffer = Duration(minutes: 30);
  static const int shiftEndHour = 17;

  // 🆕 AUTO-ENFORCEMENT CONFIG
  /// Kapag 3+ missed challenges → auto-clock-out
  static const int missedThresholdForAutoClockout = 3;

  /// Kapag outside ng work zone for X minutes → auto-clock-out
  static const Duration outOfRangeAutoClockoutThreshold = Duration(minutes: 15);

  // ─── INTERNAL ──────────────────────────────────────────────
  final _db = FirebaseFirestore.instance;
  final _rng = Random.secure();
  final List<PresenceChallenge> _pending = [];
  final Set<String> _prompted = {};
  final Set<String> _notifiedMissed = {};   // 🆕 duplicate guard

  Timer? _tick;
  String? _activeEmployeeId;
  String? _activeEmployeeName;
  bool _debugLog = kDebugMode;

  // 🆕 Auto-enforcement state
  DateTime? _outOfRangeSince;
  DateTime? _lastAutoClockoutAt;
  bool _autoClockoutTriggeredToday = false;

  /// Callback kapag may due.
  void Function(ChallengeDue due)? onDue;

  /// Callback kapag may missed challenges on start.
  void Function(int missedCount)? onMissedSummary;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('presence_challenges');

  CollectionReference<Map<String, dynamic>> get _adminNotifCol =>
      _db.collection('admin_notifications');

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _effectiveCount =>
      testMode ? _testChallengesPerDay : challengesPerDay;

  void _log(String msg) {
    if (_debugLog) debugPrint('[PresenceChallenge] $msg');
  }

  // ═══════════════════════════════════════════════════════════
  // PUBLIC HELPERS
  // ═══════════════════════════════════════════════════════════
  bool get isRunning => _tick != null && _activeEmployeeId != null;

  bool get hasDueChallenge {
    final now = DateTime.now();
    return _pending.any(
            (c) => !now.isBefore(c.dueAt) && now.isBefore(c.expiresAt));
  }

  Future<void> checkNow() async {
    final id = _activeEmployeeId;
    if (id == null || id.isEmpty) {
      _log('⚠️ checkNow skipped — no active employee');
      return;
    }
    if (_tick == null) {
      _log('⚠️ checkNow skipped — service not started');
      return;
    }

    _log('⚡ checkNow() — instant check triggered');
    try {
      await _load(id);
      await _check(id);
    } catch (e) {
      _log('⚠️ checkNow error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SCHEDULE
  // ═══════════════════════════════════════════════════════════
  Future<void> scheduleForToday({
    required String employeeId,
    required DateTime clockInAt,
    String? employeeName,
  }) async {
    if (employeeId.isEmpty) {
      _log('⚠️ scheduleForToday skipped — empty employeeId');
      return;
    }

    _activeEmployeeName = employeeName;

    final now = DateTime.now();
    final date = _dateStr(now);

    try {
      final probe = await _col.doc('${employeeId}_${date}_0').get();
      if (probe.exists) {
        _log('ℹ️ Challenges already exist for $employeeId on $date — skip');
        return;
      }
    } catch (e) {
      _log('⚠️ Probe failed (offline?) — skip schedule: $e');
      return;
    }

    DateTime windowStart;
    DateTime windowEnd;

    if (testMode) {
      windowStart = now.add(const Duration(minutes: 1));
      windowEnd = now.add(const Duration(minutes: 6));
      _log('🧪 TEST MODE — window = now+1min to now+6min');
    } else {
      final earliest = clockInAt.add(afterClockInBuffer);
      windowStart =
      earliest.isAfter(now) ? earliest : now.add(const Duration(minutes: 1));

      windowEnd = DateTime(
        now.year,
        now.month,
        now.day,
        shiftEndHour,
        0,
      ).subtract(beforeShiftEndBuffer);
    }

    final totalMinutes = windowEnd.difference(windowStart).inMinutes;
    if (totalMinutes < _effectiveCount * 2) {
      _log('ℹ️ Not enough time window ($totalMinutes min) — skip');
      return;
    }

    final slotMinutes = totalMinutes ~/ _effectiveCount;
    final batch = _db.batch();

    for (var i = 0; i < _effectiveCount; i++) {
      final offset =
          i * slotMinutes + (slotMinutes > 1 ? _rng.nextInt(slotMinutes) : 0);
      final dueAt = windowStart.add(Duration(minutes: offset));
      final expiresAt = dueAt.add(responseWindow);

      batch.set(_col.doc('${employeeId}_${date}_$i'), {
        'employeeId': employeeId,
        'employeeName': employeeName ?? '',
        'date': date,
        'dueAt': Timestamp.fromDate(dueAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'status': 'pending',
        'attempts': 0,
        'testMode': testMode,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _log('📅 Scheduled #$i → due $dueAt, expires $expiresAt');
    }

    try {
      await batch.commit();
      _log('✅ Scheduled $_effectiveCount challenge(s) for $employeeId');
    } catch (e) {
      _log('❌ Batch commit failed: $e');
      return;
    }

    await _load(employeeId);
  }

  // ═══════════════════════════════════════════════════════════
  // START / STOP
  // ═══════════════════════════════════════════════════════════
  Future<void> start(String employeeId, {String? employeeName}) async {
    if (_activeEmployeeId == employeeId && _tick != null) {
      _log('ℹ️ Already running for $employeeId — skipping restart');
      if (employeeName != null && employeeName.isNotEmpty) {
        _activeEmployeeName = employeeName;
      }
      await _load(employeeId);
      return;
    }

    stop();
    _activeEmployeeId = employeeId;
    if (employeeName != null && employeeName.isNotEmpty) {
      _activeEmployeeName = employeeName;
    }

    // Reset daily auto-clockout flag
    _autoClockoutTriggeredToday = false;
    _outOfRangeSince = null;

    final missedCount = await _auditExpiredChallenges(employeeId);
    if (missedCount > 0 && onMissedSummary != null) {
      _log('⚠️ [Audit] $missedCount missed challenge(s) flagged');
      try {
        onMissedSummary!(missedCount);
      } catch (e) {
        _log('⚠️ onMissedSummary callback error: $e');
      }
    }

    await _load(employeeId);

    _tick = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _check(employeeId),
    );

    _log('🛰️ Started for $employeeId '
        '(${_pending.length} pending, ${testMode ? "TEST" : "PROD"} mode)');
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
    _pending.clear();
    _prompted.clear();
    _notifiedMissed.clear();
    _activeEmployeeId = null;
    _outOfRangeSince = null;
    _log('🛑 Stopped');
  }

  // ═══════════════════════════════════════════════════════════
  // AUDIT — with clock status verification
  // ═══════════════════════════════════════════════════════════
  Future<int> _auditExpiredChallenges(String employeeId) async {
    try {
      bool clockedIn = false;
      try {
        clockedIn = await ClockStatusService.instance
            .isCurrentlyClockedIn(employeeId)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        _log('⚠️ [Audit] Clock status check failed: $e — assuming clocked in');
        clockedIn = true;
      }

      _log('🔍 [Audit] Employee clockedIn=$clockedIn');

      final snap = await _col
          .where('employeeId', isEqualTo: employeeId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isEmpty) {
        _log('🔍 [Audit] No pending challenges to audit');
        return 0;
      }

      final now = DateTime.now();
      int flaggedMissed = 0;
      int cancelled = 0;

      for (final doc in snap.docs) {
        final c = PresenceChallenge.fromDoc(doc);

        if (!clockedIn) {
          try {
            await _col.doc(c.id).update({
              'status': 'cancelled',
              'resolvedAt': FieldValue.serverTimestamp(),
              'resolvedBy': 'audit_clocked_out',
            });
            cancelled++;
          } catch (e) {
            _log('⚠️ [Audit] Cancel failed: $e');
          }
          continue;
        }

        if (now.isAfter(c.expiresAt)) {
          await _markMissed(c);
          flaggedMissed++;
        }
      }

      _log('🔍 [Audit] Done — $flaggedMissed missed, $cancelled cancelled');
      return flaggedMissed;
    } catch (e) {
      _log('⚠️ [Audit] Failed: $e');
      return 0;
    }
  }

  Future<void> _load(String employeeId) async {
    try {
      final snap = await _col
          .where('employeeId', isEqualTo: employeeId)
          .where('date', isEqualTo: _dateStr(DateTime.now()))
          .where('status', isEqualTo: 'pending')
          .get();

      _pending
        ..clear()
        ..addAll(snap.docs.map(PresenceChallenge.fromDoc));

      // Clean notifiedMissed — alisin ang wala na sa pending
      _notifiedMissed.removeWhere(
              (id) => !_pending.any((c) => c.id == id));

      _log('📥 Loaded ${_pending.length} pending challenge(s)');
    } catch (e) {
      _log('⚠️ _load failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CHECK (main loop)
  // ═══════════════════════════════════════════════════════════
  Future<void> _check(String employeeId) async {
    // 🆕 1) Auto-clock-out check kung 3+ missed
    await _checkMissedThreshold(employeeId);

    // 🆕 2) Auto-clock-out check kung outside for 15+ min
    await _checkOutOfRange(employeeId);

    // Kung may trigger na auto-clockout, tapos na tayo
    if (_autoClockoutTriggeredToday) return;

    if (_pending.isEmpty) return;

    // Verify clock status first
    try {
      final clockedIn =
      await ClockStatusService.instance.isCurrentlyClockedIn(employeeId);
      if (!clockedIn) {
        _log('🚪 Not clocked-in — cancelling all pending challenges');
        await _cancelAll();
        return;
      }
    } catch (e) {
      _log('⚠️ Clock status check failed: $e');
      return;
    }

    final now = DateTime.now();
    final expired = _pending.where((c) => now.isAfter(c.expiresAt)).toList();
    final due = _pending
        .where((c) =>
    !now.isBefore(c.dueAt) &&
        now.isBefore(c.expiresAt) &&
        !_prompted.contains(c.id))
        .toList();

    if (expired.isEmpty && due.isEmpty) return;

    for (final c in expired) {
      _log('⏰ Challenge EXPIRED: ${c.id}');

      // 🆕 Bago i-mark as missed, i-check kung nasa labas ba si user.
      //    Kung nasa labas → i-cancel (fair) at notify admin.
      final isOutside = await _isEmployeeCurrentlyOutside(employeeId);

      if (isOutside) {
        _log('📍 [Challenge] User outside — cancelling (not marking missed)');
        await _cancelOutside(c);
      } else {
        await _markMissed(c);
      }
      _pending.remove(c);
    }

    for (final c in due) {
      _log('🎯 Challenge DUE: ${c.id} — verifying geofence...');

      bool isInside = false;
      double? distance;
      double? radius;
      String? zoneName;
      String? zoneStatus;

      try {
        final geo = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: employeeId)
            .timeout(const Duration(seconds: 20));

        isInside = geo.isAllowed || geo.isExempted;
        distance = geo.distanceMeters;
        radius = geo.radiusUsed;
        zoneName = geo.matchedLocationName;
        zoneStatus = geo.status?.toString();

        _log('📍 [Challenge] Geofence: '
            '${isInside ? "INSIDE ✅" : "OUTSIDE ❌"}');
      } catch (e) {
        _log('⚠️ [Challenge] Geofence check failed: $e');
        isInside = true;
      }

      _prompted.add(c.id);

      final dueContext = ChallengeDue(
        challenge: c,
        isInside: isInside,
        distanceMeters: distance,
        radiusUsed: radius,
        zoneName: zoneName,
        zoneStatus: zoneStatus,
      );

      unawaited(_logChallengeFired(dueContext));
      onDue?.call(dueContext);
    }
  }

  /// Helper: is the employee currently outside the work zone?
  Future<bool> _isEmployeeCurrentlyOutside(String employeeId) async {
    try {
      final geo = await GeofenceService.instance
          .checkGeofenceForEmployee(employeeId: employeeId)
          .timeout(const Duration(seconds: 15));
      return !(geo.isAllowed || geo.isExempted);
    } catch (e) {
      _log('⚠️ _isEmployeeCurrentlyOutside error: $e — assume inside');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 AUTO-CLOCK-OUT: 3+ MISSED CHALLENGES
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkMissedThreshold(String employeeId) async {
    if (_autoClockoutTriggeredToday) return;

    try {
      final date = _dateStr(DateTime.now());
      final snap = await _col
          .where('employeeId', isEqualTo: employeeId)
          .where('date', isEqualTo: date)
          .where('status', isEqualTo: 'missed')
          .get();

      final missedCount = snap.docs.length;
      if (missedCount < missedThresholdForAutoClockout) return;

      // Double-check: naka-clock-in pa ba?
      final clockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(employeeId);
      if (!clockedIn) return;

      _log('🚨 [AutoClockOut] $missedCount missed challenges '
          '— TRIGGERING auto-clock-out');

      await _forceAutoClockOut(
        employeeId: employeeId,
        reason: 'auto_clockout_${missedCount}_missed_challenges',
      );
    } catch (e) {
      _log('⚠️ _checkMissedThreshold error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 AUTO-CLOCK-OUT: 15+ MINUTES OUTSIDE
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkOutOfRange(String employeeId) async {
    if (_autoClockoutTriggeredToday) return;

    try {
      // Naka-clock-in ba?
      final clockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(employeeId);
      if (!clockedIn) {
        _outOfRangeSince = null;
        return;
      }

      // Nasa labas ba?
      final isOutside = await _isEmployeeCurrentlyOutside(employeeId);

      if (isOutside) {
        _outOfRangeSince ??= DateTime.now();

        final duration = DateTime.now().difference(_outOfRangeSince!);
        _log('⚠️ [AutoClockOut] Outside for ${duration.inMinutes}min '
            '(threshold: ${outOfRangeAutoClockoutThreshold.inMinutes}min)');

        if (duration >= outOfRangeAutoClockoutThreshold) {
          _log('🚨 [AutoClockOut] Outside for ${duration.inMinutes}min '
              '— TRIGGERING auto-clock-out');

          await _forceAutoClockOut(
            employeeId: employeeId,
            reason:
            'auto_clockout_outside_${duration.inMinutes}min',
          );
          _outOfRangeSince = null;
        }
      } else {
        if (_outOfRangeSince != null) {
          _log('✅ [AutoClockOut] Back in range — out-of-range timer reset');
        }
        _outOfRangeSince = null;
      }
    } catch (e) {
      _log('⚠️ _checkOutOfRange error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🆕 FORCE AUTO-CLOCK-OUT
  // ═══════════════════════════════════════════════════════════
  Future<void> _forceAutoClockOut({
    required String employeeId,
    required String reason,
  }) async {
    if (_autoClockoutTriggeredToday) {
      _log('⏭️ [AutoClockOut] Already triggered today — skip');
      return;
    }
    _autoClockoutTriggeredAt = DateTime.now();
    _autoClockoutTriggeredToday = true;

    final now = DateTime.now();
    final dateStr = _dateStr(now);
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final employeeName = _activeEmployeeName ?? employeeId;

    _log('🚨 [AutoClockOut] EXECUTING for $employeeId — reason: $reason');

    // 1) Cancel all pending challenges
    try {
      await _cancelAll();
    } catch (e) {
      _log('⚠️ [AutoClockOut] Cancel pending failed: $e');
    }

    // 2) Write attendance_log OUT (via OfflineAttendanceService para may sync)
    try {
      await OfflineAttendanceService.instance.logAttendance(
        employeeId: employeeId,
        employeeName: employeeName,
        employeeEmail: '',
        type: 'OUT',
        timestamp: now,
        device: 'AutoEnforcement',
        remarks: reason,
        zoneType: 'inside',
      );
      _log('✅ [AutoClockOut] Local attendance OUT written');
    } catch (e) {
      _log('⚠️ [AutoClockOut] Local attendance failed: $e');
    }

    // 3) Write Firestore attendance_log directly (belt + suspenders)
    try {
      await _db.collection('attendance_logs').add({
        'employee_id': employeeId,
        'employee_name': employeeName,
        'type': 'OUT',
        'date': dateStr,
        'time': timeStr,
        'timestamp': FieldValue.serverTimestamp(),
        'device': 'AutoEnforcement',
        'remarks': reason,
        'zone_type': 'inside',
        'auto_clockout': true,
        'auto_clockout_reason': reason,
        'session_nonce': null,
        'face_match_percent': 0,
        'match_score': 0,
      });
      _log('✅ [AutoClockOut] Firestore attendance OUT written');
    } catch (e) {
      _log('❌ [AutoClockOut] Firestore write failed: $e');
    }

    // 4) CRITICAL admin notification
    try {
      await _adminNotifCol.add({
        'type': 'challenge_auto_clockout',
        'title': '🚨 AUTO-CLOCK-OUT — Possible Abandonment',
        'message':
        '$employeeName was automatically clocked out.\nReason: $reason',
        'employeeId': employeeId,
        'employeeName': employeeName,
        'priority': 'critical',
        'metadata': {
          'reason': reason,
          'missedThreshold': missedThresholdForAutoClockout,
          'outOfRangeThresholdMin':
          outOfRangeAutoClockoutThreshold.inMinutes,
          'clockoutAt': now.toIso8601String(),
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      _log('📢 [AutoClockOut] Admin notified (CRITICAL)');
    } catch (e) {
      _log('⚠️ [AutoClockOut] Admin notif failed: $e');
    }

    // 5) Log security event
    try {
      await _db.collection('security_events').add({
        'type': 'auto_clockout_triggered',
        'severity': 'high',
        'details': 'Auto-clock-out triggered for $employeeId: $reason',
        'employeeId': employeeId,
        'employeeName': employeeName,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // 6) Stop the service — walang nang challenge pag clock-out na
    _log('🛑 [AutoClockOut] Stopping service (auto-clockout complete)');
    stop();
  }

  // 🆕 Reference — kailangan i-declare sa field list
  DateTime? _autoClockoutTriggeredAt;

  Future<void> _logChallengeFired(ChallengeDue due) async {
    try {
      await _col.doc(due.challenge.id).update({
        'firedAt': FieldValue.serverTimestamp(),
        'insideAtFire': due.isInside,
        if (due.distanceMeters != null)
          'distanceAtFire': due.distanceMeters,
        if (due.radiusUsed != null) 'radiusAtFire': due.radiusUsed,
        if (due.zoneName != null) 'zoneAtFire': due.zoneName,
      });
    } catch (e) {
      _log('⚠️ logChallengeFired failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // MARK MISSED — with duplicate guard
  // ═══════════════════════════════════════════════════════════
  Future<void> _markMissed(PresenceChallenge c) async {
    if (_notifiedMissed.contains(c.id)) {
      _log('⏭️ [Mark Missed] Already notified: ${c.id} — skip');
      return;
    }
    _notifiedMissed.add(c.id);

    String? zone;
    double? distance;

    try {
      final geo = await GeofenceService.instance
          .checkGeofence()
          .timeout(const Duration(seconds: 10));
      zone = geo.isInside ? 'inside' : 'outside';
      distance = geo.distanceMeters;
    } catch (_) {}

    try {
      await _col.doc(c.id).update({
        'status': 'missed',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': 'auto_audit',
        if (zone != null) 'zoneAtExpiry': zone,
        if (distance != null) 'distanceAtExpiry': distance,
      });
      _log('💾 Marked MISSED: ${c.id} (zone=$zone)');
    } catch (e) {
      _log('⚠️ _markMissed update failed: $e');
    }

    unawaited(_notifyAdminMissed(c, zone: zone, distance: distance));
  }

  // 🆕 Cancel (not missed) kapag user ay nasa labas
  Future<void> _cancelOutside(PresenceChallenge c) async {
    if (_notifiedMissed.contains(c.id)) {
      _log('⏭️ [Cancel Outside] Already processed: ${c.id} — skip');
      return;
    }
    _notifiedMissed.add(c.id);

    try {
      await _col.doc(c.id).update({
        'status': 'cancelled',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': 'outside_zone_at_expiry',
        'cancelReason': 'user_outside_at_expiry',
      });
      _log('📍 Marked CANCELLED (outside): ${c.id}');
    } catch (e) {
      _log('⚠️ _cancelOutside update failed: $e');
    }

    // Notify admin — mas mild kaysa missed
    try {
      final name = await _resolveEmployeeName(c.employeeId);
      await _adminNotifCol.add({
        'type': 'challenge_cancelled_outside',
        'title': '📍 Presence Check — Cancelled (Outside Zone)',
        'message':
        '$name was outside the work zone when the random check expired. '
            'Cancelled instead of marked missed.',
        'employeeId': c.employeeId,
        'employeeName': name,
        'priority': 'normal',
        'metadata': {
          'challengeId': c.id,
          'reason': 'user_outside_at_expiry',
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      _log('📢 [Admin] Notified: challenge_cancelled_outside for ${c.id}');
    } catch (e) {
      _log('⚠️ [Admin] notify cancelled_outside failed: $e');
    }
  }

  Future<void> _cancelAll() async {
    if (_pending.isEmpty) return;
    try {
      final batch = _db.batch();
      for (final c in _pending) {
        batch.update(_col.doc(c.id), {
          'status': 'cancelled',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'clock_out_detected',
        });
      }
      await batch.commit();
      _log('💾 Cancelled ${_pending.length} pending challenge(s)');
    } catch (e) {
      _log('⚠️ _cancelAll failed: $e');
    }
    _pending.clear();
    _prompted.clear();
  }

  // ═══════════════════════════════════════════════════════════
  // RESOLVE
  // ═══════════════════════════════════════════════════════════
  Future<void> submitPassed(
      PresenceChallenge c, {
        required double faceScore,
        required String zone,
        double? distanceMeters,
        String? deviceBinding,
      }) async {
    // Mark as processed para hindi na ma-mark missed
    _notifiedMissed.add(c.id);

    try {
      await _col.doc(c.id).update({
        'status': 'passed',
        'method': 'face',
        'faceScore': faceScore,
        'zone': zone,
        if (distanceMeters != null) 'distanceMeters': distanceMeters,
        if (deviceBinding != null) 'deviceBinding': deviceBinding,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      _log('✅ Marked PASSED: ${c.id} (score=$faceScore, zone=$zone)');
    } catch (e) {
      _log('⚠️ submitPassed update failed: $e');
    }
    _pending.removeWhere((x) => x.id == c.id);

    unawaited(_notifyAdminPassed(
      c,
      faceScore: faceScore,
      zone: zone,
      distanceMeters: distanceMeters,
    ));
  }

  Future<void> recordFailedAttempt(
      PresenceChallenge c, {
        required double faceScore,
        required String reason,
      }) async {
    // Mark as processed para hindi na ma-mark missed
    _notifiedMissed.add(c.id);

    try {
      await _col.doc(c.id).update({
        'status': 'failed',
        'attempts': FieldValue.increment(1),
        'lastFaceScore': faceScore,
        'lastFailReason': reason,
        'lastAttemptAt': FieldValue.serverTimestamp(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': 'user_action',
      });
      _log('❌ Recorded FAILED: ${c.id} (reason=$reason)');
    } catch (e) {
      _log('⚠️ recordFailedAttempt update failed: $e');
    }

    _pending.removeWhere((x) => x.id == c.id);

    unawaited(_notifyAdminFailed(
      c,
      faceScore: faceScore,
      reason: reason,
    ));
  }

  // ═══════════════════════════════════════════════════════════
  // ADMIN NOTIFICATION HELPERS
  // ═══════════════════════════════════════════════════════════
  Future<String> _resolveEmployeeName(String employeeId) async {
    if (_activeEmployeeName != null &&
        _activeEmployeeName!.isNotEmpty &&
        _activeEmployeeId == employeeId) {
      return _activeEmployeeName!;
    }

    try {
      final doc = await _col
          .doc('${employeeId}_${_dateStr(DateTime.now())}_0')
          .get();
      final name = doc.data()?['employeeName']?.toString();
      if (name != null && name.isNotEmpty) {
        _activeEmployeeName = name;
        return name;
      }
    } catch (_) {}

    return employeeId;
  }

  Future<void> _notifyAdminPassed(
      PresenceChallenge c, {
        required double faceScore,
        required String zone,
        double? distanceMeters,
      }) async {
    try {
      final name = await _resolveEmployeeName(c.employeeId);

      await _adminNotifCol.add({
        'type': 'challenge_passed',
        'title': '✅ Presence Check Passed',
        'message': '$name passed the random presence check '
            '(${faceScore.toStringAsFixed(1)}% face match, zone: $zone)',
        'employeeId': c.employeeId,
        'employeeName': name,
        'priority': 'normal',
        'metadata': {
          'challengeId': c.id,
          'faceScore': faceScore,
          'zone': zone,
          if (distanceMeters != null) 'distanceMeters': distanceMeters,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      _log('📢 [Admin] Notified: challenge_passed for ${c.id}');
    } catch (e) {
      _log('⚠️ [Admin] notify passed failed: $e');
    }
  }

  Future<void> _notifyAdminFailed(
      PresenceChallenge c, {
        required double faceScore,
        required String reason,
      }) async {
    try {
      final name = await _resolveEmployeeName(c.employeeId);

      await _adminNotifCol.add({
        'type': 'challenge_failed',
        'title': '❌ Presence Check Failed',
        'message': '$name FAILED the random presence check. Reason: $reason',
        'employeeId': c.employeeId,
        'employeeName': name,
        'priority': 'high',
        'metadata': {
          'challengeId': c.id,
          'faceScore': faceScore,
          'reason': reason,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      _log('📢 [Admin] Notified: challenge_failed for ${c.id}');
    } catch (e) {
      _log('⚠️ [Admin] notify failed failed: $e');
    }
  }

  Future<void> _notifyAdminMissed(
      PresenceChallenge c, {
        String? zone,
        double? distance,
      }) async {
    try {
      final name = await _resolveEmployeeName(c.employeeId);

      await _adminNotifCol.add({
        'type': 'challenge_missed',
        'title': '⚠️ Presence Check Missed',
        'message': '$name did NOT respond to the random presence check '
            'within ${responseWindow.inMinutes} minutes. '
            'Possible device abandonment.',
        'employeeId': c.employeeId,
        'employeeName': name,
        'priority': 'high',
        'metadata': {
          'challengeId': c.id,
          'windowMinutes': responseWindow.inMinutes,
          if (zone != null) 'zoneAtExpiry': zone,
          if (distance != null) 'distanceAtExpiry': distance,
        },
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      _log('📢 [Admin] Notified: challenge_missed for ${c.id}');
    } catch (e) {
      _log('⚠️ [Admin] notify missed failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // DEBUG
  // ═══════════════════════════════════════════════════════════
  Map<String, dynamic> debugInfo() => {
    'testMode': testMode,
    'challengesPerDay': _effectiveCount,
    'afterClockInBuffer': afterClockInBuffer.inMinutes,
    'activeEmployeeId': _activeEmployeeId,
    'activeEmployeeName': _activeEmployeeName,
    'pendingCount': _pending.length,
    'promptedCount': _prompted.length,
    'notifiedMissed': _notifiedMissed.length,
    'pendingIds': _pending.map((c) => c.id).toList(),
    'tickActive': _tick != null,
    'onDueHooked': onDue != null,
    'onMissedSummaryHooked': onMissedSummary != null,
    'outOfRangeSince': _outOfRangeSince?.toIso8601String(),
    'autoClockoutTriggeredToday': _autoClockoutTriggeredToday,
    'missedThreshold': missedThresholdForAutoClockout,
    'outOfRangeThresholdMin':
    outOfRangeAutoClockoutThreshold.inMinutes,
  };

  void printDebugInfo() {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🎯 [PresenceChallengeService] DEBUG INFO');
    debugPrint('═══════════════════════════════════════════');
    debugInfo().forEach((k, v) => debugPrint('   $k: $v'));
    debugPrint('═══════════════════════════════════════════');
  }
}