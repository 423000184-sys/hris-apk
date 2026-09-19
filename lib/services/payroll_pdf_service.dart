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
  static const orangeSoft = PdfColor.fromInt(0xFFFFF3E0);
  static const black = PdfColors.black;
  static const white = PdfColors.white;
  static const cardBorder = PdfColor.fromInt(0xFF27272A);
  static const dividerGrey = PdfColor.fromInt(0xFF3F3F46);
  static const textGray = PdfColor.fromInt(0xFFA1A1AA);
  static const textGrayDark = PdfColor.fromInt(0xFF52525B);
  static const lime = PdfColor.fromInt(0xFFC4FF0A);
  static const limeSoft = PdfColor.fromInt(0xFFF3FFDB);
  static const limeDark = PdfColor.fromInt(0xFF16A34A);
  static const red = PdfColor.fromInt(0xFFDC2626);
  static const redSoft = PdfColor.fromInt(0xFFFEEAEA);
  static const blue = PdfColor.fromInt(0xFF2563EB);
  static const blueSoft = PdfColor.fromInt(0xFFEFF6FF);
  static const netBoxBg = PdfColor.fromInt(0xFFFFF3E0);
  static const paidBg = PdfColor.fromInt(0xFFF3FFDB);
  static const securityBg = PdfColor.fromInt(0xFFFFF3E0);
}

class PayrollPdfService {
  PayrollPdfService._();

  static const String _masterOwnerPassword = 'RACOMA_HRIS_MASTER_2024';

  static Future<String?> generate(
      BuildContext context, {
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
        // 🍱 WORK HOURS
        int workRawMinutes = 0,
        int workLunchMinutes = 0,
        int workNetMinutes = 0,
        int workOvertimeMinutes = 0,
        int daysWithLogs = 0,
        int daysWithLunchApplied = 0,
        // 🍱 ATTENDANCE
        int workingDays = 22,
        int presentDays = 0,
        double dailyRate = 0,
        double allowances = 0,
        double overtimePay = 0,
        double grossPay = 0,
        // 💰 SALARY CONFIG
        int workingDaysPerMonth = 22,
        String salarySource = 'manual',
      }) async {
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
      workRawMinutes: workRawMinutes,
      workLunchMinutes: workLunchMinutes,
      workNetMinutes: workNetMinutes,
      workOvertimeMinutes: workOvertimeMinutes,
      daysWithLogs: daysWithLogs,
      daysWithLunchApplied: daysWithLunchApplied,
      workingDays: workingDays,
      presentDays: presentDays,
      dailyRate: dailyRate,
      allowances: allowances,
      overtimePay: overtimePay,
      grossPay: grossPay,
      workingDaysPerMonth: workingDaysPerMonth,
      salarySource: salarySource,
    );

    final rawEmployeeId = employee.employeeId.trim();

    debugPrint('═══════════════════════════════════════════');
    debugPrint('🔒 PDF ENCRYPTION');
    debugPrint('   Raw Employee ID : "$rawEmployeeId"');
    debugPrint('   Length          : ${rawEmployeeId.length} chars');
    debugPrint('═══════════════════════════════════════════');

    final pdfUserPassword =
    rawEmployeeId.isNotEmpty ? rawEmployeeId : _masterOwnerPassword;

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

    final safeOwnerPwd =
    finalOwnerPwd == finalUserPwd ? '${finalOwnerPwd}_OWNER' : finalOwnerPwd;

    final document = sf.PdfDocument(inputBytes: pdfBytes);
    document.security.userPassword = finalUserPwd;
    document.security.ownerPassword = safeOwnerPwd;

    final List<int> securedBytes = await document.save();
    document.dispose();

