// lib/screens/attendance_history_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
// ❌ REMOVED: employee_hours_service.dart
// ❌ REMOVED: work_hours_summary_card.dart
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

class _Extra {
  static const Color purple = Color(0xFFA78BFA);
  static const Color lime = Color(0xFFC4FF0A);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : const Color(0xFFF7F7F7);
  Color get card => isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get cardBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get statBg => isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF);
  Color get statBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get statLabel =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF666666);
  Color get mobileCardBg =>
      isDark ? const Color(0xFF1A1A1D) : const Color(0xFFF8F8F8);
  Color get mobileCardBorder =>
      isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE0E0E0);
  Color get mobileRowDivider =>
      isDark ? const Color(0xFF2A2A2E) : const Color(0xFFE0E0E0);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF71717A);
  Color get emptyIcon =>
      isDark ? const Color(0x33FFFFFF) : const Color(0xFFD1D5DB);
  Color get emptyTitle =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF6B7280);
  Color get emptySubtitle =>
      isDark ? const Color(0xFF888888) : const Color(0xFF9CA3AF);
  Color get refreshBg => isDark ? const Color(0xFF18181B) : Colors.white;
}

class AttendanceHistoryScreen extends StatefulWidget {
  final Employee? initialEmployee;
  final VoidCallback? onBack;

  const AttendanceHistoryScreen({
    super.key,
    this.initialEmployee,
    this.onBack,
  });

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {
  Employee? _employee;

  List<Attendance> _localRecords = [];
  List<Map<String, dynamic>> _loginLogs = [];
  List<Map<String, dynamic>> _logoutLogs = [];
  List<Map<String, dynamic>> _combined = [];

  bool _loading = true;
  bool _syncing = false;
  int _pendingCount = 0;
  String? _error;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription<QuerySnapshot>? _remoteAttendanceSub;

  late TabController _tabController;

  // ❌ REMOVED: Work hours summary state

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: kIsWeb ? 3 : 1, vsync: this);

