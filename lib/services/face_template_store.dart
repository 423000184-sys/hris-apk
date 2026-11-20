// lib/services/face_template_store.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores enrolled face templates in the Android Keystore-backed store.
/// Templates are biometric data: never upload or log them.
class FaceTemplateStore {
  FaceTemplateStore._();
  static final instance = FaceTemplateStore._();
  static const int version = 1;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _key(String id) => 'secure_face_v${version}_$id';

  Future<void> save(String id, List<Float32List> embeddings) async {
    final enc = embeddings
        .map((e) => base64Encode(e.buffer.asUint8List(e.offsetInBytes, e.lengthInBytes)))
        .toList();
    await _storage.write(key: _key(id), value: jsonEncode({'v': version, 'e': enc}));
  }

  Future<List<Float32List>> load(String id) async {
    try {
      final raw = await _storage.read(key: _key(id));
      if (raw == null) {
        if (kDebugMode) debugPrint('🗂️ Template: NONE for $id');
        return const [];
      }
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (kDebugMode) {
        debugPrint('🗂️ Template: ${(map['e'] as List).length} embeddings for $id');
      }
      if (map['v'] != version) return const [];
      return (map['e'] as List).map((s) {
        final bytes = base64Decode(s as String);
        return Float32List.fromList(Float32List.view(bytes.buffer));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Naghihiwalay ng "walang template" (items walang laman, unreadable=false)
  /// at "hindi mabasa" (corrupted, ibang version, o nag-error ang Keystore).
  Future<({List<Float32List> items, bool unreadable})> loadChecked(
      String id) async {
    try {
      final raw = await _storage.read(key: _key(id));
      if (raw == null) return (items: <Float32List>[], unreadable: false);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != version) {
        return (items: <Float32List>[], unreadable: true);
      }
      final items = (map['e'] as List).map((s) {
        final bytes = base64Decode(s as String);
        return Float32List.fromList(Float32List.view(bytes.buffer));
      }).toList();
      if (items.isEmpty) return (items: <Float32List>[], unreadable: true);
      return (items: items, unreadable: false);
    } catch (_) {
      return (items: <Float32List>[], unreadable: true);
    }
  }

  Future<void> delete(String id) => _storage.delete(key: _key(id));
}