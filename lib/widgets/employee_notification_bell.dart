// lib/widgets/employee_notification_bell.dart
import 'package:flutter/material.dart';
import '../services/employee_notification_service.dart';
import '../services/local_notification_service.dart';
import '../screens/employee_notifications_screen.dart';

class EmployeeNotificationBell extends StatelessWidget {
  final String employeeId;
  final Color iconColor;
  final double size;

  const EmployeeNotificationBell({
    super.key,
    required this.employeeId,
    required this.iconColor,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ I-set ang handler kapag na-tap ang device notification
    LocalNotificationService.instance.onNotificationTap = (payload) {
      debugPrint('🔔 Tapped notification: $payload');
      _openNotifications(context);
    };

    return StreamBuilder<int>(
      stream:
      EmployeeNotificationService.instance.streamUnreadCount(employeeId),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => _openNotifications(context),
              icon: Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                size: size,
                color: iconColor,
              ),
            ),
            if (count > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeNotificationsScreen(employeeId: employeeId),
      ),
    );
  }
}