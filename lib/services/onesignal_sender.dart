// lib/services/onesignal_sender.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OneSignalSender {
  OneSignalSender._();
  static final OneSignalSender instance = OneSignalSender._();

  // ✅ DITO NAKA-SAVE ANG API KEY PARA GUMANA AGAD
  static const String _restApiKey =
      'os_v2_app_bsdcvyt65bdnxd46m5aoqlaglr35xo6jvfcew74hy2hgqnjnmgthy4gdtw3llfdwtusxeydyl3gfgv6lkcl5kceog6bgvgg37w7vh6q';

  static const String _appId = '0c862ae2-7ee8-46db-8f9e-6740e82c065c';

  static final Uri _endpoint =
  Uri.parse('https://api.onesignal.com/notifications');

  /// Ipadala ang notification sa isang specific employee.
  Future<bool> sendToEmployee({
    required String employeeId,
    required String title,
    required String message,
    String type = 'general',
  }) async {
    if (employeeId.trim().isEmpty) {
      debugPrint('❌ [OneSignal] Employee ID is empty. Cannot send.');
      return false;
    }

    return _send(
      title: title,
      message: message,
      type: type,
      includeAliases: {
        'external_id': [employeeId.trim()],
      },
    );
  }

  /// Ipadala ang notification sa LAHAT ng naka-install na app.
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
      debugPrint('❌ [OneSignal] REST API key is missing.');
      return false;
    }

    try {
      final payload = <String, dynamic>{
        'app_id': _appId,
        'headings': {'en': title},
        'contents': {'en': message},
        'data': {
          'type': type,
          'route': 'notifications',
        },
        'priority': 10,
        'sound': 'default',
        'android_sound': 'default',
        'ios_sound': 'default',
        'ios_badgeType': 'Increase',
        'ios_badgeCount': 1,
      };

      if (includeAliases != null) {
        payload['include_aliases'] = includeAliases;
        payload['target_channel'] = 'push';
      } else if (includedSegments != null) {
        payload['included_segments'] = includedSegments;
      }

      debugPrint('📤 [OneSignal] Sending to → ${includeAliases ?? includedSegments}');

      final res = await http.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Key $_restApiKey',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        final responseData = jsonDecode(res.body);
        final recipients = responseData['recipients'] ?? 0;
        debugPrint('✅ [OneSignal] Success! Recipients: $recipients');

        if (recipients == 0) {
          debugPrint('⚠️ [OneSignal] No devices received the push. Make sure the employee app is logged in on a real phone.');
        }

        return true;
      } else {
        debugPrint('❌ [OneSignal] Failed with status ${res.statusCode}');
        debugPrint('❌ [OneSignal] Response: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [OneSignal] Error: $e');
      return false;
    }
  }
}