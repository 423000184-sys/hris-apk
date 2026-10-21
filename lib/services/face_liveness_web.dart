// lib/services/face_liveness_web.dart
//
// Web implementation — bridges face-api.js to Dart using modern web interop.

import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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

      // 🔥 FIX: Safe null check imbes na boolean negation
      final jsFunction = globalContext.getProperty('detectFaceLiveness'.toJS);
      if (jsFunction == null || jsFunction.isUndefinedOrNull) {
        debugPrint('⚠️ [FaceLiveness] detectFaceLiveness not on window');
        return null;
      }

      // 2. Call the JS function
      final promise = globalContext.callMethod(
        'detectFaceLiveness'.toJS,
        videoElement as JSAny,
      ) as JSPromise<JSAny?>;

      // 3. Await the JS Promise
      final jsResult = await promise.toDart;
      if (jsResult == null || jsResult.isUndefinedOrNull) return null;

      // 4. Read properties from the result
      final resultObj = jsResult as JSObject;

      final facePresent = (resultObj.getProperty('facePresent'.toJS)?.dartify() as bool?) ?? false;
      if (!facePresent) {
        return FaceLivenessResult(facePresent: false);
      }

      final eyeOpen = (resultObj.getProperty('eyeOpenScore'.toJS)?.dartify() as num? ?? 1.0).toDouble();
      final smile = (resultObj.getProperty('smileScore'.toJS)?.dartify() as num? ?? 0.0).toDouble();

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
      final videos = web.document.querySelectorAll('video');
      if (videos.length == 0) return null;

      // Prefer the visible one (iterate from last to first)
      for (int i = videos.length - 1; i >= 0; i--) {
        final el = videos.item(i);
        if (el is web.HTMLVideoElement) {
          final rect = el.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            return el;
          }
        }
      }

      // Fallback to the first video element if none are visible
      return videos.item(0);
    } catch (e) {
      debugPrint('⚠️ [FaceLiveness] getVideoElement error: $e');
      return null;
    }
  }
}