// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
<<<<<<< HEAD
import 'package:flutter_svg/flutter_svg.dart';
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
import '../theme/app_theme.dart';
import '../models/employee.dart' as model;
import 'dashboard_screen.dart';
import 'clock_screen.dart';
import 'attendance_history_screen.dart';
import 'apply_leave_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  final model.Employee? employee;
  const MainScreen({super.key, this.employee});

  @override
  State<MainScreen> createState() => MainScreenState();
}

<<<<<<< HEAD
class MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _showClockOverlay = false;

  // ── FIX: key para direktang ma-refresh ang Dashboard (loadTodayAttendance /
  // loadPayslipAmount) pagkatapos mag-clock in/out, imbes na maghintay
  // hanggang manual pull-to-refresh o app restart. Laging naka-mount ang
  // DashboardScreen dahil nasa loob ito ng IndexedStack. ──
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey<DashboardScreenState>();

  // ── FIX: dati, pag naka-open ang Clock Screen overlay, ang pagpindot sa
  // bottom nav ay nagpapalit lang ng _currentIndex sa likod, pero hindi
  // sinasara ang overlay — kaya parang hindi gumagana yung nav. Isinasara
  // na rin ngayon ang overlay bago lumipat ng tab. ──
  void switchTab(int index) {
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _showClockOverlay = false;
    });
  }

  void _openClockOverlay() {
    setState(() => _showClockOverlay = true);
  }

  // ── FIX: pinapatawag ito ng ClockScreen sa onContinue, para agad
  // mag-refresh ang Dashboard status banner / toggle / floating action. ──
  void _refreshDashboard() {
    _dashboardKey.currentState?.loadTodayAttendance();
    _dashboardKey.currentState?.loadPayslipAmount();
=======
class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  void switchTab(int index) {
    if (mounted) setState(() => _currentIndex = index);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

<<<<<<< HEAD
  static const Color _navActive = Color(0xFFFF8A00);
  static const Color _navInactive = Color(0xFF71717A);
  static const Color _navBg = Color(0xFFF8F8F8);

  static const List<_NavData> _navItems = [
    _NavData(label: 'Home', index: 0, svg: _homeSvg),
    _NavData(label: 'Logs', index: 1, svg: _logsSvg),
    _NavData(label: 'Itinerary', index: 2, svg: _itinerarySvg),
    _NavData(label: 'Profile', index: 3, svg: _profileSvg),
=======
  static const _navItems = [
    _NavData(icon: Icons.dashboard_rounded,   label: 'Dashboard',  index: 0, color: Color(0xFFFF5500)),
    _NavData(icon: Icons.fingerprint_rounded, label: 'Clock',      index: 1, color: Color(0xFFFF7A1A)),
    _NavData(icon: Icons.history_rounded,     label: 'History',    index: 2, color: Color(0xFFFFAA00)),
    _NavData(icon: Icons.people_rounded,      label: 'Leave',      index: 3, color: Color(0xFFFF3D00)),
    _NavData(icon: Icons.bar_chart_rounded,   label: 'Reports',    index: 4, color: Color(0xFFFFCC44)),
    _NavData(icon: Icons.person_rounded,      label: 'Profile',    index: 5, color: Color(0xFFFF8833)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  ];

  @override
  Widget build(BuildContext context) {
    final isWeb = kIsWeb && MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Row(
        children: [
          if (isWeb) _buildWebSidebar(),
          Expanded(
            child: Stack(
              children: [
<<<<<<< HEAD
                // Main content (IndexedStack)
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                Positioned.fill(
                  bottom: isWeb ? 0 : 70,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      DashboardScreen(
<<<<<<< HEAD
                          key: _dashboardKey,
                          onTabSwitch: switchTab,
                          initialEmployee: widget.employee,
                          onReportsTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReportsScreen(initialEmployee: widget.employee),
                              ),
                            );
                          }),
=======
                          onTabSwitch: switchTab,
                          initialEmployee: widget.employee),
                      ClockScreen(initialEmployee: widget.employee),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                      AttendanceHistoryScreen(
                          initialEmployee: widget.employee),
                      ApplyLeaveScreen(
                        employeeId: widget.employee?.employeeId ?? '',
                        employeeName: widget.employee?.fullName ?? 'Guest',
                      ),
<<<<<<< HEAD
=======
                      ReportsScreen(initialEmployee: widget.employee),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                      ProfileScreen(initialEmployee: widget.employee),
                    ],
                  ),
                ),
<<<<<<< HEAD

                // ── ClockScreen overlay ────────────────────────────────────
                // FIX: gamit na ang parehong bottom offset ng IndexedStack
                // (70 sa mobile) para hindi na kasama ng overlay na ito ang
                // espasyo ng bottom nav — dati'y buong screen ang sakop
                // nito kasama pa yung likod mismo ng nav bar.
                if (_showClockOverlay)
                  Positioned.fill(
                    bottom: isWeb ? 0 : 70,
                    child: ClockScreen(
                      initialEmployee: widget.employee,
                      onBack: () {
                        setState(() => _showClockOverlay = false);
                      },
                      onContinue: () {
                        setState(() {
                          _showClockOverlay = false;
                          _currentIndex = 0; // balik sa Dashboard
                        });
                        _refreshDashboard();
                      },
                    ),
                  ),

                // ── Reports quick-access ──────────────────────────────────
                // FIX: dati, laging naka-Positioned(top:12,right:12) ito sa
                // ibabaw ng anumang laman ng aktibong tab. Sa Dashboard tab
                // (index 0), nagbabanggaan ito sa sarili nang header cluster
                // ng DashboardScreen (avatar + stat icon sa parehong corner),
                // kaya natatakpan/naharangan yung mga button doon. Itinatago
                // na lang ito pag nasa Dashboard tab — doon dapat ilagay ang
                // sariling Reports icon ng DashboardScreen sa loob ng header
                // niya para maayos ang spacing.
                if (!_showClockOverlay && _currentIndex != 0)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: SafeArea(
                      child: _buildReportsButton(),
                    ),
                  ),

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                if (!isWeb)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildMobileBottomNav(),
                  ),
              ],
            ),
          ),
        ],
      ),
