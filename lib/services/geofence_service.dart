// lib/services/geofence_service.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════════
// RESULT MODEL
// ══════════════════════════════════════════════════════════════════
class GeofenceResult {
  final bool isAllowed;
  final double? distanceMeters;
  final double? accuracyMeters;
  final String message;
  final GeofenceStatus status;
  final Position? position;
  final double? radiusUsed;
  final String? matchedLocationName;
  final bool isExempted;

  const GeofenceResult({
    required this.isAllowed,
    required this.message,
    required this.status,
    this.distanceMeters,
    this.accuracyMeters,
    this.position,
    this.radiusUsed,
    this.matchedLocationName,
    this.isExempted = false,
  });

  String get distanceLabel {
    if (distanceMeters == null) return 'Unknown';
    if (distanceMeters! < 1000) {
      return '${distanceMeters!.toStringAsFixed(0)} m';
    }
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
  exempted,
}

// ══════════════════════════════════════════════════════════════════
// INTERNAL ZONE MODEL
// ══════════════════════════════════════════════════════════════════
class _LocationZone {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double radius;

  const _LocationZone({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.radius,
  });
}

// ══════════════════════════════════════════════════════════════════
// GEOFENCE SERVICE
// ══════════════════════════════════════════════════════════════════
class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  // ✅ Legacy fallback (kung walang locations sa Firestore)
  static const double _officeLat = 14.59805;
  static const double _officeLng = 120.98917;
  static const String _officeAddress =
      '629 J. Nepomuceno St., Quiapo, Manila 1001';

  // ✅ Default radius
  static const double _defaultRadiusMeters = 100.0;

  // ✅ Cached values
  double _currentRadiusMeters = _defaultRadiusMeters;
  List<_LocationZone> _cachedZones = [];
  DateTime? _cacheTime;
  static const Duration _cacheTtl = Duration(minutes: 2);
  static const String _prefsRadiusKey = 'geofence_radius_cache';

  final _statusController = StreamController<GeofenceResult>.broadcast();
  Stream<GeofenceResult> get statusStream => _statusController.stream;

  StreamSubscription<Position>? _positionSub;
  GeofenceResult? _lastResult;

  GeofenceResult? get lastResult => _lastResult;
  bool get isInsideGeofence => _lastResult?.isInside ?? false;

  double get allowedRadius => _currentRadiusMeters;
  int get zoneCount => _cachedZones.length;
  List<String> get zoneNames => _cachedZones.map((z) => z.name).toList();

  static String get officeAddress => _officeAddress;
  static double get officeLat => _officeLat;
  static double get officeLng => _officeLng;

  // ══════════════════════════════════════════════════════════════════
  // CACHE INVALIDATION
  // ══════════════════════════════════════════════════════════════════
  void invalidateCache() {
    _cacheTime = null;
    debugPrint('🔄 [Geofence] Cache invalidated — '
        'next check will fetch fresh config from Firestore');
  }

  Future<void> forceReload() async {
    invalidateCache();
    await _loadRadiusFromFirestore();
  }

  // ══════════════════════════════════════════════════════════════════
  // LOAD ZONES FROM FIRESTORE (MULTI-LOCATION)
  // ══════════════════════════════════════════════════════════════════
  Future<void> _loadRadiusFromFirestore() async {
    // Cache TTL check
    if (_cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      debugPrint('💾 [Geofence] Using cached zones '
          '(${_cachedZones.length} zone(s))');
      return;
    }

    // 1️⃣ Primary: locations collection
    try {
      debugPrint('🌐 [Geofence] Loading locations from Firestore...');

      final snap = await FirebaseFirestore.instance
          .collection('locations')
          .where('active', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 5));

      final zones = <_LocationZone>[];

      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lng = (d['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final radius = ((d['radius'] as num?)?.toDouble() ??
            _defaultRadiusMeters)
            .clamp(20.0, 5000.0);

        zones.add(_LocationZone(
          id: doc.id,
          name: (d['name'] ?? 'Unnamed').toString(),
          address: (d['address'] ?? '').toString(),
          lat: lat,
          lng: lng,
          radius: radius,
        ));
      }

      if (zones.isNotEmpty) {
        _cachedZones = zones;
        _cacheTime = DateTime.now();
        debugPrint('✅ [Geofence] Loaded ${zones.length} active zone(s): '
            '${zones.map((z) => z.name).join(", ")}');
        return;
      }

      debugPrint('⚠️ [Geofence] Walang active locations — fallback sa legacy');
    } catch (e) {
      debugPrint('⚠️ [Geofence] locations load failed: $e');
    }

