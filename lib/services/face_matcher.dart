// lib/services/face_matcher.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════════════
// INTERNAL: result ng legacy-aware embedding load
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
}

class FaceMatcher {
  static const int _embeddingSize = 192;
  static const double defaultThreshold = 0.55;
  static const int _maxStoredEmbeddings = 5;
  static const int _currentVersion = 4;

  static Interpreter? _interpreter;
  static FaceDetector? _faceDetector;
  static bool _isInitialized = false;

  // ════════════════════════════════════════════════════════════
  // INIT MODELS — ✅ WEB-SAFE
  // ════════════════════════════════════════════════════════════
  static Future<void> _initModels() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      await initializeWeb();
      debugPrint('✅ Web LiteRT runtime initialized');
    }

    _interpreter ??=
    await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');

    if (!kIsWeb) {
      _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableClassification: true,
          enableLandmarks: true,
          enableContours: false,
          minFaceSize: 0.15,
        ),
      );
    } else {
      debugPrint('🌐 Web: skipping ML Kit FaceDetector (no web support)');
    }

    _isInitialized = true;
    debugPrint('✅ TFLite + ML Kit Models loaded (web: $kIsWeb)');
  }

  // ─── Alignment (mobile only) ────────────────────────────────
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
      debugPrint('✅ Face aligned: rotated ${angleDeg.toStringAsFixed(2)}°');
      return rotated;
    } catch (e) {
      debugPrint('⚠️ Alignment failed: $e');
      return src;
    }
  }

  // ════════════════════════════════════════════════════════════
  // GENERATE EMBEDDING — ✅ WEB-SAFE
  // ════════════════════════════════════════════════════════════
  static Future<List<double>> generateEmbedding(
      Uint8List imageBytes, {
        bool enableAlignment = true,
      }) async {
    try {
      await _initModels();

      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        debugPrint('❌ Could not decode image');
        return <double>[];
      }

      img.Image workingImage = decoded;
      int cropX, cropY, cropW, cropH;

      // ─── WEB PATH ────────────────────────────────────────────
      // ⚠️ WARNING: Web has NO face detection. Center crop lang ito.
      // Para sa web face detection, kailangan ng BlazeFace model (TFLite).
      // Sa ngayon, para sa tamang V4 embedding, gumamit ng MOBILE live scan.
      if (kIsWeb) {
        final minSide = math.min(decoded.width, decoded.height);
        final side = (minSide * 0.7).toInt().clamp(40, minSide);

        cropX = ((decoded.width - side) / 2).toInt().clamp(0, decoded.width);
        cropY = ((decoded.height - side) / 2).toInt().clamp(0, decoded.height);
        cropW = side.clamp(0, decoded.width - cropX);
        cropH = side.clamp(0, decoded.height - cropY);

        debugPrint('🌐 Web center-crop: ${cropW}x$cropH at ($cropX, $cropY) — '
            '⚠️ HINDI ito face detection, generic center lang');

        if (cropW < 40 || cropH < 40) {
          debugPrint('❌ Web crop too small: ${cropW}x$cropH');
          return <double>[];
        }
      }
      // ─── MOBILE PATH ─────────────────────────────────────────
      else {
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
          debugPrint('❌ No face detected');
          return <double>[];
        }

        final face = faces.first;

        if (enableAlignment) {
          workingImage = _alignFace(decoded, face);
        }

        final rect = face.boundingBox;
        final marginX = rect.width * 0.15;
        final marginY = rect.height * 0.15;

        cropX = (rect.left - marginX).toInt().clamp(0, workingImage.width);
        cropY = (rect.top - marginY).toInt().clamp(0, workingImage.height);
        cropW =
            (rect.width + marginX * 2).toInt().clamp(0, workingImage.width - cropX);
        cropH =
            (rect.height + marginY * 2).toInt().clamp(0, workingImage.height - cropY);

        if (cropW < 40 || cropH < 40) {
          debugPrint('❌ Face crop too small: ${cropW}x$cropH');
          return <double>[];
        }
      }

      // ─── Shared: crop → resize → normalize → TFLite ──────────
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
            return [
              (p.r - 127.5) / 128.0,
              (p.g - 127.5) / 128.0,
              (p.b - 127.5) / 128.0,
            ];
          }),
        ),
      );

      final output =
      List.filled(1 * _embeddingSize, 0).reshape([1, _embeddingSize]);
      _interpreter!.run(input, output);

      final rawList = output[0];
      final List<double> rawDoubles = <double>[];
      for (final v in rawList) {
        rawDoubles.add((v as num).toDouble());
      }

      double norm = 0.0;
      for (final v in rawDoubles) {
        norm += v * v;
      }
      norm = math.sqrt(norm);
      if (norm == 0) return <double>[];

      final List<double> embedding = <double>[];
      for (final v in rawDoubles) {
        embedding.add(v / norm);
      }

      debugPrint(
          '✅ Embedding generated: ${embedding.length} dims (web: $kIsWeb)');
      return embedding;
    } catch (e, st) {
      debugPrint('❌ generateEmbedding error: $e');
      debugPrint('$st');
      return <double>[];
    }
  }

  // ════════════════════════════════════════════════════════════
  // COSINE SIMILARITY
  // ════════════════════════════════════════════════════════════
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot.clamp(-1.0, 1.0);
  }

  static double _normalizeScore(double cosine) {
    final clamped = cosine.clamp(0.0, 0.7);
    return clamped / 0.7;
  }

  // ════════════════════════════════════════════════════════════
  // JSON PARSER HELPER
  // ════════════════════════════════════════════════════════════
  static List<List<double>> _parseEmbeddingsJson(String rawJson) {
    final result = <List<double>>[];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        for (final e in decoded) {
          if (e is List) {
            try {
              final emb = e.map((v) => (v as num).toDouble()).toList();
              if (emb.length > 0) result.add(emb);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ _parseEmbeddingsJson error: $e');
    }
    return result;
  }

  // ════════════════════════════════════════════════════════════
  // LEGACY-AWARE EMBEDDING LOADER
  // ════════════════════════════════════════════════════════════
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
        debugPrint('📥 [loadAll] doc not found');
        return const _EmbedLoadResult(embeddings: []);
      }

      final version = data['faceEmbeddingVersion'] ?? 1;
      debugPrint('📥 [loadAll] version=$version');

      // ─── V4 PATH (primary) ─────────────────────────────────
      if (version == _currentVersion) {
        final rawJson = data['faceEmbeddingsJson'];
        if (rawJson is String && rawJson.isNotEmpty) {
          final v4 = _parseEmbeddingsJson(rawJson)
              .where((e) => e.length == _embeddingSize)
              .toList();
          if (v4.isNotEmpty) {
            debugPrint('📥 [loadAll] V4: Loaded ${v4.length} valid embeddings');
            return _EmbedLoadResult(
              embeddings: v4,
              isLegacy: false,
              sourceVersion: _currentVersion,
            );
          }
        }
      }

      // ─── LEGACY FALLBACK (V1/V2/V3) ────────────────────────
      debugPrint('⚠️ V4 not found/empty. Trying LEGACY fallback...');

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
              if (emb.isNotEmpty) legacy.add(emb);
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

      if (rawSingle is String && rawSingle.isNotEmpty) {
        final parsed = _parseEmbeddingsJson(rawSingle);
        if (parsed.isNotEmpty) {
          legacy.addAll(parsed);
        } else {
          try {
            final decoded = jsonDecode(rawSingle);
            if (decoded is List) {
              final emb =
              decoded.map((v) => (v as num).toDouble()).toList();
              if (emb.isNotEmpty) legacy.add(emb);
            }
          } catch (_) {}
        }
      }

      if (legacy.isNotEmpty) {
        debugPrint(
            '⚠️ LEGACY: Loaded ${legacy.length} embeddings from v$version');
        return _EmbedLoadResult(
          embeddings: legacy,
          isLegacy: true,
          sourceVersion: version,
        );
      }

      debugPrint('❌ No embeddings found at all');
      return const _EmbedLoadResult(embeddings: []);
    } catch (e) {
      debugPrint('⚠️ _loadEmbeddingsForVerify error: $e');
      return const _EmbedLoadResult(embeddings: []);
    }
  }

  // ════════════════════════════════════════════════════════════
  // SAVE EMBEDDING (V4)
  // ════════════════════════════════════════════════════════════
  static Future<void> saveEmbedding(
      String employeeId, List<double> embedding,
      {String? source}) async {
    debugPrint('💾 [saveEmbedding] START for $employeeId');
    debugPrint(
        '💾 [saveEmbedding] Values: ${embedding.length} (expected: $_embeddingSize)');

    if (embedding.length != _embeddingSize) {
      debugPrint('⚠️ WRONG SIZE! Expected $_embeddingSize, got ${embedding.length}');
      return;
    }

    try {
      final docRef =
      FirebaseFirestore.instance.collection('employees').doc(employeeId);
      final doc = await docRef.get();

      List<List<double>> existing = [];

      if (doc.exists) {
        final data = doc.data();
        final version = data?['faceEmbeddingVersion'] ?? 1;
        debugPrint('💾 [saveEmbedding] Existing version: $version');

        if (version == _currentVersion) {
          final rawJson = data?['faceEmbeddingsJson'];
          if (rawJson is String && rawJson.isNotEmpty) {
            try {
              final decoded = jsonDecode(rawJson);
              if (decoded is List) {
                existing = decoded
                    .map((e) =>
                    (e as List).map((v) => (v as num).toDouble()).toList())
                    .where((e) => e.length == _embeddingSize)
                    .toList();
                debugPrint('💾 Preserving ${existing.length} existing');
              }
            } catch (e) {
              debugPrint('⚠️ Parse error: $e');
            }
          }
        } else {
          debugPrint('🔥 Detected OLD version ($version) — clearing!');
        }
      }

      existing.add(embedding);
      if (existing.length > _maxStoredEmbeddings) {
        existing = existing.sublist(existing.length - _maxStoredEmbeddings);
      }

      final embeddingsJson = jsonEncode(existing);

      await docRef.set({
        'faceEmbeddingsJson': embeddingsJson,
        'faceEmbeddingsCount': existing.length,
        'faceEmbeddingSize': _embeddingSize,
        'faceEmbeddingVersion': _currentVersion,
        'faceEmbeddingUpdatedAt': FieldValue.serverTimestamp(),
        if (source != null) 'faceEmbeddingSource': source,
        // Linisin ang legacy fields
        'faceEmbedding': FieldValue.delete(),
        'faceEmbeddings': FieldValue.delete(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));

      debugPrint(
          '✅ Saved embedding #${existing.length} for $employeeId (v$_currentVersion, source: ${source ?? 'n/a'})');
    } catch (e) {
      debugPrint('❌ saveEmbedding error: $e');
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════════
  // LOAD ALL EMBEDDINGS (public — V4-only, backward compat)
  // ════════════════════════════════════════════════════════════
  static Future<List<List<double>>> loadAllEmbeddings(
      String employeeId) async {
    final loaded = await _loadEmbeddingsForVerify(employeeId);
    return loaded.embeddings;
  }

  // ════════════════════════════════════════════════════════════
  // AUTO-UPGRADE FROM IMAGE BYTES
  // ✅ FIXED: Web skip na — walang face detection sa web, generic
  //            center crop lang na nagdudulot ng maling embedding
  //            (mukha ng tao -> dibdib/torso ang na-e-embed).
  // ════════════════════════════════════════════════════════════
  static Future<bool> autoUpgradeFromImage(
      String employeeId,
      Uint8List imageBytes, {
        String source = 'upload',
        bool onlyIfNotV4 = false,
      }) async {
    debugPrint('⬆️ [autoUpgradeFromImage] START for $employeeId (source: $source)');

    // ⛔ WEB GUARD — hindi na pwede sa web dahil walang face detector
    if (kIsWeb) {
      debugPrint(
          '⛔ [autoUpgradeFromImage] SKIPPED on web — walang face detection. '
              'Gamitin ang MOBILE live scan para sa V4 enrollment.');
      return false;
    }

    try {
      if (imageBytes.isEmpty) {
        debugPrint('⚠️ autoUpgrade: empty bytes');
        return false;
      }

      final docRef = FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId);

      if (onlyIfNotV4) {
        final doc = await docRef.get();
        final currentVersion = doc.data()?['faceEmbeddingVersion'] ?? 0;
        if (currentVersion == _currentVersion) {
          debugPrint('⏭️ autoUpgrade skipped — V4 na');
          return false;
        }
      }

      // 1️⃣ Generate V4 embedding mula sa image
      final embedding = await generateEmbedding(imageBytes);
      if (embedding.isEmpty || embedding.length != _embeddingSize) {
        debugPrint(
            '⚠️ autoUpgrade: invalid embedding (${embedding.length} dims)');
        return false;
      }

      // 2️⃣ Save as V4 (overwrites legacy)
      await saveEmbedding(employeeId, embedding, source: source);

      // 3️⃣ Activity log
      try {
        await FirebaseFirestore.instance.collection('activity logs').add({
          'type': 'face_auto_upgraded',
          'employeeId': employeeId,
          'source': source,
          'toVersion': _currentVersion,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('⚠️ autoUpgrade activity log warning: $e');
      }

      debugPrint('✅ [autoUpgradeFromImage] SUCCESS for $employeeId');
      return true;
    } catch (e) {
      debugPrint('❌ autoUpgradeFromImage error: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════
  // AUTO-UPGRADE FROM EXISTING photoUrl (Firestore)
  // ✅ FIXED: Web skip rin — same reason (center crop lang)
  // ════════════════════════════════════════════════════════════
  static Future<bool> autoUpgradeFromExistingPhoto(
      String employeeId) async {
    debugPrint('⬆️ [autoUpgradeFromExistingPhoto] START for $employeeId');

    // ⛔ WEB GUARD — dahil sa walang face detection sa web
    if (kIsWeb) {
      debugPrint(
          '⛔ [autoUpgradeFromExistingPhoto] SKIPPED on web — '
              'walang face detection. Gumamit ng mobile live scan.');
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
        debugPrint('⚠️ No photoUrl for $employeeId — skipping');
        return false;
      }

      Uint8List bytes;

      if (photoUrl.startsWith('data:image')) {
        final commaIdx = photoUrl.indexOf(',');
        if (commaIdx < 0) {
          debugPrint('❌ Invalid data URL format');
          return false;
        }
        bytes = base64Decode(photoUrl.substring(commaIdx + 1));
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(photoUrl));
          final response = await request.close();
          if (response.statusCode != 200) {
            debugPrint('❌ HTTP ${response.statusCode} fetching photo');
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

      if (bytes.isEmpty) {
        debugPrint('⚠️ Empty photo bytes');
        return false;
      }

      return await autoUpgradeFromImage(
        employeeId,
        bytes,
        source: 'existing_photo',
        onlyIfNotV4: true,
      );
    } catch (e) {
      debugPrint('❌ autoUpgradeFromExistingPhoto error: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════
  // VERIFY — with GRACE PERIOD + AUTO-UPGRADE
  // ✅ Dito gumagana pa rin ang auto-upgrade — pero ito ay
  //    called mula sa MOBILE (may live camera), kaya may face
  //    detection na legit. Hindi ito web.
  // ════════════════════════════════════════════════════════════
  static Future<FaceVerifyResult> verify(
      String employeeId,
      Uint8List liveImageBytes, {
        double threshold = defaultThreshold,
      }) async {
    try {
      final loaded = await _loadEmbeddingsForVerify(employeeId);

      if (loaded.isEmpty) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: false,
          error: 'No face registered. Please re-register in admin panel.',
        );
      }

      final live =
      await generateEmbedding(liveImageBytes, enableAlignment: true);
      if (live.isEmpty) {
        return const FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: true,
          error: 'Could not extract face from live image.',
        );
      }

      double bestCosine = -1.0;
      int compared = 0;
      for (final s in loaded.embeddings) {
        if (s.length != live.length) continue;
        compared++;
        final sim = cosineSimilarity(s, live);
        if (sim > bestCosine) bestCosine = sim;
      }

      if (compared == 0) {
        debugPrint(
            '❌ Size mismatch: live=${live.length}, stored=${loaded.embeddings.map((e) => e.length).toSet()}');
        return FaceVerifyResult(
          score: 0,
          matched: false,
          hasEmbedding: true,
          error:
          'Face data format mismatch. Please re-register in admin panel.',
        );
      }

      final score = _normalizeScore(bestCosine);
      final matched = score >= threshold;

      debugPrint('📊 Best cosine: ${bestCosine.toStringAsFixed(4)} '
          '(${(score * 100).toStringAsFixed(1)}% match) vs $compared template(s) '
          '[${loaded.isLegacy ? 'LEGACY v${loaded.sourceVersion}' : 'V4'}]');

      // Auto-upgrade kapag legacy at nag-match
      bool upgraded = false;
      if (matched && loaded.isLegacy) {
        try {
          debugPrint(
              '⬆️ Auto-upgrading $employeeId from v${loaded.sourceVersion} → v$_currentVersion');
          await saveEmbedding(employeeId, live, source: 'live_scan');
          upgraded = true;

          try {
            await FirebaseFirestore.instance
                .collection('activity logs')
                .add({
              'type': 'face_auto_upgraded',
              'employeeId': employeeId,
              'source': 'live_scan',
              'fromVersion': loaded.sourceVersion,
              'toVersion': _currentVersion,
              'timestamp': FieldValue.serverTimestamp(),
            });
          } catch (e) {
            debugPrint('⚠️ Activity log (auto-upgrade) warning: $e');
          }

          debugPrint('✅ Auto-upgrade SUCCESS for $employeeId');
        } catch (e) {
          debugPrint('⚠️ Auto-upgrade failed (login still allowed): $e');
        }
      }

      return FaceVerifyResult(
        score: score,
        matched: matched,
        hasEmbedding: true,
        upgraded: upgraded,
        error: null,
      );
    } catch (e) {
      debugPrint('❌ verify error: $e');
      return FaceVerifyResult(
        score: 0,
        matched: false,
        hasEmbedding: false,
        error: 'Verification error: $e',
      );
    }
  }

  // ════════════════════════════════════════════════════════════
  // PHOTO UPLOAD
  // ✅ FIXED: Auto-upgrade ay MOBILE-ONLY na ngayon.
  //            Sa web, upload lang ng photo — walang face embedding.
  //            Ang face enrollment ay dapat manggaling sa live
  //            scan ng employee sa mobile app.
  // ════════════════════════════════════════════════════════════
  static Future<String?> uploadEmployeePhoto(
      String employeeId, Uint8List imageBytes, {
        bool autoUpgradeFace = true,
      }) async {
    debugPrint('📤 [uploadPhoto] START for $employeeId');
    if (imageBytes.isEmpty) return null;

    Uint8List processedBytes = imageBytes;
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        final resized = img.copyResize(decoded,
            width: decoded.width > 400 ? 400 : decoded.width,
            height: decoded.height > 400 ? 400 : decoded.height,
            interpolation: img.Interpolation.average);
        processedBytes =
            Uint8List.fromList(img.encodeJpg(resized, quality: 70));
      }
    } catch (e) {
      debugPrint('⚠️ Compression failed: $e');
    }

    if (processedBytes.length > 700 * 1024) {
      debugPrint('❌ Image too large');
      return null;
    }

    // ✅ MOBILE-ONLY auto-upgrade (may face detection via ML Kit).
    //    Sa WEB, hindi na nag-a-auto-upgrade — kasi ang web
    //    center-crop lang ang gamit, at madalas mali ang nakuha
    //    (dibdib/torso kaysa mukha).
    if (autoUpgradeFace && !kIsWeb) {
      unawaited(
        autoUpgradeFromImage(
          employeeId,
          imageBytes,
          source: 'photo_upload_mobile',
        ).then((ok) {
          debugPrint(
              '⬆️ [uploadPhoto] auto-upgrade ${ok ? 'SUCCESS' : 'SKIPPED/FAILED'}');
        }),
      );
    } else if (autoUpgradeFace && kIsWeb) {
      debugPrint(
          '⛔ [uploadPhoto] Auto-upgrade skipped on WEB. '
              'Para sa face enrollment, gamitin ang MOBILE live scan.');
    }

    // ─── Upload path ─────────────────────────────────────────
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
        debugPrint('✅ Photo uploaded to Storage');
        return url;
      } catch (e) {
        debugPrint('⚠️ Storage upload failed (using base64 fallback)');
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
      debugPrint('✅ Photo saved as base64');
      return dataUrl;
    } catch (e) {
      debugPrint('❌ Base64 save failed: $e');
      return null;
    }
  }

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
      debugPrint('⚠️ deleteEmployeePhoto error: $e');
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
      });
      debugPrint('✅ Cleared ALL embeddings for $employeeId');
    } catch (e) {
      debugPrint('❌ clearAllEmbeddings error: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// RESULT CLASS — may `upgraded` field
// ═══════════════════════════════════════════════════════════════
class FaceVerifyResult {
  final double score;
  final bool matched;
  final bool hasEmbedding;

  /// true kung ang login na ito ay nag-trigger ng auto-upgrade
  /// mula legacy (V1/V2/V3) papuntang V4.
  final bool upgraded;

  final String? error;

  const FaceVerifyResult({
    required this.score,
    required this.matched,
    required this.hasEmbedding,
    this.upgraded = false,
    this.error,
  });
}