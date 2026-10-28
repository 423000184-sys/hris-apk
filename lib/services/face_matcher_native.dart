// lib/services/face_matcher_native.dart
//
// 📱 NATIVE-ONLY IMPLEMENTATION
//
// Ang file na ito ay KINI-COMPILE LANG sa Android, iOS, Windows,
// macOS, at Linux. HINDI ito dapat i-import nang direkta — gamitin
// ang `face_matcher.dart` (facade) sa halip.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, kDebugMode;
import 'package:flutter_litert/flutter_litert.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

void _secureLog(String message) {
  if (kDebugMode) debugPrint(message);
}

// ═══════════════════════════════════════════════════════════════
// INTERNAL: Embedding load result
// ═══════════════════════════════════════════════════════════════
class _EmbedLoadResult {
  final List<List<double>> embeddings;
  final bool isLegacy;
  final int sourceVersion;

  const _EmbedLoadResult({
    required this.embeddings,
    this.isLegacy = false,
    this.sourceVersion = 0,
  });

  bool get isEmpty => embeddings.isEmpty;
  int get count => embeddings.length;
}

// ═══════════════════════════════════════════════════════════════
// 🆕 ENROLL RESULT CLASS
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

// ═══════════════════════════════════════════════════════════════
// FACE MATCHER
// ═══════════════════════════════════════════════════════════════
class FaceMatcher {
  static const int _embeddingSize = 192;

  static const double defaultThreshold = 0.65;
  static const double _minAcceptableThreshold = 0.60;
  static const int _maxStoredEmbeddings = 5;
  static const int _currentVersion = 4;

  static const double _minEmbeddingValue = -1.5;
  static const double _maxEmbeddingValue = 1.5;
  static const double _cosineCeiling = 0.70;

  static Interpreter? _interpreter;
  static FaceDetector? _faceDetector;
  static bool _isInitialized = false;

