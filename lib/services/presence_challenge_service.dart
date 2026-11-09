// lib/services/presence_challenge_service.dart
// ═══════════════════════════════════════════════════════════════════
// PRESENCE CHALLENGE SERVICE v3.0 (OFFLINE-SAFE)
//
// v3.0 CHANGES:
//   ✅ Offline queue para sa lahat ng writes
//   ✅ Persisted pending schedule request (retry on reconnect)
//   ✅ Persisted out-of-range timer (survives restart)
//   ✅ Cached schedule (works offline after first load)
//   ✅ Fixed duplicate attendance OUT write
//   ✅ Cached missed count (offline threshold check)
//   ✅ Graceful degradation kapag offline
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clock_status_service.dart';
import 'geofence_service.dart';
import 'offline_attendance_service.dart';
import '../data/local/dao/connectivity_service.dart';

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

  /// 🎯 NEW: from cached JSON
  factory PresenceChallenge.fromJson(Map<String, dynamic> j) {
    return PresenceChallenge(
      id: j['id'] as String,
      employeeId: j['employeeId'] as String,
      dueAt: DateTime.parse(j['dueAt'] as String),
      expiresAt: DateTime.parse(j['expiresAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeId': employeeId,
    'dueAt': dueAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

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

  static const int missedThresholdForAutoClockout = 3;
  static const Duration outOfRangeAutoClockoutThreshold = Duration(minutes: 15);

  // 🎯 NEW: SharedPreferences keys
  static const String _kPendingSchedulePrefix = 'pc_pending_schedule_';
  static const String _kScheduleCachePrefix = 'pc_schedule_cache_';
  static const String _kOutOfRangeSinceKey = 'pc_out_of_range_since';
  static const String _kMissedCountPrefix = 'pc_missed_count_';

  // ─── INTERNAL ──────────────────────────────────────────────
  final _db = FirebaseFirestore.instance;
  final _rng = Random.secure();
  final List<PresenceChallenge> _pending = [];
  final Set<String> _prompted = {};
  final Set<String> _notifiedMissed = {};

  Timer? _tick;
  String? _activeEmployeeId;
  String? _activeEmployeeName;
  final bool _debugLog = kDebugMode;

  // 🎯 Auto-enforcement state
  DateTime? _outOfRangeSince;
  DateTime? _lastAutoClockoutAt;

  // 🎯 MOVED: from late declaration to here
  DateTime? _autoClockoutTriggeredAt;
  bool _autoClockoutTriggeredToday = false;

  /// 🎯 NEW: cached missed count for offline threshold check
  int _cachedMissedCount = 0;

  /// 🎯 NEW: true kapag offline at hindi pa-loaded ang schedule
  bool _scheduleLoadedFromCache = false;

  void Function(ChallengeDue due)? onDue;
  void Function(int missedCount)? onMissedSummary;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('presence_challenges');

  CollectionReference<Map<String, dynamic>> get _adminNotifCol =>
      _db.collection('admin_notifications');

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _effectiveCount =>
      testMode ? _testChallengesPerDay : challengesPerDay;

  bool get _isOnline {
    try {
      return ConnectivityService.instance.isOnline;
    } catch (_) {
      return true;
    }
  }

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

    _log('⚡ checkNow() — instant check');
    try {
      await _load(id);
      await _check(id);
    } catch (e) {
      _log('⚠️ checkNow error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 CACHE PERSISTENCE
  // ═══════════════════════════════════════════════════════════
  Future<void> _cacheSchedule(
      String employeeId, String date, List<PresenceChallenge> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = list.map((c) => c.toJson()).toList();
      await prefs.setString(
        '$_kScheduleCachePrefix${employeeId}_$date',
        jsonEncode(json),
      );
      _log('💾 Cached ${list.length} challenges for $employeeId/$date');
    } catch (e) {
      _log('⚠️ Cache write failed: $e');
    }
  }

  Future<List<PresenceChallenge>> _readCachedSchedule(
      String employeeId, String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kScheduleCachePrefix${employeeId}_$date');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((j) => PresenceChallenge.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log('⚠️ Cache read failed: $e');
      return [];
    }
  }

  // 🎯 NEW: persist pending schedule request for offline retry
  Future<void> _persistPendingSchedule({
    required String employeeId,
    required DateTime clockInAt,
    String? employeeName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_kPendingSchedulePrefix$employeeId',
        jsonEncode({
          'employeeId': employeeId,
          'clockInAt': clockInAt.toIso8601String(),
          'employeeName': employeeName,
        }),
      );
      _log('💾 Pending schedule persisted for $employeeId');
    } catch (e) {
      _log('⚠️ Persist pending failed: $e');
    }
  }

  Future<void> _clearPendingSchedule(String employeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kPendingSchedulePrefix$employeeId');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readPendingSchedule(
      String employeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_kPendingSchedulePrefix$employeeId');
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // 🎯 Persist out-of-range timer
  Future<void> _persistOutOfRange(DateTime? since) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (since == null) {
        await prefs.remove(_kOutOfRangeSinceKey);
      } else {
        await prefs.setString(
            _kOutOfRangeSinceKey, since.toIso8601String());
      }
    } catch (_) {}
  }

  Future<DateTime?> _readPersistedOutOfRange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kOutOfRangeSinceKey);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  // 🎯 Cache missed count
  Future<void> _cacheMissedCount(String employeeId, int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = _dateStr(DateTime.now());
      await prefs.setInt(
          '$_kMissedCountPrefix${employeeId}_$date', count);
      _cachedMissedCount = count;
    } catch (_) {}
  }

  Future<int> _readCachedMissedCount(String employeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final date = _dateStr(DateTime.now());
      return prefs.getInt('$_kMissedCountPrefix${employeeId}_$date') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 SCHEDULE — offline-safe with pending retry
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

    // 🎯 Kung offline → persist request at hintayin ang online
    if (!_isOnline) {
      _log('📥 Offline — persisting schedule request for $employeeId');
      await _persistPendingSchedule(
        employeeId: employeeId,
        clockInAt: clockInAt,
        employeeName: employeeName,
      );
      return;
    }

    final now = DateTime.now();
    final date = _dateStr(now);

    // ── Probe: check kung may existing na ──
    try {
      final probe = await _col.doc('${employeeId}_${date}_0').get();
      if (probe.exists) {
        _log('ℹ️ Challenges already exist for $employeeId on $date — skip');
        await _clearPendingSchedule(employeeId);
        // Cache din ang existing
        await _load(employeeId);
        return;
      }
    } catch (e) {
      _log('⚠️ Probe failed — persist for retry: $e');
      await _persistPendingSchedule(
        employeeId: employeeId,
        clockInAt: clockInAt,
        employeeName: employeeName,
      );
      return;
    }

    // ── Compute window ──
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
      await _clearPendingSchedule(employeeId);
      return;
    }

    final slotMinutes = totalMinutes ~/ _effectiveCount;
    final batch = _db.batch();
    final cacheList = <PresenceChallenge>[];

    for (var i = 0; i < _effectiveCount; i++) {
      final offset =
          i * slotMinutes + (slotMinutes > 1 ? _rng.nextInt(slotMinutes) : 0);
      final dueAt = windowStart.add(Duration(minutes: offset));
      final expiresAt = dueAt.add(responseWindow);
      final challengeId = '${employeeId}_${date}_$i';

      batch.set(_col.doc(challengeId), {
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

      cacheList.add(PresenceChallenge(
        id: challengeId,
        employeeId: employeeId,
        dueAt: dueAt,
        expiresAt: expiresAt,
      ));

      _log('📅 Scheduled #$i → due $dueAt, expires $expiresAt');
    }

    try {
      await batch.commit();
      _log('✅ Scheduled $_effectiveCount challenge(s) for $employeeId');
      // 🎯 Cache lokal para sa offline fallback
      await _cacheSchedule(employeeId, date, cacheList);
      await _clearPendingSchedule(employeeId);
    } catch (e) {
      _log('❌ Batch commit failed — persist for retry: $e');
      await _persistPendingSchedule(
        employeeId: employeeId,
        clockInAt: clockInAt,
        employeeName: employeeName,
      );
      return;
    }

    await _load(employeeId);
  }

  // 🎯 NEW: retry pending schedule kapag online
  Future<void> _retryPendingSchedule(String employeeId) async {
    if (!_isOnline) return;

    final pending = await _readPendingSchedule(employeeId);
    if (pending == null) return;

    _log('🔁 Retrying pending schedule for $employeeId');
    try {
      await scheduleForToday(
        employeeId: pending['employeeId'] as String,
        clockInAt: DateTime.parse(pending['clockInAt'] as String),
        employeeName: pending['employeeName'] as String?,
      );
    } catch (e) {
      _log('⚠️ Retry schedule failed: $e');
    }
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

    _autoClockoutTriggeredToday = false;
    _autoClockoutTriggeredAt = null;

    // 🎯 Restore persisted out-of-range
    _outOfRangeSince = await _readPersistedOutOfRange();
    if (_outOfRangeSince != null) {
      _log('♻️ Restored out-of-range since: $_outOfRangeSince');
    }

    // 🎯 Load cached missed count
    _cachedMissedCount = await _readCachedMissedCount(employeeId);

    // 🎯 Retry pending schedule kung online
    unawaited(_retryPendingSchedule(employeeId));

    // 🎯 Audit expired (online-only)
    if (_isOnline) {
      final missedCount = await _auditExpiredChallenges(employeeId);
      if (missedCount > 0 && onMissedSummary != null) {
        _log('⚠️ [Audit] $missedCount missed flagged');
        try {
          onMissedSummary!(missedCount);
        } catch (e) {
          _log('⚠️ onMissedSummary error: $e');
        }
      }
    } else {
      _log('📥 Offline at start — using cached data');
    }

    await _load(employeeId);

    _tick = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _check(employeeId),
    );

    _log('🛰️ Started for $employeeId '
        '(${_pending.length} pending, ${testMode ? "TEST" : "PROD"} mode, '
        'online=$_isOnline)');
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
    _pending.clear();
    _prompted.clear();
    _notifiedMissed.clear();
    _activeEmployeeId = null;
    // 🎯 Huwag i-clear ang _outOfRangeSince — persist siya
    _log('🛑 Stopped');
  }

  // 🎯 NEW: cleanup for logout
  Future<void> clearAll() async {
    stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
              (k) => k.startsWith('pc_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
      _log('🧹 Cleared all PC prefs');
    } catch (_) {}
    _cachedMissedCount = 0;
    _outOfRangeSince = null;
  }

  // ═══════════════════════════════════════════════════════════
  // AUDIT — online-only, but uses cached missed count offline
  // ═══════════════════════════════════════════════════════════
  Future<int> _auditExpiredChallenges(String employeeId) async {
    if (!_isOnline) {
      _log('📥 [Audit] Offline — skipping remote audit');
      return _cachedMissedCount;
    }

    try {
      bool clockedIn = false;
      try {
        clockedIn = await ClockStatusService.instance
            .isCurrentlyClockedIn(employeeId)
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        _log('⚠️ [Audit] Clock status failed: $e — assume clocked in');
        clockedIn = true;
      }

      final snap = await _col
          .where('employeeId', isEqualTo: employeeId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (snap.docs.isEmpty) {
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

      _cachedMissedCount = flaggedMissed;
      await _cacheMissedCount(employeeId, flaggedMissed);

      _log('🔍 [Audit] Done — $flaggedMissed missed, $cancelled cancelled');
      return flaggedMissed;
    } catch (e) {
      _log('⚠️ [Audit] Failed: $e');
      return _cachedMissedCount;
    }
  }

  // 🎯 UPDATED: offline fallback sa cached schedule
  Future<void> _load(String employeeId) async {
    final date = _dateStr(DateTime.now());

    if (!_isOnline) {
      // Use cached schedule
      final cached = await _readCachedSchedule(employeeId, date);
      _pending
        ..clear()
        ..addAll(cached.where((c) => !c.isExpired));
      _scheduleLoadedFromCache = true;
      _log('📥 [Cache] Loaded ${_pending.length} challenge(s) from cache');
      return;
    }

    try {
      final snap = await _col
          .where('employeeId', isEqualTo: employeeId)
          .where('date', isEqualTo: date)
          .where('status', isEqualTo: 'pending')
          .get();

      _pending
        ..clear()
        ..addAll(snap.docs.map(PresenceChallenge.fromDoc));

      // 🎯 Update cache
      await _cacheSchedule(employeeId, date, _pending);
      _scheduleLoadedFromCache = false;

      _notifiedMissed.removeWhere(
              (id) => !_pending.any((c) => c.id == id));

      _log('📥 Loaded ${_pending.length} pending challenge(s) from server');
    } catch (e) {
      _log('⚠️ _load failed — falling back to cache: $e');
      final cached = await _readCachedSchedule(employeeId, date);
      _pending
        ..clear()
        ..addAll(cached.where((c) => !c.isExpired));
      _scheduleLoadedFromCache = true;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CHECK (main loop)
  // ═══════════════════════════════════════════════════════════
  Future<void> _check(String employeeId) async {
    // 1) Missed threshold check
    await _checkMissedThreshold(employeeId);

    // 2) Out-of-range check
    await _checkOutOfRange(employeeId);

    if (_autoClockoutTriggeredToday) return;

    if (_pending.isEmpty) {
      // Kung offline at walang cache, subukan i-load ulit
      if (_isOnline) return;
      await _load(employeeId);
      if (_pending.isEmpty) return;
    }

    // Verify clock status
    try {
      final clockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(employeeId);
      if (!clockedIn) {
        _log('🚪 Not clocked-in — cancelling all pending');
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
      _log('⏰ EXPIRED: ${c.id}');

      // Kung offline, huwag i-mark missed — i-skip muna (fair)
      if (!_isOnline) {
        _log('📥 Offline — deferring missed marking for ${c.id}');
        // Huwag i-remove sa _pending — susubukan ulit pag online
        continue;
      }

      final isOutside = await _isEmployeeCurrentlyOutside(employeeId);

      if (isOutside) {
        _log('📍 Outside — cancelling (not missed)');
        await _cancelOutside(c);
      } else {
        await _markMissed(c);
      }
      _pending.remove(c);
    }

    for (final c in due) {
      _log('🎯 DUE: ${c.id} — geofence check...');

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
        zoneStatus = geo.status.toString();
      } catch (e) {
        _log('⚠️ Geofence failed: $e — assume inside');
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
  // AUTO-CLOCK-OUT: 3+ MISSED (offline-safe)
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkMissedThreshold(String employeeId) async {
    if (_autoClockoutTriggeredToday) return;

    try {
      int missedCount = _cachedMissedCount;

      if (_isOnline) {
        final date = _dateStr(DateTime.now());
        final snap = await _col
            .where('employeeId', isEqualTo: employeeId)
            .where('date', isEqualTo: date)
            .where('status', isEqualTo: 'missed')
            .get();
        missedCount = snap.docs.length;
        _cachedMissedCount = missedCount;
        await _cacheMissedCount(employeeId, missedCount);
      } else {
        _log('📥 [MissedThreshold] Using cached count: $missedCount');
      }

      if (missedCount < missedThresholdForAutoClockout) return;

      final clockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(employeeId);
      if (!clockedIn) return;

      _log('🚨 [AutoClockOut] $missedCount missed — TRIGGERING');

      await _forceAutoClockOut(
        employeeId: employeeId,
        reason: 'auto_clockout_${missedCount}_missed_challenges',
      );
    } catch (e) {
      _log('⚠️ _checkMissedThreshold error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // AUTO-CLOCK-OUT: 15+ MIN OUTSIDE (persisted)
  // ═══════════════════════════════════════════════════════════
  Future<void> _checkOutOfRange(String employeeId) async {
    if (_autoClockoutTriggeredToday) return;

    try {
      final clockedIn = await ClockStatusService.instance
          .isCurrentlyClockedIn(employeeId);
      if (!clockedIn) {
        if (_outOfRangeSince != null) {
          _outOfRangeSince = null;
          await _persistOutOfRange(null);
        }
        return;
      }

      final isOutside = await _isEmployeeCurrentlyOutside(employeeId);

      if (isOutside) {
        if (_outOfRangeSince == null) {
          _outOfRangeSince = DateTime.now();
          await _persistOutOfRange(_outOfRangeSince);
          _log('⚠️ [OutOfRange] Started timer at $_outOfRangeSince');
        }

        final duration = DateTime.now().difference(_outOfRangeSince!);
        _log('⚠️ [OutOfRange] ${duration.inMinutes}min '
            '(threshold: ${outOfRangeAutoClockoutThreshold.inMinutes}min)');

        if (duration >= outOfRangeAutoClockoutThreshold) {
          _log('🚨 [OutOfRange] Triggering auto-clock-out');
          await _forceAutoClockOut(
            employeeId: employeeId,
            reason: 'auto_clockout_outside_${duration.inMinutes}min',
          );
          _outOfRangeSince = null;
          await _persistOutOfRange(null);
        }
      } else {
        if (_outOfRangeSince != null) {
          _log('✅ [OutOfRange] Back in range — timer reset');
        }
        _outOfRangeSince = null;
        await _persistOutOfRange(null);
      }
    } catch (e) {
      _log('⚠️ _checkOutOfRange error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 🎯 FORCE AUTO-CLOCK-OUT (fixed: no duplicate write, offline-safe)
  // ═══════════════════════════════════════════════════════════
  Future<void> _forceAutoClockOut({
    required String employeeId,
    required String reason,
  }) async {
    if (_autoClockoutTriggeredToday) return;
    _autoClockoutTriggeredAt = DateTime.now();
    _autoClockoutTriggeredToday = true;

    final now = DateTime.now();
    final dateStr = _dateStr(now);
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final employeeName = _activeEmployeeName ?? employeeId;

    _log('🚨 [AutoClockOut] EXECUTING $employeeId — $reason');

    // 1) Cancel all pending (queued)
    try {
      await _cancelAll();
    } catch (e) {
      _log('⚠️ Cancel failed: $e');
    }

    // 2) 🎯 ATTENDANCE OUT — via offline queue (NO direct write!)
    //    Deterministic ID para hindi doble kahit i-retry
    final localId = '${employeeId}_AUTOOUT_${now.millisecondsSinceEpoch}';
    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'attendance_logs',
        docId: localId,
        data: {
          'employee_id': employeeId,
          'employee_name': employeeName,
          'employee_email': '',
          'type': 'OUT',
          'date': dateStr,
          'time': timeStr,
          'timestamp': FieldValue.serverTimestamp(),
          'device': 'AutoEnforcement',
          'remarks': reason,
          'zone_type': 'inside',
          'auto_clockout': true,
          'auto_clockout_reason': reason,
          'face_match_percent': 0,
          'match_score': 0,
          'localId': localId,
        },
      );
      _log('✅ [AutoClockOut] Attendance OUT queued (id=$localId)');
    } catch (e) {
      _log('❌ [AutoClockOut] Queue failed: $e');
    }

    // 3) 🎯 Admin notification — via queue
    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'admin_notifications',
        data: {
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
        },
      );
      _log('📢 [AutoClockOut] Admin notification queued');
    } catch (e) {
      _log('⚠️ Admin notif failed: $e');
    }

    // 4) 🎯 Security event — via queue
    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'security_events',
        data: {
          'type': 'auto_clockout_triggered',
          'severity': 'high',
          'details': 'Auto-clock-out for $employeeId: $reason',
          'employeeId': employeeId,
          'employeeName': employeeName,
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        },
      );
    } catch (_) {}

    // 5) Stop
    _log('🛑 [AutoClockOut] Stopping service');
    stop();
  }

  Future<void> _logChallengeFired(ChallengeDue due) async {
    if (!_isOnline) return;
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
  // MARK MISSED (offline-safe)
  // ═══════════════════════════════════════════════════════════
  Future<void> _markMissed(PresenceChallenge c) async {
    if (_notifiedMissed.contains(c.id)) return;
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

    // 🎯 Queue instead of direct write
    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'presence_challenges',
        docId: c.id,
        data: {
          'status': 'missed',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'auto_audit',
          if (zone != null) 'zoneAtExpiry': zone,
          if (distance != null) 'distanceAtExpiry': distance,
        },
      );
      _log('💾 MISSED queued: ${c.id} (zone=$zone)');
    } catch (e) {
      _log('⚠️ _markMissed failed: $e');
    }

    // Update local cache
    _cachedMissedCount++;
    if (_activeEmployeeId != null) {
      await _cacheMissedCount(_activeEmployeeId!, _cachedMissedCount);
    }

    unawaited(_notifyAdminMissed(c, zone: zone, distance: distance));
  }

  Future<void> _cancelOutside(PresenceChallenge c) async {
    if (_notifiedMissed.contains(c.id)) return;
    _notifiedMissed.add(c.id);

    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'presence_challenges',
        docId: c.id,
        data: {
          'status': 'cancelled',
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'outside_zone_at_expiry',
          'cancelReason': 'user_outside_at_expiry',
        },
      );
      _log('📍 CANCELLED (outside) queued: ${c.id}');
    } catch (e) {
      _log('⚠️ _cancelOutside failed: $e');
    }

    try {
      final name = await _resolveEmployeeName(c.employeeId);
      await OfflineAttendanceService.instance.enqueue(
        collection: 'admin_notifications',
        data: {
          'type': 'challenge_cancelled_outside',
          'title': '📍 Presence Check — Cancelled (Outside Zone)',
          'message':
          '$name was outside when the random check expired. '
              'Cancelled instead of missed.',
          'employeeId': c.employeeId,
          'employeeName': name,
          'priority': 'normal',
          'metadata': {
            'challengeId': c.id,
            'reason': 'user_outside_at_expiry',
          },
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        },
      );
    } catch (e) {
      _log('⚠️ notify cancelled failed: $e');
    }
  }

  Future<void> _cancelAll() async {
    if (_pending.isEmpty) return;

    for (final c in _pending) {
      try {
        await OfflineAttendanceService.instance.enqueue(
          collection: 'presence_challenges',
          docId: c.id,
          data: {
            'status': 'cancelled',
            'resolvedAt': FieldValue.serverTimestamp(),
            'resolvedBy': 'clock_out_detected',
          },
        );
      } catch (e) {
        _log('⚠️ _cancelAll enqueue failed: $e');
      }
    }
    _log('💾 Cancelled ${_pending.length} pending (queued)');
    _pending.clear();
    _prompted.clear();
  }

  // ═══════════════════════════════════════════════════════════
  // RESOLVE (offline-safe)
  // ═══════════════════════════════════════════════════════════
  Future<void> submitPassed(
      PresenceChallenge c, {
        required double faceScore,
        required String zone,
        double? distanceMeters,
        String? deviceBinding,
      }) async {
    _notifiedMissed.add(c.id);

    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'presence_challenges',
        docId: c.id,
        data: {
          'status': 'passed',
          'method': 'face',
          'faceScore': faceScore,
          'zone': zone,
          if (distanceMeters != null) 'distanceMeters': distanceMeters,
          if (deviceBinding != null) 'deviceBinding': deviceBinding,
          'respondedAt': FieldValue.serverTimestamp(),
        },
      );
      _log('✅ PASSED queued: ${c.id} (score=$faceScore, zone=$zone)');
    } catch (e) {
      _log('⚠️ submitPassed failed: $e');
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
    _notifiedMissed.add(c.id);

    try {
      await OfflineAttendanceService.instance.enqueue(
        collection: 'presence_challenges',
        docId: c.id,
        data: {
          'status': 'failed',
          'attempts': FieldValue.increment(1),
          'lastFaceScore': faceScore,
          'lastFailReason': reason,
          'lastAttemptAt': FieldValue.serverTimestamp(),
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': 'user_action',
        },
      );
      _log('❌ FAILED queued: ${c.id} ($reason)');
    } catch (e) {
      _log('⚠️ recordFailedAttempt failed: $e');
    }

    _pending.removeWhere((x) => x.id == c.id);

    unawaited(_notifyAdminFailed(
      c,
      faceScore: faceScore,
      reason: reason,
    ));
  }

  // ═══════════════════════════════════════════════════════════
  // ADMIN NOTIFICATIONS (offline-safe)
  // ═══════════════════════════════════════════════════════════
  Future<String> _resolveEmployeeName(String employeeId) async {
    if (_activeEmployeeName != null &&
        _activeEmployeeName!.isNotEmpty &&
        _activeEmployeeId == employeeId) {
      return _activeEmployeeName!;
    }

    if (!_isOnline) return employeeId;

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
      await OfflineAttendanceService.instance.enqueue(
        collection: 'admin_notifications',
        data: {
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
        },
      );
    } catch (e) {
      _log('⚠️ notify passed failed: $e');
    }
  }

  Future<void> _notifyAdminFailed(
      PresenceChallenge c, {
        required double faceScore,
        required String reason,
      }) async {
    try {
      final name = await _resolveEmployeeName(c.employeeId);
      await OfflineAttendanceService.instance.enqueue(
        collection: 'admin_notifications',
        data: {
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
        },
      );
    } catch (e) {
      _log('⚠️ notify failed failed: $e');
    }
  }

  Future<void> _notifyAdminMissed(
      PresenceChallenge c, {
        String? zone,
        double? distance,
      }) async {
    try {
      final name = await _resolveEmployeeName(c.employeeId);
      await OfflineAttendanceService.instance.enqueue(
        collection: 'admin_notifications',
        data: {
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
        },
      );
    } catch (e) {
      _log('⚠️ notify missed failed: $e');
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
    'autoClockoutTriggeredAt': _autoClockoutTriggeredAt?.toIso8601String(),
    'missedThreshold': missedThresholdForAutoClockout,
    'outOfRangeThresholdMin':
    outOfRangeAutoClockoutThreshold.inMinutes,
    'cachedMissedCount': _cachedMissedCount,
    'isOnline': _isOnline,
    'scheduleLoadedFromCache': _scheduleLoadedFromCache,
  };

  void printDebugInfo() {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('🎯 [PresenceChallengeService] DEBUG');
    debugPrint('═══════════════════════════════════════════');
    debugInfo().forEach((k, v) => debugPrint('   $k: $v'));
    debugPrint('═══════════════════════════════════════════');
  }
}