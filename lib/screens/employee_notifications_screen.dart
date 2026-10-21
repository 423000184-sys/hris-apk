// lib/screens/employee_notifications_screen.dart
// v1.5: 🗑️ DELETE support — individual, multi-select, and delete-all
//       • Long-press to enter selection mode
//       • "Select all" + "Delete selected" in AppBar
//       • Popup menu with "Mark all read" + "Delete all"
//       • PopScope: back button exits selection mode (hindi nagsasara ng screen)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../data/local/dao/connectivity_service.dart';
import '../models/employee_notification.dart';
import '../services/employee_notification_service.dart';
import '../services/demo_mode_service.dart';
import '../widgets/skeleton_screens.dart';

// ═══════════════════════════════════════════════════════════════
// HAND WATERMARK
// ═══════════════════════════════════════════════════════════════
const String _kLogoAsset = 'assets/images/logo.png';

// ⚠️ CHANGE THIS kung iba ang collection name sa Firestore
const String _kNotificationsCollection = 'notifications';

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

  // 🆕 Selection state
  final Set<String> _selectedIds = <String>{};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  static const Duration _demoSkeletonDuration = Duration(milliseconds: 900);

  late List<EmployeeNotification> _demoItems;

  bool get _isDemo => DemoModeService.instance.isEnabled;

  double _watermarkOpacity(bool isDark) => isDark ? 0.15 : 0.80;

  @override
  void initState() {
    super.initState();

    if (_isDemo) {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('🎭 [DemoMode] EmployeeNotifications — DEMO PATH');
      debugPrint('   • Skeleton shown for ${_demoSkeletonDuration.inMilliseconds}ms');
      debugPrint('═══════════════════════════════════════════');

      _demoItems = _buildDemoNotifications();
      _networkState = _NetworkState.online;
      _isInitialLoading = true;

      Future.delayed(_demoSkeletonDuration, () {
        if (!mounted) return;
        setState(() => _isInitialLoading = false);
        debugPrint('🎭 [DemoMode] Skeleton hidden — demo UI revealed');
      });

      return;
    }

    try {
      _networkSub =
          ConnectivityService.instance.onStatusChange.listen((online) {
            if (!mounted) return;
            debugPrint(
                '🌐 [EmployeeNotifications] connectivity → online=$online');

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

  // ═══════════════════════════════════════════════════════════════
  // HELPER — replaces missing copyWith() sa model
  // ═══════════════════════════════════════════════════════════════
  EmployeeNotification _withRead(EmployeeNotification n) {
    return EmployeeNotification(
      id: n.id,
      employeeId: n.employeeId,
      type: n.type,
      title: n.title,
      message: n.message,
      senderName: n.senderName,
      timestamp: n.timestamp,
      read: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 DEMO NOTIFICATIONS SEED
  // ═══════════════════════════════════════════════════════════════
  List<EmployeeNotification> _buildDemoNotifications() {
    final now = DateTime.now();
    return <EmployeeNotification>[
      EmployeeNotification(
        id: 'DEMO_NOTIF_001',
        employeeId: widget.employeeId,
        type: 'announcement',
        title: 'System Maintenance',
        message:
        'Magkakaroon ng scheduled maintenance sa Sabado, 10PM–12AM. '
            'Paki-log out bago mag 10PM.',
        senderName: 'HR Admin',
        timestamp: now.subtract(const Duration(minutes: 3)),
        read: false,
      ),
      EmployeeNotification(
        id: 'DEMO_NOTIF_002',
        employeeId: widget.employeeId,
        type: 'payroll',
        title: 'Payslip Available',
        message:
        'Available na ang payslip mo para sa cut-off na ito. '
            'Net pay: ₱22,300.00',
        senderName: 'Payroll Department',
        timestamp: now.subtract(const Duration(hours: 2)),
        read: false,
      ),
      EmployeeNotification(
        id: 'DEMO_NOTIF_003',
        employeeId: widget.employeeId,
        type: 'support_reply',
        title: 'Reply sa Ticket #1247',
        message:
        'Naayos na ang issue mo sa biometric — paki-try ulit ang '
            'fingerprint enrollment.',
        senderName: 'IT Support',
        timestamp: now.subtract(const Duration(hours: 5)),
        read: false,
      ),
      EmployeeNotification(
        id: 'DEMO_NOTIF_004',
        employeeId: widget.employeeId,
        type: 'reminder',
        title: 'Clock-In Reminder',
        message:
        'Huwag kalimutang mag clock-in bago mag 9:00 AM para hindi '
            'ma-markahan ng late.',
        senderName: 'System',
        timestamp: now.subtract(const Duration(hours: 12)),
        read: true,
      ),
      EmployeeNotification(
        id: 'DEMO_NOTIF_005',
        employeeId: widget.employeeId,
        type: 'support_resolved',
        title: 'Ticket Resolved',
        message:
        'Ang ticket #1189 mo (leave balance discrepancy) ay resolved na. '
            'Salamat sa pag-report.',
        senderName: 'HR Admin',
        timestamp: now.subtract(const Duration(days: 2)),
        read: true,
      ),
      EmployeeNotification(
        id: 'DEMO_NOTIF_006',
        employeeId: widget.employeeId,
        type: 'announcement',
        title: 'Team Building 2026',
        message:
        'Save the date! Team building sa Baguio sa March 15–16, 2026. '
            'Details to follow.',
        senderName: 'Events Committee',
        timestamp: now.subtract(const Duration(days: 5)),
        read: true,
      ),
    ];
  }

  Future<void> _checkNetworkOnEntry() async {
    if (_isDemo) {
      if (mounted) setState(() => _networkState = _NetworkState.online);
      return;
    }
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

  // ═══════════════════════════════════════════════════════════════
  // 🎭 MARK AS READ
  // ═══════════════════════════════════════════════════════════════
  void _markOneRead(String id) {
    if (_isDemo) {
      setState(() {
        _demoItems = _demoItems
            .map<EmployeeNotification>(
                (n) => n.id == id ? _withRead(n) : n)
            .toList();
      });
      debugPrint('🎭 [DemoMode] Marked read locally: $id');
      return;
    }
    EmployeeNotificationService.instance.markAsRead(id);
  }

  void _markAllRead() {
    if (_isDemo) {
      setState(() {
        _demoItems = _demoItems
            .map<EmployeeNotification>((n) => _withRead(n))
            .toList();
      });
      debugPrint('🎭 [DemoMode] Marked all read locally');
      return;
    }
    EmployeeNotificationService.instance
        .markAllAsRead(widget.employeeId);
  }

  // ═══════════════════════════════════════════════════════════════
  // 🗑️ DELETE — single, selected, all
  // ═══════════════════════════════════════════════════════════════
  Future<void> _deleteOne(String id) async {
    if (_isDemo) {
      setState(() {
        _demoItems.removeWhere((n) => n.id == id);
        _selectedIds.remove(id);
      });
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection(_kNotificationsCollection)
          .doc(id)
          .delete();
    } catch (e) {
      debugPrint('❌ [Delete] Single failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete notification.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = List<String>.from(_selectedIds);
    final ok = await _confirmDialog(
      'Delete ${ids.length} notification${ids.length == 1 ? '' : 's'}?',
    );
    if (ok != true) return;

    for (final id in ids) {
      await _deleteOne(id);
    }
    if (mounted) setState(() => _selectedIds.clear());
  }

  Future<void> _deleteAll() async {
    final ok = await _confirmDialog(
      'Delete ALL notifications? This cannot be undone.',
    );
    if (ok != true) return;

    if (_isDemo) {
      setState(() => _demoItems.clear());
      debugPrint('🎭 [DemoMode] Deleted all notifications locally');
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection(_kNotificationsCollection)
          .where('employeeId', isEqualTo: widget.employeeId)
          .get();

      // Fallback for snake_case field name
      QuerySnapshot<Map<String, dynamic>>? snap2;
      if (snap.docs.isEmpty) {
        try {
          snap2 = await FirebaseFirestore.instance
              .collection(_kNotificationsCollection)
              .where('employee_id', isEqualTo: widget.employeeId)
              .get();
        } catch (_) {}
      }

      final refs = <DocumentReference>{
        ...snap.docs.map((d) => d.reference),
        if (snap2 != null) ...snap2.docs.map((d) => d.reference),
      };

      for (final ref in refs) {
        await ref.delete();
      }
      debugPrint('🗑️ [Delete] Deleted ${refs.length} notifications');
    } catch (e) {
      debugPrint('❌ [Delete] All failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete all notifications.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<bool?> _confirmDialog(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor:
          isDark ? const Color(0xFF18181B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFEF4444), size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Confirm Delete',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              color: isDark
                  ? const Color(0xFFB0B0B0)
                  : const Color(0xFF52525B),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFFB0B0B0)
                        : const Color(0xFF71717A),
                    fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SELECTION HANDLERS
  // ═══════════════════════════════════════════════════════════════
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    setState(() => _selectedIds.add(id));
  }

  void _exitSelectionMode() {
    setState(() => _selectedIds.clear());
  }

  void _selectAll(List<EmployeeNotification> items) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(items.map((n) => n.id));
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F10) : Colors.white;
    final card = isDark ? const Color(0xFF18181B) : Colors.white;
    final border =
    isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
    final text = isDark ? Colors.white : Colors.black;
    final muted =
    isDark ? const Color(0xFF888888) : const Color(0xFF71717A);

    final isOffline = _networkState == _NetworkState.offline;
    final isChecking = _networkState == _NetworkState.checking;

    // Skeleton loading state
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

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: _buildAppBar(card, text, isDark),
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _buildHandWatermark(opacity: _watermarkOpacity(isDark)),

            if (_isDemo)
              _buildList(_demoItems, text, muted, border, isDark)
            else
              StreamBuilder<List<EmployeeNotification>>(
                stream: EmployeeNotificationService.instance
                    .streamForEmployee(widget.employeeId),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFFF8A00)),
                    );
                  }

                  final items = snap.data ?? <EmployeeNotification>[];

                  // Cleanup: remove stale selections kung nawala na ang item
                  // (e.g., na-delete sa ibang device)
                  final ids = items.map((n) => n.id).toSet();
                  _selectedIds.removeWhere((id) => !ids.contains(id));

                  return _buildList(items, text, muted, border, isDark);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // APPBAR — normal mode vs selection mode
  // ═══════════════════════════════════════════════════════════════
  PreferredSizeWidget _buildAppBar(Color card, Color text, bool isDark) {
    if (_isSelectionMode) {
      return AppBar(
        backgroundColor: card,
        foregroundColor: text,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectionMode,
          tooltip: 'Cancel selection',
        ),
        title: Text(
          '${_selectedIds.length} selected',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all_rounded),
            tooltip: 'Select all',
            onPressed: () {
              if (_isDemo) {
                _selectAll(_demoItems);
              } else {
                // Select all from current stream — handled in build
                // For simplicity, fetch current items via stream snapshot.
                // Here, we add the visible IDs one by one.
                // Better: pass the current items via state.
                // Simpler approach: use the stream's last value.
                _selectAllFromCurrent();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFEF4444)),
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: card,
      foregroundColor: text,
      elevation: 0,
      title: Row(
        children: [
          const Text('Notifications',
              style: TextStyle(fontWeight: FontWeight.w700)),
          if (_isDemo) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF54900),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.science_rounded,
                      color: Colors.white, size: 10),
                  SizedBox(width: 3),
                  Text('DEMO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6)),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: text),
          color: card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onSelected: (v) {
            if (v == 'mark_all_read') {
              _markAllRead();
            } else if (v == 'delete_all') {
              _deleteAll();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'mark_all_read',
              child: Row(
                children: [
                  const Icon(Icons.done_all_rounded,
                      color: Color(0xFFFF8A00), size: 18),
                  const SizedBox(width: 10),
                  Text('Mark all as read',
                      style: TextStyle(color: text, fontSize: 13)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete_all',
              child: Row(
                children: [
                  const Icon(Icons.delete_sweep_rounded,
                      color: Color(0xFFEF4444), size: 18),
                  const SizedBox(width: 10),
                  Text('Delete all',
                      style: TextStyle(color: text, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Need to track last stream items for "select all" in normal mode
  List<EmployeeNotification> _lastStreamItems = const [];

  void _selectAllFromCurrent() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_lastStreamItems.map((n) => n.id));
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SHARED LIST BUILDER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildList(
      List<EmployeeNotification> items,
      Color text,
      Color muted,
      Color border,
      bool isDark,
      ) {
    // Track for select-all
    _lastStreamItems = items;

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

  // ═══════════════════════════════════════════════════════════════
  // TILE — supports long-press to select
  // ═══════════════════════════════════════════════════════════════
  Widget _tile(
      BuildContext context,
      EmployeeNotification n,
      Color text,
      Color muted,
      Color border,
      bool isDark,
      ) {
    final style = _styleFor(n.type);
    final isSelected = _selectedIds.contains(n.id);
    final inSelectionMode = _isSelectionMode;

    final bgColor = isSelected
        ? const Color(0xFFFF8A00).withValues(alpha: 0.14)
        : (n.read
        ? Colors.transparent
        : const Color(0xFFFF8A00).withValues(alpha: 0.05));

    return InkWell(
      onTap: () {
        if (inSelectionMode) {
          _toggleSelection(n.id);
        } else {
          if (!n.read) _markOneRead(n.id);
        }
      },
      onLongPress: () {
        if (!inSelectionMode) {
          _enterSelectionMode(n.id);
        } else {
          _toggleSelection(n.id);
        }
      },
      child: Container(
        color: bgColor,
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🆕 Checkbox when in selection mode
            if (inSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? const Color(0xFFFF8A00)
                      : muted.withValues(alpha: 0.6),
                  size: 22,
                ),
              ),

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
                      if (!n.read && !inSelectionMode)
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
                    style: TextStyle(
                        fontSize: 12, color: muted, height: 1.4),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 11, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          n.senderName,
                          style:
                          TextStyle(fontSize: 10, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        n.timestamp != null
                            ? _fmtTime(n.timestamp!)
                            : '',
                        style:
                        TextStyle(fontSize: 10, color: muted),
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
        return const _NStyle(
            Icons.campaign_rounded, Color(0xFF3B82F6));
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
        return const _NStyle(
            Icons.info_rounded, Color(0xFF8B5CF6));
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