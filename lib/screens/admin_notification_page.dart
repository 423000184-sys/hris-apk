// lib/screens/admin_notification_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import '../services/admin_notification_alert_service.dart';  // 🔔 para sa tunay na service
import 'admin_theme.dart';

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _soundOn = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadSoundPref();
  }

  Future<void> _loadSoundPref() async {
    try {
      final svc = AdminNotificationAlertService.instance;
      // Ensure initialized (safe — may guard sa loob)
      if (!svc.initialized) {
        await svc.init();
      }
      if (mounted) setState(() => _soundOn = svc.enabled);
    } catch (e) {
      debugPrint('⚠️ [_loadSoundPref] error: $e');
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);

    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
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
          // 🔔 Sound toggle
          IconButton(
            tooltip: _soundOn ? 'Mute sounds' : 'Unmute sounds',
            onPressed: () async {
              final newValue = !_soundOn;
              setState(() => _soundOn = newValue);
              try {
                await AdminNotificationAlertService.instance
                    .setEnabled(newValue);
              } catch (e) {
                debugPrint('⚠️ [sound toggle] $e');
              }
            },
            icon: Icon(
              _soundOn
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              color: tc.textMuted,
              size: 20,
            ),
          ),

          // ✅ Mark all read
          TextButton(
            onPressed: () =>
                AdminNotificationService.instance.markAllAsRead(),
            child: Text(
              'Mark all read',
              style: TextStyle(
                color: tc.orange,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),

          // ⋮ More menu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: tc.textMuted),
            color: tc.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (v) async {
              if (v == 'clear') {
                final ok = await _confirmClear(context, tc);
                if (ok == true) {
                  await AdminNotificationService.instance.clearAll();
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_sweep_rounded,
                      size: 16,
                      color: tc.red,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Clear all',
                      style: TextStyle(color: tc.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Column(
            children: [
              Container(height: 1, color: tc.border),
              TabBar(
                controller: _tabs,
                labelColor: tc.orange,
                unselectedLabelColor: tc.textMuted,
                indicatorColor: tc.orange,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'Unread'),
                  Tab(text: 'Alerts'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: StreamBuilder<List<AdminNotification>>(
        stream: AdminNotificationService.instance.streamAll(limit: 100),
        builder: (context, snap) {
          // ✅ PRIORITIZE hasData — hindi na mag-flicker sa reconnect
          final all = snap.data;

          if (all != null) {
            return TabBarView(
              controller: _tabs,
              children: [
                // Tab 1: All
                _buildList(context, tc, all),

                // Tab 2: Unread
                _buildList(
                  context,
                  tc,
                  all.where((n) => !n.read).toList(),
                ),

                // Tab 3: Alerts (high priority + geofence + leave + presence change + password change)
                _buildList(
                  context,
                  tc,
                  all.where((n) {
                    if (n.priority == 'high') return true;
                    if (n.type == 'geofence_alert') return true;
                    if (n.type == 'leave_request') return true;
                    if (n.type == 'password_change') return true;   // ✅ BAGO
                    // ✅ presence_update: urgent lang kapag changed
                    if (n.type == 'presence_update' &&
                        n.metadata['changed'] == true) {
                      return true;
                    }
                    return false;
                  }).toList(),
                ),
              ],
            );
          }

          if (snap.hasError) {
            return _errorState(tc, '${snap.error}');
          }

          return Center(
            child: CircularProgressIndicator(
              color: tc.orange,
              strokeWidth: 2.5,
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // LIST with grouping
  // ═══════════════════════════════════════════════════════════════
  Widget _buildList(
      BuildContext context,
      AdminColors tc,
      List<AdminNotification> items,
      ) {
    if (items.isEmpty) return _emptyState(tc);

    // Group by day bucket
    final groups = <String, List<AdminNotification>>{};
    for (final n in items) {
      final key = _bucketLabel(n.timestamp);
      groups.putIfAbsent(key, () => []).add(n);
    }

    final orderedKeys = ['Today', 'Yesterday', 'This week', 'Older'];

    return RefreshIndicator(
      color: tc.orange,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final key in orderedKeys)
            if (groups.containsKey(key)) ...[
              _sectionHeader(tc, key, groups[key]!.length),
              ...groups[key]!.map((n) => _tile(context, tc, n)),
            ],
        ],
      ),
    );
  }

  Widget _sectionHeader(AdminColors tc, String label, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: tc.textMuted,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: tc.orangeLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: tc.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TILE
  // ═══════════════════════════════════════════════════════════════
  Widget _tile(
      BuildContext context,
      AdminColors tc,
      AdminNotification n,
      ) {
    final style = _styleFor(n.type, tc);
    final time = n.timestamp != null ? _fmtTime(n.timestamp!) : '';
    final zoneEmoji = n.zoneEmoji;

    return Dismissible(
      key: ValueKey('notif_${n.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: tc.red.withValues(alpha: 0.15),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline_rounded, color: tc.red, size: 22),
      ),
      confirmDismiss: (_) async {
        await AdminNotificationService.instance.deleteNotification(n.id);
        return true;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!n.read) {
              AdminNotificationService.instance.markAsRead(n.id);
            }
            _showDetail(context, tc, n);
          },
          onLongPress: () => _showQuickActions(context, tc, n),
          child: Container(
            color: n.read
                ? Colors.transparent
                : tc.orange.withValues(alpha: tc.isDark ? 0.08 : 0.05),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon / emoji
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: zoneEmoji.isNotEmpty
                        ? Text(zoneEmoji,
                        style: const TextStyle(fontSize: 18))
                        : Icon(style.icon, color: style.color, size: 20),
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: n.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                fontSize: 14,
                                color: tc.text,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (!n.read) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: tc.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tc.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: tc.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              color: tc.muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (n.priority == 'high') ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tc.pillErrBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'HIGH',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: tc.pillErrTx,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                          if (n.zoneLabel.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                n.zoneLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: tc.muted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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

  // ═══════════════════════════════════════════════════════════════
  // DETAILS SHEET
  // ═══════════════════════════════════════════════════════════════
  void _showDetail(
      BuildContext context, AdminColors tc, AdminNotification n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
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
                  color: tc.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              n.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              n.message,
              style: TextStyle(
                fontSize: 13.5,
                color: tc.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            if (n.employeeName != null)
              _kv(tc, 'Employee', n.employeeName!),
            _kv(tc, 'Type', n.type),
            if (n.zoneLabel.isNotEmpty) _kv(tc, 'Zone', n.zoneLabel),
            if (n.priority != 'normal') _kv(tc, 'Priority', n.priority),
            _kv(tc, 'Time',
                n.timestamp != null ? _fullTime(n.timestamp!) : '—'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AdminNotificationService.instance
                          .deleteNotification(n.id);
                      Navigator.pop(context);
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 16, color: tc.red),
                    label: Text('Delete',
                        style: TextStyle(
                            color: tc.red, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: tc.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: tc.orange,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(AdminColors tc, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style: TextStyle(
                    fontSize: 12,
                    color: tc.muted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontSize: 12.5,
                    color: tc.text,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // QUICK ACTIONS (long press)
  // ═══════════════════════════════════════════════════════════════
  void _showQuickActions(
      BuildContext context, AdminColors tc, AdminNotification n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: tc.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!n.read)
              ListTile(
                leading: Icon(Icons.done_all_rounded, color: tc.orange),
                title: Text('Mark as read',
                    style: TextStyle(color: tc.text)),
                onTap: () {
                  AdminNotificationService.instance.markAsRead(n.id);
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: tc.red),
              title: Text('Delete',
                  style: TextStyle(color: tc.text)),
              onTap: () {
                AdminNotificationService.instance.deleteNotification(n.id);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CONFIRM DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<bool?> _confirmClear(
      BuildContext context, AdminColors tc) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: tc.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all notifications?',
            style: TextStyle(color: tc.text, fontWeight: FontWeight.w800)),
        content: Text(
          'Hindi na ito maibabalik. Tuloy ka?',
          style: TextStyle(color: tc.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: tc.textMuted, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: tc.red),
            child: const Text('Clear all',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EMPTY / ERROR
  // ═══════════════════════════════════════════════════════════════
  Widget _emptyState(AdminColors tc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tc.orangeLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_off_outlined,
                size: 32,
                color: tc.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Walang notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lalabas dito ang clock in/out, WFH toggles,\nat leave requests mula sa mga employee.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: tc.textMuted,
                height: 1.5,
              ),
            ),
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
            Text(
              'Error loading notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tc.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tc.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // STYLE MAP
  // ═══════════════════════════════════════════════════════════════
  _NStyle _styleFor(String type, AdminColors tc) {
    switch (type) {
      case 'clock_in':
        return _NStyle(
          Icons.login_rounded,
          tc.isDark ? const Color(0xFF4CE346) : const Color(0xFF16A34A),
        );
      case 'clock_out':
        return _NStyle(
          Icons.logout_rounded,
          tc.isDark ? const Color(0xFFFFB77D) : const Color(0xFFF59E0B),
        );
      case 'leave_request':
        return _NStyle(Icons.event_busy_rounded, tc.orange);
      case 'wfh_toggle':
        return _NStyle(
          Icons.home_work_rounded,
          tc.isDark ? const Color(0xFF93C5FD) : const Color(0xFF3B82F6),
        );
      case 'face_enrollment':
        return _NStyle(
          Icons.face_rounded,
          tc.isDark ? const Color(0xFFC4B5FD) : const Color(0xFF8B5CF6),
        );
      case 'geofence_alert':
        return _NStyle(
          Icons.warning_amber_rounded,
          tc.isDark ? const Color(0xFFFFB4AB) : const Color(0xFFEF4444),
        );
    // ✅ presence update
      case 'presence_update':
        return _NStyle(
          Icons.location_searching_rounded,
          tc.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
        );
    // ✅ BAGONG case para sa password change request
      case 'password_change':
        return _NStyle(
          Icons.lock_reset_rounded,
          tc.isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
        );
      default:
        return _NStyle(Icons.notifications_rounded, tc.muted);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // TIME HELPERS
  // ═══════════════════════════════════════════════════════════════
  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Ngayon lang';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, hh:mm a').format(d);
  }

  String _fullTime(DateTime d) =>
      DateFormat('MMM d, yyyy · hh:mm a').format(d);

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