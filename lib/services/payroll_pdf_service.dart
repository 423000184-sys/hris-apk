// lib/services/payroll_pdf_service.dart
//
// Generates a Payslip / Full-Month Payroll PDF report.
// Pulls records and computes daily/monthly revenue figures.
//
// Dependencies (dapat nasa pubspec.yaml at na-`flutter pub get` na):
//   pdf: ^3.10.8
//   printing: ^5.12.0
//   path_provider: ^2.1.2
//   intl: (already present)

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show BuildContext;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/employee.dart';
import '../services/database_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for one day's attendance + earnings
// ─────────────────────────────────────────────────────────────────────────────
class _DayRecord {
  final String date;         // yyyy-MM-dd
  final String? timeIn;      // HH:mm:ss
  final String? timeOut;     // HH:mm:ss
  final String  method;
  final double  hoursWorked;
  final double  dailyEarned;

  const _DayRecord({
    required this.date,
    this.timeIn,
    this.timeOut,
    required this.method,
    required this.hoursWorked,
    required this.dailyEarned,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Color palette — matches the light "Payslip" mock palette & dark theme elements.
// ─────────────────────────────────────────────────────────────────────────────
class _PK {
  static const orange       = PdfColor.fromInt(0xFFFF8A00);
  static const black        = PdfColors.black;
  static const white        = PdfColors.white;
  static const cardBorder   = PdfColor.fromInt(0xFF27272A);
  static const dividerGrey  = PdfColor.fromInt(0xFF3F3F46);
  static const textGray     = PdfColor.fromInt(0xFFA1A1AA);
  static const textGrayDark = PdfColor.fromInt(0xFF52525B);
  static const lime         = PdfColor.fromInt(0xFFC4FF0A);
  static const netBoxBg     = PdfColor.fromInt(0xFFFFF3E0);
  static const paidBg       = PdfColor.fromInt(0xFFF3FFDB);
}

class _K {
  static const navy     = PdfColor.fromInt(0xFF0A0F2E);
  static const card     = PdfColor.fromInt(0xFF0F1535);
  static const accent   = PdfColor.fromInt(0xFF00D4FF);
  static const success  = PdfColor.fromInt(0xFF00C88A);
  static const warning  = PdfColor.fromInt(0xFFFFBB00);
  static const error    = PdfColor.fromInt(0xFFFF4D6D);
  static const white    = PdfColors.white;
  static const white70  = PdfColor.fromInt(0xB3FFFFFF);
  static const textGrey = PdfColor.fromInt(0xFF8892A4);
  static const rowAlt   = PdfColor.fromInt(0xFF131A45);
}

class PayrollPdfService {
  PayrollPdfService._();

  /// Entry point — call this from ReportsScreen's Download/Print button.
  /// Returns the saved file path on mobile/desktop, or null on web.
  static Future<String?> generate(
      BuildContext context, {
        required Employee employee,
        required DateTime month,
        required double basicSalary,
        required double housingAllowance,
        required double transportAllowance,
        required double specialAllowance,
        required double providentFund,
        required double professionalTax,
        required String bankName,
        required String accountNumber,
        required String department,
        required String designation,
      }) async {
    final bytes = await _buildPayslipPdf(
      employee: employee,
      month: month,
      basicSalary: basicSalary,
      housingAllowance: housingAllowance,
      transportAllowance: transportAllowance,
      specialAllowance: specialAllowance,
      providentFund: providentFund,
      professionalTax: professionalTax,
      bankName: bankName,
      accountNumber: accountNumber,
      department: department,
      designation: designation,
    );

    final filename = _filename(employee, month);

    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: filename);
      return null;
    }

    // Isulat ang PDF sa device storage muna
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    // Karagdagang option: share sheet
    await Printing.sharePdf(bytes: bytes, filename: filename);

    return file.path;
  }

  // ── PDF builder ────────────────────────────────────────────────────────────
  static Future<Uint8List> _buildPayslipPdf({
    required Employee employee,
    required DateTime month,
    required double basicSalary,
    required double housingAllowance,
    required double transportAllowance,
    required double specialAllowance,
    required double providentFund,
    required double professionalTax,
    required String bankName,
    required String accountNumber,
    required String department,
    required String designation,
  }) async {
    final doc = pw.Document(
      title: 'Payslip — ${employee.fullName}',
      author: 'R.A.C.O.M.A HRIS',
    );

    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final totalEarnings =
        basicSalary + housingAllowance + transportAllowance + specialAllowance;
    final totalDeductions = providentFund + professionalTax;
    final netSalary = totalEarnings - totalDeductions;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(monthLabel),
            pw.SizedBox(height: 20),
            _companyAndPaidRow(monthLabel),
            pw.SizedBox(height: 18),
            _detailsGrid(
              employee: employee,
              designation: designation,
              department: department,
              bankName: bankName,
              accountNumber: accountNumber,
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: _PK.dividerGrey, thickness: 0.75),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _earningsColumn(
                    basicSalary: basicSalary,
                    housingAllowance: housingAllowance,
                    transportAllowance: transportAllowance,
                    specialAllowance: specialAllowance,
                    totalEarnings: totalEarnings,
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: _deductionsColumn(
                    providentFund: providentFund,
                    professionalTax: professionalTax,
                    totalDeductions: totalDeductions,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            _netSalaryBox(netSalary: netSalary, bankName: bankName),
            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.Text(
                'This is a computer-generated document. No signature is required.',
                style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 9),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Generated on ${DateFormat('M/d/yyyy').format(DateTime.now())} via R.A.C.O.M.A HRIS',
                style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 9),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(String monthLabel) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: pw.BoxDecoration(
        color: _PK.orange,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Payslip Details',
              style: pw.TextStyle(
                  color: _PK.white, fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Salary slip for $monthLabel',
              style: pw.TextStyle(color: _PK.white, fontSize: 11)),
        ],
      ),
    );
  }

  static pw.Widget _companyAndPaidRow(String monthLabel) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('R.A.C.O.M.A',
                style: pw.TextStyle(
                    color: _PK.orange, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Smart HR Information System',
                style: pw.TextStyle(color: _PK.black, fontSize: 9)),
            pw.SizedBox(height: 4),
            pw.Text('Jumbo HQ, Manila, Philippines',
                style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 8)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: _PK.paidBg,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text('Paid',
                  style: pw.TextStyle(
                      color: _PK.lime, fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Payslip for $monthLabel',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    color: _PK.black, fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _detailsGrid({
    required Employee employee,
    required String designation,
    required String department,
    required String bankName,
    required String accountNumber,
  }) {
    pw.Widget item(String label, String value) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(color: _PK.black, fontSize: 8)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  color: _PK.black, fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );

    return pw.Column(
      children: [
        pw.Row(children: [
          item('Employee Name', employee.fullName),
          item('Employee ID', employee.employeeId),
        ]),
        pw.SizedBox(height: 12),
        pw.Row(children: [
          item('Designation', designation),
          item('Department', department),
        ]),
        pw.SizedBox(height: 12),
        pw.Row(children: [
          item('Bank Name', bankName),
          item('Account Number', accountNumber),
        ]),
      ],
    );
  }

  static pw.Widget _earningsColumn({
    required double basicSalary,
    required double housingAllowance,
    required double transportAllowance,
    required double specialAllowance,
    required double totalEarnings,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: pw.Text('EARNINGS',
              style: pw.TextStyle(
                  color: _PK.black, fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 8),
        _lineItem('Basic Salary', basicSalary),
        pw.SizedBox(height: 8),
        _lineItem('Housing Allowance (HRA)', housingAllowance),
        pw.SizedBox(height: 8),
        _lineItem('Transport Allowance', transportAllowance),
        pw.SizedBox(height: 8),
        _lineItem('Special Allowance', specialAllowance),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: _lineItem('Total Earnings', totalEarnings, bold: true),
        ),
      ],
    );
  }

  static pw.Widget _deductionsColumn({
    required double providentFund,
    required double professionalTax,
    required double totalDeductions,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: pw.Text('DEDUCTIONS',
              style: pw.TextStyle(
                  color: _PK.black, fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 8),
        _lineItem('Provident Fund (PF)', providentFund),
        pw.SizedBox(height: 8),
        _lineItem('Professional Tax', professionalTax),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: _lineItem('Total Deductions', totalDeductions, bold: true),
        ),
      ],
    );
  }

  static pw.Widget _lineItem(String label, double value, {bool bold = false}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Expanded(
          child: pw.Text(label,
              style: pw.TextStyle(
                  color: bold ? _PK.black : _PK.textGray,
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
        pw.Text(_peso(value),
            style: pw.TextStyle(
                color: _PK.black, fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _netSalaryBox({required double netSalary, required String bankName}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _PK.netBoxBg,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Net Salary Payable',
                  style: pw.TextStyle(
                      color: _PK.orange, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('Amount transferred to $bankName',
                  style: pw.TextStyle(color: _PK.textGray, fontSize: 8)),
            ],
          ),
          pw.Text(_peso(netSalary),
              style: pw.TextStyle(
                  color: _PK.black, fontSize: 15, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ── utils ──────────────────────────────────────────────────────────────────
  static String _peso(double v) {
    final wholeStr = v.toStringAsFixed(2);
    final parts = wholeStr.split('.');
    final wholePart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '00';
    final buf = StringBuffer();
    for (int i = 0; i < wholePart.length; i++) {
      final posFromEnd = wholePart.length - i;
      buf.write(wholePart[i]);
      if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
    }
    return '\u20b1${buf.toString()}.$decimalPart';
  }

  static String _filename(Employee employee, DateTime month) {
    final m = DateFormat('yyyy-MM').format(month);
    final n = employee.fullName.replaceAll(RegExp(r'\s+'), '_');
    return 'Payslip_${n}_$m.pdf';
  }
}