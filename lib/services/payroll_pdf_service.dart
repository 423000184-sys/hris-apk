// lib/services/payroll_pdf_service.dart
// ═══════════════════════════════════════════════════════════════════
// PAYROLL PDF SERVICE  v3.0
// Updates:
//   - DETERMINISTIC PASSWORD: derived from Employee ID only.
//     Same employee → same password → FOREVER.
//     No Firestore storage, no versions, no resets.
//   - Old PDFs still work with the same password after re-download.
//   - Auto-creates "RACOMA_Payslips" subfolder in Downloads.
//   - Auto-deletes old PDFs on new download (cleanup).
//   - No auto-open (removed Printing.sharePdf).
// ═══════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart' show BuildContext;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/employee.dart';

class PdfExportResult {
  final bool success;
  final String? filePath;
  final String? errorMessage;
  final String? userPassword;

  const PdfExportResult._({
    required this.success,
    this.filePath,
    this.errorMessage,
    this.userPassword,
  });

  factory PdfExportResult.ok({String? path, String? password}) =>
      PdfExportResult._(
        success: true,
        filePath: path,
        userPassword: password,
      );

  factory PdfExportResult.error(String msg) =>
      PdfExportResult._(success: false, errorMessage: msg);
}

class PayrollPdfService {
  PayrollPdfService._();

  static const String appSubfolder = 'RACOMA_Payslips';
  static const String _secretSalt = 'RACOMA-HRIS-2026-PDF-SALT';

  static const String _ownerPasswordFromEnv =
  String.fromEnvironment('PDF_OWNER_KEY', defaultValue: '');

