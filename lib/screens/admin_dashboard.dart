import 'dart:async';
import 'dart:math' show sin, cos, asin, sqrt;
import 'package:flutter/material.dart';
import 'admin_database.dart';
import 'admin_theme.dart';

<<<<<<< HEAD
// Modular View Imports with Aliases
import 'admin_overview_page.dart';
import 'admin_employees_page.dart' as emp_page;
import 'admin_add_employee_page.dart' as add_emp_page;
import 'admin_attendance_page.dart';
import 'admin_attendance_verification_page.dart';
import 'admin_activity_page.dart';
import 'admin_tracking_page.dart';
import 'admin_payroll_page.dart';
import 'admin_payroll_management_page.dart';
=======
// Modular View Imports
import 'admin_overview_page.dart';
import 'admin_employees_page.dart';
import 'admin_add_employee_page.dart';
import 'admin_attendance_page.dart';
import 'admin_activity_page.dart';
import 'admin_tracking_page.dart';
import 'admin_payroll_page.dart';
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

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

class AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;
  String _search = '';
  final _searchCtrl = TextEditingController();

<<<<<<< HEAD
=======
  final _bf1E = TextEditingController();
  final _bf1P = TextEditingController();

>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  List<Map<String, dynamic>> _regLogs = [];
  List<Map<String, dynamic>> _loginLogs = [];
  List<Map<String, dynamic>> _logoutLogs = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _locations = [];
  Map<String, List<Map<String, dynamic>>> _userLogs = {};

  bool _loading = true;
  String? _error;
  Timer? _poll;

<<<<<<< HEAD
  String? _verifyLogId;
  Map<String, dynamic>? _verifyLogData;

  Map<String, dynamic>? _selectedPayrollEmployee;

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

  void openPayrollManagement(Map<String, dynamic> employeeData) {
    setState(() {
      _selectedPayrollEmployee = employeeData;
    });
  }

  void closePayrollManagement() {
    setState(() {
      _selectedPayrollEmployee = null;
    });
  }

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  static const double officeLat = 14.6114;
  static const double officeLng = 120.9936;
  static const double radiusLimit = 1500.0;

<<<<<<< HEAD
  static const Color _bg = Color(0xFFF7F4F1);
  static const Color _sidebarBg = Color(0xFFFFFFFF);
  static const Color _orange = Color(0xFFF3A24B);
  static const Color _orangeDeep = Color(0xFFEE9A3E);
  static const Color _navText = Color(0xFF6B7280);
  static const Color _cardBorder = Color(0xFFECE8E3);
  static const Color _mutedText = Color(0xFF9CA3AF);

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  static const List<_AdminNavItem> _navItems = [
    _AdminNavItem(0, 'Overview', Icons.dashboard_rounded),
    _AdminNavItem(1, 'Employees', Icons.people_rounded),
    _AdminNavItem(2, 'Add Employee', Icons.person_add_rounded),
    _AdminNavItem(3, 'Attendance', Icons.calendar_today_rounded),
    _AdminNavItem(4, 'Activity', Icons.checklist_rounded),
    _AdminNavItem(5, 'Tracking', Icons.location_on_rounded),
    _AdminNavItem(6, 'Payroll', Icons.receipt_long_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _fetchAll());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchCtrl.dispose();
<<<<<<< HEAD
=======
    _bf1E.dispose();
    _bf1P.dispose();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    super.dispose();
  }

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dPhi = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLam = (lon2 - lon1) * 3.141592653589793 / 180;
    final a = sin(dPhi / 2) * sin(dPhi / 2) + cos(lat1 * 3.141592653589793 / 180) * cos(lat2 * 3.141592653589793 / 180) * sin(dLam / 2) * sin(dLam / 2);
    return r * 2 * asin(sqrt(a));
  }

  Future<void> _fetchAll() async {
    try {
      final results = await Future.wait([
        AdminDatabase.getLogs('registration'),
        AdminDatabase.getLogs('login'),
        AdminDatabase.getLogs('logout'),
        AdminDatabase.getEmployees(),
        AdminDatabase.getLocations(),
      ]);

      final emps = (results[3] as List).cast<Map<String, dynamic>>();
      final Map<String, List<Map<String, dynamic>>> ul = {};

      for (final e in emps) {
        final id = (e['id'] ?? '').toString();
        if (id.isNotEmpty) ul[id] = await AdminDatabase.getUserLogs(id);
      }

      if (mounted) {
        setState(() {
          _regLogs = (results[0] as List).cast<Map<String, dynamic>>();
          _loginLogs = (results[1] as List).cast<Map<String, dynamic>>();
          _logoutLogs = (results[2] as List).cast<Map<String, dynamic>>();
          _employees = emps;
          _locations = (results[4] as List).cast<Map<String, dynamic>>();
          _userLogs = ul;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

<<<<<<< HEAD
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _orange)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Error: $_error', style: const TextStyle(color: AdminTheme.red))),
      );
    }
=======
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? AdminTheme.red : AdminTheme.green));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AdminTheme.orange)));
    if (_error != null) return Scaffold(body: Center(child: Text('Error: $_error', style: const TextStyle(color: AdminTheme.red))));
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 768;
      return Scaffold(
<<<<<<< HEAD
        backgroundColor: _bg,
        appBar: buildTopBar(wide),
        drawer: wide ? null : buildDrawer(),
        body: MediaQuery(
          data: MediaQuery.of(context).removePadding(removeTop: true),
          child: wide
              ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildSidebar(),
              Expanded(child: buildPage()),
            ],
          )
              : buildPage(),
        ),
