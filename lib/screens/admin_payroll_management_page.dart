// lib/screens/admin_payroll_management_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminPayrollManagementPage extends StatelessWidget {
  final Map<String, dynamic> employeeData;

  const AdminPayrollManagementPage({
    super.key,
    this.employeeData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final tc = AdminTheme.getColors(context);

    final String name = employeeData['name'] ??
        '${employeeData['firstName'] ?? ''} ${employeeData['lastName'] ?? ''}'
            .trim();
    final String employeeId =
    (employeeData['id'] ?? employeeData['employeeId'] ?? 'EMP-2023-042')
        .toString();
    final String department =
    (employeeData['department'] ?? 'Engineering').toString();
    final double basicSalary =
        (employeeData['basicSalary'] as num?)?.toDouble() ?? 50000.0;

    final double sss = basicSalary * 0.045;
    final double philhealth = basicSalary * 0.025;
    final double pagibig = basicSalary * 0.020;
    final double totalDeduction = sss + philhealth + pagibig;
    final double netPay = basicSalary - totalDeduction;

    Future<Uint8List> generatePdf() async {
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
                  pw.Text('Employee: $name'),
                  pw.Text('ID: $employeeId'),
                  pw.Text('Department: $department'),
                  pw.Text('Period: Oct 1 - Oct 15, 2023'),
                  pw.Divider(),
                  pw.SizedBox(height: 12),
                  pw.Text('Basic Salary: ₱${basicSalary.toStringAsFixed(2)}'),
                  pw.Text('SSS Deduction: ₱${sss.toStringAsFixed(2)}'),
                  pw.Text(
                      'PhilHealth Deduction: ₱${philhealth.toStringAsFixed(2)}'),
                  pw.Text(
                      'Pag-IBIG Deduction: ₱${pagibig.toStringAsFixed(2)}'),
                  pw.Text(
                      'Total Deductions: ₱${totalDeduction.toStringAsFixed(2)}'),
                  pw.SizedBox(height: 12),
                  pw.Divider(),
                  pw.Text('NET PAY: ₱${netPay.toStringAsFixed(2)}',
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

    Future<void> handlePrint() async {
      final pdfBytes = await generatePdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'payslip_$employeeId.pdf',
      );
    }

    Future<void> handleDownload() async {
      final pdfBytes = await generatePdf();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'payslip_$employeeId.pdf',
      );
    }

    return Scaffold(
      backgroundColor: tc.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: BsContainer(
          maxWidth: 1300,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildProfileCard(
                tc,
                name: name,
                employeeId: employeeId,
                department: department,
                onPrint: handlePrint,
                onDownload: handleDownload,
              ),
              const SizedBox(height: 24),
              _buildMetricsRow(
                tc,
                netPay: netPay,
                basicSalary: basicSalary,
                totalDeduction: totalDeduction,
              ),
              const SizedBox(height: 24),
              _buildBreakdownGrid(
                tc,
                basicSalary: basicSalary,
                sss: sss,
                philhealth: philhealth,
                pagibig: pagibig,
                totalDeduction: totalDeduction,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PROFILE CARD
  // ══════════════════════════════════════════════════════════════
  Widget _buildProfileCard(
      AdminColors tc, {
        required String name,
        required String employeeId,
        required String department,
        required VoidCallback onPrint,
        required VoidCallback onDownload,
      }) {
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

          final header = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: Color(0xFFFFECD0),
                backgroundImage:
                NetworkImage('https://i.pravatar.cc/150?img=12'),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
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
                        Text('🆔 ID: $employeeId',
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Text('🛠️ $department',
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

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onPrint,
                icon: const Text('🖨️', style: TextStyle(fontSize: 14)),
                label: Text('Print',
                    style: TextStyle(
                        color: tc.text, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: tc.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: onDownload,
                icon: const Text('📥', style: TextStyle(fontSize: 14)),
                label: const Text('Download Payslip',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.orange,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
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

  // ══════════════════════════════════════════════════════════════
  // METRICS ROW — Wrap based
  // ══════════════════════════════════════════════════════════════
  Widget _buildMetricsRow(
      AdminColors tc, {
        required double netPay,
        required double basicSalary,
        required double totalDeduction,
      }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isWide = w > 800;
        const gap = 20.0;

        final cards = <Widget>[
          _buildMetricCard(tc, 'NET PAY', '₱${netPay.toStringAsFixed(2)}',
              'Total take-home for this period', false),
          _buildMetricCard(tc, 'GROSS PAY',
              '₱${basicSalary.toStringAsFixed(2)}', 'Regular earnings', false),
          _buildMetricCard(
              tc,
              'TOTAL DEDUCTIONS',
              '₱${totalDeduction.toStringAsFixed(2)}',
              '9% of Gross Pay',
              true),
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

  // ══════════════════════════════════════════════════════════════
  // BREAKDOWN GRID — Earnings (13/23) + Remittances (10/23)
  // ══════════════════════════════════════════════════════════════
  Widget _buildBreakdownGrid(
      AdminColors tc, {
        required double basicSalary,
        required double sss,
        required double philhealth,
        required double pagibig,
        required double totalDeduction,
      }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0;
        final isWide = w > 900;

        final earnings = _buildEarningsCard(tc, basicSalary);
        final remittances = _buildRemittancesCard(
          tc,
          sss: sss,
          philhealth: philhealth,
          pagibig: pagibig,
          totalDeduction: totalDeduction,
          basicSalary: basicSalary,
        );

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

  Widget _buildEarningsCard(AdminColors tc, double basicSalary) {
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
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: tc.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('₱${basicSalary.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: tc.orangeText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildBreakdownItem(
              tc, 'Basic Salary', 'Regular 15-day period',
              '₱${basicSalary.toStringAsFixed(2)}', false),
          _buildBreakdownItem(
              tc, 'Overtime Pay', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem(tc, 'Late', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem(tc, 'Leave', '0 hours logged', '₱0.00', false),
          _buildBreakdownItem(
              tc, 'Allowances', 'Non-taxable', '₱0.00', false),
          _buildBreakdownItem(tc, 'Absent', '0 hrs', '-₱0.00', true),
        ],
      ),
    );
  }

  Widget _buildRemittancesCard(
      AdminColors tc, {
        required double sss,
        required double philhealth,
        required double pagibig,
        required double totalDeduction,
        required double basicSalary,
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
                child: Text('Government Remittances & Deductions',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: tc.text),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: tc.pillErrBg,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('₱${totalDeduction.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: tc.pillErrTx,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildBreakdownItem(tc, 'SSS Contribution',
              '4.5% Employee Share', '-₱${sss.toStringAsFixed(2)}', true),
          _buildBreakdownItem(
              tc,
              'PhilHealth Contribution',
              '2.5% Employee Share',
              '-₱${philhealth.toStringAsFixed(2)}',
              true),
          _buildBreakdownItem(tc, 'Pag-IBIG Contribution',
              '2.0% Employee Share', '-₱${pagibig.toStringAsFixed(2)}', true),
          _buildBreakdownItem(tc, 'Withholding Tax',
              'Calculated based on net taxable income', '-₱0.00', true),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.pillWarnBg,
              border: Border(
                  left: BorderSide(color: tc.pillWarnTx, width: 4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ℹ️ Total statutory deductions amount to 9% of the basic salary (₱${basicSalary.toStringAsFixed(2)}) for this pay period according to current government tables.',
              style: TextStyle(
                  fontSize: 11, color: tc.pillWarnTx, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
      AdminColors tc, String title, String value, String subtitle, bool isRed) {
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
      AdminColors tc, String title, String desc, String amount, bool isNegative) {
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
}