// lib/services/geofence_service.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// Logs only in debug builds (hindi lalabas ang location sa release logcat)
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

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
  final bool usedTolerance;

  /// True kapag fake GPS / mock location ang nakita (Android).
  final bool isMockLocation;

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
    this.usedTolerance = false,
    this.isMockLocation = false,
  });

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
  insideWithTolerance,
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

  // ══════════════════════════════════════════════════════════════════
  // EMERGENCY ZONES — gagamitin LANG kapag pumalya ang Firestore
  // (network/permission error). Hindi gagamitin kung successful ang
  // Firestore pero walang active zone.
  // ══════════════════════════════════════════════════════════════════
  static const List<Map<String, dynamic>> _emergencyZones = [
    {
      'id': 'emergency_nepomuceno',
      'name': 'J. Nepomuceno Street',
      'address': '629 J. Nepomuceno St, Quiapo, Manila 1001',
      'lat': 14.59493,
      'lng': 120.989653,
      'radius': 50.0,
    },
    {
      'id': 'emergency_lacson',
      'name': 'A. H. Lacson Avenue',
      'address': '256 Lacson Ave, Sampaloc Manila 1008',
      'lat': 14.608012,
      'lng': 120.994361,
      'radius': 50.0,
    },
  ];

  // Legacy values (iniwan para hindi masira ang ibang screen na gumagamit)
  // ⚠️ Ang coordinates dito ay ~350m ang layo sa emergency zone ng
  // 629 J. Nepomuceno. I-check kung alin ang tama.
  static const double _officeLat = 14.59805;
  static const double _officeLng = 120.98917;
  static const String _officeAddress =
      '629 J. Nepomuceno St., Quiapo, Manila 1001';
  static const double _defaultRadiusMeters = 100.0;

  // ══════════════════════════════════════════════════════════════════
  // GPS ACCURACY / TOLERANCE
  // ══════════════════════════════════════════════════════════════════
  // Dating 80 / 150. Binawasan para hindi lumuwag nang sobra ang zone.
  static const double _baseToleranceMeters = 30.0;
  static const double _maxAccuracyConsidered = 60.0;

  // Kapag mas mahina pa rito ang GPS accuracy, hindi tatanggapin ang
  // reading (magpapa-ulit). Itaas kung maraming nahihirapan sa loob
  // ng building (hal. 150).
  static const double _maxAcceptableAccuracy = 100.0;

  // ══════════════════════════════════════════════════════════════════
  // STATE
  // ══════════════════════════════════════════════════════════════════
  StreamSubscription<QuerySnapshot>? _zonesSub;
  List<_LocationZone> _cachedZones = [];
  bool _zonesLoaded = false;
  bool _isUsingEmergency = false;
  DateTime? _zonesLoadedAt;

  final _statusController = StreamController<GeofenceResult>.broadcast();
  Stream<GeofenceResult> get statusStream => _statusController.stream;

  StreamSubscription<Position>? _positionSub;
  GeofenceResult? _lastResult;

  GeofenceResult? get lastResult => _lastResult;
  bool get isInsideGeofence => _lastResult?.isInside ?? false;
  double get allowedRadius =>
      _cachedZones.isNotEmpty ? _cachedZones.first.radius : _defaultRadiusMeters;
  int get zoneCount => _cachedZones.length;
  List<String> get zoneNames => _cachedZones.map((z) => z.name).toList();

  static String get officeAddress => _officeAddress;
  static double get officeLat => _officeLat;
  static double get officeLng => _officeLng;

  // ══════════════════════════════════════════════════════════════════
  // EMERGENCY ZONES BUILDER
  // ══════════════════════════════════════════════════════════════════
  List<_LocationZone> _buildEmergencyZones() {
    return _emergencyZones.map((z) {
      return _LocationZone(
        id: z['id'] as String,
        name: z['name'] as String,
        address: z['address'] as String,
        lat: (z['lat'] as num).toDouble(),
        lng: (z['lng'] as num).toDouble(),
        radius: (z['radius'] as num).toDouble(),
      );
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════════
  // REAL-TIME LISTENER
  // ══════════════════════════════════════════════════════════════════
  void startZonesListener() {
    if (_zonesSub != null) return;

    _log('🔄 [Geofence] Starting real-time listener...');

    _zonesSub = FirebaseFirestore.instance
        .collection('locations')
        .snapshots()
        .listen(
          (snap) {
        final activeDocs = snap.docs.where((doc) {
          final active = doc.data()['active'];
          return active == null || active == true;
        }).toList();

        // Kahit empty, ina-update. Ibig sabihin walang active zone ngayon
        // (hindi babalik sa emergency zones).
        final zones = _parseZones(activeDocs);
        _cachedZones = zones;
        _zonesLoaded = true;
        _isUsingEmergency = false;
        _zonesLoadedAt = DateTime.now();

        _log('🔔 [Geofence] ZONES UPDATED FROM FIRESTORE: ${zones.length}');
        for (int i = 0; i < zones.length; i++) {
          _log('   [$i] "${zones[i].name}"');
        }
      },
      onError: (e) {
        _log('❌ [Geofence] Listener error: $e');
      },
    );
  }

  void stopZonesListener() {
    _zonesSub?.cancel();
    _zonesSub = null;
  }

  List<_LocationZone> _parseZones(List<QueryDocumentSnapshot> docs) {
    final zones = <_LocationZone>[];
    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final radius =
      ((d['radius'] as num?)?.toDouble() ?? _defaultRadiusMeters)
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
    return zones;
  }

  void invalidateCache() {
    _zonesLoadedAt = null;
    _log('🔄 [Geofence] Cache invalidated');
  }

  Future<void> forceReload() async {
    invalidateCache();
    await _loadZonesOneTime();
  }

  // ══════════════════════════════════════════════════════════════════
  // LOAD ZONES — Firestore → Emergency (kapag FAILED lang)
  // ══════════════════════════════════════════════════════════════════
  Future<void> _loadZonesOneTime() async {
    _log('🌐 [Geofence] Fetching locations from Firestore...');

    // ═══ ATTEMPT 1: with active filter ═══
    try {
      final snap = await FirebaseFirestore.instance
          .collection('locations')
          .where('active', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 8));

      final zones = _parseZones(snap.docs);
      if (zones.isNotEmpty) {
        _setFirestoreZones(zones);
        _log('✅ [Geofence] LOADED ${zones.length} ZONE(S) (active query)');
        return;
      }
      // Empty — baka walang 'active' field ang mga dokumento.
      // Subukan ang full fetch sa attempt 2.
    } catch (e) {
      _log('❌ [Geofence] Active query FAILED: $e');
    }

    // ═══ ATTEMPT 2: fetch ALL, filter locally ═══
    try {
      final snap = await FirebaseFirestore.instance
          .collection('locations')
          .get()
          .timeout(const Duration(seconds: 8));

      final activeDocs = snap.docs.where((doc) {
        final active = doc.data()['active'];
        return active == null || active == true;
      }).toList();

      // Successful ang Firestore. Kahit empty ang resulta, ito ang totoo
      // (walang active zone) — HINDI babalik sa emergency zones.
      final zones = _parseZones(activeDocs);
      _setFirestoreZones(zones);
      _log('✅ [Geofence] LOADED ${zones.length} zone(s) (full fetch)');
      return;
    } catch (e) {
      _log('❌ [Geofence] Full fetch FAILED: $e');
    }

    // ═══ ATTEMPT 3: EMERGENCY — pumalya ang Firestore ═══
    _log('🚨 [Geofence] FIRESTORE FAILED — using EMERGENCY zones');
    _cachedZones = _buildEmergencyZones();
    _zonesLoaded = true;
    _isUsingEmergency = true;
    _zonesLoadedAt = DateTime.now();
  }

  void _setFirestoreZones(List<_LocationZone> zones) {
    _cachedZones = zones;
    _zonesLoaded = true;
    _isUsingEmergency = false;
    _zonesLoadedAt = DateTime.now();
  }

  Future<void> _ensureZonesLoaded() async {
    // Gagamitin lang ang cache kung may timestamp (kaya gumagana na
    // ang invalidateCache) at hindi pa luma.
    if (_zonesLoaded && _zonesLoadedAt != null) {
      final age = DateTime.now().difference(_zonesLoadedAt!);
      final cacheSecs = _isUsingEmergency ? 60 : 30;
      if (age.inSeconds < cacheSecs) {
        _log('💾 [Geofence] Using cached (${_cachedZones.length} zones, '
            'emergency=$_isUsingEmergency, ${age.inSeconds}s old)');
        return;
      }
    }

    await _loadZonesOneTime();
  }

  // ══════════════════════════════════════════════════════════════════
  // CHECK GEOFENCE
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> checkGeofence({bool forceRefresh = false}) async {
    _log('🌍 [Geofence] Starting check...');

    startZonesListener();

    if (forceRefresh) invalidateCache();

    await _ensureZonesLoaded();

    _log('📏 [Geofence] Zones: ${_cachedZones.length} | '
        'Emergency: $_isUsingEmergency');

    if (kIsWeb) return _checkGeofenceWeb();
    return _checkGeofenceNative();
  }

  Future<GeofenceResult> checkGeofenceForEmployee({
    required String employeeId,
    bool forceRefresh = false,
  }) async {
    final empId = employeeId.trim();
    if (empId.isEmpty) return checkGeofence(forceRefresh: forceRefresh);

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
        final position =
        (d['position'] ?? '').toString().toLowerCase().trim();
        final dept = (d['department'] ?? '').toString().toLowerCase().trim();

        bool has(String s) => s.contains('driver') || s.contains('rider');

        if (wfh) {
          isExempted = true;
          exemptionReason = 'WFH access is enabled';
        } else if (has(role) || has(position) || has(dept)) {
          isExempted = true;
          exemptionReason = 'Company driver';
        }
      }
    } catch (e) {
      _log('⚠️ [Geofence] Exemption check failed: $e');
    }

    if (isExempted) {
      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.exempted,
        message: '$exemptionReason.\nPwede kang mag-time in kahit saan.',
        isExempted: true,
      ));
    }

    return checkGeofence(forceRefresh: forceRefresh);
  }

  Future<Position?> _getBestAccuracyPosition() async {
    Position? bestPos;
    double bestAcc = double.infinity;

    for (int i = 0; i < 3; i++) {
      try {
        _log('📍 [Geofence] GPS attempt ${i + 1}/3...');

        // Kung magka-deprecation/build error sa bagong geolocator,
        // palitan ng: locationSettings: LocationSettings(accuracy: LocationAccuracy.best)
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('GPS timeout'),
        );

        _log('📍 [Geofence] Attempt ${i + 1}: '
            'acc=${p.accuracy.toStringAsFixed(1)}m mocked=${p.isMocked}');

        // Kapag may mock sa kahit isang reading, itatago natin
        // para hindi ito mawala sa best-accuracy selection.
        if (p.isMocked) {
          bestPos = p;
          break;
        }

        if (p.accuracy < bestAcc) {
          bestAcc = p.accuracy;
          bestPos = p;
          if (p.accuracy < 15.0) break;
        }

        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 600));
        }
      } catch (e) {
        _log('⚠️ [Geofence] Attempt ${i + 1} failed: $e');
        continue;
      }
    }

    return bestPos;
  }

  Future<GeofenceResult> _checkGeofenceNative() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.serviceDisabled,
        message: 'Location services disabled. Enable GPS.',
      ));
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return _emit(const GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.permissionDenied,
          message: 'Location permission denied.',
        ));
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionPermanentlyDenied,
        message: 'Location permission permanently denied.',
      ));
    }

    return _fetchAndEvaluate();
  }

  Future<GeofenceResult> _checkGeofenceWeb() async {
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      permission = LocationPermission.denied;
    }

    if (permission == LocationPermission.denied) {
      return _emit(const GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.permissionDenied,
        message: 'Location permission denied sa browser.',
      ));
    }

    return _fetchAndEvaluate();
  }

  Future<GeofenceResult> _fetchAndEvaluate() async {
    _emit(const GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.loading,
      message: 'Fetching location...',
    ));

    try {
      final position = await _getBestAccuracyPosition();
      if (position == null) {
        return _emit(const GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.error,
          message: 'Hindi makuha ang location.',
        ));
      }
      return _evaluate(position);
    } catch (e) {
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'Location error: $e',
      ));
    }
  }

  Future<void> startMonitoring() async {
    await stopMonitoring();
    startZonesListener();
    await _ensureZonesLoaded();

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(distanceFilter: 5),
    ).listen(
          (position) => _evaluate(position),
      onError: (e) => _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        message: 'GPS error: $e',
      )),
    );
  }

  Future<void> stopMonitoring() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  /// Hindi na sinasara ang stream controller dahil singleton ang service
  /// at magagamit pa ulit pagkatapos.
  void dispose() {
    stopMonitoring();
    stopZonesListener();
  }

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
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // EVALUATE — checks ALL zones
  // ══════════════════════════════════════════════════════════════════
  GeofenceResult _evaluate(Position position) {
    final isMock = position.isMocked;

    if (_cachedZones.isEmpty) {
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.outside,
        message: 'Walang naka-set na location.',
        isMockLocation: isMock,
      ));
    }

    final rawAccuracy = position.accuracy;

    // Masyadong mahina ang GPS — huwag mag-judge, magpa-ulit.
    // (Hindi ito ginagawa kapag mock, para ma-flag pa rin ang fake GPS.)
    if (!isMock && rawAccuracy > _maxAcceptableAccuracy) {
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.error,
        accuracyMeters: rawAccuracy,
        position: position,
        message: 'Mahina ang GPS signal (±${rawAccuracy.toStringAsFixed(0)}m).\n'
            'Lumabas sa bukas na lugar at subukan ulit.',
      ));
    }

    final clampedAccuracy = rawAccuracy.clamp(0.0, _maxAccuracyConsidered);
    final totalTolerance = _baseToleranceMeters + clampedAccuracy;

    _log('🔍 [Geofence] CHECKING ${_cachedZones.length} ZONE(S) | '
        'acc=±${rawAccuracy.toStringAsFixed(0)}m '
        'tol=${totalTolerance.toStringAsFixed(0)}m mock=$isMock');

    _LocationZone? nearest;
    double nearestDist = double.infinity;

    _LocationZone? exactZone;
    double exactDist = 0;

    _LocationZone? tolZone;
    double tolDist = double.infinity;

    for (int i = 0; i < _cachedZones.length; i++) {
      final z = _cachedZones[i];
      final d = _haversineDistance(
        lat1: position.latitude,
        lng1: position.longitude,
        lat2: z.lat,
        lng2: z.lng,
      );

      final effectiveRad = z.radius + totalTolerance;

      _log('   [$i] "${z.name}" dist=${d.toStringAsFixed(1)}m '
          'radius=${z.radius.toStringAsFixed(0)}m '
          'effective=${effectiveRad.toStringAsFixed(0)}m');

      if (d < nearestDist) {
        nearestDist = d;
        nearest = z;
      }

      if (d <= z.radius) {
        // Pinakamalapit na exact match
        if (exactZone == null || d < exactDist) {
          exactZone = z;
          exactDist = d;
        }
        continue;
      }

      // Pinakamalapit na tolerance match (hindi na "huling zone")
      if (d <= effectiveRad && d < tolDist) {
        tolZone = z;
        tolDist = d;
      }
    }

    _log('📊 Verdict: '
        '${(exactZone != null || tolZone != null) ? "ALLOWED" : "BLOCKED"}');

    if (exactZone != null) {
      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.inside,
        distanceMeters: exactDist,
        accuracyMeters: rawAccuracy,
        radiusUsed: exactZone.radius,
        matchedLocationName: exactZone.name,
        position: position,
        isMockLocation: isMock,
        message: '✅ Nasa loob ka ng "${exactZone.name}".\n'
            'Distance: ${exactDist.toStringAsFixed(0)} m',
      ));
    }

    if (tolZone != null) {
      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.insideWithTolerance,
        distanceMeters: tolDist,
        accuracyMeters: rawAccuracy,
        radiusUsed: tolZone.radius + totalTolerance,
        matchedLocationName: tolZone.name,
        position: position,
        usedTolerance: true,
        isMockLocation: isMock,
        message: '✅ Nasa loob ka ng "${tolZone.name}".\n'
            'Distance: ${tolDist.toStringAsFixed(0)} m',
      ));
    }

    final baseRadius = nearest?.radius ?? _defaultRadiusMeters;
    final effectiveRadius = baseRadius + totalTolerance;

    return _emit(GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.outside,
      distanceMeters: nearestDist,
      accuracyMeters: rawAccuracy,
      radiusUsed: effectiveRadius,
      matchedLocationName: nearest?.name,
      position: position,
      isMockLocation: isMock,
      message: '❌ Wala ka sa loob ng anumang zone.\n'
          'Nearest: "${nearest?.name ?? 'Unknown'}" '
          '(${nearestDist.toStringAsFixed(0)}m away)\n'
          'Allowed: ${effectiveRadius.toStringAsFixed(0)}m',
    ));
  }

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