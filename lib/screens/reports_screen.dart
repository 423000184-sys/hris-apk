// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_calculator.dart';
import '../services/payroll_pdf_service.dart';
import '../models/employee.dart';

// ══════════════════════════════════════════════════════════════
// 💰 SALARY CONFIG
// ══════════════════════════════════════════════════════════════
const int kWorkingDaysPerMonth = 22;

class _Mock {
  static const Color orange = Color(0xFFFF8A00);
  static const Color orangeMid = Color(0xFFFA6A00);
  static const Color orangeDark = Color(0xFFF54900);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : Colors.white;
  Color get cardBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textGrayDark =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF52525B);
  Color get printButtonBg =>
      isDark ? const Color(0xFF27272A) : Colors.white;
  Color get printButtonBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF3F3F46);
}

class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Employee? _employee;
  Map<String, dynamic>? _rawData;
  PayrollBreakdown _breakdown = PayrollBreakdown.empty;
  bool _loading = true;
  bool _exporting = false;

  String _bankName = '—';
  String _accountNumber = '—';
  String _department = '—';
  String _designation = '—';

  double _basicSalary = 0;
  double _allowances = 0;
  double _dailyRate = 0;
  int _workingDaysPerMonth = kWorkingDaysPerMonth;
  String _salarySource = 'manual';
  String _role = '';

  String _displayName = '—';
  String _displayEmpId = '—';

  DateTime get _periodStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, 1);
  }

  DateTime get _periodEnd {
    final n = DateTime.now();
    return DateTime(n.year, n.month + 1, 0, 23, 59, 59);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _num(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _int(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  // ══════════════════════════════════════════════════════════════
  // 🔍 FETCH
  // ══════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> _fetchByRawId(String rawId) async {
    final fs = FirebaseFirestore.instance;
    debugPrint('🔍 [_fetchByRawId] rawId = "$rawId"');

    try {
      final doc = await fs.collection('employees').doc(rawId).get();
      if (doc.exists) {
        debugPrint('✅ [raw-1] FOUND via doc(rawId)');
        return doc.data();
      }
    } catch (e) {
      debugPrint('⚠️ [raw-1] failed: $e');
    }

    try {
      final snap = await fs
          .collection('employees')
          .where('employeeId', isEqualTo: rawId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        debugPrint('✅ [raw-2] FOUND via query(employeeId)');
        return snap.docs.first.data();
      }
    } catch (e) {
      debugPrint('⚠️ [raw-2] failed: $e');
    }

    try {
      final snap = await fs
          .collection('employees')
          .where('id', isEqualTo: rawId)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        debugPrint('✅ [raw-3] FOUND via query(id)');
        return snap.docs.first.data();
      }
    } catch (e) {
      debugPrint('⚠️ [raw-3] failed: $e');
    }

    try {
      final all = await fs.collection('employees').limit(50).get();
      final target = rawId.toLowerCase().trim();
      for (final d in all.docs) {
        final data = d.data();
        final docId = d.id.toLowerCase().trim();
        final empIdField =
        (data['employeeId'] ?? '').toString().toLowerCase().trim();
        if (docId == target || empIdField == target) {
          debugPrint('✅ [raw-4] FOUND case-insensitive');
          return data;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [raw-4] failed: $e');
    }

    return null;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      String? rawEmpId;
      if (!kIsWeb) {
        rawEmpId = await SecurityService.instance.getCurrentEmployeeId();
      }

      Employee? emp = widget.initialEmployee;
      if (emp == null && rawEmpId != null && rawEmpId.isNotEmpty) {
        try {
          emp = await DatabaseService.instance.getEmployeeById(rawEmpId);
        } catch (_) {}
      }

      Map<String, dynamic>? data;
      if (rawEmpId != null && rawEmpId.isNotEmpty) {
        data = await _fetchByRawId(rawEmpId);
      }
      if (data == null && emp != null) {
        for (final id in <String>{emp.employeeId, emp.id}) {
          if (id.isEmpty) continue;
          data = await _fetchByRawId(id);
          if (data != null) break;
        }
      }
      if (data == null) {
        final authUser = FirebaseAuth.instance.currentUser;
        if (authUser != null && authUser.email != null) {
          try {
            final all = await FirebaseFirestore.instance
                .collection('employees')
                .limit(50)
                .get();
            final targetEmail = authUser.email!.toLowerCase().trim();
            for (final d in all.docs) {
              final dd = d.data();
              final docEmail =
              (dd['email'] ?? '').toString().toLowerCase().trim();
              if (docEmail == targetEmail) {
                data = dd;
                break;
              }
            }
          } catch (_) {}
        }
      }

      PayrollBreakdown b = PayrollBreakdown.empty;
      if (data != null) {
        final empData = {
          ...data,
          if (emp != null && emp.id.isNotEmpty) 'id': emp.id,
          if (rawEmpId != null) 'employeeId': rawEmpId,
        };
        b = await PayrollCalculator.compute(
          employee: empData,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        );
      }

      final basicFromData = _num(data?['basicSalary']);
      final basicAllow = _num(data?['basicAllowance'] ?? data?['allowances']);
      final housingAllow = _num(data?['housingAllowance']);
      final transportAllow = _num(data?['transportAllowance']);
      final specialAllow = _num(data?['specialAllowance']);
      final allowancesFromData =
          basicAllow + housingAllow + transportAllow + specialAllow;

      final dailyFromData = _num(data?['dailyRate']);
      final workingDays = _int(data?['workingDaysPerMonth'], 22);
      final salarySource = (data?['salarySource'] as String?) ?? 'manual';
      final roleFromData = (data?['role'] as String?) ?? '';

      final effectiveDaily = dailyFromData > 0
          ? dailyFromData
          : (basicFromData > 0 && workingDays > 0
          ? basicFromData / workingDays
          : 0.0);

      final displayName = emp?.fullName ??
          (data?['name'] as String?) ??
          '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();

      final displayId = emp?.employeeId ??
          rawEmpId ??
          (data?['employeeId'] as String?) ??
          '—';

      if (!mounted) return;
      setState(() {
        _employee = emp;
        _rawData = data;
        _breakdown = b;
        _bankName = (data?['bankName'] as String?) ?? '—';
        _accountNumber = (data?['accountNumber'] as String?) ?? '—';
        _department = (data?['department'] as String?) ?? '—';
        _designation = (data?['designation'] as String?) ??
            (data?['role'] as String?) ??
            emp?.position ??
            '—';

        _basicSalary = basicFromData > 0
            ? basicFromData
            : (b.basicSalary > 0 ? b.basicSalary : 0);
        _allowances = allowancesFromData > 0
            ? allowancesFromData
            : (b.allowances > 0 ? b.allowances : 0);
        _dailyRate = effectiveDaily > 0
            ? effectiveDaily
            : (b.dailyRate > 0 ? b.dailyRate : 0);
        _workingDaysPerMonth = workingDays > 0 ? workingDays : 22;
        _salarySource = salarySource;
        _role = roleFromData;

        _displayName = displayName.isNotEmpty ? displayName : '—';
        _displayEmpId = displayId.isNotEmpty ? displayId : '—';

        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('❌ _loadData ERROR: $e');
      debugPrint('$stack');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 📄 GENERATE PDF
  // ══════════════════════════════════════════════════════════════
  Future<void> _generatePdf() async {
    final emp = _employee ?? widget.initialEmployee;

    Employee effectiveEmp;
    if (emp != null) {
      effectiveEmp = emp;
    } else if (_rawData != null) {
      final now = DateTime.now();
      effectiveEmp = Employee(
        id: (_rawData!['id'] ?? _displayEmpId).toString(),
        employeeId: (_rawData!['employeeId'] ?? _displayEmpId).toString(),
        firstName: (_rawData!['firstName'] ?? '').toString(),
        lastName: (_rawData!['lastName'] ?? '').toString(),
        email: (_rawData!['email'] ?? '').toString(),
        department: _department,
        position: _designation,
        createdAt: now,
        updatedAt: now,
      );
    } else {
      _showSnack('No employee data.', error: true);
      return;
    }

    if (_basicSalary <= 0 && _breakdown.basicSalary <= 0) {
      _showSnack('No salary configured. Please contact HR.', error: true);
      return;
    }

    setState(() => _exporting = true);
    try {
      final basicToUse =
      _basicSalary > 0 ? _basicSalary : _breakdown.basicSalary;
      final allowancesToUse =
      _allowances > 0 ? _allowances : _breakdown.allowances;
      final dailyToUse = _dailyRate > 0
          ? _dailyRate
          : (basicToUse /
          (_workingDaysPerMonth > 0 ? _workingDaysPerMonth : 22));

      final savedPath = await PayrollPdfService.generate(
        context,
        employee: effectiveEmp,
        month: DateTime.now(),
        basicSalary: basicToUse,
        allowances: allowancesToUse,
        dailyRate: dailyToUse,
        workingDaysPerMonth: _workingDaysPerMonth,
        salarySource: _salarySource,
        sss: _breakdown.sss,
        philhealth: _breakdown.philhealth,
        pagibig: _breakdown.pagibig,
        absenceDeduction: _breakdown.absenceDeduction,
        absentDays: _breakdown.absentDays,
        workingDays: _breakdown.workingDays,
        presentDays: _breakdown.presentDays,
        workRawMinutes: _breakdown.workRawMinutes,
        workLunchMinutes: _breakdown.workLunchMinutes,
        workNetMinutes: _breakdown.workNetMinutes,
        workOvertimeMinutes: _breakdown.workOvertimeMinutes,
        daysWithLogs: _breakdown.daysWithLogs,
        daysWithLunchApplied: _breakdown.daysWithLunchApplied,
        overtimePay: _breakdown.overtimePay,
        grossPay: _breakdown.grossPay,
        thirteenthMonth: _breakdown.thirteenthMonth,
        silCredits: _breakdown.silCredits,
        bankName: _bankName,
        accountNumber: _accountNumber,
        department: _department,
        designation: _designation,
      );

      try {
        await FirebaseFirestore.instance.collection('pdf_exports').add({
          'employee_id': effectiveEmp.employeeId,
          'employee_name': effectiveEmp.fullName,
          'report_type': 'Payslip PDF',
          'month': DateFormat('yyyy-MM').format(DateTime.now()),
          'net_pay': _breakdown.netPay,
          'basic_salary': basicToUse,
          'allowances': allowancesToUse,
          'daily_rate': dailyToUse,
          'salary_source': _salarySource,
          'absent_days': _breakdown.absentDays,
          'exported_at': FieldValue.serverTimestamp(),
          'platform': kIsWeb ? 'Web' : 'Mobile',
        });
      } catch (_) {}

      if (mounted) {
        _showSnack(savedPath != null
            ? 'Payslip saved to device ✓'
            : 'PDF payslip generated ✓');
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
      error ? const Color(0xFFFF4D6D) : const Color(0xFF00E5A0),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // 🎨 BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: tc.bg,
      body: SafeArea(
        child: _loading
            ? const Center(
            child: CircularProgressIndicator(
                color: _Mock.orange, strokeWidth: 2.5))
            : Column(
          children: [
            _buildHeader(tc, thisMonth),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: _Mock.orange,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                  const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPayslipCard(tc, thisMonth),
                      const SizedBox(height: 20),
                      _buildDownloadButton(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 🎨 HEADER
  // ══════════════════════════════════════════════════════════════
  Widget _buildHeader(_ThemeColors tc, String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF8A00),
            Color(0xFFFA6A00),
            Color(0xFFF54900),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                behavior: HitTestBehavior.opaque,
                child: const Row(
                  children: [
                    Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 2),
                    Text(
                      'Back',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _exporting ? null : _generatePdf,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tc.printButtonBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tc.printButtonBorder),
                  ),
                  child: _exporting
                      ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                        color: _Mock.orange, strokeWidth: 2),
                  )
                      : const Icon(Icons.print_rounded,
                      color: _Mock.orange, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'Payslip Details',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Salary slip for $thisMonth',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 💳 PAYSLIP CARD (Company + Paid Badge + Month)
  // ══════════════════════════════════════════════════════════════
  Widget _buildPayslipCard(_ThemeColors tc, String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Company Info (left) ────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'R.A.C.O.M.A',
                  style: TextStyle(
                    color: _Mock.orange,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Smart HR Information System',
                  style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Jumbo HQ, Manila, Philippines',
                  style: TextStyle(
                    color: tc.textGrayDark,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ─── Paid badge + month (right) ─────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _Mock.paidBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Mock.paidBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: _Mock.lime, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Paid',
                      style: TextStyle(
                        color: _Mock.lime,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Payslip for\n$thisMonth',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: tc.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ⬇️ DOWNLOAD BUTTON
  // ══════════════════════════════════════════════════════════════
  Widget _buildDownloadButton() {
    return GestureDetector(
      onTap: _exporting ? null : _generatePdf,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF8A00),
              Color(0xFFFA6A00),
              Color(0xFFF54900),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _exporting
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5),
          )
              : const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded,
                  color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Download as PDF / Print',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}