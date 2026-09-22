// lib/screens/clock_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../models/employee.dart';
import '../services/geofence_service.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';
import '../services/presence_monitor_service.dart';
import '../services/device_info_service.dart';
import '../services/admin_notification_service.dart';
import '../widgets/employee_notification_bell.dart';

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get navBg => isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get navBorder => const Color(0xFF27272A);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted =>
      isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get textOnDark => Colors.white;
  Color get cardFill =>
      isDark ? const Color(0xFF1F1F23) : Colors.white.withValues(alpha: 0.5);
  Color get cardBorder => const Color(0xFFFFA500);
  Color get avatarBg =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get avatarBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
}

class ClockScreen extends StatefulWidget {
  final Employee? initialEmployee;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;
  final VoidCallback? onRefresh;
  final VoidCallback? onClockIn;
  final VoidCallback? onClockOut;
  final VoidCallback? onShortcutHome;
  final VoidCallback? onShortcutProfile;
  final VoidCallback? onShortcutLeaves;
  final ValueChanged<int>? onNavTap;
  final bool initialInRange;
  final bool initialWfhAccess;

  const ClockScreen({
    super.key,
    this.initialEmployee,
    this.onBack,
    this.onContinue,
    this.onRefresh,
    this.onClockIn,
    this.onClockOut,
    this.onShortcutHome,
    this.onShortcutProfile,
    this.onShortcutLeaves,
    this.onNavTap,
    this.initialInRange = false,
    this.initialWfhAccess = false,
  });

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  static const _orange = Color(0xFFFF8A00);
  static const _orangeMid = Color(0xFFFA6A00);
  static const _orangeDeep = Color(0xFFF54900);
  static const _orangeBorder = Color(0xFFFFA500);
  static const _green = Color(0xFFC4FF0A);
  static const _greenDeep = Color(0xFF166534);
  static const _red = Color(0xFFFF0000);

