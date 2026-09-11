// lib/screens/admin_attendance_verification_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'admin_theme.dart';
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
  String? _clientInfoOverride;
  bool _loading = true;

  AdminColors get tc => AdminTheme.getColors(context);

  @override
  void initState() {
    super.initState();
    _fetchRelatedData();
  }

  // ══════════════════════════════════════════════════════════════
  // EXTRACT LATLNG from any map
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
  // EXTRACT DEVICE INFO
  // ══════════════════════════════════════════════════════════════
  String? _extractDeviceInfo(Map<String, dynamic> data) {
    const keys = [
      'deviceInfo', 'device', 'deviceName', 'deviceModel',
      'userAgent', 'platform', 'deviceId', 'device_id',
      'clientDevice', 'phoneModel', 'browser', 'os', 'source',
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
  // EXTRACT CLIENT INFO
  // ══════════════════════════════════════════════════════════════
  String? _extractClientInfo(Map<String, dynamic> data) {
    const keys = [
      'client', 'clientName', 'clientInfo', 'purpose', 'reason',
      'verificationMethod', 'verificationNote', 'note',
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
    final log = widget.logData;
    final empId = (log['employee_id'] ?? log['employeeId'] ?? '').toString();
    final empAuthUid = (log['authUid'] ?? log['auth_uid'] ?? '').toString();
    final empName = (log['employee_name'] ?? log['name'] ?? '').toString();
    final empEmail = (log['email'] ?? '').toString();
    final logTs = _toDateTime(log['timestamp']);

    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🔍 [VERIFY] Fetch: name="$empName" id="$empId" email="$empEmail"');
    debugPrint('🔍 [VERIFY] Log timestamp: $logTs');
    debugPrint('🔍 [VERIFY] Log fields: ${log.keys.toList()}');

    _deviceInfoOverride = _extractDeviceInfo(log);
    _clientInfoOverride = _extractClientInfo(log);

    final logCoords = _extractLatLng(log);
    if (logCoords != null) {
      _locationData = {
        'latitude': logCoords.latitude,
        'longitude': logCoords.longitude,
        'locationName': log['locationName'] ?? log['location_name'],
        'timestamp': log['timestamp'],
      };
      debugPrint('✅ [VERIFY] Coords IN LOG: ${logCoords.latitude}, ${logCoords.longitude}');
    }

    // 1. Fetch employee doc
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
          debugPrint('✅ [VERIFY] Emp by authUid');
        }
      }

      if (found == null && empId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(empId)
            .get();
        if (doc.exists && doc.data() != null) {
          found = {...doc.data()!, 'id': doc.id};
          debugPrint('✅ [VERIFY] Emp by doc id');
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
          debugPrint('✅ [VERIFY] Emp by name');
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
          debugPrint('✅ [VERIFY] Emp by nfcTagId');
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
          debugPrint('✅ [VERIFY] Emp by email');
        }
      }

      _employeeData = found;
    } catch (e) {
      debugPrint('❌ [VERIFY] Emp error: $e');
    }

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

    // 2. Fetch GPS from user locations
    if (_locationData == null) {
      const locationCollections = [
        'user locations', 'user_locations', 'locations',
        'attendance_locations', 'gps_logs',
      ];
      const employeeFieldNames = [
        'employeeId', 'employee_id', 'empId', 'uid', 'authUid',
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
                debugPrint('✅ [VERIFY] Location found in "$coll"');
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

    // 3. Device info fallback
    if (_deviceInfoOverride == null) {
      for (final coll in ['attendance_logs', 'activity_logs', 'clock_ins', 'clock_outs']) {
        if (_deviceInfoOverride != null) break;
        for (final id in empIds) {
          if (_deviceInfoOverride != null) break;
          try {
            final s = await FirebaseFirestore.instance
                .collection(coll)
                .where('employeeId', isEqualTo: id)
                .limit(10)
                .get();
            for (final d in s.docs) {
              final device = _extractDeviceInfo(d.data());
              if (device != null) {
                _deviceInfoOverride = device;
                break;
              }
            }
          } catch (_) {}
        }
      }
    }

    if (_deviceInfoOverride == null && _locationData != null) {
      _deviceInfoOverride = _extractDeviceInfo(_locationData!);
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
    if (_deviceInfoOverride != null && _deviceInfoOverride!.isNotEmpty) {
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
              _buildBreadcrumb(tc),
              const SizedBox(height: 8),
              _buildPageHeader(context, tc),
              const SizedBox(height: 24),
              if (_loading)
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

              // ✅ Bootstrap: stack below lg (992px)
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
                        locationName: locationName,
                        coordsStr: coordsStr,
                        verificationNote: verificationNote,
                        dateStr: dateStr,
                      ),
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
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
                          locationName: locationName,
                          coordsStr: coordsStr,
                          verificationNote: verificationNote,
                          dateStr: dateStr,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // BREADCRUMB
  // ══════════════════════════════════════════════════════════════
  Widget _buildBreadcrumb(AdminColors tc) {
    return Row(
      children: [
        if (widget.onBack != null) ...[
          InkWell(
            onTap: widget.onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.arrow_back_rounded,
                  size: 16, color: tc.muted),
            ),
          ),
        ],
        Flexible(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: tc.muted),
              children: [
                TextSpan(
                  text: 'Attendance Logs',
                  recognizer: widget.onBack != null
                      ? (TapGestureRecognizerHolder(widget.onBack!).recognizer)
                      : null,
                ),
                const TextSpan(text: ' > '),
                TextSpan(
                  text: 'Verification Detail',
                  style: TextStyle(
                      color: tc.orange, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE HEADER — responsive
  // ══════════════════════════════════════════════════════════════
  Widget _buildPageHeader(BuildContext context, AdminColors tc) {
    return LayoutBuilder(builder: (_, c) {
      final r = BsResponsive(c.maxWidth);
      final narrow = !r.up(BsSize.sm);

      final title = Text(
        'Attendance Verification',
        style: TextStyle(
          fontSize: r.responsive<double>(
            xs: 22, sm: 24, md: 26, lg: 28,
          ),
          fontWeight: FontWeight.w700,
          color: tc.text,
          letterSpacing: -0.5,
        ),
      );

      final approveBtn = ElevatedButton.icon(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Marked as approved.'),
              backgroundColor: tc.green,
            ),
          );
        },
        icon: const Icon(Icons.done_all_rounded, size: 16),
        label: const Text('Approve All',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: tc.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      );

      if (narrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 12),
            approveBtn,
          ],
        );
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: title),
          const SizedBox(width: 12),
          approveBtn,
        ],
      );
    });
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
          // Avatar + name + ID badge
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

          // Department + Manager
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
                    child: _metaColumn(tc,
                        label: 'DEPARTMENT', value: department)),
                const SizedBox(width: 16),
                Expanded(
                    child: _metaColumn(tc,
                        label: 'MANAGER', value: manager)),
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

    final subInfo =
    _s(entry['locationName'] ?? entry['keyfobSerial'] ?? '', '');

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
                                fontWeight: FontWeight.w700,
                                color: tc.text),
                          ),
                        ],
                      ),
                    ),
                    if (subInfo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.confirmation_number_outlined,
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
          // Header row
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
                              style: TextStyle(
                                  fontSize: 13, color: tc.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () {
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
                    border:
                    Border.all(color: tc.red.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.flag_outlined,
                      size: 18, color: tc.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Map preview
          _buildMapPreview(tc,
              dateStr: dateStr,
              coordsStr: coordsStr,
              locationName: locationName),
          const SizedBox(height: 20),

          // Client + Device — stack on narrow
          LayoutBuilder(builder: (_, c) {
            final narrow = c.maxWidth < 400;
            final clientBox = _subDetailBox(tc,
                icon: Icons.work_outline_rounded,
                label: 'CLIENT',
                value: client);
            final deviceBox = _subDetailBox(tc,
                icon: Icons.phone_iphone_rounded,
                label: 'DEVICE INFO',
                value: deviceInfo);

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
        xs: 260, sm: 300, md: 340, lg: 340,
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

            // Overlay info card
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
                      color: (coords != null
                          ? tc.pillGreenTx
                          : tc.pillWarnTx)
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
                        color: coords != null
                            ? tc.pillGreenTx
                            : tc.pillWarnTx,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        coords != null ? 'Location\nMatched' : 'No GPS\nData',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: coords != null
                              ? tc.pillGreenTx
                              : tc.pillWarnTx,
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

class TapGestureRecognizerHolder {
  final VoidCallback onTap;
  TapGestureRecognizerHolder(this.onTap);
  late final recognizer = (TapGestureRecognizer()..onTap = onTap);
}