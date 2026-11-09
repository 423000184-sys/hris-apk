// lib/screens/admin_overview_page.dart
// v2.2: 🎭 Demo Mode Mock Data — Actual data is hidden when Demo Mode is active
import 'dart:math' show max;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import 'admin_login_screen.dart';
import '../services/demo_mode_service.dart';
import '../widgets/bootstrap_grid.dart';

class AdminOverviewPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> loginLogs;
  final List<Map<String, dynamic>> logoutLogs;
  final List<Map<String, dynamic>> regLogs;
  final List<Map<String, dynamic>> locations;

  final double officeLat;
  final double officeLng;
  final double radiusLimit;

  final double Function(double, double, double, double) distanceCalculator;
  final Function(int) onTabNavigate;

  const AdminOverviewPage({
    super.key,
    required this.employees,
    required this.loginLogs,
    required this.logoutLogs,
    required this.regLogs,
    required this.locations,
    required this.officeLat,
    required this.officeLng,
    required this.radiusLimit,
    required this.distanceCalculator,
    required this.onTabNavigate,
  });

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  static const int _officeStartHour = 9;
  static const int _officeStartMinute = 0;
  static const int _graceMinutes = 15;

  // 🎭 Demo getter — read the global demo flag
  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════
  static DateTime? _toDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is String) return DateTime.tryParse(ts);
    return null;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _isToday(dynamic ts) {
    final dt = _toDateTime(ts);
    if (dt == null) return false;
    return _isSameDay(dt, DateTime.now());
  }

  static int _lateMinutes(dynamic ts) {
    final dt = _toDateTime(ts);
    if (dt == null) return 0;
    final cutoff = DateTime(
      dt.year,
      dt.month,
      dt.day,
      _officeStartHour,
      _officeStartMinute,
    ).add(const Duration(minutes: _graceMinutes));
    return dt.difference(cutoff).inMinutes;
  }

  static Set<String> _computeActiveOnDay(
      DateTime day,
      List<Map<String, dynamic>> loginLogs,
      List<Map<String, dynamic>> logoutLogs,
      ) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final Map<String, List<Map<String, dynamic>>> eventsByEmp = {};

    for (final log in [...loginLogs, ...logoutLogs]) {
      final dt = _toDateTime(log['timestamp']);
      if (dt == null) continue;
      if (dt.isBefore(dayStart) || !dt.isBefore(dayEnd)) continue;

      final empId = (log['employee_id'] ?? log['employeeId'] ?? '').toString();
      if (empId.isEmpty) continue;

      eventsByEmp.putIfAbsent(empId, () => []).add(log);
    }

    final Set<String> activeIds = {};
    eventsByEmp.forEach((empId, logs) {
      logs.sort((a, b) {
        final ta = _toDateTime(a['timestamp']);
        final tb = _toDateTime(b['timestamp']);
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });
      final latest = logs.last;
      final type = (latest['type'] ?? '').toString().toUpperCase();
      if (type == 'IN' || type == 'LOGIN') {
        activeIds.add(empId);
      }
    });

    return activeIds;
  }

  // ══════════════════════════════════════════════════════════════
  // 🎭 DEMO: exit demo and return to admin login
  // ══════════════════════════════════════════════════════════════
  Future<void> _exitDemo() async {
    try {
      await DemoModeService.instance.endDemoSession(); // ✅ Ginamit ang tamang method
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AdminLoginScreen(forceLogout: true),
      ),
          (_) => false,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TIME-BASED GREETING
  // ══════════════════════════════════════════════════════════════
  static String _greetingForHour(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final isDemo = _isDemo;

    // ═══════════════════════════════════════════════════════════
    // 🎭 DATA SELECTION (MOCK VS ACTUAL)
    // ═══════════════════════════════════════════════════════════
    List<Map<String, dynamic>> activeEmployeesList;
    List<Map<String, dynamic>> activeLoginLogs;
    List<Map<String, dynamic>> activeLogoutLogs;
    List<Map<String, dynamic>> activeRegLogs;
    List<Map<String, dynamic>> activeLocations;

    if (isDemo) {
      // Gumamit ng Mock Data kapag Demo Mode
      final now = DateTime.now();
      activeEmployeesList = List.generate(5, (i) => {
        'id': 'DEMO-00$i',
        'employeeId': 'EMP-00$i',
        'firstName': 'Demo',
        'lastName': 'User $i',
        'role': 'Staff',
        'department': 'Operations',
        'status': 'Active',
      });

      activeLoginLogs = List.generate(3, (i) => {
        'id': 'DEMO-LOGIN-$i',
        'employee_id': 'DEMO-00$i',
        'employee_name': 'Demo User $i',
        'type': 'LOGIN',
        'timestamp': now.subtract(Duration(minutes: 15 + (i * 10))),
      });

      activeLogoutLogs = List.generate(2, (i) => {
        'id': 'DEMO-LOGOUT-$i',
        'employee_id': 'DEMO-00${i + 3}',
        'employee_name': 'Demo User ${i + 3}',
        'type': 'LOGOUT',
        'timestamp': now.subtract(Duration(minutes: 5 + (i * 10))),
      });

      activeRegLogs = List.generate(2, (i) => {
        'id': 'DEMO-REG-$i',
        'employee_name': 'New Demo User $i',
        'type': 'REGISTRATION',
        'timestamp': now.subtract(Duration(hours: 1, minutes: i * 5)),
      });

      // Mock Locations (kalat-kalat)
      activeLocations = List.generate(4, (i) {
        final isOutside = i > 2;
        return {
          'id': 'DEMO-LOC-$i',
          'latitude': widget.officeLat + (isOutside ? 0.05 : 0.001 * i),
          'longitude': widget.officeLng + (isOutside ? 0.05 : 0.001 * i),
        };
      });

    } else {
      // Totoong Data mula sa Firebase
      activeEmployeesList = widget.employees;
      activeLoginLogs = widget.loginLogs;
      activeLogoutLogs = widget.logoutLogs;
      activeRegLogs = widget.regLogs;
      activeLocations = widget.locations;
    }

    // ─── Compute stats ───
    final inRangeCount = activeLocations.where((l) {
      final lat = (l['latitude'] as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      return widget.distanceCalculator(
          lat, lng, widget.officeLat, widget.officeLng) <=
          widget.radiusLimit;
    }).length;

    final outOfRangeCount = activeLocations.where((l) {
      final lat = (l['latitude'] as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      return widget.distanceCalculator(
          lat, lng, widget.officeLat, widget.officeLng) >
          widget.radiusLimit;
    }).length;

    final List<Map<String, dynamic>> contextActivity = [
      ...activeLoginLogs,
      ...activeLogoutLogs,
      ...activeRegLogs,
    ];
    contextActivity.sort((a, b) {
      final ta = _toDateTime(a['timestamp']);
      final tb = _toDateTime(b['timestamp']);
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final todayActiveIds =
    _computeActiveOnDay(now, activeLoginLogs, activeLogoutLogs);
    final yesterdayActiveIds =
    _computeActiveOnDay(yesterdayStart, activeLoginLogs, activeLogoutLogs);

    final activeEmployees = todayActiveIds.length;
    final yesterdayActive = yesterdayActiveIds.length;

    final int changePercent;
    if (yesterdayActive == 0 && activeEmployees == 0) {
      changePercent = 0;
    } else if (yesterdayActive == 0) {
      changePercent = 100;
    } else {
      changePercent =
          (((activeEmployees - yesterdayActive) / yesterdayActive) * 100)
              .round();
    }

    final activePercent = activeEmployeesList.isEmpty
        ? 0
        : ((activeEmployees / activeEmployeesList.length) * 100).round();

    final todaysLogins =
    activeLoginLogs.where((l) => _isToday(l['timestamp'])).toList();
    final clockedIn = todaysLogins.length;

    final lateLogs = todaysLogins.where((l) {
      final ts = l['timestamp'];
      return ts != null && _lateMinutes(ts) > 0;
    }).toList();
    final lateArrivals = lateLogs.length;

    final avgLateMinutes = lateLogs.isEmpty
        ? 0
        : (lateLogs.fold<int>(
        0, (sum, l) => sum + _lateMinutes(l['timestamp'])) /
        lateLogs.length)
        .round();

    final List<int> chartData = List.filled(8, 0);
    for (final log in todaysLogins) {
      final dt = _toDateTime(log['timestamp']);
      if (dt == null) continue;
      final bucket = dt.hour ~/ 3;
      if (bucket >= 0 && bucket < 8) chartData[bucket]++;
    }

    final totalAlerts = lateArrivals + outOfRangeCount;

    // Time-based greeting
    final greeting = _greetingForHour(now.hour);

    return Scaffold(
      backgroundColor: tc.background,
      body: SafeArea(
        child: BsContainer(
          maxWidth: 1600,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════════
                // 🎭 DEMO BANNER
                // ═══════════════════════════════════════════════
                if (isDemo) ...[
                  _buildDemoBanner(tc),
                  const SizedBox(height: 16),
                ],

                // ═══════════════════════════════════════════════
                // HERO + WORKFORCE
                // ═══════════════════════════════════════════════
                BsResponsiveRow(
                  stackBelow: BsSize.lg,
                  children: [
                    _heroCard(tc, totalAlerts, greeting, isDemo),
                    _workforceCard(
                      tc,
                      activePercent,
                      activeEmployeesList.length,
                      activeEmployees,
                      changePercent,
                      yesterdayActive,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ═══════════════════════════════════════════════
                // STAT CARDS — 4 columns on lg+
                // ═══════════════════════════════════════════════
                BsGrid(
                  xs: 1,
                  sm: 2,
                  md: 2,
                  lg: 4,
                  xl: 4,
                  spacing: 16,
                  children: [
                    _statCard(
                      tc,
                      title: 'TOTAL STAFF',
                      value: '${activeEmployeesList.length}',
                      footer: 'Active',
                      footerIcon: Icons.check_circle_outline,
                      footerColor: tc.green,
                    ),
                    _statCard(
                      tc,
                      title: 'CLOCKED IN',
                      value: '$clockedIn',
                      progress: activeEmployeesList.isEmpty
                          ? 0
                          : (clockedIn / activeEmployeesList.length)
                          .clamp(0.0, 1.0),
                    ),
                    _statCard(
                      tc,
                      title: 'LATE ARRIVALS',
                      value: '$lateArrivals',
                      valueColor: lateArrivals > 0 ? tc.red : null,
                      footer: lateArrivals > 0
                          ? 'Avg: ${avgLateMinutes}m delay'
                          : 'None today',
                      footerColor:
                      lateArrivals > 0 ? tc.textMuted : tc.green,
                    ),
                    _statCard(
                      tc,
                      title: 'GEO-ALERTS',
                      value: outOfRangeCount.toString().padLeft(2, '0'),
                      valueColor:
                      outOfRangeCount > 0 ? tc.orange : tc.textMuted,
                      footer: outOfRangeCount > 0 ? 'Live' : 'All clear',
                      footerIcon: Icons.location_on_outlined,
                      footerColor:
                      outOfRangeCount > 0 ? tc.orange : tc.green,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ═══════════════════════════════════════════════
                // CHART + ACTIVITY
                // ═══════════════════════════════════════════════
                BsResponsiveRow(
                  stackBelow: BsSize.lg,
                  children: [
                    _chartCard(tc, chartData),
                    _activityCard(tc, contextActivity),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 🎭 DEMO BANNER
  // ══════════════════════════════════════════════════════════════
  Widget _buildDemoBanner(AdminColors tc) {
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
                  'Showing sample data for demonstration purposes. '
                      'No real records are affected.',
                  style: TextStyle(
                    fontSize: 11,
                    color: tc.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _exitDemo,
            style: TextButton.styleFrom(
              foregroundColor: tc.orange,
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text(
              'Exit Demo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HERO CARD
  // ══════════════════════════════════════════════════════════════
  Widget _heroCard(
      AdminColors tc, int alerts, String greeting, bool isDemo) {
    final alertsText = alerts == 0
        ? 'All operations running smoothly.'
        : '$alerts alert${alerts == 1 ? '' : 's'} require your immediate attention.';

    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);

        final titleWidget = RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: responsive.responsive<double>(
                xs: 22,
                sm: 26,
                md: 28,
                lg: 32,
              ),
              fontWeight: FontWeight.w800,
              color: tc.text,
              height: 1.15,
            ),
            children: [
              TextSpan(text: '$greeting, '),
              TextSpan(
                text: 'Admin',
                style: TextStyle(color: tc.orange),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        );

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isDemo) ...[
                _demoChip(tc),
                const SizedBox(height: 10),
              ],
              titleWidget,
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Text(
                  isDemo
                      ? 'You are exploring the admin overview in Demo Mode. '
                      'Sample data is shown below — $alertsText'
                      : 'Operations are running within normal parameters. $alertsText',
                  style: TextStyle(
                    color: tc.navText,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _demoChip(AdminColors tc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tc.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_rounded, size: 12, color: tc.orange),
          const SizedBox(width: 5),
          Text(
            'DEMO MODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: tc.orange,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // WORKFORCE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _workforceCard(
      AdminColors tc,
      int activePercent,
      int total,
      int active,
      int changePercent,
      int yesterdayActive,
      ) {
    final bool hasYesterdayData = yesterdayActive > 0 || active > 0;
    final String changeLabel = !hasYesterdayData
        ? 'No data from yesterday'
        : '${changePercent >= 0 ? '+' : ''}$changePercent% from yesterday';

    final IconData changeIcon = !hasYesterdayData
        ? Icons.remove_rounded
        : (changePercent >= 0
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.orange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACTIVE WORKFORCE',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$activePercent%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(changeIcon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  changeLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STAT CARD
  // ══════════════════════════════════════════════════════════════
  Widget _statCard(
      AdminColors tc, {
        required String title,
        required String value,
        Color? valueColor,
        String? footer,
        Color? footerColor,
        IconData? footerIcon,
        double? progress,
      }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tc.navText,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor ?? tc.text,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: tc.elevated,
                valueColor: AlwaysStoppedAnimation(tc.orange),
              ),
            )
          else if (footer != null)
            Row(
              children: [
                if (footerIcon != null) ...[
                  Icon(footerIcon,
                      size: 14, color: footerColor ?? tc.textMuted),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    footer,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: footerColor ?? tc.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // CHART CARD
  // ══════════════════════════════════════════════════════════════
  Widget _chartCard(AdminColors tc, List<int> data) {
    final maxVal = data.isEmpty ? 0.0 : data.reduce(max).toDouble();
    const labels = ['06:00', '12:00', '18:00', '00:00'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);
        final isNarrow = constraints.maxWidth < 400;
        final chartHeight = responsive.responsive<double>(
          xs: 300,
          sm: 340,
          md: 380,
          lg: 420,
        );

        return Container(
          height: chartHeight,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                Text(
                  'Attendance Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: tc.text,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tc.border),
                    color: tc.surface,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Last 24 Hours',
                          style: TextStyle(
                            fontSize: 13,
                            color: tc.navText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down,
                          size: 18, color: tc.textMuted),
                    ],
                  ),
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Attendance Trend',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: tc.text,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: tc.border),
                        color: tc.surface,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Last 24 Hours',
                              style: TextStyle(
                                fontSize: 14,
                                color: tc.navText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down,
                              size: 18, color: tc.textMuted),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: data.map((v) {
                    final ratio = maxVal == 0 ? 0.0 : v / maxVal;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: tc.elevated,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                            FractionallySizedBox(
                              heightFactor: ratio.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: tc.orange.withValues(alpha: 0.4),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: labels
                      .map((l) => Text(
                    l,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tc.navText,
                    ),
                  ))
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACTIVITY CARD
  // ══════════════════════════════════════════════════════════════
  Widget _activityCard(AdminColors tc, List<Map<String, dynamic>> logs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = BsResponsive(constraints.maxWidth);
        final cardHeight = responsive.responsive<double>(
          xs: 360,
          sm: 380,
          md: 400,
          lg: 420,
        );

        return Container(
          height: cardHeight,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tc.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tc.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tc.text,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: logs.isEmpty
                    ? Center(
                  child: Text(
                    'No recent activity',
                    style: TextStyle(color: tc.textMuted, fontSize: 13),
                  ),
                )
                    : ListView.builder(
                  itemCount: logs.take(3).length,
                  itemBuilder: (_, index) =>
                      _activityTile(tc, logs[index]),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => widget.onTabNavigate(4),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tc.orange,
                    side: BorderSide(color: tc.orange.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'View Detailed Log',
                    style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ACTIVITY TILE
  // ══════════════════════════════════════════════════════════════
  Widget _activityTile(AdminColors tc, Map<String, dynamic> log) {
    final kind = (log['type'] ?? 'login').toString().toLowerCase();
    final name =
    (log['employee_name'] ?? log['name'] ?? 'Employee').toString();
    final dt = _toDateTime(log['timestamp']);
    final time = dt != null ? DateFormat('hh:mm a').format(dt) : '--';

    IconData icon;
    Color iconColor;
    String subtitle;
    String badgeText;
    Color badgeColor;
    bool dimmed = false;

    switch (kind) {
      case 'logout':
        icon = Icons.logout_rounded;
        iconColor = tc.navText;
        subtitle = 'Clocked Out • $time';
        badgeText = 'OUT';
        badgeColor = tc.navText;
        dimmed = true;
        break;
      case 'registration':
        icon = Icons.login_rounded;
        iconColor = tc.orange;
        subtitle = 'Registered • $time';
        badgeText = 'NEW';
        badgeColor = tc.orange;
        break;
      case 'flag':
      case 'flagged':
        icon = Icons.location_off_rounded;
        iconColor = tc.red;
        subtitle = 'Clock In Flagged • $time';
        badgeText = 'OUTSIDE';
        badgeColor = tc.red;
        break;
      default: // login
        icon = Icons.login_rounded;
        iconColor = tc.orange;
        subtitle = 'Clocked In • $time';
        badgeText = 'GPS OK';
        badgeColor = tc.green;
    }

    return Opacity(
      opacity: dimmed ? 0.7 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tc.elevated,
          borderRadius: BorderRadius.circular(8),
          border:
          Border.all(color: tc.border.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tc.card,
                shape: BoxShape.circle,
                border: Border.all(
                    color: tc.border.withValues(alpha: 0.5), width: 1),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: tc.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tc.navText, fontSize: 14),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}