// lib/screens/admin_add_client_location_page.dart
// v1.1: 🎭 Demo Mode Support (Mock Clients & Action Blocking)
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'admin_theme.dart';
import 'admin_pick_location_page.dart';
import '../services/demo_mode_service.dart'; // 🎭 Added

class AdminAddClientLocationPage extends StatefulWidget {
  final VoidCallback? onSaved;
  final VoidCallback? onBack;
  final bool embedded;
  final void Function(int index)? onTabNavigate;

  const AdminAddClientLocationPage({
    super.key,
    this.onSaved,
    this.onBack,
    this.embedded = false,
    this.onTabNavigate,
  });

  @override
  State<AdminAddClientLocationPage> createState() =>
      _AdminAddClientLocationPageState();
}

class _AdminAddClientLocationPageState
    extends State<AdminAddClientLocationPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  // 🎭 Demo Mode Getter
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  // 🎭 Demo Block Helper
  void _demoBlock() {
    _showSnack('Action disabled in Demo Mode.', isError: true);
  }

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  final _radiusCtrl = TextEditingController(text: '500');

  bool _isActive = true;
  bool _submitting = false;
  bool _loadingLocation = false;
  bool _testingConnection = false;

  bool _geocodingAddress = false;
  Timer? _geocodeDebounce;
  String? _lastGeocodedAddress;
  bool _suppressAddressGeocode = false;
  String? _geocodeStatus;

  List<Map<String, dynamic>> _clients = [];
  bool _loadingClients = true;

  // 🎭 MOCK CLIENTS
  List<Map<String, dynamic>> _getMockClients() {
    return [
      {
        'id': 'demo_client_1',
        'name': 'Acme Corporation HQ',
        'address': '123 Ayala Ave, Makati City',
        'lat': 14.5547,
        'lng': 121.0244,
        'radiusMeters': 100,
        'isActive': true,
      },
      {
        'id': 'demo_client_2',
        'name': 'Global Tech Solutions',
        'address': '456 BGC, Taguig City',
        'lat': 14.5500,
        'lng': 121.0500,
        'radiusMeters': 150,
        'isActive': true,
      },
      {
        'id': 'demo_client_3',
        'name': 'Sunrise Ventures',
        'address': '789 Ortigas Center, Pasig',
        'lat': 14.5800,
        'lng': 121.0600,
        'radiusMeters': 120,
        'isActive': false,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadClients();
    _addressCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _addressCtrl.removeListener(_onAddressChanged);
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // AUTO-GEOCODE (Address → Lat/Lng)
  // ═══════════════════════════════════════════════════════════════
  void _onAddressChanged() {
    if (_suppressAddressGeocode) return;

    _geocodeDebounce?.cancel();
    final text = _addressCtrl.text.trim();

    if (text.length < 5) {
      if (mounted) {
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = null;
        });
      }
      return;
    }

    if (_lastGeocodedAddress == text) return;

    if (mounted) {
      setState(() => _geocodeStatus = '⏳ Hintayin kang matapos mag-type...');
    }

    _geocodeDebounce = Timer(const Duration(milliseconds: 900), () {
      _geocodeAddress(text);
    });
  }

  Future<void> _geocodeAddress(String address) async {
    if (!mounted) return;

    setState(() {
      _geocodingAddress = true;
      _geocodeStatus = '🔍 Hinahanap ang address...';
    });
    debugPrint('🌍 [Geocode] Looking up: "$address"');

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': address,
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'RACOMA-HRIS/1.0 (contact@racoma.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode != 200) {
        debugPrint('❌ [Geocode] HTTP ${response.statusCode}');
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Lookup failed (${response.statusCode}).';
        });
        return;
      }

      final data = jsonDecode(response.body) as List<dynamic>;

      if (data.isEmpty) {
        debugPrint('⚠️ [Geocode] No results for: "$address"');
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Walang nahanap. Try more specific address.';
        });
        return;
      }

      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lng == null) {
        debugPrint('❌ [Geocode] Could not parse lat/lng');
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Invalid coordinates.';
        });
        return;
      }

      debugPrint('✅ [Geocode] Found: $lat, $lng');

      _suppressAddressGeocode = true;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lngCtrl.text = lng.toStringAsFixed(6);
      _suppressAddressGeocode = false;

      _lastGeocodedAddress = address;

      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus =
        '✅ Auto-filled: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      });
    } on TimeoutException {
      debugPrint('❌ [Geocode] Timeout');
      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus = '❌ Lookup timed out.';
      });
    } catch (e) {
      debugPrint('❌ [Geocode] Error: $e');
      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus = '❌ Network error. Check internet.';
      });
    }
  }

  Future<void> _pasteCoordsFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = (data?.text ?? '').trim();

      if (text.isEmpty) {
        _showSnack('⚠️ Clipboard is empty.', isError: true);
        return;
      }

      final regex = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
      final match = regex.firstMatch(text);

      if (match == null) {
        _showSnack(
          '⚠️ Could not parse coordinates.\nCopy as "lat, lng" format.',
          isError: true,
        );
        return;
      }

      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');

      if (lat == null || lng == null) {
        _showSnack('⚠️ Invalid coordinates.', isError: true);
        return;
      }

      if (!mounted) return;
      setState(() {
        _latCtrl.text = lat.toStringAsFixed(6);
        _lngCtrl.text = lng.toStringAsFixed(6);
        _geocodeStatus = '✅ Pasted from clipboard.';
      });
      _showSnack('✅ Coordinates pasted from clipboard!');
    } catch (e) {
      _showSnack('⚠️ Paste failed: $e', isError: true);
    }
  }

  Future<void> _pickOnMap() async {
    if (_isDemo) return _demoBlock();

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final currentAddr = _addressCtrl.text.trim();

    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => AdminPickLocationPage(
          initialLat: lat,
          initialLng: lng,
          initialAddress: currentAddr.isEmpty ? null : currentAddr,
          onTabNavigate: widget.onTabNavigate,
        ),
      ),
    );

    if (result == null || !mounted) return;

    _suppressAddressGeocode = true;
    _latCtrl.text = result.lat.toStringAsFixed(6);
    _lngCtrl.text = result.lng.toStringAsFixed(6);

    if (result.address != null && result.address!.isNotEmpty) {
      _addressCtrl.text = result.address!;
    }
    _suppressAddressGeocode = false;
    _lastGeocodedAddress = _addressCtrl.text.trim();

    setState(() {
      _geocodeStatus =
      '✅ Picked on map: ${result.lat.toStringAsFixed(5)}, ${result.lng.toStringAsFixed(5)}';
    });
    _showSnack('✅ Location picked from map!');
  }

  Future<void> _openInGoogleMaps({double? lat, double? lng}) async {
    final latVal = lat ?? double.tryParse(_latCtrl.text.trim());
    final lngVal = lng ?? double.tryParse(_lngCtrl.text.trim());

    if (latVal == null || lngVal == null) {
      _showSnack('⚠️ Enter coordinates first to view on map.',
          isError: true);
      return;
    }

    final url = Uri.parse('https://www.google.com/maps?q=$latVal,$lngVal');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showSnack('⚠️ Could not open Google Maps.', isError: true);
      }
    } catch (e) {
      debugPrint('⚠️ [Maps] open failed: $e');
      _showSnack('⚠️ Could not open Google Maps.', isError: true);
    }
  }

  Future<void> _testConnection() async {
    if (_isDemo) return _demoBlock();

    setState(() => _testingConnection = true);
    try {
      debugPrint('🧪 Testing Firestore connection...');
      final fs = FirebaseFirestore.instance;
      debugPrint('🧪 App name: ${fs.app.name}');
      debugPrint('🧪 Project ID: ${fs.app.options.projectId}');

      final testRef = fs.collection('_connection_test').doc('ping');
      await testRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'admin_add_client_location',
      }).timeout(const Duration(seconds: 10));

      debugPrint('✅ Firestore WRITE OK — deleting test doc...');
      await testRef.delete();

      if (!mounted) return;
      _showSnack('✅ Firestore connection OK! You can now save.');
    } catch (e) {
      debugPrint('❌ Firestore FAILED: $e');
      if (!mounted) return;
      _showSnack('❌ Firestore error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Future<void> _loadClients() async {
    if (!mounted) return;

    // 🎭 Demo Mode — use mock clients
    if (_isDemo) {
      setState(() {
        _clients = _getMockClients();
        _loadingClients = false;
      });
      return;
    }

    setState(() => _loadingClients = true);
    try {
      debugPrint('📥 [Clients] Loading from client_locations...');
      final snap = await FirebaseFirestore.instance
          .collection('client_locations')
          .get()
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 [Clients] Loaded ${snap.docs.length} docs');

      final list = snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList();

      list.sort((a, b) {
        final aName = (a['name'] ?? '').toString().toLowerCase();
        final bName = (b['name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _clients = list;
        _loadingClients = false;
      });
    } catch (e) {
      debugPrint('❌ [Clients] Load error: $e');
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );

      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);

      try {
        final placemarks =
        await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && _addressCtrl.text.trim().isEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            if ((p.street ?? '').isNotEmpty) p.street!,
            if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
            if ((p.locality ?? '').isNotEmpty) p.locality!,
            if ((p.administrativeArea ?? '').isNotEmpty)
              p.administrativeArea!,
          ];

          _suppressAddressGeocode = true;
          _addressCtrl.text = parts.join(', ');
          _lastGeocodedAddress = _addressCtrl.text.trim();
          _suppressAddressGeocode = false;
        }
      } catch (_) {}

      if (!mounted) return;
      final acc = pos.accuracy;
      if (acc <= 30) {
        _showSnack(
            '✅ Location captured! GPS accuracy: ±${acc.toStringAsFixed(0)}m');
      } else if (acc <= 100) {
        _showSnack(
            '⚠️ GPS weak: ±${acc.toStringAsFixed(0)}m. Verify on map!',
            isError: true);
      } else {
        _showSnack(
            '❌ GPS inaccurate: ±${acc.toStringAsFixed(0)}m. Try ulit sa labas.',
            isError: true);
      }
      setState(() {
        _geocodeStatus =
        '✅ GPS captured: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _saveClient() async {
    if (_isDemo) return _demoBlock();

    debugPrint('═══════════════════════════════════════════');
    debugPrint('💾 [Save] Starting save...');

    _geocodeDebounce?.cancel();

    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [Save] VALIDATION FAILED');
      _showSnack('⚠️ Please fill all required fields (marked *)',
          isError: true);
      return;
    }

    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final latStr = _latCtrl.text.trim();
    final lngStr = _lngCtrl.text.trim();
    final radiusStr = _radiusCtrl.text.trim();

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    final radius = double.tryParse(radiusStr) ?? 500;

    if (lat == null || lng == null) {
      debugPrint('❌ [Save] Invalid coordinates');
      _showSnack(
          '❌ Invalid coordinates. I-type ang address o i-tap ang GPS.',
          isError: true);
      return;
    }

    if (name.isEmpty) {
      debugPrint('❌ [Save] Empty name');
      _showSnack('❌ Client name is required', isError: true);
      return;
    }

    if (address.isEmpty) {
      _showSnack('❌ Address is required', isError: true);
      return;
    }

    final confirmed = await _showConfirmDialog(
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      radius: radius,
    );

    if (confirmed != true) {
      debugPrint('ℹ️ [Save] Cancelled by user');
      return;
    }

    setState(() => _submitting = true);

    try {
      final fs = FirebaseFirestore.instance;
      final docRef = fs.collection('client_locations').doc();
      debugPrint('💾 [Save] Doc ID: ${docRef.id}');

      final payload = <String, dynamic>{
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radius,
        'isActive': _isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(payload).timeout(const Duration(seconds: 15));

      debugPrint('✅ [Save] Write SUCCESS — doc ${docRef.id}');

      if (!mounted) return;
      _showSnack('✅ Client "$name" added successfully!');
      _resetForm();
      await _loadClients();
      if (widget.onSaved != null) widget.onSaved!();
    } catch (e, stack) {
      debugPrint('❌ [Save] FAILED: $e');
      debugPrint('❌ [Save] Stack: $stack');
      if (!mounted) return;
      _showSnack('❌ Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
      debugPrint('═══════════════════════════════════════════');
    }
  }

  Future<bool?> _showConfirmDialog({
    required String name,
    required String address,
    required double lat,
    required double lng,
    required double radius,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: tc.orange, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Client Location?',
                style: TextStyle(
                  color: tc.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow('Name', name),
            const SizedBox(height: 6),
            _confirmRow('Address', address),
            const SizedBox(height: 6),
            _confirmRow('Coordinates', '$lat, $lng'),
            const SizedBox(height: 6),
            _confirmRow('Radius', '${radius.toStringAsFixed(0)}m'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tc.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: tc.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 14, color: tc.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Verify on Google Maps before saving',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tc.orangeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _openInGoogleMaps(lat: lat, lng: lng),
                      icon: Icon(Icons.map_rounded,
                          size: 16, color: tc.orange),
                      label: Text(
                        'View on Google Maps',
                        style: TextStyle(
                          color: tc.orange,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: tc.orange, width: 1.5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Confirm & Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tc.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
        ),
      ],
    );
  }

  void _resetForm() {
    _geocodeDebounce?.cancel();
    setState(() {
      _suppressAddressGeocode = true;
      _nameCtrl.clear();
      _addressCtrl.clear();
      _latCtrl.clear();
      _lngCtrl.clear();
      _radiusCtrl.text = '500';
      _isActive = true;
      _geocodingAddress = false;
      _geocodeStatus = null;
      _lastGeocodedAddress = null;
      _suppressAddressGeocode = false;
    });
  }

  Future<void> _editClient(Map<String, dynamic> client) async {
    if (_isDemo) return _demoBlock();

    debugPrint('✏️ [Edit] Opening edit dialog for client ${client['id']}');

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditClientDialog(client: client),
    );

    if (updated != true) return;

    if (!mounted) return;
    _showSnack('✅ Client updated successfully!');
    _loadClients();
    if (widget.onSaved != null) widget.onSaved!();
  }

  Future<void> _deleteClient(Map<String, dynamic> client) async {
    if (_isDemo) return _demoBlock();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        title: Text('Delete Client?', style: TextStyle(color: tc.text)),
        content: Text('Delete "${client['name']}"?',
            style: TextStyle(color: tc.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('client_locations')
          .doc(client['id'])
          .delete();
      if (!mounted) return;
      _showSnack('🗑️ Deleted "${client['name']}"');
      _loadClients();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> client) async {
    if (_isDemo) return _demoBlock();

    try {
      final current = client['isActive'] == true;
      await FirebaseFirestore.instance
          .collection('client_locations')
          .doc(client['id'])
          .update({
        'isActive': !current,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _loadClients();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🎭 DEMO BANNER
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 20),
              ],
              _buildHeader(),
              const SizedBox(height: 20),
              _buildForm(),
              const SizedBox(height: 32),
              _buildClientsList(),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return Container(color: tc.background, child: body);
    }

    return Scaffold(
      backgroundColor: tc.background,
      body: SafeArea(child: body),
    );
  }

  // 🎭 DEMO BANNER
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
                  'Showing sample clients. Adding, editing, and deleting are disabled.',
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
        TextButton.icon(
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.maybePop(context);
            }
          },
          icon: const Icon(Icons.arrow_back_rounded,
              size: 16, color: Color(0xFFFF8A00)),
          label: const Text(
            'Back to Activity & Leave',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFF8A00),
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Client Locations',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: tc.text,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Register client offices for meeting assignments.',
          style: TextStyle(fontSize: 13, color: tc.muted),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──
            LayoutBuilder(builder: (context, c) {
              final isNarrow = c.maxWidth < 400;

              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      color: tc.orange, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Add New Client Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tc.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: _isDemo
                        ? 'Test disabled in Demo'
                        : 'Test Firestore connection',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (_testingConnection || _isDemo)
                            ? (_isDemo ? _demoBlock : null)
                            : _testConnection,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: _testingConnection
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                              : Icon(
                            Icons.wifi_tethering_rounded,
                            color: _isDemo ? tc.muted : tc.orange,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Refresh clients',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _loadClients,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.refresh_rounded,
                            color: tc.muted,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  actions,
                ],
              );
            }),
            const SizedBox(height: 20),

            // ── 1. CLIENT NAME ──
            TextFormField(
              controller: _nameCtrl,
              decoration: _inputDeco('Client Name *',
                  hint: 'e.g. ABC Corporation HQ'),
              style: TextStyle(color: tc.text),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: 16),

            // ── 2. ADDRESS (PRIMARY) ──
            TextFormField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: _inputDeco('Address *',
                  hint: 'e.g. 629 J. Nepomuceno St, Quiapo, Manila')
                  .copyWith(
                suffixIcon: _geocodingAddress
                    ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tc.orange,
                    ),
                  ),
                )
                    : null,
              ),
              style: TextStyle(color: tc.text),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Address is required'
                  : null,
            ),
            const SizedBox(height: 6),

            // ── 3. AUTO-GEOCODE STATUS ──
            if (_geocodeStatus != null)
              Row(
                children: [
                  Icon(
                    _geocodeStatus!.startsWith('✅')
                        ? Icons.check_circle_outline
                        : (_geocodeStatus!.startsWith('❌')
                        ? Icons.error_outline
                        : Icons.hourglass_empty),
                    size: 12,
                    color: _geocodeStatus!.startsWith('✅')
                        ? tc.green
                        : (_geocodeStatus!.startsWith('❌')
                        ? tc.red
                        : tc.orange),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _geocodeStatus!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _geocodeStatus!.startsWith('✅')
                            ? tc.green
                            : (_geocodeStatus!.startsWith('❌')
                            ? tc.red
                            : tc.orange),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded,
                      size: 12, color: tc.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'AUTO-FILL: I-type ang address → kusang lalabas ang lat/lng',
                      style: TextStyle(fontSize: 10.5, color: tc.muted),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),

            // ── 4. COORDINATES (auto-filled, editable) ──
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 600;
              final latField = TextFormField(
                controller: _latCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration:
                _inputDeco('Latitude *', hint: 'e.g. 14.5547'),
                style: TextStyle(color: tc.text),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) {
                    return 'Invalid number';
                  }
                  return null;
                },
              );
              final lngField = TextFormField(
                controller: _lngCtrl,
                keyboardType:
                const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: _inputDeco('Longitude *',
                    hint: 'e.g. 121.0244'),
                style: TextStyle(color: tc.text),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) {
                    return 'Invalid number';
                  }
                  return null;
                },
              );
              final radiusField = TextFormField(
                controller: _radiusCtrl,
                keyboardType: TextInputType.number,
                decoration:
                _inputDeco('Radius (meters)', hint: '500'),
                style: TextStyle(color: tc.text),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final d = double.tryParse(v.trim());
                  if (d == null || d <= 0) return 'Invalid';
                  return null;
                },
              );

              if (!wide) {
                return Column(
                  children: [
                    latField,
                    const SizedBox(height: 12),
                    lngField,
                    const SizedBox(height: 12),
                    radiusField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: latField),
                  const SizedBox(width: 12),
                  Expanded(child: lngField),
                  const SizedBox(width: 12),
                  Expanded(child: radiusField),
                ],
              );
            }),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openInGoogleMaps(),
                icon: Icon(Icons.map_rounded,
                    size: 16, color: tc.orange),
                label: Text(
                  'I-verify sa Google Maps',
                  style: TextStyle(
                    fontSize: 12,
                    color: tc.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── 5. SECONDARY OPTIONS ──
            Text(
              'IBA PANG OPTIONS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: tc.muted,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 700;

              final gpsBtn = OutlinedButton.icon(
                onPressed:
                _loadingLocation ? null : _useCurrentLocation,
                icon: _loadingLocation
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2),
                )
                    : Icon(Icons.my_location_rounded,
                    size: 16, color: tc.orange),
                label: Text(
                  _loadingLocation ? 'GPS...' : 'Use My GPS',
                  style: TextStyle(
                    color: tc.orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tc.orange, width: 1.5),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );

              final mapBtn = OutlinedButton.icon(
                onPressed: _isDemo ? _demoBlock : _pickOnMap,
                icon: Icon(Icons.map_rounded,
                    size: 16, color: _isDemo ? tc.muted : tc.orange),
                label: Text(
                  'Pick on Map',
                  style: TextStyle(
                    color: _isDemo ? tc.muted : tc.orange,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _isDemo ? tc.border : tc.orange, width: 1.5),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );

              final pasteBtn = OutlinedButton.icon(
                onPressed: _pasteCoordsFromClipboard,
                icon: Icon(Icons.content_paste_rounded,
                    size: 16, color: tc.text),
                label: Text(
                  'Paste Coords',
                  style: TextStyle(
                    color: tc.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tc.border),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );

              if (!wide) {
                return Column(
                  children: [
                    SizedBox(width: double.infinity, child: gpsBtn),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: mapBtn),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: pasteBtn),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: gpsBtn),
                  const SizedBox(width: 8),
                  Expanded(child: mapBtn),
                  const SizedBox(width: 8),
                  Expanded(child: pasteBtn),
                ],
              );
            }),
            const SizedBox(height: 20),

            // ── 6. ACTIVE TOGGLE ──
            Row(
              children: [
                Switch(
                  value: _isActive,
                  onChanged: _isDemo
                      ? null
                      : (v) => setState(() => _isActive = v),
                  activeColor: _isDemo ? tc.muted : tc.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  _isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _isActive ? tc.green : tc.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 7. ACTIONS ──
            Row(
              children: [
                TextButton.icon(
                  onPressed: _submitting ? null : _resetForm,
                  icon: Icon(Icons.refresh_rounded,
                      size: 16, color: tc.muted),
                  label: Text('Reset',
                      style: TextStyle(color: tc.muted)),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: (_submitting || _isDemo)
                      ? (_isDemo ? _demoBlock : null)
                      : _saveClient,
                  icon: (_submitting)
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Icon(
                    _isDemo
                        ? Icons.lock_outline_rounded
                        : Icons.save_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _submitting
                        ? 'Saving...'
                        : (_isDemo
                        ? 'Save Disabled (Demo)'
                        : 'Save Client'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDemo ? tc.border : tc.orange,
                    foregroundColor: _isDemo ? tc.muted : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: tc.muted),
      hintStyle: TextStyle(color: tc.muted.withValues(alpha: 0.6)),
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
        borderSide: BorderSide(color: tc.orange, width: 2),
      ),
    );
  }

  Widget _buildClientsList() {
    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.list_alt_rounded, color: tc.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registered Clients',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: tc.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_clients.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: tc.orangeText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tc.border),
          if (_loadingClients)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(color: tc.orange),
              ),
            )
          else if (_clients.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.location_off_rounded,
                        size: 40, color: tc.muted),
                    const SizedBox(height: 8),
                    Text('No clients registered yet.',
                        style:
                        TextStyle(color: tc.muted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            ..._clients.map(_buildClientTile),
        ],
      ),
    );
  }

  Widget _buildClientTile(Map<String, dynamic> c) {
    final isActive = c['isActive'] == true;
    final name = (c['name'] ?? 'Unknown').toString();
    final address = (c['address'] ?? '').toString();
    final lat = (c['lat'] as num?)?.toDouble();
    final lng = (c['lng'] as num?)?.toDouble();
    final radius = (c['radiusMeters'] as num?)?.toDouble();

    final statusColor = isActive ? tc.green : tc.muted;

    final statusPill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: statusColor,
        ),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () {
            if (lat != null && lng != null) {
              _openInGoogleMaps(lat: lat, lng: lng);
            } else {
              _showSnack('⚠️ No coordinates to view.', isError: true);
            }
          },
          icon: Icon(Icons.map_rounded,
              color: _isDemo ? tc.muted : tc.orange, size: 18),
          tooltip: 'View on Google Maps',
          padding: EdgeInsets.zero,
          constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: _isDemo ? _demoBlock : () => _editClient(c),
          icon: Icon(Icons.edit_rounded,
              color: _isDemo ? tc.muted : tc.orange, size: 18),
          tooltip: _isDemo ? 'Edit disabled in Demo' : 'Edit client',
          padding: EdgeInsets.zero,
          constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: _isDemo ? _demoBlock : () => _toggleActive(c),
          icon: Icon(
            isActive
                ? Icons.toggle_on_rounded
                : Icons.toggle_off_rounded,
            color: _isDemo ? tc.muted : (isActive ? tc.green : tc.muted),
            size: 22,
          ),
          tooltip: isActive ? 'Disable' : 'Enable',
          padding: EdgeInsets.zero,
          constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          onPressed: _isDemo ? _demoBlock : () => _deleteClient(c),
          icon: Icon(Icons.delete_outline_rounded,
              color: _isDemo ? tc.muted : tc.red, size: 18),
          tooltip: _isDemo ? 'Delete disabled in Demo' : 'Delete',
          padding: EdgeInsets.zero,
          constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 600;

      if (isNarrow) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: tc.border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 100,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: tc.text),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusPill,
                      ],
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        address,
                        style:
                        TextStyle(fontSize: 11, color: tc.muted),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (lat != null && lng != null) ...[
                          Icon(Icons.location_on_outlined,
                              size: 12, color: tc.muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (radius != null) ...[
                          const SizedBox(width: 8),
                          Text('•',
                              style: TextStyle(
                                  fontSize: 11, color: tc.muted)),
                          const SizedBox(width: 8),
                          Text(
                            '${radius.toStringAsFixed(0)}m',
                            style: TextStyle(
                                fontSize: 11, color: tc.muted),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: actions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tc.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tc.text),
                      overflow: TextOverflow.ellipsis),
                  if (address.isNotEmpty)
                    Text(address,
                        style:
                        TextStyle(fontSize: 11, color: tc.muted),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lat != null && lng != null)
                    Text(
                        '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tc.text)),
                  if (radius != null)
                    Text('${radius.toStringAsFixed(0)}m radius',
                        style:
                        TextStyle(fontSize: 11, color: tc.muted)),
                ],
              ),
            ),
            statusPill,
            const SizedBox(width: 8),
            ...actions.children,
          ],
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════════
// EDIT CLIENT DIALOG
// ═══════════════════════════════════════════════════════════════════
class _EditClientDialog extends StatefulWidget {
  final Map<String, dynamic> client;

