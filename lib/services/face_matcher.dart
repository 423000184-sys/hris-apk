// lib/services/face_matcher.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Simple face embedding generator + comparator.
/// Extracts pixel-based signature from a face crop.
/// NOT production-grade — enough for demo, school projects, and basic verification.
class FaceMatcher {
  /// Embedding is N x N grayscale values (normalized 0..1)
  static const int _embeddingSize = 32;

  /// Default similarity threshold (0..1). Higher = stricter.
  static const double defaultThreshold = 0.85;

  // ───────────────────────────────────────────────────────────────────
  // EMBEDDING GENERATION
  // ───────────────────────────────────────────────────────────────────

  /// Generate embedding from raw image bytes.
  /// Returns list of N*N doubles (0..1), or empty on failure.
  static Future<List<double>> generateEmbedding(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        debugPrint('⚠️ Could not decode image');
        return [];
      }

      final resized = img.copyResize(
        decoded,
        width: _embeddingSize,
        height: _embeddingSize,
        interpolation: img.Interpolation.average,
      );

      final embedding = <double>[];
      for (int y = 0; y < _embeddingSize; y++) {
        for (int x = 0; x < _embeddingSize; x++) {
          final p = resized.getPixel(x, y);
          // Weighted grayscale (luminance)
          final gray = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
          embedding.add(gray / 255.0);
        }
      }

      debugPrint('✅ Embedding generated: ${embedding.length} values');
      return embedding;
    } catch (e) {
      debugPrint('❌ generateEmbedding error: $e');
      return [];
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // SIMILARITY
  // ───────────────────────────────────────────────────────────────────

  /// Compute similarity between two embeddings (0..1).
  /// 1.0 = identical, 0.0 = completely different.
  static double similarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

    double sumDiff = 0.0;
    for (int i = 0; i < a.length; i++) {
      sumDiff += (a[i] - b[i]).abs();
    }

    final avgDiff = sumDiff / a.length;
    // avgDiff 0 → similarity 1.0
    // avgDiff 0.5+ → similarity 0.0
    return (1.0 - (avgDiff * 2)).clamp(0.0, 1.0);
  }

  // ───────────────────────────────────────────────────────────────────
  // PERSISTENCE (Firestore)
  // ───────────────────────────────────────────────────────────────────

  /// Save embedding to employee document in Firestore.
  static Future<void> saveEmbedding(
      String employeeId,
      List<double> embedding,
      ) async {
    await FirebaseFirestore.instance
        .collection('employees')
        .doc(employeeId)
        .update({
      'faceEmbedding': embedding,
      'faceEmbeddingSize': _embeddingSize,
      'faceEmbeddingUpdatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ Embedding saved to Firestore for $employeeId');
  }

  /// Load embedding from employee document.
  static Future<List<double>?> loadEmbedding(String employeeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get();

      final data = doc.data();
      if (data == null) return null;

      final raw = data['faceEmbedding'];
      if (raw is! List) return null;

      return raw.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      debugPrint('⚠️ loadEmbedding error: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // PHOTO UPLOAD (Firebase Storage)
  // ───────────────────────────────────────────────────────────────────

  /// Upload employee photo to Firebase Storage.
  /// Returns download URL, or null if failed.
  static Future<String?> uploadEmployeePhoto(
      String employeeId,
      Uint8List imageBytes,
      ) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('employee_photos')
          .child('$employeeId.jpg');

      await ref.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await ref.getDownloadURL();
      debugPrint('✅ Photo uploaded: $url');
      return url;
    } catch (e) {
      debugPrint('⚠️ Photo upload failed: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // VERIFICATION
  // ───────────────────────────────────────────────────────────────────

  /// Verify live face against stored embedding for given employee.
  static Future<FaceVerifyResult> verify(
      String employeeId,
      Uint8List liveImageBytes, {
        double threshold = defaultThreshold,
      }) async {
    final stored = await loadEmbedding(employeeId);
    if (stored == null || stored.isEmpty) {
      return const FaceVerifyResult(
        score: 0,
        matched: false,
        hasEmbedding: false,
        error: 'No face registered for this employee.',
      );
    }

    final live = await generateEmbedding(liveImageBytes);
    if (live.isEmpty) {
      return const FaceVerifyResult(
        score: 0,
        matched: false,
        hasEmbedding: true,
        error: 'Could not extract face from live image.',
      );
    }

    final score = similarity(stored, live);
    return FaceVerifyResult(
      score: score,
      matched: score >= threshold,
      hasEmbedding: true,
      error: null,
    );
  }
}

class FaceVerifyResult {
  final double score;
  final bool matched;
  final bool hasEmbedding;
  final String? error;

  const FaceVerifyResult({
    required this.score,
    required this.matched,
    required this.hasEmbedding,
    this.error,
  });
}