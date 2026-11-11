// lib/screens/admin_create_leave_request_page.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_theme.dart';
import '../widgets/bootstrap_grid.dart';

class AdminCreateLeaveRequestPage extends StatefulWidget {
  final List<Map<String, dynamic>> employees;
  final VoidCallback? onBack;
  final VoidCallback? onSuccess;

  const AdminCreateLeaveRequestPage({
    super.key,
    this.employees = const [],
    this.onBack,
    this.onSuccess,
  });

  @override
  State<AdminCreateLeaveRequestPage> createState() =>
  _AdminCreateLeaveRequestPageState();
}

class _AdminCreateLeaveRequestPageState
extends State<AdminCreateLeaveRequestPage> {

  AdminColors get tc => AdminTheme.getColors(context);
  String get _actorEmail => FirebaseAuth.instance.currentUser?.email ?? 'admin';

  // ── Controllers ──
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _relieverController = TextEditingController();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();
  final TextEditingController _daysController = TextEditingController(text: "0");
  final TextEditingController _hoursController = TextEditingController(text: "0");
  final TextEditingController _returnDateController = TextEditingController();
  final TextEditingController _returnTimeController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  // ── Values ──
  DateTime? _dateFrom;
  DateTime? _dateTo;
  DateTime? _returnDate;
  TimeOfDay? _returnTime;
  double _totalDays = 0;
  double _totalHours = 0;
  String? _selectedEmployeeId;
  bool _isSubmitting = false;

  Map<String, dynamic> _employeeBalances = {};

  final List<Map<String, String>> _leaveTypes = const [
    {"code": "SL", "desc": "Sick Leave"},
    {"code": "VL", "desc": "Vacation Leave"},
    {"code": "EL", "desc": "Emergency"},
    {"code": "ML / PL", "desc": "Maternity/Paternity"},
  ];
  String _selectedLeaveType = "SL";

  String _empName(Map<String, dynamic> employee) {
    final dynamic name = employee['name'];
    if (name != null && name.toString().trim().isNotEmpty) return name.toString().trim();
    final String first = (employee['firstName'] ?? '').toString().trim();
    final String last = (employee['lastName'] ?? '').toString().trim();
    return '$first $last'.trim().isEmpty ? 'Unknown' : '$first $last'.trim();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _relieverController.dispose();
    _fromDateController.dispose();
    _toDateController.dispose();
    _daysController.dispose();
    _hoursController.dispose();
    _returnDateController.dispose();
    _returnTimeController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // AUTO-CALCULATE DAYS & HOURS
  // ══════════════════════════════════════════════════════════════
  void _calculateDaysAndHours() {
    if (_dateFrom == null || _dateTo == null) return;

    // Normalize dates to midnight (12:00 AM) to avoid time discrepancies
    final start = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
    final end = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day);

    if (end.isBefore(start)) {
      setState(() {
        _totalDays = 0;
        _totalHours = 0;
        _daysController.text = "0";
        _hoursController.text = "0";
      });
      return;
    }

    int days = end.difference(start).inDays + 1; // +1 for inclusive dates
    double hours = days * 8.0; // Standard 8 hours per day

    setState(() {
      _totalDays = days.toDouble();
      _totalHours = hours;
      _daysController.text = days.toString();
      _hoursController.text = hours.toStringAsFixed(0);
    });
  }

  // ══════════════════════════════════════════════════════════════
  // HR OVERRIDE PASSWORD
  // ══════════════════════════════════════════════════════════════
  String _sha256Hash(String input) => sha256.convert(utf8.encode(input)).toString();

  Future<bool> _verifyHrOverridePassword() async {
    final pwdCtrl = TextEditingController();
    bool obscure = true;

    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: tc.card,
          title: Row(children: [
            Icon(Icons.lock_outline_rounded, color: tc.orange, size: 22),
            const SizedBox(width: 10),
            Text('HR Override Required', style: TextStyle(color: tc.text)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter password to save this leave request.',
                   style: TextStyle(color: tc.textMuted, fontSize: 13)),
                   const SizedBox(height: 16),
                   TextField(
                     controller: pwdCtrl,
                     obscureText: obscure,
                     autofocus: true,
                     style: TextStyle(color: tc.text),
                     decoration: _inputDecoration(
                       'Override Password',
                       suffixIcon: IconButton(
                         icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: tc.muted),
                         onPressed: () => setDlgState(() => obscure = !obscure),
                       ),
                     ),
                   ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: tc.muted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tc.orange, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return false;
    if (pwdCtrl.text.trim().isEmpty) return false;

    try {
      final cfg = await FirebaseFirestore.instance.collection('system_config').doc('attendance_override').get();
      final storedHash = (cfg.data()?['passwordHash'] ?? '').toString().toLowerCase();
      if (!cfg.exists || storedHash.isEmpty) {
        _showError('Override password not configured.');
        return false;
      }
      return _sha256Hash(pwdCtrl.text.trim()).toLowerCase() == storedHash;
    } catch (e) {
      _showError('Verification failed.');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // EMPLOYEE PICKER & BALANCE FETCH
  // ══════════════════════════════════════════════════════════════
  Future<void> _showEmployeePicker() async {
    final searchCtrl = TextEditingController();
    String query = '';

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final filtered = widget.employees.where((e) {
            final name = _empName(e).toLowerCase();
            final id = (e['employeeId'] ?? e['employee_id'] ?? e['id'] ?? '').toString().toLowerCase();
            return name.contains(query) || id.contains(query);
          }).toList();

          return AlertDialog(
            backgroundColor: tc.card,
            title: Text('Select Employee', style: TextStyle(color: tc.text)),
            content: SizedBox(
              width: 400, height: 450,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: _inputDecoration("Search by name or ID...", suffixIcon: Icon(Icons.search, color: tc.muted)),
                    onChanged: (v) => setDlg(() => query = v.toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final emp = filtered[i];
                        return ListTile(
                          title: Text(_empName(emp), style: TextStyle(color: tc.text)),
                          subtitle: Text((emp['department'] ?? emp['dept'] ?? 'N/A').toString(), style: TextStyle(color: tc.muted)),
                          onTap: () => Navigator.pop(ctx, emp),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedEmployeeId = (selected['id'] ?? selected['employeeId'] ?? '').toString();
        _nameController.text = _empName(selected);
        _positionController.text = (selected['position'] ?? selected['role'] ?? selected['jobTitle'] ?? 'N/A').toString();
        _departmentController.text = (selected['department'] ?? selected['dept'] ?? selected['section'] ?? 'N/A').toString();

        _employeeBalances = Map<String, dynamic>.from(selected['leaveBalances'] ?? {});
      });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // UI BUILD
  // ══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: tc.background,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: BsContainer(
            maxWidth: 1400,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackLink(),
                const SizedBox(height: 8),
                _buildPageHeading(),
                const SizedBox(height: 24),
                _buildFormCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackLink() {
    return InkWell(
      onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back, size: 14, color: tc.orange),
          const SizedBox(width: 6),
          Text("Back to Activity & Leave", style: TextStyle(color: tc.orange, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPageHeading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Create Leave Request", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: tc.text)),
        const SizedBox(height: 2),
        Text("Application for Leave of Absence", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: tc.orange)),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tc.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tc.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInstructionBox(),
          const SizedBox(height: 24),
          _sectionLabel("EMPLOYEE INFORMATION"),
          const SizedBox(height: 16),
          _buildEmployeeInformation(),
          const SizedBox(height: 32),
          _sectionLabel("LEAVE DETAILS"),
          const SizedBox(height: 16),
          _buildLeaveDetails(),
          const SizedBox(height: 20),
          _buildReturnToWork(),
          const SizedBox(height: 32),
          _sectionLabel("LEAVE APPLIED FOR"),
          const SizedBox(height: 16),
          _buildLeaveTypes(),
          const SizedBox(height: 20),
          _buildReasonField(),
          const SizedBox(height: 28),
          _buildApprovalWorkflow(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildInstructionBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: tc.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: tc.orange, width: 4)),
      ),
      child: Text(
        "INSTRUCTION: This form should be filled out BEFORE an employee goes on leave. In case of emergency or illness, this form must be filled out IMMEDIATELY upon return for work.",
        style: TextStyle(fontSize: 12, height: 1.5, color: tc.text, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tc.border, width: 1))),
      child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tc.orange, letterSpacing: 0.5)),
    );
  }

  Widget _responsiveGrid({required List<Widget> children}) {
    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth < 768) {
        return Column(children: children.map((child) => Padding(padding: const EdgeInsets.only(bottom: 16), child: child)).toList());
      }
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: children.map((child) => SizedBox(width: (c.maxWidth - 20) / 2, child: child)).toList(),
      );
    });
  }

  Widget _buildEmployeeInformation() {
    return _responsiveGrid(
      children: [
        _labeledField(
          "Name of Employee",
          TextField(
            controller: _nameController,
            readOnly: true,
            onTap: _showEmployeePicker,
            style: TextStyle(fontSize: 16, color: tc.text, fontWeight: FontWeight.bold),
            decoration: _inputDecoration("Click to select employee", suffixIcon: Icon(Icons.search, color: tc.orange)),
          ),
        ),
        _labeledField(
          "Designation / Position",
          TextField(
            controller: _positionController,
            readOnly: true,
            style: TextStyle(fontSize: 16, color: tc.textMuted),
            decoration: _inputDecoration("Auto-filled"),
          ),
        ),
        _labeledField(
          "Section / Department",
          TextField(
            controller: _departmentController,
            readOnly: true,
            style: TextStyle(fontSize: 16, color: tc.textMuted),
            decoration: _inputDecoration("Auto-filled"),
          ),
        ),
        _labeledField(
          "Name of Reliever (Optional)",
          TextField(controller: _relieverController, decoration: _inputDecoration("Who will cover your duties?")),
        ),
      ],
    );
  }

  // 👇 BAGONG DATE PICKER UI (Hindi na TextField, Clickable Box na)
  Widget _buildDatePickerBox({
    required String hint,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14), // Kaparehas ng TextField height
        decoration: BoxDecoration(
          color: tc.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tc.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value.isEmpty ? hint : value,
              style: TextStyle(
                color: value.isEmpty ? tc.muted : tc.text,
                fontSize: 14,
              ),
            ),
            Icon(Icons.calendar_today, color: tc.muted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tc.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: _responsiveGrid(
        children: [
          _labeledField(
            "Inclusive Dates",
            Row(
              children: [
                Expanded(
                  child: _buildDatePickerBox(
                    hint: "From",
                    value: _fromDateController.text,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dateFrom ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100)
                      );
                      if (d != null) {
                        setState(() {
                          _dateFrom = d;
                          _fromDateController.text = DateFormat('MM/dd/yyyy').format(d);
                        });
                        _calculateDaysAndHours(); // Auto-compute
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildDatePickerBox(
                    hint: "To",
                    value: _toDateController.text,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dateTo ?? _dateFrom ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100)
                      );
                      if (d != null) {
                        setState(() {
                          _dateTo = d;
                          _toDateController.text = DateFormat('MM/dd/yyyy').format(d);
                        });
                        _calculateDaysAndHours(); // Auto-compute
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          _labeledField(
            "Total Time Out",
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    "Days",
                    _daysController,
                    readOnly: true, // Read-only
                  )
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    "Hours",
                    _hoursController,
                    readOnly: true, // Read-only
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnToWork() {
    return _responsiveGrid(
      children: [
        _labeledField(
          "Return to Work Date",
          _buildDatePickerBox(
            hint: "mm/dd/yyyy",
            value: _returnDateController.text,
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _returnDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100)
              );
              if (d != null) setState(() { _returnDate = d; _returnDateController.text = DateFormat('MM/dd/yyyy').format(d); });
            },
          ),
        ),
        _labeledField(
          "Return to Work Time",
          InkWell(
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _returnTime ?? TimeOfDay.now());
              if (t != null) setState(() { _returnTime = t; _returnTimeController.text = t.format(context); });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: tc.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: tc.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _returnTimeController.text.isEmpty ? "--:--" : _returnTimeController.text,
                    style: TextStyle(color: _returnTimeController.text.isEmpty ? tc.muted : tc.text, fontSize: 14),
                  ),
                  Icon(Icons.access_time, color: tc.muted, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveTypes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _leaveTypes.map((type) {
            final selected = _selectedLeaveType == type["code"];
            return InkWell(
              onTap: () => setState(() => _selectedLeaveType = type["code"]!),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 130,
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
                decoration: BoxDecoration(
                  color: selected ? tc.orange.withValues(alpha: 0.12) : tc.card,
                  border: Border.all(color: selected ? tc.orange : tc.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(type["code"]!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tc.text)),
                    const SizedBox(height: 2),
                    Text(type["desc"]!, style: TextStyle(fontSize: 12, color: tc.muted)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_selectedEmployeeId != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tc.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 16, color: tc.green),
                const SizedBox(width: 8),
                Text(
                  "Available Balance: ${_employeeBalances[_selectedLeaveType] ?? '0'} Day(s)",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tc.green),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReasonField() {
    return _labeledField(
      "Reason",
      TextField(controller: _reasonController, maxLines: 4, decoration: _inputDecoration("Please provide specific details regarding your leave request...")),
    );
  }

  Widget _buildApprovalWorkflow() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Approval Workflow (Automatic Routing)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tc.text)),
          const SizedBox(height: 16),
          Divider(color: tc.border),
          _buildApprovalItem("Section Head", "Pending Recommendation"),
          _buildApprovalItem("Department Head", "Pending Approval"),
        ],
      ),
    );
  }

  Widget _buildApprovalItem(String title, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: tc.blue.withValues(alpha: 0.15), child: Icon(Icons.person_outline, size: 16, color: tc.blue)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tc.text)),
              Text(status, style: TextStyle(fontSize: 12, color: tc.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: widget.onBack ?? () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          child: const Text("Cancel"),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitLeaveRequest,
          style: ElevatedButton.styleFrom(
            backgroundColor: tc.orange,
            foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          child: _isSubmitting
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text("Submit Request", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // SUBMIT WITH DEDUCTION & OVERRIDE
  // ══════════════════════════════════════════════════════════════
  Future<void> _submitLeaveRequest() async {
    if (_selectedEmployeeId == null || _nameController.text.isEmpty) {
      return _showError("Please select an employee from the list.");
    }
    if (_dateFrom == null || _dateTo == null) {
      return _showError("Please select the Inclusive Dates.");
    }

    final available = double.tryParse(_employeeBalances[_selectedLeaveType]?.toString() ?? '0') ?? 0;
    if (_totalDays > available) {
      return _showError("Insufficient leave balance. Available: $available, Requested: $_totalDays");
    }

    // HR OVERRIDE DITO
    final authorized = await _verifyHrOverridePassword();
    if (!authorized) return;

    setState(() => _isSubmitting = true);
    try {
      final empDocRef = FirebaseFirestore.instance.collection('employees').doc(_selectedEmployeeId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final empSnapshot = await transaction.get(empDocRef);

        if (empSnapshot.exists) {
          Map<String, dynamic> currentBalances = Map<String, dynamic>.from(empSnapshot.data()!['leaveBalances'] ?? {});
          double currentBal = double.tryParse(currentBalances[_selectedLeaveType]?.toString() ?? '0') ?? 0;

          if (currentBal < _totalDays) {
            throw Exception("Insufficient balance in Firestore.");
          }

          currentBalances[_selectedLeaveType] = currentBal - _totalDays;
          transaction.update(empDocRef, {'leaveBalances': currentBalances});
        }

        final newLeaveRef = FirebaseFirestore.instance.collection('leave_applications').doc();
        transaction.set(newLeaveRef, {
          'employeeId': _selectedEmployeeId,
          'employeeName': _nameController.text.trim(),
          'position': _positionController.text.trim(),
          'department': _departmentController.text.trim(),
          'leaveType': _selectedLeaveType,
          'startDate': Timestamp.fromDate(_dateFrom!),
          'endDate': Timestamp.fromDate(_dateTo!),
          'days': _totalDays.toInt(),
          'hours': _totalHours,
          'reason': _reasonController.text.trim(),
          'status': 'pending',
          'source': 'admin',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _actorEmail,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Leave saved & Balance deducted!"), backgroundColor: Colors.green));
      widget.onSuccess?.call();
      widget.onBack?.call();

    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Widget _labeledField(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: tc.text)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: tc.muted)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(fontSize: 16, color: readOnly ? tc.textMuted : tc.text),
          decoration: _inputDecoration("0"),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: tc.muted, fontSize: 14),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: tc.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: tc.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: tc.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: tc.orange, width: 1.2)),
    );
  }
}