  const _EditClientDialog({required this.client});

  @override
  State<_EditClientDialog> createState() => _EditClientDialogState();
}

class _EditClientDialogState extends State<_EditClientDialog> {
  AdminColors get tc => AdminTheme.getColors(context);

  // 🎭 Demo Mode Getter
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  void _demoBlock() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Action disabled in Demo Mode.'),
        backgroundColor: tc.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _radiusCtrl;

  bool _isActive = true;
  bool _saving = false;
  bool _loadingLocation = false;

  bool _geocodingAddress = false;
  Timer? _geocodeDebounce;
  String? _lastGeocodedAddress;
  bool _suppressAddressGeocode = false;
  String? _geocodeStatus;

  @override
  void initState() {
    super.initState();

    final c = widget.client;

    _nameCtrl = TextEditingController(
      text: (c['name'] ?? '').toString(),
    );
    _addressCtrl = TextEditingController(
      text: (c['address'] ?? '').toString(),
    );
    _latCtrl = TextEditingController(
      text: (c['lat'] as num?)?.toStringAsFixed(6) ?? '',
    );
    _lngCtrl = TextEditingController(
      text: (c['lng'] as num?)?.toStringAsFixed(6) ?? '',
    );
    _radiusCtrl = TextEditingController(
      text: (c['radiusMeters'] as num?)?.toStringAsFixed(0) ?? '500',
    );

    _isActive = c['isActive'] == true;
    _lastGeocodedAddress = _addressCtrl.text.trim();

    _addressCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _addressCtrl.removeListener(_onAddressChanged);
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _onAddressChanged() {
    if (_suppressAddressGeocode) return;

    _geocodeDebounce?.cancel();
    final text = _addressCtrl.text.trim();

    if (text.length < 5) {
      if (mounted) {
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = null;
        });
      }
      return;
    }

