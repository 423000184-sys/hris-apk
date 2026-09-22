// lib/services/face_liveness_web.dart
//
// Web implementation — bridges face-api.js to Dart.

import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

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
  /// Calls JS `window.detectFaceLiveness(videoEl)` — returns detection result.
  Future<FaceLivenessResult?> detect(dynamic videoElement) async {
    try {
      if (videoElement == null) return null;

      final hasFn = js.context.hasProperty('detectFaceLiveness');
      if (!hasFn) {
        debugPrint('⚠️ [FaceLiveness] detectFaceLiveness not on window');
        return null;
      }

      final promise =
      js.context.callMethod('detectFaceLiveness', [videoElement]);
      final jsResult = await js_util.promiseToFuture<Object?>(promise);
      if (jsResult == null) return null;

      final facePresent =
          js_util.getProperty<bool?>(jsResult, 'facePresent') ?? false;
      if (!facePresent) {
        return FaceLivenessResult(facePresent: false);
      }

      final eyeOpen =
      (js_util.getProperty<num?>(jsResult, 'eyeOpenScore') ?? 1.0)
          .toDouble();
      final smile =
      (js_util.getProperty<num?>(jsResult, 'smileScore') ?? 0.0)
          .toDouble();

      return FaceLivenessResult(
        facePresent: true,
        eyeOpenScore: eyeOpen,
        smileScore: smile,
      );
    } catch (e) {
      debugPrint('❌ [FaceLiveness] detect error: $e');
      return null;
    }
  }

  /// Returns the Flutter camera plugin's <video> element (usually the last).
  dynamic getVideoElement() {
    try {
      final videos = html.document.getElementsByTagName('video');
      if (videos.isEmpty) return null;
      // Prefer the visible one
      for (final el in videos.reversed) {
        if (el is html.VideoElement) {
          final rect = el.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) return el;
        }
      }
      return videos.last;
    } catch (e) {
      debugPrint('⚠️ [FaceLiveness] getVideoElement error: $e');
      return null;
    }
  }
}