=======
        backgroundColor: AdminTheme.body,
        appBar: buildTopBar(wide),
        drawer: wide ? null : buildDrawer(),
        body: wide ? Row(children: [buildSidebar(), Expanded(child: buildPage())]) : buildPage(),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        bottomNavigationBar: wide ? null : buildBottomNav(),
      );
    });
  }

  PreferredSizeWidget buildTopBar(bool wide) => AppBar(
<<<<<<< HEAD
    backgroundColor: Colors.white,
    foregroundColor: AdminTheme.text,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: 64,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(0.5),
      child: Container(height: 0.5, color: _cardBorder),
    ),
    title: RichText(
      text: const TextSpan(
        style: TextStyle(fontSize: AdminTheme.textLg, fontWeight: FontWeight.w700, fontFamily: 'sans-serif'),
        children: [
          TextSpan(text: 'R.A.C.O.M.A. ', style: TextStyle(color: AdminTheme.text)),
          TextSpan(text: 'Admin', style: TextStyle(color: _mutedText, fontWeight: FontWeight.w400)),
        ],
      ),
    ),
    actions: [
      Container(
        width: wide ? 230 : 160,
        height: 38,
        margin: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: _cardBorder, width: 1)),
        child: Row(children: [
          const SizedBox(width: 12),
          const Icon(Icons.search, color: _mutedText, size: 17),
=======
    backgroundColor: AdminTheme.white,
    foregroundColor: AdminTheme.text,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(0.5),
      child: Container(height: 0.5, color: AdminTheme.border),
    ),
    leading: wide
        ? Padding(
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(color: AdminTheme.orange, borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
        child: const Icon(Icons.fingerprint, color: AdminTheme.white, size: 22),
      ),
    )
        : null,
    title: wide
        ? RichText(
      text: const TextSpan(
        style: TextStyle(fontSize: AdminTheme.textLg, fontWeight: FontWeight.w600, fontFamily: 'sans-serif'),
        children: [
          TextSpan(text: 'R.A.C.O.M.A. ', style: TextStyle(color: AdminTheme.text)),
          TextSpan(text: 'Admin', style: TextStyle(color: AdminTheme.muted, fontWeight: FontWeight.w400)),
        ],
      ),
    )
        : const Text('R.A.C.O.M.A.', style: TextStyle(fontSize: AdminTheme.textLg, fontWeight: FontWeight.w700)),
    actions: [
      Container(
        width: 190, height: 36,
        margin: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(color: AdminTheme.body, borderRadius: BorderRadius.circular(AdminTheme.radius), border: Border.all(color: AdminTheme.border, width: 0.5)),
        child: Row(children: [
          const SizedBox(width: 10),
          const Icon(Icons.search, color: AdminTheme.muted, size: 16),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
<<<<<<< HEAD
              cursorColor: Colors.black,
              style: const TextStyle(color: Colors.black, fontSize: AdminTheme.textBase),
              decoration: const InputDecoration(
                hintText: 'Search logs...',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: _mutedText),
                filled: true,
                fillColor: Colors.white,
              ),
=======
              style: const TextStyle(color: AdminTheme.text, fontSize: AdminTheme.textBase),
              decoration: const InputDecoration(hintText: 'Search context...', border: InputBorder.none, isDense: true),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            ),
          ),
        ]),
      ),
