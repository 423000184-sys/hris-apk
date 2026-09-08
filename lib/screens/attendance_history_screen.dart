// lib/screens/attendance_history_screen.dart
//
<<<<<<< HEAD
// CONVERTED FROM HTML DESIGN:
//   - Phone-container style with rounded corners
//   - Orange gradient header with back button
//   - Stats cards (Present Days / Late Days) — Present number in orange,
//     Late number in lime (#C4FF0A), matching the HTML mockup exactly.
//   - Recent logs restyled to match the mockup: bordered header row with
//     a calendar icon + date label and a status badge (Present = lime,
//     Late = orange), a Clock In / Clock Out row each with a small clock
//     icon, and a footer row with a pin icon + "Verified at Jumbo HQ",
//     separated by a hairline top border (not a full divider) — same as
//     the mockup's card sections.
//   - Removed hardcoded bottom navigation (kept as a real Scaffold screen).
//
// UPDATED: local `_C` color palette removed — every color now comes from
// the shared `AppColors` / `AppTheme` system in `theme/app_theme.dart`,
// so this screen re-skins automatically if the app theme changes.
// The mockup's one-off lime accent (#C4FF0A) is kept local since nothing
// else in the app uses it.
=======
// RESTYLED: Matches dashboard orange/dark theme.
//   - Navy black background (#0D0D0D)
//   - Orange accent (#FF8C00) replaces cyan
//   - Green for login/in, Purple for logout/out
//   - Warm card surfaces (#1A1A1A / #222222)
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../data/local/dao/sync_service.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

<<<<<<< HEAD
// A couple of one-off accents the shared palette doesn't define
// (e.g. the "logout" purple, and the mockup's lime "Present" accent).
// Kept local since they're used nowhere else.
class _Extra {
  static const Color purple = Color(0xFFA78BFA);
  static const Color lime = Color(0xFFC4FF0A);
=======
// ── Design tokens ──────────────────────────────────────────────────────────
class _C {
  static const Color navy    = Color(0xFF0D0D0D);
  static const Color card    = Color(0xFF1A1A1A);
  static const Color cardAlt = Color(0xFF222222);
  static const Color orange  = Color(0xFFFF8C00);
  static const Color orange2 = Color(0xFFFFA500);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFFFBB00);
  static const Color error   = Color(0xFFFF4D6D);
  static const Color purple  = Color(0xFFA78BFA);
  static const Color white   = Color(0xFFFFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white08 = Color(0x14FFFFFF);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}

class AttendanceHistoryScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const AttendanceHistoryScreen({super.key, this.initialEmployee});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen>
    with SingleTickerProviderStateMixin {

  Employee? _employee;

  List<Attendance> _localRecords = [];
  List<Map<String, dynamic>> _loginLogs  = [];
  List<Map<String, dynamic>> _logoutLogs = [];
  List<Map<String, dynamic>> _combined   = [];

  bool    _loading      = true;
  bool    _syncing      = false;
  int     _pendingCount = 0;
  String? _error;

  StreamSubscription? _syncSub;
  StreamSubscription? _connectSub;
  StreamSubscription? _attendanceSub;

  late TabController _tabController;

  // ── lifecycle ──────────────────────────────────────────────────────────────
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
<<<<<<< HEAD
            _snack('✓ ${e.syncedCount} record(s) synced', AppColors.success);
=======
            _snack('✓ ${e.syncedCount} record(s) synced', _C.success);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
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
    super.dispose();
  }