  static String _resolveOwnerPassword() {
    if (_ownerPasswordFromEnv.length >= 16) return _ownerPasswordFromEnv;
    final rnd = math.Random.secure();
    return List<int>.generate(24, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔑 DETERMINISTIC PASSWORD
  // ═══════════════════════════════════════════════════════════════

  /// Password is deterministically derived from Employee ID.
  /// Same employee ID → same password → FOREVER.
  static String deriveUserPassword(String employeeId, [dynamic _]) {
    final id = employeeId.trim();
    if (id.isEmpty) return '';
    final material = '$_secretSalt::$id';
    final hash = sha256.convert(utf8.encode(material)).toString();
    final raw = hash.substring(0, 8).toUpperCase();
    return raw
        .replaceAll('0', 'X')
        .replaceAll('O', 'Y')
        .replaceAll('I', 'Z');
  }

  /// Alias — same as deriveUserPassword().
  static Future<String> getOrCreateUserPassword(String employeeId) async {
    return deriveUserPassword(employeeId);
  }

  static Future<String?> getCurrentPassword(String employeeId) async {
    final id = employeeId.trim();
    if (id.isEmpty) return null;
    return deriveUserPassword(id);
  }

  // ═══════════════════════════════════════════════════════════════
  // 📄 GENERATE PDF
  // ═══════════════════════════════════════════════════════════════
  static Future<PdfExportResult> generate(
      BuildContext context, {
        required Employee employee,
        required DateTime periodStart,
        required DateTime periodEnd,
        String companyName = 'TOPTRADERS IMPORT EXPORT CORP',
        String companyAddress =
        '10/F GE Antonio Bldg., J.Bocobo-TM Kalaw Sts Ermita, Manila',
        String companyContact = 'Tel. Nos. (02) 8525-5541',
        required double regularPay,
        required double basicPay,
        required double basicHours,
        required double absentAmount,
        required double absentHours,
        required double lateAmount,
        required double lateHours,
        required double undertimeAmount,
        required double undertimeHours,
        required double dayOffOtAmount,
        required double dayOffOtHours,
        required double overtimeAmount,
        required double overtimeHours,
        required double nightDiffAmount,
        required double nightDiffHours,
        required double holidayAmount,
        required double otherIncomeAllowance,
        required double totalAdjustmentsMade,
        required double sss,
        required double philhealth,
        required double pagibig,
        required double taxableIncome,
        required double taxWithheld,
        required double totalLoanDeductions,
        required double sickLeaveBalance,
        required double vacationLeaveBalance,
        required double riceAllowance,
        required String receivedThru,
        String? sessionNonce,
      }) async {
    final rawEmployeeId = employee.employeeId.trim();
    if (rawEmployeeId.isEmpty) {
      return PdfExportResult.error('Missing employee ID.');
    }

    final pdfBytes = await _buildPayslipPdf(
      employee: employee,
      periodStart: periodStart,
      periodEnd: periodEnd,
      companyName: companyName,
      companyAddress: companyAddress,
      companyContact: companyContact,
      regularPay: regularPay,
      basicPay: basicPay,
      basicHours: basicHours,
      absentAmount: absentAmount,
      absentHours: absentHours,
      lateAmount: lateAmount,
      lateHours: lateHours,
      undertimeAmount: undertimeAmount,
      undertimeHours: undertimeHours,
      dayOffOtAmount: dayOffOtAmount,
      dayOffOtHours: dayOffOtHours,
      overtimeAmount: overtimeAmount,
      overtimeHours: overtimeHours,
      nightDiffAmount: nightDiffAmount,
      nightDiffHours: nightDiffHours,
      holidayAmount: holidayAmount,
      otherIncomeAllowance: otherIncomeAllowance,
      totalAdjustmentsMade: totalAdjustmentsMade,
      sss: sss,
      philhealth: philhealth,
      pagibig: pagibig,
      taxableIncome: taxableIncome,
      taxWithheld: taxWithheld,
      totalLoanDeductions: totalLoanDeductions,
      sickLeaveBalance: sickLeaveBalance,
      vacationLeaveBalance: vacationLeaveBalance,
      riceAllowance: riceAllowance,
      receivedThru: receivedThru,
    );

    final userPassword = deriveUserPassword(rawEmployeeId);
    if (userPassword.isEmpty) {
      return PdfExportResult.error('Could not compute PDF password.');
    }

    final ownerPassword = _resolveOwnerPassword();

    Uint8List securedBytes;
    try {
      securedBytes = await _encryptPdf(
        pdfBytes,
        userPassword: userPassword,
        ownerPassword: ownerPassword,
      );
    } catch (e) {
      debugPrint('🚨 PDF encryption FAILED: $e');
      return PdfExportResult.error(
          'Unable to secure PDF. Please try again or contact support.');
    }

    final filename = _sanitizedFilename(employee, periodStart);

    if (kIsWeb) {
      return PdfExportResult.error(
          'Web build: use the mobile app to download the PDF.');
    }

    try {
      // Delete old PDFs first (so folder stays clean)
      await deleteOldPdfs();

      final targetDir = await _resolvePayslipDir();
      debugPrint('📁 Target dir: ${targetDir.path}');

      final file = File('${targetDir.path}/$filename');
      await file.writeAsBytes(securedBytes, flush: true);

      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      debugPrint('✅ Payslip saved: ${file.path} (exists=$exists, $size bytes)');

      if (!exists || size == 0) {
        return PdfExportResult.error(
            'File not saved. Please check storage permission.');
      }

      return PdfExportResult.ok(
        path: file.path,
        password: userPassword,
      );
    } catch (e) {
      debugPrint('🚨 File write failed: $e');
      return PdfExportResult.error('Unable to save file: $e');
    }
  }

  /// Delete all PDFs in the payslip folder.
  static Future<void> deleteOldPdfs() async {
    try {
      final dir = await _resolvePayslipDir();
      if (!await dir.exists()) return;
      final files = dir.listSync();
      for (final f in files) {
        if (f is File && f.path.toLowerCase().endsWith('.pdf')) {
          try {
            await f.delete();
            debugPrint('🗑️ Deleted old PDF: ${f.path}');
          } catch (e) {
            debugPrint('⚠️ Failed to delete ${f.path}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ deleteOldPdfs failed: $e');
    }
  }

  static Future<Directory> _resolvePayslipDir() async {
    if (Platform.isAndroid) {
      bool hasPermission = false;
      try {
        if (await Permission.manageExternalStorage.isGranted) {
          hasPermission = true;
        } else {
          final status = await Permission.manageExternalStorage.request();
          hasPermission = status.isGranted;
          debugPrint('🔐 manageExternalStorage: $status');
        }
      } catch (e) {
        debugPrint('⚠️ Permission request failed: $e');
      }

      if (hasPermission) {
        const candidates = <String>[
          '/storage/emulated/0/Download',
          '/sdcard/Download',
          '/storage/emulated/0/Downloads',
          '/sdcard/Downloads',
        ];
        for (final base in candidates) {
          try {
            final dir = Directory(base);
            if (await dir.exists()) {
              final targetDir = Directory('${dir.path}/$appSubfolder');
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
                debugPrint('📁 Created: ${targetDir.path}');
              }
              return targetDir;
            }
          } catch (e) {
            debugPrint('⚠️ Candidate $base failed: $e');
          }
        }
      }

      try {
        final external = await getExternalStorageDirectory();
        if (external != null) {
          final targetDir = Directory('${external.path}/$appSubfolder');
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
            debugPrint('📁 Created (app-specific): ${targetDir.path}');
          }
          return targetDir;
        }
      } catch (e) {
        debugPrint('⚠️ getExternalStorageDirectory failed: $e');
      }
    }

    Directory? base;
    try {
      final d = await getDownloadsDirectory();
      if (d != null) base = d;
    } catch (e) {
      debugPrint('⚠️ getDownloadsDirectory failed: $e');
    }

    base ??= await getApplicationDocumentsDirectory();

    final targetDir = Directory('${base.path}/$appSubfolder');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      debugPrint('📁 Created: ${targetDir.path}');
    }
    return targetDir;
  }

  static Future<Uint8List> _encryptPdf(
      Uint8List pdfBytes, {
        required String userPassword,
        required String ownerPassword,
      }) async {
    final finalUserPwd = userPassword.trim();
    final finalOwnerPwd = ownerPassword.trim();
    if (finalUserPwd.length < 6) {
      throw Exception('User password too weak');
    }
    if (finalOwnerPwd.length < 16) {
      throw Exception('Owner password too weak');
    }

    final safeOwnerPwd =
    finalOwnerPwd == finalUserPwd ? '${finalOwnerPwd}_OWNER' : finalOwnerPwd;
    final document = sf.PdfDocument(inputBytes: pdfBytes);
    document.security.userPassword = finalUserPwd;
    document.security.ownerPassword = safeOwnerPwd;
    document.security.permissions
        .addAll(<sf.PdfPermissionsFlags>[sf.PdfPermissionsFlags.print]);

    final List<int> securedBytes = await document.save();
    document.dispose();
    return Uint8List.fromList(securedBytes);
  }

  // ═══════════════════════════════════════════════════════════
  // BUILD PAYSLIP PDF (DOT-MATRIX STYLE)
  // ═══════════════════════════════════════════════════════════
  static Future<Uint8List> _buildPayslipPdf({
    required Employee employee,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String companyName,
    required String companyAddress,
    required String companyContact,
    required double regularPay,
    required double basicPay,
    required double basicHours,
    required double absentAmount,
    required double absentHours,
    required double lateAmount,
    required double lateHours,
    required double undertimeAmount,
    required double undertimeHours,
    required double dayOffOtAmount,
    required double dayOffOtHours,
    required double overtimeAmount,
    required double overtimeHours,
    required double nightDiffAmount,
    required double nightDiffHours,
    required double holidayAmount,
    required double otherIncomeAllowance,
    required double totalAdjustmentsMade,
    required double sss,
    required double philhealth,
    required double pagibig,
    required double taxableIncome,
    required double taxWithheld,
    required double totalLoanDeductions,
    required double sickLeaveBalance,
    required double vacationLeaveBalance,
    required double riceAllowance,
    required String receivedThru,
  }) async {
    final doc = pw.Document(
      title: 'Payslip',
      author: 'HRIS',
      creator: 'HRIS',
      subject: 'Confidential Payslip',
    );

    final periodLabel =
        'For the period of ${DateFormat('MM/dd/yyyy').format(periodStart)} to ${DateFormat('MM/dd/yyyy').format(periodEnd)}';

    final totalEarnings = basicPay +
        absentAmount +
        lateAmount +
        undertimeAmount +
        dayOffOtAmount +
        overtimeAmount +
        nightDiffAmount +
        holidayAmount +
        otherIncomeAllowance +
        totalAdjustmentsMade;
    final totalDeductions =
        sss + philhealth + pagibig + taxWithheld + totalLoanDeductions;
    final netPay = totalEarnings - totalDeductions;

    String peso(double v) {
      final s = v.toStringAsFixed(2);
      final parts = s.split('.');
      final whole = parts[0];
      final buf = StringBuffer();
      for (int i = 0; i < whole.length; i++) {
        final posFromEnd = whole.length - i;
        buf.write(whole[i]);
        if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
      }
      return '${buf.toString()}.${parts.length > 1 ? parts[1] : '00'}';
    }

    pw.TableRow _buildRow(String desc, String hrs, String amount,
        {bool isBold = false}) {
      final style = pw.TextStyle(
        fontSize: 10,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(desc, style: style),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child:
            pw.Text(hrs, style: style, textAlign: pw.TextAlign.right),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(amount,
                style: style, textAlign: pw.TextAlign.right),
          ),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(companyName,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text(companyAddress,
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 2),
                pw.Text(companyContact,
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 15),
                pw.Text('Payroll Slip',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            children: [
              pw.Expanded(
                flex: 1,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Employee Code:    ${employee.employeeId}',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        'Employee Name:   ${employee.fullName.toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Regular Pay:',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('P  ${peso(regularPay)}',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                children: [
                  pw.Container(),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text('Hrs.',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text('Amount',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
              _buildRow('Basic Pay', basicHours.toStringAsFixed(2),
                  peso(basicPay)),
              _buildRow('Absent', absentHours.toStringAsFixed(2),
                  peso(absentAmount)),
              _buildRow('Late', lateHours.toStringAsFixed(2),
                  peso(lateAmount)),
              _buildRow('Undertime', undertimeHours.toStringAsFixed(2),
                  peso(undertimeAmount)),
              _buildRow('Dayoff OT', dayOffOtHours.toStringAsFixed(2),
                  peso(dayOffOtAmount)),
              _buildRow('Overtime', overtimeHours.toStringAsFixed(2),
                  peso(overtimeAmount)),
              _buildRow('Night Diff.', nightDiffHours.toStringAsFixed(2),
                  peso(nightDiffAmount)),
              _buildRow('Holiday', '', peso(holidayAmount)),
              _buildRow('Other Income-Allowance', '',
                  peso(otherIncomeAllowance)),
              _buildRow('Total Adjustments Made', '',
                  peso(totalAdjustmentsMade)),
            ],
          ),
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total:',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(peso(totalEarnings),
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 15),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
            },
            children: [
              _buildRow('SSS', '', peso(sss)),
              _buildRow('Phil. Health', '', peso(philhealth)),
              _buildRow('Pag-Ibig', '', peso(pagibig)),
              _buildRow('Taxable Income & Tax Withhe',
                  taxableIncome.toStringAsFixed(2), peso(taxWithheld)),
              _buildRow('Total Loan Deductions', '',
                  peso(totalLoanDeductions)),
            ],
          ),
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total:',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(peso(totalDeductions),
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('NET PAY:',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(peso(netPay),
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('LEAVE',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Sick Leave',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(sickLeaveBalance.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Vacation Leave',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(vacationLeaveBalance.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 40),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OTHER INCOME',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Rice Allowance',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(riceAllowance.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(riceAllowance.toStringAsFixed(2),
                            style: const pw.TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 40),
          pw.Text('Received thru: $receivedThru',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),
          pw.Text('Received by: ___________________________',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );

    return doc.save();
  }

  static String _sanitizedFilename(Employee employee, DateTime month) {
    final m = DateFormat('yyyy-MM').format(month);
    final idPart = employee.employeeId
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final safeId = idPart.isEmpty ? 'UNKNOWN' : idPart;
    return 'Payslip_${safeId}_$m.pdf';
  }
}