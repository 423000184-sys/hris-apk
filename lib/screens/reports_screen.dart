// lib/screens/reports_screen.dart
//
<<<<<<< HEAD
// SIMPLIFIED PAYSLIP VIEW:
//   - Orange gradient header (Back + Print icon)
//   - Summary card: company name, "Paid" badge, month label
//   - Employee name & ID (displayed below the card)
//   - "Download as PDF / Print" button
//   - All detailed breakdown (earnings, deductions, net salary) is
//     only shown in the generated PDF (payroll_pdf_service.dart)
=======
// Payslip Details screen — matches the orange-gradient header design.
// Shows company info card with Paid badge, and a Download as PDF / Print button.
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
<<<<<<< HEAD
import '../theme/app_theme.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_pdf_service.dart';
import '../models/employee.dart';

// Mockup-specific light palette
class _Mock {
  static const Color cardBg = Color(0xFFF8F8F8);
  static const Color cardBorder = Color(0xFF27272A);
  static const Color orange = Color(0xFFFF8A00);
  static const Color lime = Color(0xFFC4FF0A);
  static const Color textGrayDark = Color(0xFF52525B);
  static const Color paidBg = Color(0x1AC4FF0A);
  static const Color paidBorder = Color(0x33C4FF0A);
}

=======
import '../services/database_service.dart';
import '../services/security_service.dart';
import '../services/payroll_pdf_service.dart';
import '../models/attendance.dart';
import '../models/employee.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Design tokens
// ══════════════════════════════════════════════════════════════════════════════
class _C {
  static const bg         = Color(0xFF0A0A0A);
  static const card       = Color(0xFF1A1A1A);
  static const orangeTop  = Color(0xFFFF8C00);
  static const orangeBot  = Color(0xFFFF6600);
  static const white      = Color(0xFFFFFFFF);
  static const white70    = Color(0xB3FFFFFF);
  static const white40    = Color(0x66FFFFFF);
  static const white15    = Color(0x26FFFFFF);
  static const white08    = Color(0x14FFFFFF);
  static const paid       = Color(0xFF22C55E);
  static const paidBg     = Color(0xFF16231C);
}

// ══════════════════════════════════════════════════════════════════════════════
// ReportsScreen
// ══════════════════════════════════════════════════════════════════════════════
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
class ReportsScreen extends StatefulWidget {
  final Employee? initialEmployee;
  const ReportsScreen({super.key, this.initialEmployee});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Employee? _employee;
<<<<<<< HEAD
  bool _loading = true;
  bool _exporting = false;
  double _hourlyRate = 75.0;

  // Payroll data
  double _basicSalary = 0;
  double _housingAllowance = 0;
  double _transportAllowance = 0;
  double _specialAllowance = 0;
  double _providentFund = 0;
  double _professionalTax = 0;
  String _bankName = '—';
  String _accountNumber = '—';
  String _department = '—';
  String _designation = '—';

  static const _standardMonthlyHours = 160.0;
=======
  bool      _loading    = true;
  bool      _exporting  = false;
  double    _hourlyRate = 75.0;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1

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

<<<<<<< HEAD
      double rate = 75.0;
      Map<String, dynamic>? data;
=======
      // Try to read hourlyRate from Firestore
      double rate = 75.0;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
      if (emp != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('employees')
              .where('employeeId', isEqualTo: emp.employeeId)
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
<<<<<<< HEAD
            data = snap.docs.first.data();
=======
            final data = snap.docs.first.data();
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            final r = data['hourlyRate'] ?? data['hourly_rate'] ?? data['rate'];
            if (r != null) rate = (r as num).toDouble();
          }
        } catch (_) {}
      }

