// lib/screens/admin_attendance_verification_page.dart
// v2.7: ✅ Field selfie proof review (field_proofs) — approve/reject together
//       with the attendance log, audit trail + employee notification.
// v2.6: 🛠️ Fixed missing GPS data by querying `activity_logs` as fallback.
//       Now searches multiple collections to find the coordinates.
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'admin_theme.dart';
import '../services/demo_mode_service.dart';
import '../widgets/bootstrap_grid.dart';

class AdminAttendanceVerificationPage extends StatefulWidget {
  final String logId;
  final Map<String, dynamic> logData;
  final VoidCallback? onBack;

  const AdminAttendanceVerificationPage({
    super.key,
    required this.logId,
    required this.logData,
    this.onBack,
  });

  @override
  State<AdminAttendanceVerificationPage> createState() =>
      _AdminAttendanceVerificationPageState();
}

class _AdminAttendanceVerificationPageState
    extends State<AdminAttendanceVerificationPage> {
  Map<String, dynamic>? _employeeData;
  String? _deviceInfoOverride;
  String _deviceStatus = 'none';
  String _registeredDeviceValue = '';
  String _actualDeviceValue = '';
  String? _clientInfoOverride;

  // Map & GPS State
  final MapController _mapController = MapController();
  ll.LatLng? _clockInCoords;
  ll.LatLng? _clockOutCoords;
  DateTime? _clockInTime;
  DateTime? _clockOutTime;

  // ── Field proof (selfie) state ──
  String? _proofId;
  Map<String, dynamic>? _proofData;
  Uint8List? _proofBytes;
  ll.LatLng? _proofCoords;

  // Debug Console
  List<String> _debugMessages = [];

  bool _loading = true;
  bool _processingAction = false;
  bool _disposed = false;
  bool get _safe => mounted && !_disposed;

  void _safeSetState(VoidCallback fn) {
    if (_safe) setState(fn);
  }

  AdminColors get tc => AdminTheme.getColors(context);

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

  String get _actorEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ?? 'unknown';
  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

  bool get _hasProof => _proofId != null && _proofData != null;
  String get _proofStatus =>
      (_proofData?['status'] ?? 'pending').toString().toLowerCase();
  bool get _isClockInPhoto => _proofData?['source'] == 'clock_in_photo';

  @override
  void initState() {
    super.initState();
    _fetchRelatedData();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // FIELD PROOF HELPERS
  // ══════════════════════════════════════════════════════════════
  /// Finds the field_proofs doc id from `fieldProofId` or from the
  /// `proof:<id>` tag written into `remarks` by the face screen.
  String? _extractProofId(Map<String, dynamic> log) {
    final direct = (log['fieldProofId'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final remarks = (log['remarks'] ?? '').toString();
    final m = RegExp(r'proof:([A-Za-z0-9_\-]+)').firstMatch(remarks);
    return m?.group(1);
  }

    /// Fallback: kung walang `proof:<id>` sa log, hanapin ang field_proofs
  /// ng parehong empleyado, parehong araw at parehong IN/OUT.
  Future<String?> _findProofByEmployeeAndDay(Map<String, dynamic> log) async {
    try {
      final empId =
          (log['employee_id'] ?? log['employeeId'] ?? '').toString().trim();
      if (empId.isEmpty) return null;
      final logTs =
          _toDateTime(log['timestamp'] ?? log['date'] ?? log['createdAt']);
      if (logTs == null) return null;
      final type = (log['type'] ?? '').toString().toUpperCase();

      final snap = await FirebaseFirestore.instance
          .collection('field_proofs')
          .where('employeeId', isEqualTo: empId)
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 10));

      String? bestId;
      Duration? bestDiff;
      for (final d in snap.docs) {
        final data = d.data();
        final at = _toDateTime(data['capturedAt']);
        if (at == null) continue;
        if (at.year != logTs.year ||
            at.month != logTs.month ||
            at.day != logTs.day) {
          continue;
        }
        final t = (data['attendanceType'] ?? '').toString().toUpperCase();
        if (type.isNotEmpty && t.isNotEmpty && t != type) continue;
        final diff = at.difference(logTs).abs();
        if (bestDiff == null || diff < bestDiff) {
          bestDiff = diff;
          bestId = d.id;
        }
      }
      _debugMessages.add(bestId != null
          ? 'Proof matched by employee/day: $bestId'
          : 'No proof found for $empId on this day.');
      return bestId;
    } catch (e) {
      _debugMessages.add('Proof lookup error: $e');
      return null;
    }
  }

  Future<void> _loadFieldProof(Map<String, dynamic> log) async {
    String? id = _extractProofId(log);
    if (id == null || id.isEmpty) {
      id = await _findProofByEmployeeAndDay(log);
    }
    if (id == null || id.isEmpty) {
      _debugMessages.add('No field proof linked to this log.');
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('field_proofs')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!doc.exists || doc.data() == null) {
        _debugMessages.add('Field proof $id not found.');
        return;
      }
      final d = doc.data()!;
      _proofId = id;
      _proofData = d;

      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat != null && lng != null) _proofCoords = ll.LatLng(lat, lng);

      final photo = (d['photo'] ?? '').toString();
      if (photo.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photo.split(',').last);
          if (bytes.length <= 2 * 1024 * 1024) _proofBytes = bytes;
        } catch (_) {}
      }
      _debugMessages.add('Field proof loaded: $id (${d['status']})');
    } catch (e) {
      _debugMessages.add('Field proof error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // RECURSIVE LATLNG EXTRACTOR
  // ══════════════════════════════════════════════════════════════
  ll.LatLng? _extractLatLng(dynamic data) {
    if (data == null) return null;

    if (data is GeoPoint) return ll.LatLng(data.latitude, data.longitude);

    if (data is Map) {
      final latKeys = ['latitude', 'lat', 'gps_lat', 'gpsLatitude', 'gps_latitude', 'clockInLatitude', 'clockOutLatitude', 'clock_in_lat', 'clock_out_lat', 'timeInLat', 'timeOutLat', 'latitudeIn', 'latitudeOut', 'checkInLat', 'checkOutLat', 'lastLat', 'currentLat'];
      final lngKeys = ['longitude', 'lng', 'lon', 'gps_lng', 'gpsLongitude', 'gps_longitude', 'clockInLongitude', 'clockOutLongitude', 'clock_in_lng', 'clock_out_lng', 'timeInLng', 'timeOutLng', 'longitudeIn', 'longitudeOut', 'checkInLng', 'checkOutLng', 'lastLng', 'currentLng'];

      for (final k in latKeys) {
        if (data.containsKey(k)) {
          for (final l in lngKeys) {
            if (data.containsKey(l)) {
              final lat = data[k];
              final lng = data[l];
              if (lat is num && lng is num) return ll.LatLng(lat.toDouble(), lng.toDouble());
              if (lat is String && lng is String) {
                final latD = double.tryParse(lat);
                final lngD = double.tryParse(lng);
                if (latD != null && lngD != null) return ll.LatLng(latD, lngD);
              }
            }
          }
        }
      }

      final nestedKeys = ['location', 'geopoint', 'geo', 'coordinates', 'clockInLocation', 'clockOutLocation', 'attendanceLocation', 'gps', 'position', 'coord', 'loc', 'checkInLocation', 'checkOutLocation', 'map_location', 'location_map', 'lastLocation', 'currentLocation'];
      for (final key in nestedKeys) {
        if (data.containsKey(key)) {
          final res = _extractLatLng(data[key]);
          if (res != null) return res;
        }
      }
    }

    if (data is List && data.length >= 2) {
      final lat = data[0];
      final lng = data[1];
      if (lat is num && lng is num) return ll.LatLng(lat.toDouble(), lng.toDouble());
    }

    if (data is String) {
      final parts = data.split(',');
      if (parts.length == 2) {
        final latD = double.tryParse(parts[0].trim());
        final lngD = double.tryParse(parts[1].trim());
        if (latD != null && lngD != null) return ll.LatLng(latD, lngD);
      }
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // DEVICE MATCH HELPERS
  // ══════════════════════════════════════════════════════════════
  bool _fuzzyDeviceMatch(String registered, String actual) {
    final regLower = registered.toLowerCase().trim();
    final actLower = actual.toLowerCase().trim();

    if (regLower.isEmpty || actLower.isEmpty) return false;
    if (regLower == actLower) return true;

    String clean(String s) {
      return s.replaceAll(RegExp(r'\(web\)', caseSensitive: false), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    final regClean = clean(regLower);
    final actClean = clean(actLower);

    if (regClean.isEmpty || actClean.isEmpty) return false;
    if (regClean == actClean) return true;

    const genericTerms = {
      'mobile app', 'web browser', 'android app', 'ios app', 'windows app',
      'macos app', 'linux app', 'mobile', 'web', 'android', 'ios',
      'unknown device', 'not recorded', '—', 'null',
    };

    final regIsGeneric = genericTerms.contains(regClean);
    final actIsGeneric = genericTerms.contains(actClean);

    if (regIsGeneric != actIsGeneric) return false;
    if (regIsGeneric && actIsGeneric) return regClean == actClean;

    final regTokens = regClean.split(RegExp(r'[\s\-_\,\.]+')).where((t) => t.length >= 2).toSet();
    final actTokens = actClean.split(RegExp(r'[\s\-_\,\.]+')).where((t) => t.length >= 2).toSet();

    if (regTokens.isEmpty || actTokens.isEmpty) return false;

    final shorter = regTokens.length <= actTokens.length ? regTokens : actTokens;
    final longer = regTokens.length <= actTokens.length ? actTokens : regTokens;

    return shorter.every((t) => longer.contains(t));
  }

  bool _isLegacyDeviceValue(String value) {
    final v = value.toLowerCase().trim();
    return v == 'mobile app' || v == 'android app' || v == 'ios app' || v == 'windows app' || v == 'macos app' || v == 'linux app';
  }

  bool _isSystemAction(String value) {
    final v = value.toLowerCase().trim();
    return v.contains('auto clock') || v == 'system' || v == 'server' || v == 'cron' || v.contains('dashboard');
  }

  Map<String, dynamic> _extractDeviceInfoWithSource(Map<String, dynamic> log) {
    String registeredDevice = '';
    if (_employeeData != null) {
      final candidates = [_employeeData!['registeredDevice'], _employeeData!['deviceModel'], _employeeData!['deviceName'], _employeeData!['device']];
      for (final c in candidates) {
        final v = (c ?? '').toString().trim();
        if (v.isNotEmpty && v != '—' && v.toLowerCase() != 'null' && v.toLowerCase() != 'not recorded') {
          registeredDevice = v;
          break;
        }
      }
    }

    String actualDevice = '';
    const specificKeys = ['deviceModel', 'deviceInfo', 'clientDevice', 'phoneModel', 'deviceName'];
    for (final key in specificKeys) {
      final v = (log[key] ?? '').toString().trim();
      if (v.isNotEmpty && v != '—' && v.toLowerCase() != 'null' && v.toLowerCase() != 'mobile app' && v.toLowerCase() != 'web browser' && !_isLegacyDeviceValue(v)) {
        actualDevice = v;
        break;
      }
    }

    if (actualDevice.isEmpty) {
      final v = (log['device'] ?? '').toString().trim();
      if (v.isNotEmpty && v != '—' && v.toLowerCase() != 'null') actualDevice = v;
    }

    if (actualDevice.isEmpty) {
      const fallbackKeys = ['platform', 'os', 'userAgent', 'browser'];
      for (final key in fallbackKeys) {
        final v = (log[key] ?? '').toString().trim();
        if (v.isNotEmpty && v != '—' && v.toLowerCase() != 'null') {
          actualDevice = v;
          break;
        }
      }
    }

    if (_isSystemAction(actualDevice) || _isLegacyDeviceValue(actualDevice)) {
      actualDevice = '';
    }

    if (registeredDevice.isNotEmpty) {
      if (_isLegacyDeviceValue(registeredDevice)) {
        if (actualDevice.isNotEmpty && !_isLegacyDeviceValue(actualDevice)) {
          return {'displayValue': actualDevice, 'status': 'legacy', 'registeredDevice': registeredDevice, 'actualDevice': actualDevice};
        }
        return {'displayValue': registeredDevice, 'status': 'registered', 'registeredDevice': registeredDevice, 'actualDevice': actualDevice.isNotEmpty ? actualDevice : registeredDevice};
      }

      if (actualDevice.isEmpty) return {'displayValue': registeredDevice, 'status': 'registered', 'registeredDevice': registeredDevice, 'actualDevice': ''};

      final matches = _fuzzyDeviceMatch(registeredDevice, actualDevice);
      if (matches) {
        return {'displayValue': registeredDevice, 'status': 'registered', 'registeredDevice': registeredDevice, 'actualDevice': actualDevice};
      } else {
        return {'displayValue': actualDevice, 'status': 'unregistered', 'registeredDevice': registeredDevice, 'actualDevice': actualDevice};
      }
    }

    if (actualDevice.isNotEmpty) return {'displayValue': actualDevice, 'status': 'none', 'registeredDevice': '', 'actualDevice': actualDevice};

    return {'displayValue': 'Not recorded', 'status': 'none', 'registeredDevice': '', 'actualDevice': ''};
  }

  String? _extractClientInfo(Map<String, dynamic> data) {
    const keys = ['client', 'clientName', 'clientInfo', 'purpose', 'reason', 'verificationMethod', 'verificationNote', 'note'];
    for (final key in keys) {
      final v = data[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH DATA (MAY DEBUG LOGS)
  // ══════════════════════════════════════════════════════════════
  Future<void> _fetchRelatedData() async {
    _debugMessages.clear();

    if (_isDemo) {
      final log = widget.logData;
      _clientInfoOverride = _extractClientInfo(log);
      _employeeData = {
        'name': log['employees_name'] ?? log['employee_name'] ?? 'Demo Employee',
        'employeeId': log['employee_id'] ?? log['employeeId'] ?? 'DEMO-001',
        'department': log['department'] ?? 'Operations',
        'role': log['position'] ?? 'Staff',
        'photoUrl': '',
        'deviceName': log['registeredDevice'] ?? 'iPhone 14 Pro',
      };

      _deviceInfoOverride = log['registeredDevice']?.toString() ?? 'iPhone 14 Pro';
      _deviceStatus = 'registered';
      _registeredDeviceValue = _deviceInfoOverride!;
      _actualDeviceValue = _deviceInfoOverride!;

      _clockInCoords = const ll.LatLng(14.5995, 120.9842);
      _clockOutCoords = const ll.LatLng(14.5547, 121.0244);
      _clockInTime = DateTime.now().subtract(const Duration(hours: 8));
      _clockOutTime = DateTime.now();

      if (_safe) _safeSetState(() => _loading = false);
      return;
    }

    final log = widget.logData;
    final empId = (log['employee_id'] ?? log['employeeId'] ?? log['employees_id'] ?? log['employeeDocId'] ?? '').toString();
    final empAuthUid = (log['authUid'] ?? log['auth_uid'] ?? '').toString();
    final empName = (log['employees_name'] ?? log['employee_name'] ?? log['name'] ?? '').toString();

    final logTs = _toDateTime(log['timestamp'] ?? log['date'] ?? log['createdAt'] ?? log['clockInTime']);
    final targetDate = logTs ?? DateTime.now();

    _debugMessages.add('Target Date: ${DateFormat('yyyy-MM-dd').format(targetDate)}');
    _debugMessages.add('Target EmpID: $empId');

    _clientInfoOverride = _extractClientInfo(log);

    final logCoords = _extractLatLng(log);
    if (logCoords != null) {
      _clockInCoords = logCoords;
      _clockInTime = logTs;
      _debugMessages.add('Found GPS in current log!');
    }

    // ── Field selfie proof (if this log was submitted from the field) ──
    await _loadFieldProof(log);

    try {
      Map<String, dynamic>? found;
      if (empId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('employees').doc(empId).get();
        if (doc.exists && doc.data() != null) found = {...doc.data()!, 'id': doc.id};
      }
      if (found == null && empAuthUid.isNotEmpty) {
        final s = await FirebaseFirestore.instance.collection('employees').where('authUid', isEqualTo: empAuthUid).limit(1).get();
        if (s.docs.isNotEmpty) found = {...s.docs.first.data()!, 'id': s.docs.first.id};
      }
      if (found == null && empName.isNotEmpty) {
        final s = await FirebaseFirestore.instance.collection('employees').where('name', isEqualTo: empName).limit(1).get();
        if (s.docs.isNotEmpty) found = {...s.docs.first.data()!, 'id': s.docs.first.id};
      }
      _employeeData = found;
      if (found != null) _debugMessages.add('Employee profile found. ID: ${found['id']}');
    } catch (e) {
      _debugMessages.add('Emp error: $e');
    }

    if (_clockInCoords == null && _employeeData != null) {
      final empCoords = _extractLatLng(_employeeData!);
      if (empCoords != null) {
        _clockInCoords = empCoords;
        _clockInTime = targetDate;
        _debugMessages.add('Found GPS in Employee Profile!');
      }
    }

    final Set<String> searchIds = {empId};
    if (_employeeData != null) {
      searchIds.add((_employeeData!['id'] ?? '').toString());
      searchIds.add((_employeeData!['employeeId'] ?? '').toString());
    }
    searchIds.removeWhere((e) => e.isEmpty);

    if (searchIds.isNotEmpty) {
      try {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs = [];

        // 1. Hanapin sa attendance_logs
        try {
          final snap1 = await FirebaseFirestore.instance.collection('attendance_logs')
              .where('employee_id', whereIn: searchIds.toList()).get();
          allDocs.addAll(snap1.docs);
        } catch (_) {}

        // 2. Hanapin sa activity_logs (Madalas nandito ang GPS galing phone)
        try {
          final snap2 = await FirebaseFirestore.instance.collection('activity_logs')
              .where('employee_id', whereIn: searchIds.toList()).get();
          allDocs.addAll(snap2.docs);
        } catch (_) {}

        // 3. Hanapin sa activity logs (legacy)
        try {
          final snap3 = await FirebaseFirestore.instance.collection('activity logs')
              .where('employee_id', whereIn: searchIds.toList()).get();
          allDocs.addAll(snap3.docs);
        } catch (_) {}

        _debugMessages.add('Fetched ${allDocs.length} logs total.');

        // I-sort lahat mula pinakabago pababa
        allDocs.sort((a, b) {
          final ta = _toDateTime(a.data()['timestamp'] ?? a.data()['date'] ?? a.data()['createdAt']);
          final tb = _toDateTime(b.data()['timestamp'] ?? b.data()['date'] ?? b.data()['createdAt']);
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

        for (var doc in allDocs) {
          final data = doc.data();
          final ts = _toDateTime(data['timestamp'] ?? data['date'] ?? data['createdAt']);

          if (ts == null) continue;
          if (ts.year != targetDate.year || ts.month != targetDate.month || ts.day != targetDate.day) continue;

          final coords = _extractLatLng(data);
          if (coords != null) {
            final type = (data['type'] ?? data['status'] ?? data['action'] ?? '').toString().toUpperCase();

            _debugMessages.add('Log [${DateFormat('hh:mm a').format(ts)}] Type: $type, HasGPS: Yes');

            if (type.contains('IN') || type.contains('LOGIN') || type.contains('CLOCKED IN')) {
              if (_clockInCoords == null) {
                _clockInCoords = coords;
                _clockInTime = ts;
              }
            } else if (type.contains('OUT') || type.contains('LOGOUT') || type.contains('CLOCKED OUT')) {
              if (_clockOutCoords == null) {
                _clockOutCoords = coords;
                _clockOutTime = ts;
              }
            } else {
              if (_clockInCoords == null) {
                _clockInCoords = coords;
                _clockInTime = ts;
              } else if (_clockOutCoords == null && ts.isAfter(_clockInTime!)) {
                _clockOutCoords = coords;
                _clockOutTime = ts;
              }
            }
          } else {
            final type = (data['type'] ?? data['status'] ?? data['action'] ?? '').toString().toUpperCase();
            _debugMessages.add('Log [${DateFormat('hh:mm a').format(ts)}] Type: $type, NO GPS.');
          }
        }
      } catch (e) {
        _debugMessages.add('Query Error: $e');
      }
    } else {
      _debugMessages.add('No search IDs available.');
    }

    final deviceResult = _extractDeviceInfoWithSource(log);
    _deviceInfoOverride = deviceResult['displayValue'] as String;
    _deviceStatus = deviceResult['status'] as String;
    _registeredDeviceValue = deviceResult['registeredDevice'] as String? ?? '';
    _actualDeviceValue = deviceResult['actualDevice'] as String? ?? '';

    if (_safe) _safeSetState(() => _loading = false);
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
  String _s(dynamic v, [String fallback = 'Not recorded']) {
    if (v == null) return fallback;
    final str = v.toString().trim();
    return str.isEmpty ? fallback : str;
  }

  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtTimelineDate(DateTime? dt) {
    if (dt == null) return 'Not recorded';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    final time = DateFormat('hh:mm a').format(dt);
    if (diff == 0) return 'Today, $time';
    if (diff == 1) return 'Yesterday, $time';
    return '${DateFormat('MMM d').format(dt)}, $time';
  }

  String _fmtFullDate(DateTime? dt) {
    if (dt == null) return 'Not recorded';
    return DateFormat('MMM d, yyyy \u2022 hh:mm:ss a').format(dt);
  }

  String _formatEmployeeId() {
    if (_employeeData != null) {
      final actualId = _s(_employeeData!['employeeId'], '');
      if (actualId.isNotEmpty && actualId != 'Not recorded' && !actualId.contains(':')) return actualId.toUpperCase();
      final docId = _s(_employeeData!['id'], '');
      if (docId.isNotEmpty) return 'EMP-${docId.substring(0, docId.length > 6 ? 6 : docId.length).toUpperCase()}';
    }
    final raw = widget.logId;
    if (raw.isEmpty) return 'EMP-0000';
    return 'EMP-${raw.substring(0, raw.length > 6 ? 6 : raw.length).toUpperCase()}';
  }

  String _getDepartment() {
    if (_employeeData != null) {
      final d = _s(_employeeData!['department'], '');
      if (d.isNotEmpty && d != 'Not recorded') return d;
    }
    final fromLog = _s(widget.logData['department'], '');
    return (fromLog.isNotEmpty && fromLog != 'Not recorded') ? fromLog : 'Not recorded';
  }

  String _getManager() {
    if (_employeeData != null) {
      final m = _s(_employeeData!['manager'] ?? _employeeData!['managerName'] ?? _employeeData!['supervisor'], '');
      if (m.isNotEmpty && m != 'Not recorded') return m;
    }
    return 'Not assigned';
  }

  String _getRole() {
    if (_employeeData != null) {
      final r = _s(_employeeData!['role'] ?? _employeeData!['position'], '');
      if (r.isNotEmpty && r != 'Not recorded') return r;
    }
    return _s(widget.logData['role'], 'Employee');
  }

  String _getPhotoUrl() {
    if (_employeeData != null) {
      final p = _s(_employeeData!['photoUrl'] ?? _employeeData!['photo'], '');
      if (p.isNotEmpty && p != 'Not recorded') return p;
    }
    return _s(widget.logData['photoUrl'], '');
  }

  String _getDeviceInfo() {
    if (_deviceInfoOverride != null && _deviceInfoOverride!.isNotEmpty && _deviceInfoOverride != '—') return _deviceInfoOverride!;
    return 'Not recorded';
  }

  String _getClientInfo() {
    if (_clientInfoOverride != null && _clientInfoOverride!.isNotEmpty) return _clientInfoOverride!;
    return 'Not specified';
  }

  // ══════════════════════════════════════════════════════════════
  // ACTIONS (Approve & Flag)
  // ══════════════════════════════════════════════════════════════
  Future<void> _writeAudit(String action, Map<String, dynamic> details) async {
    try {
      await FirebaseFirestore.instance.collection('admin_audit_log').add({
        'action': action,
        'targetType': 'attendance_log',
        'targetId': widget.logId,
        'actorUid': _actorUid,
        'actorEmail': _actorEmail,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _notifyEmployee(String title, String message) async {
    try {
      final empId = (widget.logData['employee_id'] ??
              widget.logData['employeeId'] ??
              _proofData?['employeeId'] ??
              '')
          .toString()
          .trim();
      if (empId.isEmpty) return;
      await FirebaseFirestore.instance.collection('employee_notifications').add({
        'employeeId': empId,
        'employee_id': empId,
        'type': 'attendance',
        'title': title,
        'message': message,
        'senderName': _actorEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      }).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> _approveLog() async {
    if (_isDemo) return _demoBlock();

        if (_hasProof && _proofStatus != 'pending' && _proofStatus != 'auto') {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: tc.card,
          title: Text('Proof already $_proofStatus', style: TextStyle(color: tc.text)),
          content: Text('This field proof was already reviewed. Approve again?', style: TextStyle(color: tc.text, fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: tc.muted))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tc.orange), onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
          ],
        ),
      );
      if (go != true) return;
    }

    _safeSetState(() => _processingAction = true);
    try {
      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();

      batch.set(fs.collection('attendance_logs').doc(widget.logId), {
        'reviewStatus': 'approved',
        'reviewedBy': _actorEmail,
        'reviewedByUid': _actorUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        if (_hasProof) 'fieldProofId': _proofId,
      }, SetOptions(merge: true));

      if (_hasProof) {
        batch.set(fs.collection('field_proofs').doc(_proofId), {
          'status': 'approved',
          'reviewedBy': _actorEmail,
          'reviewedByUid': _actorUid,
          'reviewedAt': FieldValue.serverTimestamp(),
          'attendanceLogId': widget.logId,
        }, SetOptions(merge: true));
      }

      await batch.commit().timeout(const Duration(seconds: 15));

      await _writeAudit(
        _hasProof ? 'field_proof_approved' : 'attendance_approved',
        {'fieldProofId': _proofId, 'proofStatusBefore': _proofStatus},
      );
        if (_hasProof && !_isClockInPhoto) {
        await _notifyEmployee('Field Attendance Approved',
            'Your field selfie attendance was approved by HR.');
      }

      if (!_safe) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance approved.'), backgroundColor: Colors.green));
      widget.onBack?.call();
    } catch (e) {
      if (!_safe) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: tc.red));
    } finally {
      if (_safe) _safeSetState(() => _processingAction = false);
    }
  }

  Future<void> _flagLog() async {
    if (_isDemo) return _demoBlock();

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        title: Text(_hasProof ? 'Reject Field Proof' : 'Flag for Review', style: TextStyle(color: tc.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasProof)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('The selfie proof will be rejected and this attendance flagged. The employee will be notified.', style: TextStyle(color: tc.textMuted, fontSize: 12)),
              ),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              style: TextStyle(color: tc.text),
              decoration: InputDecoration(labelText: 'Reason', labelStyle: TextStyle(color: tc.muted), border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: tc.muted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: tc.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_hasProof ? 'Reject' : 'Flag'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim();
    if (_hasProof && reason.length < 5) {
      if (!_safe) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Please provide a reason (min. 5 characters).'), backgroundColor: tc.red));
      return;
    }

    _safeSetState(() => _processingAction = true);
    try {
      final fs = FirebaseFirestore.instance;
      final batch = fs.batch();

      batch.set(fs.collection('attendance_logs').doc(widget.logId), {
        'reviewStatus': 'flagged',
        'reviewReason': reason,
        'reviewedBy': _actorEmail,
        'reviewedByUid': _actorUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        if (_hasProof) 'fieldProofId': _proofId,
      }, SetOptions(merge: true));

      if (_hasProof) {
        batch.set(fs.collection('field_proofs').doc(_proofId), {
          'status': 'rejected',
          'reviewReason': reason,
          'reviewedBy': _actorEmail,
          'reviewedByUid': _actorUid,
          'reviewedAt': FieldValue.serverTimestamp(),
          'attendanceLogId': widget.logId,
        }, SetOptions(merge: true));
      }

      await batch.commit().timeout(const Duration(seconds: 15));

      await _writeAudit(
        _hasProof ? 'field_proof_rejected' : 'attendance_flagged',
        {'fieldProofId': _proofId, 'reason': reason},
      );
      if (_hasProof && !_isClockInPhoto) {
        await _notifyEmployee('Field Attendance Rejected',
            'Your field selfie attendance was rejected by HR. Reason: $reason');
      }

      if (!_safe) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_hasProof ? 'Field proof rejected.' : 'Attendance flagged for review.'),
        backgroundColor: Colors.orange,
      ));
      widget.onBack?.call();
    } catch (e) {
      if (!_safe) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: tc.red));
    } finally {
      if (_safe) _safeSetState(() => _processingAction = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final name = _s(_employeeData?['name'] ?? widget.logData['employees_name'] ?? widget.logData['employee_name'] ?? widget.logData['name'], 'System User');
    final role = _getRole();
    final department = _getDepartment();
    final manager = _getManager();
    final photoUrl = _getPhotoUrl();
    final client = _getClientInfo();
    final deviceInfo = _getDeviceInfo();
    final verificationNote = _hasProof
        ? (_isClockInPhoto ? 'Clock-in Photo' : 'Field Selfie Proof')
        : _s(widget.logData['verificationNote'], 'Off-site Client Meeting Proof');
    final employeeId = _formatEmployeeId();
    final ts = _toDateTime(widget.logData['timestamp'] ?? widget.logData['date'] ?? widget.logData['createdAt'] ?? widget.logData['clockInTime']);
    final dateStr = _fmtFullDate(ts);

    final rawHistory = widget.logData['history'];
    final List<Map<String, dynamic>> historyList = rawHistory is List ? rawHistory.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
    final timeline = [widget.logData, ...historyList];

    return Container(
      color: tc.background,
      child: SingleChildScrollView(
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 16),
              ],
              if (widget.logData['isOverridden'] == true || widget.logData['overriddenBy'] != null || widget.logData['manualEntry'] == true) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFFFF7ED), border: Border.all(color: const Color(0xFFF59E0B)), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note_rounded, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Edited by: ${widget.logData['overriddenByEmail'] ?? widget.logData['overriddenByName'] ?? widget.logData['overriddenBy'] ?? 'Admin'}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E))
                            ),
                            Text(
                                'Reason: ${widget.logData['overrideReason'] ?? widget.logData['manualNote'] ?? 'No reason provided'}',
                                style: const TextStyle(color: Color(0xFFB45309))
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              _buildBreadcrumb(tc),
              const SizedBox(height: 8),
              _buildPageHeader(context, tc),
              const SizedBox(height: 24),
              if (_loading && !_isDemo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tc.orange)),
                      const SizedBox(width: 10),
                      Text('Fetching employee details...', style: TextStyle(fontSize: 12, color: tc.muted)),
                    ],
                  ),
                ),
              LayoutBuilder(builder: (_, c) {
                final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);

                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLeftColumn(tc, name: name, role: role, department: department, manager: manager, photoUrl: photoUrl, employeeId: employeeId, timeline: timeline),
                      const SizedBox(height: 20),
                      _buildVerificationCard(context, tc, client: client, deviceInfo: deviceInfo, deviceStatus: _deviceStatus, registeredDevice: _registeredDeviceValue, actualDevice: _actualDeviceValue, verificationNote: verificationNote, dateStr: dateStr),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 420, child: _buildLeftColumn(tc, name: name, role: role, department: department, manager: manager, photoUrl: photoUrl, employeeId: employeeId, timeline: timeline)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildVerificationCard(context, tc, client: client, deviceInfo: deviceInfo, deviceStatus: _deviceStatus, registeredDevice: _registeredDeviceValue, actualDevice: _actualDeviceValue, verificationNote: verificationNote, dateStr: dateStr)),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDemoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: tc.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10), border: Border.all(color: tc.orange.withValues(alpha: 0.45))),
      child: Row(
        children: [
          Icon(Icons.science_rounded, color: tc.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Demo Mode Active', style: TextStyle(fontWeight: FontWeight.w800, color: tc.orange, fontSize: 13)),
                Text('Showing sample verification data. Actions are disabled.', style: TextStyle(fontSize: 11, color: tc.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(AdminColors tc) {
    if (widget.onBack == null) return const SizedBox.shrink();
    return InkWell(
      onTap: widget.onBack,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12.0, top: 4, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, color: tc.orange, size: 18),
            const SizedBox(width: 6),
            Text('Back to Attendance Logs', style: TextStyle(color: tc.orange, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader(BuildContext context, AdminColors tc) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);

      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance Verification', style: TextStyle(fontSize: r.responsive<double>(xs: 22, sm: 24, md: 26, lg: 28), fontWeight: FontWeight.w700, color: tc.text, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(_hasProof ? 'Field Selfie Proof' : 'Off-site Client Meeting Proof', style: TextStyle(fontSize: 13, color: tc.muted)),
        ],
      );

      final approveBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.done_all_rounded,
        label: _isDemo ? 'Approve (Demo)' : 'Approve',
        color: _isDemo ? tc.border : tc.orange,
        fg: _isDemo ? tc.muted : Colors.white,
        onTap: _isDemo ? _demoBlock : (_processingAction ? () {} : _approveLog),
      );

      final flagBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.flag_outlined,
        label: _isDemo ? 'Flag (Demo)' : (_hasProof ? 'Reject' : 'Flag'),
        color: _isDemo ? tc.border : tc.red.withValues(alpha: 0.85),
        fg: _isDemo ? tc.muted : Colors.white,
        outlined: true,
        onTap: _isDemo ? _demoBlock : (_processingAction ? () {} : _flagLog),
      );

      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
        children: [approveBtn, flagBtn],
      );

      if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), actions]);
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: title), const SizedBox(width: 12), Flexible(child: actions)]);
    });
  }

  Widget _headerButton({required IconData icon, required String label, required Color color, required Color fg, required VoidCallback onTap, bool outlined = false}) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color, width: 1.4), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
    );
  }

  Widget _buildLeftColumn(AdminColors tc, {required String name, required String role, required String department, required String manager, required String photoUrl, required String employeeId, required List<Map<String, dynamic>> timeline}) {
    return Column(
      children: [
        _buildEmployeeCard(tc, name: name, role: role, department: department, manager: manager, photoUrl: photoUrl, employeeId: employeeId),
        const SizedBox(height: 20),
        _buildTimelineCard(tc, timeline),
      ],
    );
  }

  Widget _buildEmployeeCard(AdminColors tc, {required String name, required String role, required String department, required String manager, required String photoUrl, required String employeeId}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: tc.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 320;
            final avatarAndName = Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: tc.orange.withValues(alpha: 0.15), border: Border.all(color: tc.card, width: 2)),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? Image.network(photoUrl, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _initialsAvatar(tc, name, size: 56))
                            : _initialsAvatar(tc, name, size: 56),
                      ),
                    ),
                    Positioned(bottom: 0, right: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: tc.green, shape: BoxShape.circle, border: Border.all(color: tc.card, width: 2)))),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tc.text), overflow: TextOverflow.ellipsis, maxLines: 1),
                      const SizedBox(height: 2),
                      Text(role, style: TextStyle(fontSize: 13, color: tc.muted), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            );

            final badge = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: tc.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(employeeId.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tc.orangeText, letterSpacing: 0.3)),
            );

            if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [avatarAndName, const SizedBox(height: 12), badge]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: avatarAndName), const SizedBox(width: 8), badge]);
          }),
          const SizedBox(height: 20),
          Divider(color: tc.border, height: 1),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 280;
            if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_metaColumn(tc, label: 'DEPARTMENT', value: department), const SizedBox(height: 12), _metaColumn(tc, label: 'MANAGER', value: manager)]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _metaColumn(tc, label: 'DEPARTMENT', value: department)), const SizedBox(width: 16), Expanded(child: _metaColumn(tc, label: 'MANAGER', value: manager))]);
          }),
        ],
      ),
    );
  }

  Widget _initialsAvatar(AdminColors tc, String name, {double size = 56}) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size, height: size, alignment: Alignment.center, color: tc.orange.withValues(alpha: 0.2),
      child: Text(initial, style: TextStyle(color: tc.orangeText, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
  }

  Widget _metaColumn(AdminColors tc, {required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: tc.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tc.text), overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildTimelineCard(AdminColors tc, List<Map<String, dynamic>> entries) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: tc.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Time-In Events', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tc.text)),
              Text('This Week', style: TextStyle(fontSize: 12, color: tc.muted)),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(entries.length, (i) => _buildTimelineItem(tc, entries[i], isFirst: i == 0, isLast: i == entries.length - 1)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(AdminColors tc, Map<String, dynamic> entry, {required bool isFirst, required bool isLast}) {
    final ts = _toDateTime(entry['timestamp'] ?? entry['date'] ?? entry['createdAt'] ?? entry['clockInTime']);
    final dateLabel = _fmtTimelineDate(ts);
    final type = _s(entry['type'], 'LOGIN').toString().toUpperCase();
    final isLogin = type.contains('IN') || type.contains('LOGIN');
    final verifiedVia = _s(entry['verificationMethod'] ?? entry['client'], 'Verified');

    final statusRaw = _s(entry['status'] ?? entry['verificationStatus'], '').toLowerCase();
    final isLate = statusRaw == 'late' || (ts != null && (ts.hour > 9 || (ts.hour == 9 && ts.minute > 15)));

    final statusBg = isLate ? tc.pillWarnBg : tc.pillGreenBg;
    final statusTx = isLate ? tc.pillWarnTx : tc.pillGreenTx;
    final statusLabel = isLate ? 'Late' : (isLogin ? 'On Time' : 'Clocked Out');

    final rawDevice = _s(entry['deviceModel'] ?? entry['deviceName'] ?? entry['device'] ?? '', '');
    final deviceFromEntry = _isSystemAction(rawDevice) ? '' : rawDevice;
    final subInfo = deviceFromEntry.isNotEmpty ? deviceFromEntry : _s(entry['locationName'] ?? entry['keyfobSerial'] ?? '', '');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(width: isFirst ? 20 : 14, height: isFirst ? 20 : 14, margin: EdgeInsets.only(top: isFirst ? 4 : 7, left: isFirst ? 2 : 5, right: isFirst ? 2 : 5), decoration: BoxDecoration(color: isFirst ? tc.orange : tc.blue.withValues(alpha: 0.4), shape: BoxShape.circle, border: Border.all(color: tc.card, width: 2))),
                if (!isLast) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: tc.border)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: isFirst ? tc.orange.withValues(alpha: 0.06) : tc.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: isFirst ? tc.orange.withValues(alpha: 0.2) : tc.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(dateLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tc.text))),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(4)), child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusTx))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: tc.muted),
                        children: [const TextSpan(text: 'Verification: '), TextSpan(text: verifiedVia, style: TextStyle(fontWeight: FontWeight.w700, color: tc.text))],
                      ),
                    ),
                    if (subInfo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [Icon(Icons.phone_iphone_rounded, size: 12, color: tc.muted), const SizedBox(width: 4), Expanded(child: Text(subInfo, style: TextStyle(fontSize: 11, color: tc.muted), overflow: TextOverflow.ellipsis))]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(BuildContext context, AdminColors tc, {required String client, required String deviceInfo, required String deviceStatus, required String registeredDevice, required String actualDevice, required String verificationNote, required String dateStr}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: tc.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 12))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: tc.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.fact_check_outlined, size: 20, color: tc.orange)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Verification Detail', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tc.text)),
                          const SizedBox(height: 2),
                          Text(verificationNote, style: TextStyle(fontSize: 13, color: tc.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _flagLog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: tc.red.withValues(alpha: 0.3))),
                  child: Icon(Icons.flag_outlined, size: 18, color: tc.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
                    if (_hasProof) ...[
            _buildFieldProofCard(tc),
            const SizedBox(height: 20),
          ] else if (_debugMessages.any((m) => m.toLowerCase().contains('proof'))) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tc.pillWarnBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _debugMessages
                    .where((m) => m.toLowerCase().contains('proof'))
                    .join('\n'),
                style: TextStyle(fontSize: 11, color: tc.pillWarnTx),
              ),
            ),
            const SizedBox(height: 20),
          ],
          _buildMapPreview(tc, dateStr: dateStr),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 400;
            final clientBox = _subDetailBox(tc, icon: Icons.work_outline_rounded, label: 'CLIENT', value: client);
            final deviceBox = _buildDeviceInfoBox(tc, deviceStatus: deviceStatus, displayValue: deviceInfo, registeredDevice: registeredDevice, actualDevice: actualDevice);

            if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [clientBox, const SizedBox(height: 12), deviceBox]);
            return Row(children: [Expanded(child: clientBox), const SizedBox(width: 12), Expanded(child: deviceBox)]);
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FIELD PROOF CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildFieldProofCard(AdminColors tc) {
    final d = _proofData!;
    final status = _proofStatus;

    Color bg, fg;
    String label;
    if (status == 'approved') {
      bg = tc.pillGreenBg; fg = tc.pillGreenTx; label = 'APPROVED';
    } else if (status == 'rejected') {
      bg = tc.pillErrBg; fg = tc.pillErrTx; label = 'REJECTED';
    } else if (status == 'auto') {
      bg = tc.pillGreenBg; fg = tc.pillGreenTx; label = 'AUTO-CAPTURED';
    } else {
      bg = tc.pillWarnBg; fg = tc.pillWarnTx; label = 'PENDING HR REVIEW';
    }

    final capturedAt = _toDateTime(d['capturedAt']);
    final accuracy = (d['accuracyMeters'] as num?)?.toDouble();
    final nearest = _s(d['nearestSiteName'], 'None');
    final type = _s(d['attendanceType'], '—').toUpperCase();
    final coordsText = _proofCoords != null
        ? '${_proofCoords!.latitude.toStringAsFixed(6)}, ${_proofCoords!.longitude.toStringAsFixed(6)}'
        : 'Not recorded';

    final photo = Container(
      width: 140,
      height: 180,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.border),
      ),
      child: _proofBytes != null
          ? InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.black,
                  child: InteractiveViewer(child: Image.memory(_proofBytes!, fit: BoxFit.contain)),
                ),
              ),
              child: Image.memory(_proofBytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: tc.muted)),
            )
          : Center(child: Icon(Icons.no_photography_outlined, color: tc.muted, size: 32)),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: fg.withValues(alpha: 0.3))),
          child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.5)),
        ),
        const SizedBox(height: 10),
        _proofRow(tc, Icons.swap_vert_rounded, 'Type', type),
        _proofRow(tc, Icons.schedule_rounded, 'Server time', _fmtFullDate(capturedAt)),
        _proofRow(tc, Icons.place_outlined, 'Coordinates', coordsText),
        _proofRow(tc, Icons.gps_fixed_rounded, 'GPS accuracy', accuracy != null ? '±${accuracy.toStringAsFixed(0)} m' : 'Not recorded'),
        _proofRow(tc, Icons.business_outlined, 'Nearest site', nearest),
        if (status == 'rejected' && _s(d['reviewReason'], '').isNotEmpty)
          _proofRow(tc, Icons.info_outline_rounded, 'Reason', _s(d['reviewReason'])),
        if (_s(d['reviewedBy'], '').isNotEmpty)
          _proofRow(tc, Icons.person_outline_rounded, 'Reviewed by', _s(d['reviewedBy'])),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.camera_front_rounded, size: 16, color: tc.orange),
            const SizedBox(width: 8),
                    Text(_isClockInPhoto ? 'CLOCK-IN PHOTO' : 'FIELD SELFIE PROOF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tc.orangeText, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 4),
          Text(
            _isClockInPhoto
                ? 'Photo captured automatically after face verification at clock-in.'
                : 'Submitted because the employee was outside every assigned client site. Attendance stays pending until HR approves.',
            style: TextStyle(fontSize: 11, color: tc.textMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (_, c) {
            if (c.maxWidth < 420) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [photo, const SizedBox(height: 12), info]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [photo, const SizedBox(width: 16), Expanded(child: info)]);
          }),
        ],
      ),
    );
  }

  Widget _proofRow(AdminColors tc, IconData icon, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: tc.muted),
          const SizedBox(width: 6),
          SizedBox(width: 84, child: Text(k, style: TextStyle(fontSize: 11, color: tc.muted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 12, color: tc.text, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoBox(AdminColors tc, {required String deviceStatus, required String displayValue, required String registeredDevice, required String actualDevice}) {
    final bool isRegistered = deviceStatus == 'registered';
    final bool isUnregistered = deviceStatus == 'unregistered';
    final bool isLegacy = deviceStatus == 'legacy';

    Color boxBg, boxBorder, iconColor, labelColor, valueColor;
    IconData icon;
    Color? badgeBg, badgeTextColor;
    String? badgeText;

    if (isRegistered) {
      boxBg = const Color(0xFFDCFCE7); boxBorder = const Color(0xFF22C55E); iconColor = const Color(0xFF166534); labelColor = const Color(0xFF166534); icon = Icons.verified_user_rounded; valueColor = tc.text; badgeBg = const Color(0xFF22C55E); badgeTextColor = Colors.white; badgeText = 'REGISTERED';
    } else if (isUnregistered) {
      boxBg = const Color(0xFFFEE2E2); boxBorder = const Color(0xFFEF4444); iconColor = const Color(0xFF991B1B); labelColor = const Color(0xFF991B1B); icon = Icons.gpp_maybe_rounded; valueColor = const Color(0xFF991B1B); badgeBg = const Color(0xFFEF4444); badgeTextColor = Colors.white; badgeText = 'UNREGISTERED';
    } else if (isLegacy) {
      boxBg = const Color(0xFFFEF3C7); boxBorder = const Color(0xFFF59E0B); iconColor = const Color(0xFF92400E); labelColor = const Color(0xFF92400E); icon = Icons.system_update_alt_rounded; valueColor = const Color(0xFF92400E); badgeBg = const Color(0xFFF59E0B); badgeTextColor = Colors.white; badgeText = 'NEEDS UPDATE';
    } else {
      boxBg = tc.surface; boxBorder = tc.border; iconColor = tc.muted; labelColor = tc.muted; icon = Icons.phone_iphone_rounded; valueColor = tc.text;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: boxBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: boxBorder, width: isRegistered || isUnregistered || isLegacy ? 1.5 : 1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 6),
              Text('DEVICE INFO', style: TextStyle(fontSize: 10, color: labelColor, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              if (badgeText != null) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(4)), child: Text(badgeText, style: TextStyle(fontSize: 7, color: badgeTextColor, fontWeight: FontWeight.w800, letterSpacing: 0.5))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(displayValue, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor), overflow: TextOverflow.ellipsis, maxLines: 2),
          if (isUnregistered && registeredDevice.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFF991B1B)), const SizedBox(width: 4), Expanded(child: Text('Registered: $registeredDevice', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF991B1B)), overflow: TextOverflow.ellipsis))]),
                  const SizedBox(height: 3),
                  const Text('A different device was used than the registered one', style: TextStyle(fontSize: 10, color: Color(0xFF991B1B), fontStyle: FontStyle.italic, height: 1.3)),
                ],
              ),
            ),
          ],
          if (isRegistered && actualDevice.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF166534)), const SizedBox(width: 4), Expanded(child: Text('Verified — matches registered device', style: const TextStyle(fontSize: 10, color: Color(0xFF166534), fontStyle: FontStyle.italic), overflow: TextOverflow.ellipsis))]),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MAP PREVIEW (FIXED SHADER ISSUE)
  // ══════════════════════════════════════════════════════════════
  Widget _buildMapPreview(AdminColors tc, {required String dateStr}) {
    final points = <ll.LatLng>[];
    if (_clockInCoords != null) points.add(_clockInCoords!);
    if (_clockOutCoords != null) points.add(_clockOutCoords!);
    if (_proofCoords != null) points.add(_proofCoords!);

    final hasGps = points.isNotEmpty;

    // DEFAULT OFFICE LOCATION KUNG WALANG GPS
    final defaultCoords = const ll.LatLng(14.5995, 120.9842);
    final displayCenter = hasGps ? points.first : defaultCoords;
    final initialZoom = points.length > 1 ? 13.0 : 16.0;

    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final mapHeight = r.responsive<double>(xs: 280, sm: 320, md: 360, lg: 360);

      return Container(
        height: mapHeight,
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tc.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (hasGps)
                RepaintBoundary(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: displayCenter,
                      initialZoom: initialZoom,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.hris.biometrics'),

                      MarkerLayer(
                        markers: [
                          if (_clockInCoords != null)
                            Marker(
                              point: _clockInCoords!,
                              width: 40, height: 40,
                              child: Container(
                                decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          if (_clockOutCoords != null)
                            Marker(
                              point: _clockOutCoords!,
                              width: 40, height: 40,
                              child: Container(
                                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          if (_proofCoords != null)
                            Marker(
                              point: _proofCoords!,
                              width: 40, height: 40,
                              child: Container(
                                decoration: BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (hasGps)
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
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (!_safe) return;
                                try {
                                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 0.5);
                                } catch (_) {}
                              },
                              child: SizedBox(
                                width: 32, height: 32,
                                child: Icon(Icons.add, size: 16, color: tc.text),
                              ),
                            ),
                            Container(height: 1, width: 32, color: tc.border),
                            InkWell(
                              onTap: () {
                                if (!_safe) return;
                                try {
                                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 0.5);
                                } catch (_) {}
                              },
                              child: SizedBox(
                                width: 32, height: 32,
                                child: Icon(Icons.remove, size: 16, color: tc.text),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          if (!_safe || !hasGps) return;
                          try {
                            _mapController.move(displayCenter, initialZoom);
                          } catch (_) {}
                        },
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: tc.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tc.border),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: Icon(Icons.my_location, size: 14, color: tc.text),
                        ),
                      ),
                    ],
                  ),
                ),

              if (!hasGps)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF1E1E1E),
                    padding: const EdgeInsets.all(24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 24),
                              const SizedBox(width: 8),
                              const Text('No GPS data recorded', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Dahil ang logs na ito ay gawa sa "Manual Entry" o walang nakuhang GPS noong nag-clock in/out, hindi ito makapag-render ng mapa.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white24),
                          const SizedBox(height: 8),
                          const Text('DEBUG LOGS:', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          const SizedBox(height: 8),
                          ..._debugMessages.map((msg) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $msg', style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
                          )),
                        ],
                      ),
                    ),
                  ),
                ),

              if (hasGps)
                Positioned(
                  left: 16, right: 16, bottom: 16,
                  child: LayoutBuilder(builder: (_, overlayC) {
                    final info = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Icon(Icons.calendar_today_rounded, size: 12, color: tc.orange), const SizedBox(width: 6), Flexible(child: Text(dateStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tc.text), overflow: TextOverflow.ellipsis))]),
                        const SizedBox(height: 6),

                        if (_clockInTime != null || _clockInCoords != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.login_rounded, size: 12, color: Colors.green),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'IN: ${_clockInTime != null ? DateFormat('hh:mm a').format(_clockInTime!) : 'Time N/A'}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tc.text),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (_clockOutTime != null || _clockOutCoords != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.logout_rounded, size: 12, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'OUT: ${_clockOutTime != null ? DateFormat('hh:mm a').format(_clockOutTime!) : 'Time N/A'}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tc.text),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_proofCoords != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.deepOrange),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Selfie proof location',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    );

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: tc.card.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(10), border: Border.all(color: tc.border), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                      child: Row(children: [Expanded(child: info), const SizedBox(width: 12), _buildGpsBadge(tc, true)]),
                    );
                  }),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildGpsBadge(AdminColors tc, bool hasGps) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: hasGps ? tc.pillGreenBg : tc.pillWarnBg, borderRadius: BorderRadius.circular(20), border: Border.all(color: (hasGps ? tc.pillGreenTx : tc.pillWarnTx).withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasGps ? Icons.verified_rounded : Icons.warning_amber_rounded, size: 12, color: hasGps ? tc.pillGreenTx : tc.pillWarnTx),
          const SizedBox(width: 4),
          Text(hasGps ? 'Location\nMatched' : 'No GPS\nData', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: hasGps ? tc.pillGreenTx : tc.pillWarnTx, height: 1.1)),
        ],
      ),
    );
  }

  Widget _subDetailBox(AdminColors tc, {required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: tc.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: tc.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 12, color: tc.muted), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 10, color: tc.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5))]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tc.text), overflow: TextOverflow.ellipsis, maxLines: 2),
        ],
      ),
    );
  }
}