// lib/services/api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'security_service.dart';

class ApiService {
  static ApiService? _instance;
  late final Dio _dio;
  
  // I-update ito sa iyong actual server URL (Localhost IP kung testing)
  static const String _baseUrl = kIsWeb ? 'http://localhost/hris_biometrics/api' : 'http://10.0.2.2/hris_biometrics/api';

  ApiService._() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
  }

  static ApiService get instance => _instance ??= ApiService._();

  // ============ CORE API METHODS ============

  Future<ApiResponse> login(String employeeId, String password) async {
    return _safeCall(() => _dio.post('/login.php', data: {
      'employee_id': employeeId,
      'password': password,
    }));
  }

  Future<ApiResponse> getProfile(String employeeId) async {
    return _safeCall(() => _dio.get('/get_profile.php', queryParameters: {'id': employeeId}));
  }

  Future<ApiResponse> clockIn(Map<String, dynamic> data) async {
    return _safeCall(() => _dio.post('/clock_in.php', data: data));
  }

  Future<ApiResponse> clockOut(Map<String, dynamic> data) async {
    return _safeCall(() => _dio.post('/clock_out.php', data: data));
  }

  Future<ApiResponse> getAttendanceHistory(String employeeId) async {
    return _safeCall(() => _dio.get('/history.php', queryParameters: {'id': employeeId}));
  }

  // ============ HELPER ============
  Future<ApiResponse> _safeCall(Future<Response> Function() call) async {
    try {
      final response = await call();
      return ApiResponse(
        success: response.data['success'] ?? false,
        data: response.data['data'],
        message: response.data['message'],
      );
    } catch (e) {
      return ApiResponse(success: false, message: 'Connection Error: $e');
    }
  }
}

class ApiResponse {
  final bool success;
  final dynamic data;
  final String? message;
  ApiResponse({required this.success, this.data, this.message});
}
