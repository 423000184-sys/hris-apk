// lib/services/webauthn_service_stub.dart
class NoCredentialException implements Exception {
  final String message;
  NoCredentialException([this.message = 'No registered credential found']);
  @override
  String toString() => message;
}

class WebAuthnService {
  static const String supabaseUrl =
      "https://xrmzgzlpbybscudpszhk.supabase.co/functions/v1";

  static const String supabaseAnonKey =
      "sb_publishable_fYGWAqPTKT9sPlKIUzUrcQ_CEzgez9r";

  Future<void> registerBiometrics(
      String employeeId, {
        String deviceLabel = "Web Browser",
      }) async {
    throw UnsupportedError(
      'WebAuthn (registerBiometrics) is only available on Web platform. '
          'Sa mobile, gamitin ang local_auth biometrics o facial recognition.',
    );
  }

  Future<bool> authenticateBiometrics(String employeeId) async {
    throw UnsupportedError(
      'WebAuthn (authenticateBiometrics) is only available on Web platform. '
          'Sa mobile, gamitin ang local_auth biometrics o facial recognition.',
    );
  }
}