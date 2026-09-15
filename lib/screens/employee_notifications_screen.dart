// lib/screens/employee_notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/employee_notification.dart';
import '../services/employee_notification_service.dart';

class EmployeeNotificationsScreen extends StatelessWidget {
  final String employeeId;

  const EmployeeNotificationsScreen({
    super.key,
    required this.employeeId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F10) : Colors.white;
    final card = isDark ? const Color(0xFF18181B) : Colors.white;
    final border = isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
    final text = isDark ? Colors.white : Colors.black;
    final muted = isDark ? const Color(0xFF888888) : const Color(0xFF71717A);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => EmployeeNotificationService.instance
                .markAllAsRead(employeeId),
            child: const Text(
              'Mark all read',
              style: TextStyle(
                  color: Color(0xFFFF8A00), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<EmployeeNotification>>(
        stream:
        EmployeeNotificationService.instance.streamForEmployee(employeeId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8A00)),
            );
          }

          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_off_outlined,
                      size: 56, color: muted),
                  const SizedBox(height: 12),
                  Text('Walang notifications',
                      style: TextStyle(fontSize: 15, color: muted)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Lalabas dito ang updates mula sa admin — announcements, payslips, reminders.',
                      style: TextStyle(fontSize: 12, color: muted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: border),
            itemBuilder: (_, i) {
              final n = items[i];
              return _tile(context, n, text, muted, border, isDark);
            },
          );
        },
      ),
    );
  }

  Widget _tile(
      BuildContext context,
      EmployeeNotification n,
      Color text,
      Color muted,
      Color border,
      bool isDark,
      ) {
    final style = _styleFor(n.type);

    return InkWell(
      onTap: () {
        if (!n.read) {
          EmployeeNotificationService.instance.markAsRead(n.id);
        }
      },
      child: Container(
        color: n.read
            ? Colors.transparent
            : const Color(0xFFFF8A00).withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(style.icon, color: style.color, size: 20),
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
                            color: text,
                          ),
                        ),
                      ),
                      if (!n.read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.message,
                    style: TextStyle(fontSize: 12, color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 11, color: muted),
                      const SizedBox(width: 3),
                      Text(n.senderName,
                          style: TextStyle(fontSize: 10, color: muted)),
                      const SizedBox(width: 8),
                      Text(
                        n.timestamp != null ? _fmtTime(n.timestamp!) : '',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _NStyle _styleFor(String type) {
    switch (type) {
      case 'announcement':
        return const _NStyle(Icons.campaign_rounded, Color(0xFF3B82F6));
      case 'payroll':
        return const _NStyle(
            Icons.receipt_long_rounded, Color(0xFF16A34A));
      case 'reminder':
        return const _NStyle(
            Icons.alarm_rounded, Color(0xFFF59E0B));
      default:
        return const _NStyle(Icons.info_rounded, Color(0xFF8B5CF6));
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