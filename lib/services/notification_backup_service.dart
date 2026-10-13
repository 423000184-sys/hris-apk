// lib/services/notification_backup_service.dart
import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/admin_notification.dart';

/// 💾 Notification Backup Service — SINGLE FILE MODE
///
/// Auto-saves EVERY notification from `admin_notifications` into ONE
/// .txt file. No filtering. Uses Firestore `doc.id` for dedup.
class NotificationBackupService {
  NotificationBackupService._();
  static final instance = NotificationBackupService._();

  static const String _localFolder = 'notification_backups';
  static const String _singleFileName = 'notifications_backup.txt';
  static const String _webPrefsKey = 'notif_backup_single_v1';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final Set<String> _processedIds = {};
  bool _initialized = false;
  int _backupCount = 0;

  String? _cachedContent;

  int get backupCount => _backupCount;
  int get trackedCount => _processedIds.length;

  // ═══════════════════════════════════════════════════════════════
  // INIT — call from admin_dashboard initState
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('💾 [NotifBackup] Initializing (web=$kIsWeb)...');

    await _loadCache();

    try {
      final caught = await forceBackupNow(limit: 200);
      if (caught > 0) {
        debugPrint('💾 [NotifBackup] Catch-up: $caught new');
      } else {
        debugPrint('💾 [NotifBackup] Catch-up: none new (already synced)');
      }
    } catch (e) {
      debugPrint('💾 [NotifBackup] Catch-up error: $e');
    }

    _sub = FirebaseFirestore.instance
        .collection('admin_notifications')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen(
      _onSnapshot,
      onError: (e) => debugPrint('💾 [NotifBackup] Stream error: $e'),
    );