    if (!kIsWeb) {
      _syncSub = SyncService.instance.events.listen((e) async {
        if (!mounted) return;
        setState(() => _pendingCount = e.pendingCount);
        if (e.type == SyncEventType.syncDone) {
          await _loadData();
          if (e.syncedCount > 0) {
            _snack('✓ ${e.syncedCount} record(s) synced', AppColors.success);
          }
        }
      });
      _connectSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (mounted && online) _sync();
          });
      _attendanceSub =
          DatabaseService.instance.onAttendanceChanged.listen((_) {
            if (mounted) _loadData();
          });

      _startRemoteAttendanceListener();
    }

    _loadData();
    if (!kIsWeb) _sync();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncSub?.cancel();
    _connectSub?.cancel();
    _attendanceSub?.cancel();
    _remoteAttendanceSub?.cancel();
    super.dispose();
  }

  // ❌ REMOVED: _loadHoursSummary()

  void _startRemoteAttendanceListener() {
    _resolveEmployeeId().then((empId) {
      if (empId == null || empId.isEmpty) return;
      if (!mounted) return;

      _remoteAttendanceSub?.cancel();
      _remoteAttendanceSub = FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: empId)
          .snapshots()
          .listen(
            (snap) {
          if (!mounted) return;
          _loadData();
          // ❌ REMOVED: _loadHoursSummary();
        },
        onError: (e) => debugPrint('❌ Remote listener error: $e'),
      );
    });
  }

  Future<String?> _resolveEmployeeId() async {
    final initId = widget.initialEmployee?.employeeId ??
        widget.initialEmployee?.id;
    if (initId != null && initId.isNotEmpty) return initId;

    final secId = await SecurityService.instance.getCurrentEmployeeId();
    if (secId != null && secId.isNotEmpty) return secId;
    return null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (kIsWeb) {
        await _loadWebData();
      } else {
        await _loadMobileData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadWebData() async {
    final emp = widget.initialEmployee;
    final empId = emp?.employeeId ?? emp?.id ?? '';

    try {
      Query loginQuery = FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: 'login');
      if (empId.isNotEmpty) {
        loginQuery = loginQuery.where('employee_id', isEqualTo: empId);
      }

      Query logoutQuery = FirebaseFirestore.instance
          .collection('activity_logs')
          .where('type', isEqualTo: 'logout');
      if (empId.isNotEmpty) {
        logoutQuery = logoutQuery.where('employee_id', isEqualTo: empId);
      }

      final results = await Future.wait([
        loginQuery.get(),
        logoutQuery.get(),
      ]);

      int tsSort(Map<String, dynamic> a, Map<String, dynamic> b) {
        final ta = a['timestamp'];
        final tb = b['timestamp'];
        if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
        return 0;
      }

      final logins = results[0]
          .docs
          .map((d) => {'_docId': d.id, ...d.data() as Map<String, dynamic>})
          .toList()
        ..sort(tsSort);

      final logouts = results[1]
          .docs
          .map((d) => {'_docId': d.id, ...d.data() as Map<String, dynamic>})
          .toList()
        ..sort(tsSort);

      final combined = <Map<String, dynamic>>[];
      final usedLogoutIds = <String>{};

      for (final login in logins) {
        final ts = login['timestamp'];
        DateTime? loginDt;
        if (ts is Timestamp) loginDt = ts.toDate();
        final loginDateStr =
        loginDt != null ? DateFormat('yyyy-MM-dd').format(loginDt) : '';
        final eid = (login['employee_id'] ?? '').toString();

        Map<String, dynamic>? matchedLogout;
        for (final logout in logouts) {
          if (usedLogoutIds.contains(logout['_docId'])) continue;
          final lts = logout['timestamp'];
          DateTime? logoutDt;
          if (lts is Timestamp) logoutDt = lts.toDate();
          final logoutDateStr =
          logoutDt != null ? DateFormat('yyyy-MM-dd').format(logoutDt) : '';
          final leid = (logout['employee_id'] ?? '').toString();

          if (leid == eid && logoutDateStr == loginDateStr) {
            matchedLogout = logout;
            usedLogoutIds.add(logout['_docId'].toString());
            break;
          }
        }

        combined.add({
          'date': loginDateStr,
          'employee_id': eid,
          'employee_name': (login['employee_name'] ?? '').toString(),
          'device': (login['device'] ?? '').toString(),
          'login_ts': login['timestamp'],
          'logout_ts': matchedLogout?['timestamp'],
          'has_out': matchedLogout != null,
        });
      }

      if (mounted) {
        setState(() {
          _employee = emp;
          _loginLogs = logins;
          _logoutLogs = logouts;
          _combined = combined;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('_loadWebData error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMobileData() async {
    final empId = await _resolveEmployeeId();
    Employee? emp = widget.initialEmployee;
    List<Attendance> localRecords = [];
    List<Attendance> remoteRecords = [];
    int pending = 0;

    if (empId != null) {
      try {
        emp = await DatabaseService.instance.getEmployeeById(empId);
        localRecords = await DatabaseService.instance
            .getAttendanceByEmployee(empId, limit: 90);
        pending = await SyncService.instance.getPendingCount();
      } catch (e) {
        debugPrint('⚠️ Local DB read failed: $e');
      }

      remoteRecords = await _fetchRemoteAttendance(empId);
    }

    final merged = _mergeAttendance(localRecords, remoteRecords);

    if (mounted) {
      setState(() {
        _employee = emp ?? widget.initialEmployee;
        _localRecords = merged;
        _pendingCount = pending;
        _loading = false;
      });
    }
  }

  Future<List<Attendance>> _fetchRemoteAttendance(String empId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('attendance_logs')
          .where('employee_id', isEqualTo: empId)
          .get();

      final Map<String, List<Map<String, dynamic>>> byDate = {};
      for (final doc in snap.docs) {
        final d = doc.data();
        final date = (d['date'] ?? '').toString();
        if (date.isEmpty) continue;
        byDate.putIfAbsent(date, () => []).add({...d, '_docId': doc.id});
      }

      final records = <Attendance>[];
      for (final entry in byDate.entries) {
        final date = entry.key;
        final logs = entry.value;

        logs.sort((a, b) {
          final ta = (a['time'] ?? '').toString();
          final tb = (b['time'] ?? '').toString();
          return ta.compareTo(tb);
        });

        String? timeIn;
        String? timeOut;
        for (final log in logs) {
          final type = (log['type'] ?? '').toString().toUpperCase();
          final time = (log['time'] ?? '').toString();
          if (type == 'IN' || type == 'CLOCK_IN') {
            timeIn = time;
            timeOut = null;
          } else if (type == 'OUT' || type == 'CLOCK_OUT') {
            if (timeIn != null) timeOut = time;
          }
        }

        if (timeIn == null && timeOut == null) continue;

        AttendanceStatus status = AttendanceStatus.present;
        if (timeIn != null) {
          try {
            final parts = timeIn.split(':');
            final hour = int.parse(parts[0]);
            final min = int.parse(parts.length > 1 ? parts[1] : '0');
            if (hour > 9 || (hour == 9 && min > 15)) {
              status = AttendanceStatus.late;
            }
          } catch (_) {}
        }

        AttendanceMethod method = AttendanceMethod.face;
        for (final log in logs) {
          final m = (log['verification_method'] ?? log['method'] ?? '')
              .toString()
              .toLowerCase();
          if (m.isEmpty) continue;
          if (m.contains('face')) {
            method = AttendanceMethod.face;
            break;
          } else if (m.contains('finger')) {
            method = AttendanceMethod.fingerprint;
            break;
          } else if (m.contains('pin')) {
            method = AttendanceMethod.pin;
            break;
          } else if (m.contains('qr')) {
            method = AttendanceMethod.qrCode;
            break;
          } else if (m.contains('nfc')) {
            method = AttendanceMethod.nfc;
            break;
          } else if (m.contains('manual')) {
            method = AttendanceMethod.manual;
            break;
          }
        }

        DateTime createdAt = DateTime.now();
        final rawTs = logs.first['timestamp'];
        final rawCreated = logs.first['created_at'];
        if (rawTs is Timestamp) {
          createdAt = rawTs.toDate();
        } else if (rawCreated is String && rawCreated.isNotEmpty) {
          createdAt = DateTime.tryParse(rawCreated) ?? DateTime.now();
        }

        records.add(Attendance(
          id: logs.first['_docId']?.toString() ?? 'remote_$date',
          employeeId: empId,
          date: date,
          timeIn: timeIn,
          timeOut: timeOut,
          status: status,
          method: method,
          createdAt: createdAt,
        ));
      }

      records.sort((a, b) => b.date.compareTo(a.date));
      return records;
    } catch (e) {
      debugPrint('⚠️ _fetchRemoteAttendance failed: $e');
      return [];
    }
  }

  List<Attendance> _mergeAttendance(
      List<Attendance> local, List<Attendance> remote) {
    final Map<String, Attendance> byDate = {};
    for (final r in local) {
      byDate[r.date] = r;
    }
    for (final r in remote) {
      byDate[r.date] = r;
    }
    final result = byDate.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  Future<void> _sync() async {
    if (kIsWeb || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    await DatabaseService.instance.syncLocalFilesToDatabase();
    await SyncService.instance.syncPending();
    if (mounted) setState(() => _syncing = false);
    await _loadData();
    // ❌ REMOVED: await _loadHoursSummary();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 2),
    ));
  }

  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  String _fmtTimestamp(dynamic ts) {
    if (ts == null) return '--:--';
    if (ts is Timestamp) {
      return DateFormat('hh:mm a').format(ts.toDate().toLocal());
    }
    return '--:--';
  }

  String _fmtDate(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('EEE, MMM d yyyy').format(ts.toDate().toLocal());
    }
    return '—';
  }

  String _durationFromTs(dynamic loginTs, dynamic logoutTs) {
    if (loginTs == null || loginTs is! Timestamp) return '--';
    final start = loginTs.toDate();
    final end = logoutTs is Timestamp ? logoutTs.toDate() : DateTime.now();
    final diff = end.difference(start);
    if (diff.isNegative) return '--';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (kIsWeb) _buildTabBar(tc),
            Expanded(
              child: _loading
                  ? _buildLoader(tc)
                  : _error != null
                  ? _buildError(tc)
                  : kIsWeb
                  ? _buildWebContent(tc)
                  : _buildMobileContent(tc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _handleBack,
              borderRadius: BorderRadius.circular(12),
              splashColor: Colors.white.withValues(alpha: 0.3),
              highlightColor: Colors.white.withValues(alpha: 0.15),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border:
                  Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Attendance Logs',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!kIsWeb) ...[
            if (_pendingCount > 0) ...[
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        color: AppColors.warning, size: 11),
                    const SizedBox(width: 3),
                    Text(
                      '$_pendingCount',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onTap: _syncing ? null : _sync,
              child: _syncing
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : const Icon(Icons.sync_rounded,
                  color: Colors.white, size: 22),
            ),
          ],
          if (kIsWeb)
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border:
                  Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Refresh',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(_ThemeColors tc) {
    return Container(
      color: tc.card,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.orange,
        indicatorWeight: 2,
        labelColor: AppColors.orange,
        unselectedLabelColor: tc.textSecondary,
        labelStyle:
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        tabs: const [
          Tab(text: 'All Records'),
          Tab(text: 'Logins'),
          Tab(text: 'Logouts'),
        ],
      ),
    );
  }

  Widget _buildLoader(_ThemeColors tc) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: AppColors.orange,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading records…',
          style: TextStyle(color: tc.textSecondary, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _buildError(_ThemeColors tc) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border:
          Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Failed to load records',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(color: tc.textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ❌ REMOVED: _buildHoursSummarySection()
  // ❌ REMOVED: _summaryTab()

  Widget _buildStatsRow(_ThemeColors tc) {
    final present = kIsWeb
        ? _combined.where((r) => r['has_out'] == true).length
        : _localRecords
        .where((r) => r.status == AttendanceStatus.present)
        .length;

    final late = kIsWeb
        ? _combined.where((r) => r['has_out'] == false).length
        : _localRecords
        .where((r) => r.status == AttendanceStatus.late)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Expanded(
              child:
              _statCard(tc, '$present', 'Present Days', AppColors.orange)),
          const SizedBox(width: 15),
          Expanded(child: _statCard(tc, '$late', 'Late Days', _Extra.lime)),
        ],
      ),
    );
  }

  Widget _statCard(
      _ThemeColors tc, String value, String label, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: tc.statBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.statBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: tc.statLabel,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent(_ThemeColors tc) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildCombinedList(tc),
        _buildLoginList(tc),
        _buildLogoutList(tc),
      ],
    );
  }

  Widget _buildCombinedList(_ThemeColors tc) {
    if (_combined.isEmpty) {
      return _buildEmptyState(tc, 'No attendance records found',
          subtitle: 'Login and logout activity will appear here.');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // ❌ REMOVED: _buildHoursSummarySection(tc),
        _buildStatsRow(tc),
        ..._combined.map((r) => _buildCombinedCard(tc, r)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCombinedCard(_ThemeColors tc, Map<String, dynamic> record) {
    final loginTs = record['login_ts'];
    final logoutTs = record['logout_ts'];
    final hasOut = record['has_out'] == true;
    final empName = record['employee_name'] as String? ?? '';
    final dateStr = record['date'] as String? ?? '';
    final dur = _durationFromTs(loginTs, logoutTs);

    DateTime? dt;
    if (dateStr.isNotEmpty) {
      try {
        dt = DateTime.parse(dateStr);
      } catch (_) {}
    } else if (loginTs is Timestamp) {
      dt = loginTs.toDate().toLocal();
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = dateStr == today;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? AppColors.orange.withValues(alpha: 0.45)
              : tc.cardBorder,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 60,
              decoration: BoxDecoration(
                color: isToday
                    ? AppColors.orange.withValues(alpha: 0.1)
                    : (tc.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isToday
                      ? AppColors.orange.withValues(alpha: 0.3)
                      : tc.cardBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dt != null ? DateFormat('EEE').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 9,
                      color: isToday ? AppColors.orange : tc.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    dt != null ? DateFormat('d').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isToday ? AppColors.orange : tc.textPrimary,
                    ),
                  ),
                  Text(
                    dt != null ? DateFormat('MMM').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 9,
                      color: isToday ? AppColors.orange : tc.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (empName.isNotEmpty)
                    Text(
                      empName,
                      style: TextStyle(
                        color: tc.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTimeChip(
                          'IN', _fmtTimestamp(loginTs), AppColors.success),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: tc.textSecondary,
                        ),
                      ),
                      _buildTimeChip(
                        'OUT',
                        hasOut ? _fmtTimestamp(logoutTs) : 'ACTIVE',
                        hasOut ? _Extra.purple : AppColors.orangeDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 11, color: tc.textSecondary),
                      const SizedBox(width: 4),
                      Text(dur,
                          style: TextStyle(
                              fontSize: 11, color: tc.textSecondary)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasOut
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasOut ? 'COMPLETE' : 'ACTIVE',
                          style: TextStyle(
                            fontSize: 8,
                            color: hasOut
                                ? AppColors.success
                                : AppColors.orangeDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginList(_ThemeColors tc) {
    if (_loginLogs.isEmpty) {
      return _buildEmptyState(tc, 'No login records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildCountBadge(
            '${_loginLogs.length} Login Records',
            Icons.login_rounded,
            AppColors.success,
          ),
        ),
        ..._loginLogs.map((r) => _buildActivityLogCard(tc, r, 'login')),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLogoutList(_ThemeColors tc) {
    if (_logoutLogs.isEmpty) {
      return _buildEmptyState(tc, 'No logout records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildCountBadge(
            '${_logoutLogs.length} Logout Records',
            Icons.logout_rounded,
            _Extra.purple,
          ),
        ),
        ..._logoutLogs.map((r) => _buildActivityLogCard(tc, r, 'logout')),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildActivityLogCard(
      _ThemeColors tc, Map<String, dynamic> record, String type) {
    final isLogin = type == 'login';
    final color = isLogin ? AppColors.success : _Extra.purple;
    final ts = record['timestamp'];
    final empName = (record['employee_name'] ?? '').toString();
    final device = (record['device'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(
              isLogin ? Icons.login_rounded : Icons.logout_rounded,
              color: color,
              size: 20,
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
                        _fmtDate(ts),
                        style: TextStyle(
                          color: tc.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _fmtTimestamp(ts),
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (empName.isNotEmpty) ...[
                      Icon(Icons.person_outline_rounded,
                          size: 10, color: tc.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          empName,
                          style: TextStyle(
                              fontSize: 11, color: tc.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (device.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            device.toLowerCase().contains('web')
                                ? Icons.computer_rounded
                                : Icons.phone_android_rounded,
                            size: 10,
                            color: tc.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            device,
                            style: TextStyle(
                                fontSize: 10, color: tc.textSecondary),
                          ),
                        ],
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

  Widget _buildCountBadge(String label, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileContent(_ThemeColors tc) {
    if (_localRecords.isEmpty) {
      return RefreshIndicator(
        color: AppColors.orange,
        backgroundColor: tc.refreshBg,
        onRefresh: _sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: _buildEmptyState(tc, 'No attendance records yet'),
            ),
          ],
        ),
      );
    }

    final present = _localRecords
        .where((r) => r.status == AttendanceStatus.present)
        .length;
    final late =
        _localRecords.where((r) => r.status == AttendanceStatus.late).length;

    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: tc.refreshBg,
      onRefresh: () async {
        await _sync();
        // ❌ REMOVED: await _loadHoursSummary();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          // ❌ REMOVED: _buildHoursSummarySection(tc),

          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Expanded(
                    child: _statCard(
                        tc, '$present', 'Present Days', AppColors.orange)),
                const SizedBox(width: 15),
                Expanded(
                    child:
                    _statCard(tc, '$late', 'Late Days', _Extra.lime)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Recent Logs',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.textPrimary,
              ),
            ),
          ),
          ..._localRecords.take(30).map((r) => _buildMobileCard(tc, r)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMobileCard(_ThemeColors tc, Attendance record) {
    final date = DateTime.tryParse(record.date);
    final isToday =
        record.date == DateFormat('yyyy-MM-dd').format(DateTime.now());

    Color statusColor;
    String statusLabel;
    switch (record.status) {
      case AttendanceStatus.present:
        statusColor = _Extra.lime;
        statusLabel = 'Present';
        break;
      case AttendanceStatus.late:
        statusColor = AppColors.orange;
        statusLabel = 'Late';
        break;
      default:
        statusColor = AppColors.error;
        statusLabel = 'Absent';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 15),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tc.mobileCardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.mobileCardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: tc.isDark ? 0.2 : 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: tc.mobileRowDivider, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: tc.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isToday
                          ? 'Today'
                          : (date != null
                          ? DateFormat('MMM d, yyyy').format(date)
                          : record.date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: tc.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                    Border.all(color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: statusColor == _Extra.lime
                          ? const Color(0xFF7A9900)
                          : statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 12, color: tc.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Clock In',
                            style: TextStyle(
                                fontSize: 10, color: tc.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fmt12(record.timeIn),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tc.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 12, color: tc.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Clock Out',
                            style: TextStyle(
                                fontSize: 10, color: tc.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.timeOut != null
                            ? _fmt12(record.timeOut)
                            : '--:--',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: tc.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: tc.mobileRowDivider, width: 1)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_rounded,
                    size: 12, color: tc.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Verified at Jumbo HQ',
                  style: TextStyle(fontSize: 10, color: tc.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String label, String time, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            time,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(_ThemeColors tc, String msg, {String? subtitle}) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, color: tc.emptyIcon, size: 56),
            const SizedBox(height: 16),
            Text(
              msg,
              style: TextStyle(
                color: tc.emptyTitle,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle ?? 'Records will appear here once available',
              style: TextStyle(
                color: tc.emptySubtitle,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _loadData,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.orange.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Refresh',
                    style: TextStyle(
                      color: AppColors.orangeDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}