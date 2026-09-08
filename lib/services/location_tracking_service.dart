// lib/services/location_tracking_service.dart
import 'dart:async';
import 'dart:math' show cos, sqrt, asin, pi;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class LocationTrackingService {
  static LocationTrackingService? _instance;
  LocationTrackingService._();
  static LocationTrackingService get instance => _instance ??= LocationTrackingService._();

  Timer? _timer;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Office Location (Must match AdminDashboard and GeofenceService)
  static const double _officeLat = 14.6114;
  static const double _officeLng = 120.9936;
  static const double _radiusLimit = 1500.0; // 1.5km

  void startTracking(String employeeId) {
    _timer?.cancel();
    _updateLocation(employeeId);
    
    // 🔥 UPDATED: Set timer for every 2 minutes
    _timer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _updateLocation(employeeId);
    });
    debugPrint('📍 Location tracking started for: $employeeId (Every 2 minutes)');
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    debugPrint('📍 Location tracking stopped');
  }

  Future<void> _updateLocation(String employeeId) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final firebaseUid = AuthService.instance.currentUser?.uid;
      if (firebaseUid == null) return;

      // Calculate if inside perimeter
      double distance = _calculateDistance(position.latitude, position.longitude, _officeLat, _officeLng) * 1000;
      bool isInside = distance <= _radiusLimit;

      // Update Firestore with location AND perimeter status
      await _firestore.collection('user_locations').doc(firebaseUid).set({
        'employee_id': employeeId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'distance_from_office': distance,
        'is_inside_perimeter': isInside,
        'last_updated': FieldValue.serverTimestamp(),
        'status': 'online',
      }, SetOptions(merge: true));

      debugPrint('📍 Location updated: ${isInside ? "INSIDE" : "OUTSIDE"} ($distance m)');
    } catch (e) {
      debugPrint('📍 Location update failed: $e');
    }
  }

  double _calculateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}
