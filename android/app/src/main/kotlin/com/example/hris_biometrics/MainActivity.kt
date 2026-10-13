package com.example.hris_biometrics

import io.flutter.embedding.android.FlutterFragmentActivity

// ✅ FIXED: Must use FlutterFragmentActivity (NOT FlutterActivity)
// Required for:
// - local_auth biometric dialogs
// - nfc_manager proper IntentFilter registration
// - permission_handler dialogs
class MainActivity : FlutterFragmentActivity()