  // ── data loading ───────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      if (kIsWeb) {
        await _loadWebData();
      } else {
        await _loadMobileData();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadWebData() async {
    final emp   = widget.initialEmployee;
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

      final combined      = <Map<String, dynamic>>[];
      final usedLogoutIds = <String>{};

      for (final login in logins) {
        final ts = login['timestamp'];
        DateTime? loginDt;
        if (ts is Timestamp) loginDt = ts.toDate();
        final loginDateStr = loginDt != null
            ? DateFormat('yyyy-MM-dd').format(loginDt) : '';
        final eid = (login['employee_id'] ?? '').toString();

        Map<String, dynamic>? matchedLogout;
        for (final logout in logouts) {
          if (usedLogoutIds.contains(logout['_docId'])) continue;
          final lts = logout['timestamp'];
          DateTime? logoutDt;
          if (lts is Timestamp) logoutDt = lts.toDate();
          final logoutDateStr = logoutDt != null
              ? DateFormat('yyyy-MM-dd').format(logoutDt) : '';
          final leid = (logout['employee_id'] ?? '').toString();

          if (leid == eid && logoutDateStr == loginDateStr) {
            matchedLogout = logout;
            usedLogoutIds.add(logout['_docId'].toString());
            break;
          }
        }

        combined.add({
          'date'          : loginDateStr,
          'employee_id'   : eid,
          'employee_name' : (login['employee_name'] ?? '').toString(),
          'device'        : (login['device'] ?? '').toString(),
          'login_ts'      : login['timestamp'],
          'logout_ts'     : matchedLogout?['timestamp'],
          'has_out'       : matchedLogout != null,
        });
      }

      if (mounted) {
        setState(() {
          _employee   = emp;
          _loginLogs  = logins;
          _logoutLogs = logouts;
          _combined   = combined;
          _loading    = false;
        });
      }
    } catch (e) {
      debugPrint('_loadWebData error: $e');
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMobileData() async {
    final empId = await SecurityService.instance.getCurrentEmployeeId();
    Employee? emp = widget.initialEmployee;
    List<Attendance> records = [];
    int pending = 0;

    if (empId != null) {
      emp     = await DatabaseService.instance.getEmployeeById(empId);
      records = await DatabaseService.instance
          .getAttendanceByEmployee(empId, limit: 90);
      pending = await SyncService.instance.getPendingCount();
    }

    if (mounted) {
      setState(() {
        _employee     = emp;
        _localRecords = records;
        _pendingCount = pending;
        _loading      = false;
      });
    }
  }

  Future<void> _sync() async {
    if (kIsWeb || _syncing) return;
    if (mounted) setState(() => _syncing = true);
    await DatabaseService.instance.syncLocalFilesToDatabase();
    await SyncService.instance.syncPending();
    if (mounted) setState(() => _syncing = false);
    await _loadData();
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

  // ── time helpers ───────────────────────────────────────────────────────────
  String _fmt12(String? t) {
    if (t == null) return '--:--';
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) { return t; }
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
    final end   = logoutTs is Timestamp ? logoutTs.toDate() : DateTime.now();
    final diff  = end.difference(start);
    if (diff.isNegative) return '--';
    return '${diff.inHours}h ${diff.inMinutes % 60}m';
  }

<<<<<<< HEAD
=======
  String _durationStr(String? timeIn, String? timeOut, String? date) {
    if (timeIn == null || date == null) return '--';
    try {
      final start = DateTime.parse('${date}T$timeIn');
      final end   = timeOut != null
          ? DateTime.parse('${date}T$timeOut') : DateTime.now();
      final diff  = end.difference(start);
      if (diff.isNegative) return '--';
      return '${diff.inHours}h ${diff.inMinutes % 60}m';
    } catch (_) { return '--'; }
  }

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
<<<<<<< HEAD
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (kIsWeb) _buildTabBar(),
            Expanded(
              child: _loading
                  ? _buildLoader()
                  : _error != null
                  ? _buildError()
                  : kIsWeb
                  ? _buildWebContent()
                  : _buildMobileContent(),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER (Phone style, per HTML mockup's orange gradient header) ─────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: AppColors.gradientOrange, // FF8A00 → FA6A00 → F54900
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 15),
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
          // Sync indicator for mobile
          if (!kIsWeb) ...[
            if (_pendingCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_upload_outlined, color: AppColors.warning, size: 11),
                    const SizedBox(width: 3),
                    Text(
                      '$_pendingCount',
                      style: TextStyle(
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
                  : const Icon(Icons.sync_rounded, color: Colors.white, size: 22),
            ),
          ],
          if (kIsWeb)
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    const Text(
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
=======
      backgroundColor: _C.navy,
      body: Column(children: [
        _buildHeader(),
        if (kIsWeb) _buildTabBar(),
        Expanded(
          child: _loading
              ? _buildLoader()
              : _error != null
              ? _buildError()
              : kIsWeb
              ? _buildWebContent()
              : _buildMobileContent(),
        ),
      ]),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, kIsWeb ? 20 : MediaQuery.of(context).padding.top + 16, 20, 16),
      decoration: BoxDecoration(
        color: _C.card,
        border: Border(bottom: BorderSide(color: _C.white15, width: 0.5)),
      ),
      child: Row(children: [
        // Orange gradient icon — matches dashboard style
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF8C00), Color(0xFFC45E00)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Attendance History',
                style: TextStyle(
                    color: _C.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              _employee?.fullName ??
                  widget.initialEmployee?.fullName ??
                  'All Records',
              style: const TextStyle(color: _C.white40, fontSize: 12),
            ),
          ]),
        ),

        // Web: refresh button
        if (kIsWeb)
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _C.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _C.orange.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.refresh_rounded, color: _C.orange2, size: 14),
                const SizedBox(width: 6),
                Text('Refresh',
                    style: TextStyle(
                        color: _C.orange2,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),

        // Mobile: pending badge + sync
        if (!kIsWeb) ...[
          if (_pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _C.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _C.warning.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_upload_outlined, color: _C.warning, size: 11),
                const SizedBox(width: 3),
                Text('$_pendingCount',
                    style: TextStyle(
                        fontSize: 10,
                        color: _C.warning,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onTap: _syncing ? null : _sync,
            child: _syncing
                ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    color: _C.orange, strokeWidth: 2))
                : const Icon(Icons.sync_rounded, color: _C.orange, size: 22),
          ),
        ],
      ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    );
  }

  // ── TAB BAR ────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
