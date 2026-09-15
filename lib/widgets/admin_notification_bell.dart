// lib/widgets/admin_notification_bell.dart
import 'package:flutter/material.dart';
import '../services/admin_notification_service.dart';
import '../screens/admin_notification_page.dart';
import '../screens/admin_theme.dart';      // ✅ para sa adminRoute()

class AdminNotificationBell extends StatelessWidget {
  final Color iconColor;
  final double size;

  const AdminNotificationBell({
    super.key,
    required this.iconColor,
    this.size = 21,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: AdminNotificationService.instance.streamUnreadCount(),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {
                // ✅ GAMITIN ANG adminRoute PARA SUMABAY SA THEME
                Navigator.of(context).push(
                  adminRoute(const AdminNotificationPage()),
                );
              },
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
}