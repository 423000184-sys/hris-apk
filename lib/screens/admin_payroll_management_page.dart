import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class AdminPayrollManagementPage extends StatelessWidget {
  final Map<String, dynamic> employeeData;

  const AdminPayrollManagementPage({
    super.key,
    this.employeeData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final String name = employeeData['name'] ??
        '${employeeData['firstName'] ?? ''} ${employeeData['lastName'] ?? ''}'.trim();
    final String employeeId = employeeData['id'] ?? employeeData['employeeId'] ?? 'EMP-2023-042';
    final String department = employeeData['department'] ?? 'Engineering';
    final double basicSalary = (employeeData['basicSalary'] as num?)?.toDouble() ?? 50000.0;

    final double sss = basicSalary * 0.045;
    final double philhealth = basicSalary * 0.025;
    final double pagibig = basicSalary * 0.020;
    final double totalDeduction = sss + philhealth + pagibig;
    final double netPay = basicSalary - totalDeduction;

    // Cross-platform PDF Generator for Printing and Downloading
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
                  pw.Text('PAYSLIP', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 12),
                  pw.Text('Employee: $name'),
                  pw.Text('ID: $employeeId'),
                  pw.Text('Department: $department'),
                  pw.Text('Period: Oct 1 - Oct 15, 2023'),
                  pw.Divider(),
                  pw.SizedBox(height: 12),
                  pw.Text('Basic Salary: ₱${basicSalary.toStringAsFixed(2)}'),
                  pw.Text('SSS Deduction: ₱${sss.toStringAsFixed(2)}'),
                  pw.Text('PhilHealth Deduction: ₱${philhealth.toStringAsFixed(2)}'),
                  pw.Text('Pag-IBIG Deduction: ₱${pagibig.toStringAsFixed(2)}'),
                  pw.Text('Total Deductions: ₱${totalDeduction.toStringAsFixed(2)}'),
                  pw.SizedBox(height: 12),
                  pw.Divider(),
                  pw.Text('NET PAY: ₱${netPay.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            );
          },
        ),
      );
      return pdf.save();
    }

    void handlePrint() async {
      final pdfBytes = await generatePdf();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'payslip_$employeeId.pdf',
      );
    }

    void handleDownload() async {
      final pdfBytes = await generatePdf();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'payslip_$employeeId.pdf',
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          // CONTENT BODY
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1300),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PROFILE CARD
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE1E6ED)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                radius: 32,
                                backgroundColor: Color(0xFFFFECD0),
                                backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=12'),
                              ),
                              const SizedBox(width: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF11142D))),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text('🆔 ID: $employeeId', style: const TextStyle(fontSize: 12, color: Color(0xFF6C727F), fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 16),
                                      const Text('•', style: TextStyle(color: Color(0xFF6C727F))),
                                      const SizedBox(width: 16),
                                      Text('🛠️ $department', style: const TextStyle(fontSize: 12, color: Color(0xFF6C727F), fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 16),
                                      const Text('•', style: TextStyle(color: Color(0xFF6C727F))),
                                      const SizedBox(width: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFE1E6ED)),
                                        ),
                                        child: const Text('📅 Oct 1 - Oct 15, 2023', style: TextStyle(fontSize: 12, color: Color(0xFF11142D), fontWeight: FontWeight.w500)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: handlePrint,
                                icon: const Text('🖨️', style: TextStyle(fontSize: 14)),
                                label: const Text('Print', style: TextStyle(color: Color(0xFF11142D), fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFE1E6ED)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: handleDownload,
                                icon: const Text('📥', style: TextStyle(fontSize: 14)),
                                label: const Text('Download Payslip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF8A00),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // METRICS ROW
                    Row(
                      children: [
                        Expanded(child: _buildMetricCard('NET PAY', '₱${netPay.toStringAsFixed(2)}', 'Total take-home for this period', false)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildMetricCard('GROSS PAY', '₱${basicSalary.toStringAsFixed(2)}', 'Regular earnings', false)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildMetricCard('TOTAL DEDUCTIONS', '₱${totalDeduction.toStringAsFixed(2)}', '9% of Gross Pay', true)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // BREAKDOWN GRID
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 13,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E6ED))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Earnings Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF11142D))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFFFECD0), borderRadius: BorderRadius.circular(6)),
                                      child: Text('₱${basicSalary.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFC27803), fontSize: 11, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildBreakdownItem('Basic Salary', 'Regular 15-day period', '₱${basicSalary.toStringAsFixed(2)}', false),
                                _buildBreakdownItem('Overtime Pay', '0 hours logged', '₱0.00', false),
                                _buildBreakdownItem('Late', '0 hours logged', '₱0.00', false),
                                _buildBreakdownItem('Leave', '0 hours logged', '₱0.00', false),
                                _buildBreakdownItem('Allowances', 'Non-taxable', '₱0.00', false),
                                _buildBreakdownItem('Absent', '0 hrs', '-₱0.00', true),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 10,
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE1E6ED))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Government Remittances & Deductions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF11142D))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                                      child: Text('₱${totalDeduction.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                _buildBreakdownItem('SSS Contribution', '4.5% Employee Share', '-₱${sss.toStringAsFixed(2)}', true),
                                _buildBreakdownItem('PhilHealth Contribution', '2.5% Employee Share', '-₱${philhealth.toStringAsFixed(2)}', true),
                                _buildBreakdownItem('Pag-IBIG Contribution', '2.0% Employee Share', '-₱${pagibig.toStringAsFixed(2)}', true),
                                _buildBreakdownItem('Withholding Tax', 'Calculated based on net taxable income', '-₱0.00', true),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    border: const Border(left: BorderSide(color: Color(0xFFF59E0B), width: 4)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ℹ️ Total statutory deductions amount to 9% of the basic salary (₱${basicSalary.toStringAsFixed(2)}) for this pay period according to current government tables.',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, bool isRed) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E6ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6C727F), letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isRed ? const Color(0xFFEF4444) : const Color(0xFF11142D))),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6C727F))),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(String title, String desc, String amount, bool isNegative) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF11142D))),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11, color: Color(0xFF6C727F))),
            ],
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isNegative ? const Color(0xFFEF4444) : const Color(0xFF11142D),
            ),
          ),
        ],
      ),
    );
  }
}