// lib/screens/admin_notification_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import '../services/admin_notification_alert_service.dart';
import '../services/admin_support_actions_service.dart';
import '../services/security_hardening_service.dart';
import '../services/support_reply_service.dart';
import '../services/demo_mode_service.dart';
import '../services/onesignal_sender.dart';
import 'admin_theme.dart';

// 🧭 MGA TOTOONG SCREENS MO
import 'admin_challenge_details_screen.dart';
import 'admin_attendance_page.dart';
import 'admin_presence_page.dart';
import 'admin_create_leave_request_page.dart';
import 'admin_edit_employee_page.dart';
import 'admin_employees_page.dart'; // Ginamit bilang fallback sa password change

void _secureLog(String msg) {
  if (kDebugMode) debugPrint('[AdminNotif] $msg');
}

enum _SortMode { newest, oldest, priority }

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _query = '';
  _SortMode _sortMode = _SortMode.newest;

  final List<DateTime> _destructiveActionTimes = [];
  static const int _maxDestructivePerWindow = 5;
  static const Duration _rateWindow = Duration(seconds: 30);
  static const int _maxSearchLength = 80;

  Timer? _searchDebounce;

  bool get _isDemo {
    try {
      return DemoModeService.instance.isEnabled;
    } catch (_) {
      return false;
    }
  }

  void _demoBlock() {
    _showSnack('Action disabled in Demo Mode.');
  }

  List<AdminNotification> _getMockNotifications() {
    final now = DateTime.now();
    return [
      AdminNotification(
        id: 'demo_n1',
        type: 'support_request',
        title: 'Support: Cannot download payslip PDF',
        message: 'Hi admin, hindi ko ma-download yung payslip ko. Error: file not found.',
        timestamp: now.subtract(const Duration(minutes: 5)),
        read: false,
        priority: 'high',
        employeeName: 'John Doe',
        employeeId: 'DEMO-001',
        metadata: const {
          'status': 'pending',
          'category': 'pdf_download',
          'categoryLabel': 'PDF Download',
        },
      ),
      AdminNotification(
        id: 'demo_n2',
        type: 'support_request',
        title: 'Support: Forgot PDF password',
        message: 'Nakalimutan ko yung password ng payslip PDF ko. Paano ito ma-open?',
        timestamp: now.subtract(const Duration(minutes: 18)),
        read: false,
        priority: 'high',
        employeeName: 'Jane Smith',
        employeeId: 'DEMO-002',
        metadata: const {
          'status': 'in_progress',
          'category': 'pdf_password',
          'categoryLabel': 'PDF Password',
          'lastReplyBy': 'admin@racoma.com',
        },
      ),
      AdminNotification(
        id: 'demo_n3',
        type: 'clock_in',
        title: 'Clocked in',
        message: 'Mike Johnson clocked in at 8:55 AM.',
        timestamp: now.subtract(const Duration(minutes: 32)),
        read: false,
        priority: 'normal',
        employeeName: 'Mike Johnson',
        employeeId: 'DEMO-003',
        metadata: const {
          'zoneLabel': 'Inside office',
          'zoneEmoji': '🟢',
        },
      ),
      AdminNotification(
        id: 'demo_n4',
        type: 'geofence_alert',
        title: 'Geofence violation',
        message: 'Sarah Lee attempted to clock in outside the office geofence (1.2 km away).',
        timestamp: now.subtract(const Duration(hours: 1)),
        read: false,
        priority: 'high',
        employeeName: 'Sarah Lee',
        employeeId: 'DEMO-004',
        metadata: const {
          'zoneLabel': 'Outside office',
          'zoneEmoji': '🔴',
        },
      ),
      AdminNotification(
        id: 'demo_n5',
        type: 'leave_request',
        title: 'Leave request submitted',
        message: 'John Doe requested 3 days of vacation leave from Nov 15-17.',
        timestamp: now.subtract(const Duration(hours: 2)),
        read: true,
        priority: 'normal',
        employeeName: 'John Doe',
        employeeId: 'DEMO-001',
        metadata: const {},
      ),
      AdminNotification(
        id: 'demo_n6',
        type: 'clock_out',
        title: 'Clocked out',
        message: 'Jane Smith clocked out at 5:03 PM.',
        timestamp: now.subtract(const Duration(hours: 3)),
        read: true,
        priority: 'normal',
        employeeName: 'Jane Smith',
        employeeId: 'DEMO-002',
        metadata: const {
          'zoneLabel': 'Inside office',
          'zoneEmoji': '🟠',
        },
      ),
      AdminNotification(
        id: 'demo_n7',
        type: 'password_change_request',
        title: 'Password change request',
        message: 'Mike Johnson requested a PIN reset.',
        timestamp: now.subtract(const Duration(hours: 5)),
        read: true,
        priority: 'high',
        employeeName: 'Mike Johnson',
        employeeId: 'DEMO-003',
        metadata: const {'requestId': 'demo_pc_1'},
      ),
      AdminNotification(
        id: 'demo_n8',
        type: 'wfh_toggle',
        title: 'WFH access enabled',
        message: 'Admin enabled WFH for Sarah Lee.',
        timestamp: now.subtract(const Duration(hours: 8)),
        read: true,
        priority: 'normal',
        employeeName: 'Sarah Lee',
        employeeId: 'DEMO-004',
        metadata: const {},
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_onTabChanged);
    _loadSoundPref();
    if (!_isDemo) {
      _logAudit('page_opened', 'Admin opened notifications page');
    }
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  Future<void> _loadSoundPref() async {
    try {
      final svc = AdminNotificationAlertService.instance;
      if (!svc.initialized) await svc.init();
    } catch (e) {
      _secureLog('loadSoundPref error: $e');
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _logAudit(String action, String details) async {
    if (_isDemo) return;
    try {
      final empId = await SecurityHardeningService.instance.getCurrentEmployeeId();
      if (empId == null) return;
      await FirebaseFirestore.instance.collection('admin_audit_logs').add({
        'action': action,
        'details': details,
        'adminId': empId,
        'stage': 'notification_page',
        'platform': kIsWeb ? 'web' : 'mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _secureLog('Audit log failed: $e');
    }
  }

  bool _checkRateLimit() {
    final now = DateTime.now();
    _destructiveActionTimes.removeWhere((t) => now.difference(t) > _rateWindow);
    if (_destructiveActionTimes.length >= _maxDestructivePerWindow) {
      _secureLog('🚦 Rate limit hit');
      return false;
    }
    _destructiveActionTimes.add(now);
    return true;
  }

  String _sanitize(String input) {
    if (input.isEmpty) return input;
    var s = input;
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
    if (s.length > 500) s = '${s.substring(0, 500)}…';
    return s;
  }

  Future<bool> _safeDelete(AdminNotification n) async {
    if (_isDemo) {
      _demoBlock();
      return false;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return false;
    }

    try {
      await AdminNotificationService.instance.deleteNotification(n.id);
      _logAudit('notification_deleted', 'Deleted notif: ${n.id} (type=${n.type})');
      return true;
    } on AdminSessionExpiredException {
      _showSnack('🚨 Session expired. Please log in again.');
      return false;
    } on AdminPermissionDeniedException {
      _showSnack('🚫 Permission denied. You cannot delete notifications.');
      return false;
    } catch (e) {
      _secureLog('Delete failed: $e');
      _showSnack('⚠️ Failed to delete notification.');
      return false;
    }
  }

  Future<bool> _safeClearAll() async {
    if (_isDemo) {
      _demoBlock();
      return false;
    }
    if (!_checkRateLimit()) {
      _showSnack('⚠️ Too fast. Please wait a few seconds.');
      return false;
    }

    try {
      await AdminNotificationService.instance.clearAll();
      _logAudit('notifications_cleared', 'Cleared all notifications');
      return true;
    } on AdminSessionExpiredException {
      _showSnack('🚨 Session expired. Please log in again.');
      return false;
    } on AdminPermissionDeniedException {
      _showSnack('🚫 Permission denied. You cannot clear notifications.');
      return false;
    } catch (e) {
      _secureLog('Clear failed: $e');
      _showSnack('⚠️ Failed to clear notifications.');
      return false;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _isAlertNotification(AdminNotification n) {
    if (n.priority == 'high') return true;
    if (n.type == 'geofence_alert') return true;
    if (n.type == 'leave_request') return true;
    if (n.type == 'password_change') return true;
    if (n.type == 'password_change_request') return true;
    if (n.type == 'challenge_failed') return true;
    if (n.type == 'challenge_missed') return true;
    if (n.type == 'challenge_passed') return false;
    if (n.type == 'support_request') return true;
    if (n.type == 'presence_update' && n.metadata['changed'] == true) {
      return true;
    }
    return false;
  }

  List<AdminNotification> _applyFilterAndSort(List<AdminNotification> input) {
    var list = List<AdminNotification>.from(input);

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((n) {
        return n.title.toLowerCase().contains(q) ||
            n.message.toLowerCase().contains(q) ||
            (n.employeeName?.toLowerCase().contains(q) ?? false) ||
            n.type.toLowerCase().contains(q);
      }).toList();
    }

    switch (_sortMode) {
      case _SortMode.newest:
        list.sort((a, b) {
          final at = a.timestamp ?? DateTime(2000);
          final bt = b.timestamp ?? DateTime(2000);
          return bt.compareTo(at);
        });
        break;
      case _SortMode.oldest:
        list.sort((a, b) {
          final at = a.timestamp ?? DateTime(2000);
          final bt = b.timestamp ?? DateTime(2000);
          return at.compareTo(bt);
        });
        break;
      case _SortMode.priority:
        list.sort((a, b) {
          final ap = a.priority == 'high' ? 0 : 1;
          final bp = b.priority == 'high' ? 0 : 1;
          if (ap != bp) return ap.compareTo(bp);
          final at = a.timestamp ?? DateTime(2000);
          final bt = b.timestamp ?? DateTime(2000);
          return bt.compareTo(at);
        });
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF18181B) : tc.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(tc),
      body: _isDemo
          ? _buildDemoBody(tc)
          : StreamBuilder<List<AdminNotification>>(
        stream: AdminNotificationService.instance.streamAll(limit: 100),
        builder: (context, snap) {
          final all = snap.data;

          if (all != null) {
            final filtered = _applyFilterAndSort(all);
            final unreadList = filtered.where((n) => !n.read).toList();
            final alertsList = filtered.where(_isAlertNotification).toList();

            return TabBarView(
              controller: _tabs,
              children: [
                _buildList(context, tc, filtered, allNotifications: all),
                _buildList(context, tc, unreadList, allNotifications: all),
                _buildList(context, tc, alertsList, allNotifications: all),
              ],
            );
          }

          if (snap.hasError) {
            return _errorState(tc, '${snap.error}');
          }

          return _skeletonLoader(tc);
        },
      ),
    );
  }

  Widget _buildDemoBody(AdminColors tc) {
    final all = _getMockNotifications();
    final filtered = _applyFilterAndSort(all);
    final unreadList = filtered.where((n) => !n.read).toList();
    final alertsList = filtered.where(_isAlertNotification).toList();

    return Column(
      children: [
        _buildDemoBanner(tc),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildList(context, tc, filtered, allNotifications: all),
              _buildList(context, tc, unreadList, allNotifications: all),
              _buildList(context, tc, alertsList, allNotifications: all),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDemoBanner(AdminColors tc) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
            child: Text(
              'Demo Mode — showing sample notifications. Delete, clear, reply, and status updates are disabled.',
              style: TextStyle(
                fontSize: 11,
                color: tc.orange,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AdminColors tc) {
    return AppBar(
      backgroundColor: tc.topBarBg,
      foregroundColor: tc.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Notifications',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: tc.text,
        ),
      ),
      actions: [
        PopupMenuButton<_SortMode>(
          tooltip: 'Sort',
          icon: Icon(Icons.sort_rounded, color: tc.textMuted, size: 20),
          color: tc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (mode) {
            setState(() => _sortMode = mode);
            _logAudit('sort_changed', 'Sort mode: ${mode.name}');
          },
          itemBuilder: (_) => [
            _sortMenuItem(tc, _SortMode.newest, 'Newest first', Icons.south_rounded),
            _sortMenuItem(tc, _SortMode.oldest, 'Oldest first', Icons.north_rounded),
            _sortMenuItem(tc, _SortMode.priority, 'Priority first', Icons.priority_high_rounded),
          ],
        ),
        TextButton(
          onPressed: _isDemo
              ? _demoBlock
              : () async {
            try {
              await AdminNotificationService.instance.markAllAsRead();
              _logAudit('mark_all_read', 'Marked all as read');
              _showSnack('✅ All notifications marked as read.');
            } on AdminSessionExpiredException {
              _showSnack('🚨 Session expired. Please log in again.');
            } on AdminPermissionDeniedException {
              _showSnack('🚫 Permission denied. You cannot mark all as read.');
            } catch (e) {
              _showSnack('⚠️ Failed to mark all as read.');
              _secureLog('markAllAsRead error: $e');
            }
          },
          child: Text(
            'Mark all read',
            style: TextStyle(
              color: _isDemo ? tc.muted : tc.orange,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: tc.textMuted),
          color: tc.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) async {
            if (_isDemo) {
              _demoBlock();
              return;
            }
            if (v == 'clear') {
              final ok = await _confirmClear(context, tc);
              if (ok == true) {
                final success = await _safeClearAll();
                if (success) {
                  _showSnack('✅ All notifications cleared.');
                }
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_rounded, size: 16, color: _isDemo ? tc.muted : tc.red),
                  const SizedBox(width: 10),
                  Text('Clear all', style: TextStyle(color: _isDemo ? tc.muted : tc.text, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(108),
        child: Column(
          children: [
            Container(height: 1, color: tc.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: _buildSearchBar(tc),
            ),
            TabBar(
              controller: _tabs,
              labelColor: tc.orange,
              unselectedLabelColor: tc.textMuted,
              indicatorColor: tc.orange,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                const Tab(text: 'All'),
                Tab(
                  child: _tabWithBadgeFromCount(
                    'Unread',
                    (_isDemo ? _getMockNotifications() : const <AdminNotification>[])
                        .where((n) => !n.read)
                        .length,
                    tc,
                  ),
                ),
                Tab(
                  child: _tabWithBadgeFromCount(
                    'Alerts',
                    (_isDemo ? _getMockNotifications() : const <AdminNotification>[])
                        .where(_isAlertNotification)
                        .length,
                    tc,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabWithBadgeFromCount(String label, int count, AdminColors tc) {
    if (count <= 0) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: tc.orange, borderRadius: BorderRadius.circular(999)),
          constraints: const BoxConstraints(minWidth: 18),
          child: Text(
            count > 99 ? '99+' : '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<_SortMode> _sortMenuItem(AdminColors tc, _SortMode mode, String label, IconData icon) {
    final active = _sortMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 16, color: active ? tc.orange : tc.textMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: active ? tc.orange : tc.text,
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (active) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 14, color: tc.orange),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchBar(AdminColors tc) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: tc.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tc.border, width: 1),
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        maxLength: _maxSearchLength,
        style: TextStyle(color: tc.text, fontSize: 13, fontWeight: FontWeight.w500),
        cursorColor: tc.orange,
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          hintText: 'Search notifications...',
          hintStyle: TextStyle(color: tc.textMuted, fontSize: 13, fontWeight: FontWeight.w400),
          prefixIcon: Icon(Icons.search_rounded, color: tc.textMuted, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: tc.textMuted),
            onPressed: () {
              _searchCtrl.clear();
              _onSearchChanged('');
            },
            splashRadius: 18,
          )
              : null,
          border: InputBorder.none,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Widget _tabWithBadge(String label, int count, AdminColors tc) {
    return _tabWithBadgeFromCount(label, count, tc);
  }

  Widget _buildList(
      BuildContext context,
      AdminColors tc,
      List<AdminNotification> items, {
        required List<AdminNotification> allNotifications,
      }) {
    if (items.isEmpty) {
      final hasFilter = _query.isNotEmpty;
      return _emptyState(tc, hasFilter: hasFilter);
    }

    final groups = <String, List<AdminNotification>>{};

    for (final n in items) {
      final key = _getSectionTitle(n.type);
      groups.putIfAbsent(key, () => []).add(n);
    }

    final orderedKeys = [
      'SUPPORT REQUESTS',
      'CHALLENGE ALERTS',
      'PASSWORD REQUESTS',
      'CLOCK IN',
      'CLOCK OUT',
      'GEO ALERTS',
      'PRESENCE',
      'LEAVE REQUESTS',
      'WFH',
      'FACE ID',
      'CHALLENGE PASSED',
      'PASSWORD',
      'OTHER NOTIFS',
    ];

    return RefreshIndicator(
      color: tc.orange,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (final key in orderedKeys)
            if (groups.containsKey(key)) ...[
              _sectionHeader(tc, key, groups[key]!.length),
              _buildTable(context, tc, groups[key]!),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }

  String _getSectionTitle(String type) {
    switch (type) {
      case 'support_request': return 'SUPPORT REQUESTS';
      case 'challenge_failed':
      case 'challenge_missed': return 'CHALLENGE ALERTS';
      case 'challenge_passed': return 'CHALLENGE PASSED';
      case 'password_change_request':
      case 'password_change': return 'PASSWORD REQUESTS';
      case 'clock_in': return 'CLOCK IN';
      case 'clock_out': return 'CLOCK OUT';
      case 'geofence_alert': return 'GEO ALERTS';
      case 'presence_update': return 'PRESENCE';
      case 'leave_request': return 'LEAVE REQUESTS';
      case 'wfh_toggle': return 'WFH';
      case 'face_enrollment': return 'FACE ID';
      default: return 'OTHER NOTIFS';
    }
  }

  Widget _buildTable(BuildContext context, AdminColors tc, List<AdminNotification> items) {
    return Container(
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tc.orange.withValues(alpha: tc.isDark ? 0.12 : 0.08),
              border: Border(bottom: BorderSide(color: tc.border, width: 1)),
            ),
            child: Row(
              children: [
                SizedBox(width: 44, child: Text('TYPE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: tc.orange, letterSpacing: 1.0))),
                Expanded(child: Text('DETAILS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: tc.orange, letterSpacing: 1.0))),
                SizedBox(width: 70, child: Text('TIME', textAlign: TextAlign.right, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: tc.orange, letterSpacing: 1.0))),
              ],
            ),
          ),
          ...List.generate(items.length, (i) {
            final n = items[i];
            final isLast = i == items.length - 1;
            return _tableRow(context, tc, n, isLast: isLast);
          }),
        ],
      ),
    );
  }

  Widget _tableRow(BuildContext context, AdminColors tc, AdminNotification n, {bool isLast = false}) {
    final style = _styleFor(n.type, tc);
    final time = n.timestamp != null ? _fmtTime(n.timestamp!) : '';
    final zoneEmoji = n.zoneEmoji;

    return Dismissible(
      key: ValueKey('notif_${n.id}'),
      direction: _isDemo ? DismissDirection.none : DismissDirection.horizontal,
      background: Container(
        color: n.read ? tc.orange.withValues(alpha: 0.12) : tc.red.withValues(alpha: 0.15),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(n.read ? Icons.mark_email_unread_rounded : Icons.done_all_rounded, color: n.read ? tc.orange : tc.red, size: 22),
      ),
      secondaryBackground: Container(
        color: tc.red.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline_rounded, color: tc.red, size: 22),
      ),
      confirmDismiss: (direction) async {
        if (_isDemo) {
          _demoBlock();
          return false;
        }
        if (direction == DismissDirection.startToEnd) {
          try {
            if (!n.read) {
              await AdminNotificationService.instance.markAsRead(n.id);
              _logAudit('notification_marked_read', 'Notif: ${n.id}');
            } else {
              await AdminNotificationService.instance.markAsUnread(n.id);
              _logAudit('notification_marked_unread', 'Notif: ${n.id}');
            }
          } on AdminSessionExpiredException {
            _showSnack('🚨 Session expired. Please log in again.');
          } on AdminPermissionDeniedException {
            _showSnack('🚫 Permission denied.');
          } catch (e) {
            _showSnack('⚠️ Error: $e');
          }
          return false;
        }
        final confirmed = await _confirmSingleDelete(context, tc, n);
        if (confirmed == true) return await _safeDelete(n);
        return false;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!n.read && !_isDemo) {
              AdminNotificationService.instance.markAsRead(n.id).catchError((e) {
                _secureLog('markAsRead tap error: $e');
              });
            }
            _showDetail(context, tc, n);
          },
          onLongPress: () => _showQuickActions(context, tc, n),
          child: Container(
            decoration: BoxDecoration(
              color: n.read ? Colors.transparent : tc.orange.withValues(alpha: tc.isDark ? 0.06 : 0.04),
              border: isLast ? null : Border(bottom: BorderSide(color: tc.border.withValues(alpha: 0.6), width: 1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: style.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: style.color.withValues(alpha: 0.35), width: 1),
                        ),
                        child: Center(
                          child: zoneEmoji.isNotEmpty
                              ? Text(zoneEmoji, style: const TextStyle(fontSize: 16))
                              : Icon(style.icon, color: style.color, size: 17),
                        ),
                      ),
                      if (!n.read) ...[
                        const SizedBox(height: 4),
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: tc.red, shape: BoxShape.circle)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: style.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(_typeLabel(n.type), style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: style.color, letterSpacing: 0.4)),
                          ),
                          if (n.priority == 'high') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: tc.pillErrBg, borderRadius: BorderRadius.circular(4)),
                              child: Text('HIGH', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: tc.pillErrTx, letterSpacing: 0.4)),
                            ),
                          ],
                          if (n.type == 'support_request') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: _supportStatusBg(tc, n), borderRadius: BorderRadius.circular(4)),
                              child: Text(_supportStatusLabel(n), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: _supportStatusFg(tc, n), letterSpacing: 0.4)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(_sanitize(n.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800, fontSize: 13, color: tc.text, height: 1.3)),
                      const SizedBox(height: 3),
                      Text(_sanitize(n.message), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: tc.textMuted, height: 1.4)),
                      if (n.employeeName != null || n.zoneLabel.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (n.employeeName != null) ...[
                              Icon(Icons.person_outline_rounded, size: 10, color: tc.muted),
                              const SizedBox(width: 3),
                              Flexible(child: Text(_sanitize(n.employeeName!), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: tc.muted, fontWeight: FontWeight.w600))),
                            ],
                            if (n.employeeName != null && n.zoneLabel.isNotEmpty) const SizedBox(width: 8),
                            if (n.zoneLabel.isNotEmpty) ...[
                              Icon(Icons.place_outlined, size: 10, color: tc.muted),
                              const SizedBox(width: 3),
                              Flexible(child: Text(_sanitize(n.zoneLabel), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: tc.muted, fontStyle: FontStyle.italic))),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(time, textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: tc.muted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Icon(Icons.chevron_right_rounded, size: 16, color: tc.muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(AdminColors tc, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(color: tc.orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: tc.textMuted, letterSpacing: 1.1)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: tc.orangeLight, borderRadius: BorderRadius.circular(999)),
            child: Text('$count', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: tc.orange)),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'support_request': return 'SUPPORT';
      case 'challenge_failed': return 'CHALLENGE FAIL';
      case 'challenge_missed': return 'CHALLENGE MISS';
      case 'challenge_passed': return 'CHALLENGE OK';
      case 'password_change_request':
      case 'password_change': return 'PASSWORD REQ';
      case 'clock_in': return 'CLOCK IN';
      case 'clock_out': return 'CLOCK OUT';
      case 'leave_request': return 'LEAVE';
      case 'wfh_toggle': return 'WFH';
      case 'face_enrollment': return 'FACE ID';
      case 'geofence_alert': return 'GEOFENCE';
      case 'presence_update': return 'PRESENCE';
      default: return type.toUpperCase().replaceAll('_', ' ');
    }
  }

  String _supportStatusLabel(AdminNotification n) {
    final s = (n.metadata['status'] as String?)?.toLowerCase() ?? 'pending';
    switch (s) {
      case 'resolved': return 'RESOLVED';
      case 'in_progress': return 'IN PROGRESS';
      default: return 'PENDING';
    }
  }

  Color _supportStatusBg(AdminColors tc, AdminNotification n) {
    final s = (n.metadata['status'] as String?)?.toLowerCase() ?? 'pending';
    switch (s) {
      case 'resolved': return tc.pillGreenBg;
      case 'in_progress': return tc.pillWarnBg;
      default: return tc.orangeLight;
    }
  }

  Color _supportStatusFg(AdminColors tc, AdminNotification n) {
    final s = (n.metadata['status'] as String?)?.toLowerCase() ?? 'pending';
    switch (s) {
      case 'resolved': return tc.pillGreenTx;
      case 'in_progress': return tc.pillWarnTx;
      default: return tc.orange;
    }
  }

  void _showDetail(BuildContext context, AdminColors tc, AdminNotification n) {
    final isSupport = n.type == 'support_request';

    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: tc.border, borderRadius: BorderRadius.circular(999)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(_sanitize(n.title), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: tc.text))),
                if (isSupport) _supportStatusBadge(tc, n),
              ],
            ),
            const SizedBox(height: 8),
            Text(_sanitize(n.message), style: TextStyle(fontSize: 13.5, color: tc.textMuted, height: 1.5)),
            const SizedBox(height: 16),
            if (n.employeeName != null) _kv(tc, 'Employee', _sanitize(n.employeeName!)),
            if (n.employeeId != null && n.employeeId!.isNotEmpty) _kv(tc, 'Employee ID', _sanitize(n.employeeId!)),
            _kv(tc, 'Type', n.type),
            if (n.employeeName != null) _kv(tc, 'Employee', _sanitize(n.employeeName!)),
            if (n.metadata['categoryLabel'] != null) _kv(tc, 'Category', _sanitize(n.metadata['categoryLabel'].toString())),
            if (isSupport && n.metadata['lastReplyBy'] != null) _kv(tc, 'Last reply by', _sanitize(n.metadata['lastReplyBy'].toString())),
            if (n.zoneLabel.isNotEmpty) _kv(tc, 'Zone', _sanitize(n.zoneLabel)),
            if (n.priority != 'normal') _kv(tc, 'Priority', n.priority),
            _kv(tc, 'Time', n.timestamp != null ? _fullTime(n.timestamp!) : '—'),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    if (_isDemo) {
                      _demoBlock();
                      return;
                    }
                    final ok = await _confirmSingleDelete(context, tc, n);
                    if (ok == true) {
                      final deleted = await _safeDelete(n);
                      if (deleted && mounted && context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  icon: Icon(Icons.delete_outline_rounded, size: 16, color: _isDemo ? tc.muted : tc.red),
                  label: Text('Delete', style: TextStyle(color: _isDemo ? tc.muted : tc.red, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: tc.border),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: tc.border),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  child: Text('Close', style: TextStyle(color: tc.textMuted, fontWeight: FontWeight.w700)),
                ),

                if (!isSupport) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _navigateToTarget(context, n),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Go To', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(backgroundColor: tc.orange, padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ] else if (isSupport) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showSupportActions(context, tc, n);
                      },
                      icon: const Icon(Icons.support_agent_rounded, size: 16),
                      label: const Text('Manage Ticket', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(backgroundColor: tc.orange, padding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 🧭 NAVIGATION
  // ═══════════════════════════════════════════════════════════
  void _navigateToTarget(BuildContext context, AdminNotification n) {
    final tc = AdminTheme.getColors(context);
    Navigator.pop(context); // Isara muna bottom sheet

    if (_isDemo) {
      _demoBlock();
      return;
    }

    if (!n.read) {
      AdminNotificationService.instance.markAsRead(n.id).catchError((e) {
        _secureLog('markAsRead on navigate error: $e');
      });
    }

    final empId = (n.employeeId ?? n.metadata['employeeDocId']?.toString() ?? '').trim();

    _logAudit('notification_navigated', 'type=${n.type} notifId=${n.id}');

    switch (n.type) {
      case 'challenge_failed':
      case 'challenge_missed':
      case 'challenge_passed':
        if (empId.isEmpty) {
          _showSnack('⚠️ No employee ID on this notification.');
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminChallengeDetailsScreen(
            employeeId: empId,
            employeeName: n.employeeName ?? 'Employee',
            challengeId: n.metadata['challengeId']?.toString(),
            notificationType: n.type,
          ),
        ));
        break;

      case 'clock_in':
      case 'clock_out':
      // ✅ SINIGURO NA KUMPLETO ANG PARAMETERS PARA SA ADMINATTENDANCEPAGE
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminAttendancePage(
            title: 'Attendance Records',
            searchQuery: '',
            accent: tc.orange,
            locations: const [],
            logs: const [],
            onRefreshNeeded: () {},
          ),
        ));
        break;

      case 'geofence_alert':
      case 'presence_update':
      // ✅ SINIGURO NA KUMPLETO ANG PARAMETERS PARA SA ADMINPRESENCEPAGE
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminPresencePage(
            employees: const [],
            onRefreshNeeded: () {},
            searchQuery: '',
          ),
        ));
        break;

      case 'password_change_request':
      case 'password_change':
      // ✅ Fallback sa AdminEmployeesPage
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AdminEmployeesPage(),
        ));
        break;

      case 'leave_request':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AdminCreateLeaveRequestPage(),
        ));
        break;

      case 'wfh_toggle':
      case 'face_enrollment':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AdminEditEmployeePage(),
        ));
        break;

      default:
        _showNoRouteDialog(context, tc, n);
        break;
    }
  }

  void _showNoRouteDialog(BuildContext context, AdminColors tc, AdminNotification n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.info_outline_rounded, color: tc.orange, size: 20), const SizedBox(width: 8), Expanded(child: Text('No destination', style: TextStyle(color: tc.text, fontWeight: FontWeight.w800, fontSize: 15)))]),
        content: Text('Notification type "${n.type}" has no destination screen configured.', style: TextStyle(color: tc.textMuted, fontSize: 12.5, height: 1.5)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: tc.orange, fontWeight: FontWeight.w700)))],
      ),
    );
  }

  Widget _kv(AdminColors tc, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(k, style: TextStyle(fontSize: 12, color: tc.muted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: TextStyle(fontSize: 12.5, color: tc.text, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _showSupportActions(BuildContext context, AdminColors tc, AdminNotification n) {
    if (_isDemo) {
      _demoBlock();
      return;
    }

    final status = (n.metadata['status'] as String?)?.toLowerCase() ?? 'pending';
    final category = (n.metadata['category'] as String?)?.toLowerCase() ?? 'other';
    final categoryLabel = (n.metadata['categoryLabel'] ?? 'Support').toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: tc.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(_iconForCategory(category), color: tc.orange, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_sanitize(n.employeeName ?? 'Employee'), style: TextStyle(color: tc.text, fontSize: 14, fontWeight: FontWeight.w800)), Text('$categoryLabel · ${_statusLabel(status)}', style: TextStyle(color: tc.muted, fontSize: 11.5))])),
                    _supportStatusBadge(tc, n),
                  ],
                ),
              ),
              Divider(height: 1, color: tc.border),
              ListTile(
                leading: Icon(Icons.reply_rounded, color: tc.orange),
                title: Text('Reply to employee', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
                subtitle: Text('Send a message back', style: TextStyle(color: tc.muted, fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(context);
                  _showReplyDialog(context, tc, n);
                },
              ),
              ..._buildCategoryActions(context, tc, n, category, status),
              if (status != 'in_progress' && status != 'resolved')
                ListTile(
                  leading: Icon(Icons.pending_actions_rounded, color: tc.orange),
                  title: Text('Mark as In Progress', style: TextStyle(color: tc.text)),
                  subtitle: Text('Let other admins know someone is handling it', style: TextStyle(color: tc.muted, fontSize: 11.5)),
                  onTap: () async {
                    Navigator.pop(context);
                    final ok = await SupportReplyService.instance.updateStatus(
                      requestId: n.id, status: 'in_progress', employeeId: n.employeeId, employeeDocId: n.metadata['employeeDocId']?.toString(), employeeName: n.employeeName, categoryLabel: n.metadata['categoryLabel']?.toString(),
                    );
                    if (ok) {
                      final empId = n.employeeId ?? n.metadata['employeeDocId']?.toString() ?? '';
                      if (empId.isNotEmpty) {
                        OneSignalSender.instance.sendToEmployee(employeeId: empId, title: '⏳ Support Ticket Update', message: 'Your support ticket is now being reviewed by Admin.', type: 'support_request').catchError((e) => debugPrint('Push failed: $e'));
                      }
                    }
                    _showSnack(ok ? '✅ Marked as In Progress.' : '⚠️ Failed to update status.');
                  },
                ),
              if (status != 'resolved')
                ListTile(
                  leading: Icon(Icons.check_circle_rounded, color: tc.orange),
                  title: Text('Mark as Resolved', style: TextStyle(color: tc.text)),
                  subtitle: Text('Close the ticket', style: TextStyle(color: tc.muted, fontSize: 11.5)),
                  onTap: () async {
                    Navigator.pop(context);
                    final ok = await SupportReplyService.instance.updateStatus(
                      requestId: n.id, status: 'resolved', employeeId: n.employeeId, employeeDocId: n.metadata['employeeDocId']?.toString(), employeeName: n.employeeName, categoryLabel: n.metadata['categoryLabel']?.toString(),
                    );
                    if (ok) {
                      final empId = n.employeeId ?? n.metadata['employeeDocId']?.toString() ?? '';
                      if (empId.isNotEmpty) {
                        OneSignalSender.instance.sendToEmployee(employeeId: empId, title: '✅ Support Ticket Resolved', message: 'Your support ticket has been resolved.', type: 'support_request').catchError((e) => debugPrint('Push failed: $e'));
                      }
                    }
                    _showSnack(ok ? '✅ Marked as Resolved — employee notified.' : '⚠️ Failed to update status.');
                  },
                ),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: tc.textMuted),
                title: Text('Copy employee ID', style: TextStyle(color: tc.text)),
                subtitle: Text(_sanitize(n.employeeId ?? '—'), style: TextStyle(color: tc.muted, fontSize: 11.5)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: n.employeeId ?? ''));
                  Navigator.pop(context);
                  _showSnack('📋 Employee ID copied.');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCategoryActions(BuildContext context, AdminColors tc, AdminNotification n, String category, String status) {
    final List<Widget> actions = [];
    switch (category) {
      case 'pdf_download':
        actions.add(ListTile(
          leading: Icon(Icons.help_outline_rounded, color: tc.orange),
          title: Text('Send fix steps', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
          subtitle: Text('Auto-fill common fixes', style: TextStyle(color: tc.muted, fontSize: 11.5)),
          onTap: () {
            Navigator.pop(context);
            _showReplyDialog(context, tc, n, prefillBody: AdminSupportActionsService.instance.cannedReplyFor(category), dialogTitle: 'Send fix steps');
          },
        ));
        actions.add(ListTile(
          leading: Icon(Icons.refresh_rounded, color: tc.orange),
          title: Text('Force resync payslip', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
          subtitle: Text('Trigger a data refresh on the employee app', style: TextStyle(color: tc.muted, fontSize: 11.5)),
          onTap: () async {
            Navigator.pop(context);
            final ok = await AdminSupportActionsService.instance.flagForceRefresh(requestId: n.id, flag: 'force_refresh_payslip');
            if (ok) {
              final empId = n.employeeId ?? n.metadata['employeeDocId']?.toString() ?? '';
              if (empId.isNotEmpty) {
                OneSignalSender.instance.sendToEmployee(employeeId: empId, title: '🔄 Payslip Resync', message: 'Admin triggered a resync for your payslip. Please check the app.', type: 'support_request').catchError((e) => debugPrint('Push failed: $e'));
              }
            }
            _showSnack(ok ? '🔄 Employee app will refresh on next check.' : '⚠️ Failed to flag.');
            if (ok) await AdminSupportActionsService.instance.logAdminAction(requestId: n.id, action: 'force_refresh_payslip');
          },
        ));
        break;
      case 'pdf_password':
        actions.add(ListTile(
          leading: Icon(Icons.visibility_rounded, color: tc.orange),
          title: Text('Show current password', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
          subtitle: Text('For the existing PDF on the phone. Use this if the employee just forgot the password.', style: TextStyle(color: tc.muted, fontSize: 11.5)),
          onTap: () async {
            Navigator.pop(context);
            final empId = n.employeeId ?? '';
            if (empId.isEmpty) { _showSnack('⚠️ No employee ID — cannot fetch.'); return; }
            final currentPwd = await AdminSupportActionsService.instance.getCurrentPassword(empId);
            if (!mounted) return;
            if (currentPwd == null) { _showSnack('⚠️ No password yet. Employee must download a payslip first.'); return; }
            await _showReplyDialog(context, tc, n, prefillBody: 'Hi! Here is your CURRENT PDF password: **$currentPwd**\n\nUse this to open the payslip PDF that is ALREADY on your phone.', dialogTitle: 'Send current password');
          },
        ));
        actions.add(ListTile(
          leading: Icon(Icons.vpn_key_rounded, color: tc.orange),
          title: Text('Reset password (re-download)', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
          subtitle: Text('Creates a NEW password. The employee MUST re-download the PDF or it will NOT open.', style: TextStyle(color: tc.muted, fontSize: 11.5)),
          onTap: () async {
            Navigator.pop(context);
            if (!mounted) return;
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: tc.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(children: [Icon(Icons.warning_amber_rounded, color: tc.orange, size: 20), const SizedBox(width: 8), Expanded(child: Text('Reset password?', style: TextStyle(color: tc.text, fontWeight: FontWeight.w800, fontSize: 15)))]),
                content: Text('The employee must RE-DOWNLOAD the payslip from the app.\n\nAny existing PDF on their phone will NO LONGER open with the new password.', style: TextStyle(color: tc.muted, fontSize: 12.5, height: 1.5)),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: tc.muted, fontWeight: FontWeight.w700))), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: tc.orange), child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)))],
              ),
            );
            if (confirmed != true) return;
            final empId = n.employeeId ?? '';
            if (empId.isEmpty) { _showSnack('⚠️ No employee ID — cannot generate.'); return; }
            final newPassword = await AdminSupportActionsService.instance.generateNewPassword(empId);
            if (newPassword == null) { _showSnack('⚠️ Failed to generate password.'); return; }
            if (!mounted) return;
            OneSignalSender.instance.sendToEmployee(employeeId: empId, title: '🔐 New PDF Password', message: 'Admin generated a new PDF password for you. Please check the app.', type: 'support_request').catchError((e) => debugPrint('Push failed: $e'));
            await _showReplyDialog(context, tc, n, prefillBody: 'Hi! New password for your payslip:\n\n🔑 **$newPassword**\n\n⚠️ STEP 1: Open the app → Reports → Download PDF again.\n⚠️ STEP 2: Open the newly downloaded PDF.\n⚠️ STEP 3: Enter the new password above.\n\nThe OLD PDF on your phone will NOT work with this password — you must re-download.', dialogTitle: 'Send new password');
            await AdminSupportActionsService.instance.logAdminAction(requestId: n.id, action: 'generate_new_password', meta: {'employeeId': empId});
          },
        ));
        break;
      case 'salary_question':
        actions.add(ListTile(leading: Icon(Icons.receipt_long_rounded, color: tc.orange), title: Text('Open employee payroll', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)), subtitle: Text('Review payslip breakdown', style: TextStyle(color: tc.muted, fontSize: 11.5)), onTap: () { Navigator.pop(context); _showSnack('💰 Open Payroll Management and search for ${n.employeeName ?? "employee"}.'); }));
        actions.add(ListTile(
          leading: Icon(Icons.reply_rounded, color: tc.orange),
          title: Text('Send salary breakdown', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)),
          subtitle: Text('Auto-fill from employee payroll data', style: TextStyle(color: tc.muted, fontSize: 11.5)),
          onTap: () async {
            Navigator.pop(context);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loading salary data...'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
            final empId = n.employeeId ?? '';
            if (empId.isEmpty) { _showSnack('⚠️ No employee ID on this notification.'); return; }
            final now = DateTime.now();
            final breakdown = await AdminSupportActionsService.instance.buildSalaryBreakdownText(employeeId: empId, periodStart: DateTime(now.year, now.month, 1), periodEnd: DateTime(now.year, now.month + 1, 0, 23, 59, 59));
            if (!mounted) return;
            if (breakdown == null || breakdown.trim().isEmpty) { _showSnack('⚠️ Could not load salary data. Try again.'); return; }
            await _showReplyDialog(context, tc, n, prefillBody: breakdown, dialogTitle: 'Reply with breakdown');
            await AdminSupportActionsService.instance.logAdminAction(requestId: n.id, action: 'send_salary_breakdown', meta: {'employeeId': empId});
          },
        ));
        break;
      case 'app_issue':
        actions.add(ListTile(leading: Icon(Icons.restart_alt_rounded, color: tc.orange), title: Text('Send restart steps', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)), subtitle: Text('Auto-fill troubleshooting steps', style: TextStyle(color: tc.muted, fontSize: 11.5)), onTap: () { Navigator.pop(context); _showReplyDialog(context, tc, n, prefillBody: AdminSupportActionsService.instance.cannedReplyFor(category), dialogTitle: 'Send restart steps'); }));
        break;
      default:
        actions.add(ListTile(leading: Icon(Icons.quickreply_rounded, color: tc.orange), title: Text('Send acknowledgment', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)), subtitle: Text('Auto-fill reply', style: TextStyle(color: tc.muted, fontSize: 11.5)), onTap: () { Navigator.pop(context); _showReplyDialog(context, tc, n, prefillBody: AdminSupportActionsService.instance.cannedReplyFor(category), dialogTitle: 'Send acknowledgment'); }));
        break;
    }
    return actions;
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'pdf_download': return Icons.download_rounded;
      case 'pdf_password': return Icons.vpn_key_rounded;
      case 'salary_question': return Icons.receipt_long_rounded;
      case 'app_issue': return Icons.phonelink_erase_rounded;
      default: return Icons.support_agent_rounded;
    }
  }

  Future<void> _showReplyDialog(BuildContext context, AdminColors tc, AdminNotification n, {String? prefillBody, String dialogTitle = 'Reply to employee'}) async {
    if (_isDemo) { _demoBlock(); return; }
    final ctrl = TextEditingController(text: prefillBody ?? '');
    final categoryLabel = (n.metadata['categoryLabel'] ?? 'Support').toString();
    bool sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              backgroundColor: tc.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: Row(children: [Icon(Icons.reply_rounded, color: tc.orange, size: 20), const SizedBox(width: 10), Expanded(child: Text(dialogTitle, style: TextStyle(color: tc.text, fontSize: 16, fontWeight: FontWeight.w800)))]),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: tc.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF4F4F5), borderRadius: BorderRadius.circular(8), border: Border.all(color: tc.border)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('To: ${_sanitize(n.employeeName ?? "Employee")}', style: TextStyle(color: tc.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          const SizedBox(height: 2),
                          Text('Issue: $categoryLabel', style: TextStyle(color: tc.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                          const SizedBox(height: 4),
                          Text(_sanitize(n.message), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: tc.text, fontSize: 12.5, height: 1.4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: ctrl,
                      maxLines: 10,
                      maxLength: 2000,
                      autofocus: true,
                      enabled: !sending,
                      style: TextStyle(color: tc.text, fontSize: 13, height: 1.4),
                      cursorColor: tc.orange,
                      decoration: InputDecoration(
                        hintText: 'Type your reply...',
                        hintStyle: TextStyle(color: tc.muted, fontSize: 13),
                        filled: true,
                        fillColor: tc.isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF4F4F5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: tc.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: tc.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: tc.orange, width: 1.5)),
                        counterStyle: TextStyle(color: tc.muted, fontSize: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('This will be sent to the employee and the request will be marked as In Progress.', style: TextStyle(color: tc.muted, fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: sending ? null : () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: tc.muted, fontWeight: FontWeight.w700))),
                FilledButton.icon(
                  onPressed: sending ? null : () async {
                    final msg = ctrl.text.trim();
                    if (msg.isEmpty) { _showSnack('⚠️ Please type a reply.'); return; }
                    setDlg(() => sending = true);
                    final ok = await SupportReplyService.instance.sendReply(requestId: n.id, message: msg, newStatus: 'in_progress', employeeId: n.employeeId, employeeDocId: n.metadata['employeeDocId']?.toString(), employeeName: n.employeeName, categoryLabel: n.metadata['categoryLabel']?.toString());
                    if (ok) {
                      final empId = n.employeeId ?? n.metadata['employeeDocId']?.toString() ?? '';
                      if (empId.isNotEmpty) {
                        OneSignalSender.instance.sendToEmployee(employeeId: empId, title: '✉️ Reply from Admin', message: msg, type: 'support_reply').catchError((e) => debugPrint('Push failed: $e'));
                      }
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _showSnack(ok ? '✅ Reply sent to employee.' : '⚠️ Failed to send reply.');
                    if (ok) _logAudit('support_replied', 'Replied to support request: ${n.id}');
                  },
                  icon: sending ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  label: Text(sending ? 'Sending...' : 'Send', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  style: FilledButton.styleFrom(backgroundColor: tc.orange),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _supportStatusBadge(AdminColors tc, AdminNotification n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _supportStatusBg(tc, n), borderRadius: BorderRadius.circular(999)),
      child: Text(_supportStatusLabel(n), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: _supportStatusFg(tc, n), letterSpacing: 0.5)),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'resolved': return 'Resolved';
      case 'in_progress': return 'In Progress';
      default: return 'Pending';
    }
  }

  void _showQuickActions(BuildContext context, AdminColors tc, AdminNotification n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isDemo)
              ListTile(leading: Icon(Icons.science_rounded, color: tc.orange), title: Text('Demo Mode Active', style: TextStyle(color: tc.orange, fontWeight: FontWeight.w700)), subtitle: Text('Actions are disabled', style: TextStyle(color: tc.muted, fontSize: 11.5)), onTap: () => Navigator.pop(context))
            else ...[
              if (!n.read)
                ListTile(
                  leading: Icon(Icons.done_all_rounded, color: tc.orange), title: Text('Mark as read', style: TextStyle(color: tc.text)),
                  onTap: () async {
                    try { await AdminNotificationService.instance.markAsRead(n.id); _logAudit('notification_marked_read', 'Notif: ${n.id} (quick action)'); } on AdminSessionExpiredException { _showSnack('🚨 Session expired. Please log in again.'); } on AdminPermissionDeniedException { _showSnack('🚫 Permission denied.'); } catch (e) { _showSnack('⚠️ Error: $e'); }
                    if (mounted) Navigator.pop(context);
                  },
                )
              else
                ListTile(
                  leading: Icon(Icons.mark_email_unread_rounded, color: tc.orange), title: Text('Mark as unread', style: TextStyle(color: tc.text)),
                  onTap: () async {
                    try { await AdminNotificationService.instance.markAsUnread(n.id); _logAudit('notification_marked_unread', 'Notif: ${n.id} (quick action)'); } on AdminSessionExpiredException { _showSnack('🚨 Session expired. Please log in again.'); } on AdminPermissionDeniedException { _showSnack('🚫 Permission denied.'); } catch (e) { _showSnack('⚠️ Error: $e'); }
                    if (mounted) Navigator.pop(context);
                  },
                ),
            ],
            ListTile(leading: Icon(Icons.arrow_forward_rounded, color: tc.orange), title: Text('Go To / Open', style: TextStyle(color: tc.text, fontWeight: FontWeight.w700)), onTap: () => _navigateToTarget(context, n)),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: tc.red), title: Text('Delete', style: TextStyle(color: tc.text)),
              onTap: () async {
                Navigator.pop(context);
                if (_isDemo) { _demoBlock(); return; }
                final ok = await _confirmSingleDelete(context, tc, n);
                if (ok == true) { final deleted = await _safeDelete(n); if (deleted) _showSnack('🗑️ Notification deleted.'); }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmClear(BuildContext context, AdminColors tc) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all notifications?', style: TextStyle(color: tc.text, fontWeight: FontWeight.w800)),
        content: Text('This cannot be undone. Are you sure?', style: TextStyle(color: tc.textMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: tc.textMuted, fontWeight: FontWeight.w700))),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: tc.red), child: const Text('Clear all', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<bool?> _confirmSingleDelete(BuildContext context, AdminColors tc, AdminNotification n) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.delete_outline_rounded, color: tc.red, size: 20), const SizedBox(width: 8), Text('Delete notification?', style: TextStyle(color: tc.text, fontWeight: FontWeight.w800))]),
        content: Text('This action cannot be undone.', style: TextStyle(color: tc.textMuted, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: tc.textMuted, fontWeight: FontWeight.w700))),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: tc.red), child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _skeletonLoader(AdminColors tc) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (int i = 0; i < 6; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            height: 76,
            decoration: BoxDecoration(color: tc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: tc.border, width: 1)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _shimmer(tc, width: 34, height: 34, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _shimmer(tc, width: 60, height: 10, radius: 3),
                        const SizedBox(height: 8),
                        _shimmer(tc, width: 200, height: 12, radius: 3),
                        const SizedBox(height: 6),
                        _shimmer(tc, width: 150, height: 10, radius: 3),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _shimmer(AdminColors tc, {required double width, required double height, required double radius}) {
    return Container(width: width, height: height, decoration: BoxDecoration(color: tc.border.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(radius)));
  }

  Widget _emptyState(AdminColors tc, {bool hasFilter = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 72, height: 72, decoration: BoxDecoration(color: tc.orangeLight, shape: BoxShape.circle), child: Icon(hasFilter ? Icons.search_off_rounded : Icons.notifications_off_outlined, size: 32, color: tc.orange)),
            const SizedBox(height: 16),
            Text(hasFilter ? 'No matches found' : 'No notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tc.text)),
            const SizedBox(height: 6),
            Text(hasFilter ? 'Try a different search term or clear the filter.' : 'Clock in/out, WFH toggles, and leave requests\nfrom employees will appear here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: tc.textMuted, height: 1.5)),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () { _searchCtrl.clear(); _onSearchChanged(''); },
                icon: Icon(Icons.clear_rounded, size: 14, color: tc.orange),
                label: Text('Clear filter', style: TextStyle(color: tc.orange, fontWeight: FontWeight.w700, fontSize: 12)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: tc.orange.withValues(alpha: 0.4)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _errorState(AdminColors tc, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: tc.red),
            const SizedBox(height: 16),
            Text('Error loading notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tc.text)),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: tc.textMuted)),
          ],
        ),
      ),
    );
  }

  _NStyle _styleFor(String type, AdminColors tc) {
    switch (type) {
      case 'support_request': return _NStyle(Icons.support_agent_rounded, tc.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB));
      case 'challenge_failed': return _NStyle(Icons.gpp_bad_rounded, tc.isDark ? const Color(0xFFFFB4AB) : const Color(0xFFEF4444));
      case 'challenge_missed': return _NStyle(Icons.timer_off_rounded, tc.isDark ? const Color(0xFFFFB4AB) : const Color(0xFFEF4444));
      case 'challenge_passed': return _NStyle(Icons.verified_user_rounded, tc.isDark ? const Color(0xFF4CE346) : const Color(0xFF16A34A));
      case 'password_change_request':
      case 'password_change': return _NStyle(Icons.lock_reset_rounded, tc.isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
      case 'clock_in': return _NStyle(Icons.login_rounded, tc.isDark ? const Color(0xFF4CE346) : const Color(0xFF16A34A));
      case 'clock_out': return _NStyle(Icons.logout_rounded, tc.isDark ? const Color(0xFFFFB77D) : const Color(0xFFF59E0B));
      case 'leave_request': return _NStyle(Icons.event_busy_rounded, tc.orange);
      case 'wfh_toggle': return _NStyle(Icons.home_work_rounded, tc.isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6));
      case 'face_enrollment': return _NStyle(Icons.face_rounded, tc.isDark ? const Color(0xFFC4B5FD) : const Color(0xFF8B5CF6));
      case 'geofence_alert': return _NStyle(Icons.warning_amber_rounded, tc.isDark ? const Color(0xFFFFB4AB) : const Color(0xFFEF4444));
      case 'presence_update': return _NStyle(Icons.location_searching_rounded, tc.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB));
      default: return _NStyle(Icons.notifications_rounded, tc.muted);
    }
  }

  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('MMM d').format(d);
  }

  String _fullTime(DateTime d) => DateFormat('MMM d, yyyy · hh:mm a').format(d);

  String _bucketLabel(DateTime? d) {
    if (d == null) return 'Older';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = today.difference(date).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Older';
  }
}

class _NStyle {
  final IconData icon;
  final Color color;
  const _NStyle(this.icon, this.color);
}