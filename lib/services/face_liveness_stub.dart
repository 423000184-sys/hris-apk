// lib/services/face_liveness_stub.dart
//
// Stub for non-web platforms. Native uses google_mlkit_face_detection.

class FaceLivenessResult {
  final bool facePresent;
  final double eyeOpenScore;
  final double smileScore;

  FaceLivenessResult({
    required this.facePresent,
    this.eyeOpenScore = 1.0,
    this.smileScore = 0.0,
  });
}

class FaceLivenessService {
  Future<FaceLivenessResult?> detect(dynamic videoElement) async => null;

  dynamic getVideoElement() => null;
}