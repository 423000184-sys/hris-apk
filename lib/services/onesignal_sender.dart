// lib/services/onesignal_sender.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OneSignalSender {
  OneSignalSender._();
  static final OneSignalSender instance = OneSignalSender._();

  // ⚠️ SECURITY: Huwag i-hardcode ang API key.
  // Ilagay sa --dart-define o environment variable.
  // Example run: flutter run --dart-define=ONESIGNAL_REST_API_KEY=os_v2_app_xxxxx
  static const String _restApiKey =
  String.fromEnvironment('ONESIGNAL_REST_API_KEY', defaultValue: '');

  static const String _appId = '0c862ae2-7ee8-46db-8f9e-6740e82c065c';

  static final Uri _endpoint =
  Uri.parse('https://api.onesignal.com/notifications');

  Future<bool> sendToEmployee({
    required String employeeId,
    required String title,
    required String message,
    String type = 'general',
  }) async {
    return _send(
      title: title,
      message: message,
      type: type,
      includeAliases: {
        'external_id': [employeeId],
      },
    );
  }

  Future<bool> sendToAll({
    required String title,
    required String message,
    String type = 'general',
  }) async {
    return _send(
      title: title,
      message: message,
      type: type,
      includedSegments: ['Subscribed Users'],
    );
  }

  Future<bool> _send({
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? includeAliases,
    List<String>? includedSegments,
  }) async {
    if (_restApiKey.isEmpty) {
      debugPrint('❌ [OneSignal] REST API key is missing. '
          'Pass it via --dart-define=ONESIGNAL_REST_API_KEY=...');
      return false;
    }

    try {
      final payload = <String, dynamic>{
        'app_id': _appId,
        'headings': {'en': title},
        'contents': {'en': message},
        'data': {'type': type},
        'priority': 10,
        'sound': 'default',
        'android_sound': 'default',
        'ios_sound': 'default',
      };

      if (includeAliases != null) {
        payload['include_aliases'] = includeAliases;
        payload['target_channel'] = 'push';
      } else if (includedSegments != null) {
        payload['included_segments'] = includedSegments;
      }

      debugPrint('📤 [OneSignal] Send → ${includeAliases ?? includedSegments}');

      final res = await http.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Key $_restApiKey',
        },
        body: jsonEncode(payload),
      );

      debugPrint('📤 [OneSignal] Status: ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [OneSignal] Error: $e');
      return false;
    }
  }
}