<<<<<<< HEAD
      color: AppColors.card,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.orange,
        indicatorWeight: 2,
        labelColor: AppColors.orange,
        unselectedLabelColor: AppColors.white40,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
=======
      color: _C.card,
      child: TabBar(
        controller: _tabController,
        indicatorColor: _C.orange,
        indicatorWeight: 2,
        labelColor: _C.orange,
        unselectedLabelColor: _C.white40,
        labelStyle:
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        tabs: const [
          Tab(text: 'All Records'),
          Tab(text: 'Logins'),
          Tab(text: 'Logouts'),
        ],
      ),
    );
  }

  // ── LOADER ────────────────────────────────────────────────────────────────
  Widget _buildLoader() => Center(
<<<<<<< HEAD
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
          style: TextStyle(color: AppColors.white40, fontSize: 13),
        ),
      ],
    ),
=======
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(
              color: _C.orange, strokeWidth: 2.5)),
      const SizedBox(height: 16),
      Text('Loading records…',
          style: TextStyle(color: _C.white40, fontSize: 13)),
    ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  );

  // ── ERROR ─────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
<<<<<<< HEAD
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(
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
              style: TextStyle(color: AppColors.white40, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
=======
          color: _C.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _C.error.withOpacity(0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: _C.error, size: 40),
          const SizedBox(height: 12),
          Text('Failed to load records',
              style: TextStyle(
                  color: _C.error, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_error ?? '',
              style: TextStyle(color: _C.white40, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: _C.orange,
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    ),
  );

<<<<<<< HEAD
  // ── STATS ROW ─────────────────────────────────────────────────────────
  // Per the HTML mockup: "Present Days" number is orange, "Late Days"
  // number is lime (#C4FF0A) — both sit on a plain white/card background.
  Widget _buildStatsRow() {
    final present = kIsWeb
        ? _combined.where((r) => r['has_out'] == true).length
        : _localRecords.where((r) => r.status == AttendanceStatus.present).length;

    final late = kIsWeb
        ? _combined.where((r) => r['has_out'] == false).length
        : _localRecords.where((r) => r.status == AttendanceStatus.late).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          Expanded(child: _statCard('$present', 'Present Days', AppColors.orange)),
          const SizedBox(width: 15),
          Expanded(child: _statCard('$late', 'Late Days', _Extra.lime)),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
=======
  // ── STATS ROW ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    final total   = kIsWeb ? _combined.length  : _localRecords.length;
    final withOut = kIsWeb
        ? _combined.where((r) => r['has_out'] == true).length
        : _localRecords.where((r) => r.timeOut != null).length;
    final active  = total - withOut;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(children: [
        _StatChip(label: 'Total',     value: '$total',   color: _C.orange,  icon: Icons.list_alt_rounded),
        const SizedBox(width: 8),
        _StatChip(label: 'Completed', value: '$withOut', color: _C.success, icon: Icons.check_circle_rounded),
        const SizedBox(width: 8),
        _StatChip(label: 'Active',    value: '$active',  color: _C.purple,  icon: Icons.timelapse_rounded),
      ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    );
  }

  // ── WEB CONTENT ───────────────────────────────────────────────────────────
  Widget _buildWebContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildCombinedList(),
        _buildLoginList(),
        _buildLogoutList(),
      ],
    );
  }

  Widget _buildCombinedList() {
    if (_combined.isEmpty) {
      return _buildEmptyState(
        'No attendance records found',
        subtitle: 'Login and logout activity will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        _buildStatsRow(),
<<<<<<< HEAD
        ..._combined.map((r) => _buildCombinedCard(r)),
=======
        ..._combined.map((r) => _CombinedCard(
          record    : r,
          fmtTs     : _fmtTimestamp,
          fmtDate   : _fmtDate,
          durationTs: _durationFromTs,
        )),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        const SizedBox(height: 20),
      ],
    );
  }

<<<<<<< HEAD
  Widget _buildCombinedCard(Map<String, dynamic> record) {
    final loginTs = record['login_ts'];
    final logoutTs = record['logout_ts'];
    final hasOut = record['has_out'] == true;
    final empName = record['employee_name'] as String? ?? '';
    final dateStr = record['date'] as String? ?? '';
    final dur = _durationFromTs(loginTs, logoutTs);

    DateTime? dt;
    if (dateStr.isNotEmpty) {
      try { dt = DateTime.parse(dateStr); } catch (_) {}
    } else if (loginTs is Timestamp) {
      dt = loginTs.toDate().toLocal();
    }

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = dateStr == today;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday ? AppColors.orange.withOpacity(0.45) : AppColors.white15,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 52,
              height: 60,
              decoration: BoxDecoration(
                color: isToday ? AppColors.orange.withOpacity(0.1) : AppColors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isToday ? AppColors.orange.withOpacity(0.3) : AppColors.white15,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dt != null ? DateFormat('EEE').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 9,
                      color: isToday ? AppColors.orange : AppColors.white40,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    dt != null ? DateFormat('d').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isToday ? AppColors.orange : AppColors.white,
                    ),
                  ),
                  Text(
                    dt != null ? DateFormat('MMM').format(dt) : '--',
                    style: TextStyle(
                      fontSize: 9,
                      color: isToday ? AppColors.orange : AppColors.white40,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (empName.isNotEmpty)
                    Text(
                      empName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTimeChip('IN', _fmtTimestamp(loginTs), AppColors.success),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color: AppColors.white40,
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
                      const Icon(Icons.timer_outlined, size: 11, color: AppColors.white40),
                      const SizedBox(width: 4),
                      Text(dur, style: const TextStyle(fontSize: 11, color: AppColors.white40)),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasOut
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasOut ? 'COMPLETE' : 'ACTIVE',
                          style: TextStyle(
                            fontSize: 8,
                            color: hasOut ? AppColors.success : AppColors.orangeDark,
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

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildLoginList() {
    if (_loginLogs.isEmpty) {
      return _buildEmptyState('No login records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
<<<<<<< HEAD
          child: _buildCountBadge(
            '${_loginLogs.length} Login Records',
            Icons.login_rounded,
            AppColors.success,
          ),
        ),
        ..._loginLogs.map((r) => _buildActivityLogCard(r, 'login')),
=======
          child: _countBadge(
              '${_loginLogs.length} Login Records',
              Icons.login_rounded,
              _C.success),
        ),
        ..._loginLogs.map((r) => _ActivityLogCard(
          record  : r,
          type    : 'login',
          fmtTs   : _fmtTimestamp,
          fmtDate : _fmtDate,
        )),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLogoutList() {
    if (_logoutLogs.isEmpty) {
      return _buildEmptyState('No logout records found');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
<<<<<<< HEAD
          child: _buildCountBadge(
            '${_logoutLogs.length} Logout Records',
            Icons.logout_rounded,
            _Extra.purple,
          ),
        ),
        ..._logoutLogs.map((r) => _buildActivityLogCard(r, 'logout')),
=======
          child: _countBadge(
              '${_logoutLogs.length} Logout Records',
              Icons.logout_rounded,
              _C.purple),
        ),
        ..._logoutLogs.map((r) => _ActivityLogCard(
          record  : r,
          type    : 'logout',
          fmtTs   : _fmtTimestamp,
          fmtDate : _fmtDate,
        )),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        const SizedBox(height: 20),
      ],
    );
  }

<<<<<<< HEAD
  Widget _buildActivityLogCard(Map<String, dynamic> record, String type) {
    final isLogin = type == 'login';
    final color = isLogin ? AppColors.success : _Extra.purple;
    final ts = record['timestamp'];
    final empName = (record['employee_name'] ?? '').toString();
    final device = (record['device'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white15, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
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
                        style: const TextStyle(
                          color: AppColors.white,
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
                      const Icon(Icons.person_outline_rounded, size: 10, color: AppColors.white40),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          empName,
                          style: const TextStyle(fontSize: 11, color: AppColors.white70),
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
                            color: AppColors.white40,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            device,
                            style: const TextStyle(fontSize: 10, color: AppColors.white40),
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
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
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

  // ── MOBILE CONTENT ───────────────────────────────────────────────────
=======
  Widget _countBadge(String label, IconData icon, Color color) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }

  // ── MOBILE CONTENT ────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildMobileContent() {
    if (_localRecords.isEmpty) {
      return _buildEmptyState('No attendance records yet');
    }

<<<<<<< HEAD
    final present = _localRecords.where((r) => r.status == AttendanceStatus.present).length;
    final late = _localRecords.where((r) => r.status == AttendanceStatus.late).length;

    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: Colors.white,
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Expanded(child: _statCard('$present', 'Present Days', AppColors.orange)),
                const SizedBox(width: 15),
                Expanded(child: _statCard('$late', 'Late Days', _Extra.lime)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Recent Logs',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF222222),
              ),
            ),
          ),
          ..._localRecords.take(10).map((r) => _buildMobileCard(r)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Restyled to match the HTML mockup's log card: a bordered header row
  // (calendar icon + date, status badge top-right), a Clock In / Clock
  // Out row each labeled with a small clock icon, and a footer row with
  // a pin icon + location, separated from the row above it by a hairline
  // top border only — not a full-width Divider like before.
  Widget _buildMobileCard(Attendance record) {
    final date = DateTime.tryParse(record.date);
    final isToday = record.date == DateFormat('yyyy-MM-dd').format(DateTime.now());

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
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: calendar icon + date label, status badge
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 16,
                      color: Color(0xFF71717A),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isToday
                          ? 'Today'
                          : (date != null
                          ? DateFormat('MMM d, yyyy').format(date)
                          : record.date),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: statusColor == _Extra.lime
                          ? const Color(0xFF7A9900) // darker lime for contrast on white
                          : statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Clock In / Clock Out row
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
                          const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF71717A)),
                          const SizedBox(width: 4),
                          const Text(
                            'Clock In',
                            style: TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fmt12(record.timeIn),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
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
                          const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF71717A)),
                          const SizedBox(width: 4),
                          const Text(
                            'Clock Out',
                            style: TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.timeOut != null ? _fmt12(record.timeOut) : '--:--',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Footer row: location pin + "Verified at Jumbo HQ"
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 1)),
            ),
            child: Row(
              children: const [
                Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF71717A)),
                SizedBox(width: 4),
                Text(
                  'Verified at Jumbo HQ',
                  style: TextStyle(fontSize: 10, color: Color(0xFF71717A)),
                ),
              ],
            ),
          ),
