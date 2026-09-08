// lib/services/geofence_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeofenceResult {
  final bool isAllowed;
  final double? distanceMeters;
  final double? accuracyMeters;
  final String message;
  final GeofenceStatus status;
  final Position? position;

  const GeofenceResult({
    required this.isAllowed,
    required this.message,
    required this.status,
    this.distanceMeters,
    this.accuracyMeters,
    this.position,
  });

  String get distanceLabel {
    if (distanceMeters == null) return 'Unknown';
    if (distanceMeters! < 1000) return '${distanceMeters!.toStringAsFixed(0)} m';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)} km';
  }

  bool get isInside => status == GeofenceStatus.inside;
  bool get isOutside => status == GeofenceStatus.outside;
  bool get isPermissionDenied =>
      status == GeofenceStatus.permissionDenied ||
          status == GeofenceStatus.permissionPermanentlyDenied;
  bool get isError =>
      status == GeofenceStatus.error ||
          status == GeofenceStatus.serviceDisabled;
}

enum GeofenceStatus {
  inside,
  outside,
  permissionDenied,
  permissionPermanentlyDenied,
  serviceDisabled,
  error,
  loading,
}

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  static const double _officeLat           = 14.6021393;
  static const double _officeLng           = 120.9993248;
  static const String _officeAddress       = '256 Lacson Ave, Sampaloc Manila 1008';
  static const double _allowedRadiusMeters = 100.0;

  final _statusController = StreamController<GeofenceResult>.broadcast();
  Stream<GeofenceResult> get statusStream => _statusController.stream;

  StreamSubscription<Position>? _positionSub;
  GeofenceResult? _lastResult;
  GeofenceResult? get lastResult => _lastResult;
  bool get isInsideGeofence => _lastResult?.isInside ?? false;

  static double get allowedRadius => _allowedRadiusMeters;
  static String get officeAddress => _officeAddress;
  static double get officeLat     => _officeLat;
  static double get officeLng     => _officeLng;

  Future<GeofenceResult> checkGeofence() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.serviceDisabled,
        message: 'Location services are disabled.\nPlease enable GPS to clock in/out.',
      ));
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _emit(const GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.permissionDenied,
          message: 'Location permission denied.\nGrant permission to record attendance.',
        ));
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionPermanentlyDenied,
        message: 'Location permission permanently denied.\nOpen App Settings → Permissions → Location.',
      ));
    }

    _emit(const GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.loading,
      message: 'Fetching current location...',
    ));

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('GPS timeout'),
      );
      return _evaluate(position);
    } on TimeoutException {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location request timed out.\nMake sure GPS signal is strong and try again.',
      ));
    } catch (e) {
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location error: ${e.toString()}',
      ));
    }
  }

  Future<void> startMonitoring() async {
    await stopMonitoring();
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(distanceFilter: 5),
    ).listen(
          (position) => _evaluate(position),
      onError: (e) => _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'GPS stream error: $e',
      )),
    );
  }

  Future<void> stopMonitoring() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }

  LocationSettings _buildLocationSettings({int distanceFilter = 0}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
  }

  GeofenceResult _evaluate(Position position) {
    final distance = _haversineDistance(
      lat1: position.latitude,
      lng1: position.longitude,
      lat2: _officeLat,
      lng2: _officeLng,
    );
    final inside    = distance <= _allowedRadiusMeters;
    final remaining = _allowedRadiusMeters - distance;

    // ✅ Debug print to verify distance
    debugPrint('🔍 Distance: ${distance.toStringAsFixed(0)}m | isInside: $inside | accuracy: ${position.accuracy.toStringAsFixed(0)}m');

    final String message;
    if (inside) {
      message = 'You are inside the office zone.\n$_officeAddress\n'
          'Distance: ${distance.toStringAsFixed(0)} m from office';
    } else {
      message = 'You are outside the allowed zone.\n$_officeAddress\n'
          'You are ${distance.toStringAsFixed(0)} m away '
          '(${(-remaining).toStringAsFixed(0)} m beyond the '
          '${_allowedRadiusMeters.toStringAsFixed(0)} m limit)';
    }

    return _emit(GeofenceResult(
      isAllowed: inside,
      status: inside ? GeofenceStatus.inside : GeofenceStatus.outside,
      distanceMeters: distance,
      accuracyMeters: position.accuracy,
      message: message,
      position: position,
    ));
  }

  GeofenceResult _emit(GeofenceResult result) {
    _lastResult = result;
    if (!_statusController.isClosed) _statusController.add(result);
    return result;
  }

  double _haversineDistance({
    required double lat1, required double lng1,
    required double lat2, required double lng2,
  }) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLng / 2) * sin(dLng / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * (pi / 180);
}