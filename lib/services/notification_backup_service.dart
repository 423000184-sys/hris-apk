// lib/services/notification_backup_service.dart
import 'dart:async';
import 'dart:convert';
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
/// Lahat ng notifications ay naka-append sa ISANG .txt file lang.
///   - Native: Documents/notification_backups/notifications_backup.txt
///   - Web:    localStorage key "notif_backup_single_v1"
class NotificationBackupService {
  NotificationBackupService._();
  static final instance = NotificationBackupService._();

  // ─── SINGLE FILE CONFIG ────────────────────────────────────────
  static const String _localFolder = 'notification_backups';
  static const String _singleFileName = 'notifications_backup.txt';
  static const String _webPrefsKey = 'notif_backup_single_v1';
  static const int retentionDays = 30;

  StreamSubscription<List<AdminNotification>>? _sub;
  final Set<String> _processedIds = {};
  bool _initialized = false;
  int _backupCount = 0;

  // Memory cache of the single file content (para hindi laging file read)
  String? _cachedContent;

  int get backupCount => _backupCount;

  // ═══════════════════════════════════════════════════════════════
  // INIT — tawagin sa main.dart
  // ═══════════════════════════════════════════════════════════════
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    debugPrint('💾 [NotifBackup] Initializing (single-file mode, web=$kIsWeb)...');

    // Load existing content para may cache
    await _loadCache();

    // Seed existing IDs
    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();

