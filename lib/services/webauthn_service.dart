// lib/services/webauthn_service.dart
//
// 🌐 Platform dispatcher — pipiliin kung aling implementation ang gagamitin:
//
//   • Web (dart:js available)   → webauthn_service_web.dart
//   • Android / iOS / Desktop    → webauthn_service_stub.dart
//
// Ang lahat ng caller (e.g. fingerprint_screen.dart) ay mag-i-import pa rin
// ng 'services/webauthn_service.dart' — walang babaguhin sa kanila.

export 'webauthn_service_stub.dart'
if (dart.library.js) 'webauthn_service_web.dart';