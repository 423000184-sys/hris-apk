import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  // OpenStreetMap Controller
  final MapController _mapController = MapController();

  // Active Coordinates at Geofence Limits
  late double _currentLat;
  late double _currentLng;
  late double _currentRadius;

  // Selected Card Index
  int _selectedLocationIndex = 0;
  bool _isSaving = false;

  // Automation Switch States
  bool _autoClockOut = true;
  bool _geofenceViolation = true;
  bool _entryReminders = true;
  bool _eventAndHoliday = true;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.officeLat;
    _currentLng = widget.officeLng;
    _currentRadius = widget.radiusLimit.clamp(50.0, 2000.0);
    _loadSettingsFromFirestore();
  }

  // Live Sync mula sa Cloud Firestore Settings Collection
  Future<void> _loadSettingsFromFirestore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('geofence_config')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _autoClockOut = data['autoClockOut'] ?? _autoClockOut;
          _geofenceViolation = data['geofenceViolation'] ?? _geofenceViolation;
          _entryReminders = data['entryReminders'] ?? _entryReminders;
          _eventAndHoliday = data['eventAndHoliday'] ?? _eventAndHoliday;
          if (data['globalRadius'] != null) {
            _currentRadius = (data['globalRadius'] as num)
                .toDouble()
                .clamp(50.0, 2000.0);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  // Database Save Function
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geofence configuration successfully saved!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Map Camera Movement Function
  void _moveMapToPosition(double lat, double lng) {
    _mapController.move(LatLng(lat, lng), 15.5);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER SECTION
          const Text(
            'Geofencing & Locations',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF11142D),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Configure authorized attendance zones, map office perimeters, and manage site-specific radius validation rules.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6C727F)),
          ),
          const SizedBox(height: 20),

          // 2. MAIN GRID (Interactive OpenStreetMap + Active Locations List)
          LayoutBuilder(builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth >= 900;
            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildOpenStreetMapCard()),
                  const SizedBox(width: 20),
                  Expanded(flex: 1, child: _buildActiveLocationsPanel()),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildOpenStreetMapCard(),
                  const SizedBox(height: 20),
                  _buildActiveLocationsPanel(),
                ],
              );
            }
          }),
          const SizedBox(height: 20),

          // 3. AUTOMATION SETTINGS CARD
          _buildAutomationCard(),
          const SizedBox(height: 20),

          // 4. ACTION BUTTONS
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _loadSettingsFromFirestore(),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1C1D21),
                  side: const BorderSide(color: Color(0xFFDCE4F0)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Discard Changes',
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveConfigToFirestore,
                icon: _isSaving
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_isSaving ? 'Saving...' : 'Save Geofence Config'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8A00),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: const Color(0xFFFF8A00).withOpacity(0.3),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- OPENSTREETMAP WIDGET ---
  Widget _buildOpenStreetMapCard() {
    final LatLng centerPoint = LatLng(_currentLat, _currentLng);

    return Container(
      height: 380,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
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
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: centerPoint,
                      radius: _currentRadius,
                      useRadiusInMeter: true,
                      color: const Color(0xFFFF8A00).withOpacity(0.2),
                      borderColor: const Color(0xFFFF8A00),
                      borderStrokeWidth: 2.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: centerPoint,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Color(0xFFFF8A00),
                        size: 38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'CURRENT ACTIVE GEOFENCE',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6C727F),
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Radius: ${_currentRadius.toInt()} Meters',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF11142D)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD0D7DE)),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            _mapController.move(_mapController.camera.center,
                                _mapController.camera.zoom + 0.5);
                          },
                          child: const SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(Icons.add,
                                size: 16, color: Color(0xFF444444)),
                          ),
                        ),
                        Container(
                            height: 1,
                            width: 32,
                            color: const Color(0xFFEAEAEA)),
                        InkWell(
                          onTap: () {
                            _mapController.move(_mapController.camera.center,
                                _mapController.camera.zoom - 0.5);
                          },
                          child: const SizedBox(
                            width: 32,
                            height: 32,
                            child: Icon(Icons.remove,
                                size: 16, color: Color(0xFF444444)),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD0D7DE)),
                      ),
                      child: const Icon(Icons.my_location,
                          size: 14, color: Color(0xFF444444)),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFFFF8A00), size: 16),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_currentLat.toStringAsFixed(4)}° N, ${_currentLng.toStringAsFixed(4)}° E',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF11142D)),
                        ),
                        const Text(
                          'Primary Infrastructure Zone',
                          style:
                          TextStyle(fontSize: 10, color: Color(0xFF8C8F9A)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ACTIVE LOCATIONS LIST PANEL ---
  Widget _buildActiveLocationsPanel() {
    final List<Map<String, dynamic>> activeLocs = widget.locations.isNotEmpty
        ? widget.locations
        : [
      {
        'name': 'Global HQ Office',
        'sub': 'Main Campus Center',
        'latitude': widget.officeLat,
        'longitude': widget.officeLng,
        'staff': '142',
      },
      {
        'name': 'West Logistics Hub',
        'sub': 'Secondary Field Zone',
        'latitude': widget.officeLat + 0.005,
        'longitude': widget.officeLng + 0.005,
        'staff': '38',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Locations',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF11142D)),
              ),
              InkWell(
                onTap: () {},
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF8A00),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeLocs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final loc = activeLocs[index];
              final bool isSelected = _selectedLocationIndex == index;

              final String title =
              (loc['name'] ?? loc['employeeId'] ?? 'HQ Office').toString();
              final String sub =
              (loc['sub'] ?? 'Primary Hub Area').toString();
              final double lat =
                  (loc['latitude'] as num?)?.toDouble() ?? widget.officeLat;
              final double lng =
                  (loc['longitude'] as num?)?.toDouble() ?? widget.officeLng;
              final String staff = (loc['staff'] ?? '120').toString();

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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF8A00)
                          : const Color(0xFFE1E6ED),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF11142D)),
                              ),
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? const Color(0xFFC27803)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFC27803)
                                        : const Color(0xFFCCCCCC),
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check,
                                    size: 10, color: Colors.white)
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(sub,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF6C727F))),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('RADIUS',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF8C8F9A))),
                                  const SizedBox(height: 2),
                                  Text('${_currentRadius.toInt()}m',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF11142D))),
                                ],
                              ),
                              const SizedBox(width: 24),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('STAFF',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF8C8F9A))),
                                  const SizedBox(height: 2),
                                  Text(staff,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF11142D))),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Positioned(
                        bottom: 0,
                        right: 0,
                        child: Icon(Icons.edit_outlined,
                            size: 14, color: Color(0xFF8C8F9A)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFDCE4F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GLOBAL DEFAULT RADIUS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF6C727F),
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: const Color(0xFFFF8A00),
                    inactiveTrackColor: const Color(0xFFD0D7DE),
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8, elevation: 2),
                    overlayColor: const Color(0xFFFF8A00).withOpacity(0.2),
                  ),
                  child: Slider(
                    value: _currentRadius.clamp(50.0, 2000.0),
                    min: 50.0,
                    max: 2000.0,
                    onChanged: (val) {
                      setState(() => _currentRadius = val);
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('50m',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8C8F9A))),
                    Text(
                      'Current: ${_currentRadius.toInt()}m',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF8A00)),
                    ),
                    const Text('2000m',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8C8F9A))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- AUTOMATION CARDS ---
  Widget _buildAutomationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE4F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_none_rounded,
                  color: Color(0xFFFF8A00), size: 20),
              SizedBox(width: 8),
              Text(
                'Automation & Notifications',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF11142D)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            bool isWide = constraints.maxWidth >= 800;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildToggleCard(
                  title: 'Auto Clock-Out',
                  subtitle: 'When staff leaves zone',
                  value: _autoClockOut,
                  onChanged: (v) => setState(() => _autoClockOut = v),
                  width: isWide
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth,
                ),
                _buildToggleCard(
                  title: 'Geofence Violation',
                  subtitle: 'Alert admins on deviation',
                  value: _geofenceViolation,
                  onChanged: (v) => setState(() => _geofenceViolation = v),
                  width: isWide
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth,
                ),
                _buildToggleCard(
                  title: 'Entry Reminders',
                  subtitle: 'Push notice at perimeter',
                  value: _entryReminders,
                  onChanged: (v) => setState(() => _entryReminders = v),
                  width: isWide
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth,
                ),
                _buildToggleCard(
                  title: 'Event and Holiday',
                  subtitle: 'When Holiday or Event occurs',
                  value: _eventAndHoliday,
                  onChanged: (v) => setState(() => _eventAndHoliday = v),
                  width: isWide
                      ? (constraints.maxWidth - 32) / 3
                      : constraints.maxWidth,
                ),
              ],
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
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E6ED)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF11142D)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF6C727F)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFFFF8A00),
            activeTrackColor: const Color(0xFFFF8A00).withOpacity(0.4),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFCCCCCC),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}