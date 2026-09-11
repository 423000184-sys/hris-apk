// lib/screens/admin_tracking_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'admin_theme.dart';
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Geofence configuration successfully saved!'),
          backgroundColor: tc.green,
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

  void _moveMapToPosition(double lat, double lng) {
    _mapController.move(LatLng(lat, lng), 15.5);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD — Root layout safe mula sa unbounded constraints
  // ══════════════════════════════════════════════════════════════
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
              // 1. HEADER
              _buildHeader(),
              const SizedBox(height: 20),

              // 2. MAIN GRID — Map (2/3) + Locations (1/3)
              _buildMainGrid(),
              const SizedBox(height: 20),

              // 3. AUTOMATION SETTINGS
              _buildAutomationCard(),
              const SizedBox(height: 20),

              // 4. ACTION BUTTONS
              _buildActionButtons(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════
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
        Text(
          'Configure authorized attendance zones, map office perimeters, and manage site-specific radius validation rules.',
          style: TextStyle(fontSize: 13, color: tc.muted),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MAIN GRID — Bootstrap-style 2/3 + 1/3 ratio
  // ══════════════════════════════════════════════════════════════
  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final r = BsResponsive(w);
        final isDesktop = r.up(BsSize.lg); // lg = 992px+

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

        // Mobile / tablet: stack vertically
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

  // ══════════════════════════════════════════════════════════════
  // OPENSTREETMAP CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildOpenStreetMapCard() {
    final LatLng centerPoint = LatLng(_currentLat, _currentLng);

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
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: centerPoint,
                      radius: _currentRadius,
                      useRadiusInMeter: true,
                      color: tc.orange.withValues(alpha: 0.2),
                      borderColor: tc.orange,
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
                      child: Icon(
                        Icons.location_on,
                        color: tc.orange,
                        size: 38,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Top center badge
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: tc.card,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CURRENT ACTIVE GEOFENCE',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: tc.muted,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Radius: ${_currentRadius.toInt()} Meters',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tc.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Zoom controls
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
                            child: Icon(Icons.add, size: 16, color: tc.text),
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
                            child:
                            Icon(Icons.remove, size: 16, color: tc.text),
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

            // Bottom-left coords card
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: tc.card,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, color: tc.orange, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_currentLat.toStringAsFixed(4)}° N, ${_currentLng.toStringAsFixed(4)}° E',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Primary Infrastructure Zone',
                              style:
                              TextStyle(fontSize: 10, color: tc.muted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACTIVE LOCATIONS PANEL
  // ══════════════════════════════════════════════════════════════
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
        color: tc.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
              InkWell(
                onTap: () {},
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tc.orange,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add,
                      color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ✅ FIX: Column-based location cards (imbes na ListView.separated
          //         na may shrinkWrap sa loob ng SingleChildScrollView)
          if (activeLocs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No active locations',
                  style: TextStyle(fontSize: 12, color: tc.muted),
                ),
              ),
            )
          else
            Column(
              children: activeLocs.asMap().entries.map((entry) {
                final index = entry.key;
                final loc = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == activeLocs.length - 1 ? 0 : 12,
                  ),
                  child: _buildLocationCard(loc, index),
                );
              }).toList(),
            ),

          const SizedBox(height: 20),

          // Global Default Radius slider
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: tc.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GLOBAL DEFAULT RADIUS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tc.muted,
                      letterSpacing: 0.5),
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

  Widget _buildLocationCard(Map<String, dynamic> loc, int index) {
    final bool isSelected = _selectedLocationIndex == index;

    final String title =
    (loc['name'] ?? loc['employeeId'] ?? 'HQ Office').toString();
    final String sub = (loc['sub'] ?? 'Primary Hub Area').toString();
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
          color: tc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? tc.orange : tc.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + radio
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
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
            const SizedBox(height: 2),
            Text(sub,
                style: TextStyle(fontSize: 11, color: tc.muted),
                overflow: TextOverflow.ellipsis),
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
                      Text('${_currentRadius.toInt()}m',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tc.text)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STAFF',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: tc.muted)),
                      const SizedBox(height: 2),
                      Text(staff,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tc.text)),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 14, color: tc.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // AUTOMATION CARDS — Safe Wrap-based grid
  // ══════════════════════════════════════════════════════════════
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
              Flexible(
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
            final bool isWide = w >= 800;

            // 4 cards: 3 cols sa desktop (may 1 sa susunod na row),
            //          1 col sa mobile
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
                onChanged: (v) => setState(() => _autoClockOut = v),
              ),
              _buildToggleCard(
                title: 'Geofence Violation',
                subtitle: 'Alert admins on deviation',
                value: _geofenceViolation,
                onChanged: (v) => setState(() => _geofenceViolation = v),
              ),
              _buildToggleCard(
                title: 'Entry Reminders',
                subtitle: 'Push notice at perimeter',
                value: _entryReminders,
                onChanged: (v) => setState(() => _entryReminders = v),
              ),
              _buildToggleCard(
                title: 'Event and Holiday',
                subtitle: 'When Holiday or Event occurs',
                value: _eventAndHoliday,
                onChanged: (v) => setState(() => _eventAndHoliday = v),
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
        border: Border.all(color: tc.border),
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
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: tc.muted),
                  overflow: TextOverflow.ellipsis,
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

  // ══════════════════════════════════════════════════════════════
  // ACTION BUTTONS
  // ══════════════════════════════════════════════════════════════
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
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Discard Changes',
              style:
              TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(_isSaving ? 'Saving...' : 'Save Geofence Config'),
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: tc.orange.withValues(alpha: 0.3),
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
            saveBtn,
          ],
        );
      },
    );
  }
}