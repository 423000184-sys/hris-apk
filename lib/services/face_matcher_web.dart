// lib/services/face_matcher_web.dart
//
// 🌐 WEB STUB — compile-safe placeholder for web builds
//
// Ang tflite_flutter + google_mlkit_face_detection ay hindi tumatakbo sa
// browser. Return safe defaults (always-unmatched) para hindi mag-crash.
// Face login/verify sa web ay hindi supported — use PIN muna.
//
// Same public API as face_matcher_native.dart para mag-compile ang shared
// UI code (facial_recognition_screen.dart, admin enrollment pages, etc.).

import 'dart:typed_data';

class FaceMatcher {
  static const int _embeddingSize = 192;
  static const double defaultThreshold = 0.92;

  // ─── Embedding generation ─────────────────────────────────────
  static Future<List<double>> generateEmbedding(
    Uint8List imageBytes, {
    bool enableAlignment = true,
  }) async {
    return <double>[];
  }

  // ─── Main verify ──────────────────────────────────────────────
  static Future<FaceVerifyResult> verify(
    String employeeId,
    Uint8List liveImageBytes, {
    double threshold = defaultThreshold,
    bool allowLegacy = false,
    bool enableSelfHeal = true,
  }) async {
    return const FaceVerifyResult(
      score: 0,
      matched: false,
      hasEmbedding: false,
      error: 'Face verification is not available on web. Please use PIN.',
    );
  }

  // ─── Enroll ───────────────────────────────────────────────────
  static Future<EnrollResult> enrollFace(
    String employeeId,
    Uint8List imageBytes, {
    String source = 'web',
  }) async {
    return const EnrollResult(
      success: false,
      error: 'Face enrollment is not available on web.',
    );
  }

  static Future<bool> hasRegisteredFace(String employeeId) async => false;

  static Future<List<List<double>>> loadAllEmbeddings(
      String employeeId) async =>
      const [];

  static Future<bool> autoUpgradeFromImage(
    String employeeId,
    Uint8List imageBytes, {
    String source = 'web',
    bool onlyIfNotV4 = false,
  }) async =>
      false;

  static Future<bool> autoUpgradeFromExistingPhoto(String employeeId) async =>
      false;

  // ─── Photo management ─────────────────────────────────────────
  static Future<String?> uploadEmployeePhoto(
    String employeeId,
    Uint8List imageBytes, {
    bool autoUpgradeFace = true,
  }) async =>
      null;

  static Future<bool> deleteEmployeePhoto(String employeeId) async => false;

  static Future<void> clearAllEmbeddings(String employeeId) async {}

  // ─── Debug ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> debugTemplateStatus(
      String employeeId) async =>
      {'exists': false, 'web': true};

  // ─── Similarity (pure math — safe on web) ─────────────────────
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  static Future<void> saveEmbedding(
    String employeeId,
    List<double> embedding, {
    String? source,
  }) async {}
}

// ═══════════════════════════════════════════════════════════════
// RESULT CLASSES
// ═══════════════════════════════════════════════════════════════
class EnrollResult {
  final bool success;
  final int samplesSoFar;
  final String? error;

  const EnrollResult({
    required this.success,
    this.samplesSoFar = 0,
    this.error,
  });

  @override
  String toString() =>
      'EnrollResult(success: $success, samples: $samplesSoFar, error: $error)';
}

class FaceVerifyResult {
  final double score;
  final bool matched;
  final bool hasEmbedding;
  final bool upgraded;
  final String? error;

  const FaceVerifyResult({
    required this.score,
    required this.matched,
    required this.hasEmbedding,
    this.upgraded = false,
    this.error,
  });

  @override
  String toString() =>
      'FaceVerifyResult(score: ${score.toStringAsFixed(4)}, '
      'matched: $matched, hasEmbedding: $hasEmbedding, '
      'error: $error)';
}