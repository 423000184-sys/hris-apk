// lib/services/face_template_store.dart
import 'dart:convert';
import 'dart:typed_data';
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
      if (raw == null) return const [];
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != version) return const [];
      return (map['e'] as List).map((s) {
        final bytes = base64Decode(s as String);
        return Float32List.fromList(Float32List.view(bytes.buffer));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> delete(String id) => _storage.delete(key: _key(id));
}