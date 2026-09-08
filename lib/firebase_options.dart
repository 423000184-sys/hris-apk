// File generated manually from Firebase project config.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg',
    authDomain: 'week-9-activity-53484.firebaseapp.com',
    projectId: 'week-9-activity-53484',
    storageBucket: 'week-9-activity-53484.firebasestorage.app',
    messagingSenderId: '1095102475957',
    appId: '1:1095102475957:web:45a4624634e83b53e4d8fc',
    measurementId: 'G-605G4TDLCX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg',
    authDomain: 'week-9-activity-53484.firebaseapp.com',
    projectId: 'week-9-activity-53484',
    storageBucket: 'week-9-activity-53484.firebasestorage.app',
    messagingSenderId: '1095102475957',
    appId: '1:1095102475957:web:45a4624634e83b53e4d8fc',
    measurementId: 'G-605G4TDLCX',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg',
    authDomain: 'week-9-activity-53484.firebaseapp.com',
    projectId: 'week-9-activity-53484',
    storageBucket: 'week-9-activity-53484.firebasestorage.app',
    messagingSenderId: '1095102475957',
    appId: '1:1095102475957:web:45a4624634e83b53e4d8fc',
    measurementId: 'G-605G4TDLCX',
  );
}