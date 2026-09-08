// lib/data/local/dao/connectivity_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static ConnectivityService? _instance;
  ConnectivityService._();
  static ConnectivityService get instance =>
      _instance ??= ConnectivityService._();

  final _connectivity = Connectivity();
  final _statusController = StreamController<bool>.broadcast();

  bool _isOnline = false;
  StreamSubscription? _sub;

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _statusController.stream;

  Future<void> init() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = _parse(result);
    } catch (_) {
      _isOnline = false;
    }

    _sub = _connectivity.onConnectivityChanged.listen((result) {
      final online = _parse(result);
      if (online != _isOnline) {
        _isOnline = online;
        _statusController.add(_isOnline);
      }
    });
  }

  bool _parse(dynamic result) {
    if (result is List) {
      // CORRECT LOGIC: True if ANY connection is not 'none'
      return result.any((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  void dispose() {
    _sub?.cancel();
    _statusController.close();
  }
}
