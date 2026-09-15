// lib/widgets/network_gate.dart
import 'package:flutter/material.dart';
import '../services/network_guard.dart';

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

class _NetworkGateState extends State<NetworkGate> {
  late Stream<bool> _stream;
  bool _online = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _stream = NetworkGuard.instance.onStatusChange;
    _online = NetworkGuard.instance.isOnline;
    _checkNow();
  }

  Future<void> _checkNow() async {
    if (mounted) setState(() => _checking = true);
    final ok = await NetworkGuard.instance.recheck();
    if (!mounted) return;
    setState(() {
      _online = ok;
      _checking = false;
    });
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
                'No Internet Connection',                      // ✅ English
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'An internet connection is required to continue.\n'
                    'Please check your WiFi or mobile data.',      // ✅ English
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF52525B),
                  height: 1.5,
                ),
              ),
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
                    _checking ? 'Checking...' : 'Try Again',    // ✅ English
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner(BuildContext context) {
    return Material(
      color: const Color(0xFFFF4D6D),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.wifi_off_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No internet connection',                     // ✅ English
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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