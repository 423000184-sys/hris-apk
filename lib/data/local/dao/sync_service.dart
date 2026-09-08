// lib/data/local/dao/sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../../services/database_service.dart';
import 'connectivity_service.dart';

enum SyncStatus { pending, syncing, synced, failed }
enum SyncType { clockIn, clockOut }

class SyncRecord {
  final String id;
  final SyncType type;
  final Map<String, dynamic> payload;
  final SyncStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttempt;
  final String? errorMessage;

  SyncRecord({
    required this.id,
    required this.type,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.lastAttempt,
    this.errorMessage,
  });

  factory SyncRecord.fromMap(Map<String, dynamic> m) => SyncRecord(
    id: m['id'],
    type: SyncType.values.firstWhere((t) => t.name == m['type'],
        orElse: () => SyncType.clockIn),
    payload: jsonDecode(m['payload'] as String),
    status: SyncStatus.values.firstWhere((s) => s.name == m['status'],
        orElse: () => SyncStatus.pending),
    retryCount: (m['retry_count'] as int?) ?? 0,
    createdAt: DateTime.parse(m['created_at'] as String),
    lastAttempt: m['last_attempt'] != null
        ? DateTime.parse(m['last_attempt'] as String)
        : null,
    errorMessage: m['error_message'] as String?,
  );
}

class SyncEvent {
  final SyncEventType type;
  final int pendingCount;
  final int syncedCount;
  final String? message;

  SyncEvent({
    required this.type,
    this.pendingCount = 0,
    this.syncedCount = 0,
    this.message,
  });
}

enum SyncEventType {
  wentOffline,
  wentOnline,
  syncing,
  syncDone,
  syncFailed,
  queued
}

class SyncService {
  static SyncService? _instance;
  SyncService._();
  static SyncService get instance => _instance ??= SyncService._();

  final _uuid = const Uuid();
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // IMPORTANT: Replace 'localhost' with your machine's IP address if testing on a real device
  final String _mysqlSyncUrl = "http://localhost/hris_biometrics/admin_web_portal/sync_attendance.php";

  final _eventController = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _eventController.stream;

  Future<void> init() async {
    if (kIsWeb) return;
    await _ensureTable();
    await _resetStuckRecords();
    _connectivitySub =
        ConnectivityService.instance.onStatusChange.listen((online) async {
          if (online) {
            _eventController.add(SyncEvent(
                type: SyncEventType.wentOnline,
                message: 'Back online — syncing records...'));
            await syncPending();
          } else {
            final pending = await getPendingCount();
            _eventController.add(SyncEvent(
                type: SyncEventType.wentOffline,
                pendingCount: pending,
                message: 'Offline mode active'));
          }
        });
    if (ConnectivityService.instance.isOnline) {
      await syncPending();
    }
  }

