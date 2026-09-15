// lib/services/webauthn_service_web.dart
import 'dart:js' as js;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WebAuthnService {
  // ✅ Supabase Project URL
  static const String supabaseUrl =
      "https://xrmzgzlpbybscudpszhk.supabase.co/functions/v1";

  // ✅ Supabase Anon Key (publishable)
  static const String supabaseAnonKey =
      "sb_publishable_fYGWAqPTKT9sPlKIUzUrcQ_CEzgez9r";

  Future<Map<String, String>> _headers() async {
    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $supabaseAnonKey",
      "apikey": supabaseAnonKey,
    };
  }

  // 1. PARA SA REGISTRATION (Unang beses mag-e-enroll)
  Future<void> registerBiometrics(String employeeId,
      {String deviceLabel = "Web Browser"}) async {
    if (!kIsWeb) throw Exception("WebAuthn is only for Web");

    final optionsResponse = await http.post(
      Uri.parse("$supabaseUrl/webauthn-generate-registration-options"),
      headers: await _headers(),
      body: jsonEncode({"employeeId": employeeId}),
    );

    if (optionsResponse.statusCode != 200) {
      throw Exception("Failed to get options: ${optionsResponse.body}");
    }

    final options = jsonDecode(optionsResponse.body);
    final optionsJson = jsonEncode(options);

    // ✅ DITO LUMALABAS ANG NATIVE BIOMETRIC PROMPT
    final credential = await js.context.callMethod('eval', [
      'SimpleWebAuthnBrowser.startRegistration($optionsJson)'
    ]);

    final verifyResponse = await http.post(
      Uri.parse("$supabaseUrl/webauthn-verify-registration"),
      headers: await _headers(),
      body: jsonEncode({
        "employeeId": employeeId,
        "credential": credential,
        "deviceLabel": deviceLabel,
      }),
    );

    if (verifyResponse.statusCode != 200) {
      throw Exception("Verification failed: ${verifyResponse.body}");
    }
  }

  // 2. PARA SA AUTHENTICATION (Tuwing mag-c-clock in)
  Future<bool> authenticateBiometrics(String employeeId) async {
    if (!kIsWeb) throw Exception("WebAuthn is only for Web");

    final optionsResponse = await http.post(
      Uri.parse("$supabaseUrl/webauthn-generate-auth-options"),
      headers: await _headers(),
      body: jsonEncode({"employeeId": employeeId}),
    );

    if (optionsResponse.statusCode != 200) {
      throw Exception("Failed to get options: ${optionsResponse.body}");
    }

    final options = jsonDecode(optionsResponse.body);
    final optionsJson = jsonEncode(options);

    // ✅ DITO LUMALABAS ANG NATIVE BIOMETRIC PROMPT
    final credential = await js.context.callMethod('eval', [
      'SimpleWebAuthnBrowser.startAuthentication($optionsJson)'
    ]);

    final verifyResponse = await http.post(
      Uri.parse("$supabaseUrl/webauthn-verify-auth"),
      headers: await _headers(),
      body: jsonEncode({
        "employeeId": employeeId,
        "credential": credential,
      }),
    );

    if (verifyResponse.statusCode != 200) {
      return false;
    }

    final result = jsonDecode(verifyResponse.body);
    return result["verified"] == true;
  }
}