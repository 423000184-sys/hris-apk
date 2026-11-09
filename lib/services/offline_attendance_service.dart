// lib/services/offline_attendance_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../data/local/dao/connectivity_service.dart';

class OfflineAttendanceService {
  OfflineAttendanceService._();
  static final OfflineAttendanceService instance = OfflineAttendanceService._();

  Database? _db;
  Timer? _syncTimer;
  StreamSubscription<bool>? _connSub;
  bool _syncing = false;
  bool _started = false;

  // 🎯 FIX #4: pending count stream para sa UI
  final _pendingController = StreamController<int>.broadcast();
  Stream<int> get pendingStream => _pendingController.stream;
  int _lastPendingCount = 0;

  static const String _tableAttendance = 'pending_attendance';
  static const String _tableGeneric = 'pending_writes'; // 🎯 FIX #2

  // ═══════════════════════════════════════════════════════════════
  // INIT — DB v3 with generic queue
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_db != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'offline_attendance.db');

    _db = await openDatabase(
      path,
      version: 3, // 🎯 upgraded from v2
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableAttendance (
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
        await db.execute(
            'CREATE INDEX idx_synced ON $_tableAttendance(synced)');
        await db.execute(
            'CREATE INDEX idx_employee ON $_tableAttendance(employeeId)');

        // 🎯 FIX #2: generic queue table
        await db.execute('''
          CREATE TABLE $_tableGeneric (
            localId TEXT PRIMARY KEY,
            collection TEXT NOT NULL,
            docId TEXT,
            payload TEXT NOT NULL,
            synced INTEGER DEFAULT 0,
            retryCount INTEGER DEFAULT 0,
            createdAt TEXT NOT NULL,
            lastError TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_generic_synced ON $_tableGeneric(synced)');
        await db.execute(
            'CREATE INDEX idx_generic_collection ON $_tableGeneric(collection)');

        debugPrint('✅ OfflineAttendanceService: DB created (v3)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
                'ALTER TABLE $_tableAttendance ADD COLUMN zoneType TEXT');
          } catch (e) {
            debugPrint('⚠️ v2 migration: $e');
          }
        }
        if (oldVersion < 3) {
          try {
            await db.execute('''
              CREATE TABLE $_tableGeneric (
                localId TEXT PRIMARY KEY,
                collection TEXT NOT NULL,
                docId TEXT,
                payload TEXT NOT NULL,
                synced INTEGER DEFAULT 0,
                retryCount INTEGER DEFAULT 0,
                createdAt TEXT NOT NULL,
                lastError TEXT
              )
            ''');
            await db.execute(
                'CREATE INDEX idx_generic_synced ON $_tableGeneric(synced)');
            await db.execute(
                'CREATE INDEX idx_generic_collection ON $_tableGeneric(collection)');
            debugPrint('✅ DB migrated to v3 — generic queue added');
          } catch (e) {
            debugPrint('⚠️ v3 migration: $e');
          }
        }
      },
    );

    debugPrint('✅ OfflineAttendanceService initialized');
    await _emitPendingCount();
  }

  Database get _database {
    if (_db == null) {
      throw StateError('OfflineAttendanceService not initialized.');
    }
    return _db!;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 FIX #3: START AUTO SYNC — connectivity-based + periodic
  // ═══════════════════════════════════════════════════════════════
  Future<void> startAutoSync() async {
    if (_started) return;
    _started = true;

    await init();

    // Immediate sync on connectivity restore
    try {
      _connSub =
          ConnectivityService.instance.onStatusChange.listen((online) async {
            if (online) {
              debugPrint('📶 [AutoSync] Back online — triggering sync');
              await syncPending();
            }
          });
    } catch (e) {
      debugPrint('⚠️ [AutoSync] conn listener failed: $e');
    }

    // Periodic fallback (every 60s)
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final pending = await getPendingCount();
      if (pending > 0) {
        debugPrint('⏰ [AutoSync] $pending pending — syncing...');
        await syncPending();
      }
    });

    // Immediate sync at start
    unawaited(syncPending());

    debugPrint('⏰ [AutoSync] Started (connectivity + 60s timer)');
  }

  void stopAutoSync() {
    _connSub?.cancel();
    _connSub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _started = false;
  }

  // ═══════════════════════════════════════════════════════════════
  // LOG ATTENDANCE — existing signature (kept for backwards compat)
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
    String zoneType = 'inside',
  }) async {
    await init();

    final ts = timestamp ?? DateTime.now();
    final localId = _generateLocalId(employeeId, type, ts);

    await _database.insert(
      _tableAttendance,
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

    final synced = await _trySyncSingle(localId);

    if (synced) {
      debugPrint('✅ [Offline] Synced immediately');
      return AttendanceResult(
        success: true,
        queued: false,
        localId: localId,
        message: 'Saved and synced',
      );
    } else {
      debugPrint('📥 [Offline] Queued for later');
      await _emitPendingCount();
      return AttendanceResult(
        success: true,
        queued: true,
        localId: localId,
        message: 'Saved locally — will sync when online',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 FIX #2: GENERIC ENQUEUE — for any collection
  // ═══════════════════════════════════════════════════════════════
  Future<String> enqueue({
    required String collection,
    required Map<String, dynamic> data,
    String? docId,
  }) async {
    await init();

    // Serialize Firestore-specific types (FieldValue, Timestamp, GeoPoint)
    final sanitized = _sanitizeForStorage(data);

    final localId = docId ??
        '${collection}_${DateTime.now().millisecondsSinceEpoch}_'
            '${math.Random().nextInt(999999)}';

    await _database.insert(
      _tableGeneric,
      {
        'localId': localId,
        'collection': collection,
        'docId': docId,
        'payload': jsonEncode(sanitized),
        'synced': 0,
        'retryCount': 0,
        'createdAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    debugPrint('💾 [Generic] Enqueued: $collection/$localId');

    // Try immediate
    final ok = await _trySyncGeneric(localId);
    if (ok) {
      debugPrint('✅ [Generic] Synced immediately: $collection');
    } else {
      await _emitPendingCount();
    }

    return localId;
  }

  // Serialize types na hindi kayang i-JSON
  Map<String, dynamic> _sanitizeForStorage(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((k, v) {
      if (v is FieldValue) {
        out[k] = {'__serverTimestamp': true};
      } else if (v is Timestamp) {
        out[k] = {'__timestamp': v.toDate().toIso8601String()};
      } else if (v is DateTime) {
        out[k] = {'__datetime': v.toIso8601String()};
      } else if (v is GeoPoint) {
        out[k] = {
          '__geopoint': [v.latitude, v.longitude]
        };
      } else if (v is Map) {
        out[k] = _sanitizeForStorage(Map<String, dynamic>.from(v));
      } else if (v is List) {
        out[k] = v.map((e) {
          if (e is Map) {
            return _sanitizeForStorage(Map<String, dynamic>.from(e));
          }
          if (e is Timestamp) {
            return {'__timestamp': e.toDate().toIso8601String()};
          }
          return e;
        }).toList();
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  // Restore Firestore types from JSON
  dynamic _restoreFromStorage(dynamic v) {
    if (v is Map) {
      if (v['__serverTimestamp'] == true) return FieldValue.serverTimestamp();
      if (v.containsKey('__timestamp')) {
        return Timestamp.fromDate(DateTime.parse(v['__timestamp']));
      }
      if (v.containsKey('__datetime')) {
        return DateTime.parse(v['__datetime']);
      }
      if (v.containsKey('__geopoint')) {
        final coords = v['__geopoint'] as List;
        return GeoPoint(coords[0] as double, coords[1] as double);
      }
      return v.map((k, val) => MapEntry(k.toString(), _restoreFromStorage(val)));
    }
    if (v is List) return v.map(_restoreFromStorage).toList();
    return v;
  }

  Future<bool> _trySyncGeneric(String localId) async {
    try {
      final rows = await _database.query(
        _tableGeneric,
        where: 'localId = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return false;

      final ok = await _pushGenericToFirestore(rows.first);
      if (ok) {
        await _database.update(
          _tableGeneric,
          {'synced': 1},
          where: 'localId = ?',
          whereArgs: [localId],
        );
        await _emitPendingCount();
      } else {
        await _database.update(
          _tableGeneric,
          {'retryCount': (rows.first['retryCount'] as int? ?? 0) + 1},
          where: 'localId = ?',
          whereArgs: [localId],
        );
      }
      return ok;
    } catch (e) {
      debugPrint('❌ [Generic sync] $e');
      return false;
    }
  }

  Future<bool> _pushGenericToFirestore(Map<String, dynamic> row) async {
    final collection = row['collection'] as String;
    final docId = row['docId'] as String?;
    final payloadStr = row['payload'] as String;

    try {
      final decoded = jsonDecode(payloadStr) as Map<String, dynamic>;
      final restored = _restoreFromStorage(decoded) as Map<String, dynamic>;

      final collectionRef =
      FirebaseFirestore.instance.collection(collection);

      if (docId != null && docId.isNotEmpty) {
        await collectionRef
            .doc(docId)
            .set(restored, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } else {
        await collectionRef
            .add(restored)
            .timeout(const Duration(seconds: 10));
      }

      debugPrint('✅ [Generic] Pushed $collection/${docId ?? "auto"}');
      return true;
    } on TimeoutException {
      debugPrint('⏱️ [Generic] Timeout on $collection');
      return false;
    } catch (e) {
      debugPrint('❌ [Generic] Push failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SYNC ALL PENDING
  // ═══════════════════════════════════════════════════════════════
  Future<int> syncPending() async {
    if (_syncing) {
      debugPrint('⏳ [Sync] Already syncing');
      return 0;
    }

    await init();
    _syncing = true;
    int syncedCount = 0;

    try {
      // ── Attendance ──
      final attRows = await _database.query(
        _tableAttendance,
        where: 'synced = 0 AND retryCount < 5',
        orderBy: 'timestamp ASC',
      );

      for (final row in attRows) {
        final ok = await _pushToFirestore(row);
        if (ok) {
          await _database.update(
            _tableAttendance,
            {'synced': 1},
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
          syncedCount++;
        } else {
          await _database.update(
            _tableAttendance,
            {'retryCount': (row['retryCount'] as int? ?? 0) + 1},
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
        }
      }

      // ── Generic ──
      final genRows = await _database.query(
        _tableGeneric,
        where: 'synced = 0 AND retryCount < 5',
        orderBy: 'createdAt ASC',
      );

      for (final row in genRows) {
        final ok = await _pushGenericToFirestore(row);
        if (ok) {
          await _database.update(
            _tableGeneric,
            {'synced': 1},
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
          syncedCount++;
        } else {
          await _database.update(
            _tableGeneric,
            {
              'retryCount': (row['retryCount'] as int? ?? 0) + 1,
              'lastError': 'push failed',
            },
            where: 'localId = ?',
            whereArgs: [row['localId']],
          );
        }
      }

      if (syncedCount > 0) {
        debugPrint('✅ [Sync] Synced $syncedCount records');
      }
      await _emitPendingCount();
      return syncedCount;
    } catch (e) {
      debugPrint('❌ [Sync] Error: $e');
      return syncedCount;
    } finally {
      _syncing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Single record sync (attendance)
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _trySyncSingle(String localId) async {
    try {
      final rows = await _database.query(
        _tableAttendance,
        where: 'localId = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (rows.isEmpty) return false;

      final ok = await _pushToFirestore(rows.first);
      if (ok) {
        await _database.update(
          _tableAttendance,
          {'synced': 1},
          where: 'localId = ?',
          whereArgs: [localId],
        );
        await _emitPendingCount();
      }
      return ok;
    } catch (e) {
      debugPrint('❌ [Sync single] $e');
      return false;
    }
  }

  Future<bool> _pushToFirestore(Map<String, dynamic> row) async {
    final localId = row['localId'] as String;
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
        'zone_type': row['zoneType'] ?? 'inside',
        'localId': localId,
        'syncedAt': FieldValue.serverTimestamp(),
        'wasOffline': true,
      };

      // 🎯 KEY: use localId as doc ID — prevents duplicate on retry
      await FirebaseFirestore.instance
          .collection('attendance_logs')
          .doc(localId)
          .set(data, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      return true;
    } on TimeoutException {
      return false;
    } catch (e) {
      debugPrint('❌ [Firestore] $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎯 FIX #4: PENDING COUNT + STREAM
  // ═══════════════════════════════════════════════════════════════
  Future<int> getPendingCount() async {
    await init();
    final a = await _database.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableAttendance WHERE synced = 0',
    );
    final g = await _database.rawQuery(
      'SELECT COUNT(*) as c FROM $_tableGeneric WHERE synced = 0',
    );
    final att = (a.first['c'] as int?) ?? 0;
    final gen = (g.first['c'] as int?) ?? 0;
    return att + gen;
  }

  Future<void> _emitPendingCount() async {
    try {
      final c = await getPendingCount();
      if (c != _lastPendingCount) {
        _lastPendingCount = c;
        if (!_pendingController.isClosed) _pendingController.add(c);
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getPending() async {
    await init();
    final att = await _database.query(
      _tableAttendance,
      where: 'synced = 0',
      orderBy: 'timestamp ASC',
    );
    final gen = await _database.query(
      _tableGeneric,
      where: 'synced = 0',
      orderBy: 'createdAt ASC',
    );
    return [...att, ...gen];
  }

  Future<List<Map<String, dynamic>>> getAll({int limit = 100}) async {
    await init();
    return _database.query(
      _tableAttendance,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLatestForEmployee(String employeeId) async {
    await init();
    final rows = await _database.query(
      _tableAttendance,
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
      _tableAttendance,
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

    final d1 = await _database.delete(
      _tableAttendance,
      where: 'synced = 1 AND createdAt < ?',
      whereArgs: [cutoff],
    );
    final d2 = await _database.delete(
      _tableGeneric,
      where: 'synced = 1 AND createdAt < ?',
      whereArgs: [cutoff],
    );
    debugPrint('🧹 [Cleanup] Deleted ${d1 + d2} old records');
    return d1 + d2;
  }

  Future<void> clearAll() async {
    await init();
    await _database.delete(_tableAttendance);
    await _database.delete(_tableGeneric);
    debugPrint('🗑️ [Offline] Cleared all');
  }

  Future<void> dumpAll() async {
    await init();
    final att = await _database.query(_tableAttendance);
    final gen = await _database.query(_tableGeneric);
    debugPrint('📊 attendance=${att.length} generic=${gen.length}');
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