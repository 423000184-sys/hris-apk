// lib/screens/admin_tracking_page.dart
// v3.2: 🛡️ WEB SAFETY HARDENING
//   • _disposed flag guards every setState / map move / navigation
//   • MapController.move deferred to post-frame to avoid disposed view
//   • invalidateCache() throttled to 1x per second
//   • All async operations check _disposed before continuing
//   • Fixes: "Trying to render a disposed EngineFlutterView"
// v3.1: 🎯 AUTO EVERYTHING from ADDRESS (geocode → detect → radius)
// v3.0: 🏢 Building auto-detection via OSM Overpass API
// v2.3: 🎭 Demo Mode Support
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'admin_theme.dart';
import '../utils/geo_utils.dart';
import '../services/geofence_service.dart';
import '../services/employee_notification_service.dart';
import '../services/admin_auth_service.dart';
import '../services/demo_mode_service.dart';
import '../widgets/bootstrap_grid.dart';

class AdminTrackingPage extends StatefulWidget {
  final List<Map<String, dynamic>> locations;
  final double officeLat;
  final double officeLng;
  final double radiusLimit;
  final double Function(double, double, double, double) distanceCalculator;

  const AdminTrackingPage({
    super.key,
    required this.locations,
    required this.officeLat,
    required this.officeLng,
    required this.radiusLimit,
    required this.distanceCalculator,
  });

  @override
  State<AdminTrackingPage> createState() => _AdminTrackingPageState();
}

