// lib/screens/admin_payroll_management_page.dart
// ═══════════════════════════════════════════════════════════════════
// SECURED ADMIN PAYROLL MANAGEMENT PAGE  v2.2
// Hardened: admin guard, audit trail, rate limit, filename
//           sanitization, URL validation, error sanitization,
//           kDebugMode-gated logs, double-submit guards.
//           v2.2: Aligned sa bagong PayrollBreakdown schema.
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'admin_theme.dart';
import '../utils/file_download.dart';
import '../widgets/bootstrap_grid.dart';
import '../services/payroll_calculator.dart';
import '../services/employee_notification_service.dart';
import '../services/attendance_hours_service.dart';
import '../services/admin_auth_service.dart';

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
  EmployeeHoursSummary _hours = EmployeeHoursSummary.empty;
  bool _loading = true;
  bool _printing = false;
  bool _downloading = false;

  // ─── SECURITY GUARDS ────────────────────────────────────────
  final _SecurityGuard _guard = _SecurityGuard();
  bool _isAdminVerified = false;
  DateTime? _lastNotifyAt;

  static const Duration _notifyCooldown = Duration(minutes: 5);

  // ══════════════════════════════════════════════════════════════
  // 🔒 SECURITY HELPERS
  // ══════════════════════════════════════════════════════════════

  static String _sanitize(dynamic raw, {int maxLen = 200}) {
    if (raw == null) return '';
    var s = raw.toString();
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    s = s.replaceAll(
        RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '');
    if (s.length > maxLen) s = '${s.substring(0, maxLen)}…';
    return s.trim();
  }

  static String _safeFilenameSegment(dynamic raw, {int maxLen = 40}) {
    if (raw == null) return 'unknown';
    final s = raw.toString();
    var safe = s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    safe = safe.replaceAll(RegExp(r'^\.+'), '');
    if (safe.isEmpty) safe = 'unknown';
    if (safe.length > maxLen) safe = safe.substring(0, maxLen);
    return safe;
  }

  static bool _isSafePhotoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') return false;
      if (!uri.hasAuthority) return false;
      final host = uri.host.toLowerCase();
      if (host.contains('firebasestorage.googleapis.com')) return true;
      if (host.contains('storage.googleapis.com')) return true;
      if (host.endsWith('.googleusercontent.com')) return true;
      if (host.endsWith('.cloudinary.com')) return true;
      if (host.endsWith('.amazonaws.com')) return true;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _safeError(Object e) {
    if (kDebugMode) return e.toString();
    return 'Something went wrong. Please try again.';
  }

  Future<User?> _currentAdmin() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return null;
      await u.getIdToken(true);
      return u;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensureAdmin() async {
    return FirebaseAuth.instance.currentUser != null;
  }

  Future<void> _audit({
    required String action,
    required String targetId,
    required String targetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('security_events').add({
        'type': 'admin_action',
        'action': action,
        'targetId': targetId,
        'targetType': targetType,
        'actorUid': uid,
        'metadata': metadata ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ payroll-mgmt audit failed: $e');
    }
  }

  void _toast(String msg, {bool error = false, bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sanitize(msg, maxLen: 200)),
        backgroundColor: error ? tc.red : (success ? tc.green : tc.orange),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SAFE GETTERS
  // ══════════════════════════════════════════════════════════════
  String get _name {
    final raw = widget.employeeData['name'];
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return _sanitize(raw, maxLen: 80);
    }
    final first = _sanitize(widget.employeeData['firstName'] ?? '', maxLen: 40);
    final last = _sanitize(widget.employeeData['lastName'] ?? '', maxLen: 40);
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Unknown Employee' : full;
  }

  String get _employeeId {
    final raw = widget.employeeData['id'] ??
        widget.employeeData['employeeId'] ??
        '—';
    return _sanitize(raw, maxLen: 64);
  }

  String get _employeeIdForFilename =>
      _safeFilenameSegment(widget.employeeData['id'] ??
          widget.employeeData['employeeId'] ??
          'unknown');

  String get _department {
    final raw = widget.employeeData['department'] ?? 'Unassigned';
    return _sanitize(raw, maxLen: 60);
  }

  String? get _photoUrl {
    final url = widget.employeeData['photoUrl'];
    if (url is! String || url.isEmpty) return null;
    if (!_isSafePhotoUrl(url)) {
      if (kDebugMode) debugPrint('🚫 [PayrollMgmt] Unsafe photo URL blocked');
      return null;
    }
    return url;
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

  double get _autoOvertimePay {
    if (_hours.totalOvertimeMinutes <= 0) return 0;
    if (_b.dailyRate <= 0) return 0;
    final hourlyRate = _b.dailyRate / 8;
    return (_hours.totalOvertimeMinutes / 60.0) * hourlyRate;
  }

  // ✅ FIX: `allowances` → `otherIncomeAllowance`
  double get _autoGrossPay {
    return _b.basicSalary + _b.otherIncomeAllowance + _autoOvertimePay;
  }

  double get _autoNetPay {
    return _autoGrossPay - _b.totalDeductions;
  }

  // ══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _verifyAndLoad();
  }

  Future<void> _verifyAndLoad() async {
    final ok = await _ensureAdmin();
    if (!mounted) return;
    if (!ok) {
      _isAdminVerified = false;
      setState(() => _loading = false);
      _toast('Walang permission. Admin-only page.', error: true);
      return;
    }
    _isAdminVerified = true;
    await _load();
  }

  Future<void> _load() async {
    if (!_isAdminVerified) return;
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        PayrollCalculator.compute(
          employee: widget.employeeData,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        ),
        _loadHoursSummary(),
      ]);

      if (!mounted) return;
      setState(() {
        _b = results[0] as PayrollBreakdown;
        _hours = results[1] as EmployeeHoursSummary;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [PayrollMgmt] load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(_safeError(e), error: true);
    }
  }

  Future<EmployeeHoursSummary> _loadHoursSummary() async {
    try {
      final map = await AttendanceHoursService.instance.fetchHoursMap(
        periodStart: _periodStart,
        periodEnd: _periodEnd,
      );

      for (final k in [
        'id',
        'employeeId',
        'employee_id',
        'nfcTagId',
        'authUid'
      ]) {
        final key = widget.employeeData[k]?.toString().trim();
        if (key != null && key.isNotEmpty && map.containsKey(key)) {
          return map[key]!;
        }
      }

      return EmployeeHoursSummary.empty;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ [PayrollMgmt] Hours load error: $e');
      return EmployeeHoursSummary.empty;
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 📄 PDF GENERATION
  // ══════════════════════════════════════════════════════════════
  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document(
      title: 'Payslip',
      author: 'HRIS System',
      creator: 'HRIS',
      subject: 'Employee Payslip',
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PAYSLIP',
                      style: pw.TextStyle(
                          fontSize: 26, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('Employee Disbursement Statement',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Period: $_periodLabel',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                      'Generated: ${DateFormat('MMM d, yyyy • HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(height: 2, color: PdfColors.orange800),
          pw.SizedBox(height: 16),

          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('EMPLOYEE',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(_name,
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('EMPLOYEE ID',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(_employeeId,
                          style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DEPARTMENT',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(_department,
                          style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          _pdfSection('WORK HOURS', [
            _pdfRow('Total Raw Hours', _hours.rawDisplay),
            if (_hours.totalLunchDeductedMinutes > 0)
              _pdfRow('Lunch Deducted', '-${_hours.lunchDisplay}'),
            _pdfRow('Net Hours Worked', _hours.netDisplay, bold: true),
            if (_hours.totalOvertimeMinutes > 0)
              _pdfRow('Overtime', '+${_hours.overtimeDisplay}'),
          ]),
          pw.SizedBox(height: 14),

          // ✅ FIX: `allowances` → `otherIncomeAllowance`
          _pdfSection('EARNINGS', [
            _pdfRow('Basic Salary', PayrollCalculator.peso(_b.basicSalary)),
            _pdfRow('Allowances',
                PayrollCalculator.peso(_b.otherIncomeAllowance)),
            if (_autoOvertimePay > 0)
              _pdfRow('Overtime Pay (auto)',
                  PayrollCalculator.peso(_autoOvertimePay)),
            _pdfRow('Total Gross', PayrollCalculator.peso(_autoGrossPay),
                bold: true),
          ]),
          pw.SizedBox(height: 14),

          // ✅ FIX: `absenceDeduction` → `absentAmount`
          _pdfSection('DEDUCTIONS', [
            if (_b.absentDays > 0)
              _pdfRow('Absences (${_b.absentDays} day/s)',
                  '-${PayrollCalculator.peso(_b.absentAmount)}'),
            _pdfRow('SSS', '-${PayrollCalculator.peso(_b.sss)}'),
            _pdfRow('PhilHealth', '-${PayrollCalculator.peso(_b.philhealth)}'),
            _pdfRow('Pag-IBIG', '-${PayrollCalculator.peso(_b.pagibig)}'),
            _pdfRow('Total Deductions',
                '-${PayrollCalculator.peso(_b.totalDeductions)}',
                bold: true),
          ]),
          pw.SizedBox(height: 24),

          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.orange800, width: 1.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('NET PAY',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(PayrollCalculator.peso(_autoNetPay),
                    style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange800)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 6),
          pw.Text(
            'This is a system-generated payslip. No signature required.',
            style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfSection(String title, List<pw.Widget> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.orange800,
                letterSpacing: 0.5)),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(children: rows),
        ),
      ],
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 10.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 🖨️ PRINT
  // ══════════════════════════════════════════════════════════════
  Future<void> _handlePrint() async {
    if (_printing) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('Walang permission. Admin-only action.', error: true);
      return;
    }

    if (!_guard.tryAcquire('print_payslip')) {
      _toast('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    setState(() => _printing = true);

    try {
      final bytes = await _generatePdf();
      final safeId = _employeeIdForFilename;
      final okPrint = await Printing.layoutPdf(
        onLayout: (PdfPageFormat f) async => bytes,
        name: 'payslip_$safeId.pdf',
      );

      unawaited(_audit(
        action: 'print_payslip',
        targetId: _employeeId,
        targetType: 'payslip',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
          'success': okPrint,
        },
      ));

      if (!mounted) return;

      if (okPrint) {
        _toast('Payslip sent to printer.', success: true);
        await _notifyEmployeePayroll();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [PayrollMgmt] Print error: $e');
      if (!mounted) return;
      _toast(_safeError(e), error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 💾 DOWNLOAD
  // ══════════════════════════════════════════════════════════════
  Future<void> _handleDownload() async {
    if (_downloading) return;

    final ok = await _ensureAdmin();
    if (!ok) {
      _toast('Walang permission. Admin-only action.', error: true);
      return;
    }

    if (!_guard.tryAcquire('download_payslip')) {
      _toast('Masyadong mabilis. Please wait a moment.', error: true);
      return;
    }

    setState(() => _downloading = true);

    try {
      final bytes = await _generatePdf();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeId = _employeeIdForFilename;
      final fileName = 'payslip_${safeId}_$ts.pdf';

      final savedPath = await downloadBytesFile(
        filename: fileName,
        bytes: bytes,
        mimeType: 'application/pdf',
      );

      unawaited(_audit(
        action: 'download_payslip',
        targetId: _employeeId,
        targetType: 'payslip',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
          'filename': fileName,
          'success': savedPath != null,
        },
      ));

      if (!mounted) return;

      if (savedPath != null) {
        _toast('Payslip saved → $fileName', success: true);
        await _notifyEmployeePayroll();
      } else {
        _toast('Download cancelled.', error: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [PayrollMgmt] Download error: $e');
      if (!mounted) return;
      _toast(_safeError(e), error: true);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _notifyEmployeePayroll() async {
    final now = DateTime.now();
    if (_lastNotifyAt != null &&
        now.difference(_lastNotifyAt!) < _notifyCooldown) {
      if (kDebugMode) {
        debugPrint('🚫 [PayrollMgmt] Notify cooldown active — skipping');
      }
      return;
    }

    try {
      await EmployeeNotificationService.instance.sendPayrollAlert(
        employeeId: _employeeId,
        employeeName: _name,
        month: _periodLabel,
        netPay: _autoNetPay,
      );
      _lastNotifyAt = now;

      unawaited(_audit(
        action: 'notify_payslip',
        targetId: _employeeId,
        targetType: 'employee_notification',
        metadata: {
          'employee_name': _name,
          'period': _periodLabel,
        },
      ));

      if (kDebugMode) {
        debugPrint('✅ [PayrollMgmt] Employee notified');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [PayrollMgmt] Employee notification failed: $e');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!_isAdminVerified && !_loading) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _handleBack();
        },
        child: Scaffold(
          backgroundColor: tc.background,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 48, color: tc.red),
                  const SizedBox(height: 12),
                  Text('Admin access required',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: tc.text)),
                  const SizedBox(height: 6),
                  Text(
                    'Kailangan ng admin role para makita ang payslip.',
                    style: TextStyle(fontSize: 13, color: tc.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: _handleBack,
                    icon: Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

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
      child: InkWell(
        onTap: _handleBack,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 4, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, color: tc.orange, size: 18),
              const SizedBox(width: 6),
              Text(
                'Back to Payroll',
                style: TextStyle(
                  color: tc.orange,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
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
                        Text('ID: $_employeeId',
                            style: TextStyle(
                                fontSize: 12,
                                color: tc.muted,
                                fontWeight: FontWeight.w600)),
                        Text('•', style: TextStyle(color: tc.muted)),
                        Text(_department,
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
                          child: Text(_periodLabel,
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
                onPressed: _printing ? null : _handlePrint,
                icon: _printing
                    ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: tc.text),
                )
                    : const Icon(Icons.print_rounded, size: 16),
                label: Text(_printing ? 'Printing...' : 'Print',
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
                onPressed: _downloading ? null : _handleDownload,
                icon: _downloading
                    ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.download_rounded, size: 16),
                label: Text(
                    _downloading ? 'Downloading...' : 'Download Payslip',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: tc.orange,
                  disabledBackgroundColor:
                  tc.orange.withValues(alpha: 0.5),
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
          _buildMetricCard('NET PAY', PayrollCalculator.peso(_autoNetPay),
              'Total take-home for this period', false),
          _buildMetricCard('GROSS PAY', PayrollCalculator.peso(_autoGrossPay),
              'Basic + Allowances + OT (auto)', false),
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
    final hasOT = _autoOvertimePay > 0;

    // ✅ FIX: `allowances` → `otherIncomeAllowance`
    return _panel(
      title: 'Earnings Breakdown',
      badge: PayrollCalculator.peso(_autoGrossPay),
      badgeColor: tc.orange.withValues(alpha: 0.15),
      badgeTextColor: tc.orangeText,
      children: [
        _item('Basic Salary', 'Regular monthly pay',
            PayrollCalculator.peso(_b.basicSalary), false),
        _item('Allowances', 'Housing / Transport / Special',
            PayrollCalculator.peso(_b.otherIncomeAllowance), false),
        _item(
          'Overtime Pay',
          hasOT
              ? 'Auto-detected from work hours (${_hours.overtimeDisplay})'
              : 'No overtime this period',
          hasOT
              ? PayrollCalculator.peso(_autoOvertimePay)
              : PayrollCalculator.peso(0),
          false,
        ),
        Divider(color: tc.border, height: 20),
        _item('Total Gross', 'Sum of earnings',
            PayrollCalculator.peso(_autoGrossPay), false,
            bold: true),
        if (hasOT) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tc.pillGreenBg,
              border:
              Border(left: BorderSide(color: tc.pillGreenTx, width: 4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Auto-computed overtime: ${_hours.overtimeDisplay} beyond standard 8h/day.',
              style: TextStyle(
                  fontSize: 11, color: tc.pillGreenTx, height: 1.4),
            ),
          ),
        ],
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
            'Benefits are not deducted from net pay. These are additional savings received at the 13th month payout or year-end.',
            style:
            TextStyle(fontSize: 11, color: tc.pillGreenTx, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _absencesCard() {
    final hasHours = _hours.totalNetMinutes > 0;

    // ✅ FIX: `absenceDeduction` → `absentAmount`
    return _panel(
      title: 'Attendance & Hours',
      badge: _b.absentDays > 0
          ? '-${PayrollCalculator.peso(_b.absentAmount)}'
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

        if (hasHours) ...[
          Divider(color: tc.border, height: 20),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: tc.orange),
              const SizedBox(width: 6),
              Text('HOURS SUMMARY (Auto)',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: tc.textMuted,
                      letterSpacing: 0.5)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tc.pillBlueBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_hours.netDisplay,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: tc.pillBlueTx)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _item('Total Raw Hours', 'Before lunch deduction',
              _hours.rawDisplay, false),
          if (_hours.totalLunchDeductedMinutes > 0)
            _item(
              'Lunch Deducted',
              '${_hours.daysWithLunchApplied} day(s) applied',
              '-${_hours.lunchDisplay}',
              true,
            ),
          _item('Net Hours Worked', 'Raw − lunch deduction',
              _hours.netDisplay, false,
              bold: true),
          if (_hours.totalOvertimeMinutes > 0)
            _item('Overtime', 'Beyond standard 8h/day',
                '+${_hours.overtimeDisplay}', false),
        ],

        Divider(color: tc.border, height: 20),
        _item('Daily Rate', 'Basic ÷ working days',
            PayrollCalculator.peso(_b.dailyRate), false),
        _item('Absence Deduction',
            '${_b.absentDays} day/s × daily rate',
            '-${PayrollCalculator.peso(_b.absentAmount)}',
            _b.absentDays > 0,
            bold: true),

        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _b.absentDays > 0 ? tc.pillErrBg : tc.pillGreenBg,
            border: Border(
                left: BorderSide(
                    color:
                    _b.absentDays > 0 ? tc.pillErrTx : tc.pillGreenTx,
                    width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _b.absentDays > 0
                ? '${_b.absentDays} absent day(s) auto-deducted from salary based on attendance logs.'
                : 'No absences this period. Full salary will be received.',
            style: TextStyle(
                fontSize: 11,
                color: _b.absentDays > 0 ? tc.pillErrTx : tc.pillGreenTx,
                height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _govtCard() {
    // ✅ FIX: `withholdingTax` → `taxWithheld`
    final total =
        _b.sss + _b.philhealth + _b.pagibig + _b.taxWithheld;
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
        _item('Withholding Tax', 'Calculated based on net taxable income',
            '-${PayrollCalculator.peso(_b.taxWithheld)}', true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tc.pillWarnBg,
            border: Border(left: BorderSide(color: tc.pillWarnTx, width: 4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Total statutory deductions amount to 9% of the basic salary (${PayrollCalculator.peso(_b.basicSalary)}) for this pay period.',
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
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
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
    final clean = _sanitize(name, maxLen: 80);
    final parts = clean.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'HR';
  }
}

// ═══════════════════════════════════════════════════════════════════
// 🆕 RATE LIMITER
// ═══════════════════════════════════════════════════════════════════
class _SecurityGuard {
  final Map<String, DateTime> _lastCall = {};
  static const Duration _minInterval = Duration(seconds: 3);

  bool tryAcquire(String key) {
    final now = DateTime.now();
    final last = _lastCall[key];
    if (last != null && now.difference(last) < _minInterval) {
      return false;
    }
    _lastCall[key] = now;
    return true;
  }
}