    debugPrint('✅ PDF encrypted successfully');
    return Uint8List.fromList(securedBytes);
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD PAYSLIP PDF
  // ═══════════════════════════════════════════════════════════════
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
    int workRawMinutes = 0,
    int workLunchMinutes = 0,
    int workNetMinutes = 0,
    int workOvertimeMinutes = 0,
    int daysWithLogs = 0,
    int daysWithLunchApplied = 0,
    int workingDays = 22,
    int presentDays = 0,
    double dailyRate = 0,
    double allowances = 0,
    double overtimePay = 0,
    double grossPay = 0,
    int workingDaysPerMonth = 22,
    String salarySource = 'manual',
  }) async {
    final doc = pw.Document(
      title: 'Payslip — ${employee.fullName}',
      author: 'R.A.C.O.M.A HRIS',
      creator: 'R.A.C.O.M.A HRIS',
      subject: 'Payslip for ${DateFormat('MMMM yyyy').format(month)}',
    );

    final monthLabel = DateFormat('MMMM yyyy').format(month);
    final totalDeductions = absenceDeduction + sss + philhealth + pagibig;
    final finalGross = grossPay > 0
        ? grossPay
        : basicSalary + allowances + overtimePay;
    final netSalary = finalGross - totalDeductions;
    final totalBenefits = thirteenthMonth + silCredits;
    final govtTotal = sss + philhealth + pagibig;

    // ✅ FIX: explicit double typing
    final double effectiveDailyRate = dailyRate > 0
        ? dailyRate.toDouble()
        : (basicSalary > 0 && workingDaysPerMonth > 0
        ? (basicSalary / workingDaysPerMonth).toDouble()
        : 0.0);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
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
          _salaryConfigBox(
            basicSalary: basicSalary,
            allowances: allowances,
            dailyRate: effectiveDailyRate,
            workingDaysPerMonth: workingDaysPerMonth,
            salarySource: salarySource,
          ),
          pw.SizedBox(height: 16),
          _workHoursSection(
            rawMinutes: workRawMinutes,
            lunchMinutes: workLunchMinutes,
            netMinutes: workNetMinutes,
            overtimeMinutes: workOvertimeMinutes,
            daysWithLogs: daysWithLogs,
            daysWithLunchApplied: daysWithLunchApplied,
          ),
          pw.SizedBox(height: 16),
          _attendanceSection(
            workingDays: workingDays,
            presentDays: presentDays,
            absentDays: absentDays,
            dailyRate: effectiveDailyRate,
            absenceDeduction: absenceDeduction,
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _earningsColumn(
                  basicSalary: basicSalary,
                  allowances: allowances,
                  overtimePay: overtimePay,
                  grossPay: finalGross,
                ),
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
          _summaryBox(
            grossPay: finalGross,
            totalDeductions: totalDeductions,
            netSalary: netSalary,
            govtTotal: govtTotal,
            absenceDeduction: absenceDeduction,
          ),
          pw.SizedBox(height: 16),
          _benefitsBox(
            thirteenthMonth: thirteenthMonth,
            silCredits: silCredits,
            totalBenefits: totalBenefits,
          ),
          pw.SizedBox(height: 16),
          _securityNotice(employee),
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
    );

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════
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
                      color: _PK.limeDark,
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
              style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 8)),
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

  // ═══════════════════════════════════════════════════════════════
  // 💰 SALARY CONFIG BOX
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _salaryConfigBox({
    required double basicSalary,
    required double allowances,
    required double dailyRate,
    required int workingDaysPerMonth,
    required String salarySource,
  }) {
    final isRoleBased = salarySource == 'role_matrix';

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _PK.orangeSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PK.orange, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SALARY CONFIGURATION',
                  style: pw.TextStyle(
                      color: _PK.orange,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold)),
              pw.Container(
                padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _PK.white,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(isRoleBased ? 'Role-based' : 'Custom',
                    style: pw.TextStyle(
                        color: _PK.orange,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                  child: _statMiniInline('Monthly Basic', _peso(basicSalary))),
              pw.Expanded(
                  child: _statMiniInline('Allowances', _peso(allowances))),
              pw.Expanded(
                  child: _statMiniInline('Daily Rate', _peso(dailyRate))),
              pw.Expanded(
                  child: _statMiniInline(
                      'Working Days', '$workingDaysPerMonth days')),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Daily Rate = Basic Salary ÷ $workingDaysPerMonth working days',
            style: pw.TextStyle(
                color: _PK.textGrayDark,
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
  }

  static pw.Widget _statMiniInline(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 7.5)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
                color: _PK.black,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // WORK HOURS SECTION
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _workHoursSection({
    required int rawMinutes,
    required int lunchMinutes,
    required int netMinutes,
    required int overtimeMinutes,
    required int daysWithLogs,
    required int daysWithLunchApplied,
  }) {
    final hasLunch = lunchMinutes > 0;
    final hasOT = overtimeMinutes > 0;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _PK.blueSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PK.blue, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('WORK HOURS BREAKDOWN',
                  style: pw.TextStyle(
                      color: _PK.blue,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold)),
              pw.Container(
                padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _PK.white,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(_fmtMinutes(netMinutes),
                    style: pw.TextStyle(
                        color: _PK.blue,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          _hourRow('Total Raw Hours', 'Clock in to clock out',
              _fmtMinutes(rawMinutes), _PK.black),
          if (hasLunch) ...[
            pw.SizedBox(height: 6),
            _hourRow(
                'Lunch Break Deducted',
                '$daysWithLunchApplied day(s) applied',
                '-${_fmtMinutes(lunchMinutes)}',
                _PK.red),
          ],
          if (hasOT) ...[
            pw.SizedBox(height: 6),
            _hourRow('Overtime', 'Beyond standard work hours',
                '+${_fmtMinutes(overtimeMinutes)}', _PK.limeDark),
          ],
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border:
              pw.Border(top: pw.BorderSide(color: _PK.blue, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Net Hours Worked',
                    style: pw.TextStyle(
                        color: _PK.black,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(_fmtMinutes(netMinutes),
                    style: pw.TextStyle(
                        color: _PK.limeDark,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          if (daysWithLogs > 0) ...[
            pw.SizedBox(height: 6),
            pw.Text('$daysWithLogs day(s) with attendance records',
                style: pw.TextStyle(
                    color: _PK.textGrayDark,
                    fontSize: 8,
                    fontStyle: pw.FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ATTENDANCE SECTION
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _attendanceSection({
    required int workingDays,
    required int presentDays,
    required int absentDays,
    required double dailyRate,
    required double absenceDeduction,
  }) {
    final isPerfect = absentDays == 0;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: isPerfect ? _PK.limeSoft : _PK.redSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(
            color: isPerfect ? _PK.limeDark : _PK.red, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ATTENDANCE BREAKDOWN',
                  style: pw.TextStyle(
                      color: isPerfect ? _PK.limeDark : _PK.red,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold)),
              pw.Container(
                padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _PK.white,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(isPerfect ? 'Perfect' : '$absentDays absence(s)',
                    style: pw.TextStyle(
                        color: isPerfect ? _PK.limeDark : _PK.red,
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Expanded(
                  child: _statMini('Working Days', '$workingDays', _PK.black)),
              pw.Expanded(
                  child:
                  _statMini('Present Days', '$presentDays', _PK.limeDark)),
              pw.Expanded(
                  child: _statMini('Absent Days', '$absentDays',
                      absentDays > 0 ? _PK.red : _PK.textGrayDark)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(
                      color: isPerfect ? _PK.limeDark : _PK.red, width: 0.5)),
            ),
            child: pw.Column(
              children: [
                _hourRow('Daily Rate', 'Basic salary ÷ working days',
                    _peso(dailyRate), _PK.black),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Absence Deduction',
                        style: pw.TextStyle(
                            color: _PK.black,
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold)),
                    pw.Text('-${_peso(absenceDeduction)}',
                        style: pw.TextStyle(
                            color: absentDays > 0 ? _PK.red : _PK.textGrayDark,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _statMini(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(
                color: color, fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 8)),
      ],
    );
  }

  static pw.Widget _hourRow(
      String label, String subtitle, String value, PdfColor color) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      color: _PK.black,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold)),
              if (subtitle.isNotEmpty)
                pw.Text(subtitle,
                    style: pw.TextStyle(
                        color: _PK.textGrayDark,
                        fontSize: 7,
                        fontStyle: pw.FontStyle.italic)),
            ],
          ),
        ),
        pw.Text(value,
            style: pw.TextStyle(
                color: color, fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EARNINGS COLUMN
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _earningsColumn({
    required double basicSalary,
    required double allowances,
    required double overtimePay,
    required double grossPay,
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
          child: pw.Text('EARNINGS',
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 10),
        _lineItem('Basic Salary', basicSalary),
        if (allowances > 0) ...[
          pw.SizedBox(height: 6),
          _lineItem('Allowances', allowances),
        ],
        if (overtimePay > 0) ...[
          pw.SizedBox(height: 6),
          _lineItem('Overtime Pay', overtimePay),
        ],
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
                top: pw.BorderSide(color: _PK.cardBorder, width: 0.75)),
          ),
          child: _lineItem('Total Gross', grossPay, bold: true),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DEDUCTIONS COLUMN
  // ═══════════════════════════════════════════════════════════════
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
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 10),
        if (absentDays > 0) ...[
          _lineItem('Absences ($absentDays day/s)', absenceDeduction),
          pw.SizedBox(height: 6),
        ],
        _lineItem('SSS (4.5%)', sss),
        pw.SizedBox(height: 6),
        _lineItem('PhilHealth (2.5%)', philhealth),
        pw.SizedBox(height: 6),
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
                  color: bold ? _PK.black : _PK.textGrayDark,
                  fontSize: 9,
                  fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ),
        pw.Text(_peso(value),
            style: pw.TextStyle(
                color: _PK.black,
                fontSize: 9,
                fontWeight:
                bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // NET SALARY BOX
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _netSalaryBox({
    required double netSalary,
    required String bankName,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _PK.netBoxBg,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PK.orange, width: 0.75),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('NET SALARY PAYABLE',
                  style: pw.TextStyle(
                      color: _PK.orange,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text('Amount transferred to $bankName',
                  style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 8)),
            ],
          ),
          pw.Text(_peso(netSalary),
              style: pw.TextStyle(
                  color: _PK.black,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SUMMARY BOX
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _summaryBox({
    required double grossPay,
    required double totalDeductions,
    required double netSalary,
    required double govtTotal,
    required double absenceDeduction,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _PK.orangeSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PK.orange, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PAY SUMMARY',
              style: pw.TextStyle(
                  color: _PK.orange,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _summaryRow('Gross Pay', _peso(grossPay), _PK.black),
          pw.SizedBox(height: 5),
          _summaryRow(
              'Total Deductions', '-${_peso(totalDeductions)}', _PK.red),
          pw.SizedBox(height: 5),
          if (absenceDeduction > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: _summaryRow(
                  'Absences', '-${_peso(absenceDeduction)}', _PK.textGrayDark),
            ),
          if (govtTotal > 0) ...[
            pw.SizedBox(height: 5),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: _summaryRow(
                  'Government (9%)', '-${_peso(govtTotal)}', _PK.textGrayDark),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border:
              pw.Border(top: pw.BorderSide(color: _PK.orange, width: 0.75)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Net Take-Home',
                    style: pw.TextStyle(
                        color: _PK.black,
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(_peso(netSalary),
                    style: pw.TextStyle(
                        color: _PK.limeDark,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryRow(String label, String value, PdfColor color) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label,
            style: pw.TextStyle(color: _PK.textGrayDark, fontSize: 9)),
        pw.Text(value,
            style: pw.TextStyle(
                color: color, fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BENEFITS BOX
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _benefitsBox({
    required double thirteenthMonth,
    required double silCredits,
    required double totalBenefits,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _PK.limeSoft,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _PK.limeDark, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('BENEFITS (ACCRUED)',
              style: pw.TextStyle(
                  color: _PK.limeDark,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          _lineItem('13th Month Pay', thirteenthMonth),
          pw.SizedBox(height: 5),
          _lineItem('SIL Credits (5 days)', silCredits),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(color: _PK.limeDark, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total Benefits',
                    style: pw.TextStyle(
                        color: _PK.black,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold)),
                pw.Text(_peso(totalBenefits),
                    style: pw.TextStyle(
                        color: _PK.limeDark,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Benefits are NOT deducted from net pay. These are additional savings received at 13th month payout or year-end.',
            style: pw.TextStyle(
                color: _PK.textGrayDark,
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECURITY NOTICE
  // ═══════════════════════════════════════════════════════════════
  static pw.Widget _securityNotice(Employee employee) {
    return pw.Container(
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
          pw.Text('PASSWORD-PROTECTED PDF',
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
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  static String _fmtMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
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