    // 2️⃣ Legacy: settings/geofence_config — radius lang
    try {
      debugPrint('🌐 [Geofence] Loading legacy config...');

      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get()
          .timeout(const Duration(seconds: 5));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final radius = (data['globalRadius'] as num?)?.toDouble();

        if (radius != null && radius > 0) {
          _currentRadiusMeters = radius.clamp(50.0, 2000.0);
          debugPrint('✅ [Geofence] Legacy radius loaded: '
              '${_currentRadiusMeters.toStringAsFixed(0)}m');

          await _saveToPrefs(_currentRadiusMeters);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [Geofence] legacy config load failed: $e');
    }

    // 3️⃣ SharedPreferences fallback
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getDouble(_prefsRadiusKey);
      if (cached != null && cached > 0) {
        _currentRadiusMeters = cached;
        debugPrint('💾 [Geofence] Using prefs cache: '
            '${cached.toStringAsFixed(0)}m');
      }
    } catch (e) {
      debugPrint('⚠️ [Geofence] Prefs load failed: $e');
    }

    // 4️⃣ Last fallback: default single office
    _cachedZones = [
      _LocationZone(
        id: 'legacy_office',
        name: 'Head Office',
        address: _officeAddress,
        lat: _officeLat,
        lng: _officeLng,
        radius: _currentRadiusMeters,
      ),
    ];
    _cacheTime = DateTime.now();
    debugPrint('🔧 [Geofence] Using legacy default office '
        '(${_currentRadiusMeters.toStringAsFixed(0)}m radius)');
  }

  Future<void> _saveToPrefs(double radius) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsRadiusKey, radius);
      debugPrint('💾 [Geofence] Saved radius to prefs: '
          '${radius.toStringAsFixed(0)}m');
    } catch (e) {
      debugPrint('⚠️ [Geofence] Prefs save error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // CHECK GEOFENCE — generic (no exemption check)
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> checkGeofence() async {
    debugPrint('🌍 [Geofence] Starting check (isWeb=$kIsWeb)');

    await _loadRadiusFromFirestore();

    debugPrint('📏 [Geofence] Zones: ${_cachedZones.length} | '
        'Default radius: ${_currentRadiusMeters.toStringAsFixed(0)}m');

    if (kIsWeb) return _checkGeofenceWeb();
    return _checkGeofenceNative();
  }

  // ══════════════════════════════════════════════════════════════════
  // ⭐ CHECK GEOFENCE FOR EMPLOYEE — with WFH / Driver exemption
  //    Ito ang gamitin sa attendance/clock-in flow.
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> checkGeofenceForEmployee({
    required String employeeId,
  }) async {
    final empId = employeeId.trim();
    if (empId.isEmpty) {
      debugPrint('⚠️ [Geofence] Empty employeeId — normal check na lang');
      return checkGeofence();
    }

    // ─── 1. Check WFH / Driver exemption ───
    bool isExempted = false;
    String exemptionReason = '';

    try {
      final empDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empId)
          .get()
          .timeout(const Duration(seconds: 4));

      if (empDoc.exists) {
        final d = empDoc.data() ?? {};
        final wfh = d['wfhAccess'] == true;
        final role = (d['role'] ?? '').toString().toLowerCase().trim();

        if (wfh) {
          isExempted = true;
          exemptionReason =
          'WFH access is enabled — hindi kailangang nasa office';
        } else if (role.contains('driver')) {
          isExempted = true;
          exemptionReason =
          'Company driver — exempted sa geofence (mobile work)';
        }
      } else {
        debugPrint('⚠️ [Geofence] Employee doc not found: $empId');
      }
    } catch (e) {
      debugPrint('⚠️ [Geofence] Exemption check failed: $e');
    }

    if (isExempted) {
      debugPrint('✅ [Geofence] EXEMPTED — $exemptionReason');
      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.exempted,
        message: '$exemptionReason.\n'
            'Pwede kang mag-time in kahit saan.',
        isExempted: true,
      ));
    }

    // ─── 2. Normal geofence check ───
    return checkGeofence();
  }

  // ══════════════════════════════════════════════════════════════════
  // NATIVE FLOW (Android / iOS)
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> _checkGeofenceNative() async {
    // 1. Check location services
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.serviceDisabled,
        message: 'Location services are disabled.\n'
            'Please enable GPS to clock in/out.',
      ));
    }

    // 2. Check at request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _emit(const GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.permissionDenied,
          message: 'Location permission denied.\n'
              'Grant permission to record attendance.',
        ));
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionPermanentlyDenied,
        message: 'Location permission permanently denied.\n'
            'Open App Settings → Permissions → Location.',
      ));
    }

    // 3. Loading state
    _emit(const GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.loading,
      message: 'Fetching current location...',
    ));

    // 4. Get position
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
        message: 'Location request timed out.\n'
            'Make sure GPS signal is strong and try again.',
      ));
    } catch (e) {
      debugPrint('❌ [Geofence] Native error: $e');
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location error: ${e.toString()}',
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // WEB FLOW (Chrome / Safari / Edge)
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> _checkGeofenceWeb() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ [Geofence Web] Location service disabled');
        return _emit(const GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.serviceDisabled,
          message: 'Location services are disabled.\n'
              'Please enable location in your device settings.',
        ));
      }
    } catch (e) {
      debugPrint('⚠️ [Geofence Web] serviceEnabled check failed: $e');
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('⚠️ [Geofence Web] Permission check failed: $e');
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionDenied,
        message: 'Location permission denied.\n'
            'Please allow location access in your browser to clock in.',
      ));
    }
    if (permission == LocationPermission.deniedForever) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionPermanentlyDenied,
        message: 'Location permission blocked.\n'
            'Reset it in your browser settings (🔒 icon in address bar).',
      ));
    }

    _emit(const GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.loading,
      message: 'Fetching your location...',
    ));

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return _evaluate(position);
    } on TimeoutException {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location request timed out.\n'
            'Please check your GPS signal and try again.',
      ));
    } catch (e) {
      debugPrint('❌ [Geofence Web] Error: $e');
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location error: ${e.toString()}',
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // MONITORING (live tracking)
  // ══════════════════════════════════════════════════════════════════
  Future<void> startMonitoring() async {
    await stopMonitoring();

    await _loadRadiusFromFirestore();

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

  // ══════════════════════════════════════════════════════════════════
  // LOCATION SETTINGS
  // ══════════════════════════════════════════════════════════════════
  LocationSettings _buildLocationSettings({int distanceFilter = 0}) {
    if (kIsWeb) {
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
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

  // ══════════════════════════════════════════════════════════════════
  // ⭐ MULTI-LOCATION EVALUATION
  //    Check kung nasa loob ng ALINMAN sa active zones
  // ══════════════════════════════════════════════════════════════════
  GeofenceResult _evaluate(Position position) {
    // Walang naka-set na zones
    if (_cachedZones.isEmpty) {
      debugPrint('⚠️ [Geofence] No zones configured — cannot evaluate');
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.outside,
        message: 'Walang naka-set na clock-in location.\n'
            'Kontakin ang admin para mag-set ng office zone.',
      ));
    }

    // Hanapin ang pinakamalapit at check kung nasa loob
    _LocationZone? best;
    double bestDist = double.infinity;
    _LocationZone? matchedZone;
    bool insideAny = false;

    for (final z in _cachedZones) {
      final d = _haversineDistance(
        lat1: position.latitude,
        lng1: position.longitude,
        lat2: z.lat,
        lng2: z.lng,
      );

      if (d < bestDist) {
        bestDist = d;
        best = z;
      }

      if (d <= z.radius) {
        insideAny = true;
        matchedZone = z;
        break; // ✅ Nasa loob na ng isang zone — ok na
      }
    }

    debugPrint('🔍 [Geofence] zones:${_cachedZones.length} | '
        'nearest:${best?.name}@${bestDist.toStringAsFixed(0)}m | '
        'inside:$insideAny | '
        'accuracy:${position.accuracy.toStringAsFixed(0)}m | '
        'platform:${kIsWeb ? "WEB" : defaultTargetPlatform.name}');

    // ─── INSIDE any zone ───
    if (insideAny) {
      final z = matchedZone ?? best;
      final dist = _haversineDistance(
        lat1: position.latitude,
        lng1: position.longitude,
        lat2: z!.lat,
        lng2: z.lng,
      );

      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.inside,
        distanceMeters: dist,
        accuracyMeters: position.accuracy,
        radiusUsed: z.radius,
        matchedLocationName: z.name,
        position: position,
        message: '✅ Nasa loob ka ng "${z.name}".\n'
            '${z.address.isNotEmpty ? z.address : ""}\n'
            'Distance: ${dist.toStringAsFixed(0)} m',
      ));
    }

    // ─── OUTSIDE lahat ng zones ───
    return _emit(GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.outside,
      distanceMeters: bestDist,
      accuracyMeters: position.accuracy,
      radiusUsed: best?.radius,
      matchedLocationName: best?.name,
      position: position,
      message: '❌ Wala ka sa loob ng anumang allowed zone.\n'
          'Nearest: "${best?.name ?? 'Unknown'}" '
          '(${bestDist.toStringAsFixed(0)} m away)\n'
          'Pumunta sa isang valid clock-in location.',
    ));
  }

  // ══════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════
  GeofenceResult _emit(GeofenceResult result) {
    _lastResult = result;
    if (!_statusController.isClosed) _statusController.add(result);
    return result;
  }

  double _haversineDistance({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earthRadius = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * (pi / 180);
}