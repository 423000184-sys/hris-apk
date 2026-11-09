// lib/utils/file_download_web.dart
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/foundation.dart';

// ══════════════════════════════════════════════════════════════
// 📝 Save text file → browser auto-download
// ══════════════════════════════════════════════════════════════
Future<String?> downloadTextFile({
  required String filename,
  required String content,
}) async {
  try {
    final bytes = utf8.encode(content);
    return _triggerBrowserDownload(
      bytes: bytes,
      filename: filename,
      mimeType: 'text/plain;charset=utf-8',
    );
  } catch (e) {
    debugPrint('❌ [Download] web text error: $e');
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// 📦 Save bytes file → browser auto-download
// ══════════════════════════════════════════════════════════════
Future<String?> downloadBytesFile({
  required String filename,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  try {
    return _triggerBrowserDownload(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
  } catch (e) {
    debugPrint('❌ [Download] web bytes error: $e');
    return null;
  }
}

// ══════════════════════════════════════════════════════════════
// 🔧 Trigger browser download via Blob + anchor click
// ══════════════════════════════════════════════════════════════
String? _triggerBrowserDownload({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);

  debugPrint('💾 [Download] Browser download: $filename');
  return filename;
}