<<<<<<< HEAD
      const SizedBox(width: 10),
      IconButton(icon: const Icon(Icons.notifications_none_rounded, size: 21, color: _navText), onPressed: () {}, tooltip: 'Notifications'),
      IconButton(icon: const Icon(Icons.help_outline_rounded, size: 21, color: _navText), onPressed: () {}, tooltip: 'Help'),
      const SizedBox(width: 4),
      Padding(
        padding: const EdgeInsets.only(right: 16, left: 4),
        child: CircleAvatar(radius: 15, backgroundColor: AdminTheme.text, child: const Icon(Icons.person, size: 16, color: Colors.white)),
      ),
=======
      IconButton(icon: const Icon(Icons.build_circle_outlined, size: 20, color: AdminTheme.grayText), onPressed: _openBackfillDialog, tooltip: 'Backfill Passwords'),
      IconButton(
        icon: const Icon(Icons.refresh_rounded, size: 20, color: AdminTheme.grayText),
        onPressed: () {
          setState(() => _loading = true);
          _fetchAll();
        },
        tooltip: 'Refresh Data',
      ),
      const SizedBox(width: 8),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    ],
  );

  Widget buildSidebar() => Container(
<<<<<<< HEAD
    width: 220,
    color: _sidebarBg,
    child: SafeArea(
      child: Column(children: [
        const SizedBox(height: AdminTheme.s4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AdminTheme.s3),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.front_hand_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('R.A.C.O.M.A.', style: TextStyle(color: _orangeDeep, fontWeight: FontWeight.w800, fontSize: AdminTheme.textBase)),
                  const Text('HRIS', style: TextStyle(color: _mutedText, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.5)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: AdminTheme.s4),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AdminTheme.s3),
            children: _navItems.map((item) => _navTile(item)).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AdminTheme.s3),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(AdminTheme.radius)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Clock System Status', style: TextStyle(color: AdminTheme.text, fontSize: 12, fontWeight: FontWeight.w600)),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AdminTheme.green, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ]),
    ),
=======
    width: 200, color: AdminTheme.navBg,
    child: Column(children: [
      const SizedBox(height: AdminTheme.s4),
      Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: AdminTheme.s2), children: _navItems.map((item) => _navTile(item)).toList())),
    ]),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  );

  Widget _navTile(_AdminNavItem item) {
    final sel = _tab == item.index;
    return GestureDetector(
<<<<<<< HEAD
      onTap: () => setState(() {
        _tab = item.index;
        _selectedPayrollEmployee = null;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: AdminTheme.s3, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? _orange : Colors.transparent,
          borderRadius: BorderRadius.circular(AdminTheme.radius),
        ),
        child: Row(children: [
          Icon(item.icon, color: sel ? Colors.white : _navText, size: 18),
          const SizedBox(width: 12),
          Text(item.label, style: TextStyle(color: sel ? Colors.white : _navText, fontSize: AdminTheme.textBase, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
=======
      onTap: () => setState(() => _tab = item.index),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: AdminTheme.s3, vertical: AdminTheme.s3),
        decoration: BoxDecoration(color: sel ? AdminTheme.orange : Colors.transparent, borderRadius: BorderRadius.circular(AdminTheme.radius)),
        child: Row(children: [
          Icon(item.icon, color: sel ? AdminTheme.white : AdminTheme.navText, size: 18),
          const SizedBox(width: 12),
          Text(item.label, style: TextStyle(color: sel ? AdminTheme.white : AdminTheme.navText, fontSize: AdminTheme.textBase, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ]),
      ),
    );
  }

  Widget buildDrawer() => Drawer(
<<<<<<< HEAD
    backgroundColor: _sidebarBg,
    child: SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(AdminTheme.s3),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.front_hand_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('R.A.C.O.M.A.', style: TextStyle(color: _orangeDeep, fontWeight: FontWeight.w800)),
                const Text('HRIS', style: TextStyle(color: _mutedText, fontSize: 11)),
              ],
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            children: _navItems.map((item) => ListTile(
              leading: Icon(item.icon, color: _tab == item.index ? _orange : _navText),
              title: Text(item.label, style: TextStyle(color: _tab == item.index ? _orangeDeep : _navText, fontWeight: _tab == item.index ? FontWeight.w600 : FontWeight.w400)),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _tab = item.index;
                  _selectedPayrollEmployee = null;
                });
              },
            )).toList(),
          ),
        ),
      ]),
