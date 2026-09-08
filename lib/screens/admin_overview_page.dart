import 'dart:math' show max;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';

class AdminOverviewPage extends StatelessWidget {
  final List<Map<String, dynamic>> employees;
  final List<Map<String, dynamic>> loginLogs;
  final List<Map<String, dynamic>> logoutLogs;
  final List<Map<String, dynamic>> regLogs;
  final List<Map<String, dynamic>> locations;

  final double officeLat;
  final double officeLng;
  final double radiusLimit;

  final double Function(
      double,
      double,
      double,
      double,
      ) distanceCalculator;

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

<<<<<<< HEAD
  // ---- Design tokens matching the reference mock ----
  static const Color _bg = Color(0xFFF7F4F1);
  static const Color _cardBorder = Color(0xFFECE8E3);
  static const Color _muted = Color(0xFF9CA3AF);
  static const Color _text = Color(0xFF1F2430);

  // Shift start + grace period used to decide whether a login counts as late.
  static const int _officeStartHour = 9;
  static const int _officeStartMinute = 0;
  static const int _graceMinutes = 15;

  static bool _isToday(Timestamp? ts) {
    if (ts == null) return false;
    final d = ts.toDate();
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // Minutes past the late cutoff (0 or negative = on time).
  static int _lateMinutes(Timestamp ts) {
    final d = ts.toDate();
    final cutoff = DateTime(d.year, d.month, d.day, _officeStartHour, _officeStartMinute)
        .add(const Duration(minutes: _graceMinutes));
    return d.difference(cutoff).inMinutes;
  }

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

<<<<<<< HEAD
    // Locations currently inside the office geofence — used for the
    // "Active Workforce" hero stat.
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    final inRangeCount = locations.where((l) {
      final lat = (l['latitude'] as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null) return false;

      return distanceCalculator(
        lat,
        lng,
        officeLat,
        officeLng,
      ) <=
          radiusLimit;
    }).length;

<<<<<<< HEAD
    // Locations OUTSIDE the geofence — this is the actual alert condition.
    final outOfRangeCount = locations.where((l) {
      final lat = (l['latitude'] as num?)?.toDouble();
      final lng = (l['longitude'] as num?)?.toDouble();

      if (lat == null || lng == null) return false;

      return distanceCalculator(
        lat,
        lng,
        officeLat,
        officeLng,
      ) >
          radiusLimit;
    }).length;

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    final List<Map<String, dynamic>> contextActivity = [
      ...loginLogs,
      ...logoutLogs,
      ...regLogs,
    ];

    contextActivity.sort((a, b) {
      final ta = a['timestamp'] as Timestamp?;
      final tb = b['timestamp'] as Timestamp?;

      if (ta == null) return 1;
      if (tb == null) return -1;

      return tb.compareTo(ta);
    });

    final activePercent = employees.isEmpty
        ? 0
        : ((inRangeCount / employees.length) * 100).round();

<<<<<<< HEAD
    // Only today's logins count as "clocked in" / candidates for lateness.
    final todaysLogins = loginLogs.where((l) => _isToday(l['timestamp'] as Timestamp?)).toList();

    final clockedIn = todaysLogins.length;

    final lateLogs = todaysLogins.where((l) {
      final ts = l['timestamp'] as Timestamp?;
      return ts != null && _lateMinutes(ts) > 0;
    }).toList();

    final lateArrivals = lateLogs.length;

    final avgLateMinutes = lateLogs.isEmpty
        ? 0
        : (lateLogs.fold<int>(0, (sum, l) => sum + _lateMinutes(l['timestamp'] as Timestamp)) /
        lateLogs.length)
        .round();

    // Attendance trend — real counts of today's clock-ins bucketed into
    // 3-hour windows (00-03, 03-06, ... 21-24). Stays all-zero until
    // someone actually clocks in.
    final List<int> chartData = List.filled(8, 0);
    for (final log in todaysLogins) {
      final ts = log['timestamp'] as Timestamp?;
      if (ts == null) continue;
      final bucket = ts.toDate().hour ~/ 3;
      if (bucket >= 0 && bucket < 8) chartData[bucket]++;
    }

    return Scaffold(
      backgroundColor: _bg,
=======
    final clockedIn = loginLogs.length;

    final lateArrivals = max(0, employees.length ~/ 8);

    const List<int> chartData = [
      18,
      36,
      58,
      52,
      48,
      92,
      40,
      12,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
<<<<<<< HEAD
              // HERO + WORKFORCE
              screenWidth > 1150
                  ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _heroCard(contextActivity.length),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _workforceCard(
                        activePercent,
                        employees.length,
                        inRangeCount,
                      ),
                    ),
                  ],
                ),
              )
                  : Column(
                children: [
                  _heroCard(contextActivity.length),
                  const SizedBox(height: 16),
=======

              // TOP HEADER
              screenWidth > 850
                  ? Row(
                children: [

                  const Text(
                    'R.A.C.O.M.A. Admin',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF202020),
                    ),
                  ),

                  const Spacer(),

                  // ONLY ONE SEARCH BAR
                  Container(
                    width: 260,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE6E6E6),
                      ),
                    ),
                    child: TextField(
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),

                      cursorColor: Colors.black,

                      decoration: const InputDecoration(
                        hintText: 'Search logs...',
                        hintStyle: TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 14,
                        ),

                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: Color(0xFF9A9A9A),
                          size: 20,
                        ),

                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,

                        contentPadding: EdgeInsets.symmetric(
                          vertical: 13,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  _topIcon(
                    Icons.notifications_none_rounded,
                  ),

                  const SizedBox(width: 10),

                  _topIcon(
                    Icons.help_outline_rounded,
                  ),

                  const SizedBox(width: 14),

                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.black,
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              )
                  : Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [

                  const Text(
                    'R.A.C.O.M.A. Admin',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF202020),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [

                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                            BorderRadius.circular(16),
                            border: Border.all(
                              color:
                              const Color(0xFFE6E6E6),
                            ),
                          ),
                          child: TextField(
                            style: const TextStyle(
                              color: Colors.black,
                            ),

                            decoration:
                            const InputDecoration(
                              hintText:
                              'Search logs...',
                              border:
                              InputBorder.none,

                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Color(
                                  0xFF9A9A9A,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      _topIcon(
                        Icons.notifications_none_rounded,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // HERO + WORKFORCE
              screenWidth > 1150
                  ? Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [

                  Expanded(
                    flex: 3,
                    child: _heroCard(
                      contextActivity.length,
                    ),
                  ),

                  const SizedBox(width: 20),

                  Expanded(
                    child: _workforceCard(
                      activePercent,
                      employees.length,
                      inRangeCount,
                    ),
                  ),
                ],
              )
                  : Column(
                children: [

                  _heroCard(
                    contextActivity.length,
                  ),

                  const SizedBox(height: 20),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  _workforceCard(
                    activePercent,
                    employees.length,
                    inRangeCount,
                  ),
                ],
              ),

<<<<<<< HEAD
              const SizedBox(height: 16),

              // STATS
              GridView.count(
                crossAxisCount: screenWidth > 950 ? 4 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: screenWidth > 950 ? 1.9 : 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
=======
              const SizedBox(height: 24),

              // STATS
              GridView.count(
                crossAxisCount:
                screenWidth > 950 ? 4 : 2,

                crossAxisSpacing: 18,
                mainAxisSpacing: 18,

                childAspectRatio:
                screenWidth > 950 ? 1.35 : 1.2,

                shrinkWrap: true,

                physics:
                const NeverScrollableScrollPhysics(),

                children: [

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  _statCard(
                    title: 'TOTAL STAFF',
                    value: '${employees.length}',
                    footer: '● Active',
<<<<<<< HEAD
                    footerColor: const Color(0xFF22A559),
                  ),
=======
                    footerColor: Colors.green,
                  ),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  _statCard(
                    title: 'CLOCKED IN',
                    value: '$clockedIn',
                    progress: employees.isEmpty
                        ? 0
<<<<<<< HEAD
                        : (clockedIn / employees.length).clamp(0.0, 1.0),
                  ),
                  _statCard(
                    title: 'LATE ARRIVALS',
                    value: '$lateArrivals',
                    valueColor: lateArrivals > 0 ? const Color(0xFFE0483C) : _text,
                    footer: lateArrivals > 0 ? 'Avg: ${avgLateMinutes}m delay' : 'None today',
                    footerColor: lateArrivals > 0 ? const Color(0xFFE0483C) : const Color(0xFF22A559),
                  ),
                  _statCard(
                    title: 'GEO-ALERTS',
                    value: '$outOfRangeCount',
                    valueColor: outOfRangeCount > 0 ? AdminTheme.orange : _text,
                    footer: outOfRangeCount > 0 ? '● Outside geofence' : '● All clear',
                    footerColor: outOfRangeCount > 0 ? AdminTheme.orange : const Color(0xFF22A559),
=======
                        : (clockedIn / employees.length)
                        .clamp(0.0, 1.0),
                  ),

                  _statCard(
                    title: 'LATE ARRIVALS',
                    value: '$lateArrivals',
                    valueColor: Colors.red,
                    footer: 'Avg: 14m delay',
                    footerColor: Colors.red,
                  ),

                  _statCard(
                    title: 'GEO-ALERTS',
                    value: '$inRangeCount',
                    valueColor: AdminTheme.orange,
                    footer: '● Live',
                    footerColor: AdminTheme.orange,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  ),
                ],
              ),

<<<<<<< HEAD
              const SizedBox(height: 16),

              // CHART + ACTIVITY
              screenWidth > 1200
                  ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _chartCard(chartData),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: _activityCard(contextActivity),
                    ),
                  ],
                ),
              )
                  : Column(
                children: [
                  _chartCard(chartData),
                  const SizedBox(height: 16),
                  _activityCard(contextActivity),
=======
              const SizedBox(height: 24),

              // CHART + ACTIVITY
              screenWidth > 1200
                  ? Row(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [

                  Expanded(
                    flex: 3,
                    child: _chartCard(
                      chartData,
                    ),
                  ),

                  const SizedBox(width: 20),

                  Expanded(
                    flex: 2,
                    child: _activityCard(
                      contextActivity,
                    ),
                  ),
                ],
              )
                  : Column(
                children: [

                  _chartCard(
                    chartData,
                  ),

                  const SizedBox(height: 20),

                  _activityCard(
                    contextActivity,
                  ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // HERO CARD
  Widget _heroCard(int alerts) {
    return Container(
<<<<<<< HEAD
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _text,
                    ),
                    children: [
                      TextSpan(text: 'Good morning, '),
                      TextSpan(
                        text: 'Admin.',
                        style: TextStyle(color: AdminTheme.orange),
                      ),
                    ],
                  ),
                ),
              ),
              // SEARCH BOX (White background, dark text)
              SizedBox(
                width: 260,
                height: 44,
                child: TextField(
                  style: const TextStyle(color: _text, fontSize: 13),
                  cursorColor: _text,
                  decoration: InputDecoration(
                    hintText: 'Search logs...',
                    hintStyle: const TextStyle(color: _muted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: _muted, size: 18),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _cardBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AdminTheme.orange),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Operations are running within normal parameters. '
                '$alerts alerts require your immediate attention.',
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
              height: 1.5,
=======
      padding: const EdgeInsets.all(28),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFEAEAEA),
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF222222),
              ),
              children: [

                TextSpan(
                  text: 'Good morning, ',
                ),

                TextSpan(
                  text: 'Admin.',
                  style: TextStyle(
                    color: AdminTheme.orange,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Operations are running within normal parameters. '
                '$alerts alerts require your immediate attention.',

            style: const TextStyle(
              color: Color(0xFF8D8D8D),
              fontSize: 15,
              height: 1.6,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ],
      ),
    );
  }

  // WORKFORCE
<<<<<<< HEAD
  Widget _workforceCard(int activePercent, int total, int active) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.orange,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
=======
  Widget _workforceCard(
      int activePercent,
      int total,
      int active,
      ) {
    return Container(
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: AdminTheme.orange,
        borderRadius: BorderRadius.circular(28),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          const Text(
            'ACTIVE WORKFORCE',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              fontSize: 10,
            ),
          ),
<<<<<<< HEAD
          const SizedBox(height: 4),
=======

          const SizedBox(height: 6),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          Text(
            '$activePercent%',
            style: const TextStyle(
              color: Colors.white,
<<<<<<< HEAD
              fontSize: 34,
=======
              fontSize: 42,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
<<<<<<< HEAD
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (active / total).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.trending_up_rounded, color: Colors.white, size: 13),
              SizedBox(width: 6),
=======

          const SizedBox(height: 20),

          ClipRRect(
            borderRadius:
            BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: total == 0
                  ? 0
                  : (active / total)
                  .clamp(0.0, 1.0),

              minHeight: 7,

              backgroundColor:
              Colors.white24,

              valueColor:
              const AlwaysStoppedAnimation(
                Colors.white,
              ),
            ),
          ),

          const SizedBox(height: 12),

          const Row(
            children: [

              Icon(
                Icons.trending_up_rounded,
                color: Colors.white,
                size: 13,
              ),

              SizedBox(width: 6),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              Expanded(
                child: Text(
                  '+12% from yesterday',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // STAT CARD
  Widget _statCard({
    required String title,
    required String value,
<<<<<<< HEAD
    Color valueColor = _text,
=======
    Color valueColor = const Color(0xFF222222),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    String? footer,
    Color footerColor = Colors.grey,
    double? progress,
  }) {
    return Container(
<<<<<<< HEAD
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          if (progress != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: const Color(0xFFF1EEEA),
                valueColor: const AlwaysStoppedAnimation(AdminTheme.orange),
              ),
            )
          else if (footer != null)
=======
      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFEAEAEA),
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8B8B8B),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),

          const Spacer(),

          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),

          if (progress != null) ...[
            const SizedBox(height: 10),

            ClipRRect(
              borderRadius:
              BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor:
                const Color(0xFFF1F1F1),
                valueColor:
                const AlwaysStoppedAnimation(
                  AdminTheme.orange,
                ),
              ),
            ),
          ],

          if (footer != null) ...[
            const SizedBox(height: 8),

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            Text(
              footer,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: footerColor,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
<<<<<<< HEAD
            )
          else
            const SizedBox.shrink(),
=======
            ),
          ],
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ],
      ),
    );
  }