class _AdminTrackingPageState extends State<AdminTrackingPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  final MapController _mapController = MapController();

  // 🛡️ Web safety
  bool _disposed = false;
  bool get _safe => mounted && !_disposed;

  void _safeSetState(VoidCallback fn) {
    if (_safe) setState(fn);
  }

  void _safeMoveMap(LatLng point, double zoom) {
    if (!_safe) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_safe) return;
      try {
        _mapController.move(point, zoom);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ map move skipped: $e');
      }
    });
  }

  // 🛡️ Throttle cache invalidation (fixes "Cache invalidated" spam)
  DateTime? _lastCacheInvalidation;
  void _safeInvalidateCache() {
    final now = DateTime.now();
    if (_lastCacheInvalidation != null &&
        now.difference(_lastCacheInvalidation!) <
            const Duration(seconds: 1)) {
      return;
    }
    _lastCacheInvalidation = now;
    try {
      GeofenceService.instance.invalidateCache();
    } catch (_) {}
  }

  late double _currentLat;
  late double _currentLng;
  late double _currentRadius;

  int _selectedLocationIndex = 0;
  bool _isSaving = false;

  bool _autoClockOut = false;
  bool _geofenceViolation = false;
  bool _entryReminders = false;
  bool _eventAndHoliday = false;

  Timer? _radiusDebounce;

  StreamSubscription<QuerySnapshot>? _locSub;
  List<Map<String, dynamic>> _zones = [];
  bool _loadingZones = true;

  final _SecurityGuard _guard = _SecurityGuard();
  final Set<String> _inFlight = <String>{};
  bool _notifyingAll = false;

  void _demoBlock() {
    _snack('Action disabled in Demo Mode.', error: true);
  }

  List<Map<String, dynamic>> _getMockZones() {
    return [
      {
        'id': 'demo_loc_1',
        'name': 'Main Office (Demo)',
        'lat': 14.5547,
        'lng': 121.0244,
        'radius': 150.0,
        'active': true,
      },
      {
        'id': 'demo_loc_2',
        'name': 'Warehouse (Demo)',
        'lat': 14.6760,
        'lng': 121.0437,
        'radius': 200.0,
        'active': false,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _currentLat = widget.officeLat;
    _currentLng = widget.officeLng;
    _currentRadius = widget.radiusLimit.clamp(50.0, 2000.0);

    if (_isDemo) {
      _zones = _getMockZones();
      _loadingZones = false;
      _autoClockOut = true;
      _geofenceViolation = true;
    } else {
      _loadSettingsFromFirestore();
      _listenToLocations();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _radiusDebounce?.cancel();
    _radiusDebounce = null;
    _locSub?.cancel();
    _locSub = null;
    _inFlight.clear();
    super.dispose();
  }

  static String _sanitize(dynamic raw, {int maxLen = 120}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  static bool _isValidDocId(String id) {
    if (id.isEmpty || id.length > 1500) return false;
    if (id == '.' || id == '..') return false;
    if (id.contains('/')) return false;
    return true;
  }

  static bool _isValidLat(double lat) => GeoUtils.isValidLat(lat);
  static bool _isValidLng(double lng) => GeoUtils.isValidLng(lng);
  static bool _isValidRadius(double r) => GeoUtils.isValidRadius(r);

  String _safeError(Object e) {
    if (kDebugMode) return e.toString();
    return 'Something went wrong. Please try again.';
  }

  Future<User?> _currentAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      await u.getIdToken(true);
      return u;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _ensureAdmin() async {
    if (_isDemo) return 'Admin actions disabled in Demo Mode.';
    final admin = await _currentAdmin();
    if (admin == null) return 'Session expired. Please sign in again.';
    return null;
  }

  Future<void> _audit({
    required String action,
    required String targetId,
    required String targetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_action',
        'action': action,
        'targetId': targetId,
        'targetType': targetType,
        'actorUid': uid,
        'metadata': metadata ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ audit log failed: $e');
    }
  }

  void _listenToLocations() {
    _locSub?.cancel();
    _locSub = FirebaseFirestore.instance
        .collection('locations')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snap) {
        if (!_safe) return;
        final list = snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        _safeSetState(() {
          _zones = list;
          _loadingZones = false;
        });
        if (list.isNotEmpty && _selectedLocationIndex >= list.length) {
          _selectedLocationIndex = 0;
        }
      },
      onError: (e) {
        debugPrint('⚠️ [Tracking] locations stream error: $e');
        if (!_safe) return;
        _safeSetState(() => _loadingZones = false);
      },
    );
  }

  Future<void> _loadSettingsFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get();

      if (!_safe) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _safeSetState(() {
          _autoClockOut = (data['autoClockOut'] as bool?) ?? false;
          _geofenceViolation =
              (data['geofenceViolation'] as bool?) ?? false;
          _entryReminders = (data['entryReminders'] as bool?) ?? false;
          _eventAndHoliday = (data['eventAndHoliday'] as bool?) ?? false;

          if (data['globalRadius'] != null) {
            final r = (data['globalRadius'] as num).toDouble();
            _currentRadius =
            _isValidRadius(r) ? r : r.clamp(50.0, 2000.0);
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Admin] Error loading settings: $e');
    }
  }

  Future<void> _autoSaveConfig() async {
    if (!_safe) return;
    if (_isDemo) return;
    if (!_guard.tryAcquire('autosave_config')) return;
    if (_inFlight.contains('autosave')) return;

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) return;
    if (!_isValidRadius(_currentRadius)) return;

    _inFlight.add('autosave');
    try {
      final admin = await _currentAdmin();
      if (!_safe) return;
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .set({
        'autoClockOut': _autoClockOut,
        'geofenceViolation': _geofenceViolation,
        'entryReminders': _entryReminders,
        'eventAndHoliday': _eventAndHoliday,
        'globalRadius': _currentRadius,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': admin?.uid,
      }, SetOptions(merge: true));

      _safeInvalidateCache();
    } catch (e) {
      debugPrint('❌ [Admin] Auto-save error: $e');
    } finally {
      _inFlight.remove('autosave');
    }
  }

  Future<void> _saveConfigToFirestore() async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();
    if (_inFlight.contains('force_save')) return;
    if (!_guard.tryAcquire('force_save')) {
      _snack('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }
    if (!_isValidRadius(_currentRadius)) {
      _snack('Invalid radius value.', error: true);
      return;
    }

    _inFlight.add('force_save');
    _safeSetState(() => _isSaving = true);
    try {
      final admin = await _currentAdmin();
      if (!_safe) return;
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .set({
        'autoClockOut': _autoClockOut,
        'geofenceViolation': _geofenceViolation,
        'entryReminders': _entryReminders,
        'eventAndHoliday': _eventAndHoliday,
        'globalRadius': _currentRadius,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': admin?.uid,
      }, SetOptions(merge: true));

      _safeInvalidateCache();

      unawaited(_audit(
        action: 'update_geofence_config',
        targetId: 'geofence_config',
        targetType: 'settings',
        metadata: {'globalRadius': _currentRadius},
      ));

      _snack('Geofence saved! Radius: ${_currentRadius.toInt()}m');
    } catch (e) {
      _snack(_safeError(e), error: true);
    } finally {
      _inFlight.remove('force_save');
      _safeSetState(() => _isSaving = false);
    }
  }

  Future<void> _sendHolidayNotification() async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();
    if (_notifyingAll) return;
    if (!_guard.tryAcquire('holiday_notify')) {
      _snack('Masyadong mabilis.', error: true);
      return;
    }

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Send to ALL employees?',
            style: TextStyle(color: tc.text)),
        content: Text(
          'Ipapadala ang holiday/event announcement sa LAHAT ng empleyado. Sigurado ka ba?',
          style: TextStyle(color: tc.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send to All'),
          ),
        ],
      ),
    );
    if (!_safe) return;
    if (ok != true) return;

    _notifyingAll = true;
    try {
      await EmployeeNotificationService.instance.sendAnnouncement(
        title: '🎉 Event / Holiday Announcement',
        message:
        'An Event or Holiday has been scheduled. Please check your calendar and stay safe! — Admin',
        employeeId: 'ALL',
        priority: 'high',
      );

      unawaited(_audit(
        action: 'broadcast_holiday_announcement',
        targetId: 'ALL',
        targetType: 'announcement',
        metadata: {'scope': 'all_employees'},
      ));

      _snack('✅ Holiday notification sent to ALL employees!');
    } catch (e) {
      debugPrint('❌ [Admin] Holiday notification failed: $e');
      _snack(_safeError(e), error: true);
    } finally {
      _notifyingAll = false;
    }
  }

  void _moveMapToPosition(double lat, double lng) {
    if (!_isValidLat(lat) || !_isValidLng(lng)) return;
    _safeMoveMap(LatLng(lat, lng), 15.5);
  }

  Future<void> _openAddLocationDialog() async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationDialog(
        defaultLat: _currentLat,
        defaultLng: _currentLng,
        defaultRadius: _currentRadius,
      ),
    );
    if (!_safe) return;
    if (created == true) {
      _safeInvalidateCache();
      _snack('Location added successfully!');
    }
  }

  Future<void> _openEditLocationDialog(Map<String, dynamic> loc) async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();

    final id = (loc['id'] ?? '').toString();
    if (!_isValidDocId(id)) {
      _snack('Invalid location reference.', error: true);
      return;
    }

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationDialog(existing: loc),
    );
    if (!_safe) return;
    if (updated == true) {
      _safeInvalidateCache();
      _snack('Location updated.');
    }
  }

  Future<void> _confirmDeleteLocation(Map<String, dynamic> loc) async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();

    final id = (loc['id'] ?? '').toString();
    if (!_isValidDocId(id)) {
      _snack('Invalid location reference.', error: true);
      return;
    }
    if (_inFlight.contains('del_$id')) return;
    if (!_guard.tryAcquire('delete_location')) {
      _snack('Masyadong mabilis.', error: true);
      return;
    }

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    final name = _sanitize(loc['name'] ?? 'Location', maxLen: 60);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Delete Location?', style: TextStyle(color: tc.text)),
        content: Text(
          'Sigurado ka bang gusto mong i-delete ang "$name"?\n'
              'Hindi na ito magiging valid clock-in zone.',
          style: TextStyle(color: tc.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!_safe) return;
    if (ok != true) return;

    _inFlight.add('del_$id');
    try {
      final admin = await _currentAdmin();
      if (!_safe) return;
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(id)
          .delete();

      _safeInvalidateCache();

      unawaited(_audit(
        action: 'delete_location',
        targetId: id,
        targetType: 'location',
        metadata: {'name': name, 'actorUid': admin?.uid},
      ));

      _snack('Location deleted.');
    } catch (e) {
      _snack(_safeError(e), error: true);
    } finally {
      _inFlight.remove('del_$id');
    }
  }

  Future<void> _toggleLocationActive(Map<String, dynamic> loc) async {
    if (!_safe) return;
    if (_isDemo) return _demoBlock();

    final id = (loc['id'] ?? '').toString();
    if (!_isValidDocId(id)) {
      _snack('Invalid location reference.', error: true);
      return;
    }
    if (_inFlight.contains('tog_$id')) return;
    if (!_guard.tryAcquire('toggle_location')) {
      _snack('Masyadong mabilis.', error: true);
      return;
    }

    final err = await _ensureAdmin();
    if (!_safe) return;
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    final current = loc['active'] != false;
    _inFlight.add('tog_$id');
    try {
      final admin = await _currentAdmin();
      if (!_safe) return;
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(id)
          .update({
        'active': !current,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': admin?.uid,
      });

      _safeInvalidateCache();

      unawaited(_audit(
        action: !current ? 'enable_location' : 'disable_location',
        targetId: id,
        targetType: 'location',
        metadata: {'name': _sanitize(loc['name'] ?? '', maxLen: 60)},
      ));

      _snack(!current ? 'Location enabled.' : 'Location disabled.');
    } catch (e) {
      _snack(_safeError(e), error: true);
    } finally {
      _inFlight.remove('tog_$id');
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!_safe) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor: error ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: BsContainer(
          maxWidth: 1600,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 24),
              ],
              _buildHeader(),
              const SizedBox(height: 20),
              _buildMainGrid(),
              const SizedBox(height: 20),
              _buildAutomationCard(),
              const SizedBox(height: 20),
              _buildActionButtons(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.orange.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, color: tc.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo Mode Active',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tc.orange,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Showing sample data. Modifying geofence settings and locations is disabled.',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Geofencing & Locations',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: tc.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Type an address — the system auto-detects the building size and sets the radius.',
                style: TextStyle(fontSize: 13, color: tc.muted),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isDemo ? tc.border : tc.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _isDemo
                        ? tc.border
                        : tc.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_rounded,
                      size: 11, color: _isDemo ? tc.muted : tc.green),
                  const SizedBox(width: 4),
                  Text(_isDemo ? 'AUTO-SAVE OFF' : 'AUTO-SAVE ON',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: _isDemo ? tc.muted : tc.green,
                          letterSpacing: 0.5)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final r = BsResponsive(w);
        final isDesktop = r.up(BsSize.lg);

        if (isDesktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildOpenStreetMapCard()),
              const SizedBox(width: 20),
              Expanded(flex: 1, child: _buildActiveLocationsPanel()),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildOpenStreetMapCard(),
            const SizedBox(height: 20),
            _buildActiveLocationsPanel(),
          ],
        );
      },
    );
  }

  Widget _buildOpenStreetMapCard() {
    LatLng centerPoint = LatLng(_currentLat, _currentLng);
    final circles = <CircleMarker>[];
    final markers = <Marker>[];

    for (int i = 0; i < _zones.length; i++) {
      final z = _zones[i];
      final lat = (z['lat'] as num?)?.toDouble();
      final lng = (z['lng'] as num?)?.toDouble();
      final radius =
      ((z['radius'] as num?)?.toDouble() ?? 100).clamp(20.0, 5000.0);
      final active = z['active'] != false;
      final selected = i == _selectedLocationIndex;

      if (lat == null || lng == null) continue;
      if (!_isValidLat(lat) || !_isValidLng(lng)) continue;

      final color = !active ? Colors.grey : (selected ? tc.orange : tc.blue);

      circles.add(CircleMarker(
        point: LatLng(lat, lng),
        radius: radius,
        useRadiusInMeter: true,
        color: color.withValues(alpha: active ? 0.18 : 0.08),
        borderColor: color.withValues(alpha: active ? 1.0 : 0.5),
        borderStrokeWidth: selected ? 3 : 2,
      ));

      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: Icon(
          Icons.location_on,
          color: color,
          size: selected ? 40 : 34,
        ),
      ));
    }

    if (circles.isEmpty &&
        _isValidLat(_currentLat) &&
        _isValidLng(_currentLng)) {
      circles.add(CircleMarker(
        point: centerPoint,
        radius: _currentRadius,
        useRadiusInMeter: true,
        color: tc.orange.withValues(alpha: 0.2),
        borderColor: tc.orange,
        borderStrokeWidth: 2.5,
      ));
      markers.add(Marker(
        point: centerPoint,
        width: 40,
        height: 40,
        child: Icon(Icons.location_on, color: tc.orange, size: 38),
      ));
    }

    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: centerPoint,
                initialZoom: 15.5,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hris.biometrics',
                ),
                CircleLayer(circles: circles),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: tc.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tc.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            if (!_safe) return;
                            try {
                              _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom + 0.5);
                            } catch (_) {}
                          },
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child:
                            Icon(Icons.add, size: 16, color: tc.text),
                          ),
                        ),
                        Container(height: 1, width: 32, color: tc.border),
                        InkWell(
                          onTap: () {
                            if (!_safe) return;
                            try {
                              _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom - 0.5);
                            } catch (_) {}
                          },
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(Icons.remove,
                                size: 16, color: tc.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () =>
                        _moveMapToPosition(_currentLat, _currentLng),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: tc.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tc.border),
                      ),
                      child:
                      Icon(Icons.my_location, size: 14, color: tc.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveLocationsPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Active Locations',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add new location',
                child: InkWell(
                  onTap: _isDemo ? _demoBlock : _openAddLocationDialog,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _isDemo ? tc.border : const Color(0xFFFF8A00),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add,
                        color: _isDemo ? tc.muted : Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingZones)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tc.orange),
                ),
              ),
            )
          else if (_zones.isEmpty)
            _buildEmptyLocations()
          else
            Column(
              children: _zones.asMap().entries.map((entry) {
                final index = entry.key;
                final loc = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _zones.length - 1 ? 0 : 12,
                  ),
                  child: _buildLocationCard(loc, index),
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tc.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'GLOBAL DEFAULT RADIUS',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: tc.muted,
                            letterSpacing: 0.5),
                      ),
                    ),
                    Icon(Icons.cloud_done_rounded,
                        size: 11, color: _isDemo ? tc.muted : tc.green),
                    const SizedBox(width: 4),
                    Text(_isDemo ? 'off' : 'auto',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _isDemo ? tc.muted : tc.green)),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: _isDemo ? tc.muted : tc.orange,
                    inactiveTrackColor: tc.border,
                    thumbColor: _isDemo ? tc.muted : tc.card,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8, elevation: 2),
                    overlayColor:
                    (_isDemo ? tc.muted : tc.orange)
                        .withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _currentRadius.clamp(50.0, 2000.0),
                    min: 50.0,
                    max: 2000.0,
                    onChanged: _isDemo
                        ? null
                        : (val) {
                      _safeSetState(() => _currentRadius = val);
                      _radiusDebounce?.cancel();
                      _radiusDebounce = Timer(
                        const Duration(milliseconds: 800),
                            () {
                          if (!_safe) return;
                          _autoSaveConfig();
                        },
                      );
                    },
                    onChangeEnd: _isDemo
                        ? null
                        : (_) {
                      _radiusDebounce?.cancel();
                      _autoSaveConfig();
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text('50m',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: tc.muted)),
                    ),
                    Text(
                      'Current: ${_currentRadius.toInt()}m',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _isDemo ? tc.muted : tc.orange),
                    ),
                    Expanded(
                      child: Text('2000m',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: tc.muted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLocations() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border:
        Border.all(color: tc.orange.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Icon(Icons.location_off_rounded, size: 32, color: tc.muted),
          const SizedBox(height: 8),
          Text('Wala pang locations.',
              style: TextStyle(color: tc.text, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'I-tap ang (+) button para mag-add ng clock-in zone.',
            style: TextStyle(color: tc.muted, fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isDemo ? _demoBlock : _openAddLocationDialog,
            icon: const Icon(Icons.add_location_alt_rounded, size: 14),
            label: const Text('Add First Location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _isDemo ? tc.muted : tc.orange,
              side: BorderSide(color: _isDemo ? tc.border : tc.orange),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> loc, int index) {
    final bool isSelected = _selectedLocationIndex == index;
    final bool isActive = loc['active'] != false;

    final String title =
    _sanitize(loc['name'] ?? 'Unnamed Location', maxLen: 60);
    final String address = _sanitize(loc['address'] ?? '', maxLen: 150);
    final double lat = (loc['lat'] as num?)?.toDouble() ?? widget.officeLat;
    final double lng = (loc['lng'] as num?)?.toDouble() ?? widget.officeLng;
    final double radius =
        (loc['radius'] as num?)?.toDouble() ?? _currentRadius;

    return GestureDetector(
      onTap: () {
        if (!_safe) return;
        if (!_isValidLat(lat) || !_isValidLng(lng)) return;
        _safeSetState(() {
          _selectedLocationIndex = index;
          _currentLat = lat;
          _currentLng = lng;
        });
        _moveMapToPosition(lat, lng);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (_isDemo ? tc.border : tc.orange)
                : (!isActive
                ? tc.border.withValues(alpha: 0.5)
                : tc.border),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isActive ? tc.text : tc.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                if (!isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: tc.pillErrBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('OFF',
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: tc.pillErrTx)),
                  ),
                const SizedBox(width: 4),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? (_isDemo ? tc.border : tc.orange)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? (_isDemo ? tc.border : tc.orange)
                          : tc.muted,
                    ),
                  ),
                  child: isSelected
                      ? Icon(Icons.check,
                      size: 10,
                      color: _isDemo ? tc.muted : Colors.white)
                      : null,
                ),
              ],
            ),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(address,
                  style: TextStyle(fontSize: 11, color: tc.muted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RADIUS',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: tc.muted)),
                      const SizedBox(height: 2),
                      Text('${radius.toInt()}m',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tc.text)),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COORDINATES',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: tc.muted)),
                      const SizedBox(height: 2),
                      Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _miniBtn(
                  icon: isActive
                      ? Icons.toggle_off_rounded
                      : Icons.toggle_on_rounded,
                  color: _isDemo
                      ? tc.muted
                      : (isActive ? tc.muted : tc.green),
                  tooltip: isActive ? 'Disable' : 'Enable',
                  onTap: () => _toggleLocationActive(loc),
                ),
                const SizedBox(width: 4),
                _miniBtn(
                  icon: Icons.edit_outlined,
                  color: _isDemo ? tc.muted : tc.orange,
                  tooltip: 'Edit',
                  onTap: () => _openEditLocationDialog(loc),
                ),
                const SizedBox(width: 4),
                _miniBtn(
                  icon: Icons.delete_outline_rounded,
                  color: _isDemo ? tc.muted : tc.red,
                  tooltip: 'Delete',
                  onTap: () => _confirmDeleteLocation(loc),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildAutomationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_none_rounded,
                  color: tc.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Automation & Notifications',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 800.0;

            const double gap = 16;
            final int cols;
            if (w >= 1200) {
              cols = 4;
            } else if (w >= 800) {
              cols = 3;
            } else if (w >= 500) {
              cols = 2;
            } else {
              cols = 1;
            }
            final double itemWidth = (w - (cols - 1) * gap) / cols;

            final cards = <Widget>[
              _buildToggleCard(
                title: 'Auto Clock-Out',
                subtitle: 'When staff leaves zone',
                value: _autoClockOut,
                onChanged: (v) async {
                  _safeSetState(() => _autoClockOut = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Geofence Violation',
                subtitle: 'Alert admins on deviation',
                value: _geofenceViolation,
                onChanged: (v) async {
                  _safeSetState(() => _geofenceViolation = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Entry Reminders',
                subtitle: 'Push notice at perimeter',
                value: _entryReminders,
                onChanged: (v) async {
                  _safeSetState(() => _entryReminders = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Event and Holiday',
                subtitle: 'When Holiday or Event occurs',
                value: _eventAndHoliday,
                onChanged: (v) async {
                  _safeSetState(() => _eventAndHoliday = v);
                  await _autoSaveConfig();
                  if (v && !_isDemo && _safe) {
                    await _sendHolidayNotification();
                  }
                },
              ),
            ];

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: cards
                  .map((c) => SizedBox(width: itemWidth, child: c))
                  .toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? (_isDemo ? tc.border : tc.orange.withValues(alpha: 0.5))
              : tc.border,
          width: value ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tc.text),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value
                            ? (_isDemo ? tc.muted : tc.green)
                            : tc.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      value ? 'ON' : 'OFF',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: value
                              ? (_isDemo ? tc.muted : tc.green)
                              : tc.muted,
                          letterSpacing: 0.3),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        subtitle,
                        style: TextStyle(fontSize: 11, color: tc.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: _isDemo ? tc.muted : tc.orange,
            activeTrackColor:
            (_isDemo ? tc.muted : tc.orange).withValues(alpha: 0.4),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: tc.muted,
            onChanged: _isDemo ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final narrow = w < 500;

        final discardBtn = OutlinedButton(
          onPressed: _loadSettingsFromFirestore,
          style: OutlinedButton.styleFrom(
            backgroundColor: tc.card,
            foregroundColor: tc.text,
            side: BorderSide(color: tc.border),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Reload from Server',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        );

        final addBtn = ElevatedButton.icon(
          onPressed: _isDemo ? _demoBlock : _openAddLocationDialog,
          icon: const Icon(Icons.add_location_alt_rounded, size: 16),
          label: const Text('Add Location'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isDemo ? tc.border : tc.green,
            foregroundColor: _isDemo ? tc.muted : Colors.white,
            elevation: 2,
            shadowColor:
            (_isDemo ? tc.border : tc.green).withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        final saveBtn = ElevatedButton.icon(
          onPressed: (_isDemo || _isSaving) ? null : _saveConfigToFirestore,
          icon: _isSaving
              ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.refresh_rounded, size: 16),
          label: Text(_isSaving ? 'Saving...' : 'Force Sync Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isDemo ? tc.border : tc.orange,
            foregroundColor: _isDemo ? tc.muted : Colors.white,
            elevation: 2,
            shadowColor:
            (_isDemo ? tc.border : tc.orange).withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              addBtn,
              const SizedBox(height: 10),
              saveBtn,
              const SizedBox(height: 10),
              discardBtn,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.max,
          children: [
            discardBtn,
            const SizedBox(width: 12),
            addBtn,
            const SizedBox(width: 12),
            saveBtn,
          ],
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// BUILDING INFO MODEL
// ══════════════════════════════════════════════════════════════════
class _BuildingInfo {
  final LatLng center;
  final double radiusMeters;
  final double widthMeters;
  final double heightMeters;
  final List<LatLng> outline;

  const _BuildingInfo({
    required this.center,
    required this.radiusMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.outline,
  });
}

// ══════════════════════════════════════════════════════════════════
// ADD / EDIT LOCATION DIALOG
// ══════════════════════════════════════════════════════════════════
class _LocationDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final double? defaultLat;
  final double? defaultLng;
  final double? defaultRadius;

  const _LocationDialog({
    this.existing,
    this.defaultLat,
    this.defaultLng,
    this.defaultRadius,
  });

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _radiusCtrl;

  final MapController _dialogMapCtrl = MapController();
  LatLng? _pickedPoint;
  _BuildingInfo? _detectedBuilding;

  // 🛡️ Web safety — fixes "disposed EngineFlutterView"
  bool _disposed = false;
  bool get _safe => mounted && !_disposed;

  void _safeSetState(VoidCallback fn) {
    if (_safe) setState(fn);
  }

  void _safeMoveMap(LatLng point, double zoom) {
    if (!_safe) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_safe) return;
      try {
        _dialogMapCtrl.move(point, zoom);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ dialog map move skipped: $e');
      }
    });
  }

  // Pipeline status
  bool _searching = false;
  bool _detecting = false;
  String? _statusText;
  bool _statusIsError = false;

  Timer? _addressDebounce;
  int _pipelineGeneration = 0;

  final List<DateTime> _geocodeCalls = [];
  static const int _maxGeocodePerMinute = 10;

  final Map<String, LatLng?> _geocodeCache = {};
  final Map<String, _BuildingInfo?> _buildingCache = {};

  bool _saving = false;
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? {};

    final initLat =
        (e['lat'] as num?)?.toDouble() ?? widget.defaultLat ?? 14.598050;
    final initLng =
        (e['lng'] as num?)?.toDouble() ?? widget.defaultLng ?? 120.989170;
    if (GeoUtils.isValidLat(initLat) && GeoUtils.isValidLng(initLng)) {
      _pickedPoint = LatLng(initLat, initLng);
    }

    _nameCtrl = TextEditingController(
        text: _sanitize(e['name'] ?? '', maxLen: 60));
    _addressCtrl = TextEditingController(
        text: _sanitize(e['address'] ?? '', maxLen: 150));
    _latCtrl = TextEditingController(
        text: _isValidLat(initLat) ? initLat.toStringAsFixed(6) : '14.598050');
    _lngCtrl = TextEditingController(
        text:
        _isValidLng(initLng) ? initLng.toStringAsFixed(6) : '120.989170');

    final r =
        ((e['radius'] as num?)?.toDouble()) ?? widget.defaultRadius ?? 100;
    _radiusCtrl = TextEditingController(
        text: (_isValidRadius(r) ? r : 100).toStringAsFixed(0));

    _addressCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _pipelineGeneration++; // cancel all in-flight
    _addressDebounce?.cancel();
    _addressDebounce = null;
    _addressCtrl.removeListener(_onAddressChanged);
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  static String _sanitize(dynamic raw, {int maxLen = 120}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  static bool _isValidLat(double v) => GeoUtils.isValidLat(v);
  static bool _isValidLng(double v) => GeoUtils.isValidLng(v);
  static bool _isValidRadius(double v) => GeoUtils.isValidRadius(v);

  double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  void _onAddressChanged() {
    if (!_safe) return;
    final q = _addressCtrl.text.trim();
    _addressDebounce?.cancel();

    if (q.length < 5) {
      if (_statusText != null) {
        _safeSetState(() {
          _statusText = null;
          _autoFilled = false;
        });
      }
      return;
    }

    _addressDebounce = Timer(const Duration(milliseconds: 900), () {
      if (!_safe) return;
      _runAutoPipeline(q);
    });

    _safeSetState(() {
      _statusText = '⏳ Type more... auto-detect will start in a moment';
      _statusIsError = false;
    });
  }

  bool _geocodeRateOk() {
    final now = DateTime.now();
    _geocodeCalls
        .removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_geocodeCalls.length >= _maxGeocodePerMinute) return false;
    _geocodeCalls.add(now);
    return true;
  }

  Future<void> _runAutoPipeline(String rawQuery) async {
    if (!_safe) return;
    final cleanQuery = _sanitize(rawQuery, maxLen: 150);
    if (cleanQuery.length < 5) return;

    final myGen = ++_pipelineGeneration;

    _safeSetState(() {
      _searching = true;
      _detecting = false;
      _statusText = '🔍 Searching: "$cleanQuery"...';
      _statusIsError = false;
    });

    final latLng = await _geocodeAddress(cleanQuery);

    if (!_safe || myGen != _pipelineGeneration) return;

    if (latLng == null) {
      _safeSetState(() {
        _searching = false;
        _detecting = false;
        _statusText = '❌ Address not found. Try a more specific one.';
        _statusIsError = true;
      });
      return;
    }

    _latCtrl.text = latLng.latitude.toStringAsFixed(6);
    _lngCtrl.text = latLng.longitude.toStringAsFixed(6);
    _pickedPoint = latLng;
    _safeMoveMap(latLng, 17.0);

    _safeSetState(() {
      _searching = false;
      _detecting = true;
      _statusText = '🏢 Building found — detecting size...';
      _statusIsError = false;
    });

    final building = await _detectBuildingAt(latLng);

    if (!_safe || myGen != _pipelineGeneration) return;

    if (building != null) {
      _latCtrl.text = building.center.latitude.toStringAsFixed(6);
      _lngCtrl.text = building.center.longitude.toStringAsFixed(6);
      _radiusCtrl.text = building.radiusMeters.toStringAsFixed(0);

      _safeSetState(() {
        _pickedPoint = building.center;
        _detectedBuilding = building;
        _autoFilled = true;
        _detecting = false;
        _statusText = '✅ ${building.widthMeters.toStringAsFixed(0)}m × '
            '${building.heightMeters.toStringAsFixed(0)}m — '
            'radius auto-set to ${building.radiusMeters.toStringAsFixed(0)}m';
        _statusIsError = false;
      });

      _safeMoveMap(building.center, 17.0);
    } else {
      _radiusCtrl.text = '100';
      _safeSetState(() {
        _detectedBuilding = null;
        _autoFilled = false;
        _detecting = false;
        _statusText = '⚠️ Building not in OSM — default 100m applied. '
            'Adjust radius manually if needed.';
        _statusIsError = true;
      });
    }
  }

  Future<LatLng?> _geocodeAddress(String query) async {
    final key = query.toLowerCase().trim();
    if (_geocodeCache.containsKey(key)) return _geocodeCache[key];

    if (!_geocodeRateOk()) {
      if (_safe) {
        _safeSetState(() {
          _searching = false;
          _statusText = '⚠️ Too many lookups. Wait 1 minute.';
          _statusIsError = true;
        });
      }
      return null;
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'addressdetails': '1',
        'limit': '1',
      });

      final headers = <String, String>{'Accept': 'application/json'};
      if (!kIsWeb) headers['User-Agent'] = 'RACOMA-HRIS/1.0';

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _geocodeCache[key] = null;
        return null;
      }

      final decoded = jsonDecode(response.body);
      final List<dynamic> list = decoded is List ? decoded : <dynamic>[];
      if (list.isEmpty) {
        _geocodeCache[key] = null;
        return null;
      }

      final first = list.first;
      if (first is! Map) {
        _geocodeCache[key] = null;
        return null;
      }

      final lat = double.tryParse((first['lat'] ?? '').toString());
      final lon = double.tryParse((first['lon'] ?? '').toString());
      if (lat == null || lon == null) {
        _geocodeCache[key] = null;
        return null;
      }
      if (!_isValidLat(lat) || !_isValidLng(lon)) {
        _geocodeCache[key] = null;
        return null;
      }

      final result = LatLng(lat, lon);
      _geocodeCache[key] = result;
      return result;
    } catch (e) {
      debugPrint('❌ [Geocode] error: $e');
      _geocodeCache[key] = null;
      return null;
    }
  }

  Future<_BuildingInfo?> _detectBuildingAt(LatLng point) async {
    final cacheKey =
        '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';
    if (_buildingCache.containsKey(cacheKey)) {
      return _buildingCache[cacheKey];
    }

    try {
      final query = '''
[out:json][timeout:12];
(
  way(around:60,${point.latitude},${point.longitude})["building"];
);
out geom;
''';

      final response = await http
          .post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=${Uri.encodeComponent(query)}',
      )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _buildingCache[cacheKey] = null;
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = json['elements'] as List?;
      if (elements == null || elements.isEmpty) {
        _buildingCache[cacheKey] = null;
        return null;
      }

      _BuildingInfo? nearest;
      double nearestDist = double.infinity;

      for (final el in elements) {
        final geometry = el['geometry'] as List?;
        if (geometry == null || geometry.length < 3) continue;

        final points = <LatLng>[];
        double minLat = double.infinity, maxLat = -double.infinity;
        double minLng = double.infinity, maxLng = -double.infinity;

        for (final node in geometry) {
          if (node is! Map) continue;
          final lat = (node['lat'] as num?)?.toDouble();
          final lng = (node['lon'] as num?)?.toDouble();
          if (lat == null || lng == null) continue;

          points.add(LatLng(lat, lng));
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
          if (lng < minLng) minLng = lng;
          if (lng > maxLng) maxLng = lng;
        }

        if (points.isEmpty) continue;

        final centerLat = (minLat + maxLat) / 2;
        final centerLng = (minLng + maxLng) / 2;
        final center = LatLng(centerLat, centerLng);

        final dist = _haversineMeters(
            point.latitude, point.longitude, centerLat, centerLng);

        final midLat = (minLat + maxLat) / 2;
        final midLng = (minLng + maxLng) / 2;

        final widthM = _haversineMeters(midLat, minLng, midLat, maxLng);
        final heightM = _haversineMeters(minLat, midLng, maxLat, midLng);

        final halfDiag =
            math.sqrt(widthM * widthM + heightM * heightM) / 2;
        final radius = (halfDiag + 10).clamp(30.0, 2000.0);

        if (dist < nearestDist) {
          nearestDist = dist;
          nearest = _BuildingInfo(
            center: center,
            radiusMeters: radius,
            widthMeters: widthM,
            heightMeters: heightM,
            outline: points,
          );
        }
      }

      _buildingCache[cacheKey] = nearest;
      return nearest;
    } catch (e) {
      debugPrint('❌ [Overpass] error: $e');
      _buildingCache[cacheKey] = null;
      return null;
    }
  }

  Future<void> _onMapTapped(LatLng tapPos) async {
    if (!_safe) return;
    if (!GeoUtils.isValidLat(tapPos.latitude) ||
        !GeoUtils.isValidLng(tapPos.longitude)) {
      return;
    }

    final myGen = ++_pipelineGeneration;

    _safeSetState(() {
      _pickedPoint = tapPos;
      _latCtrl.text = tapPos.latitude.toStringAsFixed(6);
      _lngCtrl.text = tapPos.longitude.toStringAsFixed(6);
      _detectedBuilding = null;
      _detecting = true;
      _statusText = '🏢 Detecting building at tapped point...';
      _statusIsError = false;
    });

    final building = await _detectBuildingAt(tapPos);

    if (!_safe || myGen != _pipelineGeneration) return;

    if (building != null) {
      _latCtrl.text = building.center.latitude.toStringAsFixed(6);
      _lngCtrl.text = building.center.longitude.toStringAsFixed(6);
      _radiusCtrl.text = building.radiusMeters.toStringAsFixed(0);

      _safeSetState(() {
        _pickedPoint = building.center;
        _detectedBuilding = building;
        _autoFilled = true;
        _detecting = false;
        _statusText = '✅ ${building.widthMeters.toStringAsFixed(0)}m × '
            '${building.heightMeters.toStringAsFixed(0)}m — '
            'radius auto-set to ${building.radiusMeters.toStringAsFixed(0)}m';
        _statusIsError = false;
      });

      _safeMoveMap(building.center, 17.0);
    } else {
      _safeSetState(() {
        _detectedBuilding = null;
        _autoFilled = false;
        _detecting = false;
        _statusText = '⚠️ No building here — adjust radius manually.';
        _statusIsError = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_safe) return;
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final admin = FirebaseAuth.instance.currentUser;
    if (admin == null) {
      _showError('Session expired.');
      return;
    }

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final radius = double.tryParse(_radiusCtrl.text.trim());

    if (lat == null || !_isValidLat(lat)) {
      _showError('Invalid latitude (-90 to 90).');
      return;
    }
    if (lng == null || !_isValidLng(lng)) {
      _showError('Invalid longitude (-180 to 180).');
      return;
    }
    if (radius == null || !_isValidRadius(radius)) {
      _showError('Invalid radius (20-5000m).');
      return;
    }

    _safeSetState(() => _saving = true);
    try {
      final name = _sanitize(_nameCtrl.text.trim(), maxLen: 60);
      final address = _sanitize(_addressCtrl.text.trim(), maxLen: 150);

      if (name.isEmpty) {
        _showError('Location name required.');
        _safeSetState(() => _saving = false);
        return;
      }

      final data = <String, dynamic>{
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'active': widget.existing?['active'] ?? true,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': admin.uid,
      };

      if (_detectedBuilding != null) {
        data['buildingWidthM'] = _detectedBuilding!.widthMeters;
        data['buildingHeightM'] = _detectedBuilding!.heightMeters;
        data['autoSizedRadius'] = true;
      } else {
        data['autoSizedRadius'] = false;
      }

      if (widget.existing == null) {
        final ref = await FirebaseFirestore.instance
            .collection('locations')
            .add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': admin.uid,
        });

        unawaited(_auditFromDialog(
          action: 'add_location',
          targetId: ref.id,
          metadata: {
            'name': name,
            'address': address,
            'radius': radius,
            'autoSized': _detectedBuilding != null,
          },
          actorUid: admin.uid,
        ));
      } else {
        final id = widget.existing!['id'].toString();
        if (id.isEmpty || id.length > 1500 || id.contains('/')) {
          _showError('Invalid location reference.');
          _safeSetState(() => _saving = false);
          return;
        }

        await FirebaseFirestore.instance
            .collection('locations')
            .doc(id)
            .update(data);

        unawaited(_auditFromDialog(
          action: 'edit_location',
          targetId: id,
          metadata: {
            'name': name,
            'address': address,
            'radius': radius,
            'autoSized': _detectedBuilding != null,
          },
          actorUid: admin.uid,
        ));
      }

      if (!_safe) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!_safe) return;
      _safeSetState(() => _saving = false);
      _showError(kDebugMode ? 'Failed: $e' : 'Failed to save. Try again.');
    }
  }

  Future<void> _auditFromDialog({
    required String action,
    required String targetId,
    required Map<String, dynamic> metadata,
    required String actorUid,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_action',
        'action': action,
        'targetId': targetId,
        'targetType': 'location',
        'actorUid': actorUid,
        'metadata': metadata,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ dialog audit failed: $e');
    }
  }

  void _showError(String msg) {
    if (!_safe) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildMapPicker(AdminColors tc) {
    final center = _pickedPoint ?? const LatLng(14.598050, 120.989170);
    final radius =
        double.tryParse(_radiusCtrl.text.trim())?.clamp(20.0, 5000.0) ?? 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.touch_app_rounded, size: 12, color: tc.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'I-tap ang mapa para i-override — auto-detect pa rin ang building.',
                style: TextStyle(fontSize: 10.5, color: tc.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tc.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _dialogMapCtrl,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 17.0,
                    onTap: (tapPos, latLng) => _onMapTapped(latLng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.hris.biometrics',
                    ),
                    if (_detectedBuilding != null)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: _detectedBuilding!.outline,
                            color: Colors.blue.withValues(alpha: 0.20),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (_pickedPoint != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _pickedPoint!,
                            radius: radius,
                            useRadiusInMeter: true,
                            color: tc.orange.withValues(alpha: 0.18),
                            borderColor: tc.orange,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (_pickedPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _pickedPoint!,
                            width: 40,
                            height: 40,
                            child: Icon(Icons.location_on,
                                color: tc.orange, size: 38),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_searching || _detecting)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _searching
                                      ? 'Searching address...'
                                      : 'Detecting building...',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _buildStatusLine(tc),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                if (!_safe) return;
                if (_pickedPoint == null) return;
                _safeMoveMap(_pickedPoint!, 18.0);
              },
              icon: const Icon(Icons.my_location, size: 14),
              label:
              const Text('Recenter', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: tc.orange,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
            ),
            if (_detectedBuilding != null) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () {
                  if (!_safe) return;
                  _safeSetState(() {
                    _detectedBuilding = null;
                    _statusText = null;
                  });
                },
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Clear outline',
                    style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: tc.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStatusLine(AdminColors tc) {
    final text = _statusText;
    if (text == null) {
      return Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 12, color: tc.orange),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'AUTO-DETECT: I-type ang address → radius auto-set.',
              style: TextStyle(fontSize: 10.5, color: tc.muted),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          _statusIsError
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline,
          size: 12,
          color: _statusIsError ? tc.orange : tc.green,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _sanitize(text, maxLen: 200),
            style: TextStyle(
              fontSize: 10.5,
              color: _statusIsError ? tc.orange : tc.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: tc.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        color: tc.orange, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      isEdit ? 'Edit Location' : 'Add Location',
                      style: TextStyle(
                          color: tc.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'I-type ang address — auto-detect ang building at radius.',
                  style: TextStyle(color: tc.muted, fontSize: 12),
                ),
                const SizedBox(height: 20),

                _label('LOCATION NAME', tc),
                _field(_nameCtrl, 'e.g. Head Office / SM Mall',
                    maxLength: 60,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Required';
                      if (t.length > 60) return 'Max 60 chars';
                      return null;
                    }),

                const SizedBox(height: 14),

                _label('ADDRESS (AUTO-DETECT)', tc),
                _buildAddressField(tc),

                const SizedBox(height: 16),

                _label('MAP PREVIEW', tc),
                _buildMapPicker(tc),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _label('LATITUDE', tc),
                              if (_autoFilled) ...[
                                const SizedBox(width: 4),
                                _autoBadge(tc),
                              ],
                            ],
                          ),
                          _field(_latCtrl, '14.598050',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                              validator: (v) {
                                final n = double.tryParse((v ?? '').trim());
                                if (n == null) return 'Invalid';
                                if (n < -90 || n > 90) return '-90 to 90';
                                return null;
                              }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _label('LONGITUDE', tc),
                              if (_autoFilled) ...[
                                const SizedBox(width: 4),
                                _autoBadge(tc),
                              ],
                            ],
                          ),
                          _field(_lngCtrl, '120.989170',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                              validator: (v) {
                                final n = double.tryParse((v ?? '').trim());
                                if (n == null) return 'Invalid';
                                if (n < -180 || n > 180) return '-180 to 180';
                                return null;
                              }),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(child: _label('RADIUS (meters)', tc)),
                    if (_detectedBuilding != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 9, color: tc.green),
                            const SizedBox(width: 2),
                            Text('AUTO',
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: tc.green,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                      ),
                  ],
                ),
                _field(_radiusCtrl, '100',
                    keyboardType: TextInputType.number,
                    maxLength: 5,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null) return 'Enter a number';
                      if (n < 20 || n > 5000) return '20 - 5000 only';
                      return null;
                    }),

                if (_detectedBuilding != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                      Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.business_rounded,
                            size: 14, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Building: '
                                '${_detectedBuilding!.widthMeters.toStringAsFixed(0)}m × '
                                '${_detectedBuilding!.heightMeters.toStringAsFixed(0)}m '
                                '(longest ${math.max(_detectedBuilding!.widthMeters, _detectedBuilding!.heightMeters).toStringAsFixed(0)}m)',
                            style: const TextStyle(
                                color: Color(0xFF1565C0),
                                fontSize: 11,
                                height: 1.4,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: tc.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 14, color: tc.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'WFH at Company Drivers ay exempted sa geofence.',
                          style: TextStyle(
                              color: tc.text, fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                      child:
                      Text('Cancel', style: TextStyle(color: tc.muted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(isEdit ? 'Save' : 'Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tc.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _autoBadge(AdminColors tc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: tc.green.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text('AUTO',
        style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            color: tc.green,
            letterSpacing: 0.5)),
  );

  Widget _buildAddressField(AdminColors tc) {
    return TextFormField(
      controller: _addressCtrl,
      maxLength: 150,
      style: TextStyle(color: tc.text, fontSize: 14),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        hintText: 'e.g. SM Mall of Asia, Pasay City',
        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
        counterText: '',
        filled: true,
        fillColor: tc.surface,
        suffixIcon: (_searching || _detecting)
            ? Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: tc.orange),
          ),
        )
            : (_addressCtrl.text.trim().isNotEmpty
            ? IconButton(
          icon:
          Icon(Icons.close_rounded, size: 16, color: tc.muted),
          onPressed: () {
            if (!_safe) return;
            _addressCtrl.clear();
            _addressDebounce?.cancel();
            _pipelineGeneration++;
            _safeSetState(() {
              _statusText = null;
              _autoFilled = false;
              _detectedBuilding = null;
              _searching = false;
              _detecting = false;
            });
          },
        )
            : null),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.5),
        ),
      ),
    );
  }

  Widget _label(String text, AdminColors tc) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text,
        style: TextStyle(
            color: tc.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5)),
  );

  Widget _field(
      TextEditingController c,
      String hint, {
        TextInputType? keyboardType,
        String? Function(String?)? validator,
        int? maxLength,
        List<TextInputFormatter>? inputFormatters,
      }) {
    final tc = AdminTheme.getColors(context);
    return TextFormField(
      controller: c,
      keyboardType: keyboardType,
      validator: validator,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      style: TextStyle(color: tc.text, fontSize: 14),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
        counterText: '',
        filled: true,
        fillColor: tc.surface,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: tc.red, width: 1.2),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// RATE LIMITER
// ═══════════════════════════════════════════════════════════════════
class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 2);

  bool tryAcquire(String key) {
    final now = DateTime.now();
    final last = _lastCall[key];
    if (last != null && now.difference(last) < _minInterval) {
      return false;
    }
    _lastCall[key] = now;
    return true;
  }
}