=======
    backgroundColor: AdminTheme.navBg,
    child: SafeArea(
      child: ListView(
        children: _navItems.map((item) => ListTile(
          leading: Icon(item.icon, color: _tab == item.index ? AdminTheme.orange : AdminTheme.navText),
          title: Text(item.label, style: TextStyle(color: _tab == item.index ? AdminTheme.white : AdminTheme.navText)),
          onTap: () { Navigator.pop(context); setState(() => _tab = item.index); },
        )).toList(),
      ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    ),
  );

  Widget buildBottomNav() => BottomNavigationBar(
    currentIndex: _tab >= 4 ? 0 : _tab,
<<<<<<< HEAD
    onTap: (i) => setState(() {
      _tab = i;
      _selectedPayrollEmployee = null;
    }),
    backgroundColor: Colors.white,
    selectedItemColor: _orange, unselectedItemColor: _mutedText,
=======
    onTap: (i) => setState(() => _tab = i),
    selectedItemColor: AdminTheme.orange, unselectedItemColor: AdminTheme.muted,
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    type: BottomNavigationBarType.fixed,
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Overview'),
      BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Staff'),
      BottomNavigationBarItem(icon: Icon(Icons.person_add_rounded), label: 'Add'),
      BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded), label: 'Logs'),
    ],
  );

  Widget buildPage() {
    switch (_tab) {
      case 0:
        return AdminOverviewPage(
          employees: _employees, loginLogs: _loginLogs, logoutLogs: _logoutLogs, regLogs: _regLogs,
          locations: _locations, officeLat: officeLat, officeLng: officeLng, radiusLimit: radiusLimit,
          distanceCalculator: _getDistance, onTabNavigate: (idx) => setState(() => _tab = idx),
        );
      case 1:
<<<<<<< HEAD
        return emp_page.AdminEmployeesPage(
          employees: _employees,
          searchQuery: _search,
          onRefreshNeeded: _fetchAll,
          onAddEmployee: () => setState(() => _tab = 2),
        );
      case 2:
        return add_emp_page.AdminAddEmployeePage(
          onRefreshNeeded: () async {
            await _fetchAll();
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
            : AdminAttendancePage(title: 'Attendance / Logins', logs: _loginLogs, accent: AdminTheme.green, searchQuery: _search, onRefreshNeeded: _fetchAll, locations: _locations);
=======
        return AdminEmployeesPage(employees: _employees, searchQuery: _search, onRefreshNeeded: _fetchAll);
      case 2:
        return AdminAddEmployeePage(onRefreshNeeded: _fetchAll);
      case 3:
        return AdminAttendancePage(title: 'Attendance / Logins', logs: _loginLogs, accent: AdminTheme.green, searchQuery: _search, onRefreshNeeded: _fetchAll);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      case 4:
        return AdminActivityPage(employees: _employees, userLogs: _userLogs, searchQuery: _search);
      case 5:
        return AdminTrackingPage(locations: _locations, officeLat: officeLat, officeLng: officeLng, radiusLimit: radiusLimit, distanceCalculator: _getDistance);
      case 6:
<<<<<<< HEAD
        if (_selectedPayrollEmployee != null) {
          return AdminPayrollManagementPage(employeeData: _selectedPayrollEmployee!);
        }
        return AdminPayrollPage(
          employees: _employees,
          userLogs: _userLogs,
          onSelectEmployee: (emp) => openPayrollManagement(emp), // Ayos na ang lambda wrapper para iwas type mismatch error
        );
=======
        return AdminPayrollPage(employees: _employees, userLogs: _userLogs);
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      default:
        return const Center(child: Text('View not found'));
    }
  }
<<<<<<< HEAD
=======

  void _openBackfillDialog() {
    final missing = _employees.where((e) => (e['password'] ?? '').toString().isEmpty).toList();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AdminTheme.white,
        title: const Text('Backfill Security Hashes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (missing.isEmpty) const Text('All accounts populated.') else ...[
              Text('Missing hashes: ${missing.length}'),
              TextField(controller: _bf1E, decoration: const InputDecoration(labelText: 'Target Email')),
              TextField(controller: _bf1P, decoration: const InputDecoration(labelText: 'Password Injection')),
            ]
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (missing.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.orange, foregroundColor: AdminTheme.white),
              onPressed: () async {
                Navigator.pop(context);
                final map = {_bf1E.text.trim(): _bf1P.text.trim()};
                final msg = await AdminDatabase.backfillPasswords(map);
                _bf1E.clear(); _bf1P.clear();
                _snack(msg ?? 'Task completed');
                _fetchAll();
              },
              child: const Text('Execute Routine'),
            )
        ],
      ),
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}