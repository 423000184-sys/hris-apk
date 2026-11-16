// lib/services/face_liveness_native.dart
// (Ito ay temporary para hindi mag-error. I-paste mo dito yung totoong code mo later)

class FaceLivenessService {
  FaceLivenessService();

  Future<void> init() async {}

  bool check(dynamic image) => false;

  // Inilagay na rin natin dito para walang error sa mobile build
  dynamic getVideoElement() => null;
  Future<dynamic> detect(dynamic videoEl) async => null;
}