  // ═══════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════
  static Future<void> _initModels() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      _secureLog('⛔ Web: FaceMatcher is disabled');
      _isInitialized = true;
      return;
    }

    _interpreter ??=
    await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: true,
        minFaceSize: 0.15,
      ),
    );

    _isInitialized = true;
    _secureLog('✅ TFLite + ML Kit Models loaded');
  }

  // ═══════════════════════════════════════════════════════════════
  // VALIDATION HELPERS
  // ═══════════════════════════════════════════════════════════════
  static bool _isValidEmbedding(List<double> embedding) {
    if (embedding.length != _embeddingSize) return false;
    for (final v in embedding) {
      if (v.isNaN || v.isInfinite) return false;
      if (v < _minEmbeddingValue || v > _maxEmbeddingValue) return false;
    }
    return true;
  }

  static String _hashEmbedding(List<double> embedding) {
    final buffer = ByteData(embedding.length * 8);
    for (int i = 0; i < embedding.length; i++) {
      buffer.setFloat64(i * 8, embedding[i], Endian.little);
    }
    return sha256.convert(buffer.buffer.asUint8List()).toString();
  }

  static String _hashTemplate(List<List<double>> embeddings) {
    final buffer = StringBuffer();
    for (final e in embeddings) {
      buffer.write(_hashEmbedding(e));
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // FACE ALIGNMENT
  // ═══════════════════════════════════════════════════════════════
  static img.Image _alignFace(img.Image src, Face face) {
    try {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];
      if (leftEye == null || rightEye == null) return src;

      final dx = (rightEye.position.x - leftEye.position.x).toDouble();
      final dy = (rightEye.position.y - leftEye.position.y).toDouble();
      final angleRad = math.atan2(dy, dx);
      final angleDeg = -angleRad * 180 / math.pi;

      final rotated = img.copyRotate(src, angle: angleDeg);
      return rotated;
    } catch (e) {
      _secureLog('⚠️ Alignment failed: $e');
      return src;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // EMBEDDING GENERATION
  // ═══════════════════════════════════════════════════════════════
  static Future<List<double>> generateEmbedding(
      Uint8List imageBytes, {
        bool enableAlignment = true,
      }) async {
    if (kIsWeb) {
      _secureLog('⛔ generateEmbedding SKIPPED on web');
      return <double>[];
    }

    try {
      await _initModels();

      if (_interpreter == null || _faceDetector == null) {
        _secureLog('❌ Models not initialized');
        return <double>[];
      }

      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        _secureLog('❌ Could not decode image');
        return <double>[];
      }

      img.Image workingImage = decoded;

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector!.processImage(inputImage);

      try {
        await tempFile.delete();
      } catch (_) {}

      if (faces.isEmpty) {
        _secureLog('❌ No face detected');
        return <double>[];
      }

      final face = faces.first;
      final hasBothEyes = face.landmarks[FaceLandmarkType.leftEye] != null &&
          face.landmarks[FaceLandmarkType.rightEye] != null;
      if (!hasBothEyes) {
        _secureLog('❌ Face landmarks incomplete');
        return <double>[];
      }

      if (enableAlignment) {
        workingImage = _alignFace(decoded, face);
      }

      final rect = face.boundingBox;
      final marginX = rect.width * 0.15;
      final marginY = rect.height * 0.15;

      final cropX =
      (rect.left - marginX).toInt().clamp(0, workingImage.width);
      final cropY =
      (rect.top - marginY).toInt().clamp(0, workingImage.height);
      final cropW = (rect.width + marginX * 2)
          .toInt()
          .clamp(0, workingImage.width - cropX);
      final cropH = (rect.height + marginY * 2)
          .toInt()
          .clamp(0, workingImage.height - cropY);

      if (cropW < 40 || cropH < 40) {
        _secureLog('❌ Face crop too small');
        return <double>[];
      }

      final cropped = img.copyCrop(
        workingImage,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );

      final resized = img.copyResize(
        cropped,
        width: 112,
        height: 112,
        interpolation: img.Interpolation.cubic,
      );

      final input = List.generate(
        1,
            (_) => List.generate(
          112,
              (y) => List.generate(112, (x) {
            final p = resized.getPixel(x, y);
            return <double>[
              (p.r - 127.5) / 128.0,
              (p.g - 127.5) / 128.0,
              (p.b - 127.5) / 128.0,
            ];
          }),
        ),
      );

      // ✅ FIXED: Use nested List (walang .reshape, compatible sa flutter_litert)
      final output = <List<double>>[
        List<double>.filled(_embeddingSize, 0.0),
      ];

      _interpreter!.run(input, output);

      final rawDoubles = output[0];

      double norm = 0.0;
      for (final v in rawDoubles) {
        norm += v * v;
      }
      norm = math.sqrt(norm);
      if (norm == 0) return <double>[];

      final embedding = <double>[];
      for (final v in rawDoubles) {
        embedding.add(v / norm);
      }

      if (!_isValidEmbedding(embedding)) {
        _secureLog('❌ Invalid embedding generated');
        return <double>[];
      }

      _secureLog('✅ Embedding generated: ${embedding.length} dims');
      return embedding;
    } catch (e, st) {
      _secureLog('❌ generateEmbedding error: $e');
      _secureLog('$st');
      return <double>[];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SIMILARITY
  // ═══════════════════════════════════════════════════════════════
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  static double _normalizeScore(double cosine) {
    final clamped = cosine.clamp(0.0, _cosineCeiling);
    return clamped / _cosineCeiling;
  }

  // ═══════════════════════════════════════════════════════════════
  // EMBEDDING PARSING
  // ═══════════════════════════════════════════════════════════════
  static List<List<double>> _parseEmbeddingsJson(String rawJson) {
    final result = <List<double>>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is List) {
            try {
              final emb = e.map((v) {
                final d = (v as num).toDouble();
                if (d.isNaN || d.isInfinite) throw FormatException('bad');
                return d;
              }).toList();
              if (_isValidEmbedding(emb)) result.add(emb);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      _secureLog('⚠️ _parseEmbeddingsJson error: $e');
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD EMBEDDINGS
  // ═══════════════════════════════════════════════════════════════
  static Future<_EmbedLoadResult> _loadEmbeddingsForVerify(
      String employeeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get()
          .timeout(const Duration(seconds: 10));

      final data = doc.data();
      if (data == null) {
        return const _EmbedLoadResult(embeddings: []);
      }

      final version = data['faceEmbeddingVersion'] ?? 1;

      if (version == _currentVersion) {
        final rawJson = data['faceEmbeddingsJson'];
        if (rawJson is String && rawJson.isNotEmpty) {
          final v4 = _parseEmbeddingsJson(rawJson);
          if (v4.isNotEmpty) {
            return _EmbedLoadResult(
              embeddings: v4,
              isLegacy: false,
              sourceVersion: _currentVersion,
            );
          }
        }
      }

      final legacy = <List<double>>[];

      final rawJson = data['faceEmbeddingsJson'];
      if (rawJson is String && rawJson.isNotEmpty) {
        legacy.addAll(_parseEmbeddingsJson(rawJson));
      }

      final rawEmbList = data['faceEmbeddings'];
      if (rawEmbList is List) {
        for (final e in rawEmbList) {
          if (e is List) {
            try {
              final emb = e.map((v) => (v as num).toDouble()).toList();
              if (_isValidEmbedding(emb) || emb.length == _embeddingSize) {
                legacy.add(emb);
              }
            } catch (_) {}
          }
        }
      }

      final rawSingle = data['faceEmbedding'];
      if (rawSingle is List) {
        try {
          final emb = rawSingle.map((v) => (v as num).toDouble()).toList();
          if (emb.isNotEmpty) legacy.add(emb);
        } catch (_) {}
      }

      if (legacy.isNotEmpty) {
        return _EmbedLoadResult(
          embeddings: legacy,
          isLegacy: true,
          sourceVersion: version,
        );
      }

      return const _EmbedLoadResult(embeddings: []);
    } catch (e) {
      _secureLog('⚠️ _loadEmbeddingsForVerify error: $e');
      return const _EmbedLoadResult(embeddings: []);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SAVE EMBEDDING
  // ═══════════════════════════════════════════════════════════════
  static Future<void> saveEmbedding(
      String employeeId,
      List<double> embedding, {
        String? source,
      }) async {
    if (!_isValidEmbedding(embedding)) {
      _secureLog('❌ Invalid embedding — refusing to save');
      throw ArgumentError('Invalid embedding');
    }

    try {
      final docRef =
      FirebaseFirestore.instance.collection('employees').doc(employeeId);
      final doc = await docRef.get();

      List<List<double>> existing = [];

      if (doc.exists) {
        final data = doc.data();
        final version = data?['faceEmbeddingVersion'] ?? 1;

        if (version == _currentVersion) {
          final rawJson = data?['faceEmbeddingsJson'];
          if (rawJson is String && rawJson.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawJson);
              if (decoded is List) {
                existing = decoded
                    .map((e) => (e as List)
                    .map((v) => (v as num).toDouble())
                    .toList())
                    .where((e) => _isValidEmbedding(e))
                    .toList();
              }
            } catch (e) {
              _secureLog('⚠️ Parse error: $e');
            }
          }
        }
      }

      if (existing.length >= _maxStoredEmbeddings) {
        existing =
            existing.sublist(existing.length - (_maxStoredEmbeddings - 1));
      }

      existing.add(embedding);

      final embeddingsJson = jsonEncode(existing);
      final templateHash = _hashTemplate(existing);

      await docRef.set({
        'faceEmbeddingsJson': embeddingsJson,
        'faceEmbeddingsCount': existing.length,
        'faceEmbeddingSize': _embeddingSize,
        'faceEmbeddingVersion': _currentVersion,
        'faceEmbeddingUpdatedAt': FieldValue.serverTimestamp(),
        'faceEmbeddingHash': templateHash,
        if (source != null) 'faceEmbeddingSource': source,
        'faceEmbedding': FieldValue.delete(),
        'faceEmbeddings': FieldValue.delete(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));

      _secureLog('✅ Saved embedding #${existing.length} for $employeeId '
          '(source: $source)');
    } catch (e) {
      _secureLog('❌ saveEmbedding error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🆕 ENROLL FACE — para sa UNANG BESES na registration
  // ═══════════════════════════════════════════════════════════════
  static Future<EnrollResult> enrollFace(
      String employeeId,
      Uint8List imageBytes, {
        String source = 'mobile_enrollment',
      }) async {
    if (kIsWeb) {
      return const EnrollResult(
        success: false,
        error: 'Face enrollment is not available on web.',
      );
    }

    try {
      final embedding = await generateEmbedding(
        imageBytes,
        enableAlignment: true,
      );

      if (embedding.isEmpty) {
        return const EnrollResult(
          success: false,
          error: 'Hindi ma-extract ang mukha. '
              'Siguraduhing malinaw, walang harang, at live.',
        );
      }

      if (!_isValidEmbedding(embedding)) {
        return const EnrollResult(
          success: false,
          error: 'Invalid embedding. Subukan muli.',
        );
      }

      await saveEmbedding(employeeId, embedding, source: source);

      final status = await debugTemplateStatus(employeeId);
      final count = status['count'] as int? ?? 1;

      _secureLog('✅ [Enroll] Saved embedding #$count for $employeeId');

      return EnrollResult(
        success: true,
        samplesSoFar: count,
        error: null,
      );
    } catch (e, st) {
      _secureLog('❌ [Enroll] error: $e\n$st');
      return EnrollResult(
        success: false,
        error: 'Enrollment error: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🆕 CHECK — kung may registered face na ba ang employee
  // ═══════════════════════════════════════════════════════════════
  static Future<bool> hasRegisteredFace(String employeeId) async {
    try {
      final status = await debugTemplateStatus(employeeId);
      final version = status['version'] as int? ?? 0;
      final count = status['count'] as int? ?? 0;
      final hasJson = status['hasJson'] == true;

      return version == _currentVersion && count > 0 && hasJson;
    } catch (e) {
      _secureLog('⚠️ hasRegisteredFace error: $e');
      return false;
    }
  }

  static Future<List<List<double>>> loadAllEmbeddings(
      String employeeId) async {
    final loaded = await _loadEmbeddingsForVerify(employeeId);
    return loaded.embeddings;
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO-UPGRADE FROM IMAGE
  // ═══════════════════════════════════════════════════════════════
  static Future<bool> autoUpgradeFromImage(
      String employeeId,
      Uint8List imageBytes, {
        String source = 'upload',
        bool onlyIfNotV4 = false,
      }) async {
    if (kIsWeb) {
      _secureLog('⛔ autoUpgrade SKIPPED on web');
      return false;
    }

    try {
      if (imageBytes.isEmpty) return false;

      final docRef =
      FirebaseFirestore.instance.collection('employees').doc(employeeId);

      if (onlyIfNotV4) {
        final doc = await docRef.get();
        final currentVersion = doc.data()?['faceEmbeddingVersion'] ?? 0;
        if (currentVersion == _currentVersion) {
          _secureLog('⏭️ Already v$_currentVersion — skip upgrade');
          return false;
        }
      }

      final embedding = await generateEmbedding(imageBytes);
      if (!_isValidEmbedding(embedding)) {
        _secureLog('❌ autoUpgrade — invalid embedding');
        return false;
      }

      await saveEmbedding(employeeId, embedding, source: source);
      return true;
    } catch (e) {
      _secureLog('❌ autoUpgradeFromImage error: $e');
      return false;
    }
  }

  static Future<bool> autoUpgradeFromExistingPhoto(String employeeId) async {
    if (kIsWeb) {
      _secureLog('⛔ autoUpgradeFromExistingPhoto SKIPPED on web');
      return false;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get()
          .timeout(const Duration(seconds: 10));

      final photoUrl = doc.data()?['photoUrl'] as String?;
      if (photoUrl == null || photoUrl.isEmpty || photoUrl == '—') {
        _secureLog('⚠️ No photoUrl for $employeeId — cannot self-heal');
        return false;
      }

      Uint8List bytes;

      if (photoUrl.startsWith('data:image')) {
        final commaIdx = photoUrl.indexOf(',');
        if (commaIdx < 0) return false;
        bytes = base64Decode(photoUrl.substring(commaIdx + 1));
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(photoUrl));
          final response = await request.close();
          if (response.statusCode != 200) {
            _secureLog('⚠️ Photo download HTTP ${response.statusCode}');
            return false;
          }
          final chunks = <int>[];
          await for (final chunk in response) {
            chunks.addAll(chunk);
          }
          bytes = Uint8List.fromList(chunks);
        } finally {
          client.close();
        }
      }

      if (bytes.isEmpty) return false;

      _secureLog('🔧 Self-heal: generating embedding from photoUrl...');
      return await autoUpgradeFromImage(
        employeeId,
        bytes,
        source: 'self_heal_photo',
        onlyIfNotV4: false,
      );
    } catch (e) {
      _secureLog('❌ autoUpgradeFromExistingPhoto error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔥 MAIN VERIFY — strict, no auto-pass, with self-heal
  // ═══════════════════════════════════════════════════════════════
  static Future<FaceVerifyResult> verify(
      String employeeId,
      Uint8List liveImageBytes, {
        double threshold = defaultThreshold,
        bool allowLegacy = false,
        bool enableSelfHeal = true,
      }) async {
    if (kIsWeb) {
      return const FaceVerifyResult(
        score: 0,
        matched: false,
        hasEmbedding: false,
        error: 'Face verification is not available on web.',
      );
    }

    try {
      final effectiveThreshold = threshold < _minAcceptableThreshold
          ? _minAcceptableThreshold
          : threshold;

      var loaded = await _loadEmbeddingsForVerify(employeeId);

      if (loaded.isEmpty && enableSelfHeal) {
        _secureLog('🔧 No template for $employeeId — attempting self-heal...');
        try {
          final healed = await autoUpgradeFromExistingPhoto(employeeId)
              .timeout(const Duration(seconds: 25));
          if (healed) {
            loaded = await _loadEmbeddingsForVerify(employeeId);
            _secureLog('✅ Self-heal OK — retry verify '
                '(${loaded.count} templates)');
          } else {
            _secureLog('⚠️ Self-heal failed (no photoUrl or no face)');
          }
        } catch (e) {
          _secureLog('⚠️ Self-heal error: $e');
        }
      }

      if (loaded.isEmpty) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: false,
          error: 'No face registered. Please contact HR/Admin to enroll.',
        );
      }

      if (loaded.isLegacy && !allowLegacy) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: true,
          error: 'Face data outdated. Please re-enroll in admin panel.',
        );
      }

      final live =
      await generateEmbedding(liveImageBytes, enableAlignment: true);
      if (live.isEmpty) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: true,
          error: 'Could not extract face from live image. '
              'Make sure your face is clearly visible.',
        );
      }

      double bestCosine = -1.0;
      int compared = 0;
      for (final s in loaded.embeddings) {
        if (s.length != live.length) continue;
        if (!_isValidEmbedding(s)) continue;
        compared++;
        final sim = cosineSimilarity(s, live);
        if (sim > bestCosine) bestCosine = sim;
      }

      if (compared == 0) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: true,
          error: 'Face data format mismatch. Please re-register.',
        );
      }

      final score = _normalizeScore(bestCosine);
      final matched = score >= effectiveThreshold;

      _secureLog('📊 VERIFY: best cosine=${bestCosine.toStringAsFixed(4)} '
          '| score=${(score * 100).toStringAsFixed(1)}% '
          '| threshold=${(effectiveThreshold * 100).toStringAsFixed(0)}% '
          '| matched=$matched '
          '| templates=$compared');

      return FaceVerifyResult(
        score: score,
        matched: matched,
        hasEmbedding: true,
        upgraded: false,
        error: null,
      );
    } catch (e, st) {
      _secureLog('❌ verify error: $e\n$st');
      return FaceVerifyResult(
        score: 0,
        matched: false,
        hasEmbedding: false,
        error: 'Verification error: $e',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UPLOAD EMPLOYEE PHOTO (used by admin)
  // ═══════════════════════════════════════════════════════════════
  static Future<String?> uploadEmployeePhoto(
      String employeeId,
      Uint8List imageBytes, {
        bool autoUpgradeFace = true,
      }) async {
    if (imageBytes.isEmpty) return null;

    Uint8List processedBytes = imageBytes;
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > 400 ? 400 : decoded.width,
          height: decoded.height > 400 ? 400 : decoded.height,
          interpolation: img.Interpolation.average,
        );
        processedBytes =
            Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      }
    } catch (e) {
      _secureLog('⚠️ Compression failed: $e');
    }

    if (processedBytes.length > 700 * 1024) {
      _secureLog('❌ Image too large');
      return null;
    }

    if (autoUpgradeFace && !kIsWeb) {
      try {
        _secureLog('🧠 Generating face embedding during upload...');
        final ok = await autoUpgradeFromImage(
          employeeId,
          imageBytes,
          source: 'photo_upload_mobile',
        );
        _secureLog('⬆️ auto-upgrade ${ok ? 'SUCCESS' : 'SKIPPED/FAILED'}');
      } catch (e) {
        _secureLog('⚠️ auto-upgrade failed: $e');
      }
    }

    if (!kIsWeb) {
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('employee_photos')
            .child('$employeeId.jpg');
        await ref
            .putData(processedBytes,
            SettableMetadata(contentType: 'image/jpeg'))
            .timeout(const Duration(seconds: 20));
        final url = await ref.getDownloadURL();
        return url;
      } catch (e) {
        _secureLog('⚠️ Storage upload failed (base64 fallback)');
      }
    }

    try {
      final base64String = base64Encode(processedBytes);
      final dataUrl = 'data:image/jpeg;base64,$base64String';
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .update({
        'photoUrl': dataUrl,
        'photoBase64': true,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));
      return dataUrl;
    } catch (e) {
      _secureLog('❌ Base64 save failed: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE / CLEAR
  // ═══════════════════════════════════════════════════════════════
  static Future<bool> deleteEmployeePhoto(String employeeId) async {
    try {
      if (!kIsWeb) {
        try {
          await FirebaseStorage.instance
              .ref()
              .child('employee_photos')
              .child('$employeeId.jpg')
              .delete()
              .timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .update({
        'photoUrl': null,
        'photoBase64': null,
      }).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      _secureLog('⚠️ deleteEmployeePhoto error: $e');
      return false;
    }
  }

  static Future<void> clearAllEmbeddings(String employeeId) async {
    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .update({
        'faceEmbedding': FieldValue.delete(),
        'faceEmbeddings': FieldValue.delete(),
        'faceEmbeddingsJson': FieldValue.delete(),
        'faceEmbeddingsCount': FieldValue.delete(),
        'faceEmbeddingSize': FieldValue.delete(),
        'faceEmbeddingVersion': FieldValue.delete(),
        'faceEmbeddingUpdatedAt': FieldValue.delete(),
        'faceEmbeddingSource': FieldValue.delete(),
        'faceEmbeddingHash': FieldValue.delete(),
      });
      _secureLog('✅ Cleared ALL embeddings for $employeeId');
    } catch (e) {
      _secureLog('❌ clearAllEmbeddings error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DEBUG HELPERS
  // ═══════════════════════════════════════════════════════════════
  static Future<Map<String, dynamic>> debugTemplateStatus(
      String employeeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get();
      final data = doc.data();
      if (data == null) {
        return {'exists': false};
      }
      return {
        'exists': true,
        'version': data['faceEmbeddingVersion'],
        'count': data['faceEmbeddingsCount'],
        'size': data['faceEmbeddingSize'],
        'hasJson':
        (data['faceEmbeddingsJson'] as String?)?.isNotEmpty ?? false,
        'hasPhotoUrl':
        (data['photoUrl'] as String?)?.isNotEmpty ?? false,
        'updatedAt': data['faceEmbeddingUpdatedAt'],
        'source': data['faceEmbeddingSource'],
      };
    } catch (e) {
      return {'error': '$e'};
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// RESULT CLASS
// ═══════════════════════════════════════════════════════════════
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