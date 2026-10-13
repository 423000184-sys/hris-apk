// lib/services/client_location_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

// ═══════════════════════════════════════════════════════════════
// MODEL — isang registered client location
// ═══════════════════════════════════════════════════════════════
class ClientLocation {
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final double radiusMeters;
  final String? addedBy;
  final bool isActive;

  const ClientLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    this.address,
    this.addedBy,
    this.isActive = true,
  });

  factory ClientLocation.fromFirestore(Map<String, dynamic> data, String id) {
    return ClientLocation(
      id: id,
      name: (data['name'] ?? 'Unknown Client').toString(),
      address: data['address']?.toString(),
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? 100,
      addedBy: data['addedBy']?.toString(),
      isActive: data['isActive'] == true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// RESULT — validation result
// ═══════════════════════════════════════════════════════════════
class ClientLocationMatch {
  final ClientLocation? nearestClient;
  final double? distanceMeters;
  final bool isWithinRadius;
  final bool hasAnyRegisteredClient;
  final String? verificationMessage;

  const ClientLocationMatch({
    this.nearestClient,
    this.distanceMeters,
    this.isWithinRadius = false,
    this.hasAnyRegisteredClient = false,
    this.verificationMessage,
  });

  bool get isVerified => isWithinRadius && nearestClient != null;

  /// Anti-fraud: veredicto para sa admin side
  String get verdict {
    if (!hasAnyRegisteredClient) return 'no_registry';
    if (nearestClient == null) return 'unknown';
    if (isWithinRadius) return 'verified';
    return 'unverified';
  }

  static const ClientLocationMatch empty = ClientLocationMatch();
}

// ═══════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════
class ClientLocationService {
  ClientLocationService._();
  static final ClientLocationService instance = ClientLocationService._();

  final _fs = FirebaseFirestore.instance;

  List<ClientLocation>? _cachedLocations;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 10);

  // ─── Fetch all active clients (cached 10 min) ────────────────
  Future<List<ClientLocation>> getActiveLocations({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedLocations != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedLocations!;
    }

    try {
      final snap = await _fs
          .collection('client_locations')
          .where('isActive', isEqualTo: true)
          .get()
          .timeout(const Duration(seconds: 10));

      final list = snap.docs
          .map((d) => ClientLocation.fromFirestore(d.data(), d.id))
          .where((c) => c.lat != 0 && c.lng != 0)
          .toList();

      _cachedLocations = list;
      _cacheTime = DateTime.now();
      debugPrint(
          '📍 [ClientLocationService] Loaded ${list.length} registered client(s)');
      return list;
    } catch (e) {
      debugPrint('⚠️ [ClientLocationService] fetch failed: $e');
      return _cachedLocations ?? [];
    }
  }

  // ─── Validate coordinates against registry ───────────────────
  Future<ClientLocationMatch> validateLocation({
    required double lat,
    required double lng,
  }) async {
    if (lat == 0 && lng == 0) {
      return const ClientLocationMatch(
        hasAnyRegisteredClient: false,
        verificationMessage: 'No GPS coordinates',
      );
    }

    final locations = await getActiveLocations();
    if (locations.isEmpty) {
      return const ClientLocationMatch(
        hasAnyRegisteredClient: false,
        verificationMessage: 'No registered client locations yet',
      );
    }

    ClientLocation? nearest;
    double nearestDist = double.infinity;

    for (final c in locations) {
      final d = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = c;
      }
    }

    if (nearest == null) {
      return const ClientLocationMatch(
        hasAnyRegisteredClient: true,
        verificationMessage: 'No nearby client found',
      );
    }

    final within = nearestDist <= nearest.radiusMeters;

    return ClientLocationMatch(
      nearestClient: nearest,
      distanceMeters: nearestDist,
      isWithinRadius: within,
      hasAnyRegisteredClient: true,
      verificationMessage: within
          ? 'Verified at ${nearest.name}'
          : '${nearestDist.toStringAsFixed(0)}m away from ${nearest.name} '
          '(allowed: ${nearest.radiusMeters.toStringAsFixed(0)}m)',
    );
  }

  void invalidateCache() {
    _cachedLocations = null;
    _cacheTime = null;
  }

  // ─── Admin helper: seed default clients ──────────────────────
  Future<void> addClientLocation({
    required String name,
    required double lat,
    required double lng,
    String? address,
    double radiusMeters = 100,
    String addedBy = 'admin',
  }) async {
    await _fs.collection('client_locations').add({
      'name': name,
      'lat': lat,
      'lng': lng,
      'address': address,
      'radiusMeters': radiusMeters,
      'addedBy': addedBy,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    invalidateCache();
  }
}