// lib/services/admin_audit_service.dart
// ═══════════════════════════════════════════════════════════════════
// SECURED ADMIN AUDIT SERVICE  v2.0
// Hardened: input validation, action allowlist, metadata
//           sanitization, size limits, retry queue, rate limiting,
//           tamper-proof actor, backwards-compatible API.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class AdminAuditService {
  AdminAuditService._();
  static final instance = AdminAuditService._();

  // ─── CONFIG ─────────────────────────────────────────────────
  static const String _collection = 'admin_audit_logs';
  static const int _maxActionLen = 64;
  static const int _maxTargetIdLen = 256;
  static const int _maxTargetTypeLen = 32;
  static const int _maxMetadataKeys = 30;
  static const int _maxMetadataStringLen = 500;
  static const int _maxRetryQueue = 50;
  static const int _maxRatePerAction = 10; // per minute
  static const Duration _rateWindow = Duration(minutes: 1);

  /// Allowlist ng valid action names.
  /// Idagdag dito ang bagong action — huwag hayaang freeform.
  static const Set<String> _allowedActions = <String>{
    // Leave management
    'approve_leave',
    'reject_leave',
    // Client meetings
    'approve_client_meeting',
    'reject_client_meeting',
    // Geofence / locations
    'add_location',
    'edit_location',
    'delete_location',
    'enable_location',
    'disable_location',
    'update_geofence_config',
    'broadcast_holiday_announcement',
    // Payroll
    'export_payroll_csv',
    'print_payslip',
    'download_payslip',
    'notify_payslip',
    // Generic
    'admin_sign_in',
    'admin_sign_out',
    'update_settings',
  };

  // ─── INTERNAL STATE ─────────────────────────────────────────
  final Map<String, List<DateTime>> _rateBuckets = {};
  final List<Map<String, dynamic>> _retryQueue = [];
  bool _flushing = false;

  // ══════════════════════════════════════════════════════════════
  // PUBLIC API (backwards compatible)
  // ══════════════════════════════════════════════════════════════

  /// Logs an admin action.
  ///
  /// [action] MUST be in [_allowedActions] — else rejected.
  /// [adminUid] parameter is kept for API compatibility only — NOT trusted.
  /// The real actor is always resolved from `FirebaseAuth.instance.currentUser`.
  Future<void> log({
    required String action,
    required String targetId,
    required String targetType,
    String? adminUid, // ⚠️ ignored for security — kept for compat
    Map<String, dynamic>? metadata,
  }) async {
    if (adminUid != null && kDebugMode) {
      debugPrint(
          '⚠️ [Audit] adminUid parameter is ignored (security). '
              'Actor is always derived from FirebaseAuth.');
    }

    // ─── 1. Validate action ───
    final cleanAction = _sanitizeAction(action);
    if (cleanAction == null) {
      _debug('🚫 [Audit] Invalid action rejected: "$action"');
      return;
    }

    // ─── 2. Validate target ───
    final cleanTargetId = _sanitizeString(targetId, maxLen: _maxTargetIdLen);
    final cleanTargetType =
    _sanitizeString(targetType, maxLen: _maxTargetTypeLen);
    if (cleanTargetId.isEmpty || cleanTargetType.isEmpty) {
      _debug('🚫 [Audit] Empty target for action=$cleanAction');
      return;
    }

    // ─── 3. Resolve REAL actor (never trust parameters) ───
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _debug('🚫 [Audit] No authenticated user — skipping log');
      return;
    }

    // ─── 4. Rate limit per action ───
    if (!_rateLimitOk(cleanAction)) {
      _debug('🚫 [Audit] Rate limit hit: $cleanAction');
      return;
    }

    // ─── 5. Sanitize metadata (recursive, size-limited) ───
    final safeMeta = _sanitizeMetadata(metadata);

    // ─── 6. Build payload ───
    final payload = <String, dynamic>{
      'action': cleanAction,
      'targetId': cleanTargetId,
      'targetType': cleanTargetType,
      'adminUid': user.uid,
      'adminEmail': _sanitizeString(user.email ?? '', maxLen: 200),
      'metadata': safeMeta,
      'userAgent': 'flutter_admin_app',
      'schemaVersion': 2,
      'clientTimeUtc': DateTime.now().toUtc().toIso8601String(),
      // createdAt = server-trusted timestamp (para sa integrity)
      'createdAt': FieldValue.serverTimestamp(),
    };

    // ─── 7. Try write; queue on failure ───
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .add(payload);

      // Opportunistic flush ng old failures
      unawaited(_flushRetryQueue());
    } catch (e) {
      _debug('❌ [Audit] Write failed: $e');
      _enqueue(payload);
    }
  }

  /// 🆕 Bulk log — isang batch write para sa maraming actions.
  /// Makatipid ng Firestore writes at mas mabilis.
  Future<void> logBatch(List<AuditEntry> entries) async {
    if (entries.isEmpty) return;
    if (entries.length > 50) {
      _debug('🚫 [Audit] Batch too large: ${entries.length} (max 50)');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _debug('🚫 [Audit] No auth user — batch skipped');
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection(_collection);
      final now = FieldValue.serverTimestamp();

      for (final e in entries) {
        final cleanAction = _sanitizeAction(e.action);
        if (cleanAction == null) continue;
        if (!_rateLimitOk(cleanAction)) continue;

        batch.set(col.doc(), {
          'action': cleanAction,
          'targetId':
          _sanitizeString(e.targetId, maxLen: _maxTargetIdLen),
          'targetType':
          _sanitizeString(e.targetType, maxLen: _maxTargetTypeLen),
          'adminUid': user.uid,
          'adminEmail': _sanitizeString(user.email ?? '', maxLen: 200),
          'metadata': _sanitizeMetadata(e.metadata),
          'userAgent': 'flutter_admin_app',
          'schemaVersion': 2,
          'clientTimeUtc': DateTime.now().toUtc().toIso8601String(),
          'createdAt': now,
        });
      }

      await batch.commit();
    } catch (e) {
      _debug('❌ [Audit] Batch write failed: $e');
    }
  }

  /// 🆕 Convenience: log admin sign-in.
  Future<void> logSignIn({String? adminUid}) => log(
    action: 'admin_sign_in',
    targetId: adminUid ?? FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
    targetType: 'session',
  );

  /// 🆕 Convenience: log admin sign-out.
  Future<void> logSignOut({String? adminUid}) => log(
    action: 'admin_sign_out',
    targetId: adminUid ?? 'unknown',
    targetType: 'session',
  );

  /// 🆕 Force-flush ng retry queue (manual trigger).
  Future<void> flushQueue() => _flushRetryQueue();

  /// 🆕 Debug info tungkol sa queue (para sa admin diagnostics).
  int get pendingRetries => _retryQueue.length;

  // ══════════════════════════════════════════════════════════════
  // INTERNAL — SANITIZATION
  // ══════════════════════════════════════════════════════════════

  String? _sanitizeAction(String action) {
    final s = _sanitizeString(action, maxLen: _maxActionLen).toLowerCase();
    if (s.isEmpty) return null;
    if (!_allowedActions.contains(s)) return null;
    return s;
  }

  static String _sanitizeString(dynamic raw, {int maxLen = 200}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = s.substring(0, maxLen);
    return s.trim();
  }

  /// Recursive metadata sanitization:
  ///  - Strips control chars
  ///  - Caps string lengths
  ///  - Drops unsupported types (functions, symbols, cycles)
  ///  - Depth-limited (max 3 levels)
  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return {};
    if (meta.length > _maxMetadataKeys) {
      _debug('⚠️ [Audit] Metadata truncated: ${meta.length} keys');
    }

    final out = <String, dynamic>{};
    int count = 0;
    for (final entry in meta.entries) {
      if (count++ >= _maxMetadataKeys) break;
      final key = _sanitizeString(entry.key, maxLen: 64);
      if (key.isEmpty) continue;
      final safe = _sanitizeValue(entry.value, depth: 0);
      if (safe != null) out[key] = safe;
    }
    return out;
  }

  dynamic _sanitizeValue(dynamic value, {required int depth}) {
    if (depth > 3) return null; // avoid deep nesting / cycles
    if (value == null) return null;

    if (value is String) {
      return _sanitizeString(value, maxLen: _maxMetadataStringLen);
    }
    if (value is num || value is bool) return value;

    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();

    if (value is List) {
      if (value.length > 20) {
        return value.take(20).map((e) => _sanitizeValue(e, depth: depth + 1))
            .where((e) => e != null).toList();
      }
      return value
          .map((e) => _sanitizeValue(e, depth: depth + 1))
          .where((e) => e != null)
          .toList();
    }

    if (value is Map) {
      final out = <String, dynamic>{};
      int count = 0;
      for (final e in value.entries) {
        if (count++ >= 10) break;
        final k = _sanitizeString(e.key, maxLen: 64);
        if (k.isEmpty) continue;
        final v = _sanitizeValue(e.value, depth: depth + 1);
        if (v != null) out[k] = v;
      }
      return out;
    }

    // Unsupported type — drop
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // INTERNAL — RATE LIMIT
  // ══════════════════════════════════════════════════════════════

  bool _rateLimitOk(String action) {
    final now = DateTime.now();
    final bucket = _rateBuckets.putIfAbsent(action, () => []);
    bucket.removeWhere((t) => now.difference(t) > _rateWindow);
    if (bucket.length >= _maxRatePerAction) return false;
    bucket.add(now);
    return true;
  }

  // ══════════════════════════════════════════════════════════════
  // INTERNAL — RETRY QUEUE
  // ══════════════════════════════════════════════════════════════

  void _enqueue(Map<String, dynamic> payload) {
    if (_retryQueue.length >= _maxRetryQueue) {
      // Drop oldest — audit overflow policy
      _retryQueue.removeAt(0);
      _debug('⚠️ [Audit] Queue full — oldest entry dropped');
    }
    _retryQueue.add(payload);
  }

  Future<void> _flushRetryQueue() async {
    if (_flushing) return;
    if (_retryQueue.isEmpty) return;
    _flushing = true;

    final pending = List<Map<String, dynamic>>.from(_retryQueue);
    _retryQueue.clear();

    for (final payload in pending) {
      try {
        await FirebaseFirestore.instance
            .collection(_collection)
            .add(payload);
      } catch (e) {
        // Re-queue at the end (preserve order)
        _retryQueue.add(payload);
        _debug('⚠️ [Audit] Retry failed, re-queued: $e');
        // Stop trying further if we hit an error
        break;
      }
    }
    _flushing = false;
  }

  // ══════════════════════════════════════════════════════════════
  // INTERNAL — LOGGING
  // ══════════════════════════════════════════════════════════════

  void _debug(String msg) {
    if (kDebugMode) debugPrint(msg);
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🆕 SUPPORTING TYPES
// ═══════════════════════════════════════════════════════════════════
class AuditEntry {
  final String action;
  final String targetId;
  final String targetType;
  final Map<String, dynamic>? metadata;

  const AuditEntry({
    required this.action,
    required this.targetId,
    required this.targetType,
    this.metadata,
  });
}