<<<<<<< HEAD
  // CHART CARD — simple two-tone bar chart drawn from chartData
  Widget _chartCard(List<int> data) {
    final maxVal = data.reduce(max).toDouble();
    const labels = ['06:00', '12:00', '18:00', '00:00'];

    return Container(
      height: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Attendance Trend',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cardBorder),
                ),
                child: const Text(
                  'Last 24 Hours',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted),
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
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        // background track (full height, light gray)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          child: Container(
                            color: const Color(0xFFF1EEEA),
                          ),
                        ),
                        // filled value bar
                        FractionallySizedBox(
                          heightFactor: ratio.clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            child: Container(color: AdminTheme.orange.withOpacity(0.85)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels
                .map((l) => Text(l, style: const TextStyle(fontSize: 11, color: _muted)))
                .toList(),
          ),
        ],
=======
  // CHART CARD
  Widget _chartCard(List<int> data) {
    return Container(
      height: 500,
      padding: const EdgeInsets.all(28),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFEAEAEA),
        ),
      ),

      child: const Center(
        child: Text(
          'Attendance Chart Here',
        ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
    );
  }

  // ACTIVITY CARD
<<<<<<< HEAD
  Widget _activityCard(List<Map<String, dynamic>> logs) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _text),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: logs.isEmpty
                ? const Center(
              child: Text('No recent activity', style: TextStyle(color: _muted, fontSize: 13)),
            )
                : ListView.builder(
              itemCount: logs.take(4).length,
              itemBuilder: (_, index) => _activityTile(logs[index]),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => onTabNavigate(4),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminTheme.orange,
                side: const BorderSide(color: AdminTheme.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Detailed Log', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
=======
  Widget _activityCard(
      List<Map<String, dynamic>> logs,
      ) {
    return Container(
      height: 500,
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFEAEAEA),
        ),
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [

          const Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: logs.isEmpty
                ? const Center(
              child: Text(
                'No recent activity',
              ),
            )
                : ListView.builder(
              itemCount:
              logs.take(4).length,

              itemBuilder: (_, index) {
                return _activityTile(
                  logs[index],
                );
              },
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ],
      ),
    );
  }

  // ACTIVITY TILE
