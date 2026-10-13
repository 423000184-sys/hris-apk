// lib/widgets/network_gate.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/network_guard.dart';
import '../services/offline_attendance_service.dart';

class NetworkGate extends StatefulWidget {
  final Widget child;
  final bool showBannerOnly;

  const NetworkGate({
    super.key,
    required this.child,
    this.showBannerOnly = false,
  });

  @override
  State<NetworkGate> createState() => _NetworkGateState();
}

class _NetworkGateState extends State<NetworkGate>
    with WidgetsBindingObserver {
  late Stream<bool> _stream;
  bool _online = true;
  bool _checking = false;
  int _retryCount = 0;
  DateTime? _lastRetryAt;

  // 🔒 Security constants
  static const int _maxRetries = 5;
  static const int _retryCooldownMs = 3000;

  Timer? _offlineTimer;
  bool _showRetryWarning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = NetworkGuard.instance.onStatusChange;
    _online = NetworkGuard.instance.isOnline;
    _checkNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _offlineTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 🔒 Auto-recheck when app resumes
    if (state == AppLifecycleState.resumed && !_online) {
      debugPrint('🔒 [NetworkGate] App resumed — auto-rechecking');
      _checkNow();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 CHECK NOW — with debounce + rate limit
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkNow() async {
    if (_checking) return;

    // Rate limit
    final now = DateTime.now();
    if (_lastRetryAt != null) {
      final elapsed = now.difference(_lastRetryAt!).inMilliseconds;
      if (elapsed < _retryCooldownMs) {
        debugPrint('🔒 [NetworkGate] Retry rate-limited '
            '(${elapsed}ms / ${_retryCooldownMs}ms)');
        return;
      }
    }

    _lastRetryAt = now;
    _retryCount++;

    if (mounted) setState(() => _checking = true);

    // 🔒 Log retry attempt
    if (_retryCount > 2) {
      _logEvent(
        type: 'network_retry',
        severity: _retryCount > 4 ? 'high' : 'medium',
        details: 'Retry attempt #$_retryCount',
      );
    }

    final ok = await NetworkGuard.instance.recheck();

    if (!mounted) return;

    setState(() {
      _online = ok;
      _checking = false;
      if (ok) {
        _retryCount = 0;
        _showRetryWarning = false;
      } else if (_retryCount >= _maxRetries) {
        _showRetryWarning = true;
      }
    });

    // When back online, trigger sync + log
    if (ok) {
      OfflineAttendanceService.instance.syncPending();
      _logEvent(
        type: 'network_recovered',
        severity: 'info',
        details: 'Connection restored after $_retryCount retries',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔒 SECURITY LOGGING
  // ═══════════════════════════════════════════════════════════════
  Future<void> _logEvent({
    required String type,
    required String severity,
    required String details,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('security_events')
          .add({
        'type': type,
        'severity': severity,
        'details': details,
        'stage': 'network_gate',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _stream,
      initialData: _online,
      builder: (context, snap) {
        final online = snap.data ?? true;
        return Stack(
          children: [
            widget.child,
            if (!online && !widget.showBannerOnly)
              Positioned.fill(child: _buildOfflineOverlay(context)),
            if (!online && widget.showBannerOnly)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildOfflineBanner(context),
              ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OFFLINE OVERLAY
  // ═══════════════════════════════════════════════════════════════
  Widget _buildOfflineOverlay(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF8A00).withValues(alpha: 0.12),
                  border: Border.all(
                    color: const Color(0xFFFF8A00).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Color(0xFFFF8A00),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No Internet Connection',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'An internet connection is required to continue.\n'
                    'Please check your WiFi or mobile data.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF52525B),
                  height: 1.5,
                ),
              ),

              // 🔒 Retry warning
              if (_showRetryWarning) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Multiple retries failed. Check your network '
                              'settings or contact support.',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF991B1B),
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _checkNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _checking
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    _checking ? 'Checking...' : 'Try Again',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // 🔒 Retry counter
              if (_retryCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Retry $_retryCount of $_maxRetries',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF71717A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OFFLINE BANNER
  // ═══════════════════════════════════════════════════════════════
  Widget _buildOfflineBanner(BuildContext context) {
    final guard = NetworkGuard.instance;
    final quality = guard.connectionQuality;

    // 🔒 Color based on connection quality
    Color bannerColor;
    IconData iconData;
    String message;

    switch (quality) {
      case 'poor':
        bannerColor = const Color(0xFFB91C1C); // dark red
        iconData = Icons.signal_wifi_bad_rounded;
        message = 'Weak connection — records will sync later';
        break;
      case 'fair':
        bannerColor = const Color(0xFFEA580C); // orange
        iconData = Icons.signal_wifi_statusbar_connected_no_internet_4_rounded;
        message = 'Unstable connection — retrying...';
        break;
      default:
        bannerColor = const Color(0xFFFF4D6D);
        iconData = Icons.wifi_off_rounded;
        message = 'No internet — records will sync later';
    }

    return Material(
      color: bannerColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(iconData, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Pending count badge
              FutureBuilder<int>(
                future: OfflineAttendanceService.instance.getPendingCount(),
                builder: (context, snap) {
                  final count = snap.data ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count pending',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),

              TextButton(
                onPressed: _checking ? null : _checkNow,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _checking ? '...' : 'Retry',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}