<<<<<<< HEAD
      floatingActionButton: _showClockOverlay
          ? null
          : _buildClockFab(context),
      floatingActionButtonLocation:
      isWeb ? FloatingActionButtonLocation.endFloat : FloatingActionButtonLocation.centerDocked,
    );
  }

  // ── Clock FAB (nagbubukas ng overlay) ────────────────────────────────
  Widget _buildClockFab(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: _navActive,
      elevation: 4,
      onPressed: _openClockOverlay,
      child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 26),
    );
  }

  // ── Reports quick-access button ──────────────────────────────────────
  Widget _buildReportsButton() {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportsScreen(initialEmployee: widget.employee),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.bar_chart_rounded, color: _navActive, size: 20),
        ),
      ),
    );
  }

  // ── Web Sidebar ────────────────────────────────────────────────────────
=======
    );
  }

  // ── Web Sidebar ──────────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildWebSidebar() {
    final w = MediaQuery.of(context).size.width;
    final sidebarWidth = w >= 1200 ? 260.0 : 220.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildWebLogo(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
<<<<<<< HEAD
              children: [
                ..._navItems.map((item) => _webNavItem(item)),
                const Divider(height: 24),
                _webQuickLink(
                  label: 'Clock In/Out',
                  icon: Icons.fingerprint_rounded,
                  onTap: _openClockOverlay,
                ),
                _webQuickLink(
                  label: 'Reports',
                  icon: Icons.bar_chart_rounded,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportsScreen(initialEmployee: widget.employee),
                    ),
                  ),
                ),
              ],
