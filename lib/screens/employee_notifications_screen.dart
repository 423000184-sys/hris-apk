// lib/screens/employee_notifications_screen.dart
// ═══════════════════════════════════════════════════════════════════
// EMPLOYEE NOTIFICATIONS SCREEN  v1.1
//   - Added 'support_reply' and 'support_resolved' types
//   - All other code unchanged
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee_notification.dart';
import '../services/employee_notification_service.dart';
import '../widgets/skeleton_screens.dart';

// ═══════════════════════════════════════════════════════════════
// HAND WATERMARK
// ═══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';

double _degToRad(double deg) => deg * 3.1415926535 / 180;

Widget _buildHandWatermark({required double opacity}) {
  return Positioned(
    bottom: -130,
    left: -150,
    child: IgnorePointer(
      child: Transform.rotate(
        angle: _degToRad(425),
        child: Opacity(
          opacity: opacity,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Color.fromRGBO(255, 138, 0, 0.10),
              BlendMode.srcIn,
            ),
            child: Image.asset(
              _kLogoAsset,
              width: 500,
              height: 500,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                debugPrint('logo.png failed to load');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    ),
  );
}

enum _NetworkState { online, offline, checking }

class EmployeeNotificationsScreen extends StatefulWidget {
  final String employeeId;

  const EmployeeNotificationsScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<EmployeeNotificationsScreen> createState() =>
      _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState
    extends State<EmployeeNotificationsScreen> {
  _NetworkState _networkState = _NetworkState.online;
  String _networkErrorMessage = 'No internet connection.';
  bool _showOfflineOverlay = false;
  Timer? _overlayDelayTimer;
  bool _isInitialLoading = true;
  StreamSubscription<bool>? _networkSub;

  double _watermarkOpacity(bool isDark) => isDark ? 0.15 : 0.80;

  @override
  void initState() {
    super.initState();

    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint('🌐 [EmployeeNotifications] connectivity → online=$online');

            if (!online) {
              _overlayDelayTimer?.cancel();
              setState(() {
                _networkState = _NetworkState.offline;
                _networkErrorMessage =
                'No internet connection.\nPlease check your network.';
                _showOfflineOverlay = false;
              });

              _overlayDelayTimer =
                  Timer(const Duration(milliseconds: 1200), () {
                    if (mounted && _networkState == _NetworkState.offline) {
                      setState(() => _showOfflineOverlay = true);
                    }
                  });
            } else if (_networkState == _NetworkState.offline) {
              _overlayDelayTimer?.cancel();
              _showOfflineOverlay = false;
              _retryNetworkCheck();
            }
          });
    } catch (e) {
      debugPrint('⚠️ [EmployeeNotifications] connectivity failed: $e');
    }

    _checkNetworkOnEntry().then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _isInitialLoading = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    _overlayDelayTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkNetworkOnEntry() async {
    if (!mounted) return;
    setState(() => _networkState = _NetworkState.checking);

    bool hasNet = true;
    try {
      hasNet = ConnectivityService.instance.isOnline;
    } catch (_) {
      hasNet = true;
    }

    if (!mounted) return;

    if (!hasNet) {
      setState(() {
        _networkState = _NetworkState.offline;
        _networkErrorMessage =
        'No internet connection.\nPlease check your network and try again.';
      });
      return;
    }

    setState(() => _networkState = _NetworkState.online);
  }

  Future<void> _retryNetworkCheck() async {
    if (!mounted) return;
    setState(() {
      _networkState = _NetworkState.checking;
      _showOfflineOverlay = false;
    });
    await _checkNetworkOnEntry();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F10) : Colors.white;
    final card = isDark ? const Color(0xFF18181B) : Colors.white;
    final border = isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
    final text = isDark ? Colors.white : Colors.black;
    final muted = isDark ? const Color(0xFF888888) : const Color(0xFF71717A);

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

    if (isOffline || isChecking || _isInitialLoading) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: card,
          foregroundColor: text,
          elevation: 0,
          title: const Text('Notifications',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              const ListSkeleton(itemCount: 6),
              if (isOffline)
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: _showOfflineOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_showOfflineOverlay,
                      child: _buildNetworkErrorOverlay(
                        message: _networkErrorMessage,
                        onRetry: _retryNetworkCheck,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

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
                .markAllAsRead(widget.employeeId),
            child: const Text(
              'Mark all read',
              style: TextStyle(
                  color: Color(0xFFFF8A00), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          _buildHandWatermark(opacity: _watermarkOpacity(isDark)),

          StreamBuilder<List<EmployeeNotification>>(
            stream: EmployeeNotificationService.instance
                .streamForEmployee(widget.employeeId),
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
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: border),
                itemBuilder: (_, i) {
                  final n = items[i];
                  return _tile(context, n, text, muted, border, isDark);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkErrorOverlay({
    required String message,
    required VoidCallback onRetry,
  }) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFF8A00),
                  Color(0xFFFA6A00),
                  Color(0xFFF54900),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 1.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 180,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFFF8A00),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Automatically retries when network returns.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
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

  // ✅ Added: support_reply & support_resolved cases
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
      case 'support_reply':
        return const _NStyle(
            Icons.support_agent_rounded, Color(0xFF2563EB));
      case 'support_resolved':
        return const _NStyle(
            Icons.verified_rounded, Color(0xFF16A34A));
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