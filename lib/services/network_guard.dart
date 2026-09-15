// lib/services/network_guard.dart
import 'dart:async';
import 'dart:io' show InternetAddress;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkGuard {
  NetworkGuard._();

  static final NetworkGuard instance = NetworkGuard._();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  StreamSubscription? _sub;
  Timer? _pollTimer;

  Future<void> start() async {
    try {
      final conn = Connectivity();

      _sub = conn.onConnectivityChanged.listen((results) async {
        final hasTransport = results.any((r) =>
        r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet);

        if (!hasTransport) {
          _setStatus(false);
          return;
        }
        final ok = await _hasRealInternet();
        _setStatus(ok);
      });

      final ok = await _hasRealInternet();
      _setStatus(ok);

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        final ok = await _hasRealInternet();
        _setStatus(ok);
      });
    } catch (e) {
      debugPrint('⚠️ NetworkGuard.start: $e');
      _setStatus(true);
    }
  }

  void _setStatus(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    debugPrint('🌐 NetworkGuard: online = $online');
    _controller.add(online);
  }

  Future<bool> _hasRealInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasTransport = results.any((r) =>
      r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (!hasTransport) return false;

      // ✅ WEB: hindi na mag-fetch ng google.com
      //    (CORS error ang dating nangyayari).
      //    Tiwala na lang sa connectivity_plus (navigator.onLine).
      if (kIsWeb) return true;

      // ✅ MOBILE/DESKTOP: DNS lookup lang, walang CORS issue.
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ _hasRealInternet: $e');
      return false;
    }
  }

  Future<bool> recheck() async {
    final ok = await _hasRealInternet();
    _setStatus(ok);
    return ok;
  }

  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    _controller.close();
  }
}