      for (final doc in snap.docs) {
        _processedIds.add(doc.id);
      }
      debugPrint(
          '💾 [NotifBackup] Seeded ${_processedIds.length} existing IDs');
    } catch (e) {
      debugPrint('💾 [NotifBackup] Seed error: $e');
    }

    // Listen for new notifications
    _sub = FirebaseFirestore.instance
        .collection('admin_notifications')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((s) => s.docs.map(AdminNotification.fromDoc).toList())
        .listen(
      _onNewNotifications,
      onError: (e) => debugPrint('💾 [NotifBackup] Stream error: $e'),
    );

    debugPrint('💾 [NotifBackup] READY — listening for notifications');
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD CACHE — basahin yung existing file content
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadCache() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        _cachedContent = prefs.getString(_webPrefsKey) ?? '';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(p.join(dir.path, _localFolder, _singleFileName));
        if (await file.exists()) {
          _cachedContent = await file.readAsString();
        } else {
          _cachedContent = '';
        }
      }
      debugPrint(
          '💾 [NotifBackup] Cache loaded (${_cachedContent?.length ?? 0} chars)');
    } catch (e) {
      debugPrint('💾 [NotifBackup] Load cache error: $e');
      _cachedContent = '';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // FORCE BACKUP NOW — append lahat ng latest notifications
  // ═══════════════════════════════════════════════════════════════
  Future<int> forceBackupNow({int limit = 20}) async {
    debugPrint('💾 [NotifBackup] Force backup requested (limit=$limit)...');

    try {
      final snap = await FirebaseFirestore.instance
          .collection('admin_notifications')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      if (snap.docs.isEmpty) {
        debugPrint('💾 [NotifBackup] Walang notifications — skip');
        return 0;
      }

      // Prepare entries
      final List<String> newEntries = [];
      for (final doc in snap.docs) {
        final n = AdminNotification.fromDoc(doc);

        // Skip kung na-process na (para hindi mag-duplicate)
        if (_processedIds.contains(n.id)) continue;
        _processedIds.add(n.id);

        newEntries.add(_buildEntry(n));
        _backupCount++;
      }

      if (newEntries.isEmpty) {
        debugPrint('💾 [NotifBackup] All notifications already backed up');
        return 0;
      }

      // Ensure header exists
      if ((_cachedContent ?? '').isEmpty) {
        _cachedContent = _buildHeader();
      }

      // Append new entries
      _cachedContent = (_cachedContent ?? '') + newEntries.join('\n');

      // Save to storage
      await _saveToStorage();

      debugPrint(
          '💾 [NotifBackup] Force complete — appended ${newEntries.length}/${snap.docs.length}');
      return newEntries.length;
    } catch (e) {
      debugPrint('💾 [NotifBackup] Force backup error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HANDLER — for auto-backup on new notifications
  // ═══════════════════════════════════════════════════════════════
  void _onNewNotifications(List<AdminNotification> items) {
    for (final n in items) {
      if (_processedIds.contains(n.id)) continue;
      _processedIds.add(n.id);

      if (!_shouldBackup(n)) continue;

      debugPrint('💾 [NotifBackup] Backing up: ${n.type} — ${n.title}');
      _appendEntry(n);
    }
  }

  bool _shouldBackup(AdminNotification n) {
    if (n.read) return false;

    if (n.timestamp != null) {
      final age = DateTime.now().difference(n.timestamp!).inMinutes;
      if (age > 5) return false;
    }

    switch (n.type) {
      case 'geofence_alert':
      case 'clock_in':
      case 'clock_out':
      case 'wfh_toggle':
      case 'face_enrollment':
      case 'leave_request':
        return true;
      case 'presence_update':
        final changed = n.metadata['changed'] == true;
        final reason = n.metadata['notify_reason']?.toString() ?? '';
        final isInitial = reason == 'initial';
        return changed || isInitial;
      default:
        return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // APPEND ENTRY — add notification to single file
  // ═══════════════════════════════════════════════════════════════
  Future<void> _appendEntry(AdminNotification n) async {
    try {
      // Ensure header exists
      if ((_cachedContent ?? '').isEmpty) {
        _cachedContent = _buildHeader();
      }

      // Append new entry
      _cachedContent = (_cachedContent ?? '') + _buildEntry(n);

      // Save
      await _saveToStorage();

      _backupCount++;
      debugPrint(
          '💾 [NotifBackup] Appended: ${n.type} (total entries: $_backupCount)');
    } catch (e) {
      debugPrint('💾 [NotifBackup] Append error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD HEADER
  // ═══════════════════════════════════════════════════════════════
  String _buildHeader() {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('📄 NOTIFICATIONS BACKUP LOG');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln(
        'Created   : ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    buf.writeln('Source    : HRIS Biometrics Admin');
    buf.writeln('Version   : 1.0.2+3');
    buf.writeln('Storage   : ${kIsWeb ? "browser localStorage" : "local device"}');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD ENTRY — one notification block
  // ═══════════════════════════════════════════════════════════════
  String _buildEntry(AdminNotification n) {
    final now = DateTime.now();
    final buf = StringBuffer();
    buf.writeln('───────────────────────────────────────────────');
    buf.writeln(
        '📌 [${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}] ${n.type.toUpperCase()}');
    buf.writeln('───────────────────────────────────────────────');
    buf.writeln('Type       : ${n.type}');
    buf.writeln('Priority   : ${n.priority}');
    if (n.timestamp != null) {
      buf.writeln(
          'Timestamp  : ${DateFormat('yyyy-MM-dd HH:mm:ss').format(n.timestamp!)}');
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
  // SAVE TO STORAGE — writes the cached content
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
      debugPrint('💾 [NotifBackup] Save storage error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST BACKUPS — laging 1 file lang
  // ═══════════════════════════════════════════════════════════════
  Future<List<NotificationBackupInfo>> listBackups() async {
    await _loadCache();
    final content = _cachedContent ?? '';
    if (content.isEmpty) return [];

    final savedAt = await _getFileModifiedTime();

    return [
      NotificationBackupInfo(
        filename: _singleFileName,
        path: kIsWeb ? 'web://$_singleFileName' : await _getFilePath(),
        savedAt: savedAt,
        sizeBytes: content.length,
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

  // ═══════════════════════════════════════════════════════════════
  // READ
  // ═══════════════════════════════════════════════════════════════
  Future<String?> readBackup(String path) async {
    await _loadCache();
    return _cachedContent;
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE — clear the single file
  // ═══════════════════════════════════════════════════════════════
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
        return had ? 1 : 0;
      } else {
        final path = await _getFilePath();
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          _cachedContent = '';
          debugPrint('🗑️ [NotifBackup] Deleted single file');
          return 1;
        }
        _cachedContent = '';
        return 0;
      }
    } catch (e) {
      debugPrint('💾 [NotifBackup] Delete error: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // TOTAL SIZE
  // ═══════════════════════════════════════════════════════════════
  Future<int> getTotalSize() async {
    final files = await listBackups();
    return files.fold<int>(0, (sum, f) => sum + f.sizeBytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // BACKUP DIRECTORY
  // ═══════════════════════════════════════════════════════════════
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

  const NotificationBackupInfo({
    required this.filename,
    required this.path,
    required this.savedAt,
    required this.sizeBytes,
  });
}