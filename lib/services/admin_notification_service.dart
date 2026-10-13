// lib/services/admin_notification_service.dart
// ═══════════════════════════════════════════════════════════════════
// ADMIN NOTIFICATION SERVICE  v2.3
// v2.0: markAsUnread, sanitization, dedup, rate limiting, batch chunking
// v2.1: notifyAutoClockOut
// v2.2: AUTH-AWARE — fixes "Session Expired" on read/clear operations
//       • _ensureAuthFresh()  — refresh ID token before writes
//       • _runWithAuthRetry() — retry on unauthenticated errors
//       • AdminSessionExpiredException for clear UI messaging
// v2.3: 🔐 SPLIT TOKEN vs PERMISSION ERRORS
//       • AdminPermissionDeniedException — no more false "Session Expired"
//       • Only true token errors trigger refresh + retry
//       • All comments/strings translated to English
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/admin_notification.dart';
import 'admin_notification_queue.dart';
import 'network_guard.dart';

/// 🔐 Thrown when the user's session has truly expired and cannot be refreshed.
/// The UI should prompt the user to sign in again.
class AdminSessionExpiredException implements Exception {
  final String message;
  AdminSessionExpiredException([this.message = 'Session expired']);
  @override
  String toString() => 'AdminSessionExpiredException: $message';
}

/// 🔐 Thrown when the user is still signed in but Firestore security rules
/// rejected the request. The UI must NOT show "Session Expired" for this.
class AdminPermissionDeniedException implements Exception {
  final String message;
  AdminPermissionDeniedException([this.message = 'Permission denied']);
  @override
  String toString() => 'AdminPermissionDeniedException: $message';
}

class AdminNotificationService {
  AdminNotificationService._();
  static final instance = AdminNotificationService._();

  final _col = FirebaseFirestore.instance.collection('admin_notifications');

  // ═══════════════════════════════════════════════════════════════
  // 🚦 RATE LIMIT + DEDUP CONFIG
  // ═══════════════════════════════════════════════════════════════
  static const Duration _geofenceCooldownDuration = Duration(minutes: 2);
  static const Duration _dedupWindow = Duration(seconds: 30);
  static const int _maxNotificationsPerMinute = 30;
  static const int _batchChunkSize = 500;
  static const Duration _writeTimeout = Duration(seconds: 8);

  /// 🔐 Minimum token age before we bother refreshing it.
  static const Duration _authMinAge = Duration(minutes: 5);

