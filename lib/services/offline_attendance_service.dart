// lib/services/offline_attendance_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class OfflineAttendanceService {
  OfflineAttendanceService._();
  static final OfflineAttendanceService instance = OfflineAttendanceService._();

  Database? _db;
  Timer? _syncTimer;
  bool _syncing = false;

  static const String _tableName = 'pending_attendance';

  // ═══════════════════════════════════════════════════════════════
  // INIT — DB version 2 with zoneType column
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'offline_attendance.db');

    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            localId TEXT PRIMARY KEY,
            employeeId TEXT NOT NULL,
            employeeName TEXT,
            employeeEmail TEXT,
            type TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            distance REAL,
            insideZone INTEGER,
            device TEXT,
            remarks TEXT,
            zoneType TEXT,
            synced INTEGER DEFAULT 0,
            retryCount INTEGER DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_synced ON $_tableName(synced)');
        await db.execute('CREATE INDEX idx_employee ON $_tableName(employeeId)');
        debugPrint('✅ OfflineAttendanceService: DB created (v2)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
                'ALTER TABLE $_tableName ADD COLUMN zoneType TEXT');
            debugPrint('✅ DB migrated to v2 — zoneType column added');
          } catch (e) {
            debugPrint('⚠️ Migration error (may already exist): $e');
          }
        }
      },
    );

    debugPrint('✅ OfflineAttendanceService initialized');
  }

  Database get _database {
    if (_db == null) {
      throw StateError(
          'OfflineAttendanceService not initialized. Call init() first.');
    }
    return _db!;
  }

  // ═══════════════════════════════════════════════════════════════
  // LOG ATTENDANCE — with zoneType
  // ═══════════════════════════════════════════════════════════════
  Future<AttendanceResult> logAttendance({
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String type,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? distance,
    bool? insideZone,
    String device = 'Mobile App',
    String remarks = '',
    String zoneType = 'inside', // ✅ NEW
  }) async {
    await init();

    final ts = timestamp ?? DateTime.now();
    final localId = _generateLocalId(employeeId, type, ts);

    // ── 1. Save sa LOCAL muna ──
    await _database.insert(
      _tableName,
      {
        'localId': localId,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'employeeEmail': employeeEmail,
        'type': type,
        'timestamp': ts.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'distance': distance,
        'insideZone': insideZone == null ? null : (insideZone ? 1 : 0),
        'device': device,
        'remarks': remarks,
        'zoneType': zoneType,
        'synced': 0,
        'retryCount': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('💾 [Offline] Saved locally: $type (zone=$zoneType, id=$localId)');

    // ── 2. Subukan mag-sync agad ──
    final synced = await _trySyncSingle(localId);

    if (synced) {
      debugPrint('✅ [Offline] Synced immediately to Firestore');
      return AttendanceResult(
        success: true,
        queued: false,
        localId: localId,
        message: 'Saved and synced',
      );
    } else {
      debugPrint('📥 [Offline] Queued for later sync');
      return AttendanceResult(
        success: true,
        queued: true,
        localId: localId,
        message: 'Saved locally — will sync when online',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SYNC
  // ═══════════════════════════════════════════════════════════════
  Future<int> syncPending() async {
    if (_syncing) {
      debugPrint('⏳ [Sync] Already syncing, skipping');
      return 0;
    }

    await init();
    _syncing = true;
    int syncedCount = 0;

    try {
      final rows = await _database.query(
        _tableName,
        where: 'synced = 0 AND retryCount < 5',
        orderBy: 'timestamp ASC',
      );

      if (rows.isEmpty) {
        debugPrint('✅ [Sync] No pending records');
        return 0;
      }

      debugPrint('🔄 [Sync] Syncing ${rows.length} pending records...');

      for (final row in rows) {
        final ok = await _pushToFirestore(row);
        if (ok) {
          await _database.update(
            _tableName,
            {'synced': 1},
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
          syncedCount++;
        } else {
          await _database.update(
            _tableName,
            {'retryCount': (row['retryCount'] as int? ?? 0) + 1},
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
        }
      }

      debugPrint('✅ [Sync] Synced $syncedCount/${rows.length} records');
      return syncedCount;
    } catch (e) {
      debugPrint('❌ [Sync] Error: $e');
      return syncedCount;
    } finally {
      _syncing = false;
    }
  }

  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final pending = await getPendingCount();
      if (pending > 0) {
        debugPrint('⏰ [AutoSync] $pending pending — syncing...');
        await syncPending();
      }
    });
    debugPrint('⏰ [AutoSync] Started (every 30s)');
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // ═══════════════════════════════════════════════════════════════
  // SYNC — Single record
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _trySyncSingle(String localId) async {
    try {
      final rows = await _database.query(
        _tableName,
        where: 'localId = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return false;

      final ok = await _pushToFirestore(rows.first);
      if (ok) {
        await _database.update(
          _tableName,
          {'synced': 1},
          where: 'localId = ?',
          whereArgs: [localId],
        );
      }
      return ok;
    } catch (e) {
      debugPrint('❌ [Sync single] Error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ PUSH TO FIRESTORE — with zone_type + server verification
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _pushToFirestore(Map<String, dynamic> row) async {
    final localId = row['localId'] as String;

    debugPrint('═══════════════════════════════════════');
    debugPrint('🔥 [_pushToFirestore] START');
    debugPrint('   localId: $localId');
    debugPrint('   type: ${row['type']}');
    debugPrint('   zone: ${row['zoneType']}');
    debugPrint('   employeeId: ${row['employeeId']}');
    debugPrint('═══════════════════════════════════════');

    try {
      final ts = DateTime.tryParse(row['timestamp'] as String? ?? '') ??
          DateTime.now();

      final data = <String, dynamic>{
        'employee_id': row['employeeId'],
        'employee_name': row['employeeName'],
        'employee_email': row['employeeEmail'],
        'type': row['type'],
        'timestamp': Timestamp.fromDate(ts),
        'date': ts.toIso8601String().substring(0, 10),
        'time': '${ts.hour.toString().padLeft(2, '0')}:'
            '${ts.minute.toString().padLeft(2, '0')}:'
            '${ts.second.toString().padLeft(2, '0')}',
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'distance': row['distance'],
        'insideZone': (row['insideZone'] as int?) == 1,
        'device': row['device'],
        'remarks': row['remarks'],
        'zone_type': row['zoneType'] ?? 'inside', // ✅ NEW
        'localId': localId,
        'syncedAt': FieldValue.serverTimestamp(),
        'wasOffline': true,
      };

      final docRef = FirebaseFirestore.instance
          .collection('attendance_logs')
          .doc(localId);

      debugPrint('📡 [Firestore] Writing to: ${docRef.path}');

      // STEP 1: Write
      await docRef
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      debugPrint('📡 [Firestore] .set() returned');

      // STEP 2: Verify on SERVER
      debugPrint('📡 [Firestore] Verifying on SERVER...');

      final serverCheck = await docRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (serverCheck.exists) {
        final serverData = serverCheck.data();
        debugPrint('✅ [Firestore] VERIFIED on server!');
        debugPrint('   server zone: ${serverData?['zone_type']}');
        return true;
      } else {
        debugPrint('❌ [Firestore] NOT on server!');
        return false;
      }
    } on TimeoutException {
      debugPrint('⏱️ [Firestore] TIMEOUT');
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ [Firestore] FAILED: $e');
      debugPrint('   Stack: $stackTrace');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // QUERIES
  // ═══════════════════════════════════════════════════════════════
  Future<int> getPendingCount() async {
    await init();
    final result = await _database.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableName WHERE synced = 0',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    await init();
    return _database.query(
      _tableName,
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getAll({int limit = 100}) async {
    await init();
    return _database.query(
      _tableName,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLatestForEmployee(String employeeId) async {
    await init();
    final rows = await _database.query(
      _tableName,
      where: 'employeeId = ?',
      whereArgs: [employeeId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getTodayForEmployee(
      String employeeId) async {
    await init();
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    return _database.query(
      _tableName,
      where: 'employeeId = ? AND timestamp LIKE ?',
      whereArgs: [employeeId, '$todayStr%'],
      orderBy: 'timestamp ASC',
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MAINTENANCE
  // ═══════════════════════════════════════════════════════════════
  Future<int> cleanOldRecords({int daysOld = 30}) async {
    await init();
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .toIso8601String();

    final deleted = await _database.delete(
      _tableName,
      where: 'synced = 1 AND createdAt < ?',
      whereArgs: [cutoff],
    );
    debugPrint('🧹 [Cleanup] Deleted $deleted old records');
    return deleted;
  }

  Future<void> clearAll() async {
    await init();
    await _database.delete(_tableName);
    debugPrint('🗑️ [Offline] Cleared all records');
  }

  // ═══════════════════════════════════════════════════════════════
  // DIAGNOSTIC
  // ═══════════════════════════════════════════════════════════════
  Future<void> dumpAll() async {
    await init();
    final all = await getAll();
    debugPrint('═══════════════════════════════════════');
    debugPrint('📊 SQLITE DUMP — ${all.length} total records');
    debugPrint('═══════════════════════════════════════');
    for (final r in all) {
      final synced = r['synced'] == 1 ? '✅ synced ' : '📥 PENDING';
      debugPrint('  $synced | ${r['type']} | zone=${r['zoneType']} | '
          '${r['timestamp']} | id=${r['localId']}');
    }
    final pending = all.where((r) => r['synced'] == 0).length;
    debugPrint('───────────────────────────────────────');
    debugPrint('📥 Pending: $pending  |  ✅ Synced: ${all.length - pending}');
    debugPrint('═══════════════════════════════════════');
  }

  String _generateLocalId(String employeeId, String type, DateTime ts) {
    return '${employeeId}_${type}_${ts.millisecondsSinceEpoch}';
  }
}

class AttendanceResult {
  final bool success;
  final bool queued;
  final String localId;
  final String message;

  const AttendanceResult({
    required this.success,
    required this.queued,
    required this.localId,
    required this.message,
  });
}