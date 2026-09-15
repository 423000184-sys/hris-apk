// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../models/employee.dart';
import '../services/database_service.dart';
import '../services/geofence_service.dart';

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFFFFFFF);
  Color get textBlack => isDark ? Colors.white : const Color(0xFF000000);
  Color get textDark => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textGray => isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get textMuted => isDark ? const Color(0xFF888888) : const Color(0xFFA1A1AA);
  Color get cardFill => isDark
      ? const Color(0xFF1F1F23)
      : const Color.fromRGBO(131, 131, 131, 0.07);
  Color get darkBorder => isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
  Color get toggleActiveBg => isDark ? const Color(0xFF27272A) : Colors.white;
}

class _T {
  static const List<Color> gradient = [
    Color(0xFFFF8A00),
    Color(0xFFFA6A00),
    Color(0xFFF54900),
  ];
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeBorder = Color(0xFFFFA500);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color green = Color(0xFF22C55E);
  static const Color greenDeep = Color(0xFF166534);
  static const Color red = Color(0xFFEF4444);

  static const double r18 = 18;
  static const double r20 = 20;
  static const double r24 = 24;

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: gradient,
    stops: [0.0, 0.5, 1.0],
  );
}

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabSwitch;
  final VoidCallback? onClockAction;
  final Employee? initialEmployee;

  const DashboardScreen({
    super.key,
    this.onTabSwitch,
    this.onClockAction,
    this.initialEmployee,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  Employee? _employee;
  bool _isClockedIn = false;
  String _clockInTime = '--:--';
  String _clockOutTime = '--:--';
  bool _isLoadingAttendance = true;
  Timer? _durationTimer;
  String _elapsedDuration = '00:00:00';
  DateTime? _rawClockInDateTime;

  String? _photoUrl;

  StreamSubscription<QuerySnapshot>? _attendanceSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _employeeSub;

  String? _initError;

  // ══════════════════════════════════════════════════════════════
  // ✅ LOCATION / ROLE / WFH STATE (auto-detected)
  // ══════════════════════════════════════════════════════════════
  bool _isInRange = false;
  bool _wfhAccess = false;
  bool _isDriver = false;
  bool _checkingLocation = true;
  String _role = '';
  String _department = '';
  double? _distanceMeters;

  // ✅ Pwedeng mag-clock kung nasa range OR WFH OR Driver
  bool get _canClock => _isInRange || _wfhAccess || _isDriver;

  // ✅ WFH mode = naka-WFH pero wala sa office zone
  bool get _isWfhMode => _wfhAccess && !_isInRange;

  // ✅ Driver mode = driver/rider pero wala sa office zone
  bool get _isDriverMode => _isDriver && !_isInRange && !_wfhAccess;

  final DateTime _payslipMonth =
  DateTime(DateTime.now().year, DateTime.now().month - 1);
  double? _payslipAmount;
  bool _payslipLoading = true;
  bool _payslipError = false;

  bool get _isPayslipVisible {
    final now = DateTime.now();
    final firstDayAfterPayslipMonth =
    DateTime(_payslipMonth.year, _payslipMonth.month + 1, 1);
    return !now.isBefore(firstDayAfterPayslipMonth);
  }

  String? get _employeeId {
    final id = _employee?.employeeId ?? widget.initialEmployee?.employeeId;
    if (id != null && id.isNotEmpty) return id;

    final fallback = _employee?.id ?? widget.initialEmployee?.id;
    if (fallback != null && fallback.isNotEmpty) return fallback;

    return null;
  }

  String? get _employeeDocId {
    final id = _employee?.id ?? widget.initialEmployee?.id;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  @override
  void initState() {
    super.initState();
    try {
      _employee = widget.initialEmployee;
      _photoUrl = _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;

      // ✅ Seed initial values mula sa Employee model
      _role = _employee?.position ?? '';
      _department = _employee?.department ?? '';
      _wfhAccess = _readWfhFromEmployee();
      _isDriver = _isDriverRole(_role, _department);

      _safeInit();
    } catch (e, st) {
      debugPrint('❌ Dashboard initState error: $e\n$st');
      _initError = e.toString();
      _isLoadingAttendance = false;
      _checkingLocation = false;
    }
  }

  bool _readWfhFromEmployee() {
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) return false;
    try {
      final dynamic v = (emp as dynamic).wfhAccess;
      if (v is bool) return v;
      if (v != null) return v.toString().toLowerCase() == 'true';
    } catch (_) {}
    return false;
  }

  bool _isDriverRole(String role, String dept) {
    final r = role.toLowerCase().trim();
    final d = dept.toLowerCase().trim();
    return r.contains('driver') ||
        r.contains('rider') ||
        d.contains('driver') ||
        d.contains('rider');
  }

  Future<void> _safeInit() async {
    try {
      await _loadTodayAttendance().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⚠️ Attendance load timeout');
          if (mounted) setState(() => _isLoadingAttendance = false);
        },
      );
    } catch (e) {
      debugPrint('❌ _loadTodayAttendance: $e');
      if (mounted) setState(() => _isLoadingAttendance = false);
    }

    _startAttendanceStream();
    _startEmployeeListener();
    _refreshLocation();

    try {
      await _loadPayslipAmount();
    } catch (e) {
      debugPrint('❌ _loadPayslipAmount: $e');
    }

    try {
      await _loadEmployeePhoto();
    } catch (e) {
      debugPrint('❌ _loadEmployeePhoto: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ✅ REALTIME EMPLOYEE LISTENER
  // ══════════════════════════════════════════════════════════════
  void _startEmployeeListener() {
    final docId = _employeeDocId;
    if (docId == null || docId.isEmpty) {
      debugPrint('⚠️ [Dashboard] Walang employee doc ID — skip listener');
      return;
    }

    _employeeSub?.cancel();
    _employeeSub = FirebaseFirestore.instance
        .collection('employees')
        .doc(docId)
        .snapshots()
        .listen(
          (snap) {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;

        final rawWfh = data['wfhAccess'];
        final wfh = rawWfh is bool
            ? rawWfh
            : (rawWfh?.toString().toLowerCase() == 'true');

        final newRole = (data['role'] ?? data['position'] ?? _role).toString();
        final newDept = (data['department'] ?? _department).toString();
        final newIsDriver = _isDriverRole(newRole, newDept);

        debugPrint('🏠 [Dashboard] Live: wfh=$wfh, role="$newRole", '
            'dept="$newDept", isDriver=$newIsDriver');

        final changed =
            wfh != _wfhAccess || newIsDriver != _isDriver || newRole != _role;

        if (changed) {
          setState(() {
            _wfhAccess = wfh;
            _role = newRole;
            _department = newDept;
            _isDriver = newIsDriver;
          });
        }
      },
      onError: (e) => debugPrint('❌ [Dashboard] Employee listener error: $e'),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ✅ AUTO LOCATION CHECK
  // ══════════════════════════════════════════════════════════════
  Future<void> _refreshLocation() async {
    if (mounted) setState(() => _checkingLocation = true);

    try {
      debugPrint('📍 [Dashboard] Checking geofence...');
      final result = await GeofenceService.instance
          .checkGeofence()
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      debugPrint('📍 [Dashboard] inside=${result.isInside}, '
          'distance=${result.distanceMeters}m');

      setState(() {
        _isInRange = result.isInside;
        _distanceMeters = result.distanceMeters;
        _checkingLocation = false;
      });
    } catch (e) {
      debugPrint('❌ [Dashboard] Geofence error: $e');
      if (!mounted) return;
      setState(() => _checkingLocation = false);
    }
  }

  void _startAttendanceStream() {
    final employeeId = _employeeId;
    if (employeeId == null) {
      debugPrint('⚠️ Dashboard: No employee ID — skipping attendance stream');
      return;
    }

    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    debugPrint(
        '📡 [Dashboard] Querying -> employee_id: $employeeId, date: $todayStr');

    _attendanceSub?.cancel();
    _attendanceSub = FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: employeeId)
        .where('date', isEqualTo: todayStr)
        .snapshots()
        .listen(
          (snapshot) {
        if (!mounted) return;
        debugPrint(
            '📡 [Dashboard] Live update — ${snapshot.docs.length} logs found');
        _processAttendanceDocs(snapshot.docs);
      },
      onError: (e) {
        debugPrint('📡 [Dashboard] Stream error: $e');
      },
    );
  }

  String? _extractTimeString(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      return rawTime.trim();
    }

    final rawTs = data['timestamp'];
    DateTime? dt;

    if (rawTs is Timestamp) {
      dt = rawTs.toDate().toLocal();
    } else if (rawTs is String && rawTs.trim().isNotEmpty) {
      dt = DateTime.tryParse(rawTs.trim())?.toLocal();
    } else if (rawTs is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTs);
    }

    if (dt != null) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }

    return null;
  }

  DateTime? _extractDateTime(Map<String, dynamic> data) {
    final rawTime = data['time'];
    if (rawTime is String && rawTime.trim().isNotEmpty) {
      final parts = rawTime.trim().split(':');
      if (parts.length >= 2) {
        try {
          final now = DateTime.now();
          return DateTime(
            now.year,
            now.month,
            now.day,
            int.parse(parts[0]),
            int.parse(parts[1]),
            parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
          );
        } catch (_) {}
      }
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

  // ══════════════════════════════════════════════════════════════
  // ✅ PROCESS ATTENDANCE DOCS
  // Iterate through sorted docs (ascending). Ang PINAKAHULING event
  // ang mag-dedetermine ng current state:
  //   • Pinakahuling event = IN  → clocked in, _clockOutTime = '--:--'
  //   • Pinakahuling event = OUT → clocked out
  // ══════════════════════════════════════════════════════════════
  void _processAttendanceDocs(List<QueryDocumentSnapshot> docs) {
    if (!mounted) return;

    String? latestInTime;
    String? latestOutTime;
    bool clockedInState = false;
    DateTime? parsedInDateTime;

    if (docs.isNotEmpty) {
      final sortedDocs = [...docs];
      sortedDocs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aTime = _extractDateTime(aData) ?? DateTime(2000);
        final bTime = _extractDateTime(bData) ?? DateTime(2000);
        return aTime.compareTo(bTime);
      });

      for (final doc in sortedDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['type']?.toString().toUpperCase();
        final timeVal = _extractTimeString(data) ?? '--:--';

        if (type == 'IN' || type == 'CLOCK_IN') {
          latestInTime = _formatTimeTo12Hour(timeVal);
          // ✅ FIX: reset ang lumang clock-out. Kapag naka-clock in
          // ulit, hindi na valid yung dating OUT time — bagong session na.
          latestOutTime = null;
          clockedInState = true;
          try {
            final parts = timeVal.split(':');
            if (parts.length >= 2) {
              final now = DateTime.now();
              parsedInDateTime = DateTime(
                now.year,
                now.month,
                now.day,
                int.parse(parts[0]),
                int.parse(parts[1]),
                parts.length > 2 ? int.parse(parts[2].substring(0, 2)) : 0,
              );
            }
          } catch (_) {}
        } else if (type == 'OUT' || type == 'CLOCK_OUT') {
          latestOutTime = _formatTimeTo12Hour(timeVal);
          clockedInState = false;
          parsedInDateTime = null;
        }
      }
    }

    setState(() {
      _isClockedIn = clockedInState;
      _clockInTime = latestInTime ?? '--:--';
      _clockOutTime = latestOutTime ?? '--:--';
      _rawClockInDateTime = parsedInDateTime;
      _isLoadingAttendance = false;
    });

    if (_isClockedIn) {
      if (_durationTimer == null || !_durationTimer!.isActive) {
        _startElapsedTimer();
      }
    } else {
      _durationTimer?.cancel();
      _durationTimer = null;
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _attendanceSub?.cancel();
    _employeeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeePhoto() async {
    try {
      final empId = _employee?.id ?? widget.initialEmployee?.id;
      if (empId == null || empId.isEmpty) {
        debugPrint('⚠️ No employee ID for photo load');
        return;
      }

      debugPrint('📸 Loading photo for employee: $empId');
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(empId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) {
        debugPrint('⚠️ Employee document not found');
        return;
      }

      final data = doc.data();
      if (data == null) return;

      final url = data['photoUrl']?.toString();
      if (mounted && url != null && url.isNotEmpty && url != '—') {
        setState(() => _photoUrl = url);
        debugPrint('✅ Photo loaded (${url.length} chars)');
      } else {
        debugPrint('⚠️ No photoUrl in document');
      }
    } catch (e) {
      debugPrint('❌ Error loading photo: $e');
    }
  }

  void _startElapsedTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rawClockInDateTime != null && _isClockedIn) {
        final now = DateTime.now();
        final difference = now.difference(_rawClockInDateTime!);
        final hours = difference.inHours.toString().padLeft(2, '0');
        final minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
        final seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
        if (mounted) {
          setState(() {
            _elapsedDuration = '$hours:$minutes:$seconds';
          });
        }
      }
    });
  }

  Future<void> loadTodayAttendance() async => _loadTodayAttendance();
  Future<void> loadPayslipAmount() async => _loadPayslipAmount();

  /// Public method para sa manual refresh mula sa MainScreen.
  Future<void> refreshAll() async {
    await _loadTodayAttendance();
    await _loadEmployeePhoto();
    await _refreshLocation();
  }

  Future<void> _loadTodayAttendance() async {
    if (!mounted) return;
    setState(() => _isLoadingAttendance = true);
    try {
      final employeeId = _employeeId;
      if (employeeId == null) {
        debugPrint('⚠️ Walang employee ID — skipping attendance load');
        if (mounted) setState(() => _isLoadingAttendance = false);
        return;
      }

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      debugPrint(
          '🔄 [Dashboard] Manual load -> employee_id: $employeeId, date: $todayStr');

      final snapshot = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: employeeId)
          .where('date', isEqualTo: todayStr)
          .get()
          .timeout(const Duration(seconds: 10));

      debugPrint(
          '🔄 [Dashboard] Manual load found ${snapshot.docs.length} logs');
      _processAttendanceDocs(snapshot.docs);
    } catch (e) {
      debugPrint('Error loading today attendance: $e');
      if (mounted) setState(() => _isLoadingAttendance = false);
    }
  }

  String _formatTimeTo12Hour(String t) {
    try {
      if (t.contains('AM') || t.contains('PM')) return t;
      final parts = t.split(':');
      if (parts.length < 2) return t;
      int h = int.parse(parts[0]);
      final m = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      if (h == 0) h = 12;
      if (h > 12) h -= 12;
      return '${h.toString().padLeft(2, '0')}:$m $period';
    } catch (_) {
      return t;
    }
  }

  Future<void> _loadPayslipAmount() async {
    if (!mounted) return;
    setState(() {
      _payslipLoading = true;
      _payslipError = false;
    });
    try {
      final employeeId = _employeeId;
      if (employeeId == null) {
        if (mounted) {
          setState(() {
            _payslipAmount = null;
            _payslipLoading = false;
          });
        }
        return;
      }
      final double? amount =
      await _fetchPayslipFromBackend(employeeId, _payslipMonth);
      if (!mounted) return;
      setState(() {
        _payslipAmount = amount;
        _payslipLoading = false;
      });
    } catch (e) {
      debugPrint('Payslip fetch error: $e');
      if (!mounted) return;
      setState(() {
        _payslipAmount = null;
        _payslipError = true;
        _payslipLoading = false;
      });
    }
  }

  Future<double?> _fetchPayslipFromBackend(
      String employeeId, DateTime month) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return null;
  }

  String _formatPeso(double amount) {
    final wholeStr = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < wholeStr.length; i++) {
      final posFromEnd = wholeStr.length - i;
      buf.write(wholeStr[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '\u20b1${buf.toString()}';
  }

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _payslipMonthLabel =>
      '${_monthNames[_payslipMonth.month - 1]} ${_payslipMonth.year}';

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text('May error sa dashboard',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_initError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _initError = null);
                    _safeInit();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: _T.orange,
          onRefresh: refreshAll,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(tc),
                      const SizedBox(height: 20),
                      _buildStatusBanner(),
                      const SizedBox(height: 24),
                      _buildToggle(tc),
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        'Location Status',
                        tc: tc,
                        trailing: _buildGpsTag(tc),
                      ),
                      const SizedBox(height: 12),
                      _buildLocationCard(tc),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Shortcuts', tc: tc),
                      const SizedBox(height: 12),
                      _buildShortcutsGrid(tc),
                      if (_isPayslipVisible) ...[
                        const SizedBox(height: 24),
                        _buildSectionTitle(
                          'Recent Payslip',
                          tc: tc,
                          viewAll: true,
                          onViewAllTap: () => widget.onTabSwitch?.call(4),
                        ),
                        const SizedBox(height: 12),
                        _buildPayslipCard(tc),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: _buildFloatingAction(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc) {
    final name =
        _employee?.firstName ?? widget.initialEmployee?.firstName ?? 'Employee';
    final lastName =
        _employee?.lastName ?? widget.initialEmployee?.lastName ?? '';
    final photo =
        _photoUrl ?? _employee?.photoUrl ?? widget.initialEmployee?.photoUrl;

    return Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tc.darkBorder, width: 1.15),
          ),
          child: ClipOval(
            child: _buildAvatarContent(photo, name),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HI, ${name.toUpperCase()} ${lastName.toUpperCase()}',
                style: TextStyle(
                  fontSize: 10,
                  color: tc.textGray,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'Employee Dashboard',
                    style: TextStyle(
                      fontSize: 14,
                      color: tc.textBlack,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_wfhAccess) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _T.green),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_work_rounded,
                              size: 10, color: _T.greenDeep),
                          SizedBox(width: 4),
                          Text(
                            'WFH',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _T.greenDeep,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_isDriver && !_wfhAccess) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF3B82F6)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_shipping_rounded,
                              size: 10, color: Color(0xFF1E40AF)),
                          SizedBox(width: 4),
                          Text(
                            'DRIVER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E40AF),
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
        GestureDetector(
          onTap: refreshAll,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tc.cardFill,
              border: Border.all(color: _T.orangeBorder, width: 1.15),
            ),
            child: const Icon(Icons.refresh_rounded,
                color: _T.orange, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarContent(String? photo, String name) {
    final hasPhoto = photo != null && photo.isNotEmpty && photo != '—';

    if (!hasPhoto) return _avatarFallback(name);

    if (photo!.startsWith('data:image')) {
      try {
        final b64 = photo.split(',').last;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          width: 45,
          height: 45,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(name),
        );
      } catch (e) {
        debugPrint('❌ base64 decode error: $e');
        return _avatarFallback(name);
      }
    }

    if (photo.startsWith('http')) {
      return Image.network(
        photo,
        width: 45,
        height: 45,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: _T.orange,
            alignment: Alignment.center,
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _avatarFallback(name),
      );
    }

    return _avatarFallback(name);
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _T.orange,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'U',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final String statusText;
    final String subtitle;
    final Color accentColor;

    if (_isClockedIn) {
      statusText = 'clocked in.';
      subtitle =
      'Our system verified your location. You are ready to go.';
      accentColor = _T.orange;
    } else if (_checkingLocation) {
      statusText = 'verifying...';
      subtitle = 'Kinukuha ang iyong lokasyon. Maghintay lang.';
      accentColor = _T.orange;
    } else if (_isWfhMode) {
      statusText = 'on WFH mode.';
      subtitle =
      'Work-from-home access is active. You can clock in anytime.';
      accentColor = _T.green;
    } else if (_isDriverMode) {
      statusText = 'on field duty.';
      subtitle = 'Driver/Rider mode — you can clock in from anywhere.';
      accentColor = const Color(0xFF3B82F6);
    } else if (_isInRange) {
      statusText = 'clocked out.';
      subtitle = 'You are inside the authorized zone. Ready to clock in.';
      accentColor = _T.orange;
    } else {
      statusText = 'out of range.';
      subtitle =
      'Clock in from the authorized zone or ask admin for WFH access.';
      accentColor = _T.red;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_T.r24),
        border: Border.all(color: _T.orangeBorder, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_T.r24 - 1.5),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF3A3A3A),
                      Color(0xFF1A1A1A),
                      Color(0xFF0D0D0D)
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _SilkPainter())),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      children: [
                        const TextSpan(text: 'You are currently\n'),
                        TextSpan(
                          text: statusText,
                          style: TextStyle(color: accentColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFA1A1AA),
                        height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(_ThemeColors tc) {
    final clocked = _isClockedIn;
    final timeIn = _clockInTime;
    final timeOut = _clockOutTime;
    final canAction = _canClock;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_T.r18),
        gradient: _T.brandGradient,
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: (clocked || !canAction) ? null : widget.onClockAction,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock In',
                time: _isLoadingAttendance ? 'Loading...' : timeIn,
                active: true,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
                locked: !canAction,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: (!clocked || !canAction) ? null : widget.onClockAction,
              behavior: HitTestBehavior.opaque,
              child: _toggleTab(
                tc: tc,
                label: 'Clock Out',
                time: _isLoadingAttendance ? 'Loading...' : timeOut,
                active: false,
                inactiveTimeColor: Colors.white,
                inactiveLabelColor: Colors.white,
                locked: !canAction,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleTab({
    required _ThemeColors tc,
    required String label,
    required String time,
    required bool active,
    required Color inactiveLabelColor,
    required Color inactiveTimeColor,
    bool locked = false,
  }) {
    return Opacity(
      opacity: locked ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? tc.toggleActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active ? Border.all(color: _T.orangeBorder, width: 1) : null,
          boxShadow: active
              ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: active ? tc.textBlack : inactiveLabelColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              locked ? 'Locked' : time,
              style: TextStyle(
                fontSize: 11,
                color: locked
                    ? _T.red
                    : (active ? tc.textMuted : inactiveTimeColor),
                fontWeight: locked ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
      String title, {
        required _ThemeColors tc,
        Widget? trailing,
        bool viewAll = false,
        VoidCallback? onViewAllTap,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: tc.textBlack,
          ),
        ),
        if (trailing != null) trailing,
        if (viewAll)
          GestureDetector(
            onTap: onViewAllTap,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 12,
                  color: _T.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGpsTag(_ThemeColors tc) {
    final label = _checkingLocation
        ? 'Verifying'
        : (_isWfhMode
        ? 'Remote GPS'
        : (_isDriverMode ? 'Field GPS' : 'Live GPS'));
    final icon = _checkingLocation
        ? Icons.gps_fixed_rounded
        : (_isWfhMode
        ? Icons.home_work_rounded
        : (_isDriverMode
        ? Icons.local_shipping_rounded
        : Icons.near_me_rounded));

    return Row(
      children: [
        Icon(icon, size: 12, color: tc.textBlack),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: tc.textBlack,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationCard(_ThemeColors tc) {
    final Color dotColor;
    final Color borderColor;
    final Color gradientStart;
    final Color gradientEnd;
    final IconData leadingIcon;
    final String title;
    final String subtitle;
    final Color subtitleColor;

    if (_checkingLocation) {
      dotColor = tc.textMuted;
      borderColor = _T.orangeBorder;
      gradientStart = _T.orange;
      gradientEnd = _T.orange;
      leadingIcon = Icons.gps_fixed_rounded;
      title = 'Verifying location...';
      subtitle = 'Kinukuha ang GPS position';
      subtitleColor = _T.orange;
    } else if (_isWfhMode) {
      dotColor = _T.green;
      borderColor = _T.green;
      gradientStart = _T.green;
      gradientEnd = const Color(0xFF16A34A);
      leadingIcon = Icons.home_work_rounded;
      title = 'Work From Home';
      subtitle = 'Allowed — clock in from anywhere';
      subtitleColor = _T.green;
    } else if (_isDriverMode) {
      dotColor = const Color(0xFF3B82F6);
      borderColor = const Color(0xFF3B82F6);
      gradientStart = const Color(0xFF3B82F6);
      gradientEnd = const Color(0xFF1E40AF);
      leadingIcon = Icons.local_shipping_rounded;
      title = 'Field Duty';
      subtitle = 'Driver/Rider — clock in allowed';
      subtitleColor = const Color(0xFF3B82F6);
    } else if (_isInRange) {
      dotColor = _T.lime;
      borderColor = _T.orangeBorder;
      gradientStart = _T.orange;
      gradientEnd = _T.orange;
      leadingIcon = Icons.location_on_rounded;
      title = 'HQ Main Office';
      subtitle = 'Inside Authorized Zone';
      subtitleColor = _T.lime;
    } else {
      dotColor = _T.red;
      borderColor = _T.red;
      gradientStart = _T.red;
      gradientEnd = const Color(0xFFB91C1C);
      leadingIcon = Icons.location_off_rounded;
      title = 'Outside Authorized Zone';
      subtitle = _distanceMeters != null
          ? '${_distanceMeters!.toStringAsFixed(0)}m from office'
          : 'Hindi ka nasa work zone';
      subtitleColor = _T.red;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: borderColor, width: 1.15),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [gradientStart, gradientEnd],
                  ),
                  shape: BoxShape.circle,
                ),
                child: _checkingLocation
                    ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Icon(leadingIcon, color: Colors.white, size: 22),
              ),
              if (!_checkingLocation)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: tc.textBlack,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: subtitleColor,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsGrid(_ThemeColors tc) {
    final items = [
      (Icons.history_rounded, 'Logs', _T.orange,
          () => widget.onTabSwitch?.call(1)),
      (Icons.calendar_month_rounded, 'Leaves', _T.orangeBorder,
          () => widget.onTabSwitch?.call(2)),
      (Icons.person_rounded, 'Profile', _T.orange,
          () => widget.onTabSwitch?.call(3)),
    ];

    return Row(
      children: items.map((item) {
        final isLast = item == items.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 12),
            child: GestureDetector(
              onTap: item.$4,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
                decoration: BoxDecoration(
                  color: tc.cardFill,
                  borderRadius: BorderRadius.circular(_T.r20),
                  border: Border.all(color: _T.orangeBorder, width: 1.15),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: _T.brandGradient,
                        shape: BoxShape.circle,
                        border: Border.all(color: _T.orange, width: 1.15),
                      ),
                      child: Icon(item.$1, color: Colors.white, size: 20),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: item.$3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayslipCard(_ThemeColors tc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.cardFill,
        borderRadius: BorderRadius.circular(_T.r20),
        border: Border.all(color: _T.orange, width: 1.15),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: _T.brandGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: _T.orange.withValues(alpha: 0.2), width: 1.15),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _payslipMonthLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: tc.textBlack,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                _buildPayslipAmountText(tc),
              ],
            ),
          ),
          if (_payslipAmount != null && !_payslipLoading && !_payslipError)
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: _T.orange, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            )
          else if (_payslipError)
            GestureDetector(
              onTap: _loadPayslipAmount,
              behavior: HitTestBehavior.opaque,
              child: const Icon(Icons.refresh_rounded,
                  color: _T.orange, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildPayslipAmountText(_ThemeColors tc) {
    if (_payslipLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: _T.orange),
      );
    }
    if (_payslipError) {
      return const Text(
        'Hindi makuha ang sahod ngayon',
        style: TextStyle(fontSize: 12, color: Colors.redAccent),
      );
    }
    if (_payslipAmount == null) {
      return Text(
        'Wala pang available na payslip',
        style: TextStyle(fontSize: 12, color: tc.textGray),
      );
    }
    return Text(
      'Amount: ${_formatPeso(_payslipAmount!)}',
      style: TextStyle(fontSize: 12, color: tc.textGray),
    );
  }

  Widget _buildFloatingAction() {
    if (!_isClockedIn) return const SizedBox.shrink();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          debugPrint('🟢 Floating Clock Out button tapped!');
          widget.onClockAction?.call();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_T.r18),
            gradient: _T.brandGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8A00).withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clock Out (Tap to proceed)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.timer_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        'Duty Time: $_elapsedDuration',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SilkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = -5; i < 20; i++) {
      final path = Path();
      final startX = i * 22.0;
      path.moveTo(startX, 0);
      path.cubicTo(
        startX + 30, size.height * 0.3,
        startX - 10, size.height * 0.7,
        startX + 20, size.height,
      );
      canvas.drawPath(path, paint);
    }

    final glowPaint = Paint()
      ..color = const Color(0xFFFF8A00).withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 1.1), 90, glowPaint);
  }

  @override
  bool shouldRepaint(_SilkPainter old) => false;
}