  Future<void> _ensureTable() async {
    final db = await DatabaseService.instance.database;
    if (db == null) return;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        last_attempt TEXT,
        error_message TEXT
      )
    ''');
  }

  Future<void> _resetStuckRecords() async {
    final db = await DatabaseService.instance.database;
    if (db == null) return;
    await db.update(
      'sync_queue',
      {'status': SyncStatus.pending.name},
      where: "status = 'syncing'",
    );
  }

  void dispose() {
    _connectivitySub?.cancel();
    _eventController.close();
  }

  Future<String?> enqueue(SyncType type, Map<String, dynamic> payload) async {
    if (kIsWeb) return null;
    final db = await DatabaseService.instance.database;
    if (db == null) return null;
    final id = _uuid.v4();
    await db.insert('sync_queue', {
      'id': id,
      'type': type.name,
      'payload': jsonEncode(payload),
      'status': SyncStatus.pending.name,
      'retry_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    final pending = await getPendingCount();
    _eventController.add(SyncEvent(
      type: SyncEventType.queued,
      pendingCount: pending,
    ));

    if (ConnectivityService.instance.isOnline) {
      await syncPending();
    }

    return id;
  }

  Future<void> syncPending() async {
    if (kIsWeb) return;
    if (_isSyncing) return;
    if (!ConnectivityService.instance.isOnline) return;

    final db = await DatabaseService.instance.database;
    if (db == null) return;
    final rows = await db.query(
      'sync_queue',
      where: "status = 'pending'",
      orderBy: 'created_at ASC',
    );

    if (rows.isEmpty) {
      _eventController.add(SyncEvent(
        type: SyncEventType.syncDone,
        syncedCount: 0,
        pendingCount: 0,
      ));
      return;
    }

    _isSyncing = true;
    _eventController.add(SyncEvent(
      type: SyncEventType.syncing,
      pendingCount: rows.length,
      message: 'Syncing ${rows.length} record(s)...',
    ));

    int success = 0;

    try {
      for (final row in rows) {
        final record = SyncRecord.fromMap(row);
        await db.update('sync_queue', {'status': SyncStatus.syncing.name, 'last_attempt': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [record.id]);

        try {
          // 1. Sync to Firebase (Using 'clock_ins' for both to merge In and Out data)
          final fbOk = await _syncToFirebase(record);
          
          // 2. Sync to MySQL
          final mysqlOk = await _syncToMySQL(record);

          if (fbOk && mysqlOk) {
            await db.update('sync_queue', {'status': SyncStatus.synced.name}, where: 'id = ?', whereArgs: [record.id]);
            success++;
          } else {
            await _markFailed(db, record, 'Sync failed to targets (FB:$fbOk, SQL:$mysqlOk)');
          }
        } catch (e) {
          await _markFailed(db, record, e.toString());
        }
      }
    } finally {
      _isSyncing = false;
    }

    final remaining = await getPendingCount();
    _eventController.add(SyncEvent(
      type: success > 0 ? SyncEventType.syncDone : SyncEventType.syncFailed,
      syncedCount: success,
      pendingCount: remaining,
    ));

    if (success > 0) await _cleanup(db);
  }

  Future<bool> _syncToFirebase(SyncRecord record) async {
    try {
      // Use 'clock_ins' for both types so that Clock In and Clock Out merge into one document per session
      const collection = 'clock_ins';
      final docId = record.payload['attendance_id'];
      
      await _firestore.collection(collection).doc(docId).set({
        ...record.payload,
        'synced_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      return true;
    } catch (e) {
      debugPrint('Firebase Sync Error: $e');
      return false;
    }
  }

  Future<bool> _syncToMySQL(SyncRecord record) async {
    try {
      final response = await http.post(
        Uri.parse(_mysqlSyncUrl),
        body: {
          'attendance_id': record.payload['attendance_id']?.toString() ?? '',
          'employee_id':   record.payload['employee_id']?.toString() ?? '',
          'employee_name': record.payload['employee_name']?.toString() ?? '',
          'time_in':       record.payload['time_in']?.toString() ?? '',
          'time_out':      record.payload['time_out']?.toString() ?? '',
          'date':          record.payload['date']?.toString() ?? '',
          'status':        record.payload['status']?.toString() ?? 'present',
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('MySQL Sync Error: $e');
      return false;
    }
  }

  Future<void> _markFailed(Database db, SyncRecord record, String error) async {
    await db.update(
      'sync_queue',
      {
        'status': SyncStatus.failed.name,
        'retry_count': record.retryCount + 1,
        'error_message': error,
        'last_attempt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> _cleanup(Database db) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    await db.delete('sync_queue', where: "status = 'synced' AND created_at < ?", whereArgs: [cutoff]);
  }

  Future<int> getPendingCount() async {
    if (kIsWeb) return 0;
    final db = await DatabaseService.instance.database;
    if (db == null) return 0;
    final r = await db.rawQuery("SELECT COUNT(*) as c FROM sync_queue WHERE status = 'pending'");
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<SyncRecord>> getRecentQueue({int limit = 30}) async {
    if (kIsWeb) return [];
    final db = await DatabaseService.instance.database;
    if (db == null) return [];
    final rows = await db.query('sync_queue', orderBy: 'created_at DESC', limit: limit);
    return rows.map(SyncRecord.fromMap).toList();
  }
}
