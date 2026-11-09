// lib/services/network_guard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show InternetAddress, HttpClient;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NetworkGuard {
  NetworkGuard._();
  static final NetworkGuard instance = NetworkGuard._();

  // ═══════════════════════════════════════════════════════════════
  // STATE — fail-open by default
  // ═══════════════════════════════════════════════════════════════
  bool _isOnline = true; // 🔑 default ONLINE, hindi offline
  bool get isOnline => _isOnline;

  int _consecutiveFailures = 0;
  DateTime? _lastOnlineAt;
  DateTime? _lastOfflineAt;
  DateTime? _lastRecheckAt;

  // Kailangan ng 2 sunod-sunod na failed probe bago mag-declare ng offline.
  // Isang flaky signal lang hindi dapat mag-block ng login.
  static const int _offlineThreshold = 2;

  // Rate limit para sa manual recheck
  static const int _minRecheckIntervalMs = 2000;
  static const int _maxRechecksPerMinute = 30;
  final List<DateTime> _recheckHistory = [];

  // Iwasan ang sabay-sabay na probe
  Future<bool>? _inflightProbe;

  bool get isDegraded => _consecutiveFailures > 0 && _isOnline;
  int get consecutiveFailures => _consecutiveFailures;

  String get connectionQuality {
    if (!_isOnline) return 'offline';
    if (_consecutiveFailures >= 3) return 'poor';
    if (_consecutiveFailures >= 1) return 'fair';
    return 'good';
  }

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  StreamSubscription? _sub;
  Timer? _pollTimer;
  bool _started = false;

  // ═══════════════════════════════════════════════════════════════
  // START
  // ═══════════════════════════════════════════════════════════════
  Future<void> start() async {
    if (_started) {
      debugPrint('🔒 [NetworkGuard] Already started');
      return;
    }
    _started = true;

    try {
      final conn = Connectivity();

      _sub = conn.onConnectivityChanged.listen((results) async {
        // 🔑 Ang `none` ay UNKNOWN, hindi OFFLINE.
        // Sa Web at ilang emulator, nagre-report ng `none` ang plugin
        // kahit may internet naman talaga.
        final hasTransport = results.any((r) =>
        r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet);

        if (!hasTransport) {
          debugPrint('🔒 [NetworkGuard] Transport=NONE → verifying…');
          // HUWAG agad mag-declare ng offline. I-probe muna.
          await _probeAndUpdate('event_no_transport');
          return;
        }

        await _probeAndUpdate('event_transport_ok');
      });

      // Initial check — non-blocking, fail-open
      unawaited(_probeAndUpdate('initial'));

      _startAdaptivePolling();
    } catch (e) {
      debugPrint('⚠️ NetworkGuard.start error: $e');
      // Fail-safe: assume online para hindi ma-block ang app
      _recordOnline();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PROBE — single source of truth for online/offline transitions
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _probeAndUpdate(String reason) {
    // Deduplicate concurrent probes
    if (_inflightProbe != null) return _inflightProbe!;

    final future = _doProbeAndUpdate(reason);
    _inflightProbe = future;
    future.whenComplete(() {
      _inflightProbe = null;
    });
    return future;
  }

  Future<bool> _doProbeAndUpdate(String reason) async {
    final ok = await _hasRealInternet();

    if (ok) {
      final wasOffline = !_isOnline;
      _consecutiveFailures = 0;
      _lastOnlineAt = DateTime.now();

      if (wasOffline) {
        _recordOnline();
        _startAdaptivePolling(); // re-evaluate interval
      }
      return true;
    }

    _consecutiveFailures++;
    debugPrint('🔒 [NetworkGuard] Probe FAILED ($reason) — '
        'failures=$_consecutiveFailures');

    // 🔑 OFFLINE lang kapag N sunod-sunod na failure
    if (_isOnline && _consecutiveFailures >= _offlineThreshold) {
      _recordOffline(reason);
      _startAdaptivePolling();
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════════
  // ADAPTIVE POLLING
  // ═══════════════════════════════════════════════════════════════
  void _startAdaptivePolling() {
    _pollTimer?.cancel();

    Duration interval;
    if (!_isOnline) {
      interval = const Duration(seconds: 4);
    } else if (_consecutiveFailures > 0) {
      interval = const Duration(seconds: 10);
    } else {
      interval = const Duration(seconds: 25);
    }

    _pollTimer = Timer.periodic(interval, (_) async {
      await _probeAndUpdate('poll');
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // ONLINE / OFFLINE
  // ═══════════════════════════════════════════════════════════════
  void _recordOnline() {
    final wasOffline = !_isOnline;
    _isOnline = true;
    _consecutiveFailures = 0;
    _lastOnlineAt = DateTime.now();

    if (wasOffline) {
      debugPrint('🌐 [NetworkGuard] Back ONLINE');
      _controller.add(true);
      unawaited(_logNetworkEvent(
        type: 'network_online',
        severity: 'info',
        details: 'Connection restored',
      ));
    }
  }

  void _recordOffline(String reason) {
    final wasOnline = _isOnline;
    _isOnline = false;
    _lastOfflineAt = DateTime.now();

    if (wasOnline) {
      debugPrint('🌐 [NetworkGuard] Went OFFLINE — reason: $reason');
      _controller.add(false);
      unawaited(_logNetworkEvent(
        type: 'network_offline',
        severity: 'medium',
        details: 'Connection lost: $reason',
      ));
    }
  }

  Future<void> _logNetworkEvent({
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
        'consecutiveFailures': _consecutiveFailures,
        'platform': kIsWeb ? 'web' : 'mobile',
        'stage': 'network_guard',
        'timestamp': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Silent — offline nga diba?
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REAL INTERNET CHECK
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _hasRealInternet() async {
    // 🔑 WEB MUNA — ang browser ang may kontrol sa connectivity.
    // Hindi mapagkakatiwalaan ang connectivity_plus sa web; minsan
    // nagre-report ng `none` kahit bukas pa ang tab.
    if (kIsWeb) return true;

    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));

      final hasTransport = results.any((r) =>
      r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (!hasTransport) {
        debugPrint('🔒 [NetworkGuard] No transport → DNS fallback');
        // Huwag sumuko agad: mag-DNS probe pa rin. Kung nag-resolve ang
        // public host, online tayo kahit sabi ng plugin ay wala.
        final ok = await _checkDns('cloudflare.com') ||
            await _checkDns('google.com');
        return ok;
      }

      return await _verifyWithMultipleEndpoints();
    } catch (e) {
      debugPrint('⚠️ _hasRealInternet error: $e');
      // Ambiguous — fail-open para hindi ma-block ng plugin bug ang login.
      return true;
    }
  }

  Future<bool> _verifyWithMultipleEndpoints() async {
    try {
      final results = await Future.wait(<Future<bool>>[
        _checkDns('google.com'),
        _checkDns('cloudflare.com'),
        _checkHttpResponse(),
      ]).timeout(
        const Duration(seconds: 6),
        onTimeout: () => <bool>[false, false, false],
      );

      final successCount = results.where((r) => r == true).length;
      debugPrint('🔒 [NetworkGuard] Endpoints: $results '
          '($successCount/3)');
      return successCount >= 2;
    } catch (e) {
      debugPrint('⚠️ verify error: $e');
      return false;
    }
  }

  Future<bool> _checkDns(String host) async {
    try {
      final lookup = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (lookup.isEmpty) return false;

      final first = lookup.first;
      if (first.rawAddress.isEmpty) return false;

      final addr = first.address;
      if (addr.startsWith('10.') ||
          addr.startsWith('127.') ||
          addr.startsWith('192.168.') ||
          addr.startsWith('172.16.') ||
          addr.startsWith('172.17.') ||
          addr.startsWith('172.18.') ||
          addr.startsWith('172.19.') ||
          addr.startsWith('172.20.') ||
          addr.startsWith('172.21.') ||
          addr.startsWith('172.22.') ||
          addr.startsWith('172.23.') ||
          addr.startsWith('172.24.') ||
          addr.startsWith('172.25.') ||
          addr.startsWith('172.26.') ||
          addr.startsWith('172.27.') ||
          addr.startsWith('172.28.') ||
          addr.startsWith('172.29.') ||
          addr.startsWith('172.30.') ||
          addr.startsWith('172.31.') ||
          addr == '0.0.0.0') {
        debugPrint('🔒 [NetworkGuard] Rejected private IP: $addr');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('🔒 [NetworkGuard] DNS fail ($host): $e');
      return false;
    }
  }

  Future<bool> _checkHttpResponse() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 3);

      final request = await client
          .getUrl(Uri.parse('http://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 3));

      final response = await request.close()
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 204) {
        debugPrint('🔒 [NetworkGuard] Non-204: ${response.statusCode} '
            '(captive portal?)');
        return false;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 2));

      if (body.isNotEmpty && body.length > 5) {
        debugPrint('🔒 [NetworkGuard] Body >5 chars — captive portal');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('🔒 [NetworkGuard] HTTP check failed: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MANUAL RECHECK — sliding 1-minute rate limit
  // ═══════════════════════════════════════════════════════════════
  Future<bool> recheck() async {
    final now = DateTime.now();

    // Minimum interval sa pagitan ng calls
    if (_lastRecheckAt != null) {
      final elapsed = now.difference(_lastRecheckAt!).inMilliseconds;
      if (elapsed < _minRecheckIntervalMs) {
        debugPrint('🔒 [NetworkGuard] Recheck rate-limited '
            '(${elapsed}ms / ${_minRecheckIntervalMs}ms)');
        return _isOnline;
      }
    }

    // Sliding window: tanggalin ang mas matanda sa 60s
    _recheckHistory.removeWhere(
          (t) => now.difference(t).inSeconds > 60,
    );

    if (_recheckHistory.length >= _maxRechecksPerMinute) {
      debugPrint('🔒 [NetworkGuard] Recheck rate-limited '
          '($_maxRechecksPerMinute/min)');
      return _isOnline;
    }

    _recheckHistory.add(now);
    _lastRecheckAt = now;

    return _probeAndUpdate('manual_recheck');
  }

  Map<String, dynamic> getDiagnostics() => {
    'isOnline': _isOnline,
    'quality': connectionQuality,
    'consecutiveFailures': _consecutiveFailures,
    'lastOnlineAt': _lastOnlineAt?.toIso8601String(),
    'lastOfflineAt': _lastOfflineAt?.toIso8601String(),
    'lastRecheckAt': _lastRecheckAt?.toIso8601String(),
    'rechecksLastMinute': _recheckHistory.length,
    'isDegraded': isDegraded,
    'started': _started,
  };

  void dispose() {
    _sub?.cancel();
    _pollTimer?.cancel();
    _controller.close();
    _started = false;
  }
}