// lib/screens/admin_attendance_verification_page.dart
// v1.2: 🎭 Demo Mode Support (Skip Firebase Fetch & Block Actions)
//       ➕ Manual Clock Out — for employees who forgot to clock out
//       ➕ Modify Log — to correct or add clock-out time on existing logs
//       🔒 Both actions require admin reason + write full audit trail
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
  // ══════════════════════════════════════════════════════════════
  // STATE
  // ══════════════════════════════════════════════════════════════
  Map<String, dynamic>? _employeeData;
  Map<String, dynamic>? _locationData;
  String? _deviceInfoOverride;
  String _deviceStatus = 'none';
  String _registeredDeviceValue = '';
  String _actualDeviceValue = '';
  String? _clientInfoOverride;
  bool _loading = true;
  bool _processingAction = false;

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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Action disabled in Demo Mode.'),
        backgroundColor: tc.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 🔒 Admin identity for audit trail
  String get _adminIdentifier {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        return u.email ?? u.uid;
      }
    } catch (_) {}
    return 'Admin';
  }

  @override
  void initState() {
    super.initState();
    _fetchRelatedData();
  }

  // ══════════════════════════════════════════════════════════════
  // EXTRACT LATLNG
  // ══════════════════════════════════════════════════════════════
  ll.LatLng? _extractLatLng(Map<String, dynamic> data) {
    final geo = data['location'] ??
        data['geopoint'] ??
        data['geo'] ??
        data['coordinates'];
    if (geo is GeoPoint) {
      return ll.LatLng(geo.latitude, geo.longitude);
    }

    final lat = data['latitude'] ??
        data['lat'] ??
        data['gps_lat'] ??
        data['gpsLatitude'] ??
        data['gps_latitude'];
    final lng = data['longitude'] ??
        data['lng'] ??
        data['lon'] ??
        data['gps_lng'] ??
        data['gpsLongitude'] ??
        data['gps_longitude'];

    if (lat is num && lng is num) {
      if (lat.abs() <= 90 && lng.abs() <= 180) {
        return ll.LatLng(lat.toDouble(), lng.toDouble());
      }
    }

    if (lat is String && lng is String) {
      final latD = double.tryParse(lat);
      final lngD = double.tryParse(lng);
      if (latD != null && lngD != null) {
        return ll.LatLng(latD, lngD);
      }
    }

    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // ⭐ DEVICE MATCH HELPER
  // ══════════════════════════════════════════════════════════════
  bool _fuzzyDeviceMatch(String registered, String actual) {
    final regLower = registered.toLowerCase().trim();
    final actLower = actual.toLowerCase().trim();

    if (regLower.isEmpty || actLower.isEmpty) return false;
    if (regLower == actLower) return true;

    String clean(String s) {
      return s
          .replaceAll(RegExp(r'\(web\)', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    final regClean = clean(regLower);
    final actClean = clean(actLower);

    if (regClean.isEmpty || actClean.isEmpty) return false;
    if (regClean == actClean) return true;

    const genericTerms = {
      'mobile app',
      'web browser',
      'android app',
      'ios app',
      'windows app',
      'macos app',
      'linux app',
      'mobile',
      'web',
      'android',
      'ios',
      'unknown device',
      'not recorded',
      '—',
      'null',
    };

    final regIsGeneric = genericTerms.contains(regClean);
    final actIsGeneric = genericTerms.contains(actClean);

    if (regIsGeneric != actIsGeneric) return false;
    if (regIsGeneric && actIsGeneric) {
      return regClean == actClean;
    }

    final regTokens = regClean
        .split(RegExp(r'[\s\-_\,\.]+'))
        .where((t) => t.length >= 2)
        .toSet();
    final actTokens = actClean
        .split(RegExp(r'[\s\-_\,\.]+'))
        .where((t) => t.length >= 2)
        .toSet();

    if (regTokens.isEmpty || actTokens.isEmpty) return false;

    final shorter =
    regTokens.length <= actTokens.length ? regTokens : actTokens;
    final longer =
    regTokens.length <= actTokens.length ? actTokens : regTokens;

    return shorter.every((t) => longer.contains(t));
  }

  bool _isLegacyDeviceValue(String value) {
    final v = value.toLowerCase().trim();
    return v == 'mobile app' ||
        v == 'android app' ||
        v == 'ios app' ||
        v == 'windows app' ||
        v == 'macos app' ||
        v == 'linux app';
  }

  Map<String, dynamic> _extractDeviceInfoWithSource(
      Map<String, dynamic> log) {
    String registeredDevice = '';
    if (_employeeData != null) {
      final candidates = [
        _employeeData!['registeredDevice'],
        _employeeData!['deviceModel'],
        _employeeData!['deviceName'],
        _employeeData!['device'],
      ];
      for (final c in candidates) {
        final v = (c ?? '').toString().trim();
        if (v.isNotEmpty &&
            v != '—' &&
            v.toLowerCase() != 'null' &&
            v.toLowerCase() != 'not recorded') {
          registeredDevice = v;
          break;
        }
      }
    }

    String actualDevice = '';

    const specificKeys = [
      'deviceModel',
      'deviceInfo',
      'clientDevice',
      'phoneModel',
      'deviceName',
    ];
    for (final key in specificKeys) {
      final v = (log[key] ?? '').toString().trim();
      if (v.isNotEmpty &&
          v != '—' &&
          v.toLowerCase() != 'null' &&
          v.toLowerCase() != 'mobile app' &&
          v.toLowerCase() != 'web browser' &&
          !_isLegacyDeviceValue(v)) {
        actualDevice = v;
        break;
      }
    }

    if (actualDevice.isEmpty) {
      final v = (log['device'] ?? '').toString().trim();
      if (v.isNotEmpty && v != '—' && v.toLowerCase() != 'null') {
        actualDevice = v;
      }
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

    debugPrint('📱 [Device] registered="$registeredDevice" | '
        'actual="$actualDevice"');

    if (registeredDevice.isNotEmpty) {
      if (_isLegacyDeviceValue(registeredDevice)) {
        if (actualDevice.isNotEmpty && !_isLegacyDeviceValue(actualDevice)) {
          return {
            'displayValue': actualDevice,
            'status': 'legacy',
            'registeredDevice': registeredDevice,
            'actualDevice': actualDevice,
          };
        }
        return {
          'displayValue': registeredDevice,
          'status': 'registered',
          'registeredDevice': registeredDevice,
          'actualDevice':
          actualDevice.isNotEmpty ? actualDevice : registeredDevice,
        };
      }

      if (actualDevice.isEmpty) {
        return {
          'displayValue': registeredDevice,
          'status': 'registered',
          'registeredDevice': registeredDevice,
          'actualDevice': '',
        };
      }

      final matches = _fuzzyDeviceMatch(registeredDevice, actualDevice);

      if (matches) {
        return {
          'displayValue': registeredDevice,
          'status': 'registered',
          'registeredDevice': registeredDevice,
          'actualDevice': actualDevice,
        };
      } else {
        return {
          'displayValue': actualDevice,
          'status': 'unregistered',
          'registeredDevice': registeredDevice,
          'actualDevice': actualDevice,
        };
      }
    }

    if (actualDevice.isNotEmpty) {
      return {
        'displayValue': actualDevice,
        'status': 'none',
        'registeredDevice': '',
        'actualDevice': actualDevice,
      };
    }

    return {
      'displayValue': 'Not recorded',
      'status': 'none',
      'registeredDevice': '',
      'actualDevice': '',
    };
  }

  // ══════════════════════════════════════════════════════════════
  // EXTRACT CLIENT INFO
  // ══════════════════════════════════════════════════════════════
  String? _extractClientInfo(Map<String, dynamic> data) {
    const keys = [
      'client',
      'clientName',
      'clientInfo',
      'purpose',
      'reason',
      'verificationMethod',
      'verificationNote',
      'note',
    ];
    for (final key in keys) {
      final v = data[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // FETCH EMPLOYEE + LOCATION + DEVICE
  // ══════════════════════════════════════════════════════════════
  Future<void> _fetchRelatedData() async {
    // 🎭 DEMO MODE — skip Firebase completely
    if (_isDemo) {
      final log = widget.logData;
      _clientInfoOverride = _extractClientInfo(log);

      _employeeData = {
        'name': log['employee_name'] ?? log['name'] ?? 'Demo Employee',
        'employeeId': log['employee_id'] ?? log['employeeId'] ?? 'DEMO-001',
        'department': log['department'] ?? 'Operations',
        'role': log['position'] ?? 'Staff',
        'photoUrl': '',
        'deviceName': log['registeredDevice'] ?? 'iPhone 14 Pro',
      };

      _deviceInfoOverride =
          log['registeredDevice']?.toString() ?? 'iPhone 14 Pro';
      _deviceStatus = 'registered';
      _registeredDeviceValue = _deviceInfoOverride!;
      _actualDeviceValue = _deviceInfoOverride!;

      final logCoords = _extractLatLng(log);
      if (logCoords != null) {
        _locationData = {
          'latitude': logCoords.latitude,
          'longitude': logCoords.longitude,
          'locationName': log['locationName'] ?? 'Makati Office',
          'timestamp': log['timestamp'],
        };
      }

      if (mounted) setState(() => _loading = false);
      return;
    }

    // ─── NORMAL MODE: Fetch from Firebase ───
    final log = widget.logData;
    final empId = (log['employee_id'] ?? log['employeeId'] ?? '').toString();
    final empAuthUid = (log['authUid'] ?? log['auth_uid'] ?? '').toString();
    final empName = (log['employee_name'] ?? log['name'] ?? '').toString();
    final empEmail = (log['email'] ?? '').toString();
    final logTs = _toDateTime(log['timestamp']);

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🔍 [VERIFY] Fetch: name="$empName" id="$empId" email="$empEmail"');

    _clientInfoOverride = _extractClientInfo(log);

    final logCoords = _extractLatLng(log);
    if (logCoords != null) {
      _locationData = {
        'latitude': logCoords.latitude,
        'longitude': logCoords.longitude,
        'locationName': log['locationName'] ?? log['location_name'],
        'timestamp': log['timestamp'],
      };
    }

    // Fetch employee
    try {
      Map<String, dynamic>? found;

      if (empAuthUid.isNotEmpty) {
        final s = await FirebaseFirestore.instance
            .collection('employees')
            .where('authUid', isEqualTo: empAuthUid)
            .limit(1)
            .get();
        if (s.docs.isNotEmpty) {
          found = {...s.docs.first.data(), 'id': s.docs.first.id};
        }
      }

      if (found == null && empId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get();
        if (doc.exists && doc.data() != null) {
          found = {...doc.data()!, 'id': doc.id};
        }
      }

      if (found == null && empName.isNotEmpty) {
        final s = await FirebaseFirestore.instance
            .collection('employees')
            .where('name', isEqualTo: empName)
            .limit(1)
            .get();
        if (s.docs.isNotEmpty) {
          found = {...s.docs.first.data(), 'id': s.docs.first.id};
        }
      }

      if (found == null && empId.isNotEmpty) {
        final s = await FirebaseFirestore.instance
            .collection('employees')
            .where('nfcTagId', isEqualTo: empId)
            .limit(1)
            .get();
        if (s.docs.isNotEmpty) {
          found = {...s.docs.first.data(), 'id': s.docs.first.id};
        }
      }

      if (found == null && empEmail.isNotEmpty) {
        final s = await FirebaseFirestore.instance
            .collection('employees')
            .where('email', isEqualTo: empEmail)
            .limit(1)
            .get();
        if (s.docs.isNotEmpty) {
          found = {...s.docs.first.data(), 'id': s.docs.first.id};
        }
      }

      _employeeData = found;
    } catch (e) {
      debugPrint('❌ [VERIFY] Emp error: $e');
    }

    // Extract device info
    final deviceResult = _extractDeviceInfoWithSource(log);
    _deviceInfoOverride = deviceResult['displayValue'] as String;
    _deviceStatus = deviceResult['status'] as String;
    _registeredDeviceValue =
        deviceResult['registeredDevice'] as String? ?? '';
    _actualDeviceValue = deviceResult['actualDevice'] as String? ?? '';

    final Set<String> empIds = {};
    empIds.add(empId);
    if (_employeeData != null) {
      empIds.add((_employeeData!['id'] ?? '').toString());
      empIds.add((_employeeData!['employeeId'] ?? '').toString());
      empIds.add((_employeeData!['nfcTagId'] ?? '').toString());
      empIds.add((_employeeData!['authUid'] ?? '').toString());
    }
    empIds.removeWhere((e) => e.isEmpty);

    final Set<String> empEmails = {};
    empEmails.add(empEmail);
    if (_employeeData != null) {
      empEmails.add((_employeeData!['email'] ?? '').toString());
    }
    empEmails.removeWhere((e) => e.isEmpty);

    // Fetch GPS from user locations
    if (_locationData == null) {
      const locationCollections = [
        'user locations',
        'user_locations',
        'locations',
        'attendance_locations',
        'gps_logs',
      ];
      const employeeFieldNames = [
        'employeeId',
        'employee_id',
        'empId',
        'uid',
        'authUid',
      ];

      for (final coll in locationCollections) {
        if (_locationData != null) break;

        for (final field in employeeFieldNames) {
          if (_locationData != null) break;

          for (final id in empIds) {
            if (_locationData != null) break;
            try {
              final snap = await FirebaseFirestore.instance
                  .collection(coll)
                  .where(field, isEqualTo: id)
                  .limit(50)
                  .get();

              if (snap.docs.isEmpty) continue;

              final docs = snap.docs.toList();
              docs.sort((a, b) {
                final ta = _toDateTime(a.data()['timestamp']);
                final tb = _toDateTime(b.data()['timestamp']);
                if (ta == null && tb == null) return 0;
                if (ta == null) return 1;
                if (tb == null) return -1;
                if (logTs == null) return tb.compareTo(ta);
                final da = ta.difference(logTs).inSeconds.abs();
                final db = tb.difference(logTs).inSeconds.abs();
                return da.compareTo(db);
              });

              for (final d in docs) {
                final data = d.data();
                final coords = _extractLatLng(data);
                if (coords == null) continue;

                final ts = _toDateTime(data['timestamp']);
                if (logTs != null && ts != null) {
                  final diff = ts.difference(logTs).inSeconds.abs();
                  if (diff > 4 * 60 * 60) continue;
                }

                _locationData = {...data, 'id': d.id};
                break;
              }
            } catch (e) {
              debugPrint('   ❌ $coll/$field: $e');
            }
          }
        }

        if (_locationData == null && empEmails.isNotEmpty) {
          for (final email in empEmails) {
            try {
              final snap = await FirebaseFirestore.instance
                  .collection(coll)
                  .where('email', isEqualTo: email)
                  .limit(50)
                  .get();
              for (final d in snap.docs) {
                final coords = _extractLatLng(d.data());
                if (coords != null) {
                  _locationData = {...d.data(), 'id': d.id};
                  break;
                }
              }
            } catch (_) {}
            if (_locationData != null) break;
          }
        }
      }
    }

    if (_clientInfoOverride == null && _locationData != null) {
      _clientInfoOverride = _extractClientInfo(_locationData!);
    }

    if (mounted) setState(() => _loading = false);
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
    final emp = _employeeData;
    if (emp != null) {
      final actualId = _s(emp['employeeId'], '');
      if (actualId.isNotEmpty &&
          actualId != 'Not recorded' &&
          !actualId.contains(':')) {
        return actualId.toUpperCase();
      }
      final docId = _s(emp['id'], '');
      if (docId.isNotEmpty) {
        final short = docId.length > 6 ? docId.substring(0, 6) : docId;
        return 'EMP-${short.toUpperCase()}';
      }
    }
    final raw = widget.logId;
    if (raw.isEmpty) return 'EMP-0000';
    final short =
    raw.length > 6 ? raw.substring(0, 6).toUpperCase() : raw.toUpperCase();
    return 'EMP-$short';
  }

  String _getDepartment() {
    if (_employeeData != null) {
      final d = _s(_employeeData!['department'], '');
      if (d.isNotEmpty && d != 'Not recorded') return d;
    }
    final fromLog = _s(widget.logData['department'], '');
    if (fromLog.isNotEmpty && fromLog != 'Not recorded') return fromLog;
    return 'Not recorded';
  }

  String _getManager() {
    if (_employeeData != null) {
      final m = _s(
          _employeeData!['manager'] ??
              _employeeData!['managerName'] ??
              _employeeData!['supervisor'],
          '');
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

  ll.LatLng? _getCoords() {
    final fromLog = _extractLatLng(widget.logData);
    if (fromLog != null) return fromLog;
    if (_locationData != null) {
      return _extractLatLng(_locationData!);
    }
    return null;
  }

  String _getCoordsStr() {
    final coords = _getCoords();
    if (coords == null) return 'Not recorded';
    final latStr = coords.latitude.toStringAsFixed(4);
    final lngStr = coords.longitude.toStringAsFixed(4);
    final latDir = coords.latitude >= 0 ? 'N' : 'S';
    final lngDir = coords.longitude >= 0 ? 'E' : 'W';
    return '$latStr° $latDir, $lngStr° $lngDir';
  }

  String _getLocationName() {
    if (_locationData != null) {
      final n = _s(
          _locationData!['locationName'] ??
              _locationData!['location'] ??
              _locationData!['name'],
          '');
      if (n.isNotEmpty && n != 'Not recorded') return n;
    }
    return _s(
        widget.logData['locationName'] ?? widget.logData['location'], '');
  }

  String _getDeviceInfo() {
    if (_deviceInfoOverride != null &&
        _deviceInfoOverride!.isNotEmpty &&
        _deviceInfoOverride != '—') {
      return _deviceInfoOverride!;
    }
    return 'Not recorded';
  }

  String _getClientInfo() {
    if (_clientInfoOverride != null && _clientInfoOverride!.isNotEmpty) {
      return _clientInfoOverride!;
    }
    return 'Not specified';
  }

  // ══════════════════════════════════════════════════════════════
  // 🆕 MANUAL CLOCK OUT — Admin creates OUT log for employee
  // ══════════════════════════════════════════════════════════════
  Future<void> _showManualClockOutDialog() async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (_processingAction) return;

    final log = widget.logData;
    final empDocId =
    (_employeeData?['id'] ?? log['employee_id'] ?? log['employeeId'] ?? '')
        .toString();
    final empName = (_employeeData?['name'] ??
        log['employee_name'] ??
        log['name'] ??
        'Employee')
        .toString();

    if (empDocId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot clock out: employee ID missing.'),
          backgroundColor: tc.red,
        ),
      );
      return;
    }

    // Default clock-out time = now
    DateTime clockOutAt = DateTime.now();
    final reasonCtrl = TextEditingController();
    bool submitting = false;
    String? errMsg;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !_processingAction,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: tc.card,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tc.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.logout_rounded, color: tc.red, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Manual Clock Out',
                    style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: tc.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border:
                      Border.all(color: tc.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Employee',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: tc.muted,
                              letterSpacing: 0.4),
                        ),
                        const SizedBox(height: 2),
                        Text(empName,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: tc.text)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This will create a new CLOCK OUT record for this '
                        'employee. Use this when the employee forgot to '
                        'clock out.',
                    style: TextStyle(fontSize: 12, color: tc.muted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Clock-out time',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: submitting
                        ? null
                        : () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(clockOutAt),
                      );
                      if (picked != null) {
                        setDlg(() {
                          clockOutAt = DateTime(
                            clockOutAt.year,
                            clockOutAt.month,
                            clockOutAt.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: tc.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tc.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 18, color: tc.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, yyyy • hh:mm a')
                                  .format(clockOutAt),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text),
                            ),
                          ),
                          Icon(Icons.edit_rounded,
                              size: 14, color: tc.muted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Reason (required)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    maxLength: 200,
                    enabled: !submitting,
                    onChanged: (_) {
                      if (errMsg != null) setDlg(() => errMsg = null);
                    },
                    style: TextStyle(color: tc.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Employee confirmed forgot to clock out',
                      hintStyle:
                      TextStyle(color: tc.muted, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!,
                        style: TextStyle(
                            color: tc.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: tc.muted)),
              ),
              ElevatedButton.icon(
                onPressed: submitting
                    ? null
                    : () async {
                  final reason = reasonCtrl.text.trim();
                  if (reason.length < 5) {
                    setDlg(() => errMsg =
                    'Please provide a clear reason (min 5 chars).');
                    return;
                  }
                  setDlg(() {
                    submitting = true;
                    errMsg = null;
                  });
                  final ok = await _performManualClockOut(
                    employeeDocId: empDocId,
                    employeeName: empName,
                    clockOutAt: clockOutAt,
                    reason: reason,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, ok);
                },
                icon: submitting
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(submitting ? 'Saving…' : 'Clock Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );

    reasonCtrl.dispose();

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Clock-out recorded successfully.'),
          backgroundColor: tc.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _performManualClockOut({
    required String employeeDocId,
    required String employeeName,
    required DateTime clockOutAt,
    required String reason,
  }) async {
    if (_isDemo) return false;
    if (_processingAction) return false;
    setState(() => _processingAction = true);
    try {
      final now = DateTime.now();
      final adminId = _adminIdentifier;
      final fs = FirebaseFirestore.instance;

      // ✅ IDAGDAG ITO: Kunin ang original employee_id (badge ID) mula sa logData
      final originalEmpId = (widget.logData['employee_id'] ??
          widget.logData['employeeId'] ??
          employeeDocId)
          .toString();

      // ✅ Dito na mag-write ang payload gamit ang originalEmpId
      final payload = <String, dynamic>{
        'employee_id': originalEmpId,      // For employee stream filter
        'employeeId': originalEmpId,       // For camelCase fallback
        'employeeDocId': employeeDocId,    // Keep for admin lookups
        'employee_name': employeeName,
        'employeeName': employeeName,
        'type': 'OUT',
        'action': 'Manual Clock Out (Admin)',
        'details': 'Admin manually clocked out employee',
        'description': 'Manual clock-out by $adminId',
        'remarks': 'manual_clock_out_by_admin',
        'date': DateFormat('yyyy-MM-dd').format(clockOutAt),
        'time': DateFormat('HH:mm:ss').format(clockOutAt),
        'timestamp': Timestamp.fromDate(clockOutAt),
        'status': 'approved',
        'payrollStatus': 'Pending',
        'source': 'admin_manual',
        'original_log_id': widget.logId,
        'modified_by_admin': adminId,
        'modification_reason': reason,
        'modified_at': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final ref = await fs.collection('attendance_logs').add(payload);

      // Audit trail
      try {
        await fs.collection('admin_audit_logs').add({
          'action': 'manual_clock_out',
          'admin': adminId,
          'employeeId': employeeDocId,
          'employeeName': employeeName,
          'newLogId': ref.id,
          'originalLogId': widget.logId,
          'clockOutAt': Timestamp.fromDate(clockOutAt),
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
          'platform': 'admin_panel',
        });
      } catch (e) {
        debugPrint('⚠️ Audit log failed: $e');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Manual clock out failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: tc.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _processingAction = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 🆕 MODIFY LOG — Admin edits existing log (add/fix clock-out)
  // ══════════════════════════════════════════════════════════════
  Future<void> _showModifyLogDialog() async {
    if (_isDemo) {
      _demoBlock();
      return;
    }
    if (_processingAction) return;

    final logTs = _toDateTime(widget.logData['timestamp']) ?? DateTime.now();
    final reasonCtrl = TextEditingController();

    DateTime modifiedTime = logTs;
    String modifiedType =
    (widget.logData['type'] ?? 'IN').toString().toUpperCase();
    if (modifiedType != 'IN' && modifiedType != 'OUT') {
      modifiedType = 'IN';
    }

    bool submitting = false;
    String? errMsg;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: tc.card,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.edit_note_rounded,
                      color: tc.orange, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Modify Attendance Log',
                    style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: tc.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: tc.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_rounded,
                            size: 14, color: tc.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Log ID: ${widget.logId}',
                            style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: tc.muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Type',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeChip(
                          label: 'CLOCK IN',
                          selected: modifiedType == 'IN',
                          color: tc.green,
                          onTap: submitting
                              ? null
                              : () => setDlg(() => modifiedType = 'IN'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildTypeChip(
                          label: 'CLOCK OUT',
                          selected: modifiedType == 'OUT',
                          color: tc.red,
                          onTap: submitting
                              ? null
                              : () => setDlg(() => modifiedType = 'OUT'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Timestamp',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: submitting
                        ? null
                        : () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: modifiedTime,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (date == null || !ctx.mounted) return;
                      final time = await showTimePicker(
                        context: ctx,
                        initialTime:
                        TimeOfDay.fromDateTime(modifiedTime),
                      );
                      if (time == null) return;
                      setDlg(() {
                        modifiedTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: tc.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tc.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded,
                              size: 18, color: tc.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DateFormat('MMM d, yyyy • hh:mm a')
                                  .format(modifiedTime),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: tc.text),
                            ),
                          ),
                          Icon(Icons.edit_rounded,
                              size: 14, color: tc.muted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Reason for modification (required)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tc.text),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    maxLength: 200,
                    enabled: !submitting,
                    onChanged: (_) {
                      if (errMsg != null) setDlg(() => errMsg = null);
                    },
                    style: TextStyle(color: tc.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Correct clock out time — system error',
                      hintStyle:
                      TextStyle(color: tc.muted, fontSize: 12),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (errMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errMsg!,
                        style: TextStyle(
                            color: tc.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: tc.muted)),
              ),
              ElevatedButton.icon(
                onPressed: submitting
                    ? null
                    : () async {
                  final reason = reasonCtrl.text.trim();
                  if (reason.length < 5) {
                    setDlg(() => errMsg =
                    'Please provide a clear reason (min 5 chars).');
                    return;
                  }
                  setDlg(() {
                    submitting = true;
                    errMsg = null;
                  });
                  final ok = await _performModifyLog(
                    newTimestamp: modifiedTime,
                    newType: modifiedType,
                    reason: reason,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, ok);
                },
                icon: submitting
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(submitting ? 'Saving…' : 'Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );

    reasonCtrl.dispose();

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ Log modified successfully.'),
          backgroundColor: tc.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Optionally reload data so UI reflects changes
      // _fetchRelatedData();
    }
  }

  Widget _buildTypeChip({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : tc.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : tc.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14,
              color: selected ? color : tc.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? color : tc.muted,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _performModifyLog({
    required DateTime newTimestamp,
    required String newType,
    required String reason,
  }) async {
    if (_isDemo) return false;
    if (_processingAction) return false;
    setState(() => _processingAction = true);
    try {
      final adminId = _adminIdentifier;
      final fs = FirebaseFirestore.instance;

      final beforeSnapshot = Map<String, dynamic>.from(widget.logData);

      final updates = <String, dynamic>{
        'timestamp': Timestamp.fromDate(newTimestamp),
        'date': DateFormat('yyyy-MM-dd').format(newTimestamp),
        'time': DateFormat('HH:mm:ss').format(newTimestamp),
        'type': newType,
        'modified_by_admin': adminId,
        'modification_reason': reason,
        'modified_at': FieldValue.serverTimestamp(),
        'previous_value': {
          'timestamp': beforeSnapshot['timestamp'],
          'type': beforeSnapshot['type'],
        },
      };

      await fs
          .collection('attendance_logs')
          .doc(widget.logId)
          .update(updates);

      // Audit trail
      try {
        await fs.collection('admin_audit_logs').add({
          'action': 'modify_attendance_log',
          'admin': adminId,
          'logId': widget.logId,
          'employeeId': widget.logData['employee_id'] ??
              widget.logData['employeeId'],
          'before': {
            'timestamp': beforeSnapshot['timestamp'],
            'type': beforeSnapshot['type'],
          },
          'after': {
            'timestamp': Timestamp.fromDate(newTimestamp),
            'type': newType,
          },
          'reason': reason,
          'timestamp': FieldValue.serverTimestamp(),
          'platform': 'admin_panel',
        });
      } catch (e) {
        debugPrint('⚠️ Audit log failed: $e');
      }

      return true;
    } catch (e) {
      debugPrint('❌ Modify log failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: tc.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _processingAction = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final name = _s(
      _employeeData?['name'] ??
          widget.logData['employee_name'] ??
          widget.logData['name'],
      'System User',
    );
    final role = _getRole();
    final department = _getDepartment();
    final manager = _getManager();
    final photoUrl = _getPhotoUrl();
    final client = _getClientInfo();
    final deviceInfo = _getDeviceInfo();
    final locationName = _getLocationName();
    final coordsStr = _getCoordsStr();
    final verificationNote = _s(
      widget.logData['verificationNote'],
      'Off-site Client Meeting Proof',
    );
    final employeeId = _formatEmployeeId();

    final ts = _toDateTime(widget.logData['timestamp']);
    final dateStr = _fmtFullDate(ts);

    final rawHistory = widget.logData['history'];
    final List<Map<String, dynamic>> historyList = rawHistory is List
        ? rawHistory.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
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
              // 🎭 DEMO BANNER
              if (_isDemo) ...[
                _buildDemoBanner(),
                const SizedBox(height: 16),
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
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: tc.orange),
                      ),
                      const SizedBox(width: 10),
                      Text('Fetching employee details...',
                          style: TextStyle(fontSize: 12, color: tc.muted)),
                    ],
                  ),
                ),
              LayoutBuilder(builder: (_, c) {
                final stack = !BsResponsive(c.maxWidth).up(BsSize.lg);

                if (stack) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLeftColumn(
                        tc,
                        name: name,
                        role: role,
                        department: department,
                        manager: manager,
                        photoUrl: photoUrl,
                        employeeId: employeeId,
                        timeline: timeline,
                      ),
                      const SizedBox(height: 20),
                      _buildVerificationCard(
                        context,
                        tc,
                        client: client,
                        deviceInfo: deviceInfo,
                        deviceStatus: _deviceStatus,
                        registeredDevice: _registeredDeviceValue,
                        actualDevice: _actualDeviceValue,
                        locationName: locationName,
                        coordsStr: coordsStr,
                        verificationNote: verificationNote,
                        dateStr: dateStr,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 420,
                      child: _buildLeftColumn(
                        tc,
                        name: name,
                        role: role,
                        department: department,
                        manager: manager,
                        photoUrl: photoUrl,
                        employeeId: employeeId,
                        timeline: timeline,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _buildVerificationCard(
                        context,
                        tc,
                        client: client,
                        deviceInfo: deviceInfo,
                        deviceStatus: _deviceStatus,
                        registeredDevice: _registeredDeviceValue,
                        actualDevice: _actualDeviceValue,
                        locationName: locationName,
                        coordsStr: coordsStr,
                        verificationNote: verificationNote,
                        dateStr: dateStr,
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
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
                  'Showing sample verification data. Approve, Clock Out, '
                      'Modify, and Flag actions are disabled.',
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

  // ══════════════════════════════════════════════════════════════
  // BREADCRUMB
  // ══════════════════════════════════════════════════════════════
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
            Text(
              'Back to Attendance Logs',
              style: TextStyle(
                color: tc.orange,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADER — v1.2 with Manual Clock Out + Modify Log
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeader(BuildContext context, AdminColors tc) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);

      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Verification',
            style: TextStyle(
              fontSize: r.responsive<double>(xs: 22, sm: 24, md: 26, lg: 28),
              fontWeight: FontWeight.w700,
              color: tc.text,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Off-site Client Meeting Proof',
            style: TextStyle(fontSize: 13, color: tc.muted),
          ),
        ],
      );

      // ── ACTION BUTTONS ──
      final approveBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.done_all_rounded,
        label: _isDemo ? 'Approve (Demo)' : 'Approve',
        color: _isDemo ? tc.border : tc.orange,
        fg: _isDemo ? tc.muted : Colors.white,
        onTap: _isDemo
            ? _demoBlock
            : () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Marked as approved.'),
              backgroundColor: tc.green,
            ),
          );
        },
      );

      // 🆕 MANUAL CLOCK OUT
      final clockOutBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.logout_rounded,
        label: _isDemo ? 'Clock Out (Demo)' : 'Manual Clock Out',
        color: _isDemo ? tc.border : tc.red,
        fg: _isDemo ? tc.muted : Colors.white,
        onTap: _isDemo ? _demoBlock : _showManualClockOutDialog,
      );

      // 🆕 MODIFY LOG
      final modifyBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.edit_note_rounded,
        label: _isDemo ? 'Modify (Demo)' : 'Modify Log',
        color: _isDemo ? tc.border : tc.blue,
        fg: _isDemo ? tc.muted : Colors.white,
        onTap: _isDemo ? _demoBlock : _showModifyLogDialog,
      );

      // Flag button (existing behaviour)
      final flagBtn = _headerButton(
        icon: _isDemo ? Icons.lock_outline_rounded : Icons.flag_outlined,
        label: _isDemo ? 'Flag (Demo)' : 'Flag',
        color: _isDemo ? tc.border : tc.red.withValues(alpha: 0.85),
        fg: _isDemo ? tc.muted : Colors.white,
        outlined: true,
        onTap: _isDemo
            ? _demoBlock
            : () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Flagged for review.'),
              backgroundColor: tc.red,
            ),
          );
        },
      );

      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
        children: [
          approveBtn,
          clockOutBtn,
          modifyBtn,
          flagBtn,
        ],
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 12),
            actions,
          ],
        );
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          Flexible(child: actions),
        ],
      );
    });
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color fg,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.4),
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style:
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: fg,
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // LEFT COLUMN
  // ══════════════════════════════════════════════════════════════
  Widget _buildLeftColumn(
      AdminColors tc, {
        required String name,
        required String role,
        required String department,
        required String manager,
        required String photoUrl,
        required String employeeId,
        required List<Map<String, dynamic>> timeline,
      }) {
    return Column(
      children: [
        _buildEmployeeCard(
          tc,
          name: name,
          role: role,
          department: department,
          manager: manager,
          photoUrl: photoUrl,
          employeeId: employeeId,
        ),
        const SizedBox(height: 20),
        _buildTimelineCard(tc, timeline),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildEmployeeCard(
      AdminColors tc, {
        required String name,
        required String role,
        required String department,
        required String manager,
        required String photoUrl,
        required String employeeId,
      }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tc.orange.withValues(alpha: 0.15),
                        border: Border.all(color: tc.card, width: 2),
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? Image.network(
                          photoUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _initialsAvatar(tc, name, size: 56),
                        )
                            : _initialsAvatar(tc, name, size: 56),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: tc.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: tc.card, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: tc.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        role,
                        style: TextStyle(fontSize: 13, color: tc.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );

            final badge = Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tc.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                employeeId.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: tc.orangeText,
                  letterSpacing: 0.3,
                ),
              ),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatarAndName,
                  const SizedBox(height: 12),
                  badge,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: avatarAndName),
                const SizedBox(width: 8),
                badge,
              ],
            );
          }),
          const SizedBox(height: 20),
          Divider(color: tc.border, height: 1),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 280;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _metaColumn(tc, label: 'DEPARTMENT', value: department),
                  const SizedBox(height: 12),
                  _metaColumn(tc, label: 'MANAGER', value: manager),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child:
                    _metaColumn(tc, label: 'DEPARTMENT', value: department)),
                const SizedBox(width: 16),
                Expanded(
                    child: _metaColumn(tc, label: 'MANAGER', value: manager)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _initialsAvatar(AdminColors tc, String name, {double size = 56}) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: tc.orange.withValues(alpha: 0.2),
      child: Text(
        initial,
        style: TextStyle(
          color: tc.orangeText,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  Widget _metaColumn(AdminColors tc,
      {required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: tc.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tc.text,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TIMELINE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildTimelineCard(
      AdminColors tc, List<Map<String, dynamic>> entries) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Time-In Events',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: tc.text)),
              Text('This Week',
                  style: TextStyle(fontSize: 12, color: tc.muted)),
            ],
          ),
          const SizedBox(height: 20),
          ...List.generate(entries.length, (i) {
            return _buildTimelineItem(tc, entries[i],
                isFirst: i == 0, isLast: i == entries.length - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(AdminColors tc, Map<String, dynamic> entry,
      {required bool isFirst, required bool isLast}) {
    final ts = _toDateTime(entry['timestamp']);
    final dateLabel = _fmtTimelineDate(ts);
    final type = _s(entry['type'], 'LOGIN').toString().toUpperCase();
    final isLogin = type.contains('IN') || type.contains('LOGIN');
    final verifiedVia =
    _s(entry['verificationMethod'] ?? entry['client'], 'Verified');

    final statusRaw =
    _s(entry['status'] ?? entry['verificationStatus'], '').toLowerCase();
    final isLate = statusRaw == 'late' ||
        (ts != null && (ts.hour > 9 || (ts.hour == 9 && ts.minute > 15)));

    final statusBg = isLate ? tc.pillWarnBg : tc.pillGreenBg;
    final statusTx = isLate ? tc.pillWarnTx : tc.pillGreenTx;
    final statusLabel =
    isLate ? 'Late' : (isLogin ? 'On Time' : 'Clocked Out');

    final deviceFromEntry = _s(
        entry['deviceModel'] ??
            entry['deviceName'] ??
            entry['device'] ??
            '',
        '');
    final subInfo = deviceFromEntry.isNotEmpty
        ? deviceFromEntry
        : _s(entry['locationName'] ?? entry['keyfobSerial'] ?? '', '');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: isFirst ? 20 : 14,
                  height: isFirst ? 20 : 14,
                  margin: EdgeInsets.only(
                    top: isFirst ? 4 : 7,
                    left: isFirst ? 2 : 5,
                    right: isFirst ? 2 : 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                    isFirst ? tc.orange : tc.blue.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                    border: Border.all(color: tc.card, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: tc.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isFirst
                      ? tc.orange.withValues(alpha: 0.06)
                      : tc.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isFirst
                        ? tc.orange.withValues(alpha: 0.2)
                        : tc.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(dateLabel,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: tc.text)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusTx)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: tc.muted),
                        children: [
                          const TextSpan(text: 'Verification: '),
                          TextSpan(
                            text: verifiedVia,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: tc.text),
                          ),
                        ],
                      ),
                    ),
                    if (subInfo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone_iphone_rounded,
                              size: 12, color: tc.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(subInfo,
                                style: TextStyle(
                                    fontSize: 11, color: tc.muted),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
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

  // ══════════════════════════════════════════════════════════════
  // VERIFICATION CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildVerificationCard(
      BuildContext context,
      AdminColors tc, {
        required String client,
        required String deviceInfo,
        required String deviceStatus,
        required String registeredDevice,
        required String actualDevice,
        required String locationName,
        required String coordsStr,
        required String verificationNote,
        required String dateStr,
      }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
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
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tc.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.fact_check_outlined,
                          size: 20, color: tc.orange),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Verification Detail',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: tc.text)),
                          const SizedBox(height: 2),
                          Text(verificationNote,
                              style:
                              TextStyle(fontSize: 13, color: tc.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _isDemo
                    ? _demoBlock
                    : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Flagged for review.'),
                      backgroundColor: tc.red,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: (_isDemo ? tc.border : tc.red)
                            .withValues(alpha: 0.3)),
                  ),
                  child: Icon(
                    _isDemo ? Icons.lock_outline_rounded : Icons.flag_outlined,
                    size: 18,
                    color: _isDemo ? tc.muted : tc.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildMapPreview(tc,
              dateStr: dateStr,
              coordsStr: coordsStr,
              locationName: locationName),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 400;
            final clientBox = _subDetailBox(tc,
                icon: Icons.work_outline_rounded,
                label: 'CLIENT',
                value: client);

            final deviceBox = _buildDeviceInfoBox(
              tc,
              deviceStatus: deviceStatus,
              displayValue: deviceInfo,
              registeredDevice: registeredDevice,
              actualDevice: actualDevice,
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  clientBox,
                  const SizedBox(height: 12),
                  deviceBox,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: clientBox),
                const SizedBox(width: 12),
                Expanded(child: deviceBox),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // DEVICE INFO BOX
  // ══════════════════════════════════════════════════════════════
  Widget _buildDeviceInfoBox(
      AdminColors tc, {
        required String deviceStatus,
        required String displayValue,
        required String registeredDevice,
        required String actualDevice,
      }) {
    final bool isRegistered = deviceStatus == 'registered';
    final bool isUnregistered = deviceStatus == 'unregistered';
    final bool isLegacy = deviceStatus == 'legacy';
    final bool isUnknown = deviceStatus == 'none';

    Color boxBg;
    Color boxBorder;
    Color iconColor;
    Color labelColor;
    IconData icon;
    Color valueColor;
    Color? badgeBg;
    Color? badgeTextColor;
    String? badgeText;

    if (isRegistered) {
      boxBg = const Color(0xFFDCFCE7);
      boxBorder = const Color(0xFF22C55E);
      iconColor = const Color(0xFF166534);
      labelColor = const Color(0xFF166534);
      icon = Icons.verified_user_rounded;
      valueColor = tc.text;
      badgeBg = const Color(0xFF22C55E);
      badgeTextColor = Colors.white;
      badgeText = 'REGISTERED';
    } else if (isUnregistered) {
      boxBg = const Color(0xFFFEE2E2);
      boxBorder = const Color(0xFFEF4444);
      iconColor = const Color(0xFF991B1B);
      labelColor = const Color(0xFF991B1B);
      icon = Icons.gpp_maybe_rounded;
      valueColor = const Color(0xFF991B1B);
      badgeBg = const Color(0xFFEF4444);
      badgeTextColor = Colors.white;
      badgeText = 'UNREGISTERED';
    } else if (isLegacy) {
      boxBg = const Color(0xFFFEF3C7);
      boxBorder = const Color(0xFFF59E0B);
      iconColor = const Color(0xFF92400E);
      labelColor = const Color(0xFF92400E);
      icon = Icons.system_update_alt_rounded;
      valueColor = const Color(0xFF92400E);
      badgeBg = const Color(0xFFF59E0B);
      badgeTextColor = Colors.white;
      badgeText = 'NEEDS UPDATE';
    } else {
      boxBg = tc.surface;
      boxBorder = tc.border;
      iconColor = tc.muted;
      labelColor = tc.muted;
      icon = Icons.phone_iphone_rounded;
      valueColor = tc.text;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: boxBorder,
          width: isRegistered || isUnregistered || isLegacy ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 6),
              Text(
                'DEVICE INFO',
                style: TextStyle(
                  fontSize: 10,
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              if (badgeText != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 7,
                      color: badgeTextColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayValue,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (isUnregistered && registeredDevice.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 12, color: Color(0xFF991B1B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Registered: $registeredDevice',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF991B1B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'A different device was used than the registered one',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF991B1B),
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isLegacy && registeredDevice.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 12, color: Color(0xFF92400E)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Old format: $registeredDevice',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF92400E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'The registered device on the profile needs to be updated',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF92400E),
                      fontStyle: FontStyle.italic,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isRegistered && actualDevice.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 11, color: Color(0xFF166534)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Verified — matches registered device',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF166534),
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (isUnknown && displayValue == 'Not recorded') ...[
            const SizedBox(height: 4),
            Text(
              'No device info in the attendance log or profile',
              style: TextStyle(
                fontSize: 10,
                color: tc.muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // MAP PREVIEW
  // ══════════════════════════════════════════════════════════════
  Widget _buildMapPreview(
      AdminColors tc, {
        required String dateStr,
        required String coordsStr,
        required String locationName,
      }) {
    final coords = _getCoords();

    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final mapHeight = r.responsive<double>(
        xs: 260,
        sm: 300,
        md: 340,
        lg: 340,
      );

      return Container(
        height: mapHeight,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: tc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tc.border),
        ),
        child: Stack(
          children: [
            if (coords != null)
              FlutterMap(
                options: MapOptions(
                  initialCenter: coords,
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
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
                        point: coords,
                        radius: 100,
                        useRadiusInMeter: true,
                        color: tc.orange.withValues(alpha: 0.15),
                        borderColor: tc.orange.withValues(alpha: 0.6),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: coords,
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: tc.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person_pin_circle_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: tc.isDark
                          ? [
                        const Color(0xFF1F2937),
                        const Color(0xFF111827),
                      ]
                          : [
                        const Color(0xFF3B4A5F),
                        const Color(0xFF1F2937),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_off_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No GPS data recorded',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Attendance log has no coordinates',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: LayoutBuilder(builder: (_, overlayC) {
                final narrow = overlayC.maxWidth < 400;
                final info = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 12, color: tc.orange),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(dateStr,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: tc.text),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 12, color: tc.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 11, color: tc.muted),
                              children: [
                                TextSpan(
                                  text: coordsStr,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: tc.text),
                                ),
                                if (locationName.isNotEmpty &&
                                    locationName != 'Not recorded')
                                  TextSpan(
                                    text: ' ($locationName)',
                                    style: TextStyle(color: tc.muted),
                                  ),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                final badge = Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: coords != null ? tc.pillGreenBg : tc.pillWarnBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (coords != null ? tc.pillGreenTx : tc.pillWarnTx)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        coords != null
                            ? Icons.verified_rounded
                            : Icons.warning_amber_rounded,
                        size: 12,
                        color:
                        coords != null ? tc.pillGreenTx : tc.pillWarnTx,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        coords != null ? 'Location\nMatched' : 'No GPS\nData',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color:
                          coords != null ? tc.pillGreenTx : tc.pillWarnTx,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                );

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: tc.card.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tc.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: narrow
                      ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      info,
                      const SizedBox(height: 10),
                      badge,
                    ],
                  )
                      : Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 12),
                      badge,
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      );
    });
  }

  // ══════════════════════════════════════════════════════════════
  // SUB DETAIL BOX
  // ══════════════════════════════════════════════════════════════
  Widget _subDetailBox(
      AdminColors tc, {
        required IconData icon,
        required String label,
        required String value,
      }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: tc.muted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: tc.muted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tc.text),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}