<<<<<<< HEAD
      final basic = (data?['basicSalary'] as num?)?.toDouble() ??
          rate * _standardMonthlyHours;
      final housing = (data?['housingAllowance'] as num?)?.toDouble() ??
          basic * 0.40;
      final transport = (data?['transportAllowance'] as num?)?.toDouble() ??
          basic * 0.15;
      final special = (data?['specialAllowance'] as num?)?.toDouble() ??
          basic * 0.075;
      final pf = (data?['providentFund'] as num?)?.toDouble() ?? basic * 0.0225;
      final tax = (data?['professionalTax'] as num?)?.toDouble() ?? basic * 0.0025;

      if (mounted) {
        setState(() {
          _employee = emp;
          _hourlyRate = rate;
          _basicSalary = basic;
          _housingAllowance = housing;
          _transportAllowance = transport;
          _specialAllowance = special;
          _providentFund = pf;
          _professionalTax = tax;
          _bankName = (data?['bankName'] as String?) ?? '—';
          _accountNumber = (data?['accountNumber'] as String?) ?? '—';
          _department = (data?['department'] as String?) ?? '—';
          _designation = (data?['designation'] as String?) ?? emp?.position ?? '—';
          _loading = false;
=======
      if (mounted) {
        setState(() {
          _employee    = emp;
          _hourlyRate  = rate;
          _loading     = false;
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        });
      }
    } catch (e) {
      debugPrint('ReportsScreen._loadData: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

<<<<<<< HEAD
  double get _totalEarnings =>
      _basicSalary + _housingAllowance + _transportAllowance + _specialAllowance;

  double get _totalDeductions => _providentFund + _professionalTax;

  double get _netSalary => _totalEarnings - _totalDeductions;

=======
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Future<void> _generatePdf() async {
    final emp = _employee ?? widget.initialEmployee;
    if (emp == null) {
      _showSnack('No employee session. Please log in again.', error: true);
      return;
    }
    setState(() => _exporting = true);
    try {
<<<<<<< HEAD
      final savedPath = await PayrollPdfService.generate(
        context,
        employee: emp,
        month: DateTime.now(),
        basicSalary: _basicSalary,
        housingAllowance: _housingAllowance,
        transportAllowance: _transportAllowance,
        specialAllowance: _specialAllowance,
        providentFund: _providentFund,
        professionalTax: _professionalTax,
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
          'exported_at': FieldValue.serverTimestamp(),
          'platform': kIsWeb ? 'Web' : 'Mobile',
        });
      } catch (_) {}

      if (mounted) {
        _showSnack(savedPath != null
            ? 'Na-save ang payslip sa device ✓'
            : 'PDF payslip generated ✓');
      }
=======
      await PayrollPdfService.generate(
        context,
        employee   : emp,
        hourlyRate : _hourlyRate,
        month      : DateTime.now(),
      );

      // Audit log
      try {
        await FirebaseFirestore.instance.collection('pdf_exports').add({
          'employee_id'  : emp.employeeId,
          'employee_name': emp.fullName,
          'report_type'  : 'Monthly Payroll PDF',
          'hourly_rate'  : _hourlyRate,
          'month'        : DateFormat('yyyy-MM').format(DateTime.now()),
          'exported_at'  : FieldValue.serverTimestamp(),
          'platform'     : kIsWeb ? 'Web' : 'Mobile',
        });
      } catch (_) {}

      if (mounted) _showSnack('PDF payroll report generated ✓');
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
    } catch (e) {
      if (mounted) _showSnack('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFFF4D6D) : const Color(0xFF00E5A0),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

<<<<<<< HEAD
  @override
  Widget build(BuildContext context) {
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    final empName = _employee?.fullName ?? widget.initialEmployee?.fullName ?? '—';
    final empId = _employee?.employeeId ?? widget.initialEmployee?.employeeId ?? '—';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(
            child: CircularProgressIndicator(color: _Mock.orange, strokeWidth: 2.5))
            : Column(
          children: [
            _buildHeader(thisMonth),
=======
  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final thisMonth = DateFormat('MMMM yyyy').format(DateTime.now());
    final empName   = _employee?.fullName ?? widget.initialEmployee?.fullName ?? '';

    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: _loading
            ? _buildLoader()
            : Column(
          children: [
            // ── Orange gradient header ──────────────────────────────
            _buildHeader(thisMonth),

            // ── Scrollable body ─────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  children: [
<<<<<<< HEAD
                    // ✅ Correct: passing 3 parameters
                    _buildPayslipCard(thisMonth, empName, empId),
                    const SizedBox(height: 12),
                    _buildEmployeeInfo(empName, empId),
                    const SizedBox(height: 20),
=======
                    // Company info card
                    _buildCompanyCard(thisMonth, empName),
                    const SizedBox(height: 20),
                    // Download button
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                    _buildDownloadButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
<<<<<<< HEAD
    );
  }

  // ─── HEADER ──────────────────────────────────────────────────────────────
=======
      // Bottom nav bar (matches screenshot)
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  // ── Loader ─────────────────────────────────────────────────────────────────
  Widget _buildLoader() => const Center(
    child: CircularProgressIndicator(color: _C.orangeTop, strokeWidth: 2.5),
  );

  // ── Orange gradient header ─────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildHeader(String thisMonth) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
<<<<<<< HEAD
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
=======
        gradient: LinearGradient(
          colors: [_C.orangeTop, _C.orangeBot],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(0)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + Print row
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: const Row(
                  children: [
<<<<<<< HEAD
                    Icon(Icons.chevron_left_rounded, color: Colors.white, size: 22),
                    Text('Back',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
=======
                    Icon(Icons.chevron_left_rounded,
                        color: _C.white, size: 22),
                    Text('Back',
                        style: TextStyle(
                          color: _C.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        )),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                  ],
                ),
              ),
              const Spacer(),
<<<<<<< HEAD
              GestureDetector(
                onTap: _exporting ? null : _generatePdf,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Mock.cardBorder),
                  ),
                  child: _exporting
                      ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                        color: _Mock.orange, strokeWidth: 2),
                  )
                      : const Icon(Icons.print_rounded,
                      color: _Mock.orange, size: 20),
=======
              // Print icon button
              GestureDetector(
                onTap: _exporting ? null : _generatePdf,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _C.white15,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.white15),
                  ),
                  child: _exporting
                      ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        color: _C.white, strokeWidth: 2),
                  )
                      : const Icon(Icons.print_rounded,
                      color: _C.white, size: 20),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
<<<<<<< HEAD
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
=======
          // Title
          const Text(
            'Payslip Details',
            style: TextStyle(
              color: _C.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Salary slip for $thisMonth',
            style: const TextStyle(
              color: _C.white70,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ],
      ),
    );
  }

<<<<<<< HEAD
  // ─── PAYSLIP CARD (Simplified) ──────────────────────────────────────────
  // ✅ Tama na ang 3 parameters
  Widget _buildPayslipCard(String thisMonth, String empName, String empId) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _Mock.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Mock.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            // Left: Company Info
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
                  const Text('Smart HR Information System',
                      style: TextStyle(color: Colors.black, fontSize: 12)),
                  const SizedBox(height: 8),
                  const Text('Jumbo HQ, Manila, Philippines',
                      style: TextStyle(color: _Mock.textGrayDark, fontSize: 10)),
                ],
              ),
            ),
            // Right: "Paid" badge + month
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _Mock.paidBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _Mock.paidBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: _Mock.lime, size: 14),
                      const SizedBox(width: 6),
                      const Text('Paid',
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
                  style: const TextStyle(
                      color: Colors.black,
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

  // ─── EMPLOYEE INFO ────────────────────────────────────────────────────────
  Widget _buildEmployeeInfo(String empName, String empId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: _Mock.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Mock.cardBorder.withOpacity(0.5)),
      ),
      child: Row(
        children: [
=======
  // ── Company info card ──────────────────────────────────────────────────────
  Widget _buildCompanyCard(String thisMonth, String empName) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.white08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: company info
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
<<<<<<< HEAD
                const Text('Employee',
                    style: TextStyle(
                        color: _Mock.textGrayDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(empName,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Employee ID',
                    style: TextStyle(
                        color: _Mock.textGrayDark,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(empId,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
=======
                // Company name
                Text(
                  'R.A.C.O.M.A',
                  style: const TextStyle(
                    color: _C.orangeTop,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Smart HR Information\nSystem',
                  style: TextStyle(
                    color: _C.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Jumbo HQ, Dubai, UAE',
                  style: TextStyle(
                    color: _C.white40,
                    fontSize: 12,
                  ),
                ),
                if (empName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    empName,
                    style: const TextStyle(
                      color: _C.white40,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: Paid badge + payslip label
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Paid badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _C.paidBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _C.paid.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _C.paid, width: 1.5),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: _C.paid, size: 10),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'Paid',
                      style: TextStyle(
                        color: _C.paid,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Payslip label
              Text(
                'Payslip for\n$thisMonth',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _C.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ],
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
          ),
        ],
      ),
    );
  }

<<<<<<< HEAD
  // ─── DOWNLOAD BUTTON ──────────────────────────────────────────────────────
=======
  // ── Download button ────────────────────────────────────────────────────────
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
  Widget _buildDownloadButton() {
    return GestureDetector(
      onTap: _exporting ? null : _generatePdf,
      child: Container(
        width: double.infinity,
<<<<<<< HEAD
        height: 48,
        decoration: BoxDecoration(
          gradient: AppColors.gradientOrange,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
=======
        height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_C.orangeTop, _C.orangeBot],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
        ),
        child: Center(
          child: _exporting
              ? const SizedBox(
<<<<<<< HEAD
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5))
              : const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded, color: Colors.white, size: 20),
=======
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                color: _C.white, strokeWidth: 2.5),
          )
              : const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded,
                  color: _C.white, size: 20),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              SizedBox(width: 10),
              Text(
                'Download as PDF / Print',
                style: TextStyle(
<<<<<<< HEAD
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
=======
                  color: _C.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
              ),
            ],
          ),
        ),
      ),
    );
  }
<<<<<<< HEAD
=======

  // ── Bottom navigation bar ──────────────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: _C.card,
        border: Border(top: BorderSide(color: _C.white08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.grid_view_rounded, true),
          _navItem(Icons.access_time_rounded, false),
          _navItem(Icons.calendar_month_rounded, false),
          _navItem(Icons.person_outline_rounded, false),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, bool active) {
    return Icon(
      icon,
      color: active ? _C.orangeTop : _C.white40,
      size: 26,
    );
  }
>>>>>>> 65fa6bcdba6f48188055af1712f5fd32886c0ab1
}