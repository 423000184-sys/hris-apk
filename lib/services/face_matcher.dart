// lib/services/face_matcher.dart
//
// 🌐 FACADE — platform-aware import
//
// • Mobile/Desktop (dart:io) → face_matcher_native.dart (tflite_flutter)
// • Web (dart:library.js_interop) → face_matcher_web.dart (stub)
//
// Import THIS file in all UI/feature code. Never import face_matcher_native.dart
// or face_matcher_web.dart directly.

export 'face_matcher_native.dart'
    if (dart.library.js_interop) 'face_matcher_web.dart';