    debugPrint('💾 [NotifBackup] READY — ${_processedIds.length} tracked IDs');
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD CACHE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadCache() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        _cachedContent = prefs.getString(_webPrefsKey) ?? '';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, _localFolder, _singleFileName));
        _cachedContent =
        await file.exists() ? await file.readAsString() : '';
      }

      _processedIds.clear();
      final content = _cachedContent ?? '';
      final regex = RegExp(r'^ID\s+:\s+(.+?)\s*$', multiLine: true);
      for (final m in regex.allMatches(content)) {
        final id = m.group(1);
        if (id != null && id.isNotEmpty) _processedIds.add(id);
      }

      debugPrint('💾 [NotifBackup] Cache: ${content.length} chars, '
          '${_processedIds.length} tracked IDs');
    } catch (e) {
      debugPrint('💾 [NotifBackup] Load error: $e');
      _cachedContent = '';
      _processedIds.clear();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FORCE BACKUP NOW — uses doc.id for dedup
  // ═══════════════════════════════════════════════════════════════
  Future<int> forceBackupNow({int limit = 20}) async {
    debugPrint('💾 [NotifBackup] Force backup (limit=$limit)...');

    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      if (snap.docs.isEmpty) {
        debugPrint('💾 [NotifBackup] No notifications in Firestore');
        return 0;
      }

      final docs = [...snap.docs];
      docs.sort((a, b) {
        final at = a.data()['timestamp'];
        final bt = b.data()['timestamp'];
        if (at is Timestamp && bt is Timestamp) return at.compareTo(bt);
        return 0;
      });

      final buf = StringBuffer();
      int added = 0;

      for (final doc in docs) {
        if (_processedIds.contains(doc.id)) continue;
        _processedIds.add(doc.id);

        final n = AdminNotification.fromDoc(doc);
        buf.write(_buildEntry(doc.id, n));
        _backupCount++;
        added++;
      }

      if (added == 0) {
        debugPrint('💾 [NotifBackup] All ${snap.docs.length} already saved');
        return 0;
      }

      if ((_cachedContent ?? '').isEmpty) {
        _cachedContent = _buildHeader();
      }
      _cachedContent = (_cachedContent ?? '') + buf.toString();

      await _saveToStorage();

      debugPrint('💾 [NotifBackup] Appended $added/${snap.docs.length}');
      return added;
    } catch (e) {
      debugPrint('💾 [NotifBackup] Force error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CLEAR + REBUILD — wipe log then re-save ALL from Firestore
  // ═══════════════════════════════════════════════════════════════
  Future<int> rebuildLog({int limit = 500}) async {
    debugPrint('🔄 [NotifBackup] Rebuilding log...');
    await deleteAll();
    await _loadCache();
    final count = await forceBackupNow(limit: limit);
    debugPrint('🔄 [NotifBackup] Rebuilt — $count entries');
    return count;
  }

  // ═══════════════════════════════════════════════════════════════
  // LIVE SNAPSHOT HANDLER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    for (final doc in snap.docs) {
      if (_processedIds.contains(doc.id)) continue;
      _processedIds.add(doc.id);

      final n = AdminNotification.fromDoc(doc);
      debugPrint('💾 [NotifBackup] Auto-save: ${n.type} — ${n.title}');
      await _appendEntry(doc.id, n);
    }
  }

  Future<void> _appendEntry(String docId, AdminNotification n) async {
    try {
      if ((_cachedContent ?? '').isEmpty) {
        _cachedContent = _buildHeader();
      }
      _cachedContent = (_cachedContent ?? '') + _buildEntry(docId, n);
      await _saveToStorage();
      _backupCount++;
    } catch (e) {
      debugPrint('💾 [NotifBackup] Append error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILDERS
  // ═══════════════════════════════════════════════════════════════
  String _buildHeader() {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('📄 NOTIFICATIONS BACKUP LOG');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('Created   : '
        '${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buf.writeln('Source    : HRIS Biometrics Admin');
    buf.writeln('Storage   : '
        '${kIsWeb ? "browser localStorage" : "local device"}');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('');
    return buf.toString();
  }

  String _buildEntry(String docId, AdminNotification n) {
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('───────────────────────────────────────────────');
    buf.writeln('📌 [${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}] '
        '${n.type.toUpperCase()}');
    buf.writeln('───────────────────────────────────────────────');
    buf.writeln('ID         : $docId');
    buf.writeln('Type       : ${n.type}');
    buf.writeln('Priority   : ${n.priority}');
    if (n.timestamp != null) {
      buf.writeln('Timestamp  : '
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(n.timestamp!)}');
    }
    buf.writeln('Title      : ${n.title}');
    buf.writeln('Message    : ${n.message}');
    if (n.employeeId != null && n.employeeId!.isNotEmpty) {
      buf.writeln('Employee ID: ${n.employeeId}');
    }
    if (n.employeeName != null && n.employeeName!.isNotEmpty) {
      buf.writeln('Employee   : ${n.employeeName}');
    }
    if (n.metadata.isNotEmpty) {
      buf.writeln('Metadata   :');
      n.metadata.forEach((key, value) {
        buf.writeln('   $key = $value');
      });
    }
    buf.writeln('');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // STORAGE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _saveToStorage() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_webPrefsKey, _cachedContent ?? '');
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final backupDir = Directory(p.join(dir.path, _localFolder));
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        final file = File(p.join(backupDir.path, _singleFileName));
        await file.writeAsString(_cachedContent ?? '', flush: true);
      }
    } catch (e) {
      debugPrint('💾 [NotifBackup] Save error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════
  Future<List<NotificationBackupInfo>> listBackups() async {
    await _loadCache();
    final content = _cachedContent ?? '';
    if (content.isEmpty) return [];

    final savedAt = await _getFileModifiedTime();
    final entryCount = '📌 ['.allMatches(content).length;

    return [
      NotificationBackupInfo(
        filename: _singleFileName,
        path: kIsWeb ? 'web://$_singleFileName' : await _getFilePath(),
        savedAt: savedAt,
        sizeBytes: content.length,
        entryCount: entryCount,
      ),
    ];
  }

  Future<String> _getFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _localFolder, _singleFileName);
  }

  Future<DateTime> _getFileModifiedTime() async {
    try {
      if (kIsWeb) return DateTime.now();
      final path = await _getFilePath();
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.modified;
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<String?> readBackup(String path) async {
    await _loadCache();
    return _cachedContent;
  }

  Future<bool> deleteBackup(String path) async {
    return await deleteAll() > 0;
  }

  Future<int> deleteAll() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        final had = (prefs.getString(_webPrefsKey) ?? '').isNotEmpty;
        await prefs.remove(_webPrefsKey);
        _cachedContent = '';
        _processedIds.clear();
        return had ? 1 : 0;
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          _cachedContent = '';
          _processedIds.clear();
          return 1;
        }
        _cachedContent = '';
        _processedIds.clear();
        return 0;
      }
    } catch (e) {
      debugPrint('💾 [NotifBackup] Delete error: $e');
      return 0;
    }
  }

  Future<int> getTotalSize() async {
    final files = await listBackups();
    return files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
  }

  Future<String> getBackupDirectory() async {
    if (kIsWeb) return 'localStorage (browser)';
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _localFolder);
  }

  void dispose() {
    _sub?.cancel();
  }
}

// ═══════════════════════════════════════════════════════════════
// MODEL
// ═══════════════════════════════════════════════════════════════
class NotificationBackupInfo {
  final String filename;
  final String path;
  final DateTime savedAt;
  final int sizeBytes;
  final int entryCount;

  const NotificationBackupInfo({
    required this.filename,
    required this.path,
    required this.savedAt,
    required this.sizeBytes,
    this.entryCount = 0,
  });
}