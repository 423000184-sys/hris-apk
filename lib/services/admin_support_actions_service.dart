// lib/services/admin_support_actions_service.dart
// ═══════════════════════════════════════════════════════════════════
// ADMIN SUPPORT ACTIONS SERVICE  v2.0
// Updates:
//   - DETERMINISTIC PASSWORD: same algorithm as employee app.
//   - No versioning, no Firestore password storage.
//   - All user-facing text in English.
// ═══════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AdminSupportActionsService {
  AdminSupportActionsService._();
  static final instance = AdminSupportActionsService._();

  static const String _notifsCol = 'admin_notifications';
  static const String _employeesCol = 'employees';
  static const String _secretSalt = 'RACOMA-HRIS-2026-PDF-SALT';

  // ═══════════════════════════════════════════════════════════════
  // 🔑 DETERMINISTIC PASSWORD — SAME AS EMPLOYEE SIDE
  // ═══════════════════════════════════════════════════════════════

  /// Computes the same password the employee app uses.
  /// Deterministic: same employeeId → same password FOREVER.
  String computePassword(String employeeId) {
    final id = employeeId.trim();
    if (id.isEmpty) return '';
    final material = '$_secretSalt::$id';
    final hash = sha256.convert(utf8.encode(material)).toString();
    final raw = hash.substring(0, 8).toUpperCase();
    return raw
        .replaceAll('0', 'X')
        .replaceAll('O', 'Y')
        .replaceAll('I', 'Z');
  }

  /// Fetch password for support reply.
  Future<String?> getOrCreatePassword(String employeeId) async {
    final pwd = computePassword(employeeId);
    return pwd.isEmpty ? null : pwd;
  }

  Future<String?> getCurrentPassword(String employeeId) async {
    final pwd = computePassword(employeeId);
    return pwd.isEmpty ? null : pwd;
  }

  /// Kept for compatibility — returns same deterministic password.
  Future<String?> generateNewPassword(String employeeId) async {
    return computePassword(employeeId);
  }

  // ═══════════════════════════════════════════════════════════════
  // 📋 CANNED REPLIES — ENGLISH
  // ═══════════════════════════════════════════════════════════════
  String cannedReplyFor(String categoryKey) {
    switch (categoryKey) {
      case 'pdf_download':
        return 'Hi! To fix the PDF download issue, please try the following:\n\n'
            '1. Check that you have a stable internet connection (Wi-Fi or data).\n'
            '2. Open Settings > Apps > RACOMA > Permissions > Storage, and allow everything.\n'
            '3. Close and reopen the app.\n'
            '4. Try downloading the payslip again.\n\n'
            'If it still does not work, reply here and we will help you.';

      case 'pdf_password':
        return 'Hi! Here is your PDF password below. Copy it and use it to open your payslip. '
            'This password is the SAME for all your payslips and never changes.';

      case 'salary_question':
        return 'Hi! We received your question about your salary. '
            'We are reviewing your payslip details.';

      case 'app_issue':
        return 'Hi! To fix the app issue, please try the following:\n\n'
            '1. Force close the app (swipe up on recent apps).\n'
            '2. Reopen it.\n'
            '3. If it still hangs, restart your phone.\n'
            '4. Make sure the app is updated to the latest version.\n\n'
            'If you see an error message, please send a screenshot and reply here.';

      case 'other':
      default:
        return 'Hi! We received your concern. We are reviewing it and will reply soon.';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 💰 SALARY BREAKDOWN — AUTO-FILLED
  // ═══════════════════════════════════════════════════════════════
  Future<String?> buildSalaryBreakdownText({
    required String employeeId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    if (employeeId.trim().isEmpty) {
      debugPrint('⚠️ [AdminSupport] buildSalaryBreakdown: empty employeeId');
      return null;
    }

    try {
      final data = await _fetchEmployeeData(employeeId.trim());
      if (data == null) {
        debugPrint('⚠️ [AdminSupport] Employee not found: $employeeId');
        return null;
      }

      final basic = _toDbl(data['basicSalary']);
      final basicAllow =
      _toDbl(data['basicAllowance'] ?? data['allowances']);
      final housingAllow = _toDbl(data['housingAllowance']);
      final transportAllow = _toDbl(data['transportAllowance']);
      final specialAllow = _toDbl(data['specialAllowance']);
      final riceAllow = _toDbl(data['riceAllowance']);
      final overtime = _toDbl(data['overtimePay']);
      final allowances =
          basicAllow + housingAllow + transportAllow + specialAllow;

      const sssRate = 0.045;
      const phRate = 0.025;
      const pagibigRate = 0.020;
      final sss = basic * sssRate;
      final philhealth = basic * phRate;
      final pagibig = basic * pagibigRate;

      final workingDays = _toInt(data['workingDaysPerMonth'], 22);
      final savedDaily = _toDbl(data['dailyRate']);
      final dailyRate = savedDaily > 0
          ? savedDaily
          : (basic > 0 && workingDays > 0 ? basic / workingDays : 0.0);
      final absentDays = _toInt(data['absentDays'], 0);
      final absentAmount = dailyRate * absentDays;

      final gross = basic + allowances + overtime;
      final totalDed = sss + philhealth + pagibig + absentAmount;
      final net = gross - totalDed;

      final periodLabel = _formatPeriod(periodStart, periodEnd);
      final name = (data['name'] ??
          '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
          .toString()
          .trim();

      final buf = StringBuffer();
      buf.writeln('Hi ${name.isEmpty ? "there" : name.split(" ").first}! '
          'Here is the breakdown of your payslip${periodLabel.isNotEmpty ? " $periodLabel" : ""}:');
      buf.writeln();
      buf.writeln('💰 EARNINGS');
      buf.writeln('  • Basic Pay:        ₱${_peso(basic)}');
      if (allowances > 0)
        buf.writeln('  • Allowances:       ₱${_peso(allowances)}');
      if (overtime > 0)
        buf.writeln('  • Overtime:         ₱${_peso(overtime)}');
      if (riceAllow > 0)
        buf.writeln('  • Rice Allowance:   ₱${_peso(riceAllow)}');
      buf.writeln('  ────────────────────────────');
      buf.writeln('  Gross Pay:          ₱${_peso(gross)}');
      buf.writeln();
      buf.writeln('📉 DEDUCTIONS');
      buf.writeln('  • SSS:             -₱${_peso(sss)}');
      buf.writeln('  • PhilHealth:      -₱${_peso(philhealth)}');
      buf.writeln('  • Pag-IBIG:        -₱${_peso(pagibig)}');
      if (absentAmount > 0)
        buf.writeln('  • Absences ($absentDays day${absentDays == 1 ? "" : "s"}): -₱${_peso(absentAmount)}');
      buf.writeln('  ────────────────────────────');
      buf.writeln('  Total Deductions:  -₱${_peso(totalDed)}');
      buf.writeln();
      buf.writeln('✅ NET PAY:            ₱${_peso(net)}');
      buf.writeln();
      buf.writeln('If you have further questions, just reply here.');

      return buf.toString();
    } catch (e) {
      debugPrint('❌ [AdminSupport] buildSalaryBreakdown failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchEmployeeData(String rawId) async {
    final fs = FirebaseFirestore.instance;
    try {
      final doc = await fs
          .collection(_employeesCol)
          .doc(rawId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (doc.exists) return doc.data();
    } catch (e) {
      debugPrint('⚠️ [AdminSupport] fetch by doc id: $e');
    }

    try {
      final snap = await fs
          .collection(_employeesCol)
          .where('employeeId', isEqualTo: rawId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (e) {
      debugPrint('⚠️ [AdminSupport] fetch by employeeId: $e');
    }

    try {
      final snap = await fs
          .collection(_employeesCol)
          .where('id', isEqualTo: rawId)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snap.docs.isNotEmpty) return snap.docs.first.data();
    } catch (e) {
      debugPrint('⚠️ [AdminSupport] fetch by id: $e');
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔄 FORCE RESYNC
  // ═══════════════════════════════════════════════════════════════
  Future<bool> flagForceRefresh({
    required String requestId,
    String flag = 'force_refresh_payslip',
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance
          .collection(_notifsCol)
          .doc(requestId)
          .update(<String, dynamic>{
        'metadata.adminAction': flag,
        'metadata.adminActionAt': FieldValue.serverTimestamp(),
        'metadata.adminActionBy': uid,
      }).timeout(const Duration(seconds: 10));
      debugPrint('✅ [AdminSupport] Flagged: $flag');
      return true;
    } catch (e) {
      debugPrint('❌ [AdminSupport] flagForceRefresh: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 📝 AUDIT HELPER
  // ═══════════════════════════════════════════════════════════════
  Future<void> logAdminAction({
    required String requestId,
    required String action,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('admin_audit_logs')
          .add(<String, dynamic>{
        'action': action,
        'details': 'Support request: $requestId',
        'adminUid': user?.uid ?? '',
        'stage': 'support_actions',
        'platform': kIsWeb ? 'web' : 'mobile',
        'metadata': meta ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ [AdminSupport] audit failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  static double _toDbl(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static String _peso(double v) {
    final f = NumberFormat('#,##0.00', 'en_PH');
    return f.format(v);
  }

  static String _formatPeriod(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    final fmt = DateFormat('MMM d, yyyy');
    return '(${fmt.format(start)} – ${fmt.format(end)})';
  }
}