    if (_lastGeocodedAddress == text) return;

    if (mounted) {
      setState(() => _geocodeStatus = '⏳ Hintayin kang matapos mag-type...');
    }

    _geocodeDebounce = Timer(const Duration(milliseconds: 900), () {
      _geocodeAddress(text);
    });
  }

  Future<void> _geocodeAddress(String address) async {
    if (!mounted) return;

    setState(() {
      _geocodingAddress = true;
      _geocodeStatus = '🔍 Hinahanap ang address...';
    });
    debugPrint('🌍 [Edit][Geocode] Looking up: "$address"');

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': address,
        'format': 'json',
        'limit': '1',
        'addressdetails': '1',
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'RACOMA-HRIS/1.0 (contact@racoma.com)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Lookup failed.';
        });
        return;
      }

      final data = jsonDecode(response.body) as List<dynamic>;

      if (data.isEmpty) {
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Walang nahanap.';
        });
        return;
      }

      final first = data.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');

      if (lat == null || lng == null) {
        setState(() {
          _geocodingAddress = false;
          _geocodeStatus = '❌ Invalid coordinates.';
        });
        return;
      }

      _suppressAddressGeocode = true;
      _latCtrl.text = lat.toStringAsFixed(6);
      _lngCtrl.text = lng.toStringAsFixed(6);
      _suppressAddressGeocode = false;

      _lastGeocodedAddress = address;

      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus =
        '✅ Auto-filled: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus = '❌ Lookup timed out.';
      });
    } catch (e) {
      debugPrint('❌ [Edit][Geocode] Error: $e');
      if (!mounted) return;
      setState(() {
        _geocodingAddress = false;
        _geocodeStatus = '❌ Network error.';
      });
    }
  }

  Future<void> _pasteCoordsFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = (data?.text ?? '').trim();

      if (text.isEmpty) {
        _showSnack('⚠️ Clipboard is empty.', isError: true);
        return;
      }

      final regex = RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)');
      final match = regex.firstMatch(text);

      if (match == null) {
        _showSnack(
          '⚠️ Could not parse coordinates.\nCopy as "lat, lng" format.',
          isError: true,
        );
        return;
      }

      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');

      if (lat == null || lng == null) {
        _showSnack('⚠️ Invalid coordinates.', isError: true);
        return;
      }

      if (!mounted) return;
      setState(() {
        _latCtrl.text = lat.toStringAsFixed(6);
        _lngCtrl.text = lng.toStringAsFixed(6);
        _geocodeStatus = '✅ Pasted from clipboard.';
      });
      _showSnack('✅ Coordinates pasted from clipboard!');
    } catch (e) {
      _showSnack('⚠️ Paste failed: $e', isError: true);
    }
  }

  Future<void> _pickOnMap() async {
    if (_isDemo) return _demoBlock();

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final currentAddr = _addressCtrl.text.trim();

    final result = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => AdminPickLocationPage(
          initialLat: lat,
          initialLng: lng,
          initialAddress: currentAddr.isEmpty ? null : currentAddr,
        ),
      ),
    );

    if (result == null || !mounted) return;

    _suppressAddressGeocode = true;
    _latCtrl.text = result.lat.toStringAsFixed(6);
    _lngCtrl.text = result.lng.toStringAsFixed(6);

    if (result.address != null && result.address!.isNotEmpty) {
      _addressCtrl.text = result.address!;
    }
    _suppressAddressGeocode = false;
    _lastGeocodedAddress = _addressCtrl.text.trim();

    setState(() {
      _geocodeStatus =
      '✅ Picked on map: ${result.lat.toStringAsFixed(5)}, ${result.lng.toStringAsFixed(5)}';
    });
    _showSnack('✅ Location picked from map!');
  }

  Future<void> _openInGoogleMaps() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());

    if (lat == null || lng == null) {
      _showSnack('⚠️ Enter coordinates first.', isError: true);
      return;
    }

    final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('⚠️ [Maps] open failed: $e');
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Location services are disabled.';
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission denied.';
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );

      if (!mounted) return;
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      });

      final acc = pos.accuracy;
      if (acc <= 30) {
        _showSnack(
            '✅ Location captured! GPS accuracy: ±${acc.toStringAsFixed(0)}m');
      } else {
        _showSnack(
            '⚠️ GPS weak: ±${acc.toStringAsFixed(0)}m — verify with map!',
            isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('❌ $e', isError: true);
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _save() async {
    if (_isDemo) return _demoBlock();

    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final radius = double.tryParse(_radiusCtrl.text.trim()) ?? 500;

    if (lat == null || lng == null) {
      _showSnack('❌ Invalid coordinates', isError: true);
      return;
    }

    if (name.isEmpty) {
      _showSnack('❌ Client name is required', isError: true);
      return;
    }

    final confirmed = await _showConfirmDialog(
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      radius: radius,
    );
    if (confirmed != true) return;

    setState(() => _saving = true);

    try {
      final update = <String, dynamic>{
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'radiusMeters': radius,
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('client_locations')
          .doc(widget.client['id'])
          .update(update)
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('❌ [Edit] FAILED: $e');
      if (!mounted) return;
      _showSnack('Update failed: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  Future<bool?> _showConfirmDialog({
    required String name,
    required String address,
    required double lat,
    required double lng,
    required double radius,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        title: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: tc.orange, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Changes?',
                style: TextStyle(
                  color: tc.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow('Name', name),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 6),
              _confirmRow('Address', address),
            ],
            const SizedBox(height: 6),
            _confirmRow('Coordinates', '$lat, $lng'),
            const SizedBox(height: 6),
            _confirmRow('Radius', '${radius.toStringAsFixed(0)}m'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: tc.muted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Confirm & Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: tc.orange,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tc.muted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tc.text,
            ),
          ),
        ),
      ],
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? tc.red : tc.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Dialog(
      backgroundColor: tc.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tc.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_location_alt_rounded,
                        color: _isDemo ? tc.muted : tc.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Client Location',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: tc.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.client['name']?.toString() ?? '',
                          style: TextStyle(
                              fontSize: 11, color: tc.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        color: tc.muted, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tc.border),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Client Name
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: _inputDeco('Client Name *',
                            hint: 'e.g. ABC Corporation HQ'),
                        style: TextStyle(color: tc.text),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Address (primary)
                      TextFormField(
                        controller: _addressCtrl,
                        maxLines: 2,
                        decoration: _inputDeco('Address *',
                            hint:
                            'e.g. 629 J. Nepomuceno St, Quiapo')
                            .copyWith(
                          suffixIcon: _geocodingAddress
                              ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                              CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tc.orange,
                              ),
                            ),
                          )
                              : null,
                        ),
                        style: TextStyle(color: tc.text),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 6),

                      // Status
                      if (_geocodeStatus != null)
                        Row(
                          children: [
                            Icon(
                              _geocodeStatus!.startsWith('✅')
                                  ? Icons.check_circle_outline
                                  : (_geocodeStatus!.startsWith('❌')
                                  ? Icons.error_outline
                                  : Icons.hourglass_empty),
                              size: 12,
                              color: _geocodeStatus!.startsWith('✅')
                                  ? tc.green
                                  : (_geocodeStatus!.startsWith('❌')
                                  ? tc.red
                                  : tc.orange),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _geocodeStatus!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _geocodeStatus!.startsWith('✅')
                                      ? tc.green
                                      : (_geocodeStatus!
                                      .startsWith('❌')
                                      ? tc.red
                                      : tc.orange),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),

                      // Lat/Lng/Radius
                      if (isWide)
                        Row(
                          children: [
                            Expanded(child: _buildLatField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildLngField()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildRadiusField()),
                          ],
                        )
                      else ...[
                        _buildLatField(),
                        const SizedBox(height: 12),
                        _buildLngField(),
                        const SizedBox(height: 12),
                        _buildRadiusField(),
                      ],
                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openInGoogleMaps,
                          icon: Icon(Icons.map_rounded,
                              size: 16, color: tc.orange),
                          label: Text(
                            'View coordinates on Google Maps',
                            style: TextStyle(
                              fontSize: 12,
                              color: tc.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Options
                      if (isWide)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _loadingLocation
                                    ? null
                                    : _useCurrentLocation,
                                icon: _loadingLocation
                                    ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                  CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                                    : Icon(
                                    Icons.my_location_rounded,
                                    size: 16,
                                    color: tc.orange),
                                label: Text(
                                  'Use My GPS',
                                  style: TextStyle(
                                    color: tc.orange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: tc.orange, width: 1.5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isDemo ? _demoBlock : _pickOnMap,
                                icon: Icon(Icons.map_rounded,
                                    size: 16,
                                    color: _isDemo ? tc.muted : tc.orange),
                                label: Text(
                                  'Pick on Map',
                                  style: TextStyle(
                                    color: _isDemo ? tc.muted : tc.orange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: _isDemo ? tc.border : tc.orange,
                                      width: 1.5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pasteCoordsFromClipboard,
                                icon: Icon(
                                    Icons.content_paste_rounded,
                                    size: 16,
                                    color: tc.text),
                                label: Text(
                                  'Paste',
                                  style: TextStyle(
                                    color: tc.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: tc.border),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _loadingLocation
                                ? null
                                : _useCurrentLocation,
                            icon: _loadingLocation
                                ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                                : Icon(Icons.my_location_rounded,
                                size: 16, color: tc.orange),
                            label: Text(
                              'Use My GPS',
                              style: TextStyle(
                                color: tc.orange,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: tc.orange, width: 1.5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isDemo ? _demoBlock : _pickOnMap,
                            icon: Icon(Icons.map_rounded,
                                size: 16,
                                color: _isDemo ? tc.muted : tc.orange),
                            label: Text(
                              'Pick on Map',
                              style: TextStyle(
                                color: _isDemo ? tc.muted : tc.orange,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: _isDemo ? tc.border : tc.orange,
                                  width: 1.5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _pasteCoordsFromClipboard,
                            icon: Icon(Icons.content_paste_rounded,
                                size: 16, color: tc.text),
                            label: Text(
                              'Paste Coords',
                              style: TextStyle(
                                color: tc.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: tc.border),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Switch(
                            value: _isActive,
                            onChanged: (_saving || _isDemo)
                                ? null
                                : (v) =>
                                setState(() => _isActive = v),
                            activeColor: _isDemo ? tc.muted : tc.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isActive ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                              _isActive ? tc.green : tc.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Divider(height: 1, color: tc.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: tc.muted),
                    label: Text('Cancel',
                        style: TextStyle(color: tc.muted)),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: (_saving || _isDemo)
                        ? (_isDemo ? _demoBlock : null)
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Icon(
                      _isDemo
                          ? Icons.lock_outline_rounded
                          : Icons.save_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : (_isDemo
                          ? 'Save Disabled (Demo)'
                          : 'Save Changes'),
                      style:
                      const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDemo ? tc.border : tc.orange,
                      foregroundColor: _isDemo ? tc.muted : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  Widget _buildLatField() {
    return TextFormField(
      controller: _latCtrl,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      decoration:
      _inputDeco('Latitude *', hint: 'e.g. 14.5547'),
      style: TextStyle(color: tc.text),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v.trim()) == null) return 'Invalid number';
        return null;
      },
    );
  }

  Widget _buildLngField() {
    return TextFormField(
      controller: _lngCtrl,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      decoration:
      _inputDeco('Longitude *', hint: 'e.g. 121.0244'),
      style: TextStyle(color: tc.text),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v.trim()) == null) return 'Invalid number';
        return null;
      },
    );
  }

  Widget _buildRadiusField() {
    return TextFormField(
      controller: _radiusCtrl,
      keyboardType: TextInputType.number,
      decoration: _inputDeco('Radius (meters)', hint: '500'),
      style: TextStyle(color: tc.text),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        final d = double.tryParse(v.trim());
        if (d == null || d <= 0) return 'Invalid';
        return null;
      },
    );
  }

  InputDecoration _inputDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: tc.muted),
      hintStyle: TextStyle(color: tc.muted.withValues(alpha: 0.6)),
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
        borderSide: BorderSide(color: tc.orange, width: 2),
      ),
    );
  }
}