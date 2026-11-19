// lib/services/field_proof_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

class FieldProofException implements Exception {
  FieldProofException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FieldProofService {
  FieldProofService._();
  static final FieldProofService instance = FieldProofService._();

  static const double _maxAccuracyM = 100;
  static const int _maxPhotoBytes = 400 * 1024;

  /// Camera-only selfie + GPS fix taken right after the photo.
  /// Writes a `field_proofs` doc with status 'pending' and returns its id.
  /// Throws [FieldProofException] on cancel, fake GPS, weak GPS or oversize photo.
  Future<String> captureAndSubmit({
    required String employeeId,
    required String employeeDocId,
    required String attendanceType, // IN | OUT
    String? nearestSiteName,
  }) async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera, // never the gallery
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 800,
      imageQuality: 60,
    );
    if (shot == null) throw FieldProofException('Selfie cancelled.');

    // GPS is read after the photo so the proof is "photo + place, same moment".
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    ).timeout(const Duration(seconds: 12));

    if (pos.isMocked) {
      throw FieldProofException('Fake GPS detected. Proof rejected.');
    }
    if (pos.accuracy > _maxAccuracyM) {
      throw FieldProofException(
          'GPS too weak (±${pos.accuracy.toStringAsFixed(0)}m). '
          'Move to an open area and retake.');
    }

    final bytes = await shot.readAsBytes();
    if (bytes.length > _maxPhotoBytes) {
      throw FieldProofException('Photo too large. Please retake.');
    }

    final ref = FirebaseFirestore.instance.collection('field_proofs').doc();
    final payload = <String, dynamic>{
      'employeeId': employeeId,
      'employeeDocId': employeeDocId,
      'attendanceType': attendanceType,
      'status': 'pending', // pending | approved | rejected
      'photo': 'data:image/jpeg;base64,${base64Encode(bytes)}',
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracyMeters': pos.accuracy,
      'nearestSiteName': nearestSiteName,
      'capturedAtDevice': DateTime.now().toIso8601String(),
      'capturedAt': FieldValue.serverTimestamp(), // the time HR trusts
    };

    try {
      // Firestore queues this offline; don't hang the UI waiting for it.
      await ref.set(payload).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('⏳ field_proofs queued (no server ack yet)');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw FieldProofException(
            'Hindi maipadala ang proof (walang permiso). Contact Admin.');
      }
      debugPrint('⚠️ field_proofs write failed: ${e.code}');
    }
    return ref.id;
  }

  /// Auto-captured photo for a normal clock-in (no HR review needed).
  /// Never throws: a failed photo must not break the clock-in itself.
  Future<bool> saveClockInPhoto({
    required String proofId,
    required String employeeId,
    required String employeeDocId,
    required String attendanceType, // IN | OUT
    required Uint8List bytes,
    double? lat,
    double? lng,
    double? accuracy,
    double? faceMatchScore,
  }) async {
    try {
      final ref =
          FirebaseFirestore.instance.collection('field_proofs').doc(proofId);
      await ref.set(<String, dynamic>{
        'employeeId': employeeId,
        'employeeDocId': employeeDocId,
        'attendanceType': attendanceType,
        'status': 'auto', // auto | pending | approved | rejected
        'source': 'clock_in_photo',
        'photo': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracy != null) 'accuracyMeters': accuracy,
        if (faceMatchScore != null) 'faceMatchScore': faceMatchScore,
        'capturedAtDevice': DateTime.now().toIso8601String(),
        'capturedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException {
      debugPrint('⏳ clock-in photo queued (no server ack yet)');
      return true; // Firestore keeps it queued
    } catch (e) {
      debugPrint('⚠️ clock-in photo write failed: $e');
      return false;
    }
  }
}