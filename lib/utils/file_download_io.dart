// lib/utils/file_download_io.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// ══════════════════════════════════════════════════════════════
// 📝 Save text file (CSV, JSON, TXT, etc.)
// ══════════════════════════════════════════════════════════════
Future<String?> downloadTextFile({
  required String filename,
  required String content,
}) async {
  try {
    final targetDir = await _resolveTargetDir();
    final file = File('${targetDir.path}/$filename');
    await file.writeAsString(content, flush: true);
    debugPrint('💾 [Download] Text saved to: ${file.path}');
    return file.path;
  } catch (e) {
    debugPrint('❌ [Download] io text error: $e');
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// 📦 Save bytes file (PDF, image, zip, etc.)
// ══════════════════════════════════════════════════════════════
Future<String?> downloadBytesFile({
  required String filename,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    final targetDir = await _resolveTargetDir();
    final file = File('${targetDir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('💾 [Download] Bytes saved to: ${file.path}');
    return file.path;
  } catch (e) {
    debugPrint('❌ [Download] io bytes error: $e');
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// 🔧 Resolve target directory — Downloads/RACOMA_Backups
//    Falls back to Documents kung walang Downloads folder.
// ══════════════════════════════════════════════════════════════
Future<Directory> _resolveTargetDir() async {
  Directory? baseDir;
  try {
    baseDir = await getDownloadsDirectory();
  } catch (_) {}
  baseDir ??= await getApplicationDocumentsDirectory();

  final targetDir = Directory('${baseDir.path}/RACOMA_Backups');
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }
  return targetDir;
}