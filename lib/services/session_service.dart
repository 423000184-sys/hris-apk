// lib/services/session_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Secure session helper. Tokens live in Keychain (iOS) / Keystore (Android).
///
/// The client NEVER decides if a session is valid. It only asks the server
/// and caches the *existence* of a token locally.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const _kAccessKey = 'rac_session_access_v1';
  static const _kRefreshKey = 'rac_session_refresh_v1';

  /// ⚠️ Palitan ng totoong API base URL.
  static const String _apiBase = 'https://api.yourdomain.com';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<void> save({required String access, String? refresh}) async {
    try {
      await _storage.write(key: _kAccessKey, value: access);
      if (refresh != null) {
        await _storage.write(key: _kRefreshKey, value: refresh);
      }
    } catch (_) {}
  }

  Future<String?> get accessToken => _storage.read(key: _kAccessKey);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshKey);

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kAccessKey);
      await _storage.delete(key: _kRefreshKey);
    } catch (_) {}
  }

  Future<bool> hasLocalSession() async {
    try {
      final t = await _storage.read(key: _kAccessKey);
      return t != null && t.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Server-verified. On 401, tries refresh once. On failure, clears.
  Future<bool> verifyAndRefresh() async {
    final access = await _storage.read(key: _kAccessKey);
    if (access == null || access.isEmpty) return false;

    try {
      final ok = await _ping('/auth/me', access);
      if (ok) return true;

      final refresh = await _storage.read(key: _kRefreshKey);
      if (refresh == null || refresh.isEmpty) {
        await clear();
        return false;
      }

      final newAccess = await _tryRefresh(refresh);
      if (newAccess == null) {
        await clear();
        return false;
      }
      await _storage.write(key: _kAccessKey, value: newAccess);
      return true;
    } catch (e) {
      assert(() {
        debugPrint('verifyAndRefresh error: $e');
        return true;
      }());
      return false;
    }
  }

  Future<bool> _ping(String path, String token) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _tryRefresh(String refresh) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['access_token'] as String?;
    } catch (_) {
      return null;
    }
  }
}