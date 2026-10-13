// lib/screens/admin_pick_location_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'admin_theme.dart';

/// Result returned from the map picker
class PickedLocation {
  final double lat;
  final double lng;
  final String? address;

  PickedLocation({required this.lat, required this.lng, this.address});
}

class _NavItem {
  final int index;
  final String label;
  final IconData icon;
  const _NavItem(this.index, this.label, this.icon);
}

class AdminPickLocationPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  /// Callback para sa nav — kapag may tinap na ibang tab sa sidebar,
  /// i-pop ang picker tapos tatawagin ito para lumipat sa dashboard.
  final void Function(int index)? onTabNavigate;

  /// For top bar display
  final String? currentAdminName;

  const AdminPickLocationPage({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
    this.onTabNavigate,
    this.currentAdminName,
  });

  @override
  State<AdminPickLocationPage> createState() => _AdminPickLocationPageState();
}

class _AdminPickLocationPageState extends State<AdminPickLocationPage> {
  late final MapController _mapController;
  late LatLng _center;

  String _address = 'Loading address...';
  bool _loadingAddress = false;
  Timer? _debounce;
  bool _isDraggingMap = false;
  bool _gettingCurrentLocation = false;

  static const double _fallbackLat = 14.5995;
  static const double _fallbackLng = 120.9842;

  // Same as dashboard — currently active tab is 9 (Pick Location)
  static const int _currentNavIndex = 9;