  static const _orangeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_orange, _orangeMid, _orangeDeep],
    stops: [0.0, 0.5, 1.0],
  );

  late bool _isInRange;
  late bool _wfhAccess;
  bool _checkingGeofence = false;
  int _activeNavIndex = 0;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  DateTime? _clockInTime;
  DateTime? _clockOutTime;
  bool _saving = false;

  Employee? _liveEmployee;

  // 🆕 Actual device model
  String _deviceModel = 'Unknown Device';

  StreamSubscription<QuerySnapshot>? _attendanceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;

  Employee? get _employee => _liveEmployee ?? widget.initialEmployee;

  String? get _employeeId {
    final id = _employee?.employeeId;
    if (id != null && id.isNotEmpty) return id;
    final fallback = _employee?.id;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  String? get _employeeDocId {
    final id = _employee?.id;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  bool get _canClock => _isInRange || _wfhAccess;
  bool get _isWfhMode => _wfhAccess && !_isInRange;

  @override
  void initState() {
    super.initState();
    _isInRange = widget.initialInRange;
    _wfhAccess = widget.initialWfhAccess || _readWfhFromEmployee();
    _startClock();
    _startAttendanceStream();
    _startEmployeeListener();
    _loadDeviceModel(); // 🆕

    final emp = _employee;
    if (emp != null) {
      PresenceMonitorService.instance.start(employee: emp);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _refreshGeofence(silent: true);
      await Future.delayed(const Duration(seconds: 1));
      await OfflineAttendanceService.instance.dumpAll();
    });
  }

  // 🆕 Load actual device model
  Future<void> _loadDeviceModel() async {
    try {
      final model = await DeviceInfoService.instance.getDeviceModel();
      if (!mounted) return;
      setState(() => _deviceModel = model);
      debugPrint('📱 [ClockScreen] Device model: $model');
    } catch (e) {
      debugPrint('⚠️ [ClockScreen] Device model load failed: $e');
    }
  }

  bool _readWfhFromEmployee() {
    final emp = _employee;
    if (emp == null) return false;
    try {
      final dynamic v = (emp as dynamic).wfhAccess;
      if (v is bool) return v;
      if (v != null) return v.toString().toLowerCase() == 'true';
    } catch (_) {}
    return false;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    super.dispose();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  String _formatTime(DateTime t) {
    final h24 = t.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final m = t.minute.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    return '${h12.toString().padLeft(2, '0')}:$m $period';
  }

  String get _liveTime => _formatTime(_now);
  String get _clockInDisplay =>
      _clockInTime != null ? _formatTime(_clockInTime!) : '--:--';
  String get _clockOutDisplay =>
      _clockOutTime != null ? _formatTime(_clockOutTime!) : '--:--';

  String get _todayStr {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  // 🆕 Returns cached device model (from DeviceInfoService)
  String _deviceName() {
    if (_deviceModel.isNotEmpty && _deviceModel != 'Unknown Device') {
      return _deviceModel;
    }
    // Fallback kung hindi pa na-load
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android App';
      if (Platform.isIOS) return 'iOS App';
      if (Platform.isWindows) return 'Windows App';
      if (Platform.isMacOS) return 'macOS App';
      if (Platform.isLinux) return 'Linux App';
    } catch (_) {}
    return defaultTargetPlatform.name;
  }

  String _computeZoneType() {
    final role = (_employee?.position ?? '').toLowerCase();
    final dept = (_employee?.department ?? '').toLowerCase();

    final isDriver = role.contains('driver') ||
        role.contains('rider') ||
        dept.contains('driver') ||
        dept.contains('rider');
    if (isDriver) return 'driver';
    if (_isInRange) return 'inside';
    if (_wfhAccess) return 'wfh';
    return 'outside';
  }

  Future<void> _refreshGeofence({bool silent = false}) async {
    if (_checkingGeofence) return;
    if (mounted) setState(() => _checkingGeofence = true);

    GeofenceService.instance.invalidateCache();

    try {
      final empDocId = _employeeDocId;
      GeofenceResult result;

      if (empDocId != null && empDocId.isNotEmpty) {
        result = await GeofenceService.instance
            .checkGeofenceForEmployee(employeeId: empDocId)
            .timeout(const Duration(seconds: 15));
      } else {
        result = await GeofenceService.instance
            .checkGeofence()
            .timeout(const Duration(seconds: 12));
      }

      final inside = result.isInside;
      final distance = result.distanceMeters;

      if (!mounted) return;

      debugPrint('📍 [ClockScreen] geofence: inside=$inside, '
          'exempted=${result.isExempted}, '
          'zone=${result.matchedLocationName}, '
          'distance=${distance?.toStringAsFixed(0)}m');

      final changed = inside != _isInRange;

      setState(() {
        _isInRange = inside;
        _checkingGeofence = false;
      });

      if (changed && !silent) {
        _showSnack(
          inside
              ? '✅ Nasa authorized zone ka na.'
              : '📍 Wala ka sa authorized zone. '
              'Kung remote ka, pakiusapan ang admin na i-enable ang WFH.',
        );
      }
    } catch (e) {
      debugPrint('❌ Geofence error: $e');
      if (!mounted) return;
      setState(() => _checkingGeofence = false);
      if (!silent) {
        _showSnack(
          '⚠️ Hindi ma-verify ang location. Paki-check ang GPS at internet.',
        );
      }
    }
  }

  Future<void> _handlePullRefresh() async {
    await OfflineAttendanceService.instance.dumpAll();
    await Future.wait([
      _refreshGeofence(silent: true),
      _reloadAttendanceOnce(),
      _reloadEmployeeOnce(),
      OfflineAttendanceService.instance.syncPending(),
      PresenceMonitorService.instance.checkNow(),
    ]);
    await OfflineAttendanceService.instance.dumpAll();
  }

  Future<void> _reloadAttendanceOnce() async {
    final empId = _employeeId;
    if (empId == null || empId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: empId)
          .where('date', isEqualTo: _todayStr)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _processAttendance(snap.docs);
    } catch (e) {
      debugPrint('⚠️ _reloadAttendanceOnce error: $e');
    }
  }

  Future<void> _reloadEmployeeOnce() async {
    final docId = _employeeDocId;
    if (docId == null || docId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('employees')
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null || !mounted) return;
      final updated = Employee.fromFirestore(data, docId);
      setState(() => _liveEmployee = updated);
    } catch (e) {
      debugPrint('⚠️ _reloadEmployeeOnce error: $e');
    }
  }

  void _startAttendanceStream() {
    final empId = _employeeId;
    if (empId == null) return;
    _attendanceSub?.cancel();
    _attendanceSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: empId)
        .where('date', isEqualTo: _todayStr)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        _processAttendance(snap.docs);
      },
      onError: (e) => debugPrint('❌ ClockScreen stream error: $e'),
    );
  }

  void _startEmployeeListener() {
    final empDocId = _employeeDocId;
    if (empDocId == null || empDocId.isEmpty) return;
    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(empDocId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;

        Employee? updated;
        try {
          updated = Employee.fromFirestore(data, empDocId);
        } catch (e) {
          debugPrint('⚠️ Employee parse error: $e');
        }
        if (updated != null) {
          setState(() => _liveEmployee = updated);
          PresenceMonitorService.instance.start(employee: updated);
        }

        final raw = data['wfhAccess'];
        final enabled = raw is bool
            ? raw
            : (raw?.toString().toLowerCase() == 'true');

        if (enabled != _wfhAccess) {
          setState(() => _wfhAccess = enabled);
          _showSnack(
            enabled
                ? '🏠 WFH access ENABLED — pwede ka nang mag-clock in/out kahit saan.'
                : '🏢 WFH access DISABLED — kailangan nasa office zone na.',
          );
        }
      },
      onError: (e) =>
          debugPrint('❌ [ClockScreen] Employee listener error: $e'),
    );
  }

  DateTime? _extractDateTime(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      final parsed = _parseTimeString(rawTime.trim());
      if (parsed != null) return parsed;
    }
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) return rawTs.toDate().toLocal();
    if (rawTs is String && rawTs.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(rawTs.trim());
      if (parsed != null) return parsed.toLocal();
    }
    if (rawTs is int) return DateTime.fromMillisecondsSinceEpoch(rawTs);
    return null;
  }

  void _processAttendance(List<QueryDocumentSnapshot> docs) {
    DateTime? inTime;
    DateTime? outTime;

    final sorted = [...docs]..sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      final aTime = _extractDateTime(aData) ?? DateTime(2000);
      final bTime = _extractDateTime(bData) ?? DateTime(2000);
      return aTime.compareTo(bTime);
    });

    for (final doc in sorted) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type']?.toString().toUpperCase();
      final parsed = _extractDateTime(data);
      if (parsed == null) continue;

      if (type == 'IN' || type == 'CLOCK_IN') {
        inTime = parsed;
        outTime = null;
      } else if (type == 'OUT' || type == 'CLOCK_OUT') {
        if (inTime != null && parsed.isAfter(inTime)) {
          outTime = parsed;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _clockInTime = inTime;
      _clockOutTime = outTime;
    });
  }

  DateTime? _parseTimeString(String t) {
    try {
      final parts = t.split(':');
      if (parts.length < 2) return null;
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
        parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _saveAttendance({
    required String type,
    required DateTime time,
  }) async {
    final empId = _employeeId;
    if (empId == null || empId.isEmpty) {
      _showSnack('Hindi makuha ang employee ID. Pakisuri ang login.');
      return false;
    }

    final timeStr = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    final employeeName = _employee?.fullName ?? 'Unknown';
    final employeeEmail = _employee?.email ?? '';
    final deviceName = _deviceName(); // 🆕 actual device model
    final isClockIn = type == 'IN';
    final zoneType = _computeZoneType();

    double? distanceMeters;
    if (zoneType == 'outside' || zoneType == 'inside') {
      try {
        final geo = await GeofenceService.instance
            .checkGeofence()
            .timeout(const Duration(seconds: 8));
        distanceMeters = geo.distanceMeters;
      } catch (e) {
        debugPrint('⚠️ distance capture failed: $e');
      }
    }

    final result = await OfflineAttendanceService.instance.logAttendance(
      employeeId: empId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      type: type,
      timestamp: time,
      device: deviceName,
      remarks: zoneType,
      zoneType: zoneType,
    );

    if (!result.success) {
      _showSnack('Error saving attendance. Please try again.');
      return false;
    }

    if (result.queued) {
      _showSnack('💾 Saved offline. Auto-sync pagbalik ng internet.');
    }

    _writeSecondaryLogs(
      empId: empId,
      employeeName: employeeName,
      timeStr: timeStr,
      isClockIn: isClockIn,
      deviceName: deviceName,
      zoneType: zoneType,
      distanceMeters: distanceMeters,
    );

    PresenceMonitorService.instance.checkNow();

    return true;
  }

  void _writeSecondaryLogs({
    required String empId,
    required String employeeName,
    required String timeStr,
    required bool isClockIn,
    required String deviceName,
    required String zoneType,
    double? distanceMeters,
  }) {
    final activityLogPayload = <String, dynamic>{
      'type': isClockIn ? 'clock_in' : 'clock_out',
      'action': isClockIn ? 'Clocked In' : 'Clocked Out',
      'employeeId': empId,
      'employee_id': empId,
      'employee_name': employeeName,
      'time': timeStr,
      'date': _todayStr,
      'wfh': _wfhAccess,
      'in_range': _isInRange,
      'zone_type': zoneType,
      'device': deviceName,
      'deviceName': deviceName,   // 🆕 explicit key
      'deviceModel': deviceName,  // 🆕 explicit key
      'platform': deviceName,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final historyLogPayload = <String, dynamic>{
      'type': isClockIn ? 'login' : 'logout',
      'employee_id': empId,
      'employee_name': employeeName,
      'device': deviceName,
      'deviceName': deviceName,   // 🆕
      'wfh': _wfhAccess,
      'in_range': _isInRange,
      'zone_type': zoneType,
      'timestamp': FieldValue.serverTimestamp(),
    };

    FirebaseFirestore.instance
        .collection('activity logs')
        .add(activityLogPayload)
        .catchError((e) => debugPrint('⚠️ activity logs FAILED: $e'));

    FirebaseFirestore.instance
        .collection('activity_logs')
        .add(historyLogPayload)
        .catchError((e) => debugPrint('⚠️ activity_logs FAILED: $e'));

    try {
      if (isClockIn) {
        switch (zoneType) {
          case 'wfh':
            AdminNotificationService.instance.notifyWFHClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'driver':
            AdminNotificationService.instance.notifyDriverClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'outside':
            AdminNotificationService.instance.notifyGeofenceAlert(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              distanceMeters: distanceMeters ?? 0,
              action: 'clock_in',
            );
            break;
          default:
            AdminNotificationService.instance.notifyClockIn(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              wfh: _wfhAccess,
              inRange: _isInRange,
              zoneType: zoneType,
              distanceMeters: distanceMeters,
            );
        }
      } else {
        switch (zoneType) {
          case 'wfh':
            AdminNotificationService.instance.notifyWFHClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          case 'driver':
            AdminNotificationService.instance.notifyDriverClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
            );
            break;
          default:
            AdminNotificationService.instance.notifyClockOut(
              employeeId: empId,
              employeeName: employeeName,
              timeStr: timeStr,
              wfh: _wfhAccess,
              inRange: _isInRange,
              zoneType: zoneType,
              distanceMeters: distanceMeters,
            );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Admin notification failed: $e');
    }
  }

  Future<void> _notifyBlockedAttempt(String action) async {
    final empId = _employeeId;
    final empName = _employee?.fullName ?? 'Unknown';
    if (empId == null || empId.isEmpty) return;

    double distance = 0;
    try {
      final geo = await GeofenceService.instance.checkGeofence();
      distance = geo.distanceMeters ?? 0;
    } catch (e) {
      debugPrint('⚠️ BlockedAttempt geofence check failed: $e');
    }

    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    try {
      await AdminNotificationService.instance.notifyGeofenceAlertThrottled(
        employeeId: empId,
        employeeName: empName,
        timeStr: timeStr,
        distanceMeters: distance,
        action: action,
      );
    } catch (e) {
      debugPrint('❌ BlockedAttempt notify failed: $e');
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _handleContinue() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      _handleBack();
    }
  }

  Future<void> _handleClockIn() async {
    if (_saving) return;

    if (!_canClock) {
      _notifyBlockedAttempt('clock_in');
      _showSnack(
        'Wala ka sa authorized location. Hindi ka makakapag-clock in. '
            'Pakisuyo sa admin na i-enable ang WFH access kung remote ka.',
      );
      return;
    }
    if (_clockInTime != null) {
      _showSnack('Naka-clock in ka na ng ${_formatTime(_clockInTime!)}.');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final ok = await _saveAttendance(type: 'IN', time: now);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _clockInTime = now;
    });
    if (!ok) return;

    _showSnack('✅ Clocked IN at ${_formatTime(now)}');
    widget.onClockIn?.call();
  }

  Future<void> _handleClockOut() async {
    if (_saving) return;

    if (!_canClock) {
      _notifyBlockedAttempt('clock_out');
      _showSnack(
        'Wala ka sa authorized location. Hindi ka makakapag-clock out. '
            'Pakisuyo sa admin na i-enable ang WFH access kung remote ka.',
      );
      return;
    }
    if (_clockInTime == null) {
      _showSnack('Mag-clock in ka muna bago mag-clock out.');
      return;
    }
    if (_clockOutTime != null) {
      _showSnack('Naka-clock out ka na ng ${_formatTime(_clockOutTime!)}.');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final ok = await _saveAttendance(type: 'OUT', time: now);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _clockOutTime = now;
    });
    if (!ok) return;

    _showSnack('✅ Clocked OUT at ${_formatTime(now)}');
    widget.onClockOut?.call();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final empName = _employee?.fullName ?? 'JOHN HOWARD';

    return Scaffold(
      backgroundColor: tc.bg,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _orange,
                backgroundColor: tc.bg,
                onRefresh: _handlePullRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _buildHeader(tc, empName),
                      const SizedBox(height: 24),
                      _buildHeroCard(),
                      const SizedBox(height: 21),
                      _buildClockInOutSection(),
                      const SizedBox(height: 23),
                      _buildClockOutSection(tc),
                      const SizedBox(height: 21),
                      _buildShortcutsSection(tc),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildBottomNav(tc),
        ],
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc, String name) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    final empId = _employeeId ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _handleBack,
            child: _buildHeaderAvatar(tc, initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'HI, $name'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tc.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 12, color: _orange),
                    const SizedBox(width: 4),
                    Text(
                      _liveTime,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tc.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (_wfhAccess) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tc.isDark
                              ? const Color(0xFF14371F)
                              : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF22C55E)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.home_work_rounded,
                                size: 10,
                                color: tc.isDark
                                    ? const Color(0xFF86EFAC)
                                    : _greenDeep),
                            const SizedBox(width: 4),
                            Text(
                              'WFH',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: tc.isDark
                                    ? const Color(0xFF86EFAC)
                                    : _greenDeep,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (empId.isNotEmpty)
            EmployeeNotificationBell(
              employeeId: empId,
              iconColor: tc.textPrimary,
              size: 22,
            ),
          if (_checkingGeofence)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: _orange,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderAvatar(_ThemeColors tc, String initials) {
    final photoUrl = _employee?.photoUrl;
    final hasPhoto =
        photoUrl != null && photoUrl.isNotEmpty && photoUrl != '—';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tc.avatarBg,
        border: Border.all(color: tc.avatarBorder, width: 1.15),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasPhoto
          ? _buildPhotoContent(tc, photoUrl, initials)
          : Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPhotoContent(_ThemeColors tc, String url, String initials) {
    if (url.startsWith('data:image')) {
      try {
        final b64 = url.split(',').last;
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          width: 40,
          height: 40,
          errorBuilder: (_, __, ___) => _avatarFallbackText(tc, initials),
        );
      } catch (_) {
        return _avatarFallbackText(tc, initials);
      }
    }
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: 40,
        height: 40,
        errorBuilder: (_, __, ___) => _avatarFallbackText(tc, initials),
      );
    }
    return _avatarFallbackText(tc, initials);
  }

  Widget _avatarFallbackText(_ThemeColors tc, String initials) {
    return Container(
      color: _orange,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final Color accent;
    final String statusText;
    final String subtitle;

    if (_checkingGeofence && !_wfhAccess) {
      accent = const Color(0xFFA1A1AA);
      statusText = 'Checking...';
      subtitle = 'Vine-verify ang iyong lokasyon. Maghintay lang.';
    } else if (_isWfhMode) {
      accent = const Color(0xFF4ADE80);
      statusText = 'WFH Mode.';
      subtitle =
      'Work-from-home access is active. You can clock in/out anywhere.';
    } else if (_isInRange) {
      accent = _green;
      statusText = 'In Range.';
      subtitle = 'Our system verified your location. You are ready to go.';
    } else {
      accent = _orange;
      statusText = 'Out of Range.';
      subtitle =
      'You are outside the authorized zone. Clock in/out is disabled.';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _handleContinue,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _orangeBorder, width: 1.15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 50,
                offset: const Offset(0, 25),
                spreadRadius: -12,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF3A2A1A),
                      Color(0xFF1A1A1A),
                      Color(0xFF09090B),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _orange.withValues(alpha: 0.45),
                        _orange.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xE609090B),
                      Color(0x6609090B),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 32, 25, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          height: 1.15,
                        ),
                        children: [
                          const TextSpan(text: 'You are currently\n'),
                          TextSpan(
                            text: statusText,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFA1A1AA),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClockInOutSection() {
    final clockedIn = _clockInTime != null;
    final canClock = _canClock;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 72,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: _orangeGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _orangeBorder, width: 1.15),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: (_saving || !canClock) ? null : _handleClockIn,
                behavior: HitTestBehavior.opaque,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canClock ? 1.0 : 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _orangeBorder, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Clock In',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _saving && !clockedIn
                              ? 'Saving...'
                              : (canClock ? _clockInDisplay : 'Locked'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: !canClock
                                ? _red
                                : (clockedIn
                                ? _orange
                                : const Color(0xFFA1A1AA)),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: GestureDetector(
                onTap: (_saving || !canClock) ? null : _handleClockOut,
                behavior: HitTestBehavior.opaque,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: canClock ? 1.0 : 0.5,
                  child: Container(
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Clock Out',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          canClock ? _clockOutDisplay : 'Locked',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.3,
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
    );
  }

  Widget _buildClockOutSection(_ThemeColors tc) {
    final isInRangeOrWfh = _isInRange || _isWfhMode;

    final cardBg = _isInRange
        ? (tc.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.2))
        : (_isWfhMode
        ? const Color(0xFF22C55E)
        .withValues(alpha: tc.isDark ? 0.2 : 0.15)
        : (tc.isDark
        ? const Color(0xFF1F1F23)
        : const Color(0xFF838383).withValues(alpha: 0.28)));

    final cardBorder = _isInRange
        ? _orangeBorder
        : (_isWfhMode ? const Color(0xFF22C55E) : _red);

    final labelColor = isInRangeOrWfh ? tc.textPrimary : tc.textOnDark;
    final hasClockedOut = _clockOutTime != null;
    final canClock = _canClock;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Clock Out',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tc.textPrimary,
                ),
              ),
              if (hasClockedOut)
                Text(
                  _clockOutDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _orange,
                  ),
                )
              else if (!canClock)
                const Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: (_saving || !canClock) ? null : _handleClockOut,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: canClock ? 1.0 : 0.5,
                child: Container(
                  width: 105,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cardBorder, width: 1.15),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _orangeGradient,
                          border:
                          Border.all(color: _orangeBorder, width: 1.15),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          !canClock
                              ? Icons.lock_outline_rounded
                              : (hasClockedOut
                              ? Icons.check_rounded
                              : Icons.access_time_rounded),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        !canClock
                            ? 'Locked'
                            : (hasClockedOut ? 'Done' : 'Clock Out'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isWfhMode) ...[
            const SizedBox(height: 12),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tc.isDark
                    ? const Color(0xFF14371F)
                    : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.home_work_rounded,
                    size: 16,
                    color: tc.isDark ? const Color(0xFF86EFAC) : _greenDeep,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'WFH mode active — pinapayagan ang clock in/out kahit wala sa office zone.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color:
                        tc.isDark ? const Color(0xFF86EFAC) : _greenDeep,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShortcutsSection(_ThemeColors tc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Short Cuts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: tc.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.home_rounded,
                    label: 'Home',
                    onTap: widget.onShortcutHome ?? _handleBack,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    onTap: widget.onShortcutProfile,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _ShortcutCard(
                    tc: tc,
                    icon: Icons.calendar_month_rounded,
                    label: 'Leaves',
                    onTap: widget.onShortcutLeaves,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(_ThemeColors tc) {
    const items = <_NavItem>[
      _NavItem(icon: Icons.grid_view_rounded, label: 'Home'),
      _NavItem(icon: Icons.access_time_rounded, label: 'Logs'),
      _NavItem(icon: Icons.calendar_today_rounded, label: 'Itinerary'),
      _NavItem(icon: Icons.person_outline_rounded, label: 'Profile'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: tc.navBg,
        border: Border(top: BorderSide(color: tc.navBorder, width: 1.15)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(items.length, (i) {
            final item = items[i];
            final active = i == _activeNavIndex;
            final color = active ? _orange : tc.textSecondary;
            return GestureDetector(
              onTap: () {
                setState(() => _activeNavIndex = i);
                widget.onNavTap?.call(i);
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _ShortcutCard extends StatelessWidget {
  final _ThemeColors tc;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ShortcutCard({
    required this.tc,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: tc.cardFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _ClockScreenState._orangeBorder,
            width: 1.15,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _ClockScreenState._orangeGradient,
                border: Border.all(
                  color: _ClockScreenState._orangeBorder,
                  width: 1.15,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: tc.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}