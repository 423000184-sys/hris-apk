// lib/screens/admin_notification_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/admin_notification.dart';
import '../services/admin_notification_service.dart';
import 'admin_theme.dart';

class AdminNotificationPage extends StatelessWidget {
  const AdminNotificationPage({super.key});

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
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: tc.textMuted),
            color: tc.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (v) {
              if (v == 'clear') {
                AdminNotificationService.instance.clearAll();
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
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: tc.border),
        ),
      ),
      body: StreamBuilder<List<AdminNotification>>(
        stream: AdminNotificationService.instance.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: tc.orange,
                strokeWidth: 2.5,
              ),
            );
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return _emptyState(tc);
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: tc.border,
              indent: 68,
            ),
            itemBuilder: (_, i) => _tile(context, tc, items[i]),
          );
        },
      ),
    );
  }

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

  Widget _tile(
      BuildContext context, AdminColors tc, AdminNotification n) {
    final style = _styleFor(n.type, tc);
    final time = n.timestamp != null ? _fmtTime(n.timestamp!) : '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!n.read) {
            AdminNotificationService.instance.markAsRead(n.id);
          }
        },
        child: Container(
          color: n.read
              ? Colors.transparent
              : tc.orange.withValues(alpha: tc.isDark ? 0.08 : 0.05),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  style.icon,
                  color: style.color,
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
                            n.title,
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
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      case 'wfh_used':
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
      default:
        return _NStyle(Icons.notifications_rounded, tc.muted);
    }
  }

  String _fmtTime(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Ngayon lang';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, hh:mm a').format(d);
  }
}

class _NStyle {
  final IconData icon;
  final Color color;
  const _NStyle(this.icon, this.color);
}