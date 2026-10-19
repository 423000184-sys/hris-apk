// lib/screens/admin_dashboard.dart
// v1.1: 🎭 Added Demo Mode bypass in Auth Guard
import 'dart:async';
import 'dart:math' show sin, cos, asin, sqrt, pi;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_database.dart';
import 'admin_theme.dart';
import 'admin_attendance_page.dart' as attendance;

import 'admin_overview_page.dart';
import 'admin_employees_page.dart' as emp_page;
import 'admin_add_employee_page.dart' as add_emp_page;
import 'admin_attendance_verification_page.dart';
import 'admin_activity_page.dart';
import 'admin_tracking_page.dart';
import 'admin_payroll_page.dart';
import 'admin_payroll_management_page.dart';
import 'admin_create_leave_request_page.dart';
import 'admin_assign_client_meeting_page.dart';
import 'admin_add_client_location_page.dart';
import 'admin_login_screen.dart';
import 'admin_presence_monitor_screen.dart';
import 'admin_password_change_requests_page.dart';

import '../widgets/admin_notification_bell.dart';
import '../services/employee_notification_service.dart';
import '../services/admin_auth_service.dart';
import '../services/demo_mode_service.dart'; // 🎭 Idinagdag para sa Demo Mode

import '../services/presence_monitor_service.dart';
import '../services/presence_backup_service.dart';
import '../services/notification_backup_service.dart';
import 'notification_backup_list_page.dart';

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
  final _searchFocus = FocusNode();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late AnimationController _menuIconCtrl;
  late Animation<double> _menuIconRotation;

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

  bool _showCreateLeave = false;

  AdminColors get _c => ThemeProvider.instance.colors;

  static const double officeLat = 14.6114;
  static const double officeLng = 120.9936;
  static const double radiusLimit = 1500.0;

  // ═══════════════════════════════════════════════════════════════
  // NAV ITEMS — may Live Presence + Password Requests
  // ═══════════════════════════════════════════════════════════════
  static const List<_AdminNavItem> _navItems = [
    _AdminNavItem(0, 'Overview', Icons.grid_view_rounded),
    _AdminNavItem(1, 'Employees', Icons.people_alt_rounded),
    _AdminNavItem(2, 'Add Employee', Icons.person_add_alt_1_rounded),
    _AdminNavItem(3, 'Attendance', Icons.calendar_month_rounded),
    _AdminNavItem(4, 'Activity', Icons.checklist_rounded),
    _AdminNavItem(5, 'Tracking', Icons.location_on_rounded),
    _AdminNavItem(6, 'Payroll', Icons.receipt_long_rounded),
    _AdminNavItem(7, 'Live Presence', Icons.radar_rounded),
    _AdminNavItem(15, 'Password Requests', Icons.lock_reset_rounded), // 🔑 NEW
  ];

  String get _searchHint {
    switch (_tab) {
      case 0:
        return 'Search not available here';
      case 1:
        return 'Search employees...';
      case 2:
        return 'Search not available here';
      case 3:
        return 'Search attendance logs...';
      case 4:
        return 'Search activity logs...';
      case 5:
        return 'Search not available here';
      case 6:
        return 'Search not available here';
      case 7:
        return 'Search not available here';
      case 15:
        return 'Search password change requests...';
      default:
        return 'Search...';
    }
  }

  bool get _isSearchAvailable {
    if (_showCreateLeave) return false;
    return _tab == 1 || _tab == 3 || _tab == 4;
  }

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

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔑 ADMIN UID:   ${FirebaseAuth.instance.currentUser?.uid}');
    debugPrint('📧 ADMIN EMAIL: ${FirebaseAuth.instance.currentUser?.email}');
    debugPrint('═══════════════════════════════════════════');

    _menuIconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _menuIconRotation = Tween<double>(begin: 0, end: 0.25).animate(
      CurvedAnimation(parent: _menuIconCtrl, curve: Curves.easeOutCubic),
    );

    ThemeProvider.instance.addListener(_onThemeChanged);

    NotificationBackupService.instance.init();

    _loadEmployees();
    _setupStreams();

    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
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
    _searchFocus.dispose();
    super.dispose();
  }

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
    debugPrint('🟢 openPayrollManagement: ${employeeData['name']}');
    setState(() => _selectedPayrollEmployee = employeeData);
  }

  void closePayrollManagement() {
    debugPrint('🔵 closePayrollManagement: back to payroll list');
    setState(() {
      _selectedPayrollEmployee = null;
    });
  }

  void _openCreateLeaveRequest() {
    setState(() => _showCreateLeave = true);
  }

  void _closeCreateLeaveRequest() {
    setState(() => _showCreateLeave = false);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _handleNavTap(int index) {
    debugPrint('🧭 [Nav] switching to tab $index');
    _searchCtrl.clear();
    setState(() {
      _tab = index;
      _search = '';
      _selectedPayrollEmployee = null;
      if (_showCreateLeave) _showCreateLeave = false;
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _search = '');
    _searchFocus.unfocus();
  }

  Future<void> _handleSignOut(AdminColors c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: c.red, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sign out?',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'You will be signed out.',
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Sign out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AdminAuthService.instance.signOut();
    if (!mounted) return;

    // 🎭 Kung Demo Mode, i-off ito bago mag-sign out
    if (DemoModeService.instance.isEnabled) {
      await DemoModeService.instance.endDemoSession();
    }

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminLoginScreen(forceLogout: true)),
          (_) => false,
    );
  }

  void _openSendUpdateDialog(BuildContext context, AdminColors c) {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    String selectedType = 'announcement';
    String selectedRecipient = 'ALL';
    String selectedPriority = 'normal';

    InputDecoration dropDeco(String hint) => InputDecoration(
      filled: true,
      fillColor: c.surface,
      hintText: hint,
      hintStyle: TextStyle(color: c.muted),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c.orange, width: 1.5),
      ),
    );

    TextStyle itemStyle() => TextStyle(color: c.text, fontSize: 14);

    InputDecoration fieldDeco(String hint, {int? maxLines}) =>
        InputDecoration(
          filled: true,
          fillColor: c.surface,
          hintText: hint,
          hintStyle: TextStyle(color: c.muted),
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: c.orange, width: 1.5),
          ),
        );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: c.card,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.campaign_rounded, color: c.orange, size: 22),
              const SizedBox(width: 10),
              Text(
                'Send Update',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Type',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    dropdownColor: c.card,
                    iconEnabledColor: c.text,
                    style: itemStyle(),
                    decoration: dropDeco('Select type'),
                    items: [
                      DropdownMenuItem(
                          value: 'announcement',
                          child: Text('📢 Announcement', style: itemStyle())),
                      DropdownMenuItem(
                          value: 'payroll',
                          child: Text('💰 Payroll', style: itemStyle())),
                      DropdownMenuItem(
                          value: 'reminder',
                          child: Text('⏰ Reminder', style: itemStyle())),
                      DropdownMenuItem(
                          value: 'general',
                          child: Text('📋 General', style: itemStyle())),
                    ],
                    onChanged: (v) => setDlgState(
                            () => selectedType = v ?? 'announcement'),
                  ),
                  const SizedBox(height: 12),
                  Text('Recipient',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedRecipient,
                    dropdownColor: c.card,
                    isExpanded: true,
                    iconEnabledColor: c.text,
                    style: itemStyle(),
                    decoration: dropDeco('Select recipient'),
                    items: [
                      DropdownMenuItem(
                          value: 'ALL',
                          child: Text('🌐 All Employees',
                              style: itemStyle())),
                      ..._employees
                          .where((e) => e['terminated'] != true)
                          .map((e) {
                        final id =
                        (e['id'] ?? e['employeeId'] ?? '').toString();
                        final name = (e['name'] ??
                            '${e['firstName'] ?? ''} ${e['lastName'] ?? ''}')
                            .toString()
                            .trim();
                        return DropdownMenuItem(
                          value: id,
                          child: Text(
                            '${name.isEmpty ? "Unknown" : name} ($id)',
                            overflow: TextOverflow.ellipsis,
                            style: itemStyle(),
                          ),
                        );
                      }).toList(),
                    ],
                    onChanged: (v) => setDlgState(
                            () => selectedRecipient = v ?? 'ALL'),
                  ),
                  const SizedBox(height: 12),
                  Text('Priority',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedPriority,
                    dropdownColor: c.card,
                    iconEnabledColor: c.text,
                    style: itemStyle(),
                    decoration: dropDeco('Select priority'),
                    items: [
                      DropdownMenuItem(
                          value: 'low',
                          child: Text('Low', style: itemStyle())),
                      DropdownMenuItem(
                          value: 'normal',
                          child: Text('Normal', style: itemStyle())),
                      DropdownMenuItem(
                          value: 'high',
                          child: Text('High', style: itemStyle())),
                    ],
                    onChanged: (v) => setDlgState(
                            () => selectedPriority = v ?? 'normal'),
                  ),
                  const SizedBox(height: 12),
                  Text('Title',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: TextStyle(color: c.text),
                    cursorColor: c.orange,
                    decoration: fieldDeco('e.g. Team Meeting Tomorrow'),
                  ),
                  const SizedBox(height: 12),
                  Text('Message',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.muted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: messageCtrl,
                    maxLines: 4,
                    style: TextStyle(color: c.text),
                    cursorColor: c.orange,
                    decoration: fieldDeco(
                        'Write your message for the employee(s)...'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: c.muted)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final message = messageCtrl.text.trim();
                if (title.isEmpty || message.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in both title and message.'),
                      backgroundColor: Color(0xFFEF4444),
                    ),
                  );
                  return;
                }

                try {
                  await EmployeeNotificationService.instance.send(
                    type: selectedType,
                    title: title,
                    message: message,
                    employeeId: selectedRecipient,
                    priority: selectedPriority,
                  );

                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        selectedRecipient == 'ALL'
                            ? '✅ Sent to ALL employees'
                            : '✅ Sent to 1 employee',
                      ),
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text(
                'Send',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresenceDialog(BuildContext context, AdminColors c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.location_searching_rounded,
                        color: c.orange, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Presence & Backup',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Test the presence monitor and backup system',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 20),

                _debugTile(
                  c: c,
                  icon: Icons.backup_rounded,
                  title: 'Force Backup Now',
                  subtitle: 'Append the latest 20 notifications to the log',
                  color: const Color(0xFF16A34A),
                  onTap: () async {
                    Navigator.pop(ctx);
                    _showSnack('💾 Creating backup...');
                    try {
                      final count = await NotificationBackupService
                          .instance
                          .forceBackupNow(limit: 20);
                      _showSnack(
                        count > 0
                            ? '✅ $count entries added to log!'
                            : '⚠️ No new notifications to back up',
                      );
                    } catch (e) {
                      _showSnack('❌ Backup failed: $e');
                    }
                  },
                ),

                const SizedBox(height: 12),
                Text(
                  '💡 Tip: Tap the 📁 folder icon in the AppBar to view the notification log.',
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _debugTile({
    required AdminColors c,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: c.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

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
    _userLogs = ul;
  }

  Future<void> _refreshAll() async {
    if (!_initialLoadDone) {
      setState(() => _loading = true);
    }
    await _loadEmployees();
    _fetchActivityLogs();
  }

  @override
  Widget build(BuildContext context) {
    // 🎭 1. DEMO MODE BYPASS
    // Kung naka-Demo mode, wag na tignan ang Firebase Auth.
    // Deretso na agad sa Dashboard Shell!
    if (DemoModeService.instance.isEnabled) {
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

    // 2. NORMAL AUTH CHECK (Kung hindi Demo Mode)
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: _c.background,
            body: Center(
              child: CircularProgressIndicator(color: _c.orange),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const AdminLoginScreen();
        }

        return AnimatedBuilder(
          animation: ThemeProvider.instance,
          builder: (context, _) {
            return Theme(
              data: ThemeProvider.instance.theme,
              child: _buildShell(context),
            );
          },
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

  Widget _buildSearchBar(AdminColors c, {bool compact = false}) {
    final hasText = _searchCtrl.text.isNotEmpty;
    final isFocused = _searchFocus.hasFocus;
    final available = _isSearchAvailable;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: compact ? 200 : 260,
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: !available
              ? c.navBorder.withValues(alpha: 0.4)
              : (isFocused
              ? c.accent
              : (c.isDark
              ? c.navBorder
              : c.navBorder.withValues(alpha: 0.6))),
          width: isFocused && available ? 1.5 : 1,
        ),
        boxShadow: (isFocused && available)
            ? [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.15),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            available ? Icons.search_rounded : Icons.search_off_rounded,
            color: !available
                ? c.muted
                : (isFocused ? c.accent : c.navText),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              enabled: available,
              onChanged: (v) => setState(() => _search = v),
              onSubmitted: (v) {
                debugPrint('🔍 Search submitted on tab $_tab: "$v"');
                _searchFocus.unfocus();
              },
              cursorColor: c.accent,
              style: TextStyle(
                color: available ? c.text : c.muted,
                fontSize: 14,
              ),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: available
                    ? _searchHint
                    : 'Search not available on this page',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintStyle: TextStyle(
                  color: c.isDark ? c.muted : c.navText,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (hasText && available)
            GestureDetector(
              onTap: _clearSearch,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c.muted.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: c.text,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }

  PreferredSizeWidget buildTopBar(bool wide) {
    final c = _c;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;
    final isTiny = screenWidth < 360;

    return AppBar(
      backgroundColor: c.topBarBg,
      foregroundColor: c.accent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 56,
      leading: wide
          ? null
          : IconButton(
        icon: _buildAnimatedMenuIcon(c.accent),
        onPressed: _openDrawer,
        tooltip: 'Open menu',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
            minWidth: 44, minHeight: 44),
      ),
      leadingWidth: wide ? null : (isTiny ? 40 : 48),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: c.navBorder),
      ),
      title: Text(
        isTiny ? 'R.A.C.O.M.A.' : 'R.A.C.O.M.A. Admin',
        style: TextStyle(
          fontSize: isTiny ? 15 : (isNarrow ? 16 : 18),
          fontWeight: FontWeight.w700,
          color: c.accent,
          fontFamily: 'sans-serif',
        ),
        overflow: TextOverflow.ellipsis,
      ),
      titleSpacing: wide ? null : 0,
      actions: [
        if (wide) ...[
          _buildSearchBar(c, compact: false),
          const SizedBox(width: 12),
        ] else if (!isTiny) ...[
          _buildSearchBar(c, compact: true),
          const SizedBox(width: 4),
        ],

        IconButton(
          tooltip: ThemeProvider.instance.isDark
              ? 'Switch to Light Mode'
              : 'Switch to Dark Mode',
          onPressed: () => ThemeProvider.instance.toggleDarkMode(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
              minWidth: 40, minHeight: 40),
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

        AdminNotificationBell(iconColor: c.accent),

        if (wide) ...[
          IconButton(
            tooltip: 'Send Update to Employees',
            onPressed: () => _openSendUpdateDialog(context, c),
            icon: Icon(Icons.campaign_rounded, size: 21, color: c.accent),
          ),
          IconButton(
            tooltip: 'Live Presence Monitor',
            onPressed: () => _handleNavTap(7),
            icon: Icon(
              Icons.radar_rounded,
              size: 21,
              color: c.accent,
            ),
          ),
          // 🔑 NEW — Password Change Requests shortcut
          IconButton(
            tooltip: 'Password Change Requests',
            onPressed: () => _handleNavTap(15),
            icon: Icon(
              Icons.lock_reset_rounded,
              size: 21,
              color: c.accent,
            ),
          ),
          IconButton(
            tooltip: 'Presence & Backup',
            onPressed: () => _showPresenceDialog(context, c),
            icon: Icon(
              Icons.location_searching_rounded,
              size: 21,
              color: c.accent,
            ),
          ),
          IconButton(
            tooltip: 'Notification Backups',
            onPressed: () {
              Navigator.push(
                context,
                adminRoute(const NotificationBackupListPage()),
              );
            },
            icon: Icon(
              Icons.folder_special_rounded,
              size: 21,
              color: c.accent,
            ),
          ),
        ],

        if (!wide)
          PopupMenuButton<String>(
            tooltip: 'More',
            color: c.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert_rounded,
                color: c.accent, size: 22),
            onSelected: (v) {
              if (v == 'send_update') {
                _openSendUpdateDialog(context, c);
              } else if (v == 'live_presence') {
                _handleNavTap(7);
              } else if (v == 'password_requests') {
                _handleNavTap(15); // 🔑 NEW
              } else if (v == 'presence') {
                _showPresenceDialog(context, c);
              } else if (v == 'backups') {
                Navigator.push(
                  context,
                  adminRoute(const NotificationBackupListPage()),
                );
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'send_update',
                child: Row(children: [
                  Icon(Icons.campaign_rounded,
                      size: 18, color: c.orange),
                  const SizedBox(width: 10),
                  Text('Send Update',
                      style: TextStyle(color: c.text, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'live_presence',
                child: Row(children: [
                  Icon(Icons.radar_rounded,
                      size: 18, color: c.orange),
                  const SizedBox(width: 10),
                  Text('Live Presence Monitor',
                      style: TextStyle(color: c.text, fontSize: 13)),
                ]),
              ),
              // 🔑 NEW — Password Requests
              PopupMenuItem(
                value: 'password_requests',
                child: Row(children: [
                  Icon(Icons.lock_reset_rounded,
                      size: 18, color: c.orange),
                  const SizedBox(width: 10),
                  Text('Password Requests',
                      style: TextStyle(color: c.text, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'presence',
                child: Row(children: [
                  Icon(Icons.location_searching_rounded,
                      size: 18, color: c.orange),
                  const SizedBox(width: 10),
                  Text('Presence & Backup',
                      style: TextStyle(color: c.text, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'backups',
                child: Row(children: [
                  Icon(Icons.folder_special_rounded,
                      size: 18, color: c.orange),
                  const SizedBox(width: 10),
                  Text('Notification Backups',
                      style: TextStyle(color: c.text, fontSize: 13)),
                ]),
              ),
            ],
          ),

        SizedBox(width: wide ? 16 : 4),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _handleSignOut(c),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: c.red.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: c.red,
                          size: 18,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Sign Out',
                          style: TextStyle(
                            color: c.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
          onTap: () => _handleNavTap(item.index),
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
                        _handleNavTap(item.index);
                      },
                    );
                  }).toList(),
                ),
              ),
              Divider(color: c.navBorder, height: 1),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: c.red, size: 20),
                title: Text(
                  'Sign Out',
                  style: TextStyle(
                    color: c.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                onTap: () {
                  Navigator.pop(context);
                  _handleSignOut(c);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildBottomNav() {
    final c = _c;
    int bottomIndex;
    if (_tab >= 0 && _tab <= 3) {
      bottomIndex = _tab;
    } else {
      bottomIndex = 0;
    }

    return BottomNavigationBar(
      currentIndex: bottomIndex,
      onTap: (i) => _handleNavTap(i),
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

  // ═══════════════════════════════════════════════════════════════
  // BUILD PAGE — may Password Requests na
  // ═══════════════════════════════════════════════════════════════
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
          onAssignClientMeeting: () => _handleNavTap(7),
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
          return AdminPayrollManagementPage(
            key: ValueKey('payroll_$empId'),
            employeeData: _selectedPayrollEmployee!,
            onBack: closePayrollManagement,
          );
        }
        return AdminPayrollPage(
          employees: _employees,
          userLogs: _userLogs,
          onSelectEmployee: (emp) => openPayrollManagement(emp),
        );

      case 7:
        return const AdminPresenceMonitorScreen();

      case 8:
        return AdminAssignClientMeetingPage(
          employees: _employees,
          embedded: true,
          currentAdminId: 'admin',
          currentAdminName: 'Admin',
          onBack: () => _handleNavTap(0),
          onTabNavigate: (idx) => _handleNavTap(idx),
        );
      case 9:
        return AdminAddClientLocationPage(
          embedded: true,
          onBack: () => _handleNavTap(7),
          onSaved: () {},
          onTabNavigate: (idx) => _handleNavTap(idx),
        );

      case 15:
        return const PasswordChangeRequestsPage();

      default:
        return const Center(child: Text('View not found'));
    }
  }
}