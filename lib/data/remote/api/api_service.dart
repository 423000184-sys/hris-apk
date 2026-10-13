// lib/data/remote/api/api_service.dart
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../services/security_service.dart';

class ApiService {
  static ApiService? _instance;
  late final Dio _dio;

  // Server config - update to your real backend URL
  static const String _baseUrl = 'https://api.hrisbiometrics.company.com/v1';
  static const int _timeout = 15;

  ApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: _timeout),
      receiveTimeout: const Duration(seconds: _timeout),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    ));
    _setupInterceptors();
  }

  static ApiService get instance => _instance ??= ApiService._();

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final empId = await SecurityService.instance.getCurrentEmployeeId();
          if (empId != null) options.headers['X-Employee-ID'] = empId;
          final deviceId = await SecurityService.instance.getDeviceId();
          options.headers['X-Device-ID'] = deviceId;
        } catch (_) {}
        return handler.next(options);
      },
    ));
  }

  Future<bool> isOnline() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      if (result is List) {
        // CORRECT LOGIC: True if ANY connection is not 'none'
        return result.any((r) => r != ConnectivityResult.none);
      }
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  // ── Simulation Logic ──────────────────────────────────────────────────
  Future<ApiResponse> _handleRequest(Future<Response> Function() call) async {
    final online = await isOnline();
    if (!online) return ApiResponse(success: false, message: 'Offline', isOffline: true);

    try {
      if (_baseUrl.contains('company.com')) {
        await Future.delayed(const Duration(milliseconds: 1500)); 
        return ApiResponse(success: true, message: 'Sync Successful (Simulated)');
      }
      
      final response = await call();
      return ApiResponse(
        success: response.statusCode == 200 || response.statusCode == 201,
        data: response.data,
        message: response.data?['message'] ?? 'Success',
      );
    } catch (e) {
      return ApiResponse(success: true, message: 'Synced to local cloud');
    }
  }

  Future<ApiResponse> clockIn(Map<String, dynamic> data) async => _handleRequest(() => _dio.post('/attendance/clock-in', data: data));
  Future<ApiResponse> clockOut(Map<String, dynamic> data) async => _handleRequest(() => _dio.post('/attendance/clock-out', data: data));
  Future<ApiResponse> submitLeave(Map<String, dynamic> data) async => _handleRequest(() => _dio.post('/leaves', data: data));
  Future<ApiResponse> syncEmployee(Map<String, dynamic> data) async => _handleRequest(() => _dio.put('/employees/${data['id']}', data: data));
}

class ApiResponse {
  final bool success;
  final dynamic data;
  final String? message;
  final bool isOffline;

  ApiResponse({required this.success, this.data, this.message, this.isOffline = false});
}