<<<<<<< HEAD
  Widget _activityTile(Map<String, dynamic> log) {
    final kind = (log['type'] ?? 'login').toString().toLowerCase();

    final name = (log['employee_name'] ?? log['name'] ?? 'Employee').toString();

    final ts = log['timestamp'];
    final time = ts is Timestamp ? DateFormat('hh:mm a').format(ts.toDate()) : '--';

    IconData icon;
    Color color;
    String badgeText;

    switch (kind) {
      case 'logout':
        icon = Icons.logout_rounded;
        color = const Color(0xFF6B7280);
        badgeText = 'CLOCKED OUT';
        break;
      case 'registration':
        icon = Icons.person_add_alt_1_rounded;
        color = const Color(0xFF3B82F6);
        badgeText = 'NEW';
        break;
      default:
        icon = Icons.login_rounded;
        color = const Color(0xFF22A559);
        badgeText = 'GPS OK';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${kind[0].toUpperCase()}${kind.substring(1)} • $time',
                  style: const TextStyle(color: _muted, fontSize: 11),
=======
  Widget _activityTile(
      Map<String, dynamic> log,
      ) {
    final kind =
    (log['type'] ?? 'Clock In')
        .toString();

    final name =
    (log['employee_name'] ??
        log['name'] ??
        'Employee')
        .toString();

    final ts = log['timestamp'];

    final time = ts is Timestamp
        ? DateFormat('hh:mm a')
        .format(ts.toDate())
        : '--';

    return Container(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius:
        BorderRadius.circular(18),
      ),

      child: Row(
        children: [

          Container(
            width: 50,
            height: 50,

            decoration: BoxDecoration(
              color: AdminTheme.orange
                  .withOpacity(0.12),

              borderRadius:
              BorderRadius.circular(
                14,
              ),
            ),

            child: const Icon(
              Icons.login_rounded,
              color: AdminTheme.orange,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [

                Text(
                  name,
                  style: const TextStyle(
                    fontWeight:
                    FontWeight.w700,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '$kind • $time',
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12,
                  ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ),
              ],
            ),
          ),
<<<<<<< HEAD
          Text(
            badgeText,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.3),
          ),
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ],
      ),
    );
  }
<<<<<<< HEAD
=======

  // TOP ICON
  static Widget _topIcon(
      IconData icon,
      ) {
    return Container(
      width: 46,
      height: 46,

      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFEAEAEA),
        ),
      ),

      child: Icon(
        icon,
        size: 22,
        color: const Color(0xFF444444),
      ),
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}