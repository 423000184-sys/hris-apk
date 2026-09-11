// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
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

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  // ✅ TINATANDAAN ANG PINANGGALINGANG TAB
  int _previousIndex = 0;

  bool _showClockOverlay = false;

  final GlobalKey<DashboardScreenState> _dashboardKey =
  GlobalKey<DashboardScreenState>();

  // ✅ Regular tab switch – HINDI nagre-record ng previous
  // Ginagamit ito ng dashboard shortcuts lang
  void switchTab(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _showClockOverlay = false;
    });
  }

  // ✅ Switch WITH history tracking – itinatala ang previous
  // Ginagamit ito ng history button, bottom nav, at web sidebar
  void switchTabWithHistory(int index) {
    if (!mounted) return;
    if (_selectedIndex == index) return;
    setState(() {
      _previousIndex = _selectedIndex; // i-record ang pinanggalingan
      _selectedIndex = index;
      _showClockOverlay = false;
    });
  }

  // ✅ BACK HANDLER – bumabalik sa pinanggalingang tab
  void goBackToPrevious() {
    if (!mounted) return;
    debugPrint('🔙 Returning to previous tab: $_previousIndex');
    setState(() {
      _selectedIndex = _previousIndex;
      _showClockOverlay = false;
    });
  }

  void _openClockOverlay() {
    debugPrint('🟢 Opening ClockScreen overlay');
    setState(() => _showClockOverlay = true);
  }

  void _refreshDashboard() {
    _dashboardKey.currentState?.loadTodayAttendance();
    _dashboardKey.currentState?.loadPayslipAmount();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  static const Color _navActive = Color(0xFFFF8A00);
  static const Color _navInactive = Color(0xFF71717A);
  static const Color _navBg = Color(0xFFF8F8F8);

  static const List<_NavData> _navItems = [
    _NavData(label: 'Home', index: 0, svg: _homeSvg),
    _NavData(label: 'Logs', index: 1, svg: _logsSvg),
    _NavData(label: 'Itinerary', index: 2, svg: _itinerarySvg),
    _NavData(label: 'Profile', index: 3, svg: _profileSvg),
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
                Positioned.fill(
                  bottom: isWeb ? 0 : 70,
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      DashboardScreen(
                        key: _dashboardKey,
                        // ✅ Gamitin ang switchTabWithHistory para alam
                        // natin kung saan galing ang user
                        onTabSwitch: switchTabWithHistory,
                        onClockAction: _openClockOverlay,
                        initialEmployee: widget.employee,
                      ),
                      // ✅ Attendance History – babalik sa PINANGGALINGAN
                      AttendanceHistoryScreen(
                        initialEmployee: widget.employee,
                        onBack: goBackToPrevious, // <-- ITO ANG KRITIKAL
                      ),
                      ItineraryScreen(
                        employeeId: widget.employee?.employeeId ?? '',
                        employeeName: widget.employee?.fullName ?? 'Guest',
                        onGoHome: goBackToPrevious,
                      ),
                      ProfileScreen(initialEmployee: widget.employee),
                    ],
                  ),
                ),

                if (_showClockOverlay)
                  Positioned.fill(
                    child: ClockScreen(
                      initialEmployee: widget.employee,
                      onBack: () {
                        setState(() => _showClockOverlay = false);
                      },
                      onContinue: () {
                        setState(() {
                          _showClockOverlay = false;
                          _selectedIndex = 0;
                        });
                        _refreshDashboard();
                      },
                    ),
                  ),

                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHistoryButton(),
                        const SizedBox(width: 10),
                        _buildReportsButton(),
                      ],
                    ),
                  ),
                ),

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
      floatingActionButton:
      _showClockOverlay ? null : _buildClockFab(context),
      floatingActionButtonLocation: isWeb
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.centerDocked,
    );
  }

  // ── Clock FAB ──────────────────────────────────────────────────────────
  Widget _buildClockFab(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: _navActive,
      elevation: 4,
      onPressed: _openClockOverlay,
      child: const Icon(Icons.fingerprint_rounded,
          color: Colors.white, size: 26),
    );
  }

  // ── History quick access ─────────────────────────────────────────────
  // ✅ Ginagamit ang switchTabWithHistory para maalala kung saan galing
  Widget _buildHistoryButton() {
    return GestureDetector(
      onTap: () => switchTabWithHistory(1),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: AppColors.gradientOrange,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.orange, width: 1.15),
          boxShadow: [
            BoxShadow(
              color: AppColors.orange.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child:
        const Icon(Icons.history_rounded, color: Colors.white, size: 20),
      ),
    );
  }

  // ── Reports button ──────────────────────────────────────────────────
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
              builder: (_) =>
                  ReportsScreen(initialEmployee: widget.employee),
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
  Widget _buildWebSidebar() {
    final w = MediaQuery.of(context).size.width;
    final sidebarWidth = w >= 1200 ? 260.0 : 220.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
        ),
      ),
      child: Column(
        children: [
          _buildWebLogo(),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
                      builder: (_) =>
                          ReportsScreen(initialEmployee: widget.employee),
                    ),
                  ),
                ),
              ],
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
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
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
                  color: AppColors.orange.withValues(alpha: 0.35),
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
    final active = _selectedIndex == item.index;
    final color = active ? _navActive : _navInactive;
    return InkWell(
      onTap: () => switchTabWithHistory(item.index),
      borderRadius: BorderRadius.circular(4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
            active ? color.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.string(item.svg(color), width: 18, height: 18),
            const SizedBox(width: 14),
            Text(
              item.label.toUpperCase(),
              style: TextStyle(
                color:
                active ? AppColors.textPrimary : AppColors.textMuted,
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
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  Widget _buildWebProfileFooter() {
    final emp = widget.employee;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: AppColors.orange.withValues(alpha: 0.12), width: 1),
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

  // ── Mobile Bottom Nav ──────────────────────────────────────────────────
  Widget _buildMobileBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: _navBg,
        border: Border(
          top: BorderSide(color: Color(0xFF27272A), width: 1.15),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ..._navItems.sublist(0, 2).map(_navItemWidget),
              const SizedBox(width: 56),
              ..._navItems.sublist(2, 4).map(_navItemWidget),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItemWidget(_NavData item) {
    final active = _selectedIndex == item.index;
    final color = active ? _navActive : _navInactive;
    return GestureDetector(
      // ✅ Gumamit ng switchTabWithHistory
      onTap: () => switchTabWithHistory(item.index),
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
  static String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2)}';

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
  <path d="M11.9995 11C14.2087 11 15.9995 9.20914 15.9995 7C15.9995 4.79086 14.2087 3 11.9995 3C9.79037 3 11.9995 3 11.9995 3Z" stroke="$s" stroke-width="1.49987" stroke-linecap="round" stroke-linejoin="round"/>
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
  });
}