=======
    final grouped = <String, List<Attendance>>{};
    for (final r in _localRecords) {
      if (r.date.length >= 7) {
        grouped.putIfAbsent(r.date.substring(0, 7), () => []).add(r);
      }
    }

    return RefreshIndicator(
      color: _C.orange,
      backgroundColor: _C.card,
      onRefresh: _sync,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          _buildStatsRow(),
          ...grouped.entries.expand((e) => [
            _buildMonthHeader(e.key, e.value.length),
            ...e.value.map((r) =>
                _MobileAttendanceCard(record: r, fmt12: _fmt12)),
          ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ],
      ),
    );
  }

<<<<<<< HEAD
  // ── SHARED HELPERS ──────────────────────────────────────────────────────
  Widget _buildTimeChip(String label, String time, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
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
=======
  Widget _buildMonthHeader(String monthKey, int count) {
    DateTime? dt;
    try { dt = DateTime.parse('$monthKey-01'); } catch (_) {}
    final label = dt != null ? DateFormat('MMMM yyyy').format(dt) : monthKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _C.white40,
                letterSpacing: 1)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _C.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$count days',
              style: const TextStyle(
                  fontSize: 9,
                  color: _C.orange,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    );
  }

  Widget _buildEmptyState(String msg, {String? subtitle}) => Center(
<<<<<<< HEAD
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history_rounded, color: AppColors.white15, size: 56),
        const SizedBox(height: 16),
        Text(
          msg,
          style: const TextStyle(
            color: AppColors.white40,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle ?? 'Records will appear here once available',
          style: TextStyle(
            color: AppColors.white40.withOpacity(0.6),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.orange.withOpacity(0.35)),
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
=======
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history_rounded, color: _C.white15, size: 56),
      const SizedBox(height: 16),
      Text(msg,
          style: const TextStyle(
              color: _C.white40, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(
        subtitle ?? 'Records will appear here once available',
        style: TextStyle(
            color: _C.white40.withOpacity(0.6), fontSize: 12),
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
              color: _C.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _C.orange.withOpacity(0.35)),
            ),
            child: const Text('Refresh',
                style: TextStyle(
                    color: _C.orange2, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ]),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// WEB: Paired login + logout card
// ══════════════════════════════════════════════════════════════════════════════
class _CombinedCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String Function(dynamic) fmtTs;
  final String Function(dynamic) fmtDate;
  final String Function(dynamic, dynamic) durationTs;

  const _CombinedCard({
    required this.record,
    required this.fmtTs,
    required this.fmtDate,
    required this.durationTs,
  });

  @override
  Widget build(BuildContext context) {
    final loginTs  = record['login_ts'];
    final logoutTs = record['logout_ts'];
    final hasOut   = record['has_out'] == true;
    final empId    = record['employee_id']   as String? ?? '';
    final empName  = record['employee_name'] as String? ?? '';
    final device   = record['device']        as String? ?? '';
    final dateStr  = record['date']          as String? ?? '';
    final dur      = durationTs(loginTs, logoutTs);

    DateTime? dt;
    if (dateStr.isNotEmpty) {
      try { dt = DateTime.parse(dateStr); } catch (_) {}
    } else if (loginTs is Timestamp) {
      dt = loginTs.toDate().toLocal();
    }

    final today   = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = dateStr == today;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? _C.orange.withOpacity(0.45) : _C.white15,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          // ── Date block ──
          Container(
            width: 52, height: 60,
            decoration: BoxDecoration(
              color: isToday
                  ? _C.orange.withOpacity(0.1) : _C.white08,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isToday
                      ? _C.orange.withOpacity(0.3) : _C.white15),
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dt != null ? DateFormat('EEE').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 9,
                        color: isToday ? _C.orange : _C.white40,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    dt != null ? DateFormat('d').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isToday ? _C.orange : _C.white),
                  ),
                  Text(
                    dt != null ? DateFormat('MMM').format(dt) : '--',
                    style: TextStyle(
                        fontSize: 9,
                        color: isToday ? _C.orange : _C.white40,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
          ),
          const SizedBox(width: 14),

          // ── Content ──
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (empName.isNotEmpty)
                    Text(empName,
                        style: const TextStyle(
                            color: _C.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  if (empId.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(empId,
                        style: const TextStyle(
                            fontSize: 10,
                            color: _C.orange,
                            fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 8),

                  // IN → OUT chips
                  Row(children: [
                    _TimeChip(
                        label: 'IN',
                        time: fmtTs(loginTs),
                        color: _C.success),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 12, color: _C.white40),
                    ),
                    _TimeChip(
                        label: 'OUT',
                        time: hasOut ? fmtTs(logoutTs) : 'ACTIVE',
                        color: hasOut ? _C.purple : _C.orange2),
                  ]),
                  const SizedBox(height: 8),

                  // Duration + status
                  Row(children: [
                    const Icon(Icons.timer_outlined,
                        size: 11, color: _C.white40),
                    const SizedBox(width: 4),
                    Text(dur,
                        style: const TextStyle(
                            fontSize: 11, color: _C.white40)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasOut
                            ? _C.success.withOpacity(0.1)
                            : _C.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        hasOut ? 'COMPLETE' : 'ACTIVE',
                        style: TextStyle(
                            fontSize: 8,
                            color: hasOut ? _C.success : _C.orange2,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (device.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(
                        device.toLowerCase().contains('web')
                            ? Icons.computer_rounded
                            : Icons.phone_android_rounded,
                        color: _C.white40,
                        size: 11,
                      ),
                    ],
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WEB: Individual activity_log card (login or logout)
// ══════════════════════════════════════════════════════════════════════════════
class _ActivityLogCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String type; // 'login' | 'logout'
  final String Function(dynamic) fmtTs;
  final String Function(dynamic) fmtDate;

  const _ActivityLogCard({
    required this.record,
    required this.type,
    required this.fmtTs,
    required this.fmtDate,
  });

  @override
  Widget build(BuildContext context) {
    final isLogin = type == 'login';
    final color   = isLogin ? _C.success : _C.purple;
    final ts      = record['timestamp'];
    final empId   = (record['employee_id']   ?? '').toString();
    final empName = (record['employee_name'] ?? '').toString();
    final device  = (record['device']        ?? '').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.white15, width: 0.5),
      ),
      child: Row(children: [
        // Icon badge
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(
            isLogin ? Icons.login_rounded : Icons.logout_rounded,
            color: color, size: 20,
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(fmtDate(ts),
                        style: const TextStyle(
                            color: _C.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text(fmtTs(ts),
                      style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 5),

                Row(children: [
                  if (empName.isNotEmpty) ...[
                    const Icon(Icons.person_outline_rounded,
                        size: 10, color: _C.white40),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(empName,
                          style: const TextStyle(
                              fontSize: 11, color: _C.white70),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (empId.isNotEmpty) ...[
                    const Icon(Icons.badge_outlined,
                        size: 10, color: _C.white40),
                    const SizedBox(width: 4),
                    Text(empId,
                        style: const TextStyle(
                            fontSize: 10, color: _C.white40)),
                    const SizedBox(width: 10),
                  ],
                  if (device.isNotEmpty)
                    Row(children: [
                      Icon(
                        device.toLowerCase().contains('web')
                            ? Icons.computer_rounded
                            : Icons.phone_android_rounded,
                        size: 10,
                        color: _C.white40,
                      ),
                      const SizedBox(width: 3),
                      Text(device,
                          style: const TextStyle(
                              fontSize: 10, color: _C.white40)),
                    ]),
                ]),
              ]),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MOBILE: attendance card
// ══════════════════════════════════════════════════════════════════════════════
class _MobileAttendanceCard extends StatelessWidget {
  final Attendance record;
  final String Function(String?) fmt12;
  const _MobileAttendanceCard(
      {required this.record, required this.fmt12});

  @override
  Widget build(BuildContext context) {
    final date    = DateTime.tryParse(record.date);
    final isToday =
        record.date == DateFormat('yyyy-MM-dd').format(DateTime.now());

    Color statusColor;
    switch (record.status) {
      case AttendanceStatus.present: statusColor = _C.success; break;
      case AttendanceStatus.late:    statusColor = _C.purple;  break;
      default:                       statusColor = _C.error;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isToday
              ? _C.orange.withOpacity(0.45) : _C.white15,
          width: isToday ? 1.5 : 0.5,
        ),
      ),
      child: Row(children: [
        // ── Date block ──
        Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday
                ? _C.orange.withOpacity(0.1) : _C.white08,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: isToday
                    ? _C.orange.withOpacity(0.3) : _C.white15),
          ),
          child: Column(children: [
            Text(
              date != null ? DateFormat('EEE').format(date) : '',
              style: TextStyle(
                  fontSize: 9,
                  color: isToday ? _C.orange : _C.white40,
                  fontWeight: FontWeight.w700),
            ),
            Text(
              date != null ? DateFormat('d').format(date) : '--',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isToday ? _C.orange : _C.white),
            ),
            Text(
              date != null ? DateFormat('MMM').format(date) : '',
              style: TextStyle(
                  fontSize: 8,
                  color: isToday ? _C.orange : _C.white40,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ),
        const SizedBox(width: 12),

        // ── Time chips ──
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _TimeChip(
                      label: 'IN',
                      time: fmt12(record.timeIn),
                      color: _C.success),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 11, color: _C.white40)),
                  _TimeChip(
                      label: 'OUT',
                      time: record.timeOut != null
                          ? fmt12(record.timeOut) : 'ACTIVE',
                      color: record.timeOut != null
                          ? _C.purple : _C.orange2),
                ]),
                const SizedBox(height: 6),
                Text(record.formattedWorkHours,
                    style: const TextStyle(
                        fontSize: 11, color: _C.white40)),
              ]),
        ),

        // ── Status pill ──
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: statusColor.withOpacity(0.25)),
            ),
            child: Text(
              record.status.label.toUpperCase(),
              style: TextStyle(
                  fontSize: 8,
                  color: statusColor,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ══════════════════════════════════════════════════════════════════════════════
class _TimeChip extends StatelessWidget {
  final String label;
  final String time;
  final Color  color;
  const _TimeChip(
      {required this.label, required this.time, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ',
          style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w800)),
      Text(time,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color)),
    ]),
  );
}

class _StatChip extends StatelessWidget {
  final String   label;
  final String   value;
  final Color    color;
  final IconData icon;
  const _StatChip(
      {required this.label,
        required this.value,
        required this.color,
        required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: color.withOpacity(0.7),
                    fontWeight: FontWeight.w700)),
          ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    ),
  );
}