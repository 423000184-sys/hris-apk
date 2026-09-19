// lib/services/device_info_service.dart
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

// ══════════════════════════════════════════════════════════════
// 🆕 DEVICE INFO SERVICE — gets ACTUAL device model
//
// Returns real device names like:
//   Android: "Samsung SM-A546E", "Xiaomi 2201123G", "Oppo CPH2477"
//   iOS:     "iPhone13,2" (iPhone 12), "iPhone14,5" (iPhone 13)
//   Web:     "Chrome 120.0.0.0"
//   Windows: "Windows 11 Pro"
//   macOS:   "MacBookPro18,3"
// ══════════════════════════════════════════════════════════════
class DeviceInfoService {
  DeviceInfoService._();
  static final DeviceInfoService instance = DeviceInfoService._();

  String? _cachedModel;

  /// Get the actual device model name.
  /// Cached after first call — safe to call multiple times.
  Future<String> getDeviceModel() async {
    if (_cachedModel != null && _cachedModel!.isNotEmpty) {
      return _cachedModel!;
    }

    try {
      final info = DeviceInfoPlugin();

      // ─── WEB ───
      if (kIsWeb) {
        try {
          final webInfo = await info.webBrowserInfo;
          final browser = webInfo.browserName.name;
          final version = webInfo.appVersion ?? '';
          final vShort = version.split('.').take(2).join('.');
          _cachedModel = vShort.isNotEmpty
              ? '${_cap(browser)} $vShort (Web)'
              : '${_cap(browser)} (Web)';
          return _cachedModel!;
        } catch (_) {
          _cachedModel = 'Web Browser';
          return _cachedModel!;
        }
      }

      // ─── ANDROID ───
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        _cachedModel = _formatAndroid(
          brand: android.brand,
          model: android.model,
          device: android.device,
        );
        return _cachedModel!;
      }

      // ─── iOS ───
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        // utsname.machine gives "iPhone13,2" — convert to friendly name
        final machine = ios.utsname.machine;
        _cachedModel = _formatIOS(machine, ios.name);
        return _cachedModel!;
      }

      // ─── WINDOWS ───
      if (Platform.isWindows) {
        final win = await info.windowsInfo;
        _cachedModel = '${win.productName} '
            '${win.displayVersion.isNotEmpty ? win.displayVersion : ""}'.trim();
        return _cachedModel!;
      }

      // ─── macOS ───
      if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        _cachedModel = 'Mac ${mac.model}';
        return _cachedModel!;
      }

      // ─── LINUX ───
      if (Platform.isLinux) {
        final linux = await info.linuxInfo;
        _cachedModel = linux.prettyName.isNotEmpty
            ? linux.prettyName
            : 'Linux Device';
        return _cachedModel!;
      }
    } catch (e) {
      debugPrint('⚠️ [DeviceInfo] Error: $e');
    }

    // ─── FALLBACK ───
    _cachedModel = defaultTargetPlatform.name;
    return _cachedModel!;
  }

  /// Full info: model + OS version
  Future<String> getFullDeviceInfo() async {
    try {
      final info = DeviceInfoPlugin();

      if (kIsWeb) {
        final web = await info.webBrowserInfo;
        final version = (web.appVersion ?? '').split('.').take(2).join('.');
        return '${_cap(web.browserName.name)} $version (Web)';
      }

      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final model = _formatAndroid(
          brand: a.brand,
          model: a.model,
          device: a.device,
        );
        return '$model • Android ${a.version.release}';
      }

      if (Platform.isIOS) {
        final i = await info.iosInfo;
        final model = _formatIOS(i.utsname.machine, i.name);
        return '$model • iOS ${i.systemVersion}';
      }

      if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return '${w.productName} • Windows ${w.displayVersion}';
      }

      if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        return 'Mac ${m.model} • macOS ${m.osRelease}';
      }

      if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return '${l.prettyName} • ${l.version ?? ""}'.trim();
      }
    } catch (e) {
      debugPrint('⚠️ [DeviceInfo] Full info error: $e');
    }

    return await getDeviceModel();
  }

  // ─── Helpers ───
  String _formatAndroid({
    required String brand,
    required String model,
    required String device,
  }) {
    final b = brand.trim();
    final m = model.trim();
    final d = device.trim();

    if (b.isNotEmpty && m.isNotEmpty) {
      if (m.toLowerCase().startsWith(b.toLowerCase())) {
        return _cap(m);
      }
      if (m.toLowerCase() == 'android' && d.isNotEmpty) {
        return '${_cap(b)} ${_cap(d)}';
      }
      return '${_cap(b)} $m';
    }
    if (m.isNotEmpty) return _cap(m);
    if (d.isNotEmpty) return '${_cap(b)} ${_cap(d)}'.trim();
    return 'Android Device';
  }

  String _formatIOS(String machine, String name) {
    const map = <String, String>{
      'iPhone10,1': 'iPhone 8',
      'iPhone10,4': 'iPhone 8',
      'iPhone10,2': 'iPhone 8 Plus',
      'iPhone10,5': 'iPhone 8 Plus',
      'iPhone10,3': 'iPhone X',
      'iPhone10,6': 'iPhone X',
      'iPhone11,2': 'iPhone XS',
      'iPhone11,4': 'iPhone XS Max',
      'iPhone11,6': 'iPhone XS Max',
      'iPhone11,8': 'iPhone XR',
      'iPhone12,1': 'iPhone 11',
      'iPhone12,3': 'iPhone 11 Pro',
      'iPhone12,5': 'iPhone 11 Pro Max',
      'iPhone12,8': 'iPhone SE 2',
      'iPhone13,1': 'iPhone 12 mini',
      'iPhone13,2': 'iPhone 12',
      'iPhone13,3': 'iPhone 12 Pro',
      'iPhone13,4': 'iPhone 12 Pro Max',
      'iPhone14,2': 'iPhone 13 Pro',
      'iPhone14,3': 'iPhone 13 Pro Max',
      'iPhone14,4': 'iPhone 13 mini',
      'iPhone14,5': 'iPhone 13',
      'iPhone14,6': 'iPhone SE 3',
      'iPhone14,7': 'iPhone 14',
      'iPhone14,8': 'iPhone 14 Plus',
      'iPhone15,2': 'iPhone 14 Pro',
      'iPhone15,3': 'iPhone 14 Pro Max',
      'iPhone15,4': 'iPhone 15',
      'iPhone15,5': 'iPhone 15 Plus',
      'iPhone16,1': 'iPhone 15 Pro',
      'iPhone16,2': 'iPhone 15 Pro Max',
      'iPad13,1': 'iPad Air 4',
      'iPad13,2': 'iPad Air 4',
    };

    final friendly = map[machine];
    if (friendly != null) return friendly;

    if (name.isNotEmpty && name.toLowerCase() != 'iphone') return name;
    return machine.isNotEmpty ? machine : 'iPhone';
  }

  String _cap(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  void clearCache() {
    _cachedModel = null;
  }
}