  static const List<_NavItem> _navItems = [
    _NavItem(0, 'Overview', Icons.grid_view_rounded),
    _NavItem(1, 'Employees', Icons.people_alt_rounded),
    _NavItem(2, 'Add Employee', Icons.person_add_alt_1_rounded),
    _NavItem(3, 'Attendance', Icons.calendar_month_rounded),
    _NavItem(4, 'Activity', Icons.checklist_rounded),
    _NavItem(5, 'Tracking', Icons.location_on_rounded),
    _NavItem(6, 'Payroll', Icons.receipt_long_rounded),
    _NavItem(7, 'Assign Meeting', Icons.assignment_ind_rounded),
    _NavItem(8, 'Client Locations', Icons.add_location_alt_rounded),
    _NavItem(9, 'Pick Location', Icons.map_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = LatLng(
      widget.initialLat ?? _fallbackLat,
      widget.initialLng ?? _fallbackLng,
    );

    if (widget.initialAddress != null &&
        widget.initialAddress!.isNotEmpty) {
      _address = widget.initialAddress!;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reverseGeocode(_center);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // NAV — handle sidebar tap
  // ═══════════════════════════════════════════════════════════════
  void _handleNavTap(int index) {
    if (index == _currentNavIndex) return; // already on this tab

    debugPrint('🧭 [MapPicker Nav] → tab $index');
    Navigator.of(context).pop(); // close picker first
    widget.onTabNavigate?.call(index); // then navigate in dashboard
  }

  // ═══════════════════════════════════════════════════════════════
  // REVERSE GEOCODE — with timeout handling
  // ═══════════════════════════════════════════════════════════════
  Future<void> _reverseGeocode(LatLng point) async {
    if (!mounted) return;
    setState(() => _loadingAddress = true);

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'json',
        'zoom': '18',
        'addressdetails': '1',
      });

      debugPrint('🔍 [ReverseGeocode] $point');

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'RACOMA-HRIS/1.0 (contact@racoma.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final displayName = (data['display_name'] ?? '').toString();
        if (displayName.isNotEmpty) {
          setState(() {
            _address = displayName;
            _loadingAddress = false;
          });
          debugPrint('✅ [ReverseGeocode] $displayName');
          return;
        }
      }

      setState(() {
        _address = 'Address not available for this point';
        _loadingAddress = false;
      });
    } on TimeoutException {
      debugPrint('⏱️ [ReverseGeocode] TIMEOUT');
      if (!mounted) return;
      setState(() {
        _address = '⚠️ Address lookup timed out — drag to retry';
        _loadingAddress = false;
      });
    } catch (e) {
      debugPrint('❌ [ReverseGeocode] error: $e');
      if (!mounted) return;
      setState(() {
        _address = '⚠️ Address lookup failed — drag to retry';
        _loadingAddress = false;
      });
    }
  }

  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    setState(() {
      _center = camera.center;
      if (hasGesture) _isDraggingMap = true;
    });

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() => _isDraggingMap = false);
        _reverseGeocode(_center);
      }
    });
  }

  void _confirmSelection() {
    Navigator.of(context).pop(
      PickedLocation(
        lat: _center.latitude,
        lng: _center.longitude,
        address: _address,
      ),
    );
  }

  Future<void> _centerOnCurrentLocation(AdminColors tc) async {
    setState(() => _gettingCurrentLocation = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('⚠️ Location services are disabled.', tc);
        setState(() => _gettingCurrentLocation = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('⚠️ Location permission denied.', tc);
        setState(() => _gettingCurrentLocation = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      if (!mounted) return;

      final target = LatLng(pos.latitude, pos.longitude);
      _mapController.move(target, 18);
      setState(() {
        _center = target;
        _gettingCurrentLocation = false;
      });
      _reverseGeocode(target);

      final acc = pos.accuracy;
      _showSnack(
        acc <= 30
            ? '✅ Centered (±${acc.toStringAsFixed(0)}m)'
            : '⚠️ Centered — GPS: ±${acc.toStringAsFixed(0)}m',
        tc,
        isError: acc > 50,
      );
    } catch (e) {
      debugPrint('⚠️ [MapPicker] GPS error: $e');
      if (!mounted) return;
      setState(() => _gettingCurrentLocation = false);
      _showSnack('❌ Could not get GPS location.', tc);
    }
  }

  Future<void> _copyCoordinates(AdminColors tc) async {
    final text =
        '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: text));
    _showSnack('📋 Copied: $text', tc);
  }

  void _showSnack(String msg, AdminColors tc, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _searchAddress(String query, AdminColors tc) async {
    if (query.trim().length < 5) {
      _showSnack('⚠️ Type at least 5 characters', tc, isError: true);
      return;
    }

    setState(() => _loadingAddress = true);

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
        'countrycodes': 'ph',
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'RACOMA-HRIS/1.0 (contact@racoma.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) {
        setState(() => _loadingAddress = false);
        _showSnack('⚠️ Address not found: "$query"', tc, isError: true);
        return;
      }

      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lng == null) {
        setState(() => _loadingAddress = false);
        _showSnack('⚠️ Invalid result', tc, isError: true);
        return;
      }

      final target = LatLng(lat, lng);
      _mapController.move(target, 18);
      setState(() {
        _center = target;
        _loadingAddress = false;
      });
      _reverseGeocode(target);
    } catch (e) {
      debugPrint('⚠️ [MapPicker] search failed: $e');
      if (!mounted) return;
      setState(() => _loadingAddress = false);
      _showSnack('⚠️ Search failed', tc, isError: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD — with sidebar + top bar
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
        return Theme(
          data: ThemeProvider.instance.theme,
          child: Builder(
            builder: (innerContext) {
              final tc = AdminTheme.getColors(innerContext);
              return _buildShell(innerContext, tc);
            },
          ),
        );
      },
    );
  }

  Widget _buildShell(BuildContext context, AdminColors tc) {
    return LayoutBuilder(
      builder: (_, c) {
        final wide = c.maxWidth >= 768;

        return Scaffold(
          backgroundColor: tc.background,
          appBar: _buildTopBar(tc, wide),
          body: MediaQuery(
            data: MediaQuery.of(context).removePadding(removeTop: true),
            child: wide
                ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(tc),
                Expanded(child: _buildContent(tc)),
              ],
            )
                : _buildContent(tc),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TOP BAR — katulad ng dashboard pero may "Pick Location" title
  // ═══════════════════════════════════════════════════════════════
  PreferredSizeWidget _buildTopBar(AdminColors c, bool wide) {
    return AppBar(
      backgroundColor: c.topBarBg,
      foregroundColor: c.accent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 64,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: c.accent, size: 22),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back',
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.navBorder),
      ),
      title: Row(
        children: [
          Icon(Icons.map_rounded, color: c.orange, size: 20),
          const SizedBox(width: 10),
          Text(
            'Pick Location on Map',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.accent,
              fontFamily: 'sans-serif',
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: ThemeProvider.instance.isDark
              ? 'Light Mode'
              : 'Dark Mode',
          onPressed: () => ThemeProvider.instance.toggleDarkMode(),
          icon: Icon(
            ThemeProvider.instance.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            size: 20,
            color: c.accent,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: 0.15),
              border: Border.all(color: c.navBorder, width: 1),
            ),
            child: Icon(Icons.person_rounded, size: 16, color: c.accent),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SIDEBAR — same structure ng dashboard
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSidebar(AdminColors c) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.navBg,
        border: Border(right: BorderSide(color: c.navBorder, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.sidebarLogoBox,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.front_hand_rounded,
                      color: c.isDark
                          ? Colors.white
                          : const Color(0xFF53433C),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'R.A.C.O.M.A.',
                          style: TextStyle(
                            color: c.sidebarBrandText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'HRIS',
                          style: TextStyle(
                            color: c.navText,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _navItems.map((item) => _navTile(c, item)).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: c.clockCardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: c.isDark
                        ? c.navBorder.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Clock System Status',
                        style: TextStyle(
                          color: c.clockCardText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.clockDotColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.clockDotColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
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

  Widget _navTile(AdminColors c, _NavItem item) {
    final sel = item.index == _currentNavIndex;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: sel ? c.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _handleNavTap(item.index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: sel ? c.sidebarActiveText : c.navText,
                  size: 18,
                ),
                const SizedBox(width: 14),
                Text(
                  item.label,
                  style: TextStyle(
                    color: sel ? c.sidebarActiveText : c.navText,
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONTENT — Search bar + Map + Bottom sheet
  // ═══════════════════════════════════════════════════════════════
  Widget _buildContent(AdminColors tc) {
    return Container(
      color: tc.background,
      child: Column(
        children: [
          _buildSearchBar(tc),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 17,
                    minZoom: 3,
                    maxZoom: 19,
                    onPositionChanged: _onMapPositionChanged,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                      'com.example.hris_biometrics',
                      maxZoom: 19,
                    ),
                  ],
                ),

                // Center pin
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(
                      Icons.location_pin,
                      size: 48,
                      color: Color(0xFFF97316),
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),

                // Hint
                if (!_isDraggingMap)
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded,
                                size: 14, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Drag map to adjust pin',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Center on me button
                Positioned(
                  right: 12,
                  bottom: 20,
                  child: _mapControlBtn(
                    tc: tc,
                    icon: _gettingCurrentLocation
                        ? null
                        : Icons.my_location_rounded,
                    showSpinner: _gettingCurrentLocation,
                    isPrimary: true,
                    onTap: _gettingCurrentLocation
                        ? null
                        : () => _centerOnCurrentLocation(tc),
                    tooltip: 'Center on my location',
                  ),
                ),

                // Zoom controls
                Positioned(
                  right: 12,
                  top: 60,
                  child: Column(
                    children: [
                      _mapControlBtn(
                        tc: tc,
                        icon: Icons.add,
                        onTap: () {
                          final z = _mapController.camera.zoom + 1;
                          _mapController.move(
                              _center, z.clamp(3, 19).toDouble());
                        },
                        tooltip: 'Zoom in',
                      ),
                      const SizedBox(height: 8),
                      _mapControlBtn(
                        tc: tc,
                        icon: Icons.remove,
                        onTap: () {
                          final z = _mapController.camera.zoom - 1;
                          _mapController.move(
                              _center, z.clamp(3, 19).toDouble());
                        },
                        tooltip: 'Zoom out',
                      ),
                    ],
                  ),
                ),

                // Coordinate overlay
                Positioned(
                  top: 16,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _copyCoordinates(tc),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: tc.card.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: tc.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded,
                                size: 12, color: tc.orange),
                            const SizedBox(width: 6),
                            Text(
                              '${_center.latitude.toStringAsFixed(6)}, '
                                  '${_center.longitude.toStringAsFixed(6)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: tc.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildBottomSheet(tc),
        ],
      ),
    );
  }

  Widget _buildSearchBar(AdminColors tc) {
    final searchCtrl = TextEditingController();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tc.card,
        border: Border(bottom: BorderSide(color: tc.border)),
      ),
      child: TextField(
        controller: searchCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => _searchAddress(v, tc),
        style: TextStyle(color: tc.text, fontSize: 14),
        cursorColor: tc.orange,
        decoration: InputDecoration(
          hintText: 'Search address or place…',
          hintStyle: TextStyle(
            color: tc.muted.withValues(alpha: 0.7),
            fontSize: 13,
          ),
          prefixIcon:
          Icon(Icons.search_rounded, color: tc.muted, size: 20),
          suffixIcon: IconButton(
            icon: Icon(Icons.arrow_forward_rounded,
                color: tc.orange, size: 20),
            onPressed: () => _searchAddress(searchCtrl.text, tc),
            tooltip: 'Search',
          ),
          filled: true,
          fillColor: tc.surface,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: tc.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: tc.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: tc.orange, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _mapControlBtn({
    required AdminColors tc,
    required IconData? icon,
    required VoidCallback? onTap,
    bool showSpinner = false,
    bool isPrimary = false,
    String? tooltip,
  }) {
    final btn = Material(
      color: isPrimary ? tc.orange : tc.card,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: isPrimary ? 48 : 40,
          height: isPrimary ? 48 : 40,
          alignment: Alignment.center,
          child: showSpinner
              ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: isPrimary ? Colors.white : tc.orange,
            ),
          )
              : Icon(
            icon ?? Icons.my_location_rounded,
            color: isPrimary ? Colors.white : tc.text,
            size: isPrimary ? 22 : 20,
          ),
        ),
      ),
    );

    if (tooltip == null) return btn;
    return Tooltip(message: tooltip, child: btn);
  }

  Widget _buildBottomSheet(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: tc.card,
        border: Border(top: BorderSide(color: tc.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tc.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.location_on_rounded,
                    color: tc.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected location',
                      style: TextStyle(
                        fontSize: 11,
                        color: tc.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (_loadingAddress)
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: tc.orange),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Looking up address…',
                            style: TextStyle(
                                fontSize: 12, color: tc.muted),
                          ),
                        ],
                      )
                    else
                      Text(
                        _address,
                        style: TextStyle(
                          fontSize: 12,
                          color: tc.text,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _copyCoordinates(tc),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: tc.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tc.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _coordChip(tc,
                          'Lat', _center.latitude.toStringAsFixed(6)),
                    ),
                    Container(width: 1, height: 28, color: tc.border),
                    Expanded(
                      child: _coordChip(tc,
                          'Lng', _center.longitude.toStringAsFixed(6)),
                    ),
                    Icon(Icons.copy_rounded,
                        size: 14, color: tc.muted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmSelection,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text(
                'Confirm This Location',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: tc.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordChip(AdminColors tc, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: tc.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: tc.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}