=======
              children: _navItems.map((item) => _webNavItem(item)).toList(),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
          _buildWebProfileFooter(),
        ],
      ),
    );
  }

  Widget _buildWebLogo() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orange.withOpacity(0.35),
                  blurRadius: 14,
                )
              ],
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('HRIS',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3)),
              Text('BIOMETRICS',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _webNavItem(_NavData item) {
    final active = _currentIndex == item.index;
<<<<<<< HEAD
    final color = active ? _navActive : _navInactive;
=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    return InkWell(
      onTap: () => switchTab(item.index),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
<<<<<<< HEAD
          color: active ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? color.withOpacity(0.3) : Colors.transparent,
=======
          color: active ? item.color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? item.color.withOpacity(0.3) : Colors.transparent,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ),
        child: Row(
          children: [
<<<<<<< HEAD
            SvgPicture.string(item.svg(color), width: 18, height: 18),
=======
            Icon(item.icon,
                color: active ? item.color : AppColors.textMuted,
                size: 18),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            const SizedBox(width: 14),
            Text(
              item.label.toUpperCase(),
              style: TextStyle(
                color: active ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            if (active) ...[
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
<<<<<<< HEAD
                  color: color,
=======
                  color: item.color,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

<<<<<<< HEAD
  Widget _webQuickLink({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textMuted, size: 18),
            const SizedBox(width: 14),
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildWebProfileFooter() {
    final emp = widget.employee;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withOpacity(0.12), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.gradientOrange,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                emp?.initials ?? '?',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emp?.fullName ?? 'Guest',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  emp?.position ?? 'User',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.textMuted, size: 17),
          ),
        ],
      ),
    );
  }

<<<<<<< HEAD
  // ── Mobile Bottom Nav ──────────────────────────────────────────────────
  Widget _buildMobileBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: _navBg,
        border: Border(
          top: BorderSide(color: Color(0xFF27272A), width: 1.15),
        ),
=======
  // ── Mobile Bottom Nav ────────────────────────────────────────────────────────
  Widget _buildMobileBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withOpacity(0.2), width: 1),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
<<<<<<< HEAD
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Left pair: Home, Logs
              ..._navItems.sublist(0, 2).map(_navItemWidget),
              // ── FIX: reserved na blangkong puwang sa gitna para hindi
              // na-ov na ng centerDocked FAB (fingerprint icon) ang
              // "Itinerary" label — dati'y natatabunan ito at hindi
              // ma-tap nang maayos. ──
              const SizedBox(width: 56),
              // Right pair: Itinerary, Profile
              ..._navItems.sublist(2, 4).map(_navItemWidget),
            ],
=======
          height: 60,
          child: Row(
            children: _navItems.map((item) {
              final active = _currentIndex == item.index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => switchTab(item.index),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? item.color.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(item.icon,
                            color: active ? item.color : AppColors.textMuted,
                            size: 19),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label.toUpperCase(),
                        style: TextStyle(
                          color: active ? item.color : AppColors.textMuted,
                          fontSize: 8,
                          fontWeight:
                          active ? FontWeight.w800 : FontWeight.w500,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ),
      ),
    );
  }
<<<<<<< HEAD

  Widget _navItemWidget(_NavData item) {
    final active = _currentIndex == item.index;
    final color = active ? _navActive : _navInactive;
    return GestureDetector(
      onTap: () => switchTab(item.index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(item.svg(color), width: 24, height: 24),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── SVG icon builders ──────────────────────────────────────────────────
  static String _hex(Color c) => '#${c.value.toRadixString(16).substring(2)}';

  static String _homeSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M8.99951 3H3.99951C3.44723 3 2.99951 3.44772 2.99951 4V11C2.99951 11.5523 3.44723 12 3.99951 12H8.99951C9.5518 12 9.99951 11.5523 9.99951 11V4C9.99951 3.44772 9.5518 3 8.99951 3Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M19.9985 3H14.9985C14.4463 3 13.9985 3.44772 13.9985 4V7C13.9985 7.55228 14.4463 8 14.9985 8H19.9985C20.5508 8 20.9985 7.55228 20.9985 7V4C20.9985 3.44772 20.5508 3 19.9985 3Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M19.9985 11.999H14.9985C14.4463 11.999 13.9985 12.4467 13.9985 12.999V19.999C13.9985 20.5513 14.4463 20.999 14.9985 20.999H19.9985C20.5508 20.999 20.9985 20.5513 20.9985 19.999V12.999C20.9985 12.4467 20.5508 11.999 19.9985 11.999Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M8.99951 15.999H3.99951C3.44723 15.999 2.99951 16.4467 2.99951 16.999V19.999C2.99951 20.5513 3.44723 20.999 3.99951 20.999H8.99951C9.5518 20.999 9.99951 20.5513 9.99951 19.999V16.999C9.99951 16.4467 9.5518 15.999 8.99951 15.999Z" fill="$s" fill-opacity="0.1" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _logsSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M11.9991 21.9982C17.5215 21.9982 21.9982 17.5215 21.9982 11.9991C21.9982 6.47676 17.5215 2 11.9991 2C6.47676 2 2 6.47676 2 11.9991C2 17.5215 6.47676 21.9982 11.9991 21.9982Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M11.999 5.99902V11.999L15.999 13.999" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _itinerarySvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M7.99951 2V6" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M15.9985 2V6" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M18.9981 4H4.99934C3.89486 4 2.99951 4.89535 2.99951 5.99983V19.9986C2.99951 21.1031 3.89486 21.9984 4.99934 21.9984H18.9981C20.1026 21.9984 20.9979 21.1031 20.9979 19.9986V5.99983C20.9979 4.89535 20.1026 4 18.9981 4Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M2.99951 9.99902H20.9979" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  static String _profileSvg(Color color) {
    final s = _hex(color);
    return '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  <path d="M18.9983 20.9985V18.9987C18.9983 17.9379 18.5769 16.9206 17.8268 16.1705C17.0767 15.4204 16.0594 14.999 14.9986 14.999H8.99916C7.93839 14.999 6.92106 15.4204 6.17098 16.1705C5.4209 16.9206 4.99951 17.9379 4.99951 18.9987V20.9985" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M11.9995 11C14.2087 11 15.9995 9.20914 15.9995 7C15.9995 4.79086 14.2087 3 11.9995 3C9.79037 3 7.99951 4.79086 7.99951 7C7.99951 9.20914 9.79037 11 11.9995 11Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }
}

class _NavData {
  final String label;
  final int index;
  final String Function(Color color) svg;

  const _NavData({
    required this.label,
    required this.index,
    required this.svg,
=======
}

class _NavData {
  final IconData icon;
  final String label;
  final int index;
  final Color color;

  const _NavData({
    required this.icon,
    required this.label,
    required this.index,
    required this.color,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  });
}