// lib/utils/file_download_stub.dart
import 'package:flutter/foundation.dart';

Future<String?> downloadTextFile({
  required String filename,
  required String content,
}) async {
  return null;
}

Future<String?> downloadBytesFile({
  required String filename,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  return null;
}