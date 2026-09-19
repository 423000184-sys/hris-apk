// lib/services/presence_backup_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'network_guard.dart';

/// 💾 Presence Backup Service — LOCAL DEVICE ONLY
///
/// Flow:
///   1. Generate .txt file with presence data
///   2. Save sa device (Documents/presence_backups/)
///   3. Auto-delete files older than retentionDays (default 30)
class PresenceBackupService {
  PresenceBackupService._();
  static final instance = PresenceBackupService._();

  static const String _localFolder = 'presence_backups';
  static const int retentionDays = 30;

  // ═══════════════════════════════════════════════════════════════
  // MAIN — generate local backup
  // ═══════════════════════════════════════════════════════════════
  Future<BackupResult> generateBackup({
    required String employeeId,
    required String employeeName,
    required String zone,
    required double distanceMeters,
    double? accuracyMeters,
    int? checkCount,
  }) async {
    try {
      final now = DateTime.now();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'presence_${employeeId}_$timestamp.txt';

      // Build .txt content
      final content = _buildTxtContent(
        employeeId: employeeId,
        employeeName: employeeName,
        zone: zone,
        distanceMeters: distanceMeters,
        accuracyMeters: accuracyMeters,
        checkCount: checkCount,
        now: now,
      );

      // Save locally
      final localPath = await _saveLocal(
        filename: filename,
        content: content,
      );
      debugPrint('💾 [Backup] Local saved: $localPath');

      // Cleanup old files
      await _cleanupOldLocalFiles();

      return BackupResult(
        success: true,
        localPath: localPath,
        filename: filename,
        savedAt: now,
      );
    } catch (e, st) {
      debugPrint('❌ [Backup] Generate failed: $e');
      debugPrint('$st');
      return BackupResult(success: false, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD TXT CONTENT
  // ═══════════════════════════════════════════════════════════════
  String _buildTxtContent({
    required String employeeId,
    required String employeeName,
    required String zone,
    required double distanceMeters,
    double? accuracyMeters,
    int? checkCount,
    required DateTime now,
  }) {
    final inRange = zone == 'inside';
    final statusEmoji = inRange ? '🟢' : '🔴';
    final statusText = inRange ? 'IN RANGE' : 'OUT OF RANGE';

    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('🛰️  PRESENCE BACKUP SNAPSHOT');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('Generated : ${DateFormat('yyyy-MM-dd HH:mm:ss').format(now)}');
    buf.writeln('Timezone  : ${now.timeZoneName}');
    buf.writeln('');
    buf.writeln('─── EMPLOYEE ────────────────────────────────');
    buf.writeln('ID        : $employeeId');
    buf.writeln('Name      : $employeeName');
    buf.writeln('');
    buf.writeln('─── STATUS ──────────────────────────────────');
    buf.writeln('Status    : $statusEmoji $statusText');
    buf.writeln('Zone      : $zone');
    buf.writeln(
        'Distance  : ${distanceMeters.toStringAsFixed(1)} m from office');
    if (accuracyMeters != null) {
      buf.writeln('Accuracy  : ±${accuracyMeters.toStringAsFixed(0)} m');
    }
    if (checkCount != null) {
      buf.writeln('Check #   : $checkCount');
    }
    buf.writeln('Online    : ${NetworkGuard.instance.isOnline}');
    buf.writeln('');
    buf.writeln('─── METADATA ────────────────────────────────');
    buf.writeln('Backup ID : ${DateFormat('yyyyMMdd_HH').format(now)}');
    buf.writeln('Source    : HRIS Biometrics App');
    buf.writeln('Storage   : Local Device Only');
    buf.writeln('Version   : 1.0.2+3');
    buf.writeln('');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('END OF SNAPSHOT');
    buf.writeln('═══════════════════════════════════════════════');

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // SAVE LOCALLY
  // ═══════════════════════════════════════════════════════════════
  Future<String> _saveLocal({
    required String filename,
    required String content,
  }) async {
    // Web: hindi supported ang file system
    if (kIsWeb) {
      throw Exception(
        'Local backup is not supported on web. Use a mobile device.',
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, _localFolder));

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final file = File(p.join(backupDir.path, filename));
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  // ═══════════════════════════════════════════════════════════════
  // CLEANUP — files older than retentionDays
  // ═══════════════════════════════════════════════════════════════
  Future<int> _cleanupOldLocalFiles() async {
    if (kIsWeb) return 0;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, _localFolder));

      if (!await backupDir.exists()) return 0;

      final cutoff =
      DateTime.now().subtract(const Duration(days: retentionDays));
      int deleted = 0;

      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
            deleted++;
          }
        }
      }

      if (deleted > 0) {
        debugPrint('🧹 [Backup] Deleted $deleted old local files');
      }
      return deleted;
    } catch (e) {
      debugPrint('⚠️ [Backup] Local cleanup failed: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST BACKUPS
  // ═══════════════════════════════════════════════════════════════
  Future<List<BackupFileInfo>> listLocalBackups() async {
    if (kIsWeb) return [];

    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, _localFolder));
      if (!await backupDir.exists()) return [];

      final files = <BackupFileInfo>[];
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          final stat = await entity.stat();
          files.add(BackupFileInfo(
            filename: p.basename(entity.path),
            path: entity.path,
            savedAt: stat.modified,
            sizeBytes: stat.size,
          ));
        }
      }
      files.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return files;
    } catch (e) {
      debugPrint('⚠️ [Backup] listLocalBackups failed: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // READ FILE CONTENT
  // ═══════════════════════════════════════════════════════════════
  Future<String?> readBackup(String path) async {
    if (kIsWeb) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (e) {
      debugPrint('⚠️ [Backup] readBackup failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE SINGLE FILE
  // ═══════════════════════════════════════════════════════════════
  Future<bool> deleteBackup(String path) async {
    if (kIsWeb) return false;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ [Backup] Deleted: $path');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('⚠️ [Backup] deleteBackup failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE ALL BACKUPS
  // ═══════════════════════════════════════════════════════════════
  Future<int> deleteAllBackups() async {
    if (kIsWeb) return 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, _localFolder));
      if (!await backupDir.exists()) return 0;

      int deleted = 0;
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          await entity.delete();
          deleted++;
        }
      }
      debugPrint('🗑️ [Backup] Deleted ALL ($deleted files)');
      return deleted;
    } catch (e) {
      debugPrint('⚠️ [Backup] deleteAllBackups failed: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GET BACKUP DIRECTORY PATH (para sa info display)
  // ═══════════════════════════════════════════════════════════════
  Future<String> getBackupDirectory() async {
    if (kIsWeb) return 'Web: not supported';
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _localFolder);
  }

  // ═══════════════════════════════════════════════════════════════
  // TOTAL SIZE
  // ═══════════════════════════════════════════════════════════════
  Future<int> getTotalSizeBytes() async {
    if (kIsWeb) return 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, _localFolder));
      if (!await backupDir.exists()) return 0;

      int total = 0;
      await for (final entity in backupDir.list()) {
        if (entity is File && entity.path.endsWith('.txt')) {
          final stat = await entity.stat();
          total += stat.size;
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════
class BackupResult {
  final bool success;
  final String? localPath;
  final String? filename;
  final DateTime? savedAt;
  final String? error;

  const BackupResult({
    required this.success,
    this.localPath,
    this.filename,
    this.savedAt,
    this.error,
  });
}

class BackupFileInfo {
  final String filename;
  final String path;
  final DateTime savedAt;
  final int sizeBytes;

  const BackupFileInfo({
    required this.filename,
    required this.path,
    required this.savedAt,
    required this.sizeBytes,
  });
}