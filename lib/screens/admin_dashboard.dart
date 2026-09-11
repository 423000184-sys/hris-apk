// lib/screens/admin_dashboard.dart
import 'dart:async';
import 'dart:math' show sin, cos, asin, sqrt, pi;
import 'package:flutter/material.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import 'admin_attendance_page.dart' as attendance;

// Modular View Imports with Aliases
import 'admin_overview_page.dart';
import 'admin_employees_page.dart' as emp_page;
import 'admin_add_employee_page.dart' as add_emp_page;
import 'admin_attendance_verification_page.dart';
import 'admin_activity_page.dart';
import 'admin_tracking_page.dart';
import 'admin_payroll_page.dart';
import 'admin_payroll_management_page.dart';
import 'admin_create_leave_request_page.dart';

class _AdminNavItem {
  final int index;
  final String label;
  final IconData icon;
  const _AdminNavItem(this.index, this.label, this.icon);
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => AdminDashboardState();
}

class AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  int _tab = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _menuIconCtrl;
  late Animation<double> _menuIconRotation;

  // ─── DATA ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];
  Map<String, List<Map<String, dynamic>>> _userLogs = {};

  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _regLogs = [];
  List<Map<String, dynamic>> _loginLogs = [];
  List<Map<String, dynamic>> _logoutLogs = [];

  bool _loading = true;
  String? _error;
  bool _initialLoadDone = false;

  StreamSubscription? _empSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _locSub;

  String? _verifyLogId;
  Map<String, dynamic>? _verifyLogData;
  Map<String, dynamic>? _selectedPayrollEmployee;

  AdminColors get _c => ThemeProvider.instance.colors;

  static const double officeLat = 14.6114;
  static const double officeLng = 120.9936;
  static const double radiusLimit = 1500.0;

  static const List<_AdminNavItem> _navItems = [
    _AdminNavItem(0, 'Overview', Icons.grid_view_rounded),
    _AdminNavItem(1, 'Employees', Icons.people_alt_rounded),
    _AdminNavItem(2, 'Add Employee', Icons.person_add_alt_1_rounded),
    _AdminNavItem(3, 'Attendance', Icons.calendar_month_rounded),
    _AdminNavItem(4, 'Activity', Icons.checklist_rounded),
    _AdminNavItem(5, 'Tracking', Icons.location_on_rounded),
    _AdminNavItem(6, 'Payroll', Icons.receipt_long_rounded),
  ];

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dPhi = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLam = (lon2 - lon1) * 3.141592653589793 / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(lat1 * 3.141592653589793 / 180) *
            cos(lat2 * 3.141592653589793 / 180) *
            sin(dLam / 2) *
            sin(dLam / 2);
    return r * 2 * asin(sqrt(a));
  }

  @override
  void initState() {
    super.initState();

    _menuIconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _menuIconRotation = Tween<double>(begin: 0, end: 0.25).animate(
      CurvedAnimation(parent: _menuIconCtrl, curve: Curves.easeOutCubic),
    );

    ThemeProvider.instance.addListener(_onThemeChanged);
    _loadEmployees();
    _setupStreams();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeProvider.instance.removeListener(_onThemeChanged);
    _menuIconCtrl.dispose();
    _empSub?.cancel();
    _attendanceSub?.cancel();
    _locSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // NAVIGATION METHODS
  // ══════════════════════════════════════════════════════════════

  void openAttendanceVerification(String logId, Map<String, dynamic> logData) {
    setState(() {
      _verifyLogId = logId;
      _verifyLogData = logData;
      _tab = 3;
    });
  }

  void closeAttendanceVerification() {
    setState(() {
      _verifyLogId = null;
      _verifyLogData = null;
    });
  }

  // ✅ Open Payroll Detail
  void openPayrollManagement(Map<String, dynamic> employeeData) {
    debugPrint('🟢 openPayrollManagement: ${employeeData['name']}');
    setState(() => _selectedPayrollEmployee = employeeData);
  }

  // ✅ Close Payroll Detail — BABALIK SA PAYROLL LIST
  void closePayrollManagement() {
    debugPrint('🔵 closePayrollManagement: back to payroll list');
    setState(() {
      _selectedPayrollEmployee = null;
    });
  }

  bool _showCreateLeave = false;

  void _openCreateLeaveRequest() {
    setState(() => _showCreateLeave = true);
  }

  void _closeCreateLeaveRequest() {
    setState(() => _showCreateLeave = false);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  // ══════════════════════════════════════════════════════════════
  // DATA LOADING
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadEmployees() async {
    try {
      final emps = await AdminDatabase.getEmployees();
      debugPrint('✅ _loadEmployees: ${emps.length} employees loaded');
      if (mounted) {
        setState(() {
          _employees = emps;
          _loading = false;
          _error = null;
          _buildUserLogs();
          _initialLoadDone = true;
        });
      }
    } catch (e) {
      debugPrint('❌ _loadEmployees error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _setupStreams() {
    _empSub = AdminDatabase.streamEmployees().listen(
          (emps) {
        if (mounted) {
          if (_initialLoadDone && emps.isEmpty) return;
          setState(() {
            _employees = emps;
            _buildUserLogs();
            if (!_initialLoadDone) {
              _loading = false;
              _initialLoadDone = true;
            }
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      },
    );

    _attendanceSub = AdminDatabase.streamAttendanceLogs().listen(
          (logs) {
        if (mounted) {
          setState(() {
            _attendanceLogs = logs;
            _loginLogs = logs
                .where((l) => l['type'] == 'IN' || l['type'] == 'LOGIN')
                .toList();
            _logoutLogs = logs
                .where((l) => l['type'] == 'OUT' || l['type'] == 'LOGOUT')
                .toList();
          });
        }
      },
      onError: (e) => debugPrint('Attendance stream error: $e'),
    );

    _locSub = AdminDatabase.streamLocations().listen(
          (locs) {
        if (mounted) setState(() => _locations = locs);
      },
      onError: (e) => debugPrint('Locations stream error: $e'),
    );

    _fetchActivityLogs();
  }

  Future<void> _fetchActivityLogs() async {
    try {
      final results = await Future.wait([
        AdminDatabase.getLogs('registration'),
        AdminDatabase.getLogs('login'),
        AdminDatabase.getLogs('logout'),
      ]);

      if (mounted) {
        setState(() {
          _regLogs = (results[0] as List).cast<Map<String, dynamic>>();
          _regLogs.addAll(_loginLogs);
          _regLogs.addAll(_logoutLogs);
        });
      }
    } catch (e) {
      debugPrint('Activity logs fetch error: $e');
    }
  }

  void _buildUserLogs() {
    final Map<String, List<Map<String, dynamic>>> ul = {};
    for (final e in _employees) {
      final id = (e['id'] ?? '').toString();
      if (id.isNotEmpty) {
        final userAttendance = _attendanceLogs
            .where((log) => (log['employee_id'] ?? '').toString() == id)
            .toList();
        ul[id] = userAttendance;
      }
    }
    setState(() => _userLogs = ul);
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    await _loadEmployees();
    _fetchActivityLogs();
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeProvider.instance,
      builder: (context, _) {
        return Theme(
          data: ThemeProvider.instance.theme,
          child: _buildShell(context),
        );
      },
    );
  }

  Widget _buildShell(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _c.background,
        body: Center(child: CircularProgressIndicator(color: _c.orange)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _c.background,
        body: Center(
          child: Text('Error: $_error', style: TextStyle(color: _c.red)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (_, c) {
        final wide = c.maxWidth >= 768;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _c.background,
          appBar: buildTopBar(wide),
          drawer: wide ? null : buildDrawer(),
          onDrawerChanged: (isOpened) {
            if (isOpened) {
              _menuIconCtrl.forward();
            } else {
              _menuIconCtrl.reverse();
            }
          },
          body: MediaQuery(
            data: MediaQuery.of(context).removePadding(removeTop: true),
            child: wide
                ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSidebar(),
                Expanded(child: buildPage()),
              ],
            )
                : buildPage(),
          ),
          bottomNavigationBar: wide ? null : buildBottomNav(),
        );
      },
    );
  }

  Widget _buildAnimatedMenuIcon(Color color) {
    return AnimatedBuilder(
      animation: _menuIconRotation,
      builder: (context, _) {
        return Transform.rotate(
          angle: _menuIconRotation.value * 2 * pi,
          child: Icon(Icons.menu_rounded, color: color, size: 22),
        );
      },
    );
  }

  PreferredSizeWidget buildTopBar(bool wide) {
    final c = _c;
    return AppBar(
      backgroundColor: c.topBarBg,
      foregroundColor: c.accent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 64,
      leading: wide
          ? null
          : IconButton(
        icon: _buildAnimatedMenuIcon(c.accent),
        onPressed: _openDrawer,
        tooltip: 'Open menu',
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.navBorder),
      ),
      title: Text(
        'R.A.C.O.M.A. Admin',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.accent,
          fontFamily: 'sans-serif',
        ),
      ),
      actions: [
        if (wide)
          Container(
            width: 260,
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.navBorder, width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search_rounded, color: c.navText, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    cursorColor: c.accent,
                    style: TextStyle(color: c.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search logs...',
                      border: InputBorder.none,
                      isDense: true,
                      hintStyle: TextStyle(
                        color: c.isDark ? c.muted : c.navText,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (wide) const SizedBox(width: 12),
        IconButton(
          tooltip: ThemeProvider.instance.isDark
              ? 'Switch to Light Mode'
              : 'Switch to Dark Mode',
          onPressed: () => ThemeProvider.instance.toggleDarkMode(),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => RotationTransition(
              turns: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              ThemeProvider.instance.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              key: ValueKey(ThemeProvider.instance.isDark),
              size: 20,
              color: c.accent,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.notifications_none_rounded,
              size: 21, color: c.accent),
          onPressed: () {},
          tooltip: 'Notifications',
        ),
        IconButton(
          icon: Icon(Icons.help_outline_rounded, size: 21, color: c.accent),
          onPressed: () {},
          tooltip: 'Help',
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: 0.15),
              border: Border.all(color: c.navBorder, width: 1),
            ),
            child: Icon(Icons.person_rounded, size: 16, color: c.accent),
          ),
        ),
      ],
    );
  }

  Widget buildSidebar() {
    final c = _c;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: c.navBg,
        border: Border(right: BorderSide(color: c.navBorder, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.sidebarLogoBox,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.front_hand_rounded,
                      color: c.isDark
                          ? Colors.white
                          : const Color(0xFF53433C),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'R.A.C.O.M.A.',
                          style: TextStyle(
                            color: c.sidebarBrandText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'HRIS',
                          style: TextStyle(
                            color: c.navText,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _navItems.map((item) => _navTile(item)).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: c.clockCardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: c.isDark
                        ? c.navBorder.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Clock System Status',
                        style: TextStyle(
                          color: c.clockCardText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.clockDotColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.clockDotColor.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile(_AdminNavItem item) {
    final c = _c;
    final sel = _tab == item.index;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: sel ? c.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            _tab = item.index;
            _selectedPayrollEmployee = null;
            if (_showCreateLeave) _showCreateLeave = false;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: sel ? c.sidebarActiveText : c.navText,
                  size: 18,
                ),
                const SizedBox(width: 14),
                Text(
                  item.label,
                  style: TextStyle(
                    color: sel ? c.sidebarActiveText : c.navText,
                    fontSize: 14,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildDrawer() {
    final c = _c;
    return Drawer(
      backgroundColor: c.navBg,
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(-30 * (1 - value), 0),
                child: child,
              ),
            );
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c.sidebarLogoBox,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.front_hand_rounded,
                        color: c.isDark
                            ? Colors.white
                            : const Color(0xFF53433C),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'R.A.C.O.M.A.',
                          style: TextStyle(
                            color: c.sidebarBrandText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'HRIS',
                          style: TextStyle(
                            color: c.navText,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(color: c.navBorder, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: _navItems.map((item) {
                    final sel = _tab == item.index;
                    return ListTile(
                      leading: Icon(
                        item.icon,
                        color: sel ? c.sidebarActiveText : c.navText,
                        size: 20,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: sel ? c.sidebarActiveText : c.navText,
                          fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      selected: sel,
                      selectedTileColor: c.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _tab = item.index;
                          _selectedPayrollEmployee = null;
                          if (_showCreateLeave) _showCreateLeave = false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBottomNav() {
    final c = _c;
    return BottomNavigationBar(
      currentIndex: _tab >= 4 ? 0 : _tab,
      onTap: (i) => setState(() {
        _tab = i;
        _selectedPayrollEmployee = null;
        if (_showCreateLeave) _showCreateLeave = false;
      }),
      backgroundColor: c.navBg,
      selectedItemColor: c.orange,
      unselectedItemColor: c.navText,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view_rounded),
          label: 'Overview',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_alt_rounded),
          label: 'Staff',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_add_alt_1_rounded),
          label: 'Add',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month_rounded),
          label: 'Logs',
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PAGE ROUTER
  // ══════════════════════════════════════════════════════════════
  Widget buildPage() {
    if (_showCreateLeave) {
      return AdminCreateLeaveRequestPage(
        employees: _employees,
        onBack: _closeCreateLeaveRequest,
      );
    }

    switch (_tab) {
      case 0:
        return AdminOverviewPage(
          employees: _employees,
          loginLogs: _loginLogs,
          logoutLogs: _logoutLogs,
          regLogs: _regLogs,
          locations: _locations,
          officeLat: officeLat,
          officeLng: officeLng,
          radiusLimit: radiusLimit,
          distanceCalculator: _getDistance,
          onTabNavigate: (idx) => setState(() => _tab = idx),
        );
      case 1:
        return emp_page.AdminEmployeesPage(
          employees: _employees,
          searchQuery: _search,
          onRefreshNeeded: _refreshAll,
          onAddEmployee: () => setState(() => _tab = 2),
        );
      case 2:
        return add_emp_page.AdminAddEmployeePage(
          onRefreshNeeded: () async {
            await _refreshAll();
            setState(() => _tab = 1);
          },
        );
      case 3:
        return _verifyLogData != null
            ? AdminAttendanceVerificationPage(
          logId: _verifyLogId ?? '',
          logData: _verifyLogData!,
          onBack: closeAttendanceVerification,
        )
            : attendance.AdminAttendancePage(
          title: 'Attendance Logs',
          logs: _attendanceLogs,
          accent: _c.green,
          searchQuery: _search,
          onRefreshNeeded: _refreshAll,
          locations: _locations,
        );
      case 4:
        return AdminActivityPage(
          employees: _employees,
          userLogs: _userLogs,
          searchQuery: _search,
          onCreateLeaveRequest: _openCreateLeaveRequest,
        );
      case 5:
        return AdminTrackingPage(
          locations: _locations,
          officeLat: officeLat,
          officeLng: officeLng,
          radiusLimit: radiusLimit,
          distanceCalculator: _getDistance,
        );
      case 6:
        if (_selectedPayrollEmployee != null) {
          final empId =
              _selectedPayrollEmployee!['id']?.toString() ?? 'unknown';
          debugPrint('🟠 Showing payroll detail for: $empId');
          return AdminPayrollManagementPage(
            key: ValueKey('payroll_$empId'),
            employeeData: _selectedPayrollEmployee!,
            // ✅ Back button wiring
            onBack: closePayrollManagement,
          );
        }
        return AdminPayrollPage(
          employees: _employees,
          userLogs: _userLogs,
          onSelectEmployee: (emp) => openPayrollManagement(emp),
        );
      default:
        return const Center(child: Text('View not found'));
    }
  }
}