// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_pdf_service.dart';
import '../models/employee.dart';

// Brand colors (same in both themes)
class _Mock {
  static const Color orange = Color(0xFFFF8A00);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
}

// ═══════════════════════════════════════════════════════════════════════════
// _ThemeColors — theme-aware colors for reports screen
// ═══════════════════════════════════════════════════════════════════════════
class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;

  Color get cardBg => isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFF27272A);

  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textGrayDark =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF52525B);

  // Print icon button
  Color get printButtonBg => isDark ? const Color(0xFF27272A) : Colors.white;
  Color get printButtonBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
}

class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Employee? _employee;
  bool _loading = true;
  bool _exporting = false;
  double _hourlyRate = 75.0;

  // Payroll data
  double _basicSalary = 0;
  double _housingAllowance = 0;
  double _transportAllowance = 0;
  double _specialAllowance = 0;
  double _providentFund = 0;
  double _professionalTax = 0;
  String _bankName = '—';
  String _accountNumber = '—';
  String _department = '—';
  String _designation = '—';

  static const _standardMonthlyHours = 160.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      Employee? emp = widget.initialEmployee;
      if (!kIsWeb) {
        final empId = await SecurityService.instance.getCurrentEmployeeId();
        if (empId != null) {
          emp = await DatabaseService.instance.getEmployeeById(empId);
        }
      }

      double rate = 75.0;
      Map<String, dynamic>? data;
      if (emp != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('employeeId', isEqualTo: emp.employeeId)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            data = snap.docs.first.data();
            final r =
                data['hourlyRate'] ?? data['hourly_rate'] ?? data['rate'];
            if (r != null) rate = (r as num).toDouble();
          }
        } catch (_) {}
      }

      final basic = (data?['basicSalary'] as num?)?.toDouble() ??
          rate * _standardMonthlyHours;
      final housing = (data?['housingAllowance'] as num?)?.toDouble() ??
          basic * 0.40;
      final transport = (data?['transportAllowance'] as num?)?.toDouble() ??
          basic * 0.15;
      final special = (data?['specialAllowance'] as num?)?.toDouble() ??
          basic * 0.075;
      final pf = (data?['providentFund'] as num?)?.toDouble() ?? basic * 0.0225;
      final tax =
          (data?['professionalTax'] as num?)?.toDouble() ?? basic * 0.0025;

      if (mounted) {
        setState(() {
          _employee = emp;
          _hourlyRate = rate;
          _basicSalary = basic;
          _housingAllowance = housing;
          _transportAllowance = transport;
          _specialAllowance = special;
          _providentFund = pf;
          _professionalTax = tax;
          _bankName = (data?['bankName'] as String?) ?? '—';
          _accountNumber = (data?['accountNumber'] as String?) ?? '—';
          _department = (data?['department'] as String?) ?? '—';
          _designation =
              (data?['designation'] as String?) ?? emp?.position ?? '—';
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ReportsScreen._loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePdf() async {
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) {
      _showSnack('No employee session. Please log in again.', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final savedPath = await PayrollPdfService.generate(
        context,
        employee: emp,
        month: DateTime.now(),
        basicSalary: _basicSalary,
        housingAllowance: _housingAllowance,
        transportAllowance: _transportAllowance,
        specialAllowance: _specialAllowance,
        providentFund: _providentFund,
        professionalTax: _professionalTax,
        bankName: _bankName,
        accountNumber: _accountNumber,
        department: _department,
        designation: _designation,
      );

      try {
        await FirebaseFirestore.instance.collection('pdf_exports').add({
          'employee_id': emp.employeeId,
          'employee_name': emp.fullName,
          'report_type': 'Payslip PDF',
          'month': DateFormat('yyyy-MM').format(DateTime.now()),
          'exported_at': FieldValue.serverTimestamp(),
          'platform': kIsWeb ? 'Web' : 'Mobile',
        });
      } catch (_) {}

      if (mounted) {
        _showSnack(savedPath != null
            ? 'Na-save ang payslip sa device ✓'
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
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tc = _ThemeColors(isDark);

    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    final empName =
        _employee?.fullName ?? widget.initialEmployee?.fullName ?? '—';
    final empId = _employee?.employeeId ??
        widget.initialEmployee?.employeeId ??
        '—';

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  children: [
                    _buildPayslipCard(tc, thisMonth, empName, empId),
                    const SizedBox(height: 12),
                    _buildEmployeeInfo(tc, empName, empId),
                    const SizedBox(height: 20),
                    _buildDownloadButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_ThemeColors tc, String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: const Row(
                  children: [
                    Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 22),
                    Text('Back',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
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
          const SizedBox(height: 20),
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
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipCard(
      _ThemeColors tc, String thisMonth, String empName, String empId) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('R.A.C.O.M.A',
                      style: TextStyle(
                          color: _Mock.orange,
                          fontSize: 20,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text('Smart HR Information System',
                      style: TextStyle(
                          color: tc.textPrimary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Jumbo HQ, Manila, Philippines',
                      style: TextStyle(
                          color: tc.textGrayDark, fontSize: 10)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _Mock.paidBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Mock.paidBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle_rounded,
                          color: _Mock.lime, size: 14),
                      SizedBox(width: 6),
                      Text('Paid',
                          style: TextStyle(
                              color: _Mock.lime,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Payslip for\n$thisMonth',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: tc.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeInfo(
      _ThemeColors tc, String empName, String empId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Employee',
                    style: TextStyle(
                        color: tc.textGrayDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(empName,
                    style: TextStyle(
                        color: tc.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Employee ID',
                    style: TextStyle(
                        color: tc.textGrayDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(empId,
                    style: TextStyle(
                        color: tc.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton() {
    return GestureDetector(
      onTap: _exporting ? null : _generatePdf,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: AppColors.gradientOrange,
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
                  color: Colors.white, strokeWidth: 2.5))
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
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}