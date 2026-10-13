// lib/services/face_matcher_web.dart
//
// 🌐 WEB STUB — API-compatible, walang native deps.
// Hindi ito nag-i-import ng tflite_flutter o dart:ffi.

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

// ═══════════════════════════════════════════════════════════════
// RESULT CLASSES — dapat pareho sa native
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

class FaceMatcher {
  static const double defaultThreshold = 0.65;

  static Future<List<double>> generateEmbedding(
      Uint8List imageBytes, {
        bool enableAlignment = true,
      }) async {
    _secureLog('⛔ FaceMatcher.generateEmbedding: unsupported on web');
    return <double>[];
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  static Future<FaceVerifyResult> verify(
      String employeeId,
      Uint8List liveImageBytes, {
        double threshold = defaultThreshold,
        bool allowLegacy = false,
        bool enableSelfHeal = true,
      }) async {
    _secureLog('⛔ FaceMatcher.verify: unsupported on web');
    return const FaceVerifyResult(
      score: 0,
      matched: false,
      hasEmbedding: false,
      error: 'Face verification is only available on the mobile app. '
          'Please use your phone or contact your administrator.',
    );
  }

  static Future<void> saveEmbedding(
      String employeeId,
      List<double> embedding, {
        String? source,
      }) async {
    _secureLog('⛔ FaceMatcher.saveEmbedding: unsupported on web');
  }

  // 🆕 Idinagdag para sa screen
  static Future<EnrollResult> enrollFace(
      String employeeId,
      Uint8List imageBytes, {
        String source = 'mobile_enrollment',
      }) async {
    _secureLog('⛔ FaceMatcher.enrollFace: unsupported on web');
    return const EnrollResult(
      success: false,
      error: 'Face enrollment is not available on web. '
          'Please use the mobile app.',
    );
  }

  // 🆕 Idinagdag para sa screen
  static Future<bool> hasRegisteredFace(String employeeId) async {
    _secureLog('⛔ FaceMatcher.hasRegisteredFace: unsupported on web');
    return false;
  }

  static Future<List<List<double>>> loadAllEmbeddings(
      String employeeId) async => <List<double>>[];

  static Future<bool> autoUpgradeFromImage(
      String employeeId,
      Uint8List imageBytes, {
        String source = 'upload',
        bool onlyIfNotV4 = false,
      }) async => false;

  static Future<bool> autoUpgradeFromExistingPhoto(String employeeId) async =>
      false;

  static Future<String?> uploadEmployeePhoto(
      String employeeId,
      Uint8List imageBytes, {
        bool autoUpgradeFace = true,
      }) async => null;

  static Future<bool> deleteEmployeePhoto(String employeeId) async => false;

  static Future<void> clearAllEmbeddings(String employeeId) async {
    _secureLog('⛔ FaceMatcher.clearAllEmbeddings: unsupported on web');
  }

  static Future<Map<String, dynamic>> debugTemplateStatus(
      String employeeId) async =>
      {'error': 'unsupported_on_web'};
}