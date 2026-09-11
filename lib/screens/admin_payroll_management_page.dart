// lib/screens/admin_payroll_management_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminPayrollManagementPage extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  final VoidCallback? onBack; // ✅ Back callback

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

  String get _name {
    final raw = widget.employeeData['name'];
    if (raw != null && raw.toString().isNotEmpty) return raw.toString();
    final first = widget.employeeData['firstName'] ?? '';
    final last = widget.employeeData['lastName'] ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unknown Employee' : full;
  }

  String get _employeeId {
    return (widget.employeeData['id'] ??
        widget.employeeData['employeeId'] ??
        'EMP-2023-042')
        .toString();
  }

  String get _department {
    return (widget.employeeData['department'] ?? 'Unassigned').toString();
  }

  double get _basicSalary {
    final raw = widget.employeeData['basicSalary'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  String? get _photoUrl {
    final url = widget.employeeData['photoUrl'];
    if (url is String && url.isNotEmpty) return url;
    return null;
  }

  double get _sss => _basicSalary * 0.045;
  double get _philhealth => _basicSalary * 0.025;
  double get _pagibig => _basicSalary * 0.020;
  double get _totalDeduction => _sss + _philhealth + _pagibig;
  double get _netPay => _basicSalary - _totalDeduction;

  // ✅ Back handler
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
        build: (pw.Context pwContext) {
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
                pw.Text('Period: Oct 1 - Oct 15, 2023'),
                pw.Divider(),
                pw.SizedBox(height: 12),
                pw.Text('Basic Salary: ₱${_basicSalary.toStringAsFixed(2)}'),
                pw.Text('SSS Deduction: ₱${_sss.toStringAsFixed(2)}'),
                pw.Text(
                    'PhilHealth Deduction: ₱${_philhealth.toStringAsFixed(2)}'),
                pw.Text('Pag-IBIG Deduction: ₱${_pagibig.toStringAsFixed(2)}'),
                pw.Text(
                    'Total Deductions: ₱${_totalDeduction.toStringAsFixed(2)}'),
                pw.SizedBox(height: 12),
                pw.Divider(),
                pw.Text('NET PAY: ₱${_netPay.toStringAsFixed(2)}',
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
    final pdfBytes = await _generatePdf();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'payslip_$_employeeId.pdf',
    );
  }

  Future<void> _handleDownload() async {
    final pdfBytes = await _generatePdf();
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'payslip_$_employeeId.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ PopScope — para gumana ang Android hardware back button
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: tc.background,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: BsContainer(
            maxWidth: 1300,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ✅ Back button sa taas
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

  // ══════════════════════════════════════════════════════════════
  // BACK BUTTON
  // ══════════════════════════════════════════════════════════════
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
                Text(
                  'Back to Payroll',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tc.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PROFILE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w =
          constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
          final isWide = w > 700;

          final avatar = Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECD0),
              shape: BoxShape.circle,
              border: Border.all(color: tc.border, width: 1),
              image: _photoUrl != null
                  ? DecorationImage(
                image: NetworkImage(_photoUrl!),
                fit: BoxFit.cover,
              )
                  : null,
            ),
            child: _photoUrl == null
                ? Center(
              child: Text(
                _getInitials(_name),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: tc.orangeText,
                ),
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
                        Text('🆔 ID: $_employeeId',
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
                          child: Text('📅 Oct 1 - Oct 15, 2023',
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

          if (isWide) {
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
            children: [
              header,
              const SizedBox(height: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isWide = w > 800;
        const gap = 20.0;

        final cards = <Widget>[
          _buildMetricCard(
              'NET PAY',
              '₱${_netPay.toStringAsFixed(2)}',
              'Total take-home for this period',
              false),
          _buildMetricCard(
              'GROSS PAY',
              '₱${_basicSalary.toStringAsFixed(2)}',
              'Regular earnings',
              false),
          _buildMetricCard(
              'TOTAL DEDUCTIONS',
              '₱${_totalDeduction.toStringAsFixed(2)}',
              '9% of Gross Pay',
              true),
        ];

        if (isWide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: gap),
                Expanded(child: cards[1]),
                const SizedBox(width: gap),
                Expanded(child: cards[2]),
              ],
            ),
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

  Widget _buildBreakdownGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isWide = w > 900;

        final earnings = _buildEarningsCard();
        final remittances = _buildRemittancesCard();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 13, child: earnings),
              const SizedBox(width: 20),
              Expanded(flex: 10, child: remittances),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            earnings,
            const SizedBox(height: 20),
            remittances,
          ],
        );
      },
    );
  }

  Widget _buildEarningsCard() {
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
                child: Text('Earnings Breakdown',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('₱${_basicSalary.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: tc.orangeText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildBreakdownItem('Basic Salary', 'Regular 15-day period',
              '₱${_basicSalary.toStringAsFixed(2)}', false),
          _buildBreakdownItem('Overtime Pay', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem('Late', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem('Leave', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem('Allowances', 'Non-taxable', '₱0.00', false),
          _buildBreakdownItem('Absent', '0 hrs', '-₱0.00', true),
        ],
      ),
    );
  }

  Widget _buildRemittancesCard() {
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
                child: Text('Government Remittances & Deductions',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: tc.pillErrBg,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('₱${_totalDeduction.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: tc.pillErrTx,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildBreakdownItem('SSS Contribution', '4.5% Employee Share',
              '-₱${_sss.toStringAsFixed(2)}', true),
          _buildBreakdownItem('PhilHealth Contribution', '2.5% Employee Share',
              '-₱${_philhealth.toStringAsFixed(2)}', true),
          _buildBreakdownItem('Pag-IBIG Contribution', '2.0% Employee Share',
              '-₱${_pagibig.toStringAsFixed(2)}', true),
          _buildBreakdownItem('Withholding Tax',
              'Calculated based on net taxable income', '-₱0.00', true),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.pillWarnBg,
              border: Border(left: BorderSide(color: tc.pillWarnTx, width: 4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ℹ️ Total statutory deductions amount to 9% of the basic salary (₱${_basicSalary.toStringAsFixed(2)}) for this pay period.',
              style: TextStyle(fontSize: 11, color: tc.pillWarnTx, height: 1.4),
            ),
          ),
        ],
      ),
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

  Widget _buildBreakdownItem(
      String title, String desc, String amount, bool isNegative) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
                        fontWeight: FontWeight.w600,
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
          Text(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isNegative ? tc.red : tc.text,
            ),
          ),
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