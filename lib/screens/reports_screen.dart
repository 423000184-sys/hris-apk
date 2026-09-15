// lib/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_calculator.dart';
import '../services/payroll_pdf_service.dart';
import '../models/employee.dart';

class _Mock {
  static const Color orange = Color(0xFFFF8A00);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
}

class _ThemeColors {
  final bool isDark;
  const _ThemeColors(this.isDark);

  Color get bg => isDark ? const Color(0xFF0F0F10) : Colors.white;
  Color get cardBg =>
      isDark ? const Color(0xFF18181B) : const Color(0xFFF8F8F8);
  Color get cardBorder =>
      isDark ? const Color(0xFF27272A) : const Color(0xFF27272A);
  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textGrayDark =>
      isDark ? const Color(0xFFB0B0B0) : const Color(0xFF52525B);
  Color get printButtonBg =>
      isDark ? const Color(0xFF27272A) : Colors.white;
  Color get printButtonBorder =>
      isDark ? const Color(0xFF3F3F46) : const Color(0xFF27272A);
  Color get pillGreenBg =>
      isDark ? const Color(0x1AC4FF0A) : const Color(0x1A16A34A);
  Color get pillGreenTx =>
      isDark ? const Color(0xFFC4FF0A) : const Color(0xFF16A34A);
  Color get pillRedBg =>
      isDark ? const Color(0x1AFF4D6D) : const Color(0x1ADC2626);
  Color get pillRedTx =>
      isDark ? const Color(0xFFFF4D6D) : const Color(0xFFDC2626);
  Color get pillWarnBg =>
      isDark ? const Color(0x1AFFA500) : const Color(0x1AD97706);
  Color get pillWarnTx =>
      isDark ? const Color(0xFFFFA500) : const Color(0xFFD97706);
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

      Map<String, dynamic>? data;
      if (emp != null) {
        try {
          QuerySnapshot? snap;
          if (emp.employeeId.isNotEmpty) {
            snap = await FirebaseFirestore.instance
                .collection('employees')
                .where('employeeId', isEqualTo: emp.employeeId)
                .limit(1)
                .get();
          }
          if ((snap == null || snap.docs.isEmpty) && emp.id.isNotEmpty) {
            final doc = await FirebaseFirestore.instance
                .collection('employees')
                .doc(emp.id)
                .get();
            if (doc.exists) {
              data = doc.data();
            }
          } else if (snap != null && snap.docs.isNotEmpty) {
            data = snap.docs.first.data() as Map<String, dynamic>?;
          }
        } catch (e) {
          debugPrint('⚠️ ReportsScreen fetch: $e');
        }
      }

      PayrollBreakdown b = PayrollBreakdown.empty;
      if (data != null) {
        final empData = {
          ...data,
          if (emp != null && emp.id.isNotEmpty) 'id': emp.id,
        };
        b = await PayrollCalculator.compute(
          employee: empData,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        );
      }

      if (!mounted) return;
      setState(() {
        _employee = emp;
        _rawData = data;
        _breakdown = b;
        _bankName = (data?['bankName'] as String?) ?? '—';
        _accountNumber = (data?['accountNumber'] as String?) ?? '—';
        _department = (data?['department'] as String?) ?? '—';
        _designation = (data?['designation'] as String?) ??
            emp?.position ??
            '—';
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ ReportsScreen._loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generatePdf() async {
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) {
      _showSnack('No employee session. Please log in again.', error: true);
      return;
    }
    if (_breakdown.basicSalary <= 0) {
      _showSnack('No salary configured. Please contact HR.', error: true);
      return;
    }

    setState(() => _exporting = true);
    try {
      final savedPath = await PayrollPdfService.generate(
        context,
        employee: emp,
        month: DateTime.now(),
        basicSalary: _breakdown.basicSalary,
        sss: _breakdown.sss,
        philhealth: _breakdown.philhealth,
        pagibig: _breakdown.pagibig,
        absenceDeduction: _breakdown.absenceDeduction,
        absentDays: _breakdown.absentDays,
        thirteenthMonth: _breakdown.thirteenthMonth,
        silCredits: _breakdown.silCredits,
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
          'net_pay': _breakdown.netPay,
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
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: _Mock.orange,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: Column(
                    children: [
                      _buildPayslipCard(tc, thisMonth),
                      const SizedBox(height: 12),
                      _buildEmployeeInfo(tc, empName, empId),
                      const SizedBox(height: 16),
                      _buildAttendanceCard(tc),
                      const SizedBox(height: 16),
                      _buildSalaryBreakdown(tc),
                      const SizedBox(height: 16),
                      _buildGovernmentCard(tc),
                      const SizedBox(height: 16),
                      _buildNetPayCard(tc),
                      const SizedBox(height: 16),
                      _buildBenefitsCard(tc),
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
                      style: TextStyle(color: tc.textPrimary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text('Jumbo HQ, Manila, Philippines',
                      style: TextStyle(color: tc.textGrayDark, fontSize: 10)),
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
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
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
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(_ThemeColors tc) {
    final b = _breakdown;
    final isPerfect = b.absentDays == 0;

    return _panel(
      tc: tc,
      title: 'Attendance',
      icon: Icons.calendar_today_rounded,
      badge: isPerfect ? 'Perfect' : '${b.absentDays} absence(s)',
      badgeColor: isPerfect ? tc.pillGreenBg : tc.pillRedBg,
      badgeText: isPerfect ? tc.pillGreenTx : tc.pillRedTx,
      children: [
        _row(tc, 'Working Days', '${b.workingDays}', false),
        const SizedBox(height: 8),
        _row(tc, 'Present Days', '${b.presentDays}', false),
        const SizedBox(height: 8),
        _row(tc, 'Absent Days', '${b.absentDays}', b.absentDays > 0),
        const SizedBox(height: 8),
        _row(tc, 'Daily Rate',
            PayrollCalculator.peso(b.dailyRate), false),
        const SizedBox(height: 12),
        Divider(color: tc.cardBorder, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Absence Deduction',
                style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            Text('-${PayrollCalculator.peso(b.absenceDeduction)}',
                style: TextStyle(
                    color: b.absentDays > 0
                        ? const Color(0xFFFF4D6D)
                        : tc.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPerfect ? tc.pillGreenBg : tc.pillRedBg,
            border: Border(
                left: BorderSide(
                    color: isPerfect ? tc.pillGreenTx : tc.pillRedTx,
                    width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            isPerfect
                ? '✓ No absences this period. Full salary will be received.'
                : '⚠️ ${b.absentDays} absent day(s) automatically deducted from salary based on your attendance logs.',
            style: TextStyle(
                fontSize: 11,
                color: isPerfect ? tc.pillGreenTx : tc.pillRedTx,
                height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildSalaryBreakdown(_ThemeColors tc) {
    final b = _breakdown;
    return _panel(
      tc: tc,
      title: 'Earnings Breakdown',
      icon: Icons.trending_up_rounded,
      badge: PayrollCalculator.peso(b.grossPay),
      badgeColor: _Mock.orange.withValues(alpha: 0.15),
      badgeText: _Mock.orange,
      children: [
        _row(tc, 'Basic Salary', PayrollCalculator.peso(b.basicSalary), false),
        const SizedBox(height: 8),
        _row(tc, 'Allowances', PayrollCalculator.peso(b.allowances), false),
        const SizedBox(height: 8),
        _row(tc, 'Overtime Pay', PayrollCalculator.peso(b.overtimePay), false),
        const SizedBox(height: 12),
        Divider(color: tc.cardBorder, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Gross',
                style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text(PayrollCalculator.peso(b.grossPay),
                style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _buildGovernmentCard(_ThemeColors tc) {
    final b = _breakdown;
    final govtTotal = b.sss + b.philhealth + b.pagibig + b.withholdingTax;

    return _panel(
      tc: tc,
      title: 'Government Remittances',
      icon: Icons.account_balance_rounded,
      badge: '-${PayrollCalculator.peso(govtTotal)}',
      badgeColor: tc.pillRedBg,
      badgeText: tc.pillRedTx,
      children: [
        _row(tc, 'SSS Contribution', '-${PayrollCalculator.peso(b.sss)}', true),
        const SizedBox(height: 8),
        _row(tc, 'PhilHealth Contribution',
            '-${PayrollCalculator.peso(b.philhealth)}', true),
        const SizedBox(height: 8),
        _row(tc, 'Pag-IBIG Contribution',
            '-${PayrollCalculator.peso(b.pagibig)}', true),
        const SizedBox(height: 8),
        _row(tc, 'Withholding Tax',
            '-${PayrollCalculator.peso(b.withholdingTax)}', true),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillWarnBg,
            border: Border(
                left: BorderSide(color: tc.pillWarnTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'ℹ️ Total statutory deductions = 9% of basic salary (${PayrollCalculator.peso(b.basicSalary)}).',
            style: TextStyle(
                fontSize: 11, color: tc.pillWarnTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildNetPayCard(_ThemeColors tc) {
    final b = _breakdown;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.gradientOrange,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _Mock.orange.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NET PAY',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Text(PayrollCalculator.peso(b.netPay),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Basic ${PayrollCalculator.peso(b.basicSalary)} − Deductions ${PayrollCalculator.peso(b.totalDeductions)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBenefitsCard(_ThemeColors tc) {
    final b = _breakdown;
    return _panel(
      tc: tc,
      title: 'Benefits (Accrued)',
      icon: Icons.card_giftcard_rounded,
      badge: PayrollCalculator.peso(b.totalBenefits),
      badgeColor: tc.pillGreenBg,
      badgeText: tc.pillGreenTx,
      children: [
        _row(tc, '13th Month Pay',
            PayrollCalculator.peso(b.thirteenthMonth), false),
        const SizedBox(height: 8),
        _row(tc, 'SIL Credits (5 days)',
            PayrollCalculator.peso(b.silCredits), false),
        const SizedBox(height: 12),
        Divider(color: tc.cardBorder, height: 1),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total Benefits',
                style: TextStyle(
                    color: tc.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text(PayrollCalculator.peso(b.totalBenefits),
                style: TextStyle(
                    color: tc.pillGreenTx,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillGreenBg,
            border: Border(
                left: BorderSide(color: tc.pillGreenTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'ℹ️ Benefits are not deducted from net pay. These are additional savings received at 13th month payout or year-end.',
            style: TextStyle(
                fontSize: 11, color: tc.pillGreenTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required _ThemeColors tc,
    required String title,
    required IconData icon,
    required String badge,
    required Color badgeColor,
    required Color badgeText,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: _Mock.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: tc.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _row(_ThemeColors tc, String label, String value, bool negative) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: tc.textGrayDark, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        Text(value,
            style: TextStyle(
                color: negative ? const Color(0xFFFF4D6D) : tc.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
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
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}