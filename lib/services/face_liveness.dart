// lib/services/face_liveness.dart
//
// Cross-platform dispatcher:
//   • Web  → uses face-api.js via JS interop
//   • Non-web → returns null (native uses google_mlkit instead)

export 'face_liveness_stub.dart'
if (dart.library.html) 'face_liveness_web.dart';