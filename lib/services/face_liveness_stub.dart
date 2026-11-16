// lib/services/face_liveness_stub.dart

class FaceLivenessService {
  FaceLivenessService();

  Future<void> init() async {}

  bool check(dynamic image) => false;

  dynamic getVideoElement() => null;
  Future<dynamic> detect(dynamic videoEl) async => null;
}