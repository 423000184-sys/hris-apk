// lib/services/geofence_service.dart
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'client_location_service.dart';


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

  /// Field worker is outside every assigned zone and must submit a selfie.
  bool get needsProof => status == GeofenceStatus.fieldNeedsProof;

  /// Walang kahit isang active na location sa system.
  bool get isNoZones => status == GeofenceStatus.noZones;
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
  fieldNeedsProof,
  noZones,
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
  final String type; // 'office' | 'client'

  const _LocationZone({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.radius,
    this.type = 'office',
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

  // Legacy values
  static const double _officeLat = 14.59805;
  static const double _officeLng = 120.98917;
  static const String _officeAddress =
      '629 J. Nepomuceno St., Quiapo, Manila 1001';
  static const double _defaultRadiusMeters = 100.0;

  // ══════════════════════════════════════════════════════════════════
  // GPS ACCURACY / TOLERANCE
  // ══════════════════════════════════════════════════════════════════
  static const double _baseToleranceMeters = 30.0;
  static const double _maxAccuracyConsidered = 60.0;
  static const double _maxAcceptableAccuracy = 100.0;

  // ══════════════════════════════════════════════════════════════════
  // STATE
  // ══════════════════════════════════════════════════════════════════
  StreamSubscription<QuerySnapshot>? _zonesSub;
  List<_LocationZone> _cachedZones = [];
  bool _zonesLoaded = false;
  bool _isUsingEmergency = false;
  DateTime? _zonesLoadedAt;
  List<_LocationZone> _clientZones = [];

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

        final zones = _parseZones(activeDocs);
        _cachedZones = zones;
        _zonesLoaded = true;
        _isUsingEmergency = false;
        _zonesLoadedAt = DateTime.now();

        _log('🔔 [Geofence] ZONES UPDATED FROM FIRESTORE: ${zones.length}');
        for (int i = 0; i < zones.length; i++) {
          _log('   [$i] "${zones[i].name}" (type=${zones[i].type})');
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
        type: (d['type'] ?? 'office').toString().toLowerCase().trim(),
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
  // LOAD ZONES — Firestore → Emergency
  // ══════════════════════════════════════════════════════════════════
  Future<void> _loadZonesOneTime() async {
    _log('🌐 [Geofence] Fetching locations from Firestore...');

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
    } catch (e) {
      _log('❌ [Geofence] Active query FAILED: $e');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('locations')
          .get()
          .timeout(const Duration(seconds: 8));

      final activeDocs = snap.docs.where((doc) {
        final active = doc.data()['active'];
        return active == null || active == true;
      }).toList();

      final zones = _parseZones(activeDocs);
      _setFirestoreZones(zones);
      _log('✅ [Geofence] LOADED ${zones.length} zone(s) (full fetch)');
      return;
    } catch (e) {
      _log('❌ [Geofence] Full fetch FAILED: $e');
    }

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
  // ZONE SELECTION
  // ══════════════════════════════════════════════════════════════════
  Future<void> _loadClientZones({bool forceRefresh = false}) async {
    try {
      final list = await ClientLocationService.instance
          .getActiveLocations(forceRefresh: forceRefresh);
      _clientZones = list
          .map((c) => _LocationZone(
                id: c.id,
                name: c.name,
                address: c.address ?? '',
                lat: c.lat,
                lng: c.lng,
                radius: c.radiusMeters.clamp(20.0, 5000.0),
                type: 'client',
              ))
          .toList();
      _log('📍 [Geofence] client_locations loaded: ${_clientZones.length}');
    } catch (e) {
      _log('⚠️ [Geofence] client_locations load failed: $e');
    }
  }

  List<_LocationZone> _zonesFor(List<String>? siteIds) {
    final office = _cachedZones.where((z) => z.type != 'client');
    if (siteIds == null) return office.toList();
    final ids = siteIds.toSet();
    final seen = <String>{};
    final clients = [
      ..._cachedZones.where((z) => z.type == 'client'),
      ..._clientZones,
    ].where((z) => ids.contains(z.id) && seen.add(z.id));
    return [...office, ...clients];
  }

  // ══════════════════════════════════════════════════════════════════
  // CHECK GEOFENCE
  // ══════════════════════════════════════════════════════════════════
  Future<GeofenceResult> checkGeofence({
    bool forceRefresh = false,
    List<String>? siteIds,
  }) async {
    _log('🌍 [Geofence] Starting check...');

    startZonesListener();
    if (forceRefresh) invalidateCache();
     await _ensureZonesLoaded();
    if (siteIds != null) {
      await _loadClientZones(forceRefresh: forceRefresh);
    }

    _log('📏 [Geofence] Zones: ${_cachedZones.length} | '
        'Emergency: $_isUsingEmergency');

    final zones = _zonesFor(siteIds);
    _log('📏 [Geofence] Zones considered for this check: ${zones.length}');

    if (kIsWeb) return _checkGeofenceWeb(zones);
    return _checkGeofenceNative(zones);
  }

  Future<GeofenceResult> checkGeofenceForEmployee({
    required String employeeId,
    bool forceRefresh = false,
  }) async {
    final empId = employeeId.trim();
    if (empId.isEmpty) return checkGeofence(forceRefresh: forceRefresh);

    bool isExempted = false;
    bool isFieldWorker = false;
    List<String> siteIds = const [];
    String exemptionReason = '';

    try {
      Map<String, dynamic>? d;

      // Primary lookup: by doc ID
      try {
        final empDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get()
            .timeout(const Duration(seconds: 4));
        if (empDoc.exists) {
          d = empDoc.data();
        }
      } catch (_) {}

      // Fallback lookup: by employeeId field (if doc ID didn't match)
      if (d == null) {
        try {
          final q = await FirebaseFirestore.instance
              .collection('employees')
              .where('employeeId', isEqualTo: empId)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 4));
          if (q.docs.isNotEmpty) {
            d = q.docs.first.data();
          }
        } catch (_) {}
      }

      if (d != null) {
        final wfh = d['wfhAccess'] == true;
        final role = (d['role'] ?? '').toString().toLowerCase().trim();
        final position = (d['position'] ?? '').toString().toLowerCase().trim();
        final dept = (d['department'] ?? '').toString().toLowerCase().trim();

        bool has(String s) => s.contains('driver') || s.contains('rider');

        if (wfh) {
          isExempted = true;
          exemptionReason = 'WFH access is enabled';
        } else if (has(role) || has(position) || has(dept)) {
          isFieldWorker = true;
          siteIds = ((d['assignedSiteIds'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
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

    if (isFieldWorker) return _checkFieldWorker(siteIds, forceRefresh);

    return checkGeofence(forceRefresh: forceRefresh);
  }

  Future<GeofenceResult> _checkFieldWorker(
      List<String> siteIds, bool forceRefresh) async {
    final r = await checkGeofence(forceRefresh: forceRefresh, siteIds: siteIds);

    if (r.isAllowed ||
        r.isMockLocation ||
        (r.status != GeofenceStatus.outside &&
            r.status != GeofenceStatus.noZones)) {
      return r;
    }

    return _emit(GeofenceResult(
      isAllowed: false,
      status: GeofenceStatus.fieldNeedsProof,
      distanceMeters: r.distanceMeters,
      accuracyMeters: r.accuracyMeters,
      radiusUsed: r.radiusUsed,
      matchedLocationName: r.matchedLocationName,
      position: r.position,
      message: siteIds.isEmpty
          ? 'No client site is assigned to you.\nSubmit a selfie for HR review.'
          : 'You are not at an assigned client site.\nSubmit a selfie for HR review.',
    ));
  }

  Future<Position?> _getBestAccuracyPosition() async {
    Position? bestPos;
    double bestAcc = double.infinity;

    for (int i = 0; i < 3; i++) {
      try {
        _log('📍 [Geofence] GPS attempt ${i + 1}/3...');
        final p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('GPS timeout'),
        );

        _log('📍 [Geofence] Attempt ${i + 1}: '
            'acc=${p.accuracy.toStringAsFixed(1)}m mocked=${p.isMocked}');

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

  Future<GeofenceResult> _checkGeofenceNative(List<_LocationZone> zones) async {
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

    return _fetchAndEvaluate(zones);
  }

  Future<GeofenceResult> _checkGeofenceWeb(List<_LocationZone> zones) async {
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

    return _fetchAndEvaluate(zones);
  }

  Future<GeofenceResult> _fetchAndEvaluate(List<_LocationZone> zones) async {
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
      return _evaluate(position, zones: zones);
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
  // EVALUATE
  // ══════════════════════════════════════════════════════════════════
  GeofenceResult _evaluate(Position position, {List<_LocationZone>? zones}) {
    final zs = zones ?? _zonesFor(null);
    final isMock = position.isMocked;

    if (zs.isEmpty) {
      return _emit(GeofenceResult(
        isAllowed: false,
        status: GeofenceStatus.noZones,
        position: position,
        accuracyMeters: position.accuracy,
        message: 'Walang active na work zone.\nContact Admin.',
        isMockLocation: isMock,
      ));
    }

    final rawAccuracy = position.accuracy;

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

    _log('🔍 [Geofence] CHECKING ${zs.length} ZONE(S) | '
        'acc=±${rawAccuracy.toStringAsFixed(0)}m '
        'tol=${totalTolerance.toStringAsFixed(0)}m mock=$isMock');

    _LocationZone? nearest;
    double nearestDist = double.infinity;

    _LocationZone? exactZone;
    double exactDist = 0;

    _LocationZone? tolZone;
    double tolDist = double.infinity;

    for (int i = 0; i < zs.length; i++) {
      final z = zs[i];
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
        if (exactZone == null || d < exactDist) {
          exactZone = z;
          exactDist = d;
        }
        continue;
      }

      if (d <= effectiveRad && d < tolDist) {
        tolZone = z;
        tolDist = d;
      }
    }

    _log('📊 Verdict: '
        '${(exactZone != null || tolZone != null) ? "ALLOWED" : "BLOCKED"}');

    if (exactZone != null) {
      if (isMock) {
        return _emit(GeofenceResult(
          isAllowed: false,
          status: GeofenceStatus.error,
          distanceMeters: exactDist,
          accuracyMeters: rawAccuracy,
          radiusUsed: exactZone.radius,
          matchedLocationName: exactZone.name,
          position: position,
          isMockLocation: true,
          message: '🚨 Fake GPS detected.\n'
              'Patayin ang mock location apps at subukan ulit.',
        ));
      }
      return _emit(GeofenceResult(
        isAllowed: true,
        status: GeofenceStatus.inside,
        distanceMeters: exactDist,
        accuracyMeters: rawAccuracy,
        radiusUsed: exactZone.radius,
        matchedLocationName: exactZone.name,
        position: position,
        isMockLocation: false,
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