  /// 🔐 Retry delays for genuine token-expired errors.
  static const List<Duration> _authRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
    Duration(milliseconds: 2500),
  ];

  final Map<String, DateTime> _geofenceCooldown = {};
  final Map<String, DateTime> _dedupTracker = {};
  final List<DateTime> _notifyCallTimes = [];

  // ═══════════════════════════════════════════════════════════════
  // 🔐 AUTH HELPERS — the actual fix for "Session Expired"
  // ═══════════════════════════════════════════════════════════════

  /// Ensure the current Firebase ID token is fresh.
  /// Returns true if authenticated, false if the user is signed out.
  Future<bool> _ensureAuthFresh({bool force = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('🚨 [NotifService] No Firebase user — session gone');
      return false;
    }

    try {
      // Fast path: if the token was issued recently, skip the refresh.
      if (!force) {
        final tokenResult = await user.getIdTokenResult(false);
        final issuedAt = tokenResult.issuedAtTime; // ✅ nullable DateTime

        if (issuedAt != null &&
            DateTime.now().toUtc().difference(issuedAt.toUtc()) <
                _authMinAge) {
          return true; // still fresh
        }
      }

      // Force refresh — expired or about to expire.
      final fresh = await user.getIdToken(force);
      if (fresh == null || fresh.isEmpty) {
        debugPrint('🚨 [NotifService] ID token refresh returned empty');
        return false;
      }
      debugPrint('🔐 [NotifService] ID token refreshed');
      return true;
    } catch (e) {
      debugPrint('🚨 [NotifService] Token refresh failed: $e');
      return false;
    }
  }

  /// True only for genuine token/auth errors — NOT for permission-denied.
  bool _isTokenError(Object e) {
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code == 'unauthenticated' ||
          code == 'unauthorized' ||
          code == 'id-token-expired' ||
          code == 'user-token-expired' ||
          code == 'invalid-credential') {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('unauthenticated') ||
        s.contains('unauthorized') ||
        s.contains('id-token-expired') ||
        s.contains('user-token-expired') ||
        s.contains('token expired') ||
        s.contains('invalid-credential');
  }

  /// True for Firestore security-rule rejections — do NOT retry these.
  bool _isPermissionError(Object e) {
    if (e is FirebaseException) {
      return e.code.toLowerCase() == 'permission-denied';
    }
    return e.toString().toLowerCase().contains('permission-denied');
  }

  /// Run a Firestore operation with auth refresh + retry on token errors.
  Future<T> _runWithAuthRetry<T>({
    required String operationName,
    required Future<T> Function() action,
  }) async {
    // 1️⃣ Make sure the token is fresh before the first attempt.
    final ok = await _ensureAuthFresh();
    if (!ok) {
      throw AdminSessionExpiredException(
        'Not authenticated before $operationName',
      );
    }

    // 2️⃣ Try, with auth-aware retries (token errors only).
    Object? lastError;
    for (int attempt = 0;
    attempt <= _authRetryDelays.length;
    attempt++) {
      try {
        return await action().timeout(_writeTimeout);
      } catch (e) {
        lastError = e;

        // 🔐 Permission-denied is a rules issue, not a session issue.
        if (_isPermissionError(e)) {
          debugPrint(
              '🚫 [NotifService] Permission denied on $operationName: $e');
          throw AdminPermissionDeniedException(
            '$operationName rejected by security rules: $e',
          );
        }

        if (!_isTokenError(e)) {
          // Not an auth issue — bail out immediately.
          rethrow;
        }

        debugPrint('🔐 [NotifService] Token error on $operationName '
            '(attempt ${attempt + 1}/${_authRetryDelays.length + 1}): $e');

        if (attempt >= _authRetryDelays.length) {
          break; // no more retries
        }

        // Force-refresh the token, wait, then retry.
        final refreshed = await _ensureAuthFresh(force: true);
        if (!refreshed) {
          throw AdminSessionExpiredException(
            'Token refresh failed during $operationName',
          );
        }
        await Future.delayed(_authRetryDelays[attempt]);
      }
    }

    // All retries failed with token errors.
    throw AdminSessionExpiredException(
      '$operationName failed after retries: $lastError',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 SECURITY HELPERS
  // ═══════════════════════════════════════════════════════════════

  String _sanitize(String? input, {int maxLen = 300}) {
    if (input == null || input.isEmpty) return '';
    var s = input;
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s;
  }

  bool _isValidEmployeeId(String? id) {
    if (id == null || id.isEmpty) return false;
    if (id.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(id);
  }

  bool _checkNotifyRateLimit() {
    final now = DateTime.now();
    _notifyCallTimes.removeWhere(
            (t) => now.difference(t) > const Duration(minutes: 1));
    if (_notifyCallTimes.length >= _maxNotificationsPerMinute) {
      debugPrint('🚦 [Notify] Rate limit hit — '
          '${_notifyCallTimes.length}/$_maxNotificationsPerMinute per min');
      return false;
    }
    _notifyCallTimes.add(now);
    return true;
  }

  String _dedupHash({
    required String type,
    required String title,
    required String? employeeId,
  }) {
    return '$type|$title|${employeeId ?? "global"}';
  }

  bool _isDuplicate({
    required String type,
    required String title,
    required String? employeeId,
  }) {
    final key = _dedupHash(
      type: type,
      title: title,
      employeeId: employeeId,
    );
    final now = DateTime.now();
    final last = _dedupTracker[key];
    if (last != null && now.difference(last) < _dedupWindow) {
      debugPrint('🔁 [Notify] Duplicate within ${_dedupWindow.inSeconds}s '
          '— skipping: $title');
      return true;
    }
    _dedupTracker[key] = now;
    _dedupTracker.removeWhere(
            (_, v) => now.difference(v) > const Duration(minutes: 5));
    return false;
  }

  // ═══════════════════════════════════════════════════════════════
  // STREAMS
  // ═══════════════════════════════════════════════════════════════
  Stream<List<AdminNotification>> streamAll({int limit = 50}) {
    return _col
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  Stream<List<AdminNotification>> streamByType({
    required List<String> types,
    int limit = 50,
  }) {
    if (types.isEmpty) return streamAll(limit: limit);
    return _col
        .where('type', whereIn: types)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  Stream<List<AdminNotification>> streamByPriority({
    required String priority,
    int limit = 50,
  }) {
    return _col
        .where('priority', isEqualTo: priority)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList());
  }

  Stream<int> streamUnreadCount() {
    return _col
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS — all go through auth-aware retry
  // ═══════════════════════════════════════════════════════════════

  /// ✓ Mark a notification as READ.
  Future<void> markAsRead(String id) async {
    if (id.isEmpty) return;
    try {
      await _runWithAuthRetry(
        operationName: 'markAsRead($id)',
        action: () => _col.doc(id).update({
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        }),
      );
      debugPrint('✅ [NotifService] Marked read: $id');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow; // let the UI handle re-login
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow; // let the UI show the correct message
    } catch (e) {
      debugPrint('⚠️ [NotifService] markAsRead error: $e');
    }
  }

  /// 🔄 Mark a notification as UNREAD.
  Future<void> markAsUnread(String id) async {
    if (id.isEmpty) return;
    try {
      await _runWithAuthRetry(
        operationName: 'markAsUnread($id)',
        action: () => _col.doc(id).update({
          'read': false,
          'readAt': null,
        }),
      );
      debugPrint('✅ [NotifService] Marked UNREAD: $id');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] markAsUnread error: $e');
    }
  }

  /// 🔥 Mark multiple notifications as read.
  Future<void> markMultipleAsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _runWithAuthRetry(
        operationName: 'markMultipleAsRead(${ids.length})',
        action: () async {
          final batch = FirebaseFirestore.instance.batch();
          for (final id in ids) {
            if (id.isEmpty) continue;
            batch.update(_col.doc(id), {
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        },
      );
      debugPrint('✅ [NotifService] Marked ${ids.length} as read');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] markMultipleAsRead error: $e');
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _runWithAuthRetry(
        operationName: 'markAllAsRead',
        action: () async {
          final batch = FirebaseFirestore.instance.batch();
          final snap = await _col
              .where('read', isEqualTo: false)
              .limit(_batchChunkSize)
              .get();
          if (snap.docs.isEmpty) {
            debugPrint('✅ [NotifService] No unread notifications');
            return;
          }
          for (final d in snap.docs) {
            batch.update(d.reference, {
              'read': true,
              'readAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
          debugPrint(
              '✅ [NotifService] Marked all as read (${snap.docs.length})');
        },
      );
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] markAllAsRead error: $e');
    }
  }

  Future<void> deleteNotification(String id) async {
    if (id.isEmpty) return;
    try {
      await _runWithAuthRetry(
        operationName: 'deleteNotification($id)',
        action: () => _col.doc(id).delete(),
      );
      debugPrint('🗑️ [NotifService] Deleted: $id');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] deleteNotification error: $e');
    }
  }

  /// 🔥 Delete multiple notifications.
  Future<void> deleteMultiple(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await _runWithAuthRetry(
        operationName: 'deleteMultiple(${ids.length})',
        action: () async {
          final batch = FirebaseFirestore.instance.batch();
          for (final id in ids) {
            if (id.isEmpty) continue;
            batch.delete(_col.doc(id));
          }
          await batch.commit();
        },
      );
      debugPrint('🗑️ [NotifService] Deleted ${ids.length} notifications');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] deleteMultiple error: $e');
    }
  }

  /// 🗑️ Clear ALL notifications — with auth-aware chunking.
  Future<void> clearAll() async {
    try {
      int totalDeleted = 0;

      // 🔐 Refresh auth ONCE before looping.
      final ok = await _ensureAuthFresh();
      if (!ok) {
        throw AdminSessionExpiredException(
          'Not authenticated before clearAll',
        );
      }

      while (true) {
        final snap = await _col.limit(_batchChunkSize).get();
        if (snap.docs.isEmpty) break;

        // 🔐 Wrap each batch commit in auth-retry.
        await _runWithAuthRetry(
          operationName: 'clearAll.batch(${snap.docs.length})',
          action: () async {
            final batch = FirebaseFirestore.instance.batch();
            for (final d in snap.docs) {
              batch.delete(d.reference);
            }
            await batch.commit();
          },
        );

        totalDeleted += snap.docs.length;
        if (snap.docs.length < _batchChunkSize) break;
      }

      debugPrint('🗑️ [NotifService] Cleared $totalDeleted notifications');
    } on AdminSessionExpiredException catch (e) {
      debugPrint('🚨 [NotifService] $e');
      rethrow;
    } on AdminPermissionDeniedException catch (e) {
      debugPrint('🚫 [NotifService] $e');
      rethrow;
    } catch (e) {
      debugPrint('⚠️ [NotifService] clearAll error: $e');
    }
  }

  /// One-shot unread count.
  Future<int> getUnreadCount() async {
    try {
      // 🔐 Ensure auth first.
      final ok = await _ensureAuthFresh();
      if (!ok) return 0;

      final snap = await _col.where('read', isEqualTo: false).count().get();
      return snap.count ?? 0;
    } catch (e) {
      debugPrint('⚠️ [NotifService] getUnreadCount error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 BASE NOTIFY
  // ═══════════════════════════════════════════════════════════════
  Future<void> notify({
    required String type,
    required String title,
    required String message,
    String? employeeId,
    String? employeeName,
    String priority = 'normal',
    Map<String, dynamic> metadata = const {},
    bool allowDuplicate = false,
  }) async {
    if (!_checkNotifyRateLimit()) return;

    final safeType = _sanitize(type, maxLen: 50);
    final safeTitle = _sanitize(title, maxLen: 200);
    final safeMessage = _sanitize(message, maxLen: 500);
    final safeEmpName = _sanitize(employeeName, maxLen: 100);

    if (safeTitle.isEmpty || safeType.isEmpty) {
      debugPrint('⚠️ [Notify] Rejected: empty type or title');
      return;
    }

    if (employeeId != null &&
        employeeId.isNotEmpty &&
        !_isValidEmployeeId(employeeId)) {
      debugPrint('🚨 [Notify] Invalid employee ID: $employeeId');
      return;
    }

    if (!allowDuplicate &&
        _isDuplicate(
          type: safeType,
          title: safeTitle,
          employeeId: employeeId,
        )) {
      return;
    }

    final payload = <String, dynamic>{
      'type': safeType,
      'title': safeTitle,
      'message': safeMessage,
      'employeeId': employeeId,
      'employeeName': safeEmpName.isEmpty ? null : safeEmpName,
      'priority': priority,
      'read': false,
      'metadata': metadata,
    };

    // Direct write when online.
    if (NetworkGuard.instance.isOnline) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          // 🔐 Refresh token before writing.
          final ok = await _ensureAuthFresh();
          if (!ok) {
            debugPrint('🚨 [Notify] Not authenticated — queueing');
            break;
          }

          await _col.add({
            ...payload,
            'timestamp': FieldValue.serverTimestamp(),
          }).timeout(_writeTimeout);
          debugPrint('✅ [Notify] $safeType — $safeTitle (direct)');
          return;
        } catch (e) {
          debugPrint('⚠️ [Notify] Attempt ${attempt + 1} failed: $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
      debugPrint('⚠️ [Notify] Direct write failed twice — queueing');
    }

    // Offline or failed — enqueue.
    await AdminNotificationQueue.instance.enqueue(payload);
    debugPrint('📥 [Notify] $safeType — queued for sync');
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CLOCK IN
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
    bool inRange = true,
    double? faceMatchPercent,
    double? distanceMeters,
    String? zoneType,
  }) {
    final zone =
        zoneType ?? (wfh ? 'wfh' : (inRange ? 'inside' : 'outside'));
    final badge = _zoneEmoji(zone);

    final title = wfh
        ? '$badge $employeeName clocked in (WFH)'
        : (inRange
        ? '$badge $employeeName clocked in'
        : '$badge $employeeName clocked in (Outside)');

    final message = [
      timeStr,
      _zoneLabel(zone),
      if (distanceMeters != null)
        '${distanceMeters.toStringAsFixed(0)}m from office',
      if (faceMatchPercent != null)
        'Face ${faceMatchPercent.toStringAsFixed(0)}%',
    ].join(' · ');

    return notify(
      type: zone == 'outside' ? 'geofence_alert' : 'clock_in',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: zone == 'outside' ? 'high' : 'normal',
      metadata: {
        'zone': zone,
        'time': timeStr,
        'wfh': wfh,
        'in_range': inRange,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ CLOCK OUT
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    bool wfh = false,
    bool inRange = true,
    double? faceMatchPercent,
    double? distanceMeters,
    String? zoneType,
  }) {
    final zone =
        zoneType ?? (wfh ? 'wfh' : (inRange ? 'inside' : 'outside'));
    final badge = _zoneEmoji(zone);

    final title = '$badge $employeeName clocked out';

    final message = [
      timeStr,
      _zoneLabel(zone),
      if (distanceMeters != null)
        '${distanceMeters.toStringAsFixed(0)}m',
    ].join(' · ');

    return notify(
      type: 'clock_out',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'normal',
      metadata: {
        'zone': zone,
        'time': timeStr,
        'wfh': wfh,
        'in_range': inRange,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ WFH
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyWFHClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    double? faceMatchPercent,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: '🏠 $employeeName — WFH Clock In',
      message: '$timeStr · Work-from-home'
          '${faceMatchPercent != null ? " · Face ${faceMatchPercent.toStringAsFixed(0)}%" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'normal',
      metadata: {
        'zone': 'wfh',
        'time': timeStr,
        'wfh': true,
        'in_range': false,
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
      },
    );
  }

  Future<void> notifyWFHClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: '🏠 $employeeName — WFH Clock Out',
      message: '$timeStr · Work-from-home ended',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'wfh',
        'time': timeStr,
        'wfh': true,
        'in_range': false,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ DRIVER
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyDriverClockIn({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    double? faceMatchPercent,
  }) {
    return notify(
      type: 'clock_in',
      title: '🚗 $employeeName (Driver) clocked in',
      message: '$timeStr · Field duty — geofence exempt'
          '${faceMatchPercent != null ? " · Face ${faceMatchPercent.toStringAsFixed(0)}%" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'driver',
        'time': timeStr,
        'wfh': false,
        'in_range': false,
        'role': 'driver',
        if (faceMatchPercent != null) 'face_percent': faceMatchPercent,
      },
    );
  }

  Future<void> notifyDriverClockOut({
    required String employeeId,
    required String employeeName,
    required String timeStr,
  }) {
    return notify(
      type: 'clock_out',
      title: '🚗 $employeeName (Driver) clocked out',
      message: '$timeStr · Field duty ended',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'zone': 'driver',
        'time': timeStr,
        'wfh': false,
        'in_range': false,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ GEOFENCE ALERT
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyGeofenceAlert({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    required double distanceMeters,
    String action = 'clock_in',
  }) {
    return notify(
      type: 'geofence_alert',
      title: '⚠️ Geofence Alert — $employeeName',
      message: 'Attempted $action outside zone · '
          '${distanceMeters.toStringAsFixed(0)}m from office at $timeStr',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'high',
      metadata: {
        'zone': 'outside',
        'time': timeStr,
        'distance_meters': distanceMeters,
        'action': action,
      },
    );
  }

  Future<void> notifyGeofenceAlertThrottled({
    required String employeeId,
    required String employeeName,
    required String timeStr,
    required double distanceMeters,
    String action = 'clock_in',
  }) async {
    final now = DateTime.now();
    final last = _geofenceCooldown[employeeId];

    if (last != null &&
        now.difference(last) < _geofenceCooldownDuration) {
      final remain = _geofenceCooldownDuration - now.difference(last);
      debugPrint('⏱️ [GeofenceAlert] Throttled for $employeeName — '
          '${remain.inSeconds}s remaining');
      return;
    }

    _geofenceCooldown[employeeId] = now;
    debugPrint('🚨 [GeofenceAlert] FIRING for $employeeName '
        '(distance=${distanceMeters.toStringAsFixed(0)}m)');

    return notifyGeofenceAlert(
      employeeId: employeeId,
      employeeName: employeeName,
      timeStr: timeStr,
      distanceMeters: distanceMeters,
      action: action,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ FACE ENROLLMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyFaceEnrollment({
    required String employeeId,
    required String employeeName,
    required int enrolledAngles,
  }) {
    return notify(
      type: 'face_enrollment',
      title: '📸 $employeeName — Face enrolled',
      message: '$enrolledAngles angle(s) captured · Biometric active',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'enrolled_angles': enrolledAngles,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ LEAVE REQUEST
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyLeaveRequest({
    required String employeeId,
    required String employeeName,
    required String leaveType,
    required String dateRange,
    String? reason,
  }) {
    return notify(
      type: 'leave_request',
      title: '📋 $employeeName — Leave Request',
      message: '$leaveType · $dateRange'
          '${reason != null && reason.isNotEmpty ? " · $reason" : ""}',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: 'high',
      metadata: {
        'leave_type': leaveType,
        'date_range': dateRange,
        if (reason != null) 'reason': reason,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔐 PASSWORD CHANGE REQUEST
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyPasswordChangeRequest({
    required String employeeId,
    required String employeeName,
    String? email,
    String? reason,
    String priority = 'high',
  }) {
    final parts = <String>[
      if (email != null && email.isNotEmpty) email,
      if (reason != null && reason.isNotEmpty) reason,
    ];

    return notify(
      type: 'password_change',
      title: '🔐 $employeeName — Password Change Request',
      message: parts.isEmpty
          ? 'Requested a password reset. Admin approval required.'
          : parts.join(' · '),
      employeeId: employeeId,
      employeeName: employeeName,
      priority: priority,
      metadata: {
        'request_type': 'password_change',
        'zone': 'wfh',
        if (email != null) 'email': email,
        if (reason != null) 'reason': reason,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ WFH TOGGLE
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyWfhToggle({
    required String employeeId,
    required String employeeName,
    required bool enabled,
  }) {
    return notify(
      type: 'wfh_toggle',
      title: enabled
          ? '🏠 WFH enabled for $employeeName'
          : '🏢 WFH disabled for $employeeName',
      message: enabled
          ? 'Employee can now clock in from anywhere.'
          : 'Employee must be within the office zone.',
      employeeId: employeeId,
      employeeName: employeeName,
      metadata: {
        'enabled': enabled,
        'zone': enabled ? 'wfh' : 'inside',
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🛰️ PRESENCE UPDATE
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyPresenceUpdate({
    required String employeeId,
    required String employeeName,
    required String zone,
    required double distanceMeters,
    required bool changed,
    String? previousZone,
    String priority = 'normal',
    String notifyReason = 'heartbeat',
  }) {
    final isInside = zone == 'inside';
    final emoji = isInside ? '🟢' : '🔴';
    final statusText = isInside ? 'IN RANGE' : 'OUT OF RANGE';

    String title;
    String message;

    if (changed && previousZone != null && previousZone.isNotEmpty) {
      final fromText =
      previousZone == 'inside' ? 'IN RANGE' : 'OUT OF RANGE';
      title = '$emoji Status Change — $employeeName';
      message = 'Moved from $fromText → $statusText · '
          '${distanceMeters.toStringAsFixed(0)}m from office';
    } else {
      title = '$emoji $employeeName — $statusText';
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      message = '${distanceMeters.toStringAsFixed(0)}m from office · '
          'Checked at $hh:$mm';
    }

    return notify(
      type: 'presence_update',
      title: title,
      message: message,
      employeeId: employeeId,
      employeeName: employeeName,
      priority: priority,
      metadata: {
        'zone': zone,
        'in_range': isInside,
        'distance_meters': distanceMeters,
        'changed': changed,
        'notify_reason': notifyReason,
        if (previousZone != null) 'previous_zone': previousZone,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔥 AUTO CLOCK-OUT
  // ═══════════════════════════════════════════════════════════════
  Future<void> notifyAutoClockOut({
    required String employeeId,
    required String employeeName,
    required String trigger,
    required String timeStr,
    required String dateStr,
    double? distanceMeters,
  }) {
    final triggerLabel = {
      'geofence_exit': 'Left work zone',
      'shift_end': 'Shift ended (5:00 PM)',
      'no_heartbeat': 'No heartbeat for 30+ mins',
      'manual': 'Manual admin trigger',
    }[trigger] ??
        trigger;

    final triggerEmoji = {
      'geofence_exit': '🚶',
      'shift_end': '⏰',
      'no_heartbeat': '💤',
      'manual': '🛠️',
    }[trigger] ??
        '⏰';

    final distancePart = distanceMeters != null
        ? ' · ${distanceMeters.toStringAsFixed(0)}m from office'
        : '';

    return notify(
      type: 'auto_clock_out',
      title: '$triggerEmoji Auto Clock-Out — $employeeName',
      message: '$triggerLabel · $timeStr$distancePart',
      employeeId: employeeId,
      employeeName: employeeName,
      priority: trigger == 'geofence_exit' ? 'high' : 'normal',
      metadata: {
        'trigger': trigger,
        'trigger_label': triggerLabel,
        'time': timeStr,
        'date': dateStr,
        if (distanceMeters != null) 'distance_meters': distanceMeters,
        'alert_type': 'auto_clock_out_performed',
      },
      allowDuplicate: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _zoneEmoji(String zone) {
    switch (zone) {
      case 'inside':
        return '📍';
      case 'wfh':
        return '🏠';
      case 'driver':
        return '🚗';
      case 'outside':
        return '⚠️';
      default:
        return '✅';
    }
  }

  String _zoneLabel(String zone) {
    switch (zone) {
      case 'inside':
        return 'GPS verified';
      case 'wfh':
        return 'Work-from-home';
      case 'driver':
        return 'Field duty';
      case 'outside':
        return 'Outside zone';
      default:
        return 'On-site';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBUG HELPERS
  // ═══════════════════════════════════════════════════════════════

  void clearThrottle() {
    _geofenceCooldown.clear();
    debugPrint('🧹 [GeofenceAlert] Throttle cleared');
  }

  void clearThrottleFor(String employeeId) {
    _geofenceCooldown.remove(employeeId);
    debugPrint('🧹 [GeofenceAlert] Throttle cleared for $employeeId');
  }

  void clearAllTrackers() {
    _geofenceCooldown.clear();
    _dedupTracker.clear();
    _notifyCallTimes.clear();
    debugPrint('🧹 [NotifService] All trackers cleared');
  }

  Map<String, int> debugTrackerStats() {
    return {
      'geofenceCooldown': _geofenceCooldown.length,
      'dedupTracker': _dedupTracker.length,
      'notifyCallTimesLastMin': _notifyCallTimes.length,
    };
  }
}