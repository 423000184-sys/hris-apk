// lib/services/payroll_pdf_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show BuildContext;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/employee.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color palette
// ─────────────────────────────────────────────────────────────────────────────
class _PK {
  static const orange = PdfColor.fromInt(0xFFFF8A00);
  static const black = PdfColors.black;
  static const white = PdfColors.white;
  static const cardBorder = PdfColor.fromInt(0xFF27272A);
  static const dividerGrey = PdfColor.fromInt(0xFF3F3F46);
  static const textGray = PdfColor.fromInt(0xFFA1A1AA);
  static const textGrayDark = PdfColor.fromInt(0xFF52525B);
  static const lime = PdfColor.fromInt(0xFFC4FF0A);
  static const netBoxBg = PdfColor.fromInt(0xFFFFF3E0);
  static const paidBg = PdfColor.fromInt(0xFFF3FFDB);
  static const securityBg = PdfColor.fromInt(0xFFFFF3E0);
}

class PayrollPdfService {
  PayrollPdfService._();

  /// ✅ Master password — para sa admin/HR (fallback kung walang Employee ID)
  static const String _masterOwnerPassword = 'RACOMA_HRIS_MASTER_2024';

  static Future<String?> generate(
      BuildContext context, {
        required Employee employee,
        required DateTime month,
        required double basicSalary,
        required double sss,
        required double philhealth,
        required double pagibig,
        // ✅ NEW optional params:
        double absenceDeduction = 0,
        int absentDays = 0,
        double thirteenthMonth = 0,
        double silCredits = 0,
        required String bankName,
        required String accountNumber,
        required String department,
        required String designation,
      }) async {
    // ── STEP 1: Generate PDF using `pdf` package ─────────────────────
    final pdfBytes = await _buildPayslipPdf(
      employee: employee,
      month: month,
      basicSalary: basicSalary,
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      absenceDeduction: absenceDeduction,
      absentDays: absentDays,
      thirteenthMonth: thirteenthMonth,
      silCredits: silCredits,
      bankName: bankName,
      accountNumber: accountNumber,
      department: department,
      designation: designation,
    );

    // ── STEP 2: Encrypt the PDF ──────────────────────────────────────
    final rawEmployeeId = employee.employeeId.trim();

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔒 PDF ENCRYPTION');
    debugPrint('   Raw Employee ID : "$rawEmployeeId"');
    debugPrint('   Length          : ${rawEmployeeId.length} chars');
    debugPrint('═══════════════════════════════════════════');

    final pdfUserPassword = rawEmployeeId.isNotEmpty
        ? rawEmployeeId
        : _masterOwnerPassword;

    Uint8List securedBytes = pdfBytes;
    try {
      securedBytes = await _encryptPdf(
        pdfBytes,
        userPassword: pdfUserPassword,
        ownerPassword: _masterOwnerPassword,
      );
    } catch (e) {
      debugPrint('⚠️ PDF encryption failed: $e');
    }

    final filename = _filename(employee, month);

    if (kIsWeb) {
      await Printing.sharePdf(bytes: securedBytes, filename: filename);
      return null;
    }

    final targetDir = await _getDownloadsDirectory();
    final file = File('${targetDir.path}/$filename');
    await file.writeAsBytes(securedBytes);

    debugPrint('✅ Payslip saved to: ${file.path}');

    try {
      await Printing.sharePdf(bytes: securedBytes, filename: filename);
    } catch (e) {
      debugPrint('⚠️ Share sheet failed: $e');
    }

    return file.path;
  }

  static Future<Directory> _getDownloadsDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!await downloads.exists()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (e) {
      debugPrint('⚠️ getDownloadsDirectory failed: $e');
    }

    if (Platform.isAndroid) {
      try {
        final androidDownload = Directory('/storage/emulated/0/Download');
        if (await androidDownload.exists()) return androidDownload;
      } catch (_) {}
      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          final downloadDir = Directory('${external.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        }
      } catch (_) {}
    }

    if (Platform.isIOS) {
      try {
        return await getApplicationDocumentsDirectory();
      } catch (_) {}
    }

    return await getApplicationDocumentsDirectory();
  }

  static Future<Uint8List> _encryptPdf(
      Uint8List pdfBytes, {
        required String userPassword,
        required String ownerPassword,
      }) async {
    final finalUserPwd = userPassword.trim();
    final finalOwnerPwd = ownerPassword.trim();

    if (finalUserPwd.isEmpty) {
      throw Exception('User password cannot be empty');
    }

    final safeOwnerPwd = finalOwnerPwd == finalUserPwd
        ? '${finalOwnerPwd}_OWNER'
        : finalOwnerPwd;

    final document = sf.PdfDocument(inputBytes: pdfBytes);
    document.security.userPassword = finalUserPwd;
    document.security.ownerPassword = safeOwnerPwd;

    final List<int> securedBytes = await document.save();
    document.dispose();

    debugPrint('✅ PDF encrypted successfully');
    return Uint8List.fromList(securedBytes);
  }

  static Future<Uint8List> _buildPayslipPdf({
    required Employee employee,
    required DateTime month,
    required double basicSalary,
    required double sss,
    required double philhealth,
    required double pagibig,
    double absenceDeduction = 0,
    int absentDays = 0,
    double thirteenthMonth = 0,
    double silCredits = 0,
    required String bankName,
    required String accountNumber,
    required String department,
    required String designation,
  }) async {
    final doc = pw.Document(
      title: 'Payslip — ${employee.fullName}',
      author: 'R.A.C.O.M.A HRIS',
      creator: 'R.A.C.O.M.A HRIS',
      subject: 'Payslip for ${DateFormat('MMMM yyyy').format(month)}',
    );

    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final totalDeductions =
        absenceDeduction + sss + philhealth + pagibig;
    final netSalary = basicSalary - totalDeductions;
    final totalBenefits = thirteenthMonth + silCredits;

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
                  child: _earningsColumn(basicSalary: basicSalary),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: _deductionsColumn(
                    absenceDeduction: absenceDeduction,
                    absentDays: absentDays,
                    sss: sss,
                    philhealth: philhealth,
                    pagibig: pagibig,
                    totalDeductions: totalDeductions,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            _netSalaryBox(netSalary: netSalary, bankName: bankName),
            pw.SizedBox(height: 16),
            _benefitsBox(
              thirteenthMonth: thirteenthMonth,
              silCredits: silCredits,
              totalBenefits: totalBenefits,
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _PK.securityBg,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _PK.orange, width: 0.75),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('🔒  PASSWORD-PROTECTED PDF',
                      style: pw.TextStyle(
                          color: _PK.orange,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'To open this file, use your Employee ID as the password.',
                    style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 8),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Employee ID: ${employee.employeeId}',
                    style: pw.TextStyle(
                        color: _PK.orange,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
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
                  color: _PK.white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold)),
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
                    color: _PK.orange,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold)),
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
              padding:
              const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: _PK.paidBg,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text('Paid',
                  style: pw.TextStyle(
                      color: _PK.lime,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 6),
            pw.Text('Payslip for $monthLabel',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                    color: _PK.black,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold)),
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
          pw.Text(label,
              style: pw.TextStyle(color: _PK.black, fontSize: 8)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
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

  static pw.Widget _earningsColumn({required double basicSalary}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: pw.Text('EARNINGS',
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 8),
        _lineItem('Basic Salary', basicSalary, bold: true),
      ],
    );
  }

  static pw.Widget _deductionsColumn({
    required double absenceDeduction,
    required int absentDays,
    required double sss,
    required double philhealth,
    required double pagibig,
    required double totalDeductions,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 5),
          decoration: pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: pw.Text('DEDUCTIONS',
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 8),
        if (absentDays > 0) ...[
          _lineItem('Absences ($absentDays day/s)', absenceDeduction),
          pw.SizedBox(height: 8),
        ],
        _lineItem('SSS Contribution (4.5%)', sss),
        pw.SizedBox(height: 8),
        _lineItem('PhilHealth (2.5%)', philhealth),
        pw.SizedBox(height: 8),
        _lineItem('Pag-IBIG (2.0%)', pagibig),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
                top: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
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
                  fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
        pw.Text(_peso(value),
            style: pw.TextStyle(
                color: _PK.black,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _netSalaryBox({
    required double netSalary,
    required String bankName,
  }) {
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
                      color: _PK.orange,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('Amount transferred to $bankName',
                  style: pw.TextStyle(color: _PK.textGray, fontSize: 8)),
            ],
          ),
          pw.Text(_peso(netSalary),
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _benefitsBox({
    required double thirteenthMonth,
    required double silCredits,
    required double totalBenefits,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _PK.paidBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _PK.lime, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('BENEFITS (ACCRUED)',
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          _lineItem('13th Month Pay', thirteenthMonth),
          pw.SizedBox(height: 4),
          _lineItem('SIL Credits (5 days)', silCredits),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(color: _PK.cardBorder, width: 0.5)),
            ),
            child: _lineItem('Total Benefits', totalBenefits, bold: true),
          ),
        ],
      ),
    );
  }

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