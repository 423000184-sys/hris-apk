// lib/screens/admin_payroll_management_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/payroll_calculator.dart';
import '../services/employee_notification_service.dart';

class AdminPayrollManagementPage extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  final VoidCallback? onBack;

  const AdminPayrollManagementPage({
    super.key,
    this.employeeData = const {},
    this.onBack,
  });

  @override
  State<AdminPayrollManagementPage> createState() =>
      _AdminPayrollManagementPageState();
}

class _AdminPayrollManagementPageState
    extends State<AdminPayrollManagementPage> {
  AdminColors get tc => AdminTheme.getColors(context);

  PayrollBreakdown _b = PayrollBreakdown.empty;
  bool _loading = true;

  String get _name {
    final raw = widget.employeeData['name'];
    if (raw != null && raw.toString().isNotEmpty) return raw.toString();
    final first = widget.employeeData['firstName'] ?? '';
    final last = widget.employeeData['lastName'] ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unknown Employee' : full;
  }

  String get _employeeId =>
      (widget.employeeData['id'] ?? widget.employeeData['employeeId'] ?? '—')
          .toString();

  String get _department =>
      (widget.employeeData['department'] ?? 'Unassigned').toString();

  String? get _photoUrl {
    final url = widget.employeeData['photoUrl'];
    if (url is String && url.isNotEmpty) return url;
    return null;
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime get _periodEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  }

  String get _periodLabel {
    final s = _periodStart;
    final e = _periodEnd;
    const m = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${m[s.month]} ${s.day} - ${m[e.month]} ${e.day}, ${e.year}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final b = await PayrollCalculator.compute(
      employee: widget.employeeData,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
    );
    if (!mounted) return;
    setState(() {
      _b = b;
      _loading = false;
    });
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context c) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('PAYSLIP',
                    style: pw.TextStyle(
                        fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 12),
                pw.Text('Employee: $_name'),
                pw.Text('ID: $_employeeId'),
                pw.Text('Department: $_department'),
                pw.Text('Period: $_periodLabel'),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text('EARNINGS',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text('Basic Salary: ${PayrollCalculator.peso(_b.basicSalary)}'),
                pw.Text('Allowances: ${PayrollCalculator.peso(_b.allowances)}'),
                pw.Text('Gross: ${PayrollCalculator.peso(_b.grossPay)}'),
                pw.SizedBox(height: 8),
                pw.Text('DEDUCTIONS',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Absences (${_b.absentDays} day/s): -${PayrollCalculator.peso(_b.absenceDeduction)}'),
                pw.Text('SSS: -${PayrollCalculator.peso(_b.sss)}'),
                pw.Text('PhilHealth: -${PayrollCalculator.peso(_b.philhealth)}'),
                pw.Text('Pag-IBIG: -${PayrollCalculator.peso(_b.pagibig)}'),
                pw.Text('Total: -${PayrollCalculator.peso(_b.totalDeductions)}'),
                pw.SizedBox(height: 8),
                pw.Divider(),
                pw.Text('NET PAY: ${PayrollCalculator.peso(_b.netPay)}',
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<void> _handlePrint() async {
    final bytes = await _generatePdf();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat f) async => bytes,
      name: 'payslip_$_employeeId.pdf',
    );

    // ✅ AUTO-NOTIFY EMPLOYEE
    await _notifyEmployeePayroll();
  }

  Future<void> _handleDownload() async {
    final bytes = await _generatePdf();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'payslip_$_employeeId.pdf',
    );

    // ✅ AUTO-NOTIFY EMPLOYEE
    await _notifyEmployeePayroll();
  }

  /// ✅ Send notification sa employee na may payslip na
  Future<void> _notifyEmployeePayroll() async {
    try {
      await EmployeeNotificationService.instance.sendPayrollAlert(
        employeeId: _employeeId,
        employeeName: _name,
        month: _periodLabel,
        netPay: _b.netPay,
      );
      debugPrint('✅ [PayrollMgmt] Employee notified of payslip');
    } catch (e) {
      debugPrint('⚠️ [PayrollMgmt] Employee notification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: tc.background,
        body: _loading
            ? Center(child: CircularProgressIndicator(color: tc.orange))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: BsContainer(
            maxWidth: 1300,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBackButton(),
                const SizedBox(height: 12),
                _buildProfileCard(),
                const SizedBox(height: 24),
                _buildMetricsRow(),
                const SizedBox(height: 24),
                _buildBreakdownGrid(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleBack,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 18, color: tc.text),
                const SizedBox(width: 8),
                Text('Back to Payroll',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tc.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
          final wide = w > 700;

          final avatar = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECD0),
              shape: BoxShape.circle,
              border: Border.all(color: tc.border),
              image: _photoUrl != null
                  ? DecorationImage(
                  image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            child: _photoUrl == null
                ? Center(
              child: Text(
                _getInitials(_name),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: tc.orangeText),
              ),
            )
                : null,
          );

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_name,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: tc.text),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('🆔 $_employeeId',
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Text('🛠️ $_department',
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tc.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tc.border),
                          ),
                          child: Text('📅 $_periodLabel',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: tc.text,
                                  fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _handlePrint,
                icon: const Text('🖨️', style: TextStyle(fontSize: 14)),
                label: Text('Print',
                    style: TextStyle(
                        color: tc.text, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tc.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _handleDownload,
                icon: const Text('📥', style: TextStyle(fontSize: 14)),
                label: const Text('Download Payslip',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.orange,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: header),
                const SizedBox(width: 16),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, const SizedBox(height: 16), actions],
          );
        },
      ),
    );
  }

  Widget _buildMetricsRow() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        final wide = w > 800;
        const gap = 20.0;

        final cards = <Widget>[
          _buildMetricCard('NET PAY', PayrollCalculator.peso(_b.netPay),
              'Total take-home for this period', false),
          _buildMetricCard('GROSS PAY', PayrollCalculator.peso(_b.grossPay),
              'Basic + Allowances + OT', false),
          _buildMetricCard('TOTAL DEDUCTIONS',
              PayrollCalculator.peso(_b.totalDeductions),
              'Absences + Govt (9%)', true),
        ];

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: gap),
              Expanded(child: cards[1]),
              const SizedBox(width: gap),
              Expanded(child: cards[2]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards[0],
            const SizedBox(height: gap),
            cards[1],
            const SizedBox(height: gap),
            cards[2],
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
      String title, String value, String subtitle, bool isRed) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: tc.muted,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: isRed ? tc.red : tc.text),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: tc.muted),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildBreakdownGrid() {
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        final wide = w > 900;

        final earnings = _earningsCard();
        final benefits = _benefitsCard();
        final absences = _absencesCard();
        final govt = _govtCard();

        if (wide) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: earnings),
                  const SizedBox(width: 20),
                  Expanded(child: benefits),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: absences),
                  const SizedBox(width: 20),
                  Expanded(child: govt),
                ],
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            earnings,
            const SizedBox(height: 20),
            benefits,
            const SizedBox(height: 20),
            absences,
            const SizedBox(height: 20),
            govt,
          ],
        );
      },
    );
  }

  Widget _earningsCard() {
    return _panel(
      title: 'Earnings Breakdown',
      badge: PayrollCalculator.peso(_b.grossPay),
      badgeColor: tc.orange.withValues(alpha: 0.15),
      badgeTextColor: tc.orangeText,
      children: [
        _item('Basic Salary', 'Regular monthly pay',
            PayrollCalculator.peso(_b.basicSalary), false),
        _item('Allowances', 'Housing / Transport / Special',
            PayrollCalculator.peso(_b.allowances), false),
        _item('Overtime Pay', 'Additional hours',
            PayrollCalculator.peso(_b.overtimePay), false),
        Divider(color: tc.border, height: 20),
        _item('Total Gross', 'Sum of earnings',
            PayrollCalculator.peso(_b.grossPay), false, bold: true),
      ],
    );
  }

  Widget _benefitsCard() {
    return _panel(
      title: 'Benefits (Accrued)',
      badge: PayrollCalculator.peso(_b.totalBenefits),
      badgeColor: tc.pillGreenBg,
      badgeTextColor: tc.pillGreenTx,
      children: [
        _item('13th Month Pay', '1/12 of basic salary',
            PayrollCalculator.peso(_b.thirteenthMonth), false),
        _item('SIL Credits', '5 days × daily rate (convertible)',
            PayrollCalculator.peso(_b.silCredits), false),
        _item('Service Incentive', 'Based on tenure & attendance',
            '—', false),
        Divider(color: tc.border, height: 20),
        _item('Total Benefits', 'Accrued, not yet paid',
            PayrollCalculator.peso(_b.totalBenefits), false, bold: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillGreenBg,
            border: Border(left: BorderSide(color: tc.pillGreenTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'ℹ️ Benefits are not deducted from net pay. These are additional savings received at the 13th month payout or year-end.',
            style: TextStyle(
                fontSize: 11, color: tc.pillGreenTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _absencesCard() {
    return _panel(
      title: 'Attendance & Absences',
      badge: _b.absentDays > 0
          ? '-${PayrollCalculator.peso(_b.absenceDeduction)}'
          : 'Perfect',
      badgeColor: _b.absentDays > 0 ? tc.pillErrBg : tc.pillGreenBg,
      badgeTextColor: _b.absentDays > 0 ? tc.pillErrTx : tc.pillGreenTx,
      children: [
        _item('Working Days', 'Weekdays in the period',
            '${_b.workingDays}', false),
        _item('Present Days', 'With clock-in logged',
            '${_b.presentDays}', false),
        _item('Absent Days', 'No clock-in on weekday',
            '${_b.absentDays}', _b.absentDays > 0),
        _item('Daily Rate', 'Basic ÷ working days',
            PayrollCalculator.peso(_b.dailyRate), false),
        Divider(color: tc.border, height: 20),
        _item('Absence Deduction',
            '${_b.absentDays} day/s × daily rate',
            '-${PayrollCalculator.peso(_b.absenceDeduction)}',
            _b.absentDays > 0,
            bold: true),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _b.absentDays > 0 ? tc.pillErrBg : tc.pillGreenBg,
            border: Border(
                left: BorderSide(
                    color: _b.absentDays > 0
                        ? tc.pillErrTx
                        : tc.pillGreenTx,
                    width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _b.absentDays > 0
                ? '⚠️ ${_b.absentDays} absent day(s) automatically deducted from salary based on attendance logs.'
                : '✓ No absences this period. Full salary will be received.',
            style: TextStyle(
                fontSize: 11,
                color:
                _b.absentDays > 0 ? tc.pillErrTx : tc.pillGreenTx,
                height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _govtCard() {
    final total = _b.sss + _b.philhealth + _b.pagibig + _b.withholdingTax;
    return _panel(
      title: 'Government Remittances & Deductions',
      badge: '-${PayrollCalculator.peso(total)}',
      badgeColor: tc.pillErrBg,
      badgeTextColor: tc.pillErrTx,
      children: [
        _item('SSS Contribution', '4.5% Employee Share',
            '-${PayrollCalculator.peso(_b.sss)}', true),
        _item('PhilHealth Contribution', '2.5% Employee Share',
            '-${PayrollCalculator.peso(_b.philhealth)}', true),
        _item('Pag-IBIG Contribution', '2.0% Employee Share',
            '-${PayrollCalculator.peso(_b.pagibig)}', true),
        _item('Withholding Tax',
            'Calculated based on net taxable income',
            '-${PayrollCalculator.peso(_b.withholdingTax)}', true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillWarnBg,
            border: Border(left: BorderSide(color: tc.pillWarnTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'ℹ️ Total statutory deductions amount to 9% of the basic salary (${PayrollCalculator.peso(_b.basicSalary)}) for this pay period.',
            style:
            TextStyle(fontSize: 11, color: tc.pillWarnTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _item(String title, String desc, String amount, bool negative,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                        bold ? FontWeight.w700 : FontWeight.w600,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(fontSize: 11, color: tc.muted),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(amount,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: negative ? tc.red : tc.text)),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'HR';
  }
}