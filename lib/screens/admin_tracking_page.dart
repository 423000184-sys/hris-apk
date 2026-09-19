// lib/screens/admin_tracking_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'admin_theme.dart';
import '../services/geofence_service.dart';
import '../services/employee_notification_service.dart';
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

  final MapController _mapController = MapController();

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

  @override
  void initState() {
    super.initState();
    _currentLat = widget.officeLat;
    _currentLng = widget.officeLng;
    _currentRadius = widget.radiusLimit.clamp(50.0, 2000.0);
    _loadSettingsFromFirestore();
    _listenToLocations();
  }

  @override
  void dispose() {
    _radiusDebounce?.cancel();
    _locSub?.cancel();
    super.dispose();
  }

  void _listenToLocations() {
    _locSub?.cancel();
    _locSub = FirebaseFirestore.instance
        .collection('locations')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snap) {
        final list = snap.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList();
        if (!mounted) return;
        setState(() {
          _zones = list;
          _loadingZones = false;
        });
        debugPrint('📡 [Tracking] Locations stream: ${list.length} zone(s)');

        if (list.isNotEmpty && _selectedLocationIndex >= list.length) {
          _selectedLocationIndex = 0;
        }
      },
      onError: (e) {
        debugPrint('⚠️ [Tracking] locations stream error: $e');
        if (!mounted) return;
        setState(() => _loadingZones = false);
      },
    );
  }

  Future<void> _loadSettingsFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (!mounted) return;
        setState(() {
          _autoClockOut = (data['autoClockOut'] as bool?) ?? false;
          _geofenceViolation =
              (data['geofenceViolation'] as bool?) ?? false;
          _entryReminders = (data['entryReminders'] as bool?) ?? false;
          _eventAndHoliday = (data['eventAndHoliday'] as bool?) ?? false;

          if (data['globalRadius'] != null) {
            _currentRadius = (data['globalRadius'] as num)
                .toDouble()
                .clamp(50.0, 2000.0);
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Admin] Error loading settings: $e');
    }
  }

  Future<void> _autoSaveConfig() async {
    try {
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
      }, SetOptions(merge: true));

      GeofenceService.instance.invalidateCache();
    } catch (e) {
      debugPrint('❌ [Admin] Auto-save error: $e');
    }
  }

  Future<void> _saveConfigToFirestore() async {
    setState(() => _isSaving = true);
    try {
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
      }, SetOptions(merge: true));

      GeofenceService.instance.invalidateCache();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geofence saved! Radius: ${_currentRadius.toInt()}m'),
          backgroundColor: tc.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: $e'),
          backgroundColor: tc.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendHolidayNotification() async {
    try {
      await EmployeeNotificationService.instance.sendAnnouncement(
        title: '🎉 Event / Holiday Announcement',
        message:
        'An Event or Holiday has been scheduled. Please check your calendar and stay safe! — Admin',
        employeeId: 'ALL',
        priority: 'high',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Holiday notification sent to ALL employees!'),
          backgroundColor: tc.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('❌ [Admin] Holiday notification failed: $e');
    }
  }

  void _moveMapToPosition(double lat, double lng) {
    _mapController.move(LatLng(lat, lng), 15.5);
  }

  Future<void> _openAddLocationDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationDialog(
        defaultLat: _currentLat,
        defaultLng: _currentLng,
        defaultRadius: _currentRadius,
      ),
    );
    if (created == true) {
      GeofenceService.instance.invalidateCache();
      _snack('Location added successfully!');
    }
  }

  Future<void> _openEditLocationDialog(Map<String, dynamic> loc) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationDialog(existing: loc),
    );
    if (updated == true) {
      GeofenceService.instance.invalidateCache();
      _snack('Location updated.');
    }
  }

  Future<void> _confirmDeleteLocation(Map<String, dynamic> loc) async {
    final name = (loc['name'] ?? 'Location').toString();
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
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(loc['id'].toString())
          .delete();
      GeofenceService.instance.invalidateCache();
      _snack('Location deleted.');
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  Future<void> _toggleLocationActive(Map<String, dynamic> loc) async {
    final id = loc['id'].toString();
    final current = loc['active'] != false;
    try {
      await FirebaseFirestore.instance.collection('locations').doc(id).update({
        'active': !current,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      GeofenceService.instance.invalidateCache();
      _snack(!current ? 'Location enabled.' : 'Location disabled.');
    } catch (e) {
      _snack('Failed: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
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
                'Configure authorized attendance zones. Toggle changes are saved automatically.',
                style: TextStyle(fontSize: 13, color: tc.muted),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: tc.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: tc.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_rounded, size: 11, color: tc.green),
                  const SizedBox(width: 4),
                  Text('AUTO-SAVE ON',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: tc.green,
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

      final color =
      !active ? Colors.grey : (selected ? tc.orange : tc.blue);

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

    if (circles.isEmpty) {
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
                            _mapController.move(_mapController.camera.center,
                                _mapController.camera.zoom + 0.5);
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
                            _mapController.move(_mapController.camera.center,
                                _mapController.camera.zoom - 0.5);
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
                    onTap: () => _moveMapToPosition(_currentLat, _currentLng),
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
                  onTap: _openAddLocationDialog,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF8A00),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 18),
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
                        size: 11, color: tc.green),
                    const SizedBox(width: 4),
                    Text('auto',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: tc.green)),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: tc.orange,
                    inactiveTrackColor: tc.border,
                    thumbColor: tc.card,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8, elevation: 2),
                    overlayColor: tc.orange.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _currentRadius.clamp(50.0, 2000.0),
                    min: 50.0,
                    max: 2000.0,
                    onChanged: (val) {
                      setState(() => _currentRadius = val);
                      _radiusDebounce?.cancel();
                      _radiusDebounce = Timer(
                        const Duration(milliseconds: 500),
                        _autoSaveConfig,
                      );
                    },
                    onChangeEnd: (_) {
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
                          color: tc.orange),
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
            onPressed: _openAddLocationDialog,
            icon: const Icon(Icons.add_location_alt_rounded, size: 14),
            label: const Text('Add First Location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tc.orange,
              side: BorderSide(color: tc.orange),
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

    final String title = (loc['name'] ?? 'Unnamed Location').toString();
    final String sub = (loc['address'] ?? '').toString();
    final double lat = (loc['lat'] as num?)?.toDouble() ?? widget.officeLat;
    final double lng = (loc['lng'] as num?)?.toDouble() ?? widget.officeLng;
    final double radius =
        (loc['radius'] as num?)?.toDouble() ?? _currentRadius;

    return GestureDetector(
      onTap: () {
        setState(() {
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
                ? tc.orange
                : (!isActive ? tc.border.withValues(alpha: 0.5) : tc.border),
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
                    color: isSelected ? tc.orange : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? tc.orange : tc.muted,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                      size: 10, color: Colors.white)
                      : null,
                ),
              ],
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(fontSize: 11, color: tc.muted),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
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
                  color: isActive ? tc.muted : tc.green,
                  tooltip: isActive ? 'Disable' : 'Enable',
                  onTap: () => _toggleLocationActive(loc),
                ),
                const SizedBox(width: 4),
                _miniBtn(
                  icon: Icons.edit_outlined,
                  color: tc.orange,
                  tooltip: 'Edit',
                  onTap: () => _openEditLocationDialog(loc),
                ),
                const SizedBox(width: 4),
                _miniBtn(
                  icon: Icons.delete_outline_rounded,
                  color: tc.red,
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
            final w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;

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
                  setState(() => _autoClockOut = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Geofence Violation',
                subtitle: 'Alert admins on deviation',
                value: _geofenceViolation,
                onChanged: (v) async {
                  setState(() => _geofenceViolation = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Entry Reminders',
                subtitle: 'Push notice at perimeter',
                value: _entryReminders,
                onChanged: (v) async {
                  setState(() => _entryReminders = v);
                  await _autoSaveConfig();
                },
              ),
              _buildToggleCard(
                title: 'Event and Holiday',
                subtitle: 'When Holiday or Event occurs',
                value: _eventAndHoliday,
                onChanged: (v) async {
                  setState(() => _eventAndHoliday = v);
                  await _autoSaveConfig();
                  if (v) {
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
          color: value ? tc.orange.withValues(alpha: 0.5) : tc.border,
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
                        color: value ? tc.green : tc.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      value ? 'ON' : 'OFF',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: value ? tc.green : tc.muted,
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
            activeColor: tc.orange,
            activeTrackColor: tc.orange.withValues(alpha: 0.4),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: tc.muted,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
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
          onPressed: _openAddLocationDialog,
          icon: const Icon(Icons.add_location_alt_rounded, size: 16),
          label: const Text('Add Location'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.green,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: tc.green.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        final saveBtn = ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveConfigToFirestore,
          icon: _isSaving
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          )
              : const Icon(Icons.refresh_rounded, size: 16),
          label: Text(_isSaving ? 'Saving...' : 'Force Sync Now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: tc.orange.withValues(alpha: 0.3),
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
// ADD / EDIT LOCATION DIALOG
// ⭐ AUTO-FILL — Type address → Lat/Lng auto-populates
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
  bool _saving = false;

  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searching = false;
  String? _statusText;
  bool _statusIsError = false;
  bool _autoFilled = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _nameCtrl = TextEditingController(text: (e['name'] ?? '').toString());
    _addressCtrl =
        TextEditingController(text: (e['address'] ?? '').toString());
    _latCtrl = TextEditingController(
        text: (e['lat'] as num?)?.toStringAsFixed(6) ??
            (widget.defaultLat ?? 14.598050).toStringAsFixed(6));
    _lngCtrl = TextEditingController(
        text: (e['lng'] as num?)?.toStringAsFixed(6) ??
            (widget.defaultLng ?? 120.989170).toStringAsFixed(6));
    _radiusCtrl = TextEditingController(
        text: (((e['radius'] as num?)?.toDouble()) ??
            widget.defaultRadius ??
            100)
            .toStringAsFixed(0));

    _addressCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressCtrl.removeListener(_onAddressChanged);
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // ⭐ AUTO-LOOKUP — Type address → auto-fill lat/lng
  // ═══════════════════════════════════════════════════════════════
  void _onAddressChanged() {
    final q = _addressCtrl.text.trim();
    _searchDebounce?.cancel();

    // Reset kapag masyadong maiksi
    if (q.length < 5) {
      if (mounted && _statusText != null) {
        setState(() {
          _statusText = null;
          _autoFilled = false;
        });
      }
      return;
    }

    // Debounce — hintayin kang matapos mag-type
    _searchDebounce = Timer(const Duration(milliseconds: 800), () {
      _autoFillFromAddress(q);
    });

    if (mounted) {
      setState(() {
        _statusText = '⏳ Hintayin kang matapos mag-type...';
        _statusIsError = false;
      });
    }
  }

  Future<void> _autoFillFromAddress(String query) async {
    final myGen = ++_searchGeneration;

    if (mounted) {
      setState(() {
        _searching = true;
        _statusText = '🔍 Hinahanap: "$query"...';
        _statusIsError = false;
      });
    }

    debugPrint('🗺️ [Geocode] Auto-fill for: "$query"');

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'json',
          'addressdetails': '1',
          'limit': '1',
        },
      );

      // ⭐ Web-safe headers (no User-Agent on browser)
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (!kIsWeb) {
        headers['User-Agent'] = 'RACOMA-HRIS/1.0';
      }

      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));

      if (myGen != _searchGeneration) return;

      debugPrint('🗺️ [Geocode] Status: ${response.statusCode}');

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _searching = false;
            _statusText = '❌ Lookup failed (${response.statusCode})';
            _statusIsError = true;
          });
        }
        return;
      }

      final decoded = jsonDecode(response.body);
      final List<dynamic> list = decoded is List ? decoded : <dynamic>[];

      if (list.isEmpty) {
        if (mounted) {
          setState(() {
            _searching = false;
            _statusText = '❌ Walang nahanap. Try a more specific address.';
            _statusIsError = true;
          });
        }
        return;
      }

      final first = list.first;
      if (first is! Map) {
        if (mounted) {
          setState(() {
            _searching = false;
            _statusText = '❌ Invalid response.';
            _statusIsError = true;
          });
        }
        return;
      }

      final lat = double.tryParse((first['lat'] ?? '').toString());
      final lon = double.tryParse((first['lon'] ?? '').toString());
      final display = (first['display_name'] ?? '').toString();

      if (lat == null || lon == null) {
        if (mounted) {
          setState(() {
            _searching = false;
            _statusText = '❌ Walang coordinates sa result.';
            _statusIsError = true;
          });
        }
        return;
      }

      if (!mounted || myGen != _searchGeneration) return;

      // ⭐ AUTO-FILL LAT/LNG
      _latCtrl.text = lat.toStringAsFixed(6);
      _lngCtrl.text = lon.toStringAsFixed(6);

      // Auto-fill name kung blangko pa
      if (_nameCtrl.text.trim().isEmpty) {
        final addr = first['address'];
        if (addr is Map) {
          final shortName = (addr['amenity'] ??
              addr['building'] ??
              addr['office'] ??
              addr['shop'] ??
              addr['road'] ??
              '')
              .toString();
          if (shortName.isNotEmpty) _nameCtrl.text = shortName;
        }
      }

      setState(() {
        _searching = false;
        _autoFilled = true;
        _statusText = '✅ Auto-filled: '
            '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
        _statusIsError = false;
      });

      debugPrint('✅ [Geocode] Auto-filled lat=$lat, lng=$lon for "$query"');
    } catch (e) {
      debugPrint('❌ [Geocode] error: $e');
      if (!mounted || myGen != _searchGeneration) return;
      setState(() {
        _searching = false;
        _statusText = '❌ Network error. Check internet connection.';
        _statusIsError = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'lat': double.parse(_latCtrl.text.trim()),
        'lng': double.parse(_lngCtrl.text.trim()),
        'radius': double.parse(_radiusCtrl.text.trim()),
        'active': widget.existing?['active'] ?? true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.existing == null) {
        await FirebaseFirestore.instance.collection('locations').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance
            .collection('locations')
            .doc(widget.existing!['id'].toString())
            .update(data);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
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
                  'I-type ang address — auto-fill ang latitude at longitude.',
                  style: TextStyle(color: tc.muted, fontSize: 12),
                ),
                const SizedBox(height: 20),

                _label('LOCATION NAME', tc),
                _field(_nameCtrl, 'e.g. Head Office',
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Required'
                        : null),

                const SizedBox(height: 14),

                // ─── ADDRESS (auto-fill trigger) ───
                _label('ADDRESS', tc),
                _buildAddressField(tc),

                const SizedBox(height: 6),

                // Status line
                _buildStatusLine(tc),

                const SizedBox(height: 14),

                // ─── LATITUDE / LONGITUDE ───
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
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
                                ),
                              ],
                            ],
                          ),
                          _field(_latCtrl, '14.598050',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                              validator: _numValidator),
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
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
                                ),
                              ],
                            ],
                          ),
                          _field(_lngCtrl, '120.989170',
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true, signed: true),
                              validator: _numValidator),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                _label('RADIUS (meters)', tc),
                _field(_radiusCtrl, '100',
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null) return 'Enter a number';
                      if (n < 20 || n > 5000) return '20 - 5000 only';
                      return null;
                    }),

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
                          'Employees na WFH o Company Drivers ay exempted dito.',
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
                      _saving ? null : () => Navigator.pop(context),
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

  Widget _buildAddressField(AdminColors tc) {
    return TextFormField(
      controller: _addressCtrl,
      style: TextStyle(color: tc.text, fontSize: 14),
      cursorColor: tc.orange,
      decoration: InputDecoration(
        hintText: 'e.g. 629 J. Nepomuceno St, Quiapo, Manila',
        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
        filled: true,
        fillColor: tc.surface,
        suffixIcon: _searching
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
          icon: Icon(Icons.close_rounded,
              size: 16, color: tc.muted),
          onPressed: () {
            _addressCtrl.clear();
            setState(() {
              _statusText = null;
              _autoFilled = false;
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

  Widget _buildStatusLine(AdminColors tc) {
    final text = _statusText;
    if (text == null) {
      return Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, size: 12, color: tc.orange),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'AUTO-FILL: I-type ang address → kusang lalabas ang lat/lng',
              style: TextStyle(fontSize: 10.5, color: tc.muted),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
          size: 12,
          color: _statusIsError ? tc.red : tc.green,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              color: _statusIsError ? tc.red : tc.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String? _numValidator(String? v) {
    final n = double.tryParse((v ?? '').trim());
    if (n == null) return 'Invalid';
    return null;
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
      }) {
    final tc = AdminTheme.getColors(context);
    return TextFormField(
      controller: c,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: tc.text, fontSize: 14),
      cursorColor: tc.orange,
      inputFormatters: keyboardType == TextInputType.number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
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