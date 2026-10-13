// lib/data/local/dao/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

class ConnectivityService {
  static ConnectivityService? _instance;
  ConnectivityService._();
  static ConnectivityService get instance =>
      _instance ??= ConnectivityService._();

  final _connectivity = Connectivity();
  final _statusController = StreamController<bool>.broadcast();

  bool _isOnline = false;
  StreamSubscription? _sub;
  Timer? _heartbeatTimer;
  bool _checking = false;

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _statusController.stream;

  // ═══════════════════════════════════════════════════════════════
  // 🌐 PING URLs
  // Web   → api.ipify.org (may CORS headers, gumagana sa browser)
  // Mobile→ clients3.google.com (mas mabilis at reliable)
  // ═══════════════════════════════════════════════════════════════
  static const String _webPingUrl = 'https://api.ipify.org?format=json';
  static const String _mobilePingUrl =
      'https://clients3.google.com/generate_204';

  Future<void> init() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = await _checkRealInternet(result);
    } catch (_) {
      _isOnline = false;
    }
    _emit(_isOnline);

    // Interface changes (WiFi/data on/off)
    _sub = _connectivity.onConnectivityChanged.listen((result) async {
      final online = await _checkRealInternet(result);
      _emit(online);
    });

    // ⏱️ Heartbeat — para madetect ang "connected pero walang internet"
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_checking) return;
      _checking = true;
      try {
        final online = await _pingInternet();
        _emit(online);
      } finally {
        _checking = false;
      }
    });
  }

  Future<bool> _checkRealInternet(dynamic result) async {
    if (!_parse(result)) return false;
    return _pingInternet();
  }

  /// Totoong internet check — web-compatible
  Future<bool> _pingInternet() async {
    // Pumili ng URL base sa platform
    final urlString = kIsWeb ? _webPingUrl : _mobilePingUrl;

    try {
      final res = await http.get(
        Uri.parse(urlString),
        headers: kIsWeb
            ? {'Accept': 'application/json'}
            : null,
      ).timeout(const Duration(seconds: 4));

      // Success = 200 o 204
      // Web (ipify):   200 OK
      // Mobile (google): 204 No Content
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      debugPrint('📡 ping failed: $e');
      return false;
    }
  }

  bool _parse(dynamic result) {
    if (result is List) {
      return result.any((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  void _emit(bool online) {
    if (online != _isOnline) {
      _isOnline = online;
      debugPrint('🌐 ConnectivityService → online=$online');
      if (!_statusController.isClosed) _statusController.add(online);
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _sub?.cancel();
    _statusController.close();
  }
}