// lib/services/auth_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

/// All auth-critical operations go through the server.
/// The client NEVER decides "this PIN is valid" on its own.
class AuthApiService {
  AuthApiService._();
  static final AuthApiService instance = AuthApiService._();

  static const String _base = 'https://api.yourdomain.com';
  static const Duration _timeout = Duration(seconds: 10);

  /// Server verifies PIN with rate limiting + lockout. Returns either
  /// a session payload or a failure reason. Never returns the raw PIN.
  Future<Map<String, dynamic>> verifyPin({
    required String pin,
    required String deviceId,
    required String sessionNonce,
  }) async {
    final res = await http
        .post(
      Uri.parse('$_base/auth/verify-pin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pin': pin,
        'device_id': deviceId,
        'session_nonce': sessionNonce,
      }),
    )
        .timeout(_timeout);

    final body = _safeJson(res.body);
    return {
      'ok': res.statusCode == 200 && body['ok'] == true,
      'status': res.statusCode,
      'error': body['error'],
      'remaining_attempts': body['remaining_attempts'],
      'lockout_until': body['lockout_until'],
      'employee': body['employee'],
      'access_token': body['access_token'],
      'refresh_token': body['refresh_token'],
    };
  }

  /// Server verifies NFC tag and issues a session.
  Future<Map<String, dynamic>> verifyNfc({
    required String tagId,
    required String deviceId,
    required String sessionNonce,
  }) async {
    final res = await http
        .post(
      Uri.parse('$_base/auth/verify-nfc'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tag_id': tagId,
        'device_id': deviceId,
        'session_nonce': sessionNonce,
      }),
    )
        .timeout(_timeout);

    final body = _safeJson(res.body);
    return {
      'ok': res.statusCode == 200 && body['ok'] == true,
      'employee': body['employee'],
      'access_token': body['access_token'],
      'error': body['error'],
    };
  }

  /// Server-side presence update. Client cannot write own status/isOnline.
  Future<void> markPresence({
    required String accessToken,
    required String state, // 'online' | 'offline' | 'client_meeting'
  }) async {
    await http
        .post(
      Uri.parse('$_base/presence'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'state': state}),
    )
        .timeout(_timeout);
  }

  /// Server-attributed security log. Client cannot forge entries.
  Future<void> logSecurityEvent({
    required String accessToken,
    required String type,
    required String severity,
    required String details,
    String? employeeId,
  }) async {
    await http
        .post(
      Uri.parse('$_base/security/log'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'type': type,
        'severity': severity,
        'details': details,
        'employee_id': employeeId,
      }),
    )
        .timeout(_timeout);
  }

  Map<String, dynamic> _safeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }
}