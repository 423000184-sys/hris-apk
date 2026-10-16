// lib/services/demo_mode_service.dart
// ═══════════════════════════════════════════════════════════════════
// DEMO MODE SERVICE — Session-Only (Walang DB Writes)
//   v1.3 — Fixed: enable()/disable() are void, removed await
// ═══════════════════════════════════════════════════════════════════
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employee.dart';

class DemoModeService {
  DemoModeService._();
  static final DemoModeService instance = DemoModeService._();

  static const String _prefsKey = 'demo_mode_enabled';

  bool _enabled = false;
  bool get isEnabled => _enabled;
  bool get shouldSkipDbWrite => _enabled;

  // ─────────────────────────────────────────────────────────────
  // DEMO EMPLOYEE
  // ─────────────────────────────────────────────────────────────
  static final Employee demoEmployee = Employee(
    id: 'DEMO_EMPLOYEE_001',
    employeeId: 'DEMO-001',
    firstName: 'Demo',
    lastName: 'Employee',
    email: 'demo@racpma.local',
    department: 'Demo Department',
    position: 'Demo User',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  // ─────────────────────────────────────────────────────────────
  // 🎭 DEMO PAYSLIP DATA
  // ─────────────────────────────────────────────────────────────
  double get demoPayslipAmount => 22300.0;

  Map<String, double> get demoPayslipBreakdown => const {
    'regularPay': 22000.0,
    'basicSalary': 22000.0,
    'basicHours': 176.0,
    'absentAmount': 0.0,
    'absentHours': 0.0,
    'lateAmount': -150.0,
    'lateHours': 1.5,
    'undertimeAmount': 0.0,
    'undertimeHours': 0.0,
    'dayOffOtAmount': 0.0,
    'dayOffOtHours': 0.0,
    'overtimeAmount': 2750.0,
    'overtimeHours': 10.0,
    'nightDiffAmount': 550.0,
    'nightDiffHours': 12.0,
    'holidayAmount': 600.0,
    'otherIncomeAllowance': 0.0,
    'totalAdjustmentsMade': 0.0,
    'grossPay': 25750.0,
    'netPay': 22300.0,
    'sss': 990.0,
    'philhealth': 550.0,
    'pagibig': 100.0,
    'taxableIncome': 24110.0,
    'taxWithheld': 1410.0,
    'totalLoanDeductions': 0.0,
    'totalDeductions': 3450.0,
    'sickLeaveBalance': 120.0,
    'vacationLeaveBalance': 120.0,
    'riceAllowance': 0.0,
  };

  // ─────────────────────────────────────────────────────────────
  // 🎭 DEMO LEAVE HISTORY
  // ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get demoLeaveHistory => [
    {
      'id': 'DEMO_LEAVE_001',
      'leaveType': 'VL',
      'startDate': DateTime.now()
          .subtract(const Duration(days: 40))
          .toIso8601String(),
      'endDate': DateTime.now()
          .subtract(const Duration(days: 38))
          .toIso8601String(),
      'days': 3,
      'status': 'approved',
      'reason': 'Family vacation',
      'createdAt': DateTime.now().subtract(const Duration(days: 55)),
    },
    {
      'id': 'DEMO_LEAVE_002',
      'leaveType': 'SL',
      'startDate': DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String(),
      'endDate': DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String(),
      'days': 1,
      'status': 'approved',
      'reason': 'Medical checkup',
      'createdAt': DateTime.now().subtract(const Duration(days: 12)),
    },
    {
      'id': 'DEMO_LEAVE_003',
      'leaveType': 'VL',
      'startDate': DateTime.now()
          .add(const Duration(days: 5))
          .toIso8601String(),
      'endDate': DateTime.now()
          .add(const Duration(days: 7))
          .toIso8601String(),
      'days': 3,
      'status': 'pending',
      'reason': 'Personal errands',
      'createdAt': DateTime.now().subtract(const Duration(days: 2)),
    },
    {
      'id': 'DEMO_LEAVE_004',
      'leaveType': 'SL',
      'startDate': DateTime.now()
          .subtract(const Duration(days: 90))
          .toIso8601String(),
      'endDate': DateTime.now()
          .subtract(const Duration(days: 90))
          .toIso8601String(),
      'days': 1,
      'status': 'rejected',
      'reason': 'Sick leave — insufficient notice',
      'createdAt': DateTime.now().subtract(const Duration(days: 91)),
    },
  ];

  // ─────────────────────────────────────────────────────────────
  // 🎭 DEMO ATTENDANCE HISTORY
  // ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get demoAttendanceHistory {
    final now = DateTime.now();
    return List.generate(10, (i) {
      final d = now.subtract(Duration(days: i));
      final isLate = i == 2 || i == 5;
      return {
        'id': 'DEMO_ATT_${i.toString().padLeft(3, '0')}',
        'date': d.toIso8601String().substring(0, 10),
        'timeIn': isLate ? '09:42:00' : '08:55:00',
        'timeOut': '18:05:00',
        'status': isLate ? 'late' : 'present',
        'method': 'face',
        'locationIn': 'Main Office — HQ',
        'locationOut': 'Main Office — HQ',
      };
    });
  }

  // ─────────────────────────────────────────────────────────────
  // 🎭 DEMO ACTIVITY LOGS
  // ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get demoLoginLogs {
    final now = DateTime.now();
    return List.generate(8, (i) {
      return {
        '_docId': 'DEMO_LOGIN_$i',
        'type': 'login',
        'employee_id': 'DEMO-001',
        'employee_name': 'Demo Employee',
        'device': i.isEven ? 'Chrome — Web' : 'Android — Mobile',
        'timestamp': now.subtract(Duration(days: i, hours: 2)),
      };
    });
  }

  List<Map<String, dynamic>> get demoLogoutLogs {
    final now = DateTime.now();
    return List.generate(8, (i) {
      return {
        '_docId': 'DEMO_LOGOUT_$i',
        'type': 'logout',
        'employee_id': 'DEMO-001',
        'employee_name': 'Demo Employee',
        'device': i.isEven ? 'Chrome — Web' : 'Android — Mobile',
        'timestamp': now.subtract(Duration(days: i, hours: -6)),
      };
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefsKey) ?? false;
      debugPrint('🎭 [DemoMode] load() — enabled=$_enabled');
    } catch (e) {
      debugPrint('⚠️ [DemoMode] load() failed: $e');
      _enabled = false;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, _enabled);
    } catch (e) {
      debugPrint('⚠️ [DemoMode] _persist() failed: $e');
    }
  }

  /// ✅ `void` method — hindi i-await ng caller
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _persist();
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('🎭 [DemoMode] ENABLED');
    debugPrint('   • All Firestore writes: BLOCKED');
    debugPrint('   • Biometric checks:     BYPASSED');
    debugPrint('   • Geofence checks:      BYPASSED');
    debugPrint('   • Employee:             ${demoEmployee.fullName}');
    debugPrint('═══════════════════════════════════════════════════════');
  }

  /// ✅ `void` method — hindi i-await ng caller
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _persist();
    debugPrint('🎭 [DemoMode] DISABLED');
  }

  void toggle() {
    if (_enabled) {
      disable();
    } else {
      enable();
    }
  }

  void printStatus() {
    debugPrint(
        '🎭 [DemoMode] Status: ${_enabled ? "ENABLED" : "DISABLED"}');
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎭 DEMO SESSION — prepares pre-auth keys for biometric flow
  // ═══════════════════════════════════════════════════════════════
  Future<void> prepareDemoSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final empId = demoEmployee.id;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final nonce = 'DEMO_${nowMs.toRadixString(16)}';

      await prefs.setString('fp_preauth_employee_id', empId);
      await prefs.setInt('fp_preauth_time', nowMs);
      await prefs.setString('fp_preauth_nonce', nonce);
      await prefs.setString('last_logged_in_employee_id', empId);
      await prefs.setString('last_employee_employee_id', empId);

      debugPrint('🎭 [DemoMode] prepareDemoSession — empId=$empId');
    } catch (e) {
      debugPrint('⚠️ [DemoMode] prepareDemoSession failed: $e');
    }
  }

  /// 🎭 One-shot: enable + prepare session
  /// ✅ enable() is void — walang await
  Future<void> startDemoSession() async {
    enable();
    await prepareDemoSession();
    debugPrint('🎭 [DemoMode] startDemoSession — READY');
  }

  /// 🎭 Cleanup — para sa logout
  /// ✅ disable() is void — walang await
  Future<void> endDemoSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fp_preauth_employee_id');
      await prefs.remove('fp_preauth_time');
      await prefs.remove('fp_preauth_nonce');
      await prefs.remove('last_logged_in_employee_id');
      await prefs.remove('last_employee_employee_id');
      debugPrint('🎭 [DemoMode] endDemoSession — session cleared');
    } catch (e) {
      debugPrint('⚠️ [DemoMode] endDemoSession